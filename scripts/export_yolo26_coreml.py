#!/usr/bin/env python3
"""Export Ultralytics YOLO26 to CoreML. pip install 'ultralytics[export]>=8.4.0'"""
from __future__ import annotations
import argparse
import os
import shutil
import sys
from pathlib import Path


def _application_support_models_dir() -> Path:
    base = Path(os.environ.get("HOME", str(Path.home())))
    return base / "Library" / "Application Support" / "KAutomobileTracker" / "models"


def _install_mlpackage(src_mlpackage: Path) -> Path:
    dest_dir = _application_support_models_dir()
    dest_dir.mkdir(parents=True, exist_ok=True)
    dest = dest_dir / src_mlpackage.name
    if dest.exists():
        shutil.rmtree(dest)
    shutil.copytree(src_mlpackage, dest)
    return dest


def _export(weights: str, imgsz: int, name: str, out_dir: Path) -> None:
    from ultralytics import YOLO
    model = YOLO(weights)
    path = model.export(format="coreml", imgsz=imgsz, nms=False)
    src = Path(path)
    dest = out_dir / f"{name}.mlpackage"
    if dest.exists(): shutil.rmtree(dest)
    shutil.move(str(src), str(dest))
    print(f"Exported: {dest.resolve()}")

def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--size", choices=["n", "s", "m", "l", "x"], default="n")
    ap.add_argument("--imgsz", type=int, default=640)
    ap.add_argument("--out", type=Path, default=Path(__file__).resolve().parent.parent / "Sources" / "KAutomobileTracker" / "Resources" / "Models")
    ap.add_argument("--general", action="store_true")
    ap.add_argument("--weights", default=None)
    ap.add_argument("--output", default="YOLO26-Signs")
    ap.add_argument(
        "--install",
        action="store_true",
        help="Copy the exported .mlpackage to ~/Library/Application Support/KAutomobileTracker/models/",
    )
    a = ap.parse_args()
    a.out.mkdir(parents=True, exist_ok=True)
    if a.general:
        _export(f"yolo26{a.size}.pt", a.imgsz, "YOLO26-General", a.out)
        exported = a.out / "YOLO26-General.mlpackage"
    elif a.weights:
        _export(a.weights, a.imgsz, a.output, a.out)
        exported = a.out / f"{a.output}.mlpackage"
    else:
        ap.print_help(); sys.exit(1)
    if a.install:
        dest = _install_mlpackage(exported)
        print(f"Installed (Application Support): {dest.resolve()}")

if __name__ == "__main__":
    main()
