#!/usr/bin/env bash
#
# Install Python, create a project venv, and install pip dependencies.

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VENV_PATH="$PROJECT_ROOT/.venv"
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
            sudo apt-get install -y python3 python3-venv python3-tk python3-pip ddcutil
            ;;
        dnf)
            step "Installing system packages via dnf"
            sudo dnf install -y python3 python3-tkinter python3-pip ddcutil
            ;;
        pacman)
            step "Installing system packages via pacman"
            sudo pacman -Sy --needed python python-tkinter python-pip ddcutil
            ;;
        *)
            step "No supported package manager found; skipping system package install"
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

ensure_python() {
    if find_python >/dev/null; then
        return 0
    fi

    step "Python 3.9+ not found. Attempting install..."
    install_system_packages

    if ! find_python >/dev/null; then
        echo "Error: Python 3.9+ is still not available after install attempt." >&2
        echo "Install python3 manually, then re-run this script." >&2
        exit 1
    fi
}

ensure_tkinter() {
    local python_cmd
    python_cmd="$(find_python)"

    if "$python_cmd" -c "import tkinter" 2>/dev/null; then
        return 0
    fi

    step "Tkinter not found. Installing system Tk packages..."
    install_system_packages

    if ! "$python_cmd" -c "import tkinter" 2>/dev/null; then
        echo "Warning: Tkinter is still unavailable. The GUI may not run." >&2
        echo "On Debian/Ubuntu, try: sudo apt install python3-tk" >&2
    fi
}

ensure_ddcutil() {
    if command_exists ddcutil; then
        return 0
    fi

    step "ddcutil not found. Installing..."
    install_system_packages

    if ! command_exists ddcutil; then
        echo "Warning: ddcutil is still not available. CLI/GUI brightness control will not work." >&2
    fi
}

main() {
    cd "$PROJECT_ROOT"

    ensure_python
    ensure_tkinter
    ensure_ddcutil

    local python_cmd
    python_cmd="$(find_python)"

    step "Using $("$python_cmd" --version)"

    if [[ ! -d "$VENV_PATH" ]]; then
        step "Creating virtual environment at .venv"
        "$python_cmd" -m venv "$VENV_PATH"
    else
        step "Virtual environment already exists at .venv"
    fi

    local venv_python="$VENV_PATH/bin/python"
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
    echo "Setup complete."
    echo
    echo "Activate the virtual environment:"
    echo "  source .venv/bin/activate"
    echo
    echo "Run the Linux GUI:"
    echo "  .venv/bin/python monitor-brightness-gui.py"
    echo
    echo "Run the CLI:"
    echo "  ./monitor-brightness.sh --list"
    echo
    echo "If ddcutil needs I2C permissions:"
    echo "  sudo usermod -aG i2c \"\$USER\""
    echo "  (log out and back in afterward)"
}

main "$@"
