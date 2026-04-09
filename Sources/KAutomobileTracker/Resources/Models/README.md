# YOLO `.mlpackage` files

The app loads packages by **family** chosen in **Object detection** (Settings or before tracking):

| Family   | General model            | Signs (optional)        |
|----------|--------------------------|-------------------------|
| YOLO26   | `YOLO26-General`         | `YOLO26-Signs`          |
| YOLO v8  | `YOLOv8-General`         | `YOLOv8-Signs`          |
| YOLO v11 | `YOLOv11-General`        | `YOLOv11-Signs`         |

Each name is the bundle **stem** (the folder is `Stem.mlpackage`).

## Where models are loaded from

1. **`~/Library/Application Support/KAutomobileTracker/models/`** — checked first. Use this for models you drop in after shipping, or when a script copies a new build here.
2. **This directory** (`Resources/Models` in the app target) — used when no matching package exists in Application Support.

Rename exports to match the table above if your tooling uses different stems.

## Exporting YOLO26 (stock weights)

From the repo root, with a Python environment that has `ultralytics[export]` (see `scripts/requirements-export.txt`):

```bash
python scripts/export_yolo26_coreml.py --general --imgsz 640
python scripts/export_yolo26_coreml.py --weights path/to/best.pt --output YOLO26-Signs
```

- Add **`--install`** to copy the exported `.mlpackage` into Application Support so the running app picks it up on the next load (no Xcode rebuild).
- Exports use **`nms=False`** so they match the app’s decoder and Soft-NMS path.

## Fine-tuning on BDD100K (dashcam, COCO-80 general head)

For a driver-centric general detector while keeping **80 COCO classes** (Ultralytics order, matching the app’s `YOLOCocoLabels`):

1. Download [BDD100K](https://doc.bdd100k.com/download.html) and point the script at the dataset root (it discovers `labels/det_20` and `images/100k` style layouts).
2. Install training deps: `pip install -r scripts/requirements-train.txt` (use a virtual environment on macOS if your Python is PEP 668–managed), or use the repo-root wrapper below (it creates `.venv-train` and runs `pip install` for you).
3. Run:

```bash
export BDD100K_DIR=~/path/to/bdd100k
./update_model.sh
# same as train script + --install; extra flags pass through, e.g. ./update_model.sh --epochs 50 --bundle
```

Or call Python directly:

```bash
python scripts/train_bdd100k_finetune.py \
  --bdd100k-dir ~/path/to/bdd100k \
  --size n \
  --epochs 30 \
  --install
```

- **`--install`** — copies `YOLO26-General.mlpackage` to Application Support.
- **`--bundle`** — also copies into this `Resources/Models` folder for embedding in the next app build.
- CoreML output is written under your dataset output folder as `coreml_export/YOLO26-General.mlpackage` before install/bundle copies.
- **`--dry-run`** — validates conversion and `data.yaml` without training (no Ultralytics run).

Relaunch the app or reload models in Settings after installing to Application Support.
