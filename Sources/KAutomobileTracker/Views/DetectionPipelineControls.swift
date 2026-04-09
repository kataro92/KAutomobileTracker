import KAutomobileTrackerCore
import SwiftUI

/// Detector backend + YOLO package family (shown before tracking / reprocess).
struct DetectionPipelineControls: View {
    @Binding var settings: DetectionPipelineSettings
    /// When true, writes changes to `AppUserSettings` (live/offline tracking + Settings window).
    var persistToUserDefaults: Bool
    /// When false, embed contents in a `Form` `Section` instead of a `GroupBox`.
    var useGroupBox: Bool = true

    var body: some View {
        let inner = VStack(alignment: .leading, spacing: 10) {
            Picker("Engine", selection: $settings.backend) {
                Text("YOLO (CoreML)").tag(ObjectDetectionBackend.yoloCoreML)
                Text("Apple Vision (built-in)").tag(ObjectDetectionBackend.appleVisionBuiltIn)
            }
            .pickerStyle(.radioGroup)

            if settings.backend == .yoloCoreML {
                Picker("YOLO version (package name)", selection: $settings.yoloFamily) {
                    Text("YOLO26 — YOLO26-General").tag(YOLOModelFamily.yolo26)
                    Text("YOLO v8 — YOLOv8-General").tag(YOLOModelFamily.yoloV8)
                    Text("YOLO v11 — YOLOv11-General").tag(YOLOModelFamily.yoloV11)
                }
                Text(
                    "Add the matching CoreML package under Application Support or the app bundle (optional signs: \(YOLOModelLocator.signsStem(family: settings.yoloFamily)).mlpackage)."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("Uses Vision rectangle and text recognition only (no YOLO classes like car or traffic light). Lane heuristics are unchanged.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)

        Group {
            if useGroupBox {
                GroupBox("Object detection") { inner }
            } else {
                inner
            }
        }
        .onChange(of: settings) { _, new in
            if persistToUserDefaults {
                AppUserSettings.detectionPipelineSettings = new
            }
        }
    }
}
