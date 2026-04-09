# Multi-object tracking (MOT) vs this app

Community MOT recipes often assume **Python, PyTorch, dense 30 FPS video, and TensorRT**. **KAutomobileTracker** is a **macOS Swift** app that runs **CoreML** (`.mlpackage`) with **throttled** sampling for CPU/GPU limits. This doc maps common forum terms to what the app actually does.

## What runs on device

| Forum / paper term | In this app |
|--------------------|------------|
| YOLOv8 / v11 / v12 / CDS-YOLO | **Weights inside the `.mlpackage`**. Export or obtain a CoreML bundle named per [`YOLOModelLocator`](../../Sources/KAutomobileTrackerCore/Services/YOLOModelLocator.swift) (e.g. `YOLOv11-General.mlpackage`). “Context-guided” modules live in the **trained model**, not in Swift. |
| Multi-scale heads | Part of the **exported model**; no separate Swift switch. |
| Soft-NMS | Implemented in [`YOLODetector`](../../Sources/KAutomobileTrackerCore/Services/YOLODetector.swift) (optional; reduces over-suppression in crowded lanes). |
| ByteTrack | **Lite two-step association** in [`OverlayObjectTracker`](../../Sources/KAutomobileTrackerCore/Services/OverlayObjectTracker.swift): high-confidence detections match first, then low-confidence boxes match unmatched tracks (no second neural net). |
| TensorRT | **Not used** (NVIDIA). Inference is **CoreML + Vision** on Apple Silicon. |
| Kalman / AEKF / 30-frame gap fill | **Not implemented**; sampling is sparse, so full MOT smoothing is limited. |
| Homography / BEV / speed from IPM | **Out of scope** unless product goals change (see main [README](../../README.md)). |
| CLAHE | **Approximated** with Core Image tone/contrast filters when “Enhance frame contrast” is enabled (not mathematical CLAHE on GPU). |
| Repulsion loss / VAR head | **Training-time** (PyTorch); deliverable is still a new CoreML package. |

## Export workflow

1. Train or download weights in **PyTorch** (any YOLO variant your toolchain supports).
2. **Export to CoreML** (e.g. Ultralytics `model.export(format="coreml", nms=False)` — match [scripts](../../scripts/) conventions).
3. Name bundles to match **Object detection** → **YOLO version** in app Settings (`YOLO26-*`, `YOLOv8-*`, `YOLOv11-*`).
4. Place under the app bundle **Resources/Models** or `~/Library/Application Support/KAutomobileTracker/models/`.

## Settings that affect tracking feel

- **YOLO confidence**: main threshold; low = more boxes (and FPs).
- **Low-confidence association** (ByteTrack-lite): uses an extra floor so slightly weaker boxes can **re-anchor** existing tracks after the first match pass.
- **Soft-NMS**: keeps more overlapping hypotheses before track association.
- **Enhance frame contrast**: may help night/glare; costs CPU on each analyzed frame.

## References

- Soft-NMS: Bodla et al., *Improving Object Detection With One Line of Code*.
- ByteTrack: Zhang et al., *Multi-Object Tracking by Associating Every Detection Box* (we implement a small subset in Swift).
