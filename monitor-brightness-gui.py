#!/usr/bin/env python3
"""GUI for controlling external monitor brightness via ddcutil on Linux."""

from __future__ import annotations

import re
import shutil
import subprocess
import sys
import tkinter as tk
from dataclasses import dataclass
from tkinter import messagebox, ttk


@dataclass
class Monitor:
    index: int
    display: int
    name: str
    brightness_supported: bool
    current_brightness: int | None = None
    min_brightness: int = 0
    max_brightness: int = 100


def require_ddcutil() -> None:
    if shutil.which("ddcutil") is None:
        messagebox.showerror(
            "ddcutil not found",
            "ddcutil is required but not installed.\n\n"
            "Debian/Ubuntu: sudo apt install ddcutil\n"
            "Fedora:        sudo dnf install ddcutil\n"
            "Arch:          sudo pacman -S ddcutil",
        )
        sys.exit(1)


def run_ddcutil(*args: str) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        ["ddcutil", *args],
        capture_output=True,
        text=True,
        check=False,
    )


def command_error(result: subprocess.CompletedProcess[str]) -> str:
    details = (result.stderr or result.stdout).strip()
    if details:
        return details
    return f"ddcutil exited with status {result.returncode}."


def get_display_numbers() -> list[int]:
    result = run_ddcutil("detect", "--terse")
    if result.returncode != 0:
        raise RuntimeError(f"Unable to detect monitors: {command_error(result)}")

    displays: list[int] = []
    for line in result.stdout.splitlines():
        match = re.match(r"^Display\s+(\d+)\b", line)
        if match:
            displays.append(int(match.group(1)))

    return displays


def get_monitor_name(display: int) -> str:
    result = run_ddcutil("detect")
    if result.returncode != 0:
        return f"Display {display}"

    found = False
    for line in result.stdout.splitlines():
        if re.match(rf"^Display\s+{display}\s*$", line):
            found = True
            continue

        if found:
            match = re.match(r"^\s*Model:\s*(.+?)\s*$", line)
            if match:
                return match.group(1)

            if re.match(r"^Display\s+\d+\b", line):
                break

    return f"Display {display}"


def parse_terse_brightness(output: str) -> tuple[int, int] | None:
    """Parse ddcutil's continuous-feature terse format: VCP 10 C CUR MAX."""
    for line in output.splitlines():
        match = re.match(
            r"^\s*VCP\s+(?:0x)?10\s+C\s+(\d+)\s+(\d+)\b",
            line,
            flags=re.IGNORECASE,
        )
        if match:
            return int(match.group(1)), int(match.group(2))
    return None


def get_brightness(display: int) -> tuple[int, int] | None:
    result = run_ddcutil("--display", str(display), "getvcp", "10", "--terse")
    if result.returncode != 0:
        return None
    return parse_terse_brightness(result.stdout)


def brightness_to_percent(current: int, minimum: int, maximum: int) -> int:
    if maximum <= minimum:
        return max(0, min(100, current))
    return max(
        0,
        min(100, round(((current - minimum) / (maximum - minimum)) * 100)),
    )


def percent_to_monitor_value(percent: int, minimum: int, maximum: int) -> int:
    percent = max(0, min(100, percent))
    if maximum <= minimum:
        return percent
    return round(minimum + ((maximum - minimum) * (percent / 100.0)))


def list_monitors() -> list[Monitor]:
    monitors: list[Monitor] = []

    for index, display in enumerate(get_display_numbers()):
        name = get_monitor_name(display)
        brightness = get_brightness(display)

        if brightness is None:
            monitors.append(
                Monitor(
                    index=index,
                    display=display,
                    name=name,
                    brightness_supported=False,
                )
            )
            continue

        current, maximum = brightness
        monitors.append(
            Monitor(
                index=index,
                display=display,
                name=name,
                brightness_supported=True,
                current_brightness=current,
                min_brightness=0,
                max_brightness=maximum,
            )
        )

    return monitors


def set_brightness(display: int, percent: int, minimum: int, maximum: int) -> None:
    value = percent_to_monitor_value(percent, minimum, maximum)
    result = run_ddcutil("--display", str(display), "setvcp", "10", str(value))
    if result.returncode != 0:
        raise RuntimeError(
            "Failed to set brightness: "
            f"{command_error(result)}\n"
            "Check DDC/CI, I2C permissions, and the monitor connection."
        )


class MonitorBrightnessApp:
    def __init__(self, root: tk.Tk) -> None:
        self.root = root
        self.root.title("Monitor Brightness")
        self.root.resizable(False, False)

        self.monitors: list[Monitor] = []
        self.updating = False

        main = ttk.Frame(root, padding=16)
        main.grid(row=0, column=0, sticky="nsew")

        ttk.Label(main, text="Monitor").grid(row=0, column=0, sticky="w")
        self.monitor_var = tk.StringVar()
        self.monitor_combo = ttk.Combobox(
            main,
            textvariable=self.monitor_var,
            state="readonly",
            width=36,
        )
        self.monitor_combo.grid(row=0, column=1, padx=(12, 8), sticky="w")
        self.monitor_combo.bind("<<ComboboxSelected>>", self.on_monitor_changed)

        ttk.Button(main, text="Refresh", command=self.refresh_monitors).grid(
            row=0, column=2, sticky="e"
        )

        ttk.Label(main, text="Brightness").grid(row=1, column=0, sticky="w", pady=(16, 0))
        self.brightness_var = tk.IntVar(value=50)
        self.brightness_value = ttk.Label(main, text="50%")
        self.brightness_value.grid(row=1, column=2, sticky="e", pady=(16, 0))

        self.brightness_scale = ttk.Scale(
            main,
            from_=0,
            to=100,
            orient="horizontal",
            variable=self.brightness_var,
            command=self.on_brightness_changed,
            length=260,
        )
        self.brightness_scale.grid(row=1, column=1, padx=(12, 8), sticky="ew", pady=(16, 0))

        self.status_var = tk.StringVar(value="")
        ttk.Label(main, textvariable=self.status_var, wraplength=410).grid(
            row=2, column=0, columnspan=3, sticky="w", pady=(16, 0)
        )

        self.refresh_monitors()

    def selected_monitor(self) -> Monitor | None:
        index = self.monitor_combo.current()
        if index < 0 or index >= len(self.monitors):
            return None
        return self.monitors[index]

    def set_status(self, message: str) -> None:
        self.status_var.set(message)

    def refresh_monitors(self) -> None:
        self.updating = True

        try:
            try:
                self.monitors = list_monitors()
            except RuntimeError as exc:
                self.monitors = []
                self.monitor_combo["values"] = []
                self.monitor_combo.set("")
                self.brightness_scale.state(["disabled"])
                self.set_status(str(exc))
                return

            labels: list[str] = []

            for monitor in self.monitors:
                if monitor.brightness_supported:
                    labels.append(monitor.name)
                else:
                    labels.append(f"{monitor.name} (brightness not supported)")

            self.monitor_combo["values"] = labels

            if not self.monitors:
                self.monitor_combo.set("")
                self.brightness_scale.state(["disabled"])
                self.set_status(
                    "No DDC/CI-capable external monitors detected. "
                    "Run 'ddcutil detect' in a terminal for diagnostics."
                )
                return

            self.monitor_combo.current(0)
            self.set_status(f"Found {len(self.monitors)} monitor(s).")
            self.sync_slider_to_monitor()
        finally:
            self.updating = False

    def sync_slider_to_monitor(self) -> None:
        monitor = self.selected_monitor()
        if monitor is None:
            return

        self.updating = True

        try:
            if not monitor.brightness_supported:
                self.brightness_scale.state(["disabled"])
                self.set_status(
                    "Selected monitor did not return VCP brightness (0x10). "
                    "Check DDC/CI and try 'ddcutil getvcp 10' in a terminal."
                )
                return

            self.brightness_scale.state(["!disabled"])
            percent = brightness_to_percent(
                monitor.current_brightness or 0,
                monitor.min_brightness,
                monitor.max_brightness,
            )
            self.brightness_var.set(percent)
            self.brightness_value.config(text=f"{percent}%")
            self.set_status(f"Showing brightness for {monitor.name}.")
        finally:
            self.updating = False

    def on_monitor_changed(self, _event: object | None = None) -> None:
        if self.updating:
            return
        self.sync_slider_to_monitor()

    def on_brightness_changed(self, value: str) -> None:
        if self.updating:
            return

        percent = int(float(value))
        self.brightness_value.config(text=f"{percent}%")

        monitor = self.selected_monitor()
        if monitor is None or not monitor.brightness_supported:
            return

        try:
            set_brightness(
                monitor.display,
                percent,
                monitor.min_brightness,
                monitor.max_brightness,
            )
            monitor.current_brightness = percent_to_monitor_value(
                percent,
                monitor.min_brightness,
                monitor.max_brightness,
            )
            self.set_status(f"Brightness set to {percent}% on {monitor.name}.")
        except RuntimeError as exc:
            self.set_status(str(exc))


def main() -> None:
    require_ddcutil()

    root = tk.Tk()
    MonitorBrightnessApp(root)
    root.mainloop()


if __name__ == "__main__":
    main()
