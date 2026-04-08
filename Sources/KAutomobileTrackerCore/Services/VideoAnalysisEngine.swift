import AVFoundation
import Combine
import CoreImage
import CoreVideo
import Foundation
import Metal
import Vision

@MainActor
public final class VideoAnalysisEngine: ObservableObject, VideoAnalyzing {
    @Published public private(set) var isRunning = false
    @Published public private(set) var lastMotion: Double = 0
    @Published public private(set) var lastLane: LaneEstimate = .unknown
    @Published public private(set) var recentSigns: [SignObservation] = []
    @Published public private(set) var processedFrames: Int = 0
    @Published public private(set) var status: String = ""

    private let ciContext: CIContext
    private let motionDimension = CGSize(width: 96, height: 54)
    private let visionMaxWidth: CGFloat = 720
    private var minInterval: TimeInterval
    private var lastProcessTime: CFAbsoluteTime = 0
    private var previousLuma: [UInt8]?
    private var reader: AVAssetReader?
    private var output: AVAssetReaderTrackOutput?
    private var signThrottle: CFAbsoluteTime = 0
    private let signMinInterval: TimeInterval = 0.55

    private var cancelFlag = false
    private var analysisTask: Task<Void, Never>?

    public init(minSampleInterval: TimeInterval? = nil) {
        if let device = MTLCreateSystemDefaultDevice() {
            ciContext = CIContext(mtlDevice: device, options: [.cacheIntermediates: false])
        } else {
            ciContext = CIContext(options: [.useSoftwareRenderer: false])
        }
        minInterval = minSampleInterval ?? AppUserSettings.analysisMinInterval
    }

    public func resetSessionCounters() {
        lastProcessTime = 0
        signThrottle = 0
        previousLuma = nil
        processedFrames = 0
        recentSigns = []
        lastMotion = 0
        lastLane = .unknown
        status = ""
    }

    public func cancel() {
        cancelFlag = true
        analysisTask?.cancel()
        reader?.cancelReading()
        AppLog.analysis.notice("Analysis cancel requested")
    }

    public func runAnalysis(
        fileURL: URL,
        simulated: Bool,
        onProgress: @escaping @Sendable (Int) -> Void,
        onComplete: @escaping @MainActor (Double, [LaneEstimate: Int], [SignObservation], Int) -> Void
    ) {
        cancelFlag = false
        analysisTask?.cancel()
        minInterval = AppUserSettings.analysisMinInterval
        resetSessionCounters()
        isRunning = true
        status = simulated ? "Simulated trip…" : "Analyzing video (throttled for efficiency)…"

        analysisTask = Task { @MainActor [weak self] in
            guard let self else { return }
            if simulated {
                await self.runSimulated(onProgress: onProgress, onComplete: onComplete)
            } else {
                await self.runRealVideo(url: fileURL, onProgress: onProgress, onComplete: onComplete)
            }
        }
    }

    private func runSimulated(
        onProgress: @escaping @Sendable (Int) -> Void,
        onComplete: @escaping @MainActor (Double, [LaneEstimate: Int], [SignObservation], Int) -> Void
    ) async {
        let frames = 48
        var lanes: [LaneEstimate: Int] = [:]
        var motion: Double = 0
        var signs: [SignObservation] = []
        let start = Date()

        for i in 0..<frames {
            if Task.isCancelled || cancelFlag { break }
            do {
                try await Task.sleep(nanoseconds: 40_000_000)
            } catch {
                break
            }
            let lane: LaneEstimate = [LaneEstimate.left, .center, .right][i % 3]
            lanes[lane, default: 0] += 1
            motion += 0.15 + Double(i % 5) * 0.02
            if i % 12 == 0 {
                signs.append(
                    SignObservation(
                        text: i % 24 == 0 ? "STOP" : "SPEED LIMIT 45",
                        timestamp: start.addingTimeInterval(Double(i) * 0.25),
                        confidence: 0.82
                    )
                )
            }
            processedFrames = i + 1
            onProgress(i + 1)
        }

        let n = processedFrames
        let avgMotion = n > 0 ? motion / Double(n) : 0
        isRunning = false
        status = (Task.isCancelled || cancelFlag) ? "Cancelled." : "Simulation complete."
        if Task.isCancelled || cancelFlag {
            AppLog.analysis.debug("Simulation cancelled after \(n) samples")
        }
        onComplete(avgMotion, lanes, signs, n)
    }

    private func runRealVideo(
        url: URL,
        onProgress: @escaping @Sendable (Int) -> Void,
        onComplete: @escaping @MainActor (Double, [LaneEstimate: Int], [SignObservation], Int) -> Void
    ) async {
        let asset = AVURLAsset(url: url)
        let track: AVAssetTrack
        do {
            let tracks = try await asset.loadTracks(withMediaType: .video)
            guard let t = tracks.first else {
                isRunning = false
                status = KAutoError.videoNoTrack.errorDescription ?? "No video track."
                AppLog.analysis.error("No video track for \(url.lastPathComponent)")
                onComplete(0, [:], [], 0)
                return
            }
            track = t
        } catch {
            isRunning = false
            status = KAutoError.videoReaderFailed(reason: error.localizedDescription).errorDescription ?? ""
            AppLog.analysis.error("Load tracks failed: \(error.localizedDescription)")
            onComplete(0, [:], [], 0)
            return
        }

        let reader: AVAssetReader
        do {
            reader = try AVAssetReader(asset: asset)
        } catch {
            isRunning = false
            status = KAutoError.videoReaderFailed(reason: error.localizedDescription).errorDescription ?? ""
            onComplete(0, [:], [], 0)
            return
        }

        let outputSettings: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
        ]
        let trackOutput = AVAssetReaderTrackOutput(track: track, outputSettings: outputSettings)
        trackOutput.alwaysCopiesSampleData = false
        guard reader.canAdd(trackOutput) else {
            isRunning = false
            status = "Reader configuration failed."
            onComplete(0, [:], [], 0)
            return
        }
        reader.add(trackOutput)
        guard reader.startReading() else {
            let readerError = reader.error?.localizedDescription ?? "Reader failed to start."
            isRunning = false
            status = readerError
            onComplete(0, [:], [], 0)
            return
        }

        self.reader = reader
        self.output = trackOutput
        lastProcessTime = 0
        signThrottle = 0
        previousLuma = nil

        var localLane: [LaneEstimate: Int] = [:]
        var localMotionSum: Double = 0
        var localSigns: [SignObservation] = []
        var count = 0
        let textRequest = VNRecognizeTextRequest()
        textRequest.recognitionLevel = .fast
        textRequest.usesLanguageCorrection = false

        var endOfStream = false
        while !cancelFlag && !endOfStream {
            if Task.isCancelled {
                cancelFlag = true
                break
            }
            await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
                autoreleasepool {
                    defer { cont.resume() }
                    guard let sample = trackOutput.copyNextSampleBuffer(),
                          let buffer = CMSampleBufferGetImageBuffer(sample)
                    else {
                        endOfStream = true
                        return
                    }

                    let now = CFAbsoluteTimeGetCurrent()
                    if now - lastProcessTime < minInterval {
                        return
                    }
                    lastProcessTime = now

                    let motion = motionScore(current: buffer)
                    localMotionSum += motion
                    let lane = laneEstimate(from: buffer)
                    localLane[lane, default: 0] += 1
                    count += 1

                    if now - signThrottle >= signMinInterval {
                        signThrottle = now
                        if let observations = recognizeSigns(in: buffer, request: textRequest) {
                            localSigns.append(contentsOf: observations)
                        }
                    }

                    processedFrames = count
                    onProgress(count)
                }
            }

            if reader.status != .reading {
                break
            }
        }

        let avg = count > 0 ? localMotionSum / Double(count) : 0
        let laneSnapshot = localLane
        let signsSnapshot = localSigns
        let countSnapshot = count
        isRunning = false
        self.reader = nil
        self.output = nil
        status = (cancelFlag || Task.isCancelled) ? "Cancelled." : "Analysis complete."
        if countSnapshot > 0 {
            AppLog.analysis.info("Analysis finished: \(countSnapshot) samples, avgMotion=\(avg, privacy: .public)")
        }
        onComplete(avg, laneSnapshot, signsSnapshot, countSnapshot)
    }

    private func lumaRow(from buffer: CVPixelBuffer) -> [UInt8]? {
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }

        let w = CVPixelBufferGetWidth(buffer)
        let h = CVPixelBufferGetHeight(buffer)
        guard let base = CVPixelBufferGetBaseAddress(buffer) else { return nil }
        let rowBytes = CVPixelBufferGetBytesPerRow(buffer)
        let ptr = base.assumingMemoryBound(to: UInt8.self)

        var row = [UInt8](repeating: 0, count: w)
        let y0 = Int(Double(h) * 0.55)
        for x in 0..<w {
            let p = y0 * rowBytes + x * 4
            let b = ptr[p]
            let g = ptr[p + 1]
            let r = ptr[p + 2]
            row[x] = UInt8((Int(r) + Int(g) + Int(b)) / 3)
        }
        return row
    }

    private func motionScore(current: CVPixelBuffer) -> Double {
        guard let luma = downsampleLuma(from: current) else { return 0 }
        defer { previousLuma = luma }
        guard let prev = previousLuma, prev.count == luma.count else { return 0 }
        var sum: Int = 0
        for i in 0..<luma.count {
            sum += abs(Int(luma[i]) - Int(prev[i]))
        }
        let norm = Double(sum) / Double(luma.count * 255)
        lastMotion = norm
        return norm
    }

    private func downsampleLuma(from buffer: CVPixelBuffer) -> [UInt8]? {
        let image = CIImage(cvPixelBuffer: buffer)
        let scaleX = motionDimension.width / image.extent.width
        let scaleY = motionDimension.height / image.extent.height
        let scaled = image.transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))

        var out: CVPixelBuffer?
        let attrs: [String: Any] = [
            kCVPixelBufferCGImageCompatibilityKey as String: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true,
        ]
        CVPixelBufferCreate(
            kCFAllocatorDefault,
            Int(motionDimension.width),
            Int(motionDimension.height),
            kCVPixelFormatType_32BGRA,
            attrs as CFDictionary,
            &out
        )
        guard let pb = out else { return nil }
        ciContext.render(scaled, to: pb)

        CVPixelBufferLockBaseAddress(pb, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pb, .readOnly) }
        let w = CVPixelBufferGetWidth(pb)
        let h = CVPixelBufferGetHeight(pb)
        guard let base = CVPixelBufferGetBaseAddress(pb) else { return nil }
        let rowBytes = CVPixelBufferGetBytesPerRow(pb)
        let ptr = base.assumingMemoryBound(to: UInt8.self)
        var result: [UInt8] = []
        result.reserveCapacity(w * h)
        for y in 0..<h {
            for x in 0..<w {
                let p = y * rowBytes + x * 4
                let b = ptr[p]
                let g = ptr[p + 1]
                let r = ptr[p + 2]
                result.append(UInt8((Int(r) + Int(g) + Int(b)) / 3))
            }
        }
        return result
    }

    private func laneEstimate(from buffer: CVPixelBuffer) -> LaneEstimate {
        guard let row = lumaRow(from: buffer), row.count > 8 else { return .unknown }
        let w = row.count
        var grad = [Int](repeating: 0, count: w - 1)
        for i in 0..<(w - 1) {
            grad[i] = abs(Int(row[i + 1]) - Int(row[i]))
        }
        let centroidNumerator = (0..<grad.count).reduce(0) { $0 + $1 * grad[$1] }
        let denom = grad.reduce(0, +)
        let lane: LaneEstimate
        if denom < w / 2 {
            lane = .unknown
        } else {
            let c = Double(centroidNumerator) / Double(denom) / Double(grad.count)
            if c < 0.38 {
                lane = .left
            } else if c > 0.62 {
                lane = .right
            } else {
                lane = .center
            }
        }

        lastLane = lane
        return lane
    }

    private func recognizeSigns(in buffer: CVPixelBuffer, request: VNRecognizeTextRequest) -> [SignObservation]? {
        let width = CGFloat(CVPixelBufferGetWidth(buffer))
        let scale = min(1, visionMaxWidth / width)
        let handler: VNImageRequestHandler
        if scale < 0.999 {
            let image = CIImage(cvPixelBuffer: buffer)
            let scaled = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
            var out: CVPixelBuffer?
            CVPixelBufferCreate(
                kCFAllocatorDefault,
                Int(scaled.extent.width),
                Int(scaled.extent.height),
                kCVPixelFormatType_32BGRA,
                nil,
                &out
            )
            guard let pb = out else { return nil }
            ciContext.render(scaled, to: pb)
            handler = VNImageRequestHandler(cvPixelBuffer: pb, orientation: .up, options: [:])
        } else {
            handler = VNImageRequestHandler(cvPixelBuffer: buffer, orientation: .up, options: [:])
        }

        do {
            try handler.perform([request])
        } catch {
            return nil
        }

        let now = Date()
        var found: [SignObservation] = []
        for obs in request.results ?? [] {
            guard let top = obs.topCandidates(1).first else { continue }
            let t = top.string.trimmingCharacters(in: .whitespacesAndNewlines)
            if t.count < 2 { continue }
            if top.confidence < 0.35 { continue }
            if looksLikeRoadSignText(t) {
                found.append(SignObservation(text: t, timestamp: now, confidence: top.confidence))
            }
        }

        recentSigns = Array(found.prefix(6))
        return found
    }

    private func looksLikeRoadSignText(_ s: String) -> Bool {
        let upper = s.uppercased()
        if upper.contains("STOP") || upper.contains("YIELD") { return true }
        if upper.contains("SPEED") || upper.range(of: "\\d+", options: .regularExpression) != nil { return true }
        if upper.contains("ONE WAY") || upper.contains("EXIT") || upper.contains("MERGE") { return true }
        if s.count >= 3 && s.count <= 32 { return true }
        return false
    }
}
