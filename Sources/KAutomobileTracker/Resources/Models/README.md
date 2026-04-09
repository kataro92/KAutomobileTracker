# YOLO `.mlpackage` files

The app loads packages by **family** chosen in **Object detection** (Settings or before tracking):

| Family   | General model            | Signs (optional)        |
|----------|--------------------------|-------------------------|
| YOLO26   | `YOLO26-General`         | `YOLO26-Signs`          |
| YOLO v8  | `YOLOv8-General`         | `YOLOv8-Signs`          |
| YOLO v11 | `YOLOv11-General`        | `YOLOv11-Signs`         |

Each name is the bundle **stem** (the folder is `Stem.mlpackage`).

## Where models are loaded from

1. **Per-user folder (checked first)** — on macOS: `~/Library/Application Support/KAutomobileTracker/models/`. On Windows (training scripts with `--install`): `%LOCALAPPDATA%\KAutomobileTracker\models\`. Copy the `.mlpackage` to your Mac’s Application Support folder if you trained on Windows.
2. **This directory** (`Resources/Models` in the app target) — used when no matching package exists in Application Support.

## Windows (PowerShell)

The Swift app still builds and runs **on macOS only**. On Windows you can run the **Python** training/export pipeline:

```powershell
$env:BDD100K_DIR = "$env:USERPROFILE\datasets\bdd100k"   # optional if default paths exist
.\update_model.ps1
# or: .\update_model.ps1 --dry-run
```

Same environment variables as `update_model.sh`: `PYTHON_TRAIN`, `SKIP_DEPS`, `NO_INSTALL`, `BDD100K_DIR`. Default dataset search: `.\bdd100k`, `%USERPROFILE%\datasets\bdd100k`, `%USERPROFILE%\bdd100k`.

`.\build_app.ps1` prints a short message on Windows (the `.app` bundle must be built on a Mac via `build_app.sh` or Xcode).

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
export BDD100K_DIR=~/path/to/bdd100k   # optional
./update_model.sh
# same as train script + --install; extra flags pass through, e.g. ./update_model.sh --epochs 50 --bundle
```

If `BDD100K_DIR` is unset, `./update_model.sh` uses the first existing path among `./bdd100k`, `~/datasets/bdd100k`, and `~/bdd100k`, as long as it contains `labels/det_20/train` (BDD100K det_20 layout).

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

**If `pip install` fails on SciPy with “gfortran cannot compile programs”:** you are likely on **Python 3.14+**, where wheels may be missing and pip tries to build SciPy from source. Use **Python 3.11–3.13** for `.venv-train` (Homebrew: `brew install python@3.12`, then `export PYTHON_TRAIN=python3.12`, remove `.venv-train`, and run `./update_model.sh` again).

**If SciPy fails with “OpenBLAS not found”** while preparing metadata: pip is building an **old SciPy sdist**. `scripts/requirements-train.txt` pins **`scipy>=1.11.4`** so macOS arm64 + Python 3.12 use wheels; run `pip install -U pip` and reinstall. Last resort: `brew install openblas`.

Relaunch the app or reload models in Settings after installing to Application Support.
