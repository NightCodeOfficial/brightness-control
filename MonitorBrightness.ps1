
param(
    [ValidateRange(0, 100)]
    [int]$Brightness = 50,

    [int]$MonitorIndex = 1,

    [switch]$List
)


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

            # VCP code 0x10 is brightness in DDC/CI.
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
        throw "Invalid monitor index. Use Get-ExternalMonitors to see available indexes."
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
        # Fallback to DDC/CI VCP brightness code 0x10.
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
        throw "Failed to set brightness. The monitor may not support DDC/CI brightness control, or DDC/CI may be disabled in the monitor menu."
    }
}

if ($List) {
    Get-ExternalMonitors
}
else {
    Set-ExternalMonitorBrightness -MonitorIndex $MonitorIndex -Brightness $Brightness
}