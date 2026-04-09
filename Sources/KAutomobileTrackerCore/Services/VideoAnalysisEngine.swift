import AVFoundation
import Combine
import CoreGraphics
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

    /// Live FaceTime / USB camera preview session (nil when not running).
    @Published public private(set) var livePreviewSession: AVCaptureSession?
    /// Samples ingested during the current live session.
    @Published public private(set) var liveSampleCount: Int = 0
    /// Last overlay for ADAS visualization (live + file sampling).
    @Published public private(set) var lastADASOverlay: ADASFrameOverlay?
    /// Downsized snapshot of the last analyzed frame (optional UI).
    @Published public private(set) var lastVisualizationCGImage: CGImage?

    private let ciContext: CIContext
    private let motionDimension = CGSize(width: 96, height: 54)
    private var minInterval: TimeInterval
    private var lastProcessTime: CFAbsoluteTime = 0
    private var previousLuma: [UInt8]?
    private var reader: AVAssetReader?
    private var output: AVAssetReaderTrackOutput?
    private var signThrottle: CFAbsoluteTime = 0
    private let signMinInterval: TimeInterval = 0.55

    private var cancelFlag = false
    private var analysisTask: Task<Void, Never>?

    private var generalYOLO: YOLODetector?
    private var signsYOLO: YOLODetector?
    private let overlayTracker = OverlayObjectTracker()
    private var overlayFrameIndex: Int = 0
    /// Active detection path for the current session / playback (YOLO vs Apple Vision).
    private var pipelineSettings: DetectionPipelineSettings = .default

    private let captureSession = AVCaptureSession()
    private let videoOutput = AVCaptureVideoDataOutput()
    private let captureQueue = DispatchQueue(label: "com.kautomobile.camera.frames")
    private let liveBridge = LiveCaptureBridge()

    /// Live trip accumulation (cleared on `consumeLiveTripForRecord`).
    private var liveSessionStart: Date?
    private var liveLaneHistogram: [LaneEstimate: Int] = [:]
    private var liveMotionSum: Double = 0
    private var liveSigns: [SignObservation] = []
    private var liveTrafficObjects: [TrafficObjectObservation] = []

    /// Designated initializer with optional sampling override (defaults read from `AppUserSettings`).
    public init(minSampleInterval: TimeInterval? = nil) {
        if let device = MTLCreateSystemDefaultDevice() {
            ciContext = CIContext(mtlDevice: device, options: [.cacheIntermediates: false])
        } else {
            ciContext = CIContext(options: [.useSoftwareRenderer: false])
        }
        minInterval = minSampleInterval ?? AppUserSettings.analysisMinInterval
        liveBridge.engine = self
        reloadYOLOModels()
    }

    /// Reload models from bundle / Application Support using **Settings → defaults** (or the last `reloadYOLOModels(for:)`).
    public func reloadYOLOModels() {
        reloadYOLOModels(for: nil)
    }

    /// Applies pipeline settings: loads YOLO packages for the selected family, or clears YOLO when using Apple Vision.
    public func reloadYOLOModels(for settings: DetectionPipelineSettings?) {
        let resolved = settings ?? AppUserSettings.detectionPipelineSettings
        pipelineSettings = resolved

        switch resolved.backend {
        case .appleVisionBuiltIn:
            generalYOLO = nil
            signsYOLO = nil
            AppLog.analysis.notice("Detection: Apple Vision built-in (rectangles + text)")
        case .yoloCoreML:
            let fam = resolved.yoloFamily
            generalYOLO = YOLODetector.loadIfPresent(
                modelURL: YOLOModelLocator.generalModelURL(family: fam),
                kind: .general,
                classNames: YOLOCocoLabels.names
            )
            signsYOLO = YOLODetector.loadIfPresent(
                modelURL: YOLOModelLocator.signsModelURL(family: fam),
                kind: .signs,
                classNames: []
            )
            if generalYOLO == nil, signsYOLO == nil {
                AppLog.analysis.notice(
                    "No YOLO CoreML models for \(fam.rawValue, privacy: .public) — add \(YOLOModelLocator.generalStem(family: fam), privacy: .public).mlpackage (see Resources/Models) or use Apple Vision."
                )
            }
        }
    }

    public func resetSessionCounters() {
        lastProcessTime = 0
        signThrottle = 0
        previousLuma = nil
        processedFrames = 0
        recentSigns = []
        liveTrafficObjects = []
        lastMotion = 0
        lastLane = .unknown
        status = ""
        overlayTracker.reset()
        overlayFrameIndex = 0
        lastADASOverlay = nil
        lastVisualizationCGImage = nil
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
        pipeline: DetectionPipelineSettings?,
        onProgress: @escaping @Sendable (Int) -> Void,
        onComplete: @escaping @MainActor (Double, [LaneEstimate: Int], [SignObservation], [TrafficObjectObservation], Int) -> Void
    ) {
        cancelFlag = false
        analysisTask?.cancel()
        minInterval = AppUserSettings.analysisMinInterval
        let cfg = pipeline ?? AppUserSettings.detectionPipelineSettings
        reloadYOLOModels(for: cfg)
        resetSessionCounters()
        isRunning = true
        if simulated {
            status = "Simulated trip…"
        } else {
            switch cfg.backend {
            case .yoloCoreML:
                status = "Analyzing video (YOLO + heuristics)…"
            case .appleVisionBuiltIn:
                status = "Analyzing video (Apple Vision + heuristics)…"
            }
        }

        analysisTask = Task { @MainActor [weak self] in
            guard let self else { return }
            if simulated {
                await self.runSimulated(onProgress: onProgress, onComplete: onComplete)
            } else {
                await self.runRealVideo(url: fileURL, onProgress: onProgress, onComplete: onComplete)
            }
        }
    }

    // MARK: - Live camera

    public func startLiveCameraAnalysis() async throws {
        reloadYOLOModels(for: AppUserSettings.detectionPipelineSettings)
        minInterval = AppUserSettings.analysisMinInterval
        resetSessionCounters()
        liveSessionStart = Date()
        liveLaneHistogram = [:]
        liveMotionSum = 0
        liveSigns = []
        liveTrafficObjects = []
        liveSampleCount = 0
        processedFrames = 0

        let session = captureSession
        session.beginConfiguration()
        defer { session.commitConfiguration() }

        for input in session.inputs {
            session.removeInput(input)
        }
        for output in session.outputs {
            session.removeOutput(output)
        }

        guard let device = AVCaptureDevice.default(for: .video) else {
            throw KAutoError.cameraUnavailable(reason: "No video device")
        }
        let input = try AVCaptureDeviceInput(device: device)
        guard session.canAddInput(input) else {
            throw KAutoError.cameraUnavailable(reason: "Cannot add camera input")
        }
        session.addInput(input)

        videoOutput.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
        ]
        videoOutput.alwaysDiscardsLateVideoFrames = true
        videoOutput.setSampleBufferDelegate(liveBridge, queue: captureQueue)

        guard session.canAddOutput(videoOutput) else {
            throw KAutoError.cameraUnavailable(reason: "Cannot add video output")
        }
        session.addOutput(videoOutput)
        if session.canSetSessionPreset(.high) {
            session.sessionPreset = .high
        }

        captureSession.startRunning()
        livePreviewSession = session
        status = AppUserSettings.detectionPipelineSettings.backend == .yoloCoreML
            ? "Live camera — YOLO"
            : "Live camera — Apple Vision"
    }

    public func stopLiveCameraAnalysis() {
        if captureSession.isRunning {
            captureSession.stopRunning()
        }
        livePreviewSession = nil
    }

    /// Call after stopping the camera to build a persisted `TripRecord`.
    public func consumeLiveTripForRecord(endedAt: Date) -> TripRecord? {
        defer {
            liveSessionStart = nil
            liveLaneHistogram = [:]
            liveMotionSum = 0
            liveSigns = []
            liveTrafficObjects = []
            liveSampleCount = 0
        }
        guard let start = liveSessionStart else { return nil }
        let n = liveSampleCount
        let avg = n > 0 ? liveMotionSum / Double(n) : 0
        let laneHist = Dictionary(uniqueKeysWithValues: liveLaneHistogram.map { ($0.key.rawValue, $0.value) })
        return TripRecord(
            startedAt: start,
            endedAt: endedAt,
            isTracked: n > 0,
            inputKind: .liveCamera,
            sourceLabel: "Live camera",
            filePath: nil,
            averageMotion: avg,
            laneHistogram: laneHist,
            signs: liveSigns,
            trafficObjects: liveTrafficObjects.isEmpty ? nil : liveTrafficObjects,
            frameSamples: n
        )
    }

    /// Entry point from `LiveCaptureBridge` (sample buffer copied on camera queue).
    public func ingestLiveFrame(_ buffer: CVPixelBuffer) {
        let now = CFAbsoluteTimeGetCurrent()
        if now - lastProcessTime < minInterval { return }
        lastProcessTime = now
        liveSampleCount += 1
        processedFrames = liveSampleCount

        liveMotionSum += motionScore(current: buffer)
        let lane = laneEstimate(from: buffer)
        liveLaneHistogram[lane, default: 0] += 1

        runVisionPipeline(
            on: buffer,
            ingestSigns: &liveSigns,
            ingestTraffic: &liveTrafficObjects,
            isLive: true,
            recordSignObservations: true,
            recordTrafficObservations: true
        )
    }

    /// Single-frame ADAS overlay for trip detail video playback (does not append to trip signs / `recentSigns`).
    public func updatePlaybackOverlay(fileURL: URL, timeSeconds: Double) async {
        let asset = AVURLAsset(url: fileURL)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = CMTime(seconds: 0.15, preferredTimescale: 600)
        generator.requestedTimeToleranceAfter = CMTime(seconds: 0.15, preferredTimescale: 600)
        let t = max(0, timeSeconds)
        let cm = CMTime(seconds: t, preferredTimescale: 600)
        do {
            let (cgImage, _) = try await generator.image(at: cm)
            guard let buffer = Self.makePixelBuffer(from: cgImage, ciContext: ciContext) else { return }
            var dummySigns: [SignObservation] = []
            var dummyTraffic: [TrafficObjectObservation] = []
            runVisionPipeline(
                on: buffer,
                ingestSigns: &dummySigns,
                ingestTraffic: &dummyTraffic,
                isLive: false,
                recordSignObservations: false,
                recordTrafficObservations: false
            )
        } catch {
            AppLog.analysis.debug("Playback overlay frame failed: \(error.localizedDescription)")
        }
    }

    private static func makePixelBuffer(from cgImage: CGImage, ciContext: CIContext) -> CVPixelBuffer? {
        let image = CIImage(cgImage: cgImage)
        let w = Int(image.extent.width)
        let h = Int(image.extent.height)
        guard w > 0, h > 0 else { return nil }
        var pb: CVPixelBuffer?
        let attrs: [String: Any] = [
            kCVPixelBufferCGImageCompatibilityKey as String: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true,
        ]
        let status = CVPixelBufferCreate(kCFAllocatorDefault, w, h, kCVPixelFormatType_32BGRA, attrs as CFDictionary, &pb)
        guard status == kCVReturnSuccess, let buffer = pb else { return nil }
        ciContext.render(image, to: buffer)
        return buffer
    }

    // MARK: - File / simulation

    private func runSimulated(
        onProgress: @escaping @Sendable (Int) -> Void,
        onComplete: @escaping @MainActor (Double, [LaneEstimate: Int], [SignObservation], [TrafficObjectObservation], Int) -> Void
    ) async {
        let frames = 48
        var lanes: [LaneEstimate: Int] = [:]
        var motion: Double = 0
        var signs: [SignObservation] = []
        let start = Date()
        let region = AppUserSettings.selectedSignRegionEnum

        for i in 0 ..< frames {
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
                let sampleText = region == .us ? "US_regulatory_speed_limit" : "VN_prohibitive_no_entry"
                let gid = SignCatalog.signGroupId(forLabel: sampleText, region: region) ?? SignCatalog.cocoStopSignGroupId(region: region)
                signs.append(
                    SignObservation(
                        text: sampleText,
                        timestamp: start.addingTimeInterval(Double(i) * 0.25),
                        confidence: 0.82,
                        signRegion: region.rawValue,
                        signGroupId: gid,
                        boundingBox: nil
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
        onComplete(avgMotion, lanes, signs, [], n)
    }

    private func runRealVideo(
        url: URL,
        onProgress: @escaping @Sendable (Int) -> Void,
        onComplete: @escaping @MainActor (Double, [LaneEstimate: Int], [SignObservation], [TrafficObjectObservation], Int) -> Void
    ) async {
        let asset = AVURLAsset(url: url)
        let track: AVAssetTrack
        do {
            let tracks = try await asset.loadTracks(withMediaType: .video)
            guard let t = tracks.first else {
                isRunning = false
                status = KAutoError.videoNoTrack.errorDescription ?? "No video track."
                onComplete(0, [:], [], [], 0)
                return
            }
            track = t
        } catch {
            isRunning = false
            status = KAutoError.videoReaderFailed(reason: error.localizedDescription).errorDescription ?? ""
            onComplete(0, [:], [], [], 0)
            return
        }

        let reader: AVAssetReader
        do {
            reader = try AVAssetReader(asset: asset)
        } catch {
            isRunning = false
            status = KAutoError.videoReaderFailed(reason: error.localizedDescription).errorDescription ?? ""
            onComplete(0, [:], [], [], 0)
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
            onComplete(0, [:], [], [], 0)
            return
        }
        reader.add(trackOutput)
        guard reader.startReading() else {
            isRunning = false
            status = reader.error?.localizedDescription ?? "Reader failed to start."
            onComplete(0, [:], [], [], 0)
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
        var localTraffic: [TrafficObjectObservation] = []
        var count = 0

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
                    processedFrames = count

                    runVisionPipeline(
                        on: buffer,
                        ingestSigns: &localSigns,
                        ingestTraffic: &localTraffic,
                        isLive: false,
                        recordSignObservations: true,
                        recordTrafficObservations: true
                    )
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
        let trafficSnapshot = localTraffic
        let countSnapshot = count
        isRunning = false
        self.reader = nil
        self.output = nil
        status = (cancelFlag || Task.isCancelled) ? "Cancelled." : "Analysis complete."
        if countSnapshot > 0 {
            AppLog.analysis.info("Analysis finished: \(countSnapshot) samples, avgMotion=\(avg, privacy: .public)")
        }
        onComplete(avg, laneSnapshot, signsSnapshot, trafficSnapshot, countSnapshot)
    }

    // MARK: - YOLO + overlay pipeline

    private func runVisionPipeline(
        on buffer: CVPixelBuffer,
        ingestSigns: inout [SignObservation],
        ingestTraffic: inout [TrafficObjectObservation],
        isLive: Bool,
        recordSignObservations: Bool,
        recordTrafficObservations: Bool
    ) {
        let now = Date()
        if pipelineSettings.backend == .appleVisionBuiltIn {
            runAppleVisionBuiltInPipeline(
                on: buffer,
                ingestSigns: &ingestSigns,
                ingestTraffic: &ingestTraffic,
                recordSignObservations: recordSignObservations,
                recordTrafficObservations: recordTrafficObservations,
                now: now
            )
            return
        }

        let inferenceBuffer = enhancePixelBufferForYOLOIfNeeded(buffer)
        let threshold = AppUserSettings.detectionConfidenceThreshold
        let useSoftNMS = AppUserSettings.useSoftNMS
        let lowFloor: Float? = {
            guard AppUserSettings.enableByteTrackLowConfidenceAssociation else { return nil }
            let f = AppUserSettings.byteTrackLowConfidenceFloor
            return f < threshold ? f : nil
        }()

        var yoloDets: [YOLODetection] = []
        if let g = generalYOLO {
            do {
                yoloDets.append(contentsOf: try g.detect(
                    pixelBuffer: inferenceBuffer,
                    confidenceThreshold: threshold,
                    useSoftNMS: useSoftNMS,
                    lowConfidenceFloor: lowFloor
                ))
            } catch {
                AppLog.analysis.debug("General YOLO error: \(error.localizedDescription)")
            }
        }
        if let s = signsYOLO {
            do {
                let signRaw = try s.detect(
                    pixelBuffer: inferenceBuffer,
                    confidenceThreshold: threshold,
                    useSoftNMS: useSoftNMS,
                    lowConfidenceFloor: nil
                )
                yoloDets.append(contentsOf: signRaw.filter { includeRegionalSign($0.label) })
            } catch {
                AppLog.analysis.debug("Sign YOLO error: \(error.localizedDescription)")
            }
        }

        var pendingHigh: [OverlayObjectTracker.Pending] = []
        var pendingLow: [OverlayObjectTracker.Pending] = []
        pendingHigh.reserveCapacity(yoloDets.count)
        for d in yoloDets {
            let cat = mapCategory(for: d)
            let overlayLabel = Self.humanReadableMappingLabel(d.label)
            let box = OverlayObjectTracker.Pending(
                box: d.boundingBox,
                category: cat,
                label: overlayLabel,
                confidence: d.confidence
            )
            if let floor = lowFloor, d.confidence >= floor, d.confidence < threshold {
                pendingLow.append(box)
            } else {
                pendingHigh.append(box)
            }
            if recordSignObservations {
                recordSignIfNeeded(detection: d, category: cat, at: now, ingest: &ingestSigns)
            }
        }

        applyLaneVisualizationAndOverlay(
            high: pendingHigh,
            low: pendingLow,
            buffer: buffer,
            now: now,
            ingestTraffic: &ingestTraffic,
            recordTrafficObservations: recordTrafficObservations
        )
    }

    /// Apple Vision: `VNDetectRectanglesRequest` + `VNRecognizeTextRequest` (no CoreML YOLO). Lane corridor unchanged.
    private func runAppleVisionBuiltInPipeline(
        on buffer: CVPixelBuffer,
        ingestSigns: inout [SignObservation],
        ingestTraffic: inout [TrafficObjectObservation],
        recordSignObservations: Bool,
        recordTrafficObservations: Bool,
        now: Date
    ) {
        var pending: [OverlayObjectTracker.Pending] = []

        let rectReq = VNDetectRectanglesRequest()
        rectReq.maximumObservations = 28
        rectReq.minimumConfidence = 0.65
        rectReq.minimumAspectRatio = 0.12
        rectReq.maximumAspectRatio = 1.0
        rectReq.quadratureTolerance = 30
        rectReq.minimumSize = 0.035

        let textReq = VNRecognizeTextRequest()
        textReq.recognitionLevel = .accurate

        let handler = VNImageRequestHandler(cvPixelBuffer: buffer, orientation: .up, options: [:])
        do {
            try handler.perform([rectReq, textReq])
        } catch {
            AppLog.analysis.debug("Apple Vision perform failed: \(error.localizedDescription)")
        }

        if let rects = rectReq.results {
            for r in rects {
                pending.append(
                    OverlayObjectTracker.Pending(
                        box: r.boundingBox,
                        category: .genericRectangle,
                        label: "Region",
                        confidence: Float(r.confidence)
                    )
                )
            }
        }

        if recordSignObservations, let observations = textReq.results {
            for o in observations {
                guard let cand = o.topCandidates(1).first else { continue }
                let s = cand.string.trimmingCharacters(in: .whitespacesAndNewlines)
                guard Self.isSignLikeVisionText(s) else { continue }
                let conf = Float(cand.confidence)
                pending.append(
                    OverlayObjectTracker.Pending(
                        box: o.boundingBox,
                        category: .text,
                        label: String(s.prefix(28)),
                        confidence: conf
                    )
                )
                recordVisionTextAsSignIfNeeded(
                    text: s,
                    boundingBox: o.boundingBox,
                    confidence: conf,
                    at: now,
                    ingest: &ingestSigns
                )
            }
        }

        applyLaneVisualizationAndOverlay(
            high: pending,
            low: [],
            buffer: buffer,
            now: now,
            ingestTraffic: &ingestTraffic,
            recordTrafficObservations: recordTrafficObservations
        )
    }

    /// Core Image contrast / tone lift for YOLO input only (CLAHE-like; lane heuristic still uses the original buffer).
    private func enhancePixelBufferForYOLOIfNeeded(_ buffer: CVPixelBuffer) -> CVPixelBuffer {
        guard AppUserSettings.enableFrameContrastEnhancement else { return buffer }
        let image = CIImage(cvPixelBuffer: buffer)
        let extent = image.extent
        guard extent.width > 2, extent.height > 2 else { return buffer }

        let boosted = image.applyingFilter("CIColorControls", parameters: [
            kCIInputContrastKey: 1.18,
            kCIInputBrightnessKey: 0.03,
            kCIInputSaturationKey: 1.04,
        ])
        let balanced = boosted.applyingFilter("CIHighlightShadowAdjust", parameters: [
            "inputShadowAmount": 0.35,
            "inputHighlightAmount": 0.28,
        ])

        let w = CVPixelBufferGetWidth(buffer)
        let h = CVPixelBufferGetHeight(buffer)
        var out: CVPixelBuffer?
        let attrs: [String: Any] = [
            kCVPixelBufferCGImageCompatibilityKey as String: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true,
        ]
        guard CVPixelBufferCreate(kCFAllocatorDefault, w, h, kCVPixelFormatType_32BGRA, attrs as CFDictionary, &out) == kCVReturnSuccess,
              let dst = out
        else {
            AppLog.analysis.debug("Frame contrast: pixel buffer create failed")
            return buffer
        }
        ciContext.render(balanced, to: dst, bounds: extent, colorSpace: CGColorSpaceCreateDeviceRGB())
        return dst
    }

    private func applyLaneVisualizationAndOverlay(
        high pendingHigh: [OverlayObjectTracker.Pending],
        low pendingLow: [OverlayObjectTracker.Pending],
        buffer: CVPixelBuffer,
        now: Date,
        ingestTraffic: inout [TrafficObjectObservation],
        recordTrafficObservations: Bool
    ) {
        overlayFrameIndex += 1
        let corridor: LaneCorridorOverlay? = {
            guard let row = lumaRow(from: buffer) else { return nil }
            return LaneGeometryEstimator.corridor(fromLumaRow: row)
        }()
        let tracked = overlayTracker.update(high: pendingHigh, low: pendingLow)
        lastADASOverlay = ADASFrameOverlay(
            laneCorridor: corridor,
            objects: tracked,
            frameIndex: overlayFrameIndex,
            timestamp: now
        )

        if recordTrafficObservations {
            appendTrafficSamples(from: tracked, at: now, ingest: &ingestTraffic)
        }

        if AppUserSettings.enableADASVisualization {
            lastVisualizationCGImage = makePreviewCGImage(from: buffer)
        }
    }

    private static let maxTrafficObservationsStored = 5_000

    private static func shouldPersistTrafficCategory(_ c: DetectedObjectCategory) -> Bool {
        switch c {
        case .vehicle, .pedestrian, .trafficLight: true
        default: false
        }
    }

    private func appendTrafficSamples(
        from tracked: [DetectedObjectOverlay],
        at date: Date,
        ingest: inout [TrafficObjectObservation]
    ) {
        let frameIdx = overlayFrameIndex
        for obj in tracked where Self.shouldPersistTrafficCategory(obj.category) {
            let bbox = obj.boundingBox
            let boxArr = [Double(bbox.minX), Double(bbox.minY), Double(bbox.width), Double(bbox.height)]
            ingest.append(
                TrafficObjectObservation(
                    label: obj.label,
                    category: obj.category,
                    trackId: obj.trackId,
                    timestamp: date,
                    confidence: obj.confidence,
                    boundingBox: boxArr,
                    frameIndex: frameIdx
                )
            )
        }
        if ingest.count > Self.maxTrafficObservationsStored {
            ingest.removeFirst(ingest.count - Self.maxTrafficObservationsStored)
        }
    }

    private static func isSignLikeVisionText(_ t: String) -> Bool {
        let trimmed = t.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2, trimmed.count <= 52 else { return false }
        let u = trimmed.uppercased()
        if u.contains("STOP") || u.contains("YIELD") || u.contains("SPEED") { return true }
        if u.contains("MPH") || u.contains("KM/H") || (u.contains("KM") && u.contains("H")) { return true }
        if trimmed.range(of: "\\d", options: .regularExpression) != nil { return true }
        let alnum = trimmed.filter { $0.isLetter || $0.isNumber || "'-/".contains($0) }
        if alnum.count == trimmed.count, trimmed.count <= 10 { return true }
        return false
    }

    private func recordVisionTextAsSignIfNeeded(
        text: String,
        boundingBox: CGRect,
        confidence: Float,
        at date: Date,
        ingest: inout [SignObservation]
    ) {
        let throttleT = CFAbsoluteTimeGetCurrent()
        if throttleT - signThrottle < signMinInterval { return }
        signThrottle = throttleT

        let region = AppUserSettings.selectedSignRegionEnum
        var gid = SignCatalog.signGroupId(forLabel: text, region: region)
        if gid == nil, text.uppercased().contains("STOP") {
            gid = SignCatalog.cocoStopSignGroupId(region: region)
        }
        let bbox = boundingBox
        let boxArr = [Double(bbox.minX), Double(bbox.minY), Double(bbox.width), Double(bbox.height)]
        let obs = SignObservation(
            text: text,
            timestamp: date,
            confidence: confidence,
            signRegion: region.rawValue,
            signGroupId: gid,
            boundingBox: boxArr
        )
        ingest.append(obs)
        var tail = recentSigns
        tail.append(obs)
        recentSigns = Array(tail.suffix(12))
    }

    private func includeRegionalSign(_ label: String) -> Bool {
        let low = label.lowercased()
        switch AppUserSettings.selectedSignRegionEnum {
        case .vietnam: return !low.hasPrefix("us_")
        case .us: return !low.hasPrefix("vn_")
        }
    }

    private func mapCategory(for det: YOLODetection) -> DetectedObjectCategory {
        if det.modelKind == .signs { return .trafficSign }
        let l = Self.semanticLabelForMapping(det.label)

        if l == "person" { return .pedestrian }

        if Self.labelMatchesTrafficLight(l) { return .trafficLight }

        if Self.labelMatchesVehicle(l) { return .vehicle }

        if Self.labelMatchesSignLikeLabel(l) { return .trafficSign }

        if Self.labelMatchesRoadsideObject(l) { return .genericRectangle }

        return .unknown
    }

    /// Lowercase; underscores/hyphens → spaces for COCO / Ultralytics / CoreML class names (`traffic_light`, `traffic-light`).
    private static func normalizedDetectionLabel(_ raw: String) -> String {
        raw.lowercased()
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Maps `2`, `cls2`, etc. to COCO names when the model does not attach string class labels.
    private static func semanticLabelForMapping(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let idx = Int(trimmed), idx >= 0, idx < YOLOCocoLabels.names.count {
            return normalizedDetectionLabel(YOLOCocoLabels.names[idx])
        }
        let n = normalizedDetectionLabel(trimmed)
        if n.hasPrefix("cls") {
            let rest = String(n.dropFirst(3)).filter { $0.isNumber }
            if let idx = Int(rest), idx >= 0, idx < YOLOCocoLabels.names.count {
                return normalizedDetectionLabel(YOLOCocoLabels.names[idx])
            }
        }
        return n
    }

    private static func humanReadableMappingLabel(_ raw: String) -> String {
        let s = semanticLabelForMapping(raw)
        guard let first = s.first else { return raw }
        return String(first).uppercased() + s.dropFirst()
    }

    private static func labelMatchesTrafficLight(_ l: String) -> Bool {
        if l == "traffic light" || l == "trafficlight" { return true }
        // Avoid class names like "traffic sign".
        if l.contains("traffic") && l.contains("light") && !l.contains("sign") { return true }
        return false
    }

    /// COCO 80 + common aliases and fine-tuned road labels (cars, motorbikes, buses, bicycles, …).
    private static func labelMatchesVehicle(_ l: String) -> Bool {
        let exact: Set<String> = [
            "car", "motorcycle", "motorbike", "airplane", "bus", "train", "truck", "boat", "bicycle",
            "van", "suv", "scooter", "moped", "tram", "taxi", "minivan", "pickup", "trailer",
            "pickup truck", "delivery truck", "police car", "ambulance", "fire truck", "school bus",
            "golf cart", "forklift", "snowmobile", "construction vehicle", "segway",
            "carriage", "go kart",
            // plurals / variants some exports use
            "cars", "motorcycles", "motorbikes", "buses", "trucks", "bicycles", "vans", "suvs",
        ]
        if exact.contains(l) { return true }
        if l == "bike" { return true }
        if l.contains("motorcycle") || l.contains("motorbike") { return true }
        if l.hasSuffix(" bus") || l.hasPrefix("bus ") { return true }
        if l.hasSuffix(" truck") && !l.contains("fire") { return true }
        // OpenImages / custom head labels
        if l.contains("vehicle") && !l.contains("non-vehicle") { return true }
        if l == "automobile" || l == "suv" || l.contains("pick-up") || l.contains("pickup") { return true }
        return false
    }

    /// COCO stop sign and similar sign-shaped classes; custom models often end with "sign".
    private static func labelMatchesSignLikeLabel(_ l: String) -> Bool {
        if l == "stop sign" { return true }
        if l.contains("stop") && l.contains("sign") { return true }
        if l.hasSuffix(" sign") { return true }
        if l.contains("speed limit") { return true }
        return false
    }

    private static func labelMatchesRoadsideObject(_ l: String) -> Bool {
        let coco: Set<String> = ["fire hydrant", "parking meter", "bench"]
        return coco.contains(l)
    }

    private func recordSignIfNeeded(
        detection: YOLODetection,
        category: DetectedObjectCategory,
        at date: Date,
        ingest: inout [SignObservation]
    ) {
        guard category == .trafficSign else { return }
        let t = CFAbsoluteTimeGetCurrent()
        if t - signThrottle < signMinInterval { return }
        signThrottle = t

        let region = AppUserSettings.selectedSignRegionEnum
        var gid = SignCatalog.signGroupId(forLabel: detection.label, region: region)
        if gid == nil, detection.label.lowercased().contains("stop") {
            gid = SignCatalog.cocoStopSignGroupId(region: region)
        }
        let bbox = detection.boundingBox
        let boxArr = [Double(bbox.minX), Double(bbox.minY), Double(bbox.width), Double(bbox.height)]
        let obs = SignObservation(
            text: detection.label,
            timestamp: date,
            confidence: detection.confidence,
            signRegion: region.rawValue,
            signGroupId: gid,
            boundingBox: boxArr
        )
        ingest.append(obs)
        var tail = recentSigns
        tail.append(obs)
        recentSigns = Array(tail.suffix(12))
    }

    private func makePreviewCGImage(from buffer: CVPixelBuffer) -> CGImage? {
        let image = CIImage(cvPixelBuffer: buffer)
        let w = image.extent.width
        let scale = min(360 / w, max(0.15, 1))
        let scaled = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        return ciContext.createCGImage(scaled, from: scaled.extent.integral)
    }

    // MARK: - Motion & lane heuristics (cheap)

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
        for x in 0 ..< w {
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
        for i in 0 ..< luma.count {
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
        for y in 0 ..< h {
            for x in 0 ..< w {
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
        for i in 0 ..< (w - 1) {
            grad[i] = abs(Int(row[i + 1]) - Int(row[i]))
        }
        let centroidNumerator = (0 ..< grad.count).reduce(0) { $0 + $1 * grad[$1] }
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
}
