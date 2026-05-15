#Requires -Version 5.1
<#
.SYNOPSIS
    Contrary Valorant TTS - Audio Setup
    Installs VB-Cable, renames to "Contrary TTS", sets as default playback.
#>

$ErrorActionPreference = "Continue"
$VBInput  = "Contrary TTS"
$VBOutput = "Contrary TTS Output"

# --- Minimal IPolicyConfig (SetDefaultEndpoint only) -------------------------
$PolicyCS = @"
using System;
using System.Runtime.InteropServices;

[Guid("f8679f50-850a-41cf-9c72-430f290290c8")]
[InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
interface IPolicyConfig {
    int N01(); int N02(); int N03(); int N04(); int N05();
    int N06(); int N07(); int N08(); int N09(); int N10();
    int SetDefaultEndpoint([MarshalAs(UnmanagedType.LPWStr)] string devId, int role);
    int N11();
}

public static class DefaultDevice {
    static readonly Guid CLSID = new Guid("870af99c-171d-4f9e-af0d-e63df40c2bc9");
    public static bool SetDefault(string deviceId) {
        try {
            var t = Type.GetTypeFromCLSID(CLSID);
            var p = (IPolicyConfig)Activator.CreateInstance(t);
            p.SetDefaultEndpoint(deviceId, 0);
            p.SetDefaultEndpoint(deviceId, 1);
            p.SetDefaultEndpoint(deviceId, 2);
            return true;
        } catch { return false; }
    }
}
"@
Add-Type -TypeDefinition $PolicyCS -Language CSharp 2>$null

# --- Helpers -----------------------------------------------------------------
function Write-Step([string]$m) { Write-Host "`n[>>] $m" -ForegroundColor Cyan }
function Write-OK([string]$m)   { Write-Host " [OK] $m" -ForegroundColor Green }
function Write-Warn([string]$m) { Write-Host " [!!] $m" -ForegroundColor Yellow }
function Write-Fail([string]$m) { Write-Host " [XX] $m" -ForegroundColor Red }

$RenderReg  = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\MMDevices\Audio\Render"
$CaptureReg = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\MMDevices\Audio\Capture"
$NameProp   = "{a45c254e-df1c-4efd-8020-67d146a850e0},14"

function Get-AudioDeviceKey([string]$path, [string]$substr) {
    if (-not (Test-Path $path)) { return $null }
    foreach ($key in Get-ChildItem $path -ErrorAction SilentlyContinue) {
        $propsPath = "$($key.PSPath)\Properties"
        $props = Get-ItemProperty $propsPath -ErrorAction SilentlyContinue
        if ($props -and $props.$NameProp -and ($props.$NameProp -like "*$substr*")) {
            return $key
        }
    }
    return $null
}

function Rename-AudioDevice([string]$path, [string]$substr, [string]$newName) {
    $key = Get-AudioDeviceKey $path $substr
    if (-not $key) { return $false }
    try {
        Set-ItemProperty -Path "$($key.PSPath)\Properties" -Name $NameProp -Value $newName -ErrorAction Stop
        return $true
    } catch { return $false }
}

function Get-DeviceId([string]$path, [string]$substr) {
    $key = Get-AudioDeviceKey $path $substr
    if (-not $key) { return $null }
    $val = Get-ItemProperty $key.PSPath -ErrorAction SilentlyContinue
    if ($val -and $val.DeviceId) { return $val.DeviceId }
    return $null
}

# --- Step 1: Check / install VB-Cable ----------------------------------------
Write-Step "Checking for VB-Cable driver..."

$cableKey = Get-AudioDeviceKey $RenderReg "CABLE"
if (-not $cableKey) { $cableKey = Get-AudioDeviceKey $RenderReg "Contrary TTS" }

if ($cableKey) {
    Write-OK "VB-Cable already installed - skipping download."
} else {
    Write-Step "Downloading VB-Cable..."
    $tmpDir  = Join-Path $env:TEMP "VBCableSetup"
    $zipPath = Join-Path $tmpDir "VBCABLE_Driver_Pack43.zip"
    New-Item -ItemType Directory -Force -Path $tmpDir | Out-Null
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        Invoke-WebRequest -Uri "https://download.vb-audio.com/Download_CABLE/VBCABLE_Driver_Pack43.zip" `
                          -OutFile $zipPath -UseBasicParsing
        Write-OK "Downloaded."
    } catch {
        Write-Fail "Download failed: $_"
        Write-Warn "Install VB-Cable manually from https://vb-audio.com/Cable/"
        exit 1
    }

    Write-Step "Extracting..."
    Expand-Archive -Path $zipPath -DestinationPath $tmpDir -Force
    Write-OK "Extracted."

    $exeFile = Get-ChildItem $tmpDir -Recurse -Filter "VBCABLE_Setup_x64.exe" | Select-Object -First 1
    if (-not $exeFile) { Write-Fail "Setup exe not found in archive."; exit 1 }

    Write-Step "Installing VB-Cable driver (UAC prompt expected)..."
    $proc = Start-Process $exeFile.FullName -ArgumentList "/S" -Verb RunAs -PassThru -Wait
    if ($proc.ExitCode -ne 0) {
        Write-Warn "Exit code $($proc.ExitCode) - may still be OK."
    }
    Write-OK "Driver install complete."

    Write-Step "Waiting for device to appear..."
    for ($i = 0; $i -lt 10; $i++) {
        Start-Sleep 2
        $cableKey = Get-AudioDeviceKey $RenderReg "CABLE"
        if ($cableKey) { Write-OK "Device detected."; break }
    }
    if (-not $cableKey) { Write-Warn "Device not visible yet. Try rebooting." }
}

# --- Step 2: Rename via registry ---------------------------------------------
Write-Step "Renaming devices..."

$ok = Rename-AudioDevice $RenderReg "CABLE Input" $VBInput
if (-not $ok) { $ok = Rename-AudioDevice $RenderReg "CABLE" $VBInput }
if ($ok)  { Write-OK "Playback renamed to '$VBInput'." }
else      { Write-Warn "Could not rename playback device (may need admin or reboot)." }

$ok2 = Rename-AudioDevice $CaptureReg "CABLE Output" $VBOutput
if (-not $ok2) { $ok2 = Rename-AudioDevice $CaptureReg "CABLE" $VBOutput }
if ($ok2) { Write-OK "Recording renamed to '$VBOutput'." }
else      { Write-Warn "Could not rename recording device." }

# --- Step 3: Set as default playback -----------------------------------------
Write-Step "Setting '$VBInput' as default playback..."

$devId = Get-DeviceId $RenderReg $VBInput
if (-not $devId) { $devId = Get-DeviceId $RenderReg "CABLE" }

if ($devId) {
    $ok3 = [DefaultDevice]::SetDefault($devId)
    if ($ok3) { Write-OK "Default playback set." }
    else      { Write-Warn "SetDefaultEndpoint failed - set manually in Sound Settings." }
} else {
    Write-Warn "Could not find device ID - set default manually in Sound Settings."
}

# --- Step 4: Install Indian English + Hindi voices ---------------------------
Write-Step "Installing speech voice packs..."
$packs = @(
    @{ Name="Language.Speech~~~en-IN~0.0.1.0"; Label="Indian English (Heera/Ravi)" },
    @{ Name="Language.Speech~~~hi-IN~0.0.1.0"; Label="Hindi (Kalpana/Hemant)" }
)
foreach ($pack in $packs) {
    try {
        $cap = Get-WindowsCapability -Online -Name $pack.Name -ErrorAction SilentlyContinue
        if ($cap -and $cap.State -eq "Installed") {
            Write-OK "$($pack.Label) - already installed."
        } else {
            Add-WindowsCapability -Online -Name $pack.Name -ErrorAction Stop | Out-Null
            Write-OK "$($pack.Label) - installed."
        }
    } catch {
        Write-Warn "$($pack.Label) - install via Settings, Time and Language, Language."
    }
}

# --- Done --------------------------------------------------------------------
Write-Host ""
Write-Host "========================================" -ForegroundColor Magenta
Write-Host "  Contrary TTS Audio Setup Complete"     -ForegroundColor Magenta
Write-Host "========================================" -ForegroundColor Magenta
Write-Host "  Playback : Contrary TTS"               -ForegroundColor White
Write-Host "  Mic      : Contrary TTS Output"        -ForegroundColor White
Write-Host "  In Valorant: Settings, Audio, Input Device, Contrary TTS" -ForegroundColor Gray
Write-Host "========================================" -ForegroundColor Magenta
exit 0
