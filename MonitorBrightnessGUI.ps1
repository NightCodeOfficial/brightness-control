Add-Type @"
using System;
using System.Runtime.InteropServices;
using System.Collections.Generic;

public class MonitorControl
{
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Auto)]
    public struct PHYSICAL_MONITOR
    {
        public IntPtr hPhysicalMonitor;

        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)]
        public string szPhysicalMonitorDescription;
    }

    public delegate bool MonitorEnumProc(
        IntPtr hMonitor,
        IntPtr hdcMonitor,
        IntPtr lprcMonitor,
        IntPtr dwData
    );

    [DllImport("user32.dll")]
    public static extern bool EnumDisplayMonitors(
        IntPtr hdc,
        IntPtr lprcClip,
        MonitorEnumProc lpfnEnum,
        IntPtr dwData
    );

    [DllImport("dxva2.dll", SetLastError = true)]
    public static extern bool GetNumberOfPhysicalMonitorsFromHMONITOR(
        IntPtr hMonitor,
        out uint pdwNumberOfPhysicalMonitors
    );

    [DllImport("dxva2.dll", SetLastError = true)]
    public static extern bool GetPhysicalMonitorsFromHMONITOR(
        IntPtr hMonitor,
        uint dwPhysicalMonitorArraySize,
        [Out] PHYSICAL_MONITOR[] pPhysicalMonitorArray
    );

    [DllImport("dxva2.dll", SetLastError = true)]
    public static extern bool DestroyPhysicalMonitor(
        IntPtr hMonitor
    );

    [DllImport("dxva2.dll", SetLastError = true)]
    public static extern bool GetMonitorBrightness(
        IntPtr hMonitor,
        out uint pdwMinimumBrightness,
        out uint pdwCurrentBrightness,
        out uint pdwMaximumBrightness
    );

    [DllImport("dxva2.dll", SetLastError = true)]
    public static extern bool SetMonitorBrightness(
        IntPtr hMonitor,
        uint dwNewBrightness
    );

    [DllImport("dxva2.dll", SetLastError = true)]
    public static extern bool GetVCPFeatureAndVCPFeatureReply(
        IntPtr hMonitor,
        byte bVCPCode,
        out uint pvct,
        out uint pdwCurrentValue,
        out uint pdwMaximumValue
    );

    [DllImport("dxva2.dll", SetLastError = true)]
    public static extern bool SetVCPFeature(
        IntPtr hMonitor,
        byte bVCPCode,
        uint dwNewValue
    );

    public static PHYSICAL_MONITOR[] GetPhysicalMonitors()
    {
        List<PHYSICAL_MONITOR> monitors = new List<PHYSICAL_MONITOR>();

        MonitorEnumProc callback = delegate(IntPtr hMonitor, IntPtr hdcMonitor, IntPtr lprcMonitor, IntPtr dwData)
        {
            uint count;
            if (GetNumberOfPhysicalMonitorsFromHMONITOR(hMonitor, out count))
            {
                PHYSICAL_MONITOR[] physicalMonitors = new PHYSICAL_MONITOR[count];

                if (GetPhysicalMonitorsFromHMONITOR(hMonitor, count, physicalMonitors))
                {
                    monitors.AddRange(physicalMonitors);
                }
            }

            return true;
        };

        EnumDisplayMonitors(IntPtr.Zero, IntPtr.Zero, callback, IntPtr.Zero);

        return monitors.ToArray();
    }
}
"@

function Get-ExternalMonitors {
    $monitors = [MonitorControl]::GetPhysicalMonitors()

    for ($i = 0; $i -lt $monitors.Count; $i++) {
        $min = 0
        $cur = 0
        $max = 0

        $brightnessSupported = [MonitorControl]::GetMonitorBrightness(
            $monitors[$i].hPhysicalMonitor,
            [ref]$min,
            [ref]$cur,
            [ref]$max
        )

        if (-not $brightnessSupported) {
            $type = 0
            $curVcp = 0
            $maxVcp = 0

            $brightnessSupported = [MonitorControl]::GetVCPFeatureAndVCPFeatureReply(
                $monitors[$i].hPhysicalMonitor,
                0x10,
                [ref]$type,
                [ref]$curVcp,
                [ref]$maxVcp
            )

            if ($brightnessSupported) {
                $cur = $curVcp
                $max = $maxVcp
                $min = 0
            }
        }

        [PSCustomObject]@{
            Index = $i
            Name = $monitors[$i].szPhysicalMonitorDescription
            BrightnessSupported = [bool]$brightnessSupported
            CurrentBrightness = if ($brightnessSupported) { $cur } else { $null }
            MinBrightness = if ($brightnessSupported) { $min } else { $null }
            MaxBrightness = if ($brightnessSupported) { $max } else { $null }
        }
    }

    foreach ($monitor in $monitors) {
        [MonitorControl]::DestroyPhysicalMonitor($monitor.hPhysicalMonitor) | Out-Null
    }
}

function Set-ExternalMonitorBrightness {
    param(
        [Parameter(Mandatory)]
        [int]$MonitorIndex,

        [Parameter(Mandatory)]
        [ValidateRange(0, 100)]
        [int]$Brightness
    )

    $monitors = [MonitorControl]::GetPhysicalMonitors()

    if ($MonitorIndex -lt 0 -or $MonitorIndex -ge $monitors.Count) {
        throw "Invalid monitor index."
    }

    $monitor = $monitors[$MonitorIndex]

    $min = 0
    $cur = 0
    $max = 0

    $usedHighLevelApi = [MonitorControl]::GetMonitorBrightness(
        $monitor.hPhysicalMonitor,
        [ref]$min,
        [ref]$cur,
        [ref]$max
    )

    if ($usedHighLevelApi) {
        $scaledBrightness = [uint32]($min + (($max - $min) * ($Brightness / 100.0)))

        $success = [MonitorControl]::SetMonitorBrightness(
            $monitor.hPhysicalMonitor,
            $scaledBrightness
        )
    }
    else {
        $success = [MonitorControl]::SetVCPFeature(
            $monitor.hPhysicalMonitor,
            0x10,
            [uint32]$Brightness
        )
    }

    foreach ($m in $monitors) {
        [MonitorControl]::DestroyPhysicalMonitor($m.hPhysicalMonitor) | Out-Null
    }

    if (-not $success) {
        throw "Failed to set brightness."
    }
}

function Get-BrightnessPercent {
    param(
        [int]$Current,
        [int]$Minimum,
        [int]$Maximum
    )

    if ($Maximum -le $Minimum) {
        return [int]$Current
    }

    return [int][Math]::Round((($Current - $Minimum) / ($Maximum - $Minimum)) * 100)
}

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$form = New-Object System.Windows.Forms.Form
$form.Text = "Monitor Brightness"
$form.ClientSize = New-Object System.Drawing.Size(420, 150)
$form.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedDialog
$form.MaximizeBox = $false
$form.StartPosition = [System.Windows.Forms.FormStartPosition]::CenterScreen

$monitorLabel = New-Object System.Windows.Forms.Label
$monitorLabel.Text = "Monitor"
$monitorLabel.Location = New-Object System.Drawing.Point(16, 18)
$monitorLabel.AutoSize = $true

$monitorCombo = New-Object System.Windows.Forms.ComboBox
$monitorCombo.Location = New-Object System.Drawing.Point(90, 14)
$monitorCombo.Size = New-Object System.Drawing.Size(230, 24)
$monitorCombo.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList

$refreshButton = New-Object System.Windows.Forms.Button
$refreshButton.Text = "Refresh"
$refreshButton.Location = New-Object System.Drawing.Point(330, 12)
$refreshButton.Size = New-Object System.Drawing.Size(75, 28)

$brightnessLabel = New-Object System.Windows.Forms.Label
$brightnessLabel.Text = "Brightness"
$brightnessLabel.Location = New-Object System.Drawing.Point(16, 58)
$brightnessLabel.AutoSize = $true

$brightnessValueLabel = New-Object System.Windows.Forms.Label
$brightnessValueLabel.Text = "50%"
$brightnessValueLabel.Location = New-Object System.Drawing.Point(370, 58)
$brightnessValueLabel.AutoSize = $true

$brightnessTrack = New-Object System.Windows.Forms.TrackBar
$brightnessTrack.Location = New-Object System.Drawing.Point(90, 52)
$brightnessTrack.Size = New-Object System.Drawing.Size(270, 45)
$brightnessTrack.Minimum = 0
$brightnessTrack.Maximum = 100
$brightnessTrack.TickFrequency = 10
$brightnessTrack.Value = 50

$statusLabel = New-Object System.Windows.Forms.Label
$statusLabel.Text = ""
$statusLabel.Location = New-Object System.Drawing.Point(16, 110)
$statusLabel.Size = New-Object System.Drawing.Size(390, 20)
$statusLabel.ForeColor = [System.Drawing.Color]::Gray

$form.Controls.AddRange(@(
    $monitorLabel,
    $monitorCombo,
    $refreshButton,
    $brightnessLabel,
    $brightnessValueLabel,
    $brightnessTrack,
    $statusLabel
))

$script:isUpdating = $false
$script:monitors = @()

function Update-BrightnessLabel {
    param([int]$Value)
    $brightnessValueLabel.Text = "$Value%"
}

function Set-Status {
    param([string]$Text, [string]$Color = "Gray")
    $statusLabel.Text = $Text
    $statusLabel.ForeColor = [System.Drawing.Color]::$Color
}

function Get-SelectedMonitor {
    if ($monitorCombo.SelectedIndex -lt 0) {
        return $null
    }

    return $script:monitors[$monitorCombo.SelectedIndex]
}

function Load-Monitors {
    $script:isUpdating = $true

    try {
        $monitorCombo.Items.Clear()
        $script:monitors = @(Get-ExternalMonitors)

        if ($script:monitors.Count -eq 0) {
            Set-Status "No DDC/CI-capable monitors detected." "DarkRed"
            $brightnessTrack.Enabled = $false
            return
        }

        foreach ($monitor in $script:monitors) {
            $label = if ($monitor.BrightnessSupported) {
                "$($monitor.Name)"
            }
            else {
                "$($monitor.Name) (brightness not supported)"
            }

            [void]$monitorCombo.Items.Add($label)
        }

        $monitorCombo.SelectedIndex = 0
        Set-Status "Found $($script:monitors.Count) monitor(s)."
    }
    catch {
        Set-Status $_.Exception.Message "DarkRed"
        $brightnessTrack.Enabled = $false
    }
    finally {
        $script:isUpdating = $false
    }
}

function Sync-SliderToMonitor {
    $selected = Get-SelectedMonitor
    if ($null -eq $selected) {
        return
    }

    $script:isUpdating = $true

    try {
        if (-not $selected.BrightnessSupported) {
            $brightnessTrack.Enabled = $false
            Set-Status "Selected monitor does not support brightness control." "DarkOrange"
            return
        }

        $brightnessTrack.Enabled = $true
        $percent = Get-BrightnessPercent `
            -Current $selected.CurrentBrightness `
            -Minimum $selected.MinBrightness `
            -Maximum $selected.MaxBrightness

        $brightnessTrack.Value = [Math]::Max(
            $brightnessTrack.Minimum,
            [Math]::Min($brightnessTrack.Maximum, $percent)
        )
        Update-BrightnessLabel -Value $brightnessTrack.Value
        Set-Status "Showing brightness for $($selected.Name)."
    }
    finally {
        $script:isUpdating = $false
    }
}

function Apply-Brightness {
    param([int]$Value)

    $selected = Get-SelectedMonitor
    if ($null -eq $selected -or -not $selected.BrightnessSupported) {
        return
    }

    try {
        Set-ExternalMonitorBrightness -MonitorIndex $selected.Index -Brightness $Value
        Update-BrightnessLabel -Value $Value
        Set-Status "Brightness set to $Value% on $($selected.Name)."
    }
    catch {
        Set-Status $_.Exception.Message "DarkRed"
    }
}

$monitorCombo.Add_SelectedIndexChanged({
    if ($script:isUpdating) { return }
    Sync-SliderToMonitor
})

$refreshButton.Add_Click({
    Load-Monitors
    Sync-SliderToMonitor
})

$brightnessTrack.Add_Scroll({
    if ($script:isUpdating) { return }
    Apply-Brightness -Value $brightnessTrack.Value
})

Load-Monitors
Sync-SliderToMonitor

[void]$form.ShowDialog()
