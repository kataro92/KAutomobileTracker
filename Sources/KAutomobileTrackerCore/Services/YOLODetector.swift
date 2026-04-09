import CoreGraphics
import CoreML
import CoreVideo
import Foundation
import Vision

/// One YOLO / CoreML object detection (normalized Vision bounding box).
public struct YOLODetection: Sendable {
    public var label: String
    public var confidence: Float
    public var boundingBox: CGRect
    public var modelKind: YOLODetector.ModelKind

    public init(label: String, confidence: Float, boundingBox: CGRect, modelKind: YOLODetector.ModelKind) {
        self.label = label
        self.confidence = confidence
        self.boundingBox = boundingBox
        self.modelKind = modelKind
    }
}

/// Runs Ultralytics YOLO26 CoreML exports on macOS (Vision + raw multi-array fallback).
public final class YOLODetector: @unchecked Sendable {
    public enum ModelKind: String, Sendable {
        case general
        case signs
    }

    private let vnModel: VNCoreMLModel
    public let classNames: [String]
    public let kind: ModelKind

    public init(modelURL: URL, kind: ModelKind, classNames: [String]) throws {
        let cfg = MLModelConfiguration()
        cfg.computeUnits = .all
        let ml = try MLModel(contentsOf: modelURL, configuration: cfg)
        self.vnModel = try VNCoreMLModel(for: ml)
        self.kind = kind
        self.classNames = Self.resolvedClassNames(
            model: ml,
            modelURL: modelURL,
            kind: kind,
            passed: classNames
        )
    }

    public static func loadIfPresent(modelURL: URL?, kind: ModelKind, classNames: [String]) -> YOLODetector? {
        guard let modelURL, FileManager.default.fileExists(atPath: modelURL.path) else { return nil }
        do {
            return try YOLODetector(modelURL: modelURL, kind: kind, classNames: classNames)
        } catch {
            AppLog.analysis.error("YOLO load failed: \(error.localizedDescription)")
            return nil
        }
    }

    /// `nmsIoUThreshold`: higher = keep more overlapping boxes (typical dashcams: adjacent vehicles).
    /// `useSoftNMS`: linear decay of overlapping scores instead of hard suppression (crowded lanes).
    /// `lowConfidenceFloor`: when lower than `confidenceThreshold`, parses extra weak anchors and returns them (ByteTrack-style second pass upstream). Same Vision run uses the lower floor for raw-tensor filtering only.
    public func detect(
        pixelBuffer: CVPixelBuffer,
        confidenceThreshold: Float,
        maxDetections: Int = 100,
        nmsIoUThreshold: CGFloat = 0.58,
        useSoftNMS: Bool = true,
        lowConfidenceFloor: Float? = nil
    ) throws -> [YOLODetection] {
        let parseMinimum = min(confidenceThreshold, lowConfidenceFloor ?? confidenceThreshold)
        let request = VNCoreMLRequest(model: vnModel)
        // Letterbox-style preserves aspect ratio like Ultralytics training; scaleFill can squash vehicles and hurt recall.
        request.imageCropAndScaleOption = .scaleFit

        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up, options: [:])
        try handler.perform([request])

        var boxes: [CGRect] = []
        var scores: [Float] = []
        var labels: [String] = []

        for o in request.results ?? [] {
            if let ro = o as? VNRecognizedObjectObservation {
                let best = ro.labels.first
                let lab = best?.identifier ?? "object"
                let conf = Float(best?.confidence ?? 0)
                if conf >= parseMinimum {
                    boxes.append(ro.boundingBox)
                    scores.append(conf)
                    labels.append(lab)
                }
            } else if let fv = o as? VNCoreMLFeatureValueObservation,
                      let m = fv.featureValue.multiArrayValue
            {
                let parsed = Self.parseRawDetections(
                    from: m,
                    classNames: classNames,
                    confidenceThreshold: parseMinimum,
                    modelKind: kind
                )
                for p in parsed {
                    boxes.append(p.0)
                    scores.append(p.1)
                    labels.append(p.2)
                }
            }
        }

        let detections: [YOLODetection]
        if useSoftNMS {
            let paired = Self.softNMSPairs(boxes: boxes, scores: scores, iouThreshold: nmsIoUThreshold, limit: maxDetections)
            detections = paired.compactMap { idx, sc in
                guard sc >= parseMinimum else { return nil }
                return YOLODetection(label: labels[idx], confidence: sc, boundingBox: boxes[idx], modelKind: kind)
            }
        } else {
            let keep = Self.nmsIndices(boxes: boxes, scores: scores, iouThreshold: nmsIoUThreshold, limit: maxDetections)
            detections = keep
                .filter { scores[$0] >= parseMinimum }
                .map { i in
                    YOLODetection(label: labels[i], confidence: scores[i], boundingBox: boxes[i], modelKind: kind)
                }
        }
        return detections
    }

    // MARK: - Class names

    private static func resolvedClassNames(
        model: MLModel,
        modelURL: URL,
        kind: ModelKind,
        passed: [String]
    ) -> [String] {
        if !passed.isEmpty { return passed }
        if let labsAny = model.modelDescription.classLabels, !labsAny.isEmpty {
            let labs = labsAny.compactMap { $0 as? String }
            if !labs.isEmpty { return labs }
        }
        let sibling = modelURL.deletingPathExtension().appendingPathExtension("txt")
        if let text = try? String(contentsOf: sibling, encoding: .utf8) {
            let lines = text.split(separator: "\n").map { String($0).trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            if !lines.isEmpty { return lines }
        }
        // Unknown class count — generic placeholders (fine-tuned models should ship labels.txt).
        return (0 ..< 128).map { "sign_\($0)" }
    }

    // MARK: - Raw YOLO (NMS-free CoreML) parsing

    private static func parseRawDetections(
        from array: MLMultiArray,
        classNames: [String],
        confidenceThreshold: Float,
        modelKind _: ModelKind
    ) -> [(CGRect, Float, String)] {
        let shape = array.shape.map { Int(truncating: $0) }
        guard shape.count == 3, shape[0] == 1 else { return [] }

        let d1 = shape[1]
        let d2 = shape[2]
        let featuresFirst: Bool
        let numFeatures: Int
        let numAnchors: Int
        // Ultralytics exports: [1, 4+C, N] or [1, N, 4+C] with N large (e.g. 8400, 25200). Do not assume N ≤ 320.
        if (5 ... 512).contains(d1), d2 > d1 {
            featuresFirst = true
            numFeatures = d1
            numAnchors = d2
        } else if (5 ... 512).contains(d2), d1 > d2 {
            featuresFirst = false
            numAnchors = d1
            numFeatures = d2
        } else {
            return []
        }

        let numClasses = numFeatures - 4
        guard numClasses > 0 else { return [] }

        func val(_ feature: Int, _ anchor: Int) -> Float {
            if featuresFirst {
                return floatAt(array, [0, feature, anchor])
            }
            return floatAt(array, [0, anchor, feature])
        }

        let input: CGFloat = 640
        var out: [(CGRect, Float, String)] = []
        out.reserveCapacity(min(numAnchors, 256))

        for j in 0 ..< numAnchors {
            var bestCls = 0
            var bestScore: Float = -1
            for c in 0 ..< numClasses {
                let logit = val(4 + c, j)
                let p: Float
                if logit >= 0, logit <= 1 {
                    p = logit
                } else {
                    p = sigmoid(logit)
                }
                if p > bestScore {
                    bestScore = p
                    bestCls = c
                }
            }
            guard bestScore >= confidenceThreshold else { continue }

            var cx = val(0, j)
            var cy = val(1, j)
            var ww = val(2, j)
            var hh = val(3, j)

            let big = max(cx, cy, ww, hh)
            if big > 1.6 {
                let f = Float(input)
                cx /= f
                cy /= f
                ww /= f
                hh /= f
            }

            let label = bestCls < classNames.count ? classNames[bestCls] : "cls\(bestCls)"
            let rect = visionRectFromXYWH(cx: CGFloat(cx), cy: CGFloat(cy), w: CGFloat(ww), h: CGFloat(hh))
            out.append((rect, bestScore, label))
        }
        return out
    }

    /// Center x,y and size in normalized **top-left** image space → Vision bottom-left rect.
    private static func visionRectFromXYWH(cx: CGFloat, cy: CGFloat, w: CGFloat, h: CGFloat) -> CGRect {
        let halfW = w / 2
        let halfH = h / 2
        let left = max(0, min(1 - w, cx - halfW))
        let top = max(0, min(1 - h, cy - halfH))
        let yVision = 1 - top - h
        return CGRect(x: left, y: max(0, yVision), width: max(0.001, w), height: max(0.001, h))
    }

    private static func floatAt(_ a: MLMultiArray, _ indices: [Int]) -> Float {
        let idx = indices.map { NSNumber(value: $0) }
        switch a.dataType {
        case .float32:
            return a[idx].floatValue
        case .double:
            return Float(a[idx].doubleValue)
        default:
            return Float(a[idx].doubleValue)
        }
    }

    private static func sigmoid(_ x: Float) -> Float {
        1 / (1 + exp(-x))
    }

    private static func nmsIndices(
        boxes: [CGRect],
        scores: [Float],
        iouThreshold: CGFloat,
        limit: Int
    ) -> [Int] {
        let order = scores.enumerated().sorted { $0.element > $1.element }.map(\.offset)
        var selected: [Int] = []
        var suppressed = Set<Int>()
        for idx in order {
            if suppressed.contains(idx) { continue }
            selected.append(idx)
            if selected.count >= limit { break }
            for j in order where j != idx && !suppressed.contains(j) {
                if iou(boxes[idx], boxes[j]) >= iouThreshold {
                    suppressed.insert(j)
                }
            }
        }
        return selected
    }

    /// Linear Soft-NMS (Bodla et al.): iteratively take the top box and decay scores of high-IoU neighbors.
    private static func softNMSPairs(
        boxes: [CGRect],
        scores: [Float],
        iouThreshold: CGFloat,
        limit: Int
    ) -> [(Int, Float)] {
        guard !boxes.isEmpty, scores.count == boxes.count else { return [] }
        var scores = scores
        var remaining = Set(boxes.indices)
        var out: [(Int, Float)] = []
        out.reserveCapacity(min(limit, boxes.count))

        while !remaining.isEmpty, out.count < limit {
            var bestIdx: Int?
            var bestScore: Float = -.greatestFiniteMagnitude
            for i in remaining {
                if scores[i] > bestScore {
                    bestScore = scores[i]
                    bestIdx = i
                }
            }
            guard let m = bestIdx else { break }
            remaining.remove(m)
            out.append((m, scores[m]))
            for j in remaining {
                let u = iou(boxes[m], boxes[j])
                if u > iouThreshold {
                    scores[j] *= Float(1.0 - u)
                }
            }
        }
        return out
    }

    private static func iou(_ a: CGRect, _ b: CGRect) -> CGFloat {
        let inter = a.intersection(b)
        if inter.isNull || inter.isEmpty { return 0 }
        let interArea = inter.width * inter.height
        let union = a.width * a.height + b.width * b.height - interArea
        guard union > 0 else { return 0 }
        return interArea / union
    }
}
