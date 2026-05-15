#Requires -Version 5.1
<#
.SYNOPSIS
    Contrary Valorant TTS - Audio Setup (Audited)
    Installs VB-Cable, renames to "Contrary TTS" using binary registry blobs,
    sets default playback, and installs voices.
#>

# --- Self-elevate with -Wait so the installer doesn't skip ahead --------------
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    $self = $MyInvocation.MyCommand.Path
    if (-not $self) { $self = $PSCommandPath }
    if ($self) {
        # Start elevated process and WAIT for it to finish
        $p = Start-Process powershell.exe -ArgumentList "-ExecutionPolicy Bypass -File `"$self`"" -Verb RunAs -PassThru -Wait
        exit $p.ExitCode
    }
    exit 1
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

$policyOk = $false
if (-not ([System.Management.Automation.PSTypeName]"DefaultDevice").Type) {
    try {
        Add-Type -TypeDefinition $PolicyCS -Language CSharp -ErrorAction Stop
        $policyOk = $true
    } catch {
        Write-Warning "IPolicyConfig failed to compile: $_"
    }
} else { $policyOk = $true }

# --- Helpers -----------------------------------------------------------------
function Write-Step([string]$m) { Write-Host "" ; Write-Host "[>>] $m" -ForegroundColor Cyan }
function Write-OK([string]$m)   { Write-Host " [OK] $m"  -ForegroundColor Green }
function Write-Warn([string]$m) { Write-Host " [!!] $m"  -ForegroundColor Yellow }
function Write-Fail([string]$m) { Write-Host " [XX] $m"  -ForegroundColor Red }

$RenderBase  = "SOFTWARE\Microsoft\Windows\CurrentVersion\MMDevices\Audio\Render"
$CaptureBase = "SOFTWARE\Microsoft\Windows\CurrentVersion\MMDevices\Audio\Capture"
$NameProp    = "{a45c254e-df1c-4efd-8020-67d146a850e0},14"

# MMDevices Properties are binary PROPVARIANT blobs.
# VT_LPWSTR (0x1F) = [2-byte VT][6-byte padding][UTF-16LE String][Null]
function Get-DeviceFriendlyName([string]$subKeyPath) {
    try {
        $k = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey($subKeyPath, $false)
        if (-not $k) { return $null }
        $raw = $k.GetValue($NameProp)
        $k.Close()
        if (-not $raw -or $raw.Length -le 8) { return $null }
        $vt = [BitConverter]::ToUInt16([byte[]]$raw, 0)
        if ($vt -eq 31) { # 0x1F
            return [System.Text.Encoding]::Unicode.GetString($raw, 8, $raw.Length - 8).TrimEnd([char]0)
        }
    } catch {}
    return $null
}

function Set-DeviceFriendlyName([string]$subKeyPath, [string]$newName) {
    try {
        $k = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey($subKeyPath, $true)
        if (-not $k) { return $false }
        $strBytes = [System.Text.Encoding]::Unicode.GetBytes($newName + [char]0)
        $header   = [byte[]]@(0x1F, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00)
        $blob     = [byte[]]($header + $strBytes)
        $k.SetValue($NameProp, $blob, [Microsoft.Win32.RegistryValueKind]::Binary)
        $k.Close()
        return $true
    } catch { return $false }
}

function Rename-MMDevice([string]$baseKey, [string]$match, [string]$newName) {
    try {
        $root = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey($baseKey, $false)
        if (-not $root) { return $false }
        foreach ($guid in $root.GetSubKeyNames()) {
            $path = "$baseKey\$guid\Properties"
            $val = Get-DeviceFriendlyName $path
            if ($val -and $val -like "*$match*") {
                $root.Close()
                return Set-DeviceFriendlyName $path $newName
            }
        }
        $root.Close()
    } catch {}
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

$found = $false
$devs = Get-PnpDevice -Class AudioEndpoint -ErrorAction SilentlyContinue
foreach ($d in $devs) {
    if ($d.FriendlyName -like "*CABLE*" -or $d.FriendlyName -like "*Contrary TTS*") {
        $found = $true; break
    }
}

if ($found) {
    Write-OK "VB-Cable / Contrary TTS detected."
} else {
    Write-Step "Downloading VB-Cable..."
    $tmpDir = Join-Path $env:TEMP "VBCableSetup"
    $zip    = Join-Path $tmpDir "VBCABLE_Driver_Pack43.zip"
    New-Item -ItemType Directory -Force -Path $tmpDir | Out-Null
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        Invoke-WebRequest -Uri "https://download.vb-audio.com/Download_CABLE/VBCABLE_Driver_Pack43.zip" -OutFile $zip -UseBasicParsing
        Write-OK "Downloaded."
    } catch {
        Write-Fail "Download failed. Please install manually from vb-audio.com"
        exit 1
    }
    Write-Step "Extracting..."
    Expand-Archive -Path $zip -DestinationPath $tmpDir -Force
    Write-OK "Extracted."

    $exe = Get-ChildItem $tmpDir -Recurse -Filter "VBCABLE_Setup_x64.exe" | Select-Object -First 1
    if (-not $exe) { Write-Fail "Setup file not found."; exit 1 }

    Write-Step "Installing driver..."
    $proc = Start-Process $exe.FullName -ArgumentList "/S" -PassThru -Wait
    Write-OK "Install finished (Exit code: $($proc.ExitCode))."

    Write-Step "Waiting for device (max 20s)..."
    for ($i=0; $i -lt 10; $i++) {
        Start-Sleep 2
        $check = Get-PnpDevice -Class AudioEndpoint -ErrorAction SilentlyContinue | Where-Object { $_.FriendlyName -like "*CABLE*" }
        if ($check) { Write-OK "Device appeared."; break }
    }
}

# --- Step 2: Rename ----------------------------------------------------------
Write-Step "Renaming devices in registry..."

$r1 = Rename-MMDevice $RenderBase "CABLE Input" $VBInput
if (-not $r1) { $r1 = Rename-MMDevice $RenderBase "CABLE" $VBInput }
if (-not $r1) { $r1 = Rename-MMDevice $RenderBase "Contrary TTS" $VBInput }

if ($r1) { Write-OK "Playback renamed to '$VBInput'." }
else     { Write-Warn "Could not rename playback device." }

$r2 = Rename-MMDevice $CaptureBase "CABLE Output" $VBOutput
if (-not $r2) { $r2 = Rename-MMDevice $CaptureBase "CABLE" $VBOutput }
if (-not $r2) { $r2 = Rename-MMDevice $CaptureBase "Contrary TTS Output" $VBOutput }

if ($r2) { Write-OK "Recording renamed to '$VBOutput'." }
else     { Write-Warn "Could not rename recording device." }

# --- Step 3: Default ---------------------------------------------------------
Write-Step "Setting default playback..."
if ($policyOk) {
    $id = Get-RenderEndpointId $VBInput
    if (-not $id) { $id = Get-RenderEndpointId "CABLE" }
    if ($id) {
        if ([DefaultDevice]::SetDefault($id)) { Write-OK "Default set." }
        else { Write-Warn "Failed to set default." }
    }
}

# --- Step 4: Voices ----------------------------------------------------------
Write-Step "Installing Indian English + Hindi voice packs..."
$packs = @("Language.Speech~~~en-IN~0.0.1.0", "Language.Speech~~~hi-IN~0.0.1.0")
foreach ($p in $packs) {
    $cap = Get-WindowsCapability -Online -Name $p -ErrorAction SilentlyContinue
    if ($cap -and $cap.State -eq "Installed") {
        Write-OK "$p already present."
    } else {
        $job = Start-Job -ScriptBlock { Add-WindowsCapability -Online -Name $using:p }
        if (Wait-Job $job -Timeout 120) { Write-OK "$p installed." }
        else { Stop-Job $job; Write-Warn "$p timed out." }
    }
}

Write-Step "Setup Complete."
exit 0
