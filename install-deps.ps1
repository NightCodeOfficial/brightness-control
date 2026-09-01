#Requires -Version 5.1

$ErrorActionPreference = "Stop"

$ProjectRoot = $PSScriptRoot
$VenvPath = Join-Path $ProjectRoot ".venv"
$RequirementsFile = Join-Path $ProjectRoot "requirements.txt"

function Write-Step {
    param([string]$Message)
    Write-Host "==> $Message" -ForegroundColor Cyan
}

function Test-PythonCommand {
    param([string]$Command)

    try {
        $version = & $Command -c "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}')" 2>$null
        return [bool]$version
    }
    catch {
        return $false
    }
}

function Get-PythonCommand {
    $candidates = @("python", "py -3", "py")

    foreach ($candidate in $candidates) {
        $parts = $candidate -split " "
        $exe = $parts[0]
        $args = @()
        if ($parts.Count -gt 1) {
            $args = $parts[1..($parts.Count - 1)]
        }

        try {
            if ($args.Count -gt 0) {
                $null = & $exe @args -c "import sys; raise SystemExit(0 if sys.version_info >= (3, 9) else 1)" 2>$null
                if ($LASTEXITCODE -eq 0) {
                    return @{ Exe = $exe; Args = $args }
                }
            }
            else {
                $null = & $exe -c "import sys; raise SystemExit(0 if sys.version_info >= (3, 9) else 1)" 2>$null
                if ($LASTEXITCODE -eq 0) {
                    return @{ Exe = $exe; Args = @() }
                }
            }
        }
        catch {
            continue
        }
    }

    return $null
}

function Install-Python {
    Write-Step "Python 3.9+ not found. Attempting install..."

    if (Get-Command winget -ErrorAction SilentlyContinue) {
        Write-Step "Installing Python via winget"
        winget install --id Python.Python.3.12 -e --accept-source-agreements --accept-package-agreements
        $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "User")
        return
    }

    throw @"
Python 3.9+ is required but was not found.

Install Python manually from https://www.python.org/downloads/
or install winget and re-run this script.
"@
}

function Invoke-Python {
    param(
        [hashtable]$Python,
        [string[]]$PythonArgs
    )

    if ($Python.Args.Count -gt 0) {
        & $Python.Exe @($Python.Args + $PythonArgs)
    }
    else {
        & $Python.Exe @PythonArgs
    }

    if ($LASTEXITCODE -ne 0) {
        throw "Python command failed: $($Python.Exe) $($PythonArgs -join ' ')"
    }
}

Write-Step "Checking for Python"
$python = Get-PythonCommand

if (-not $python) {
    Install-Python
    $python = Get-PythonCommand
}

if (-not $python) {
    throw "Python is still not available. Open a new terminal after installing Python, then re-run this script."
}

Write-Step "Using Python via $($python.Exe) $($python.Args -join ' ')"

if (-not (Test-Path $VenvPath)) {
    Write-Step "Creating virtual environment at .venv"
    Invoke-Python -Python $python -PythonArgs @("-m", "venv", $VenvPath)
}
else {
    Write-Step "Virtual environment already exists at .venv"
}

$venvPython = Join-Path $VenvPath "Scripts\python.exe"
if (-not (Test-Path $venvPython)) {
    throw "Virtual environment creation failed. Expected: $venvPython"
}

Write-Step "Upgrading pip"
& $venvPython -m pip install --upgrade pip

if (Test-Path $RequirementsFile) {
    Write-Step "Installing Python dependencies from requirements.txt"
    & $venvPython -m pip install -r $RequirementsFile
}

Write-Host ""
Write-Host "Setup complete." -ForegroundColor Green
Write-Host ""
Write-Host "Activate the virtual environment:"
Write-Host "  .\.venv\Scripts\Activate.ps1"
Write-Host ""
Write-Host "Windows GUI (PowerShell, no venv needed):"
Write-Host "  .\MonitorBrightnessGUI.ps1"
Write-Host ""
Write-Host "CLI:"
Write-Host "  .\MonitorBrightness.ps1 -List"
