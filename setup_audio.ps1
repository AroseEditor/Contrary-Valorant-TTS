#Requires -Version 5.1
<#
.SYNOPSIS
    Contrary Valorant TTS - Audio Setup
    Installs VB-Cable, renames to "Contrary TTS", sets as default playback,
    and installs Indian English + Hindi speech voices.
#>

# --- Self-elevate if not admin (registry writes require admin) ---------------
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    $argList = "-ExecutionPolicy Bypass -File `"$PSCommandPath`""
    Start-Process powershell.exe -ArgumentList $argList -Verb RunAs
    exit
}

$ErrorActionPreference = "Continue"
$VBInput  = "Contrary TTS"
$VBOutput = "Contrary TTS Output"

# --- Compile IPolicyConfig (SetDefaultEndpoint only) -------------------------
$PolicyCS = @"
using System;
using System.Runtime.InteropServices;

[Guid("f8679f50-850a-41cf-9c72-430f290290c8")]
[InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
interface IPolicyConfig {
    int N1();
    int N2();
    int N3();
    int N4();
    int N5();
    int N6();
    int N7();
    int N8();
    int N9();
    int N10();
    int SetDefaultEndpoint([MarshalAs(UnmanagedType.LPWStr)] string devId, int role);
    int N11();
}

public static class DefaultDevice {
    static readonly Guid CLSID = new Guid("870af99c-171d-4f9e-af0d-e63df40c2bc9");
    public static bool SetDefault(string deviceId) {
        try {
            object obj = Activator.CreateInstance(Type.GetTypeFromCLSID(CLSID));
            IPolicyConfig p = (IPolicyConfig)obj;
            p.SetDefaultEndpoint(deviceId, 0);
            p.SetDefaultEndpoint(deviceId, 1);
            p.SetDefaultEndpoint(deviceId, 2);
            return true;
        } catch { return false; }
    }
}
"@

$policyOk = $false
try {
    Add-Type -TypeDefinition $PolicyCS -Language CSharp -ErrorAction Stop
    $policyOk = $true
} catch {
    Write-Warning "IPolicyConfig compile failed: $_"
}

# --- Helpers -----------------------------------------------------------------
function Write-Step([string]$m) { Write-Host "" ; Write-Host "[>>] $m" -ForegroundColor Cyan }
function Write-OK([string]$m)   { Write-Host " [OK] $m" -ForegroundColor Green }
function Write-Warn([string]$m) { Write-Host " [!!] $m" -ForegroundColor Yellow }
function Write-Fail([string]$m) { Write-Host " [XX] $m" -ForegroundColor Red }

$RenderReg  = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\MMDevices\Audio\Render"
$CaptureReg = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\MMDevices\Audio\Capture"
$NameProp   = "{a45c254e-df1c-4efd-8020-67d146a850e0},14"

function Get-AudioDeviceKey([string]$basePath, [string]$substr) {
    if (-not (Test-Path $basePath)) { return $null }
    $keys = Get-ChildItem $basePath -ErrorAction SilentlyContinue
    foreach ($key in $keys) {
        $propsPath = Join-Path $key.PSPath "Properties"
        $props = Get-ItemProperty -LiteralPath $propsPath -ErrorAction SilentlyContinue
        if ($props -and $props.PSObject.Properties[$NameProp]) {
            $name = $props.$NameProp
            if ($name -and $name -like "*$substr*") { return $key }
        }
    }
    return $null
}

function Rename-AudioDevice([string]$basePath, [string]$substr, [string]$newName) {
    $key = Get-AudioDeviceKey $basePath $substr
    if (-not $key) { return $false }
    $propsPath = Join-Path $key.PSPath "Properties"
    try {
        Set-ItemProperty -LiteralPath $propsPath -Name $NameProp -Value $newName -ErrorAction Stop
        return $true
    } catch {
        Write-Warn "  Rename failed: $_"
        return $false
    }
}

# Build endpoint ID from registry key GUID name
# Format: {0.0.0.00000000}.{GUID} for render,  {0.0.1.00000000}.{GUID} for capture
function Get-EndpointId([string]$basePath, [string]$flowPrefix, [string]$substr) {
    $key = Get-AudioDeviceKey $basePath $substr
    if (-not $key) { return $null }
    # Key name is the GUID, e.g. {ab12cd34-...}
    $guid = $key.PSChildName
    return "$flowPrefix.$guid"
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
        Write-Warn "Install VB-Cable manually: https://vb-audio.com/Cable/"
        exit 1
    }

    Write-Step "Extracting..."
    Expand-Archive -Path $zipPath -DestinationPath $tmpDir -Force
    Write-OK "Extracted."

    $exeFile = Get-ChildItem $tmpDir -Recurse -Filter "VBCABLE_Setup_x64.exe" |
               Select-Object -First 1
    if (-not $exeFile) { Write-Fail "Setup exe not found in archive."; exit 1 }

    Write-Step "Installing VB-Cable driver (UAC may appear)..."
    # Already admin, run directly
    $proc = Start-Process $exeFile.FullName -ArgumentList "/S" -PassThru -Wait
    Write-OK "Driver install complete (exit $($proc.ExitCode))."

    Write-Step "Waiting for device to appear in registry..."
    for ($i = 0; $i -lt 12; $i++) {
        Start-Sleep 2
        $cableKey = Get-AudioDeviceKey $RenderReg "CABLE"
        if ($cableKey) { Write-OK "Device detected."; break }
    }
    if (-not $cableKey) { Write-Warn "Device not yet visible. A reboot may be required." }
}

# --- Step 2: Rename via registry ---------------------------------------------
Write-Step "Renaming audio devices..."

$ok = Rename-AudioDevice $RenderReg "CABLE Input" $VBInput
if (-not $ok) { $ok = Rename-AudioDevice $RenderReg "CABLE" $VBInput }
if ($ok)  { Write-OK "Playback renamed to '$VBInput'." }
else      { Write-Warn "Could not rename playback device." }

$ok2 = Rename-AudioDevice $CaptureReg "CABLE Output" $VBOutput
if (-not $ok2) { $ok2 = Rename-AudioDevice $CaptureReg "CABLE" $VBOutput }
if ($ok2) { Write-OK "Recording renamed to '$VBOutput'." }
else      { Write-Warn "Could not rename recording device." }

# --- Step 3: Set as default playback -----------------------------------------
Write-Step "Setting '$VBInput' as default playback..."

if ($policyOk) {
    # Try renamed name first, then CABLE fallback
    $endpointId = Get-EndpointId $RenderReg "{0.0.0.00000000}" $VBInput
    if (-not $endpointId) {
        $endpointId = Get-EndpointId $RenderReg "{0.0.0.00000000}" "CABLE"
    }
    if ($endpointId) {
        $ok3 = [DefaultDevice]::SetDefault($endpointId)
        if ($ok3) { Write-OK "Default playback set to '$VBInput'." }
        else      { Write-Warn "SetDefaultEndpoint failed - set manually in Sound Settings." }
    } else {
        Write-Warn "Device not found - set default manually in Sound Settings."
    }
} else {
    Write-Warn "Policy COM not available - set default manually in Sound Settings."
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
        Write-Warn "$($pack.Label) - add via Settings, Time and Language, Language."
    }
}

# --- Done --------------------------------------------------------------------
Write-Host ""
Write-Host "========================================"  -ForegroundColor Magenta
Write-Host "  Contrary TTS Audio Setup Complete"      -ForegroundColor Magenta
Write-Host "========================================"  -ForegroundColor Magenta
Write-Host "  Playback : Contrary TTS"                -ForegroundColor White
Write-Host "  Mic Out  : Contrary TTS Output"         -ForegroundColor White
Write-Host "  Valorant : Settings, Audio, Input, Contrary TTS" -ForegroundColor Gray
Write-Host "========================================"  -ForegroundColor Magenta
exit 0
