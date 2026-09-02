#!/usr/bin/env bash
#
# Activate / use a project venv and launch the Linux brightness GUI.
# On shared folders, .venv may not support Python's symlinks, so this falls
# back to ~/venvs/monitor-brightness.

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GUI_SCRIPT="$PROJECT_ROOT/monitor-brightness-gui.py"
REQUIREMENTS_FILE="$PROJECT_ROOT/requirements.txt"
LOCAL_VENV="$PROJECT_ROOT/.venv"
FALLBACK_VENV="${MONITOR_BRIGHTNESS_VENV:-$HOME/venvs/monitor-brightness}"

log() {
    echo "$@" >&2
}

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

create_fallback_venv() {
    log "==> No usable venv found."
    log "==> Creating fallback venv at $FALLBACK_VENV"

    mkdir -p "$(dirname "$FALLBACK_VENV")"

    if ! python3 -m venv "$FALLBACK_VENV"; then
        log
        log "Error: Python could not create a virtual environment."
        log "On Debian/Ubuntu, install venv support with:"
        log "  sudo apt install python3-venv"
        return 1
    fi

    local py="$FALLBACK_VENV/bin/python"
    if [[ ! -x "$py" ]]; then
        log "Error: Virtual environment creation did not produce $py"
        return 1
    fi

    "$py" -m pip install --upgrade pip >&2
    if [[ -f "$REQUIREMENTS_FILE" ]]; then
        "$py" -m pip install -r "$REQUIREMENTS_FILE" >&2
    fi

    # stdout is intentionally reserved for the path returned to the caller.
    echo "$py"
}

ensure_venv() {
    local venv_python
    if venv_python="$(find_venv_python)"; then
        echo "$venv_python"
        return 0
    fi

    create_fallback_venv
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

    if ! command -v ddcutil >/dev/null; then
        echo "Error: ddcutil not found. Run ./install-deps.sh first." >&2
        exit 1
    fi

    local venv_python
    if ! venv_python="$(ensure_venv)"; then
        exit 1
    fi

    exec "$venv_python" "$GUI_SCRIPT" "$@"
}

main "$@"
