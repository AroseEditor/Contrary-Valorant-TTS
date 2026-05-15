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
$RenderBase  = "SOFTWARE\Microsoft\Windows\CurrentVersion\MMDevices\Audio\Render"
$CaptureBase = "SOFTWARE\Microsoft\Windows\CurrentVersion\MMDevices\Audio\Capture"
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

# MMDevices Properties are stored as binary PROPVARIANT (not REG_SZ strings)
# VT_LPWSTR (0x1F): bytes 0-1 = vartype, bytes 2-7 = padding, bytes 8+ = UTF-16LE string

function Get-DeviceFriendlyName([string]$subKeyPath) {
    try {
        $k = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey($subKeyPath, $false)
        if (-not $k) { return $null }
        $raw = $k.GetValue($NameProp)
        $k.Close()
        if (-not $raw) { return $null }
        # Check VARTYPE in first 2 bytes
        $vt = [BitConverter]::ToUInt16([byte[]]$raw, 0)
        if ($vt -eq 31 -and $raw.Length -gt 8) {  # 31 = VT_LPWSTR
            return [System.Text.Encoding]::Unicode.GetString($raw, 8, $raw.Length - 8).TrimEnd([char]0)
        }
    } catch {}
    return $null
}

function Set-DeviceFriendlyName([string]$subKeyPath, [string]$newName) {
    try {
        $k = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey($subKeyPath, $true)
        if (-not $k) { return $false }
        # Build PROPVARIANT binary: 2-byte VT_LPWSTR + 6-byte padding + UTF-16LE string + null
        $strBytes  = [System.Text.Encoding]::Unicode.GetBytes($newName + [char]0)
        $header    = [byte[]]@(0x1F, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00)
        $propvariant = [byte[]]($header + $strBytes)
        $k.SetValue($NameProp, $propvariant, [Microsoft.Win32.RegistryValueKind]::Binary)
        $k.Close()
        return $true
    } catch { Write-Warn "  SetValue: $_" }
    return $false
}

function Rename-MMDevice([string]$baseKey, [string]$match, [string]$newName) {
    try {
        $root = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey($baseKey, $false)
        if (-not $root) { return $false }
        foreach ($guid in $root.GetSubKeyNames()) {
            $val = Get-DeviceFriendlyName "$baseKey\$guid\Properties"
            if ($val -and $val -like "*$match*") {
                $root.Close()
                return Set-DeviceFriendlyName "$baseKey\$guid\Properties" $newName
            }
        }
        $root.Close()
    } catch { Write-Warn "  Rename: $_" }
    return $false
}

function Get-RenderEndpointId([string]$match) {
    try {
        $root = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey($RenderBase, $false)
        if (-not $root) { return $null }
        foreach ($guid in $root.GetSubKeyNames()) {
            $val = Get-DeviceFriendlyName "$RenderBase\$guid\Properties"
            if ($val -and $val -like "*$match*") {
                $root.Close()
                return "{0.0.0.00000000}.$guid"
            }
        }
        $root.Close()
    } catch {}
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

$r1 = Rename-MMDevice $RenderBase  "CABLE Input"  $VBInput
if (-not $r1) { $r1 = Rename-MMDevice $RenderBase  "CABLE"        $VBInput }
if (-not $r1) { $r1 = Rename-MMDevice $RenderBase  "Contrary TTS" $VBInput }
if ($r1)  { Write-OK "Playback renamed to '$VBInput'." }
else      { Write-Warn "Could not rename playback device." }

$r2 = Rename-MMDevice $CaptureBase "CABLE Output"       $VBOutput
if (-not $r2) { $r2 = Rename-MMDevice $CaptureBase "CABLE"               $VBOutput }
if (-not $r2) { $r2 = Rename-MMDevice $CaptureBase "Contrary TTS Output" $VBOutput }
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
        Write-Warn "Endpoint not found - set default manually in Sound Settings."
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
