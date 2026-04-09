# YOLO `.mlpackage` files

The app loads packages by **family** chosen in **Object detection** (Settings or before tracking):

| Family   | General model            | Signs (optional)        |
|----------|--------------------------|-------------------------|
| YOLO26   | `YOLO26-General`         | `YOLO26-Signs`          |
| YOLO v8  | `YOLOv8-General`         | `YOLOv8-Signs`          |
| YOLO v11 | `YOLOv11-General`        | `YOLOv11-Signs`         |

Each row is the bundle **stem** (on disk: `Stem.mlpackage`). If your export uses another name, **rename** the folder to match this table so `YOLOModelLocator` can find it.

## Where the app loads models from

1. **Per-user folder (first)** — **macOS:** `~/Library/Application Support/KAutomobileTracker/models/`. **Windows** (only relevant after `train_bdd100k_finetune.py` / `export_yolo26_coreml.py` with `--install`): `%LOCALAPPDATA%\KAutomobileTracker\models\`. If you trained on Windows, copy the `.mlpackage` into the macOS path above for the app to use it.
2. **This directory** — `Resources/Models` in the app target, when nothing exists in the per-user folder.

## Local BDD100K path: `.data` (recommended)

Put the dataset **inside the repo** under **`./.data`** (or **`./.data/bdd100k`** if you keep an extra folder level). That directory is listed in **`.gitignore`**, so large downloads are not committed.

Expected layout (either under `.data` or `.data/bdd100k`): `labels/det_20/train` with JSON labels, plus images discoverable as in `scripts/train_bdd100k_finetune.py` (e.g. `images/100k/train`).

If **`BDD100K_DIR`** is unset, **`update_model.sh`** / **`update_model.ps1`** search in order:

1. `./.data`
2. `./.data/bdd100k`
3. `./bdd100k`
4. `~/datasets/bdd100k` / `%USERPROFILE%\datasets\bdd100k`
5. `~/bdd100k` / `%USERPROFILE%\bdd100k`

## Wrapper scripts (venv + train + install)

| Platform | Script           | Notes |
|----------|------------------|--------|
| macOS / Linux shell | `./update_model.sh` | Creates `.venv-train`, `pip install -r scripts/requirements-train.txt`, runs training with `--install` unless `NO_INSTALL=1` or `--dry-run`. |
| Windows | `.\update_model.ps1` | Same idea; use `PYTHON_TRAIN` or `py -3.12` for Python 3.11–3.13. If activation is blocked: `powershell -ExecutionPolicy Bypass -File .\update_model.ps1`. |

Shared environment variables: **`BDD100K_DIR`**, **`PYTHON_TRAIN`**, **`SKIP_DEPS=1`**, **`NO_INSTALL=1`**.

**Swift app:** still **macOS-only**. On Windows, `.\build_app.ps1` only explains that the `.app` must be built on a Mac (`./build_app.sh` or Xcode).

## Exporting stock YOLO26 (no BDD fine-tune)

From the repo root, with `ultralytics[export]` (see `scripts/requirements-export.txt`):

```bash
python scripts/export_yolo26_coreml.py --general --imgsz 640
python scripts/export_yolo26_coreml.py --weights path/to/best.pt --output YOLO26-Signs
```

- **`--install`** — copies the exported `.mlpackage` to the per-user models folder (macOS or Windows paths above).
- Exports use **`nms=False`** to match the app decoder and Soft-NMS.

## Fine-tuning on BDD100K (dashcam, COCO-80 general head)

Keeps **80 COCO classes** in Ultralytics order (matches `YOLOCocoLabels` in the app).

1. Download [BDD100K](https://doc.bdd100k.com/download.html) and unpack under **`./.data`** (or set **`BDD100K_DIR`**).
2. Dependencies: `pip install -r scripts/requirements-train.txt` in a venv, or run **`./update_model.sh`** / **`.\update_model.ps1`** (creates **`.venv-train`**).
3. Examples:

```bash
./update_model.sh
./update_model.sh --epochs 50 --bundle
./update_model.sh --dry-run
```

```bash
python scripts/train_bdd100k_finetune.py \
  --bdd100k-dir ./.data \
  --size n \
  --epochs 30 \
  --install
```

- **`--install`** — installs `YOLO26-General.mlpackage` to the per-user models folder.
- **`--bundle`** — also copies into this `Resources/Models` tree for the next app build.
- **Artifacts** — `coreml_export/YOLO26-General.mlpackage` under the YOLO dataset output directory (see script) before install/bundle.
- **`--dry-run`** — conversion + `data.yaml` check only (no Ultralytics training).

## Troubleshooting `pip install`

**“gfortran cannot compile programs”** — Usually **Python 3.14+** without SciPy wheels. Use **3.11–3.13** (e.g. `brew install python@3.12`, `export PYTHON_TRAIN=python3.12`, remove `.venv-train`, rerun the wrapper).

**“OpenBLAS not found”** (SciPy metadata) — Pip fell back to an **old SciPy sdist**. **`requirements-train.txt`** pins **`scipy>=1.11.4`** for wheels; upgrade pip and reinstall. Last resort: `brew install openblas`.

After **`--install`**, relaunch the app or reload models in **Settings**.
