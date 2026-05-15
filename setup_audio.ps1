#Requires -Version 5.1
<#
.SYNOPSIS
    Contrary Valorant TTS — Audio Setup
    Installs VB-Cable, renames devices to "Contrary TTS", sets as default playback.
    Run once from installer or manually (no admin required for rename/default;
    driver install may prompt UAC).
#>

$ErrorActionPreference = "Continue"
$VBName   = "Contrary TTS"
$VBInput  = "Contrary TTS"          # playback side (TTS speaks here)
$VBOutput = "Contrary TTS Output"   # recording side (game/Valorant picks this as mic)

# ─── Inline C# for Core Audio API ────────────────────────────────────────────
$CoreAudioCS = @"
using System;
using System.Runtime.InteropServices;

[Guid("A95664D2-9614-4F35-A746-DE8DB63617E6")]
[InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
interface IMMDeviceEnumerator {
    int EnumAudioEndpoints(int dataFlow, int stateMask, out IMMDeviceCollection ppDevices);
    int GetDefaultAudioEndpoint(int dataFlow, int role, out IMMDevice ppDevice);
    int GetDevice(string pwstrId, out IMMDevice ppDevice);
    int NotImpl1();
    int NotImpl2();
}

[Guid("D666063F-1587-4E43-81F1-B948E807363F")]
[InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
interface IMMDevice {
    int Activate(ref Guid iid, int dwClsCtx, IntPtr pActivationParams, out object ppInterface);
    int OpenPropertyStore(int stgmAccess, out IPropertyStore ppProperties);
    int GetId(out string ppstrId);
    int GetState(out int pdwState);
}

[Guid("0BD7A1BE-7A1A-44DB-8397-CC5392387B5E")]
[InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
interface IMMDeviceCollection {
    int GetCount(out uint pcDevices);
    int Item(uint nDevice, out IMMDevice ppDevice);
}

[Guid("886d8eeb-8cf2-4446-8d02-cdba1dbdcf99")]
[InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
interface IPropertyStore {
    int GetCount(out uint cProps);
    int GetAt(uint iProp, out PropertyKey pkey);
    int GetValue(ref PropertyKey key, out PropVariant pv);
    int SetValue(ref PropertyKey key, ref PropVariant pv);
    int Commit();
}

[StructLayout(LayoutKind.Sequential)]
struct PropertyKey {
    public Guid fmtid;
    public int pid;
}

[StructLayout(LayoutKind.Sequential)]
struct PropVariant {
    public short vt;
    public short r1, r2, r3;
    public IntPtr ptr;
}

// IPolicyConfig — undocumented, stable since Vista
[Guid("f8679f50-850a-41cf-9c72-430f290290c8")]
[InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
interface IPolicyConfig {
    int GetMixFormat(string pszDeviceName, IntPtr ppFormat);
    int GetDeviceFormat(string pszDeviceName, bool bDefault, IntPtr ppFormat);
    int ResetDeviceFormat(string pszDeviceName);
    int SetDeviceFormat(string pszDeviceName, IntPtr pEndpointFormat, IntPtr pMixFormat);
    int GetProcessingPeriod(string pszDeviceName, bool bDefault, IntPtr pmftDefaultPeriod, IntPtr pmftMinimumPeriod);
    int SetProcessingPeriod(string pszDeviceName, IntPtr pmftPeriod);
    int GetShareMode(string pszDeviceName, IntPtr pMode);
    int SetShareMode(string pszDeviceName, IntPtr mode);
    int GetPropertyValue(string pszDeviceName, bool bFxStore, ref PropertyKey key, out PropVariant pv);
    int SetPropertyValue(string pszDeviceName, bool bFxStore, ref PropertyKey key, ref PropVariant pv);
    int SetDefaultEndpoint(string pszDeviceName, int role);
    int SetEndpointVisibility(string pszDeviceName, bool bVisible);
}

public static class AudioSetup {
    static readonly Guid CLSID_MMDeviceEnumerator = new Guid("BCDE0395-E52F-467C-8E3D-C4579291692E");
    static readonly Guid CLSID_PolicyConfig       = new Guid("870af99c-171d-4f9e-af0d-e63df40c2bc9");

    // PKEY_Device_FriendlyName
    static readonly PropertyKey PKEY_FriendlyName = new PropertyKey {
        fmtid = new Guid("a45c254e-df1c-4efd-8020-67d146a850e0"),
        pid   = 14
    };

    static IMMDeviceEnumerator NewEnumerator() {
        return (IMMDeviceEnumerator)Activator.CreateInstance(Type.GetTypeFromCLSID(CLSID_MMDeviceEnumerator));
    }

    static IPolicyConfig NewPolicyConfig() {
        return (IPolicyConfig)Activator.CreateInstance(Type.GetTypeFromCLSID(CLSID_PolicyConfig));
    }

    public static string[] GetDeviceIds(int dataFlow) {
        var enumerator = NewEnumerator();
        IMMDeviceCollection col;
        enumerator.EnumAudioEndpoints(dataFlow, 1, out col);
        uint count; col.GetCount(out count);
        var ids = new string[count];
        for (uint i = 0; i < count; i++) {
            IMMDevice dev; col.Item(i, out dev);
            string id; dev.GetId(out id);
            ids[i] = id;
        }
        return ids;
    }

    public static string GetFriendlyName(string deviceId) {
        foreach (int flow in new[]{0,1}) {
            var en = NewEnumerator();
            IMMDeviceCollection col;
            en.EnumAudioEndpoints(flow, 1, out col);
            uint count; col.GetCount(out count);
            for (uint i = 0; i < count; i++) {
                IMMDevice dev; col.Item(i, out dev);
                string id; dev.GetId(out id);
                if (id != deviceId) continue;
                IPropertyStore store; dev.OpenPropertyStore(0, out store);
                var key = PKEY_FriendlyName;
                PropVariant pv;
                store.GetValue(ref key, out pv);
                return Marshal.PtrToStringUni(pv.ptr);
            }
        }
        return null;
    }

    // Returns device ID of first endpoint whose friendly name contains 'substring'
    public static string FindDeviceByName(string substring, int dataFlow) {
        var enumerator = NewEnumerator();
        IMMDeviceCollection col;
        enumerator.EnumAudioEndpoints(dataFlow, 1, out col);
        uint count; col.GetCount(out count);
        for (uint i = 0; i < count; i++) {
            IMMDevice dev; col.Item(i, out dev);
            string id; dev.GetId(out id);
            IPropertyStore store; dev.OpenPropertyStore(0, out store);
            var key = PKEY_FriendlyName;
            PropVariant pv;
            store.GetValue(ref key, out pv);
            string name = Marshal.PtrToStringUni(pv.ptr);
            if (name != null && name.IndexOf(substring, StringComparison.OrdinalIgnoreCase) >= 0)
                return id;
        }
        return null;
    }

    public static bool SetDefaultDevice(string deviceId) {
        try {
            var policy = NewPolicyConfig();
            policy.SetDefaultEndpoint(deviceId, 0);
            policy.SetDefaultEndpoint(deviceId, 1);
            policy.SetDefaultEndpoint(deviceId, 2);
            return true;
        } catch { return false; }
    }

    public static bool RenameDevice(string deviceId, string newName) {
        try {
            foreach (int flow in new[]{0,1}) {
                var en = NewEnumerator();
                IMMDeviceCollection col;
                en.EnumAudioEndpoints(flow, 1, out col);
                uint count; col.GetCount(out count);
                for (uint i = 0; i < count; i++) {
                    IMMDevice dev; col.Item(i, out dev);
                    string id; dev.GetId(out id);
                    if (id != deviceId) continue;
                    IPropertyStore store;
                    dev.OpenPropertyStore(2, out store);
                    var key = PKEY_FriendlyName;
                    IntPtr strPtr = Marshal.StringToCoTaskMemUni(newName);
                    var pv = new PropVariant { vt = 31, ptr = strPtr };
                    store.SetValue(ref key, ref pv);
                    store.Commit();
                    Marshal.FreeCoTaskMem(strPtr);
                    return true;
                }
            }
        } catch {}
        return false;
    }
}
"@

Add-Type -TypeDefinition $CoreAudioCS -Language CSharp `
    -ReferencedAssemblies "System.Runtime.InteropServices" 2>$null

# ─── Helper functions ─────────────────────────────────────────────────────────
function Write-Step([string]$msg) { Write-Host "`n[>>] $msg" -ForegroundColor Cyan }
function Write-OK([string]$msg)   { Write-Host " [OK] $msg" -ForegroundColor Green }
function Write-Warn([string]$msg) { Write-Host " [!!] $msg" -ForegroundColor Yellow }
function Write-Fail([string]$msg) { Write-Host " [XX] $msg" -ForegroundColor Red }

# ─── Step 1: Check if VB-Cable already installed ─────────────────────────────
Write-Step "Checking for VB-Cable driver..."

# dataFlow: 0 = render (playback), 1 = capture (recording)
$existingId = [AudioSetup]::FindDeviceByName("CABLE", 0)
if (-not $existingId) { $existingId = [AudioSetup]::FindDeviceByName("Contrary TTS", 0) }

if ($existingId) {
    Write-OK "VB-Cable / Contrary TTS already installed. Skipping driver install."
} else {
    Write-Step "Downloading VB-Cable..."
    $tmpDir  = Join-Path $env:TEMP "VBCableSetup"
    $zipPath = Join-Path $tmpDir   "VBCABLE_Driver_Pack43.zip"
    $exePath = Join-Path $tmpDir   "VBCABLE_Setup_x64.exe"

    New-Item -ItemType Directory -Force -Path $tmpDir | Out-Null

    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        Invoke-WebRequest -Uri "https://download.vb-audio.com/Download_CABLE/VBCABLE_Driver_Pack43.zip" `
                          -OutFile $zipPath -UseBasicParsing
        Write-OK "Downloaded."
    } catch {
        Write-Fail "Download failed: $_"
        Write-Warn "Please install VB-Cable manually from https://vb-audio.com/Cable/"
        exit 1
    }

    Write-Step "Extracting..."
    Expand-Archive -Path $zipPath -DestinationPath $tmpDir -Force
    Write-OK "Extracted."

    Write-Step "Installing VB-Cable driver (may prompt UAC)..."
    if (-not (Test-Path $exePath)) {
        # Some zip layouts put it in a subfolder
        $exePath = Get-ChildItem $tmpDir -Recurse -Filter "VBCABLE_Setup_x64.exe" |
                   Select-Object -First 1 -ExpandProperty FullName
    }
    if (-not $exePath) { Write-Fail "Setup exe not found in archive."; exit 1 }

    $proc = Start-Process $exePath -ArgumentList "/S" -Verb RunAs -PassThru -Wait
    if ($proc.ExitCode -ne 0) {
        Write-Fail "Driver install returned exit code $($proc.ExitCode)."
        Write-Warn "Try running the installer manually: $exePath"
        exit 1
    }
    Write-OK "Driver installed."

    # Wait for driver to register (up to 15s)
    Write-Step "Waiting for audio device to appear..."
    $waited = 0
    do {
        Start-Sleep -Seconds 2
        $waited += 2
        $existingId = [AudioSetup]::FindDeviceByName("CABLE", 0)
    } while (-not $existingId -and $waited -lt 15)

    if (-not $existingId) {
        Write-Warn "Device not detected yet. You may need to reboot. Continuing anyway..."
    } else {
        Write-OK "Device detected."
    }
}

# ─── Step 2: Rename devices ───────────────────────────────────────────────────
Write-Step "Renaming devices to '$VBName'..."

# Playback side (render = 0): CABLE Input → Contrary TTS
$renderIdCable = [AudioSetup]::FindDeviceByName("CABLE Input", 0)
if (-not $renderIdCable) { $renderIdCable = [AudioSetup]::FindDeviceByName("CABLE", 0) }

if ($renderIdCable) {
    $ok = [AudioSetup]::RenameDevice($renderIdCable, $VBInput)
    if ($ok) { Write-OK "Playback device renamed to '$VBInput'." }
    else      { Write-Warn "Could not rename playback device (may need reboot)." }
} else {
    Write-Warn "CABLE Input (playback) not found — skipping rename."
    $renderIdCable = [AudioSetup]::FindDeviceByName("Contrary TTS", 0)
}

# Capture side (capture = 1): CABLE Output → Contrary TTS Output
$captureIdCable = [AudioSetup]::FindDeviceByName("CABLE Output", 1)
if (-not $captureIdCable) { $captureIdCable = [AudioSetup]::FindDeviceByName("CABLE", 1) }

if ($captureIdCable) {
    $ok = [AudioSetup]::RenameDevice($captureIdCable, $VBOutput)
    if ($ok) { Write-OK "Recording device renamed to '$VBOutput'." }
    else      { Write-Warn "Could not rename recording device." }
} else {
    Write-Warn "CABLE Output (recording) not found — skipping rename."
}

# ─── Step 3: Set Contrary TTS as default playback device ─────────────────────
Write-Step "Setting '$VBInput' as default playback device..."

$playbackId = $renderIdCable
if (-not $playbackId) {
    $playbackId = [AudioSetup]::FindDeviceByName("Contrary TTS", 0)
}

if ($playbackId) {
    $ok = [AudioSetup]::SetDefaultDevice($playbackId)
    if ($ok) { Write-OK "Default playback set to '$VBInput'." }
    else {
        Write-Warn "IPolicyConfig failed — trying NirCmd fallback..."
        $nircmd = Join-Path $PSScriptRoot "nircmd.exe"
        if (Test-Path $nircmd) {
            & $nircmd setdefaultsounddevice "Contrary TTS" 1
            Write-OK "NirCmd fallback executed."
        } else {
            Write-Warn "NirCmd not found. Set default playback manually in Sound Settings."
        }
    }
} else {
    Write-Warn "Playback device not found. Cannot set default automatically."
}

# ─── Step 4: Summary ─────────────────────────────────────────────────────────
Write-Host ""
Write-Host "════════════════════════════════════════" -ForegroundColor Magenta
Write-Host "  Contrary TTS Audio Setup Complete" -ForegroundColor Magenta
Write-Host "════════════════════════════════════════" -ForegroundColor Magenta
Write-Host ""
Write-Host "  Playback device : Contrary TTS" -ForegroundColor White
Write-Host "  Recording device: Contrary TTS Output" -ForegroundColor White
Write-Host ""
Write-Host "  In Valorant: Settings -> Audio -> Input Device" -ForegroundColor Gray
Write-Host "  Select: Contrary TTS" -ForegroundColor Gray
Write-Host ""
Write-Host "  The TTS voices will now play through your mic." -ForegroundColor Gray
Write-Host "════════════════════════════════════════" -ForegroundColor Magenta

# ─── Step 5: Install Indian English + Hindi speech voices ─────────────────────
Write-Step "Installing speech voices (Indian English + Hindi)..."

$voicePacks = @(
    @{ Name="Language.Speech~~~en-IN~0.0.1.0"; Label="Indian English (Heera / Ravi)" },
    @{ Name="Language.Speech~~~hi-IN~0.0.1.0"; Label="Hindi (Kalpana / Hemant)" }
)

foreach ($pack in $voicePacks) {
    try {
        $existing = Get-WindowsCapability -Online -Name $pack.Name -ErrorAction SilentlyContinue
        if ($existing -and $existing.State -eq "Installed") {
            Write-OK "$($pack.Label) — already installed."
        } else {
            Write-Host "  Installing $($pack.Label)..." -ForegroundColor Cyan
            Add-WindowsCapability -Online -Name $pack.Name -ErrorAction Stop | Out-Null
            Write-OK "$($pack.Label) — installed."
        }
    } catch {
        Write-Warn "$($pack.Label) — could not install automatically. Install manually:"
        Write-Warn "  Settings → Time & Language → Language → Add English (India) / Hindi (India)"
    }
}

exit 0
