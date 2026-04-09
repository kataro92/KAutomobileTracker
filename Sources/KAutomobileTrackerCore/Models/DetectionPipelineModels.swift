import Foundation

/// Whether analysis uses exported YOLO CoreML packages or Apple Vision built-ins (rectangles + text).
public enum ObjectDetectionBackend: String, Codable, Sendable, CaseIterable {
    case yoloCoreML = "yolo_coreml"
    case appleVisionBuiltIn = "apple_vision"
}

/// Which `.mlpackage` name stem to load for YOLO (files must exist under Application Support or the app bundle).
public enum YOLOModelFamily: String, Codable, Sendable, CaseIterable {
    /// `YOLO26-General.mlpackage` / `YOLO26-Signs.mlpackage`
    case yolo26
    /// `YOLOv8-General.mlpackage` / `YOLOv8-Signs.mlpackage`
    case yoloV8 = "yolo_v8"
    /// `YOLOv11-General.mlpackage` / `YOLOv11-Signs.mlpackage`
    case yoloV11 = "yolo_v11"
}

/// Per-run detection configuration (live/offline tracking, reprocess, or playback).
public struct DetectionPipelineSettings: Codable, Equatable, Sendable {
    public var backend: ObjectDetectionBackend
    /// Used only when `backend == .yoloCoreML`.
    public var yoloFamily: YOLOModelFamily

    public init(backend: ObjectDetectionBackend, yoloFamily: YOLOModelFamily) {
        self.backend = backend
        self.yoloFamily = yoloFamily
    }

    public static let `default` = DetectionPipelineSettings(backend: .yoloCoreML, yoloFamily: .yolo26)
}
