#!/usr/bin/env bash
#
# Install Linux dependencies and prepare a Python virtual environment.

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOCAL_VENV="$PROJECT_ROOT/.venv"
FALLBACK_VENV="${MONITOR_BRIGHTNESS_VENV:-$HOME/venvs/monitor-brightness}"
REQUIREMENTS_FILE="$PROJECT_ROOT/requirements.txt"

step() {
    echo "==> $1"
}

command_exists() {
    command -v "$1" &>/dev/null
}

detect_package_manager() {
    if command_exists apt-get; then
        echo "apt"
    elif command_exists dnf; then
        echo "dnf"
    elif command_exists pacman; then
        echo "pacman"
    else
        echo ""
    fi
}

install_system_packages() {
    local pkg_manager
    pkg_manager="$(detect_package_manager)"

    case "$pkg_manager" in
        apt)
            step "Installing system packages via apt"
            sudo apt-get update
            sudo apt-get install -y \
                python3 python3-venv python3-tk python3-pip \
                ddcutil i2c-tools
            ;;
        dnf)
            step "Installing system packages via dnf"
            sudo dnf install -y \
                python3 python3-tkinter python3-pip \
                ddcutil i2c-tools
            ;;
        pacman)
            step "Installing system packages via pacman"
            sudo pacman -Sy --needed \
                python python-tkinter python-pip \
                ddcutil i2c-tools
            ;;
        *)
            echo "Error: No supported package manager found." >&2
            echo "Install Python 3.9+, Tkinter, ddcutil, and i2c-tools manually." >&2
            exit 1
            ;;
    esac
}

find_python() {
    if command_exists python3; then
        if python3 -c "import sys; raise SystemExit(0 if sys.version_info >= (3, 9) else 1)"; then
            echo "python3"
            return 0
        fi
    fi

    return 1
}

dependencies_ready() {
    local python_cmd
    python_cmd="$(find_python 2>/dev/null || true)"

    [[ -n "$python_cmd" ]] || return 1
    "$python_cmd" -c "import tkinter" 2>/dev/null || return 1
    command_exists ddcutil || return 1
    command_exists i2cdetect || return 1
}

prepare_venv() {
    local python_cmd="$1"
    local target=""

    if [[ -x "$LOCAL_VENV/bin/python" ]]; then
        target="$LOCAL_VENV"
        step "Using existing virtual environment at $target"
    elif [[ -x "$FALLBACK_VENV/bin/python" ]]; then
        target="$FALLBACK_VENV"
        step "Using existing fallback virtual environment at $target"
    else
        step "Creating virtual environment at $LOCAL_VENV"
        if "$python_cmd" -m venv "$LOCAL_VENV" 2>/dev/null \
            && [[ -x "$LOCAL_VENV/bin/python" ]]; then
            target="$LOCAL_VENV"
        else
            echo "Warning: Could not create a usable .venv in the project." >&2
            echo "This commonly happens on VirtualBox/shared filesystems." >&2
            step "Creating fallback virtual environment at $FALLBACK_VENV"
            mkdir -p "$(dirname "$FALLBACK_VENV")"
            "$python_cmd" -m venv "$FALLBACK_VENV"
            target="$FALLBACK_VENV"
        fi
    fi

    local venv_python="$target/bin/python"
    if [[ ! -x "$venv_python" ]]; then
        echo "Error: Virtual environment creation failed. Expected: $venv_python" >&2
        exit 1
    fi

    step "Upgrading pip"
    "$venv_python" -m pip install --upgrade pip

    if [[ -f "$REQUIREMENTS_FILE" ]]; then
        step "Installing Python dependencies from requirements.txt"
        "$venv_python" -m pip install -r "$REQUIREMENTS_FILE"
    fi

    echo
    echo "Python environment: $target"
}

main() {
    cd "$PROJECT_ROOT"

    if ! dependencies_ready; then
        install_system_packages
    fi

    local python_cmd
    python_cmd="$(find_python || true)"
    if [[ -z "$python_cmd" ]]; then
        echo "Error: Python 3.9+ is not available after dependency installation." >&2
        exit 1
    fi

    if ! "$python_cmd" -c "import tkinter" 2>/dev/null; then
        echo "Error: Tkinter is unavailable after dependency installation." >&2
        exit 1
    fi

    if ! command_exists ddcutil; then
        echo "Error: ddcutil is unavailable after dependency installation." >&2
        exit 1
    fi

    # Older distribution packages may not configure this automatically.
    if command_exists modprobe; then
        sudo modprobe i2c-dev 2>/dev/null || true
    fi

    step "Using $("$python_cmd" --version)"
    prepare_venv "$python_cmd"

    echo
    echo "Setup complete."
    echo
    echo "Test monitor access:"
    echo "  ddcutil detect"
    echo "  ddcutil getvcp 10 --terse"
    echo
    echo "Run the Linux GUI:"
    echo "  ./run-gui.sh"
    echo
    echo "Run the CLI:"
    echo "  ./monitor-brightness.sh --list"
    echo
    echo "If ddcutil works only with sudo, check:"
    echo "  ddcutil environment"
    echo "Then verify your user has read/write access to the relevant /dev/i2c-* device."
}

main "$@"
