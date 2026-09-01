# Monitor Brightness Controller

Control external monitor brightness from the command line or a simple GUI using DDC/CI. Works on Windows (PowerShell) and Linux (Bash/Python + `ddcutil`).

## Requirements

### Windows

- Windows 10 or later
- PowerShell 5.1+ (included with Windows)
- External monitor with DDC/CI enabled in its on-screen menu

### Linux

- [ddcutil](https://www.ddcutil.com/) installed and configured
- External monitor with DDC/CI enabled
- User must be in the `i2c` group (or run with appropriate permissions)
- GUI only: Python 3 with Tkinter (`python3-tk` on Debian/Ubuntu)

Install `ddcutil`:

```bash
# Debian / Ubuntu
sudo apt install ddcutil

# Fedora
sudo dnf install ddcutil

# Arch
sudo pacman -S ddcutil
```

Add your user to the `i2c` group (log out and back in afterward):

```bash
sudo usermod -aG i2c "$USER"
```

## Installation

Run the dependency installer for your platform. It will install Python if missing, create a `.venv` in the project root, and install any pip packages from `requirements.txt`.

**Windows:**

```powershell
.\install-deps.ps1
```

**Linux:**

```bash
chmod +x install-deps.sh
./install-deps.sh
```

The Linux installer also attempts to install `ddcutil`, `python3-tk`, and other system packages via your package manager.

Activate the virtual environment after setup:

```powershell
# Windows
.\.venv\Scripts\Activate.ps1
```

```bash
# Linux
source .venv/bin/activate
```

## Usage

### GUI

Both GUI versions provide a monitor dropdown, a brightness slider (0–100), and a refresh button.

**Windows:**

```powershell
.\MonitorBrightnessGUI.ps1
```

**Linux:**

```bash
chmod +x monitor-brightness-gui.py   # first time only
./monitor-brightness-gui.py

# or with the project venv
.venv/bin/python monitor-brightness-gui.py
```

On Debian/Ubuntu, install Tkinter if needed (or run `./install-deps.sh`):

```bash
sudo apt install python3-tk
```

### List monitors

**Windows:**

```powershell
.\MonitorBrightness.ps1 -List
```

**Linux:**

```bash
chmod +x monitor-brightness.sh   # first time only
./monitor-brightness.sh --list
```

Example output:

```
Index Name                  BrightnessSupported CurrentBrightness MinBrightness MaxBrightness
----- ----                  ------------------- ----------------- ------------- -------------
    0 DELL U2720Q           True                               75             0           100
    1 LG HDR 4K             True                               50             0           100
```

### Set brightness

Set a monitor to a brightness level between 0 and 100. Monitor indexes are **zero-based** (0 = first monitor, 1 = second, etc.). The default index is `1` (second monitor).

**Windows:**

```powershell
# Set second monitor (index 1) to 75%
.\MonitorBrightness.ps1 -Brightness 75

# Set first monitor (index 0) to 30%
.\MonitorBrightness.ps1 -MonitorIndex 0 -Brightness 30
```

**Linux:**

```bash
# Set second monitor (index 1) to 75%
./monitor-brightness.sh --brightness 75

# Set first monitor (index 0) to 30%
./monitor-brightness.sh --monitor-index 0 --brightness 30
```

### Options

| Option | Windows | Linux | Default | Description |
|--------|---------|-------|---------|-------------|
| List monitors | `-List` | `--list` | — | Show all detected monitors and current brightness |
| Brightness | `-Brightness <0-100>` | `--brightness <0-100>` | `50` | Target brightness percentage |
| Monitor index | `-MonitorIndex <n>` | `--monitor-index <n>` | `1` | Zero-based monitor index |

## How it works

Both scripts control brightness over DDC/CI — the same protocol monitor buttons use internally.

- **Windows** uses the DXGI/DXVA2 APIs (`SetMonitorBrightness` with a fallback to VCP code `0x10`). The GUI is built with Windows Forms.
- **Linux** uses `ddcutil`, which sends DDC/CI commands over I2C. The GUI is a small Python/Tkinter app with no extra dependencies beyond `ddcutil`.

These scripts target **external monitors**. Laptop built-in displays use a separate backlight interface and are not covered here.

## Troubleshooting

**Brightness does not change**

- Enable DDC/CI in the monitor's OSD settings (wording varies by brand: "DDC/CI", "DDC", or "PC control").
- On Windows, some GPU drivers or docking stations block DDC/CI — try a direct DisplayPort or HDMI connection.
- On Linux, verify `ddcutil detect` sees your monitor and that you have I2C permissions.

**Monitor not listed**

- Only monitors that respond to DDC/CI are shown. Built-in laptop panels are excluded.
- Run `ddcutil detect` (Linux) or `-List` (Windows) to confirm detection.

**Linux: permission denied**

```bash
sudo ddcutil detect   # test with elevated permissions
```

If that works, add your user to the `i2c` group as described above.

## License

MIT
