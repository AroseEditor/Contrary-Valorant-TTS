#Requires -Version 5.1
<#
.SYNOPSIS
    Contrary Valorant TTS - Audio Setup
    Installs VB-Cable, renames to "Contrary TTS", sets as default playback,
    and installs Indian English + Hindi speech voices.
#>

# --- Self-elevate if not admin -----------------------------------------------
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    $self = $MyInvocation.MyCommand.Path
    if (-not $self) { $self = $PSCommandPath }
    if ($self) {
        Start-Process powershell.exe -ArgumentList "-ExecutionPolicy Bypass -File `"$self`"" -Verb RunAs
    }
    exit
}

$ErrorActionPreference = "Continue"
$VBInput  = "Contrary TTS"
$VBOutput = "Contrary TTS Output"

# --- IPolicyConfig (SetDefaultEndpoint only) ---------------------------------
$PolicyCS = @"
using System;
using System.Runtime.InteropServices;

[Guid("f8679f50-850a-41cf-9c72-430f290290c8")]
[InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
interface IPolicyConfig {
    int N1();  int N2();  int N3();  int N4();  int N5();
    int N6();  int N7();  int N8();  int N9();  int N10();
    int SetDefaultEndpoint([MarshalAs(UnmanagedType.LPWStr)] string devId, int role);
    int N11();
}

public static class DefaultDevice {
    static readonly Guid CLSID = new Guid("870af99c-171d-4f9e-af0d-e63df40c2bc9");
    public static bool SetDefault(string deviceId) {
        try {
            var p = (IPolicyConfig)Activator.CreateInstance(Type.GetTypeFromCLSID(CLSID));
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
    Write-Warning "IPolicyConfig compile failed (set-default will be manual): $_"
}

# --- Helpers -----------------------------------------------------------------
function Write-Step([string]$m) { Write-Host "" ; Write-Host "[>>] $m" -ForegroundColor Cyan }
function Write-OK([string]$m)   { Write-Host " [OK] $m"  -ForegroundColor Green }
function Write-Warn([string]$m) { Write-Host " [!!] $m"  -ForegroundColor Yellow }
function Write-Fail([string]$m) { Write-Host " [XX] $m"  -ForegroundColor Red }

$RenderReg  = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\MMDevices\Audio\Render"
$CaptureReg = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\MMDevices\Audio\Capture"
$NameProp   = "{a45c254e-df1c-4efd-8020-67d146a850e0},14"

# Fast detection via PnP (no registry enumeration hang)
function Test-VBCableInstalled() {
    $devs = Get-PnpDevice -Class AudioEndpoint -ErrorAction SilentlyContinue
    foreach ($d in $devs) {
        if ($d.FriendlyName -like "*CABLE*" -or $d.FriendlyName -like "*Contrary TTS*") {
            return $true
        }
    }
    return $false
}

# Use GetValue/SetValue to handle property names with commas correctly
function Get-MMDeviceName([string]$propsPath) {
    try {
        $item = Get-Item -LiteralPath $propsPath -ErrorAction SilentlyContinue
        if ($item) { return $item.GetValue($NameProp) }
    } catch {}
    return $null
}

function Set-MMDeviceName([string]$propsPath, [string]$newName) {
    try {
        $item = Get-Item -LiteralPath $propsPath -ErrorAction Stop
        $item.SetValue($NameProp, $newName, [Microsoft.Win32.RegistryValueKind]::String)
        return $true
    } catch { return $false }
}

# Registry rename (requires admin)
function Rename-MMDevice([string]$regBase, [string]$match, [string]$newName) {
    if (-not (Test-Path $regBase)) { return $false }
    foreach ($key in (Get-ChildItem $regBase -ErrorAction SilentlyContinue)) {
        $pp = "$($key.PSPath)\Properties"
        if (-not (Test-Path $pp)) { continue }
        $val = Get-MMDeviceName $pp
        if ($val -and $val -like "*$match*") {
            return Set-MMDeviceName $pp $newName
        }
    }
    return $false
}

# Get endpoint ID for IPolicyConfig — constructed from registry key GUID
function Get-RenderEndpointId([string]$match) {
    foreach ($key in (Get-ChildItem $RenderReg -ErrorAction SilentlyContinue)) {
        $pp = "$($key.PSPath)\Properties"
        if (-not (Test-Path $pp)) { continue }
        $val = Get-MMDeviceName $pp
        if ($val -and $val -like "*$match*") {
            # Endpoint ID format: {0.0.0.00000000}.{GUID}
            return "{0.0.0.00000000}.$($key.PSChildName)"
        }
    }
    return $null
}

# --- Step 1: Check / install VB-Cable ----------------------------------------
Write-Step "Checking for VB-Cable driver..."

if (Test-VBCableInstalled) {
    Write-OK "VB-Cable / Contrary TTS already present."
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

    $exeFile = Get-ChildItem $tmpDir -Recurse -Filter "VBCABLE_Setup_x64.exe" | Select-Object -First 1
    if (-not $exeFile) { Write-Fail "Setup exe not found in archive."; exit 1 }

    Write-Step "Installing VB-Cable driver..."
    $proc = Start-Process $exeFile.FullName -ArgumentList "/S" -PassThru -Wait
    Write-OK "Driver install complete (exit $($proc.ExitCode))."

    Write-Step "Waiting for device to appear..."
    for ($i = 0; $i -lt 12; $i++) {
        Start-Sleep 2
        if (Test-VBCableInstalled) { Write-OK "Device detected."; break }
        if ($i -eq 11) { Write-Warn "Device not yet visible. A reboot may be required." }
    }
}

# --- Step 2: Rename via registry ---------------------------------------------
Write-Step "Renaming devices in registry..."

$r1 = Rename-MMDevice $RenderReg  "CABLE Input"  $VBInput
if (-not $r1) { $r1 = Rename-MMDevice $RenderReg  "CABLE"        $VBInput  }
if (-not $r1) { $r1 = Rename-MMDevice $RenderReg  "Contrary TTS" $VBInput  } # already renamed
if ($r1)  { Write-OK "Playback renamed to '$VBInput'." }
else      { Write-Warn "Could not rename playback device." }

$r2 = Rename-MMDevice $CaptureReg "CABLE Output"       $VBOutput
if (-not $r2) { $r2 = Rename-MMDevice $CaptureReg "CABLE"               $VBOutput }
if (-not $r2) { $r2 = Rename-MMDevice $CaptureReg "Contrary TTS Output" $VBOutput } # already renamed
if ($r2) { Write-OK "Recording renamed to '$VBOutput'." }
else     { Write-Warn "Could not rename recording device." }

# --- Step 3: Set as default playback -----------------------------------------
Write-Step "Setting '$VBInput' as default playback..."

if ($policyOk) {
    $epId = Get-RenderEndpointId $VBInput
    if (-not $epId) { $epId = Get-RenderEndpointId "CABLE" }
    if ($epId) {
        if ([DefaultDevice]::SetDefault($epId)) { Write-OK "Default playback set." }
        else { Write-Warn "SetDefaultEndpoint failed - set manually in Sound Settings." }
    } else {
        Write-Warn "Endpoint not found in registry - set default manually."
    }
} else {
    Write-Warn "Policy COM unavailable - set default manually in Sound Settings."
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
            continue
        }
        # Run with 90s timeout via background job to prevent infinite hang
        $packName = $pack.Name
        $job = Start-Job -ScriptBlock { Add-WindowsCapability -Online -Name $using:packName }
        $done = Wait-Job $job -Timeout 90
        if ($done) {
            Receive-Job $job -ErrorAction SilentlyContinue | Out-Null
            Write-OK "$($pack.Label) - installed."
        } else {
            Stop-Job $job; Remove-Job $job -Force
            Write-Warn "$($pack.Label) - timed out. Add via Settings, Time and Language."
        }
    } catch {
        Write-Warn "$($pack.Label) - add via Settings, Time and Language, Language."
    }
}

# --- Done --------------------------------------------------------------------
Write-Host ""
Write-Host "========================================"
Write-Host "  Contrary TTS Audio Setup Complete"
Write-Host "========================================"
Write-Host "  Playback : Contrary TTS"
Write-Host "  Mic Out  : Contrary TTS Output"
Write-Host "  Valorant : Settings, Audio, Input, Contrary TTS"
Write-Host "========================================"
exit 0
