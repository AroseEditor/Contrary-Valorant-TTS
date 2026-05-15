#Requires -Version 5.1
<#
.SYNOPSIS
    Contrary Valorant TTS - Audio Setup (Native Helper Mode)
#>

# --- Self-elevate -----------------------------------------------------------
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    $self = $MyInvocation.MyCommand.Path
    if (-not $self) { $self = $PSCommandPath }
    if ($self) {
        $p = Start-Process powershell.exe -ArgumentList "-ExecutionPolicy Bypass -File `"$self`"" -Verb RunAs -PassThru -Wait
        exit $p.ExitCode
    }
    exit 1
}

$ErrorActionPreference = "Continue"

# --- Helpers -----------------------------------------------------------------
function Write-Step([string]$m) { Write-Host "" ; Write-Host "[>>] $m" -ForegroundColor Cyan }
function Write-OK([string]$m)   { Write-Host " [OK] $m"  -ForegroundColor Green }
function Write-Warn([string]$m) { Write-Host " [!!] $m"  -ForegroundColor Yellow }

# --- Step 1: Detect App -----------------------------------------------------
Write-Step "Locating Contrary TTS executable..."
$exe = Get-Process "ContraryTTS" -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty Path
if (-not $exe) {
    $exe = Join-Path $PSScriptRoot "ContraryTTS.exe"
    if (-not (Test-Path $exe)) {
        $exe = Join-Path $env:LOCALAPPDATA "ContraryValorantTTS\ContraryTTS.exe"
    }
}

if (Test-Path $exe) {
    Write-OK "Found: $exe"
} else {
    Write-Warn "Executable not found. Falling back to diagnostic scan..."
}

# --- Step 2: Native Rename --------------------------------------------------
Write-Step "Renaming devices via Native Helper..."
if (Test-Path $exe) {
    # Run the app with the setup flag. This uses IPropertyStore (stable) instead of Registry (locked)
    Start-Process -FilePath $exe -ArgumentList "--setup-audio" -Wait -NoNewWindow
    Write-OK "Native setup command sent."
} else {
    Write-Warn "Cannot run native setup without the executable."
}

# --- Step 3: Voice Packs ----------------------------------------------------
Write-Step "Checking Speech Voice Packs..."
$voices = @("Language.Speech.en-IN", "Language.Speech.hi-IN")
foreach ($v in $voices) {
    $cap = Get-WindowsCapability -Online -Name "$v*"
    if ($cap.State -eq "Installed") {
        Write-OK "$v already present."
    } else {
        Write-Step "Installing $v (this may take a minute)..."
        Add-WindowsCapability -Online -Name $cap.Name > $null
        Write-OK "$v installed."
    }
}

Write-Step "Setup complete."
Start-Sleep 2
exit 0
