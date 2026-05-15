#Requires -Version 5.1
<#
.SYNOPSIS
    Contrary Valorant TTS - Audio Setup (Robust Helper Search)
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
    (Join-Path $PSScriptRoot "Release\ContraryValorantTTS.exe"),
    (Join-Path $PSScriptRoot "x64\Release\ContraryValorantTTS.exe"),
    (Join-Path $env:LOCALAPPDATA "ContraryValorantTTS\ContraryValorantTTS.exe")
)

$exe = $null
foreach ($p in $possiblePaths) {
    if ($p -and (Test-Path $p)) { $exe = $p; break }
}

if ($exe) {
    Write-OK "Found: $exe"
} else {
    Write-Warn "ContraryTTS.exe not found. Ensure you have built the project."
}

# --- Step 2: Native Rename --------------------------------------------------
Write-Step "Renaming devices via Native Helper..."
if ($exe) {
    Start-Process -FilePath $exe -ArgumentList "--setup-audio" -Wait -NoNewWindow
    Write-OK "Native setup command completed."
} else {
    Write-Warn "Skipping native rename (executable missing)."
}

# --- Step 3: Voice Packs ----------------------------------------------------
Write-Step "Checking Speech Voice Packs..."
$voices = @("Language.Speech.en-IN", "Language.Speech.hi-IN")
foreach ($v in $voices) {
    $cap = Get-WindowsCapability -Online -Name "$v*" | Select-Object -First 1
    if ($null -eq $cap) {
        Write-Warn "Capability $v not found in Windows Update."
        continue
    }
    
    if ($cap.State -eq "Installed") {
        Write-OK "$v already present."
    } else {
        Write-Step "Installing $($cap.Name) (this may take a minute)..."
        try {
            Add-WindowsCapability -Online -Name $cap.Name -ErrorAction Stop > $null
            Write-OK "Successfully installed."
        } catch {
            Write-Warn "Failed to install $v. Please check internet connection."
        }
    }
}

Write-Step "Setup complete."
Start-Sleep 2
exit 0
