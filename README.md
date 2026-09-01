# Monitor Brightness Controller

Control external monitor brightness from the command line or a simple GUI using DDC/CI. Works on Windows (PowerShell) and Linux (Bash/Python + `ddcutil`).

---

## Linux (quick start)

### 1. Install dependencies

From the project directory:

```bash
chmod +x install-deps.sh run-gui.sh monitor-brightness.sh monitor-brightness-gui.py
./install-deps.sh
```

This installs system packages (`python3`, `python3-tk`, `ddcutil`, and related tools) via your package manager. Enter your password if `sudo` asks.

### 2. Allow I2C access

`ddcutil` needs permission to talk to the monitor:

```bash
sudo usermod -aG i2c "$USER"
```

Log out and back in (or reboot), then confirm:

```bash
groups   # should list i2c
ddcutil detect
```

### 3. Run the GUI

```bash
./run-gui.sh
```

That script finds a usable Python venv (or creates one under `~/venvs/monitor-brightness` if the project lives on a VirtualBox/shared folder where `.venv` cannot be created), then launches the GUI.

### 4. Or use the CLI

```bash
# List monitors
./monitor-brightness.sh --list

# Set brightness (0–100). Default monitor index is 1 (second monitor).
./monitor-brightness.sh --brightness 75
./monitor-brightness.sh --monitor-index 0 --brightness 30
```

### Linux notes

- Enable **DDC/CI** in the monitor’s on-screen menu.
- Prefer a direct DisplayPort/HDMI cable; some docks block DDC/CI.
- If `./install-deps.sh` fails creating `.venv` with `Operation not permitted` on `lib64`, that is normal on VirtualBox shared folders. Use `./run-gui.sh` instead — it creates the venv in your home directory.
- Manual system packages (if you skip the installer):

```bash
# Debian / Ubuntu
sudo apt install python3 python3-venv python3-tk python3-pip ddcutil

# Fedora
sudo dnf install python3 python3-tkinter python3-pip ddcutil

# Arch
sudo pacman -S python python-tkinter python-pip ddcutil
```

---

## Windows

### Requirements

- Windows 10 or later
- PowerShell 5.1+ (included with Windows)
- External monitor with DDC/CI enabled in its on-screen menu

### Install

```powershell
.\install-deps.ps1
```

Optional: activate the venv afterward:

```powershell
.\.venv\Scripts\Activate.ps1
```

### Run

```powershell
# GUI
.\MonitorBrightnessGUI.ps1

# List monitors
.\MonitorBrightness.ps1 -List

# Set brightness
.\MonitorBrightness.ps1 -Brightness 75
.\MonitorBrightness.ps1 -MonitorIndex 0 -Brightness 30
```

---

## Options

| Option | Windows | Linux | Default | Description |
|--------|---------|-------|---------|-------------|
| List monitors | `-List` | `--list` | — | Show all detected monitors and current brightness |
| Brightness | `-Brightness <0-100>` | `--brightness <0-100>` | `50` | Target brightness percentage |
| Monitor index | `-MonitorIndex <n>` | `--monitor-index <n>` | `1` | Zero-based monitor index |

Example list output:

```
Index Name                  BrightnessSupported CurrentBrightness MinBrightness MaxBrightness
----- ----                  ------------------- ----------------- ------------- -------------
    0 DELL U2720Q           True                               75             0           100
    1 LG HDR 4K             True                               50             0           100
```

Monitor indexes are **zero-based** (0 = first monitor, 1 = second). Default index is `1`.

---

## How it works

Both scripts control brightness over DDC/CI — the same protocol monitor buttons use internally.

- **Windows** uses the DXGI/DXVA2 APIs (`SetMonitorBrightness` with a fallback to VCP code `0x10`). The GUI is built with Windows Forms.
- **Linux** uses `ddcutil`, which sends DDC/CI commands over I2C. The GUI is a small Python/Tkinter app with no extra pip packages beyond what `requirements.txt` lists (Tkinter comes from `python3-tk`).

These scripts target **external monitors**. Laptop built-in displays use a separate backlight interface and are not covered here.

---

## Troubleshooting

**Brightness does not change**

- Enable DDC/CI in the monitor’s OSD settings (wording varies: "DDC/CI", "DDC", or "PC control").
- On Windows, some GPU drivers or docking stations block DDC/CI — try a direct DisplayPort or HDMI connection.
- On Linux, verify `ddcutil detect` sees your monitor and that you have I2C permissions.

**Monitor not listed**

- Only monitors that respond to DDC/CI are shown. Built-in laptop panels are excluded.
- Run `ddcutil detect` (Linux) or `-List` (Windows) to confirm detection.

**Linux: permission denied**

```bash
sudo ddcutil detect   # test with elevated permissions
```

If that works, add your user to the `i2c` group (step 2 above) and log out/in.

**Linux: venv / `lib64` Operation not permitted**

Project is likely on a shared folder (e.g. VirtualBox). Do not rely on `.venv` in the project tree. Run:

```bash
./run-gui.sh
```

Override the fallback venv location if you want:

```bash
export MONITOR_BRIGHTNESS_VENV="$HOME/venvs/my-brightness"
./run-gui.sh
```

---

## License

MIT
