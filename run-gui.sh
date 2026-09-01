#!/usr/bin/env bash
#
# Activate / use the project venv and launch the Linux brightness GUI.
# On VirtualBox shared folders, .venv often cannot be created (symlink
# failures), so this falls back to ~/venvs/monitor-brightness.

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GUI_SCRIPT="$PROJECT_ROOT/monitor-brightness-gui.py"
REQUIREMENTS_FILE="$PROJECT_ROOT/requirements.txt"
LOCAL_VENV="$PROJECT_ROOT/.venv"
FALLBACK_VENV="${MONITOR_BRIGHTNESS_VENV:-$HOME/venvs/monitor-brightness}"

find_venv_python() {
    local candidate
    for candidate in "$LOCAL_VENV/bin/python" "$FALLBACK_VENV/bin/python"; do
        if [[ -x "$candidate" ]]; then
            echo "$candidate"
            return 0
        fi
    done
    return 1
}

ensure_venv() {
    local venv_python
    if venv_python="$(find_venv_python)"; then
        echo "$venv_python"
        return 0
    fi

    echo "==> No usable venv found (shared folders often block .venv symlinks)."
    echo "==> Creating fallback venv at $FALLBACK_VENV"

    mkdir -p "$(dirname "$FALLBACK_VENV")"
    python3 -m venv "$FALLBACK_VENV"

    local py="$FALLBACK_VENV/bin/python"
    "$py" -m pip install --upgrade pip
    if [[ -f "$REQUIREMENTS_FILE" ]]; then
        "$py" -m pip install -r "$REQUIREMENTS_FILE"
    fi

    echo "$py"
}

main() {
    if [[ ! -f "$GUI_SCRIPT" ]]; then
        echo "Error: GUI script not found: $GUI_SCRIPT" >&2
        exit 1
    fi

    if ! command -v python3 >/dev/null; then
        echo "Error: python3 not found. Run ./install-deps.sh first." >&2
        exit 1
    fi

    local venv_python
    venv_python="$(ensure_venv)"

    # shellcheck disable=SC1091
    source "$(dirname "$venv_python")/activate"
    exec python "$GUI_SCRIPT" "$@"
}

main "$@"
