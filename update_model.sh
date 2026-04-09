#!/usr/bin/env bash
# Run BDD100K fine-tune -> CoreML -> Application Support (see scripts/train_bdd100k_finetune.py).
#
# Usage:
#   export BDD100K_DIR="$HOME/datasets/bdd100k"   # optional; default search starts at ./.data
#   ./update_model.sh
#   ./update_model.sh --epochs 50 --bundle
#   ./update_model.sh --dry-run
#   ./update_model.sh --bdd100k-dir "$HOME/datasets/bdd100k"   # overrides BDD100K_DIR
#
# Optional:
#   NO_INSTALL=1   — skip copying to ~/Library/Application Support/... (not recommended).
#   SKIP_DEPS=1    — skip `pip install` when the venv already has dependencies.
#   PYTHON_TRAIN=python3.12 — interpreter for the venv (default: first of 3.12, 3.13, 3.11, then python3 if <3.14).

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT"

pick_train_python() {
  if [[ -n "${PYTHON_TRAIN:-}" ]]; then
    if command -v "${PYTHON_TRAIN}" >/dev/null 2>&1; then
      echo "${PYTHON_TRAIN}"
      return 0
    fi
    echo "error: PYTHON_TRAIN=${PYTHON_TRAIN} not found in PATH" >&2
    exit 1
  fi
  local cand ver major minor
  for cand in python3.12 python3.13 python3.11 python3; do
    command -v "${cand}" >/dev/null 2>&1 || continue
    ver="$("${cand}" -c 'import sys; print(sys.version_info.major, sys.version_info.minor)')"
    read -r major minor <<< "${ver}"
    if [[ "${major}" -eq 3 && "${minor}" -lt 14 ]]; then
      echo "${cand}"
      return 0
    fi
  done
  echo "error: Need Python 3.11–3.13 for prebuilt PyTorch/SciPy wheels." >&2
  echo "  On 3.14+, pip may build SciPy from source and fail (gfortran missing)." >&2
  echo "  Fix: brew install python@3.12 && export PYTHON_TRAIN=python3.12 && rm -rf .venv-train && ./update_model.sh" >&2
  exit 1
}

venv_python_ok() {
  local ver major minor
  ver="$("${1}/bin/python" -c 'import sys; print(sys.version_info.major, sys.version_info.minor)')"
  read -r major minor <<< "${ver}"
  [[ "${major}" -eq 3 && "${minor}" -lt 14 ]]
}

# True if $1 looks like a BDD100K root (det_20 labels present; matches train_bdd100k_finetune.py discovery).
looks_like_bdd100k() {
  local p="$1"
  [[ -d "${p}/labels/det_20/train" ]] \
    || [[ -d "${p}/bdd100k/labels/det_20/train" ]] \
    || [[ -d "${p}/labels/bdd100k/det_20/train" ]]
}

# Resolve dataset root: BDD100K_DIR, then repo ./.data, ./.data/bdd100k, ./bdd100k, ~/datasets/bdd100k, ~/bdd100k.
resolve_bdd100k_dir() {
  local p
  if [[ -n "${BDD100K_DIR:-}" ]]; then
    p="${BDD100K_DIR/#\~/${HOME}}"
    if [[ ! -d "${p}" ]]; then
      echo "error: BDD100K_DIR is not a directory: ${BDD100K_DIR}" >&2
      exit 1
    fi
    p="$(cd "${p}" && pwd)"
    if looks_like_bdd100k "${p}"; then
      echo "${p}"
      return 0
    fi
    echo "error: BDD100K_DIR does not look like BDD100K det_20: ${p}" >&2
    echo "  Expected .../labels/det_20/train (see https://doc.bdd100k.com/)" >&2
    exit 1
  fi
  for p in "${ROOT}/.data" "${ROOT}/.data/bdd100k" "${ROOT}/bdd100k" "${HOME}/datasets/bdd100k" "${HOME}/bdd100k"; do
    if [[ -d "${p}" ]] && looks_like_bdd100k "${p}"; then
      echo "Using BDD100K dir: ${p}" >&2
      echo "${p}"
      return 0
    fi
  done
  echo "error: No BDD100K dataset found. Download from https://doc.bdd100k.com/download.html" >&2
  echo "  Then either:" >&2
  echo "    export BDD100K_DIR=\"/path/to/bdd100k\" && ./update_model.sh" >&2
  echo "  or place the tree under e.g. ${ROOT}/.data (det_20 layout) or ${ROOT}/.data/bdd100k" >&2
  echo "  (must contain labels/det_20/train with JSON labels)" >&2
  exit 1
}

VENV="${ROOT}/.venv-train"
PY="$(pick_train_python)"

if [[ -d "${VENV}" ]]; then
  if ! venv_python_ok "${VENV}"; then
    echo "error: ${VENV} was created with Python 3.14+ (or unknown). Remove it and rerun:" >&2
    echo "  rm -rf .venv-train && ./update_model.sh" >&2
    exit 1
  fi
else
  echo "Creating Python venv at ${VENV} using ${PY}"
  "${PY}" -m venv "${VENV}"
fi
# shellcheck source=/dev/null
source "${VENV}/bin/activate"

if [[ -z "${SKIP_DEPS:-}" ]]; then
  pip install -r scripts/requirements-train.txt
fi

CMD=(python scripts/train_bdd100k_finetune.py)

has_dry=0
has_bdd=0
has_install=0
prev=
for a in "$@"; do
  if [[ "${a}" == "--dry-run" ]]; then
    has_dry=1
  fi
  if [[ "${a}" == "--install" ]]; then
    has_install=1
  fi
  if [[ "${prev}" == "--bdd100k-dir" ]] || [[ "${a}" == --bdd100k-dir=* ]]; then
    has_bdd=1
  fi
  prev="${a}"
done

if [[ "${has_dry}" -eq 0 ]]; then
  if [[ -z "${NO_INSTALL:-}" && "${has_install}" -eq 0 ]]; then
    CMD+=(--install)
  fi
  if [[ "${has_bdd}" -eq 0 ]]; then
    CMD+=(--bdd100k-dir "$(resolve_bdd100k_dir)")
  fi
fi

exec "${CMD[@]}" "$@"
