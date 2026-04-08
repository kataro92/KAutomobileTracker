import AVFoundation
import CoreVideo
import Foundation

final class LiveCaptureBridge: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    weak var engine: VideoAnalysisEngine?

    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard let engine else { return }
        guard let source = CMSampleBufferGetImageBuffer(sampleBuffer),
              let copy = Self.copyPackedPixelBuffer(source)
        else { return }

        Task { @MainActor in
            engine.ingestLiveFrame(copy)
        }
    }

    /// Deep-copies a single-plane pixel buffer so `ingestLiveFrame` can run asynchronously after the sample buffer is recycled.
    private static func copyPackedPixelBuffer(_ source: CVPixelBuffer) -> CVPixelBuffer? {
        let w = CVPixelBufferGetWidth(source)
        let h = CVPixelBufferGetHeight(source)
        let format = CVPixelBufferGetPixelFormatType(source)
        var destination: CVPixelBuffer?
        let attrs: [String: Any] = [
            kCVPixelBufferMetalCompatibilityKey as String: true,
        ]
        guard CVPixelBufferCreate(
            kCFAllocatorDefault,
            w, h, format,
            attrs as CFDictionary,
            &destination
        ) == kCVReturnSuccess, let destination else { return nil }

        CVPixelBufferLockBaseAddress(source, .readOnly)
        CVPixelBufferLockBaseAddress(destination, [])
        defer {
            CVPixelBufferUnlockBaseAddress(destination, [])
            CVPixelBufferUnlockBaseAddress(source, .readOnly)
        }
        guard CVPixelBufferGetPlaneCount(source) == CVPixelBufferGetPlaneCount(destination) else { return nil }
        guard CVPixelBufferIsPlanar(source) == CVPixelBufferIsPlanar(destination) else { return nil }
        if CVPixelBufferIsPlanar(source) {
            let planeCount = CVPixelBufferGetPlaneCount(source)
            for plane in 0..<planeCount {
                guard let sBase = CVPixelBufferGetBaseAddressOfPlane(source, plane),
                      let dBase = CVPixelBufferGetBaseAddressOfPlane(destination, plane)
                else { return nil }
                let sRow = CVPixelBufferGetBytesPerRowOfPlane(source, plane)
                let dRow = CVPixelBufferGetBytesPerRowOfPlane(destination, plane)
                let ph = CVPixelBufferGetHeightOfPlane(source, plane)
                let rowBytes = min(sRow, dRow)
                for r in 0..<ph {
                    memcpy(dBase.advanced(by: r * dRow), sBase.advanced(by: r * sRow), rowBytes)
                }
            }
        } else {
            guard let sBase = CVPixelBufferGetBaseAddress(source),
                  let dBase = CVPixelBufferGetBaseAddress(destination)
            else { return nil }
            let sRow = CVPixelBufferGetBytesPerRow(source)
            let dRow = CVPixelBufferGetBytesPerRow(destination)
            let rowBytes = min(sRow, dRow)
            for r in 0..<h {
                memcpy(dBase.advanced(by: r * dRow), sBase.advanced(by: r * sRow), rowBytes)
            }
        }
        return destination
    }
}
