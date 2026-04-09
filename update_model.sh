#!/usr/bin/env bash
# Run BDD100K fine-tune -> CoreML -> Application Support (see scripts/train_bdd100k_finetune.py).
#
# Usage:
#   export BDD100K_DIR="$HOME/datasets/bdd100k"
#   ./update_model.sh
#   ./update_model.sh --epochs 50 --bundle
#   ./update_model.sh --dry-run
#   ./update_model.sh --bdd100k-dir "$HOME/datasets/bdd100k"   # overrides BDD100K_DIR
#
# Optional:
#   NO_INSTALL=1  — skip copying to ~/Library/Application Support/... (not recommended).
#   SKIP_DEPS=1   — skip `pip install` when the venv already has dependencies.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT"

VENV="${ROOT}/.venv-train"
if [[ ! -d "${VENV}" ]]; then
  echo "Creating Python venv at ${VENV}"
  python3 -m venv "${VENV}"
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
    if [[ -z "${BDD100K_DIR:-}" ]]; then
      echo "error: set BDD100K_DIR to your BDD100K dataset root, or pass --bdd100k-dir /path" >&2
      echo "  example: export BDD100K_DIR=\"\$HOME/datasets/bdd100k\" && ./update_model.sh" >&2
      exit 1
    fi
    CMD+=(--bdd100k-dir "${BDD100K_DIR}")
  fi
fi

exec "${CMD[@]}" "$@"
