#!/usr/bin/env python3
"""
Fine-tune YOLO26 on BDD100K (det_20) with COCO-80 class indices, export CoreML (nms=False),
and optionally install YOLO26-General.mlpackage to Application Support / bundle Resources.

BDD100K must be downloaded separately (see https://doc.bdd100k.com/download.html).
Expected layout (after unzip) is flexible; see discover_bdd100k_layout().

pip install -r scripts/requirements-train.txt
"""
from __future__ import annotations

import argparse
import json
import os
import platform
import random
import shutil
import sys
import tempfile
from pathlib import Path
from typing import Any, Iterable

# COCO 80 names — must match Sources/KAutomobileTrackerCore/Services/YOLOCocoLabels.swift
COCO80_NAMES: list[str] = [
    "person", "bicycle", "car", "motorcycle", "airplane", "bus", "train", "truck", "boat",
    "traffic light", "fire hydrant", "stop sign", "parking meter", "bench", "bird", "cat", "dog", "horse",
    "sheep", "cow", "elephant", "bear", "zebra", "giraffe", "backpack", "umbrella", "handbag", "tie",
    "suitcase", "frisbee", "skis", "snowboard", "sports ball", "kite", "baseball bat", "baseball glove",
    "skateboard", "surfboard", "tennis racket", "bottle", "wine glass", "cup", "fork", "knife", "spoon",
    "bowl", "banana", "apple", "sandwich", "orange", "broccoli", "carrot", "hot dog", "pizza", "donut",
    "cake", "chair", "couch", "potted plant", "bed", "dining table", "toilet", "tv", "laptop", "mouse",
    "remote", "keyboard", "cell phone", "microwave", "oven", "toaster", "sink", "refrigerator", "book",
    "clock", "vase", "scissors", "teddy bear", "hair drier", "toothbrush",
]

# BDD100K det_20 category string -> COCO class index (Ultralytics order)
def _norm_cat(s: str) -> str:
    return "".join(c for c in s.lower().strip() if c.isalnum())


_BDD_RAW_TO_COCO: dict[str, int] = {
    "pedestrian": 0,  # person
    "rider": 0,
    "car": 2,
    "truck": 7,
    "bus": 5,
    "motorcycle": 3,
    "bicycle": 1,
    "trafficlight": 9,
    "traffic_light": 9,
    "trafficsign": 11,  # closest COCO: stop sign
    "traffic_sign": 11,
}


def bdd_category_to_coco_id(category: str) -> int | None:
    key = _norm_cat(category)
    if key in _BDD_RAW_TO_COCO:
        return _BDD_RAW_TO_COCO[key]
    # Aliases with spaces / hyphens removed
    aliases = {
        "trafficlight": 9,
        "trafficsign": 11,
    }
    return aliases.get(key)


def repo_root() -> Path:
    return Path(__file__).resolve().parent.parent


def default_bundle_models_dir() -> Path:
    return repo_root() / "Sources" / "KAutomobileTracker" / "Resources" / "Models"


def application_support_models_dir() -> Path:
    """Per-user models folder (macOS app support, Windows LocalAppData, XDG on Linux)."""
    system = platform.system()
    if system == "Darwin":
        return Path.home() / "Library" / "Application Support" / "KAutomobileTracker" / "models"
    if system == "Windows":
        local = os.environ.get("LOCALAPPDATA")
        base = Path(local) if local else Path.home() / "AppData" / "Local"
        return base / "KAutomobileTracker" / "models"
    xdg = os.environ.get("XDG_DATA_HOME")
    if xdg:
        return Path(xdg) / "KAutomobileTracker" / "models"
    return Path.home() / ".local" / "share" / "KAutomobileTracker" / "models"


def ensure_dir(p: Path) -> None:
    p.mkdir(parents=True, exist_ok=True)


def load_json_label(path: Path) -> dict[str, Any] | list[Any]:
    with path.open(encoding="utf-8") as f:
        return json.load(f)


def extract_frames(obj: Any) -> list[dict[str, Any]]:
    """BDD100K label file may be one dict or a list of frame dicts."""
    if isinstance(obj, list):
        return [x for x in obj if isinstance(x, dict)]
    if isinstance(obj, dict):
        return [obj]
    return []


def frame_image_name(frame: dict[str, Any]) -> str | None:
    n = frame.get("name")
    if isinstance(n, str) and n:
        return n
    return None


def frame_labels(frame: dict[str, Any]) -> list[dict[str, Any]]:
    labs = frame.get("labels")
    if isinstance(labs, list):
        return [x for x in labs if isinstance(x, dict)]
    return []


def box2d_to_yolo_line(
    box: dict[str, Any], img_w: float, img_h: float, class_id: int
) -> str | None:
    x1 = float(box["x1"])
    y1 = float(box["y1"])
    x2 = float(box["x2"])
    y2 = float(box["y2"])
    if img_w <= 0 or img_h <= 0:
        return None
    bw = max(x2 - x1, 1e-6)
    bh = max(y2 - y1, 1e-6)
    cx = (x1 + x2) / 2.0
    cy = (y1 + y2) / 2.0
    return f"{class_id} {cx / img_w:.6f} {cy / img_h:.6f} {bw / img_w:.6f} {bh / img_h:.6f}"


def discover_image_for_label(
    bdd_root: Path, image_name: str, search_roots: Iterable[Path]
) -> Path | None:
    """Find image file matching BDD100K frame name."""
    candidates = [image_name, image_name.replace(".jpg", ".png")]
    for root in search_roots:
        if not root.is_dir():
            continue
        for name in candidates:
            p = root / name
            if p.is_file():
                return p
            # nested train/val
            for sub in ("train", "val", "test"):
                q = root / sub / name
                if q.is_file():
                    return q
    # recursive shallow search (slow but helpful)
    for root in search_roots:
        if root.is_dir():
            for name in candidates:
                found = list(root.rglob(name))
                if found:
                    return found[0]
    return None


def try_image_size(path: Path) -> tuple[float, float]:
    try:
        from PIL import Image

        with Image.open(path) as im:
            w, h = im.size
            return float(w), float(h)
    except Exception:
        return 1280.0, 720.0


def discover_bdd100k_layout(bdd_root: Path) -> tuple[Path, list[Path]]:
    """
    Returns (labels_train_val_parent, image_search_roots).
    labels: directory containing train/ subfolder with per-image JSON (det_20).
    """
    roots = [bdd_root]
    for sub in ("bdd100k", "bdd100k_labels", "bdd100k_labels_release"):
        p = bdd_root / sub
        if p.is_dir():
            roots.append(p)

    label_dirs: list[Path] = []
    for r in roots:
        for pat in (
            r / "labels" / "det_20",
            r / "bdd100k" / "labels" / "det_20",
            r / "labels" / "bdd100k" / "det_20",
        ):
            if pat.is_dir() and (pat / "train").is_dir():
                label_dirs.append(pat)

    if not label_dirs:
        raise FileNotFoundError(
            f"No BDD100K det_20 labels found under {bdd_root}. "
            "Expected .../labels/det_20/train/*.json (see https://doc.bdd100k.com/)."
        )

    labels_parent = label_dirs[0]
    img_roots: list[Path] = []
    for r in roots:
        for ip in (
            r / "images" / "100k",
            r / "bdd100k" / "images" / "100k",
            r / "images" / "10k",
            r / "images",
        ):
            if ip.is_dir():
                img_roots.append(ip)
    if not img_roots:
        img_roots = [bdd_root]

    return labels_parent, img_roots


def convert_split(
    bdd_root: Path,
    split: str,
    out_images: Path,
    out_labels: Path,
    limit: int | None = None,
) -> tuple[int, list[Path]]:
    """Convert BDD100K det_20 JSON -> YOLO txt. Returns (count_written, list of image paths)."""
    labels_parent, img_roots = discover_bdd100k_layout(bdd_root)
    json_dir = labels_parent / split
    if not json_dir.is_dir():
        return 0, []

    ensure_dir(out_images)
    ensure_dir(out_labels)
    written = 0
    image_paths: list[Path] = []
    json_files = sorted(json_dir.glob("*.json"))
    if limit is not None:
        json_files = json_files[:limit]

    for jf in json_files:
        try:
            raw = load_json_label(jf)
        except Exception:
            continue
        for frame in extract_frames(raw):
            name = frame_image_name(frame)
            if not name:
                continue
            img_path = discover_image_for_label(bdd_root, name, img_roots)
            if img_path is None or not img_path.is_file():
                continue
            w, h = try_image_size(img_path)
            lines: list[str] = []
            for lab in frame_labels(frame):
                cat = lab.get("category")
                if not isinstance(cat, str):
                    continue
                cid = bdd_category_to_coco_id(cat)
                if cid is None:
                    continue
                b2 = lab.get("box2d")
                if not isinstance(b2, dict):
                    continue
                try:
                    ln = box2d_to_yolo_line(b2, w, h, cid)
                except (KeyError, TypeError, ValueError):
                    continue
                if ln:
                    lines.append(ln)
            if not lines:
                continue
            stem = Path(name).stem
            dst_img = out_images / f"{stem}.jpg"
            dst_lbl = out_labels / f"{stem}.txt"
            if not dst_img.exists():
                shutil.copy2(img_path, dst_img)
            dst_lbl.write_text("\n".join(lines) + "\n", encoding="utf-8")
            written += 1
            image_paths.append(dst_img.resolve())

    return written, image_paths


def write_data_yaml(yaml_path: Path, dataset_root: Path) -> None:
    """Ultralytics layout: path + train/val relative to path; labels in labels/{split}/."""
    import yaml

    data = {
        "path": str(dataset_root.resolve()),
        "train": "images/train",
        "val": "images/val",
        "nc": len(COCO80_NAMES),
        "names": COCO80_NAMES,
    }
    with yaml_path.open("w", encoding="utf-8") as f:
        yaml.safe_dump(data, f, sort_keys=False, default_flow_style=False)


def build_train_txt_with_focus(
    train_images_dir: Path,
    focus_coco_indices: set[int],
    repeats: int,
    seed: int,
) -> Path:
    """Optional upsample: list image paths; duplicate those containing focus classes."""
    rng = random.Random(seed)
    lines: list[str] = []
    for img in sorted(train_images_dir.glob("*.jpg")):
        lines.append(str(img.resolve()))
    # train_images_dir = .../images/train -> labels at .../labels/train
    lbl_dir = train_images_dir.parent.parent / "labels" / train_images_dir.name
    extra: list[str] = []
    for img_path in lines:
        stem = Path(img_path).stem
        lf = lbl_dir / f"{stem}.txt"
        if not lf.is_file():
            continue
        try:
            text = lf.read_text(encoding="utf-8").strip()
        except OSError:
            continue
        has_focus = False
        for row in text.splitlines():
            parts = row.split()
            if not parts:
                continue
            try:
                ci = int(parts[0])
            except ValueError:
                continue
            if ci in focus_coco_indices:
                has_focus = True
                break
        if has_focus:
            for _ in range(max(0, repeats - 1)):
                extra.append(img_path)
    rng.shuffle(lines)
    all_lines = lines + extra
    rng.shuffle(all_lines)
    dataset_root = train_images_dir.parent.parent
    out = dataset_root / "train_list.txt"
    out.write_text("\n".join(all_lines) + "\n", encoding="utf-8")
    return out


def coco_name_to_index(names: Iterable[str]) -> set[int]:
    m = {n.lower(): i for i, n in enumerate(COCO80_NAMES)}
    out: set[int] = set()
    for n in names:
        k = n.lower().strip()
        if k in m:
            out.add(m[k])
        # allow "motorbike" typo -> motorcycle
        if k == "motorbike" and "motorcycle" in m:
            out.add(m["motorcycle"])
    return out


def install_to_application_support(src: Path, name: str = "YOLO26-General") -> Path:
    dest_support = application_support_models_dir()
    ensure_dir(dest_support)
    dest_pkg = dest_support / f"{name}.mlpackage"
    if dest_pkg.exists():
        shutil.rmtree(dest_pkg)
    shutil.copytree(src, dest_pkg)
    print(f"Installed (Application Support): {dest_pkg}")
    return dest_pkg


def copy_mlpackage_to_bundle(src: Path, name: str = "YOLO26-General") -> Path:
    bundle_dir = default_bundle_models_dir()
    ensure_dir(bundle_dir)
    dest_b = bundle_dir / f"{name}.mlpackage"
    if dest_b.exists():
        shutil.rmtree(dest_b)
    shutil.copytree(src, dest_b)
    print(f"Installed (bundle Resources): {dest_b}")
    return dest_b


def export_coreml_move(weights: Path, imgsz: int, out_dir: Path, name: str) -> Path:
    from ultralytics import YOLO

    model = YOLO(str(weights))
    exported = model.export(format="coreml", imgsz=imgsz, nms=False)
    src = Path(exported)
    dest = out_dir / f"{name}.mlpackage"
    if dest.exists():
        shutil.rmtree(dest)
    shutil.move(str(src), str(dest))
    return dest


def create_synthetic_bdd_sample(target: Path) -> None:
    """Minimal det_20-style tree for --dry-run without real BDD100K."""
    from PIL import Image

    ensure_dir(target / "images" / "100k" / "train")
    ensure_dir(target / "images" / "100k" / "val")
    ensure_dir(target / "labels" / "det_20" / "train")
    ensure_dir(target / "labels" / "det_20" / "val")

    def _write_split(name: str, split: str) -> None:
        img_path = target / "images" / "100k" / split / f"{name}.jpg"
        Image.new("RGB", (640, 360), color=(40, 40, 40)).save(img_path, quality=90)
        frame = {
            "name": f"{name}.jpg",
            "labels": [
                {"category": "car", "box2d": {"x1": 100, "y1": 80, "x2": 400, "y2": 280}},
                {"category": "motorcycle", "box2d": {"x1": 450, "y1": 200, "x2": 580, "y2": 340}},
            ],
        }
        json_path = target / "labels" / "det_20" / split / f"{name}.json"
        json_path.write_text(json.dumps(frame), encoding="utf-8")

    _write_split("dryrun_train", "train")
    _write_split("dryrun_val", "val")


def main() -> None:
    ap = argparse.ArgumentParser(description="BDD100K -> YOLO26 fine-tune -> CoreML -> install")
    ap.add_argument(
        "--bdd100k-dir",
        type=Path,
        default=None,
        help="Root folder containing BDD100K images + labels/det_20 (optional if --dry-run without dir)",
    )
    ap.add_argument(
        "--output-dataset",
        type=Path,
        default=None,
        help="YOLO dataset output root (default: <bdd100k-dir>/../bdd100k_yolo_coco80)",
    )
    ap.add_argument("--size", choices=["n", "s", "m", "l", "x"], default="n")
    ap.add_argument("--imgsz", type=int, default=640)
    ap.add_argument("--epochs", type=int, default=30)
    ap.add_argument("--batch", type=int, default=16)
    ap.add_argument("--freeze", type=int, default=10, help="Freeze first N layers (Ultralytics)")
    ap.add_argument("--lr0", type=float, default=0.001)
    ap.add_argument(
        "--focus-classes",
        type=str,
        default="car,motorcycle",
        help="Comma-separated COCO names to upsample in train list (empty to disable)",
    )
    ap.add_argument("--focus-repeats", type=int, default=2, help="Extra copies of focus images")
    ap.add_argument("--seed", type=int, default=42)
    ap.add_argument("--install", action="store_true", help="Copy mlpackage to Application Support")
    ap.add_argument(
        "--bundle",
        action="store_true",
        help="Also copy mlpackage to Sources/.../Resources/Models",
    )
    ap.add_argument("--dry-run", action="store_true", help="Convert (limited), write yaml, skip train/export")
    ap.add_argument(
        "--dry-run-limit",
        type=int,
        default=5,
        help="Max label JSON files per split when --dry-run",
    )
    ap.add_argument("--device", type=str, default=None, help="e.g. mps, cpu, 0")
    args = ap.parse_args()

    synthetic_tmp: Path | None = None
    bdd_root = args.bdd100k_dir
    if args.dry_run and bdd_root is None:
        synthetic_tmp = Path(tempfile.mkdtemp(prefix="bdd100k_dryrun_"))
        bdd_root = synthetic_tmp
        create_synthetic_bdd_sample(bdd_root)
        print(f"[dry-run] Created synthetic sample at {bdd_root}")

    if bdd_root is None:
        ap.error("--bdd100k-dir is required unless --dry-run (synthetic sample)")

    bdd_root = bdd_root.expanduser().resolve()
    if not bdd_root.is_dir():
        print(f"ERROR: BDD100K directory not found: {bdd_root}", file=sys.stderr)
        sys.exit(1)

    out_ds = args.output_dataset
    if out_ds is None:
        out_ds = bdd_root.parent / "bdd100k_yolo_coco80"
    out_ds = out_ds.expanduser().resolve()
    train_img = out_ds / "images" / "train"
    val_img = out_ds / "images" / "val"
    train_lbl = out_ds / "labels" / "train"
    val_lbl = out_ds / "labels" / "val"
    ensure_dir(train_img)
    ensure_dir(val_img)
    ensure_dir(train_lbl)
    ensure_dir(val_lbl)

    lim = args.dry_run_limit if args.dry_run else None
    try:
        n_tr, _ = convert_split(bdd_root, "train", train_img, train_lbl, limit=lim)
        n_va, _ = convert_split(bdd_root, "val", val_img, val_lbl, limit=lim)
    except FileNotFoundError as e:
        print(f"ERROR: {e}", file=sys.stderr)
        sys.exit(1)

    if n_tr == 0:
        print(
            "ERROR: No training pairs converted. Check BDD100K paths and that images match label names.",
            file=sys.stderr,
        )
        sys.exit(1)

    # Ultralytics requires at least one val image; duplicate one train sample if needed
    if n_va == 0 and n_tr > 0:
        imgs_sorted = sorted(train_img.glob("*.jpg"))
        one = imgs_sorted[0] if imgs_sorted else None
        if one is not None:
            shutil.copy2(one, val_img / one.name)
            tl = train_lbl / f"{one.stem}.txt"
            if tl.is_file():
                shutil.copy2(tl, val_lbl / f"{one.stem}.txt")
            n_va = 1
            print("Note: no val labels converted; duplicated one train sample into val for YOLO.")

    yaml_path = out_ds / "bdd100k_coco80.yaml"
    write_data_yaml(yaml_path, out_ds)

    # Optional train list with focus upsampling
    if args.focus_classes.strip() and not args.dry_run:
        focus_idx = coco_name_to_index(s.strip() for s in args.focus_classes.split(",") if s.strip())
        if focus_idx:
            list_path = build_train_txt_with_focus(
                train_img, focus_idx, repeats=args.focus_repeats, seed=args.seed
            )
            import yaml

            with yaml_path.open(encoding="utf-8") as f:
                data = yaml.safe_load(f)
            data["train"] = "train_list.txt"
            with yaml_path.open("w", encoding="utf-8") as f:
                yaml.safe_dump(data, f, sort_keys=False, default_flow_style=False)
            print(f"Wrote focused train list: {list_path}")

    print(f"Dataset: {out_ds} (train images: {n_tr}, val: {n_va})")
    print(f"data.yaml: {yaml_path}")

    if args.dry_run:
        import yaml

        with yaml_path.open(encoding="utf-8") as f:
            loaded = yaml.safe_load(f)
        assert loaded["nc"] == 80
        assert len(loaded["names"]) == 80
        print("[dry-run] YAML valid (nc=80). Skipping train/export/install.")
        print(f"[dry-run] Application Support models dir would be: {application_support_models_dir()}")
        if synthetic_tmp is not None:
            shutil.rmtree(synthetic_tmp, ignore_errors=True)
            if args.output_dataset is None:
                shutil.rmtree(out_ds, ignore_errors=True)
        sys.exit(0)

    try:
        from ultralytics import YOLO
    except ImportError:
        print("ERROR: ultralytics not installed. pip install -r scripts/requirements-train.txt", file=sys.stderr)
        sys.exit(1)

    weights = f"yolo26{args.size}.pt"
    model = YOLO(weights)
    train_kw: dict[str, Any] = {
        "data": str(yaml_path),
        "epochs": args.epochs,
        "imgsz": args.imgsz,
        "batch": args.batch,
        "freeze": args.freeze,
        "lr0": args.lr0,
        "seed": args.seed,
        "exist_ok": True,
        "verbose": True,
    }
    if args.device:
        train_kw["device"] = args.device

    model.train(**train_kw)
    best = Path(model.trainer.best) if getattr(model, "trainer", None) and model.trainer.best else None
    if best is None or not best.is_file():
        save_dir = getattr(model.trainer, "save_dir", None) if model.trainer else None
        if save_dir:
            cand = Path(save_dir) / "weights" / "best.pt"
            if cand.is_file():
                best = cand
    if best is None or not best.is_file():
        print("ERROR: best.pt not found after training.", file=sys.stderr)
        sys.exit(1)

    export_dir = out_ds / "coreml_export"
    ensure_dir(export_dir)
    mlpkg = export_coreml_move(best, args.imgsz, export_dir, "YOLO26-General")
    print(f"Exported: {mlpkg.resolve()}")

    if args.install:
        install_to_application_support(mlpkg)
    if args.bundle:
        copy_mlpackage_to_bundle(mlpkg)
    if not args.install and not args.bundle:
        print(
            "Tip: pass --install to copy to ~/Library/Application Support/KAutomobileTracker/models/ "
            "or --bundle to also add Sources/.../Resources/Models for shipping in the app."
        )


if __name__ == "__main__":
    main()
