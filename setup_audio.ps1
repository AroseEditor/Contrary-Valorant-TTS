#Requires -Version 5.1
<#
.SYNOPSIS
    Contrary Valorant TTS - Audio Setup (Hinglish Force Mode)
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
$possiblePaths = @(
    (Get-Process "ContraryValorantTTS" -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty Path),
    (Join-Path $PSScriptRoot "ContraryValorantTTS.exe"),
    (Join-Path $env:LOCALAPPDATA "ContraryValorantTTS\ContraryValorantTTS.exe")
)
$exe = $null
foreach ($p in $possiblePaths) { if ($p -and (Test-Path $p)) { $exe = $p; break } }

if ($exe) {
    Write-Step "Renaming devices via Native Helper..."
    Start-Process -FilePath $exe -ArgumentList "--setup-audio" -Wait -NoNewWindow
    Write-OK "Native setup completed."
}

# --- Step 2: Hinglish Force -------------------------------------------------
Write-Step "Forcing Hinglish Voice Packs..."

# 1. Diagnostic: Find anything India related
$allCaps = Get-WindowsCapability -Online
$indiaCaps = $allCaps | Where-Object { $_.Name -like "*en-IN*" -or $_.Name -like "*hi-IN*" }

if ($indiaCaps) {
    foreach ($cap in $indiaCaps) {
        if ($cap.State -eq "Installed") {
            Write-OK "Already Installed: $($cap.Name)"
        } else {
            Write-Step "Installing $($cap.Name)..."
            Add-WindowsCapability -Online -Name $cap.Name > $null
            Write-OK "Done."
        }
    }
} else {
    Write-Warn "No India-specific capabilities found. Attempting direct DISM injection..."
    # Fallback to direct DISM names (standard on Win 10/11)
    $manual = @("Language.Speech.en-IN~~~~0.0.1.0", "Language.Speech.hi-IN~~~~0.0.1.0", "Language.TextToSpeech.en-IN~~~~0.0.1.0")
    foreach ($m in $manual) {
        Write-Step "Trying $m..."
        dism.exe /online /add-capability /capabilityname:$m /quiet /norestart
    }
}

Write-Step "Setup complete."
Start-Sleep 2
exit 0
