
#define UNICODE
#define _UNICODE
#define WIN32_LEAN_AND_MEAN
#define NOMINMAX

#define IDI_ICON1        101
#define IDR_SETUP_SCRIPT 102

#include <windows.h>
#include <windowsx.h>
#include <shellapi.h>
#include <sapi.h>
#include <sphelper.h>
#include <gdiplus.h>
#include <comdef.h>
#include <string>
#include <vector>
#include <thread>
#include <atomic>
#include <mutex>

#pragma comment(lib, "user32.lib")
#pragma comment(lib, "gdi32.lib")
#pragma comment(lib, "gdiplus.lib")
#pragma comment(lib, "sapi.lib")
#pragma comment(lib, "ole32.lib")
#pragma comment(lib, "shell32.lib")
#pragma comment(lib, "kernel32.lib")
#pragma comment(lib, "advapi32.lib")

// ─── Constants ───────────────────────────────────────────────────────────────
#define WM_TRAYICON      (WM_USER + 1)
#define WM_SHOW_BALLOON  (WM_USER + 2)
#define IDM_EXIT         1001
#define IDM_TITLE        1002
#define IDM_HOTKEY_INFO  1003
#define IDM_SETTINGS     1004
#define HOTKEY_ID        1
#define FADE_TIMER_ID    2
#define FADE_IN_STEP     12
#define FADE_OUT_STEP    14
#define TARGET_ALPHA     115
#define EDIT_ID          100
#define SETTINGS_LIST_ID 200
#define SETTINGS_APPLY_ID 201
#define SETTINGS_SETUP_ID 202

static const COLORREF COL_BG      = RGB(0x1a, 0x1a, 0x2e);
static const COLORREF COL_ACCENT  = RGB(0xff, 0x46, 0x55);
static const COLORREF COL_WHITE   = RGB(0xff, 0xff, 0xff);
static const int      OVL_W       = 500;
static const int      OVL_H       = 52;
static const int      OVL_TOP     = 80;

// ─── Globals ─────────────────────────────────────────────────────────────────
HWND        g_hwnd      = nullptr;
HWND        g_edit      = nullptr;
HINSTANCE   g_hInst     = nullptr;
NOTIFYICONDATA g_nid    = {};

std::atomic<bool>    g_visible      {false};
std::atomic<bool>    g_speaking     {false};
std::atomic<bool>    g_ttsStop      {false};
std::atomic<bool>    g_hasNewText   {false};
std::atomic<bool>    g_appRunning   {true};

CRITICAL_SECTION     g_cs;
std::wstring         g_pendingText;
HANDLE               g_ttsEvent       = nullptr;
std::wstring         g_selectedVoice;   // saved voice name; empty = auto
HWND                 g_settingsHwnd   = nullptr;

// Fade state
std::atomic<int>     g_alpha        {0};
enum FadeDir { FADE_NONE, FADE_IN, FADE_OUT };
std::atomic<FadeDir> g_fadeDir      {FADE_NONE};

bool                 g_placeholderActive = false;
ULONG_PTR            g_gdiplusToken = 0;

// ─── Registry helpers ─────────────────────────────────────────────────────────
static std::wstring RegLoadStr(const wchar_t* val) {
    HKEY hk; std::wstring r;
    if (RegOpenKeyEx(HKEY_CURRENT_USER, L"Software\\ContraryValorantTTS", 0, KEY_QUERY_VALUE, &hk) == ERROR_SUCCESS) {
        WCHAR buf[256]={}; DWORD sz=sizeof(buf), t=REG_SZ;
        if (RegQueryValueEx(hk, val, nullptr, &t, (BYTE*)buf, &sz) == ERROR_SUCCESS) r=buf;
        RegCloseKey(hk);
    }
    return r;
}
static void RegSaveStr(const wchar_t* val, const std::wstring& s) {
    HKEY hk;
    if (RegCreateKeyEx(HKEY_CURRENT_USER, L"Software\\ContraryValorantTTS", 0, nullptr, 0, KEY_SET_VALUE, nullptr, &hk, nullptr) == ERROR_SUCCESS) {
        RegSetValueEx(hk, val, 0, REG_SZ, (const BYTE*)s.c_str(), (DWORD)((s.size()+1)*sizeof(wchar_t)));
        RegCloseKey(hk);
    }
}
static DWORD RegLoadDW(const wchar_t* val) {
    HKEY hk; DWORD r=0;
    if (RegOpenKeyEx(HKEY_CURRENT_USER, L"Software\\ContraryValorantTTS", 0, KEY_QUERY_VALUE, &hk) == ERROR_SUCCESS) {
        DWORD sz=sizeof(r), t=REG_DWORD;
        RegQueryValueEx(hk, val, nullptr, &t, (BYTE*)&r, &sz);
        RegCloseKey(hk);
    }
    return r;
}
static void RegSaveDW(const wchar_t* val, DWORD v) {
    HKEY hk;
    if (RegCreateKeyEx(HKEY_CURRENT_USER, L"Software\\ContraryValorantTTS", 0, nullptr, 0, KEY_SET_VALUE, nullptr, &hk, nullptr) == ERROR_SUCCESS) {
        RegSetValueEx(hk, val, 0, REG_DWORD, (BYTE*)&v, sizeof(v));
        RegCloseKey(hk);
    }
}

// ─── Audio setup ──────────────────────────────────────────────────────────────
static void RunAudioSetupPS() {
    WCHAR psPath[MAX_PATH] = {};
    bool usingTemp = false;

    // 1. Try to extract from embedded resource (single-exe mode)
    HRSRC hRes = FindResource(nullptr, MAKEINTRESOURCE(IDR_SETUP_SCRIPT), RT_RCDATA);
    if (hRes) {
        HGLOBAL hGlob = LoadResource(nullptr, hRes);
        DWORD   sz    = SizeofResource(nullptr, hRes);
        void*   pData = LockResource(hGlob);
        if (pData && sz > 0) {
            GetTempPath(MAX_PATH, psPath);
            wcscat_s(psPath, L"ContraryTTS_setup.ps1");
            HANDLE hFile = CreateFile(psPath, GENERIC_WRITE, 0, nullptr,
                                      CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, nullptr);
            if (hFile != INVALID_HANDLE_VALUE) {
                DWORD written;
                WriteFile(hFile, pData, sz, &written, nullptr);
                CloseHandle(hFile);
                usingTemp = true;
            }
        }
    }

    // 2. Fallback: setup_audio.ps1 beside the exe
    if (!usingTemp) {
        GetModuleFileName(nullptr, psPath, MAX_PATH);
        WCHAR* sl = wcsrchr(psPath, L'\\');
        if (!sl) return;
        wcscpy_s(sl+1, MAX_PATH-(int)(sl-psPath)-1, L"setup_audio.ps1");
        if (GetFileAttributes(psPath) == INVALID_FILE_ATTRIBUTES) return;
    }

    std::wstring args = std::wstring(L"-ExecutionPolicy Bypass -NonInteractive -WindowStyle Hidden -File \"") + psPath + L"\"";
    ShellExecuteW(nullptr, L"open", L"powershell.exe", args.c_str(), nullptr, SW_HIDE);
}
static void CheckAndRunAudioSetup() {
    std::thread([](){
        if (RegLoadDW(L"AudioSetupDone")==1) return;
        RunAudioSetupPS();
        RegSaveDW(L"AudioSetupDone", 1);
    }).detach();
}

// ─── GDI+ ARGB helper ────────────────────────────────────────────────────────
static Gdiplus::ARGB MakeARGB(BYTE a, BYTE r, BYTE g, BYTE b) {
    return ((DWORD)a << 24) | ((DWORD)r << 16) | ((DWORD)g << 8) | b;
}

// ─── Draw the layered window surface ─────────────────────────────────────────
static void DrawLayered(HWND hwnd, BYTE alpha) {
    RECT rc;
    GetWindowRect(hwnd, &rc);
    int w = rc.right - rc.left;
    int h = rc.bottom - rc.top;

    HDC hdcScreen = GetDC(nullptr);
    HDC hdcMem    = CreateCompatibleDC(hdcScreen);

    BITMAPINFO bmi = {};
    bmi.bmiHeader.biSize        = sizeof(BITMAPINFOHEADER);
    bmi.bmiHeader.biWidth       = w;
    bmi.bmiHeader.biHeight      = -h;
    bmi.bmiHeader.biPlanes      = 1;
    bmi.bmiHeader.biBitCount    = 32;
    bmi.bmiHeader.biCompression = BI_RGB;

    void* pBits = nullptr;
    HBITMAP hBmp = CreateDIBSection(hdcMem, &bmi, DIB_RGB_COLORS, &pBits, nullptr, 0);
    HBITMAP hOld = (HBITMAP)SelectObject(hdcMem, hBmp);

    // Use GDI+ for per-pixel alpha rendering
    {
        Gdiplus::Graphics g(hdcMem);
        g.SetSmoothingMode(Gdiplus::SmoothingModeAntiAlias);

        // Clear transparent
        g.Clear(Gdiplus::Color(0, 0, 0, 0));

        // Background rounded rect with alpha
        BYTE bgAlpha = (BYTE)((DWORD)alpha * 230 / 255); // slightly less opaque bg
        Gdiplus::SolidBrush bgBrush(Gdiplus::Color(bgAlpha, 0x1a, 0x1a, 0x2e));
        Gdiplus::GraphicsPath path;
        int r = 10;
        int bx = 1, by = 1, bw = w - 2, bh = h - 2;
        path.AddArc(bx, by, r*2, r*2, 180, 90);
        path.AddArc(bx+bw-r*2, by, r*2, r*2, 270, 90);
        path.AddArc(bx+bw-r*2, by+bh-r*2, r*2, r*2, 0, 90);
        path.AddArc(bx, by+bh-r*2, r*2, r*2, 90, 90);
        path.CloseFigure();
        g.FillPath(&bgBrush, &path);

        // Border
        Gdiplus::Pen borderPen(Gdiplus::Color(alpha, 0xff, 0x46, 0x55), 1.5f);
        g.DrawPath(&borderPen, &path);

        // Red/white dot indicator (left side, vertically centered)
        int dotX = 14, dotY = h / 2 - 4, dotR = 8;
        Gdiplus::Color dotColor = g_speaking.load()
            ? Gdiplus::Color(alpha, 0xff, 0xff, 0xff)
            : Gdiplus::Color(alpha, 0xff, 0x46, 0x55);
        Gdiplus::SolidBrush dotBrush(dotColor);
        g.FillEllipse(&dotBrush, dotX, dotY, dotR, dotR);
    }

    // Premultiply alpha for UpdateLayeredWindow
    DWORD* pixels = (DWORD*)pBits;
    for (int i = 0; i < w * h; i++) {
        BYTE a = (pixels[i] >> 24) & 0xff;
        BYTE r2 = (BYTE)(((pixels[i] >> 16) & 0xff) * a / 255);
        BYTE g2 = (BYTE)(((pixels[i] >>  8) & 0xff) * a / 255);
        BYTE b2 = (BYTE)(((pixels[i]      ) & 0xff) * a / 255);
        pixels[i] = ((DWORD)a << 24) | ((DWORD)r2 << 16) | ((DWORD)g2 << 8) | b2;
    }

    POINT ptSrc  = {0, 0};
    SIZE  sz     = {w, h};
    POINT ptDst  = {rc.left, rc.top};
    BLENDFUNCTION bf = {AC_SRC_OVER, 0, 255, AC_SRC_ALPHA};

    UpdateLayeredWindow(hwnd, hdcScreen, &ptDst, &sz, hdcMem, &ptSrc, 0, &bf, ULW_ALPHA);

    SelectObject(hdcMem, hOld);
    DeleteObject(hBmp);
    DeleteDC(hdcMem);
    ReleaseDC(nullptr, hdcScreen);
}

// ─── Show/Hide overlay ────────────────────────────────────────────────────────
static void ShowOverlay() {
    if (g_visible.load()) return;

    // Center on primary monitor, 80px from top
    int sw = GetSystemMetrics(SM_CXSCREEN);
    int x  = (sw - OVL_W) / 2;
    SetWindowPos(g_hwnd, HWND_TOPMOST, x, OVL_TOP, OVL_W, OVL_H, SWP_NOACTIVATE);

    g_alpha = 0;
    DrawLayered(g_hwnd, 0);
    ShowWindow(g_hwnd, SW_SHOWNA);

    // Placeholder
    SetWindowText(g_edit, L"Type to speak...");
    g_placeholderActive = true;

    // Attach to foreground thread so SetFocus works even when a game owns the foreground
    HWND  hFg      = GetForegroundWindow();
    DWORD fgTid    = GetWindowThreadProcessId(hFg, nullptr);
    DWORD myTid    = GetCurrentThreadId();
    bool  attached = (fgTid != myTid) && AttachThreadInput(myTid, fgTid, TRUE);
    SetFocus(g_edit);
    if (attached) AttachThreadInput(myTid, fgTid, FALSE);

    g_visible  = true;
    g_fadeDir  = FADE_IN;
    SetTimer(g_hwnd, FADE_TIMER_ID, 8, nullptr);
}

static void HideOverlay() {
    if (!g_visible.load()) return;
    g_fadeDir = FADE_OUT;
    SetTimer(g_hwnd, FADE_TIMER_ID, 8, nullptr);
}

// ─── TTS voice selection ──────────────────────────────────────────────────────
static bool HasDevanagari(const std::wstring& s) {
    for (wchar_t c : s)
        if (c >= 0x0900 && c <= 0x097F) return true;
    return false;
}

static ISpVoice* g_voice = nullptr;

static void SelectVoice(bool hindiNeeded) {
    if (!g_voice) return;

    // ── User-selected voice override ─────────────────────────────────────────
    if (!g_selectedVoice.empty()) {
        ISpObjectTokenCategory* pC2 = nullptr;
        IEnumSpObjectTokens*    pE2 = nullptr;
        SpGetCategoryFromId(SPCAT_VOICES, &pC2);
        if (pC2) { pC2->EnumTokens(nullptr, nullptr, &pE2); pC2->Release(); }
        if (pE2) {
            ISpObjectToken* pT2 = nullptr;
            while (pE2->Next(1, &pT2, nullptr) == S_OK) {
                WCHAR* d2 = nullptr;
                SpGetDescription(pT2, &d2);
                bool match = d2 && (wcsstr(d2, g_selectedVoice.c_str()) || wcsstr(g_selectedVoice.c_str(), d2));
                if (d2) CoTaskMemFree(d2);
                if (match) { g_voice->SetVoice(pT2); pT2->Release(); pE2->Release(); return; }
                pT2->Release();
            }
            pE2->Release();
        }
    }

    ISpObjectTokenCategory* pCat  = nullptr;
    IEnumSpObjectTokens*    pEnum = nullptr;
    SpGetCategoryFromId(SPCAT_VOICES, &pCat);
    if (!pCat) return;
    pCat->EnumTokens(nullptr, nullptr, &pEnum);
    pCat->Release();
    if (!pEnum) return;

    // Priority: Devanagari → Hindi | English → Heera > Ravi > Zira > David > any
    ISpObjectToken* pToken=nullptr, *heera=nullptr, *ravi=nullptr,
                   *zira=nullptr,  *david=nullptr, *hindi=nullptr, *fallback=nullptr;

    while (pEnum->Next(1, &pToken, nullptr) == S_OK) {
        WCHAR* desc = nullptr;
        SpGetDescription(pToken, &desc);
        if (desc) {
            std::wstring d(desc); CoTaskMemFree(desc);
            if (hindiNeeded && (d.find(L"Hemant")!=std::wstring::npos||d.find(L"Kalpana")!=std::wstring::npos) && !hindi)
                { hindi=pToken; pToken->AddRef(); }
            if (d.find(L"Heera")!=std::wstring::npos && !heera) { heera=pToken; pToken->AddRef(); }
            if (d.find(L"Ravi") !=std::wstring::npos && !ravi)  { ravi =pToken; pToken->AddRef(); }
            if (d.find(L"Zira") !=std::wstring::npos && !zira)  { zira =pToken; pToken->AddRef(); }
            if (d.find(L"David")!=std::wstring::npos && !david) { david=pToken; pToken->AddRef(); }
            if (!fallback) { fallback=pToken; pToken->AddRef(); }
        }
        pToken->Release();
    }
    pEnum->Release();

    ISpObjectToken* chosen = nullptr;
    if (hindiNeeded && hindi) chosen=hindi;
    else if (heera)  chosen=heera;
    else if (ravi)   chosen=ravi;
    else if (zira)   chosen=zira;
    else if (david)  chosen=david;
    else             chosen=fallback;

    if (chosen) g_voice->SetVoice(chosen);
    auto rel=[&](ISpObjectToken* t){ if(t&&t!=chosen) t->Release(); };
    rel(hindi); rel(heera); rel(ravi); rel(zira); rel(david); rel(fallback);
}

// ─── Audio output device routing ─────────────────────────────────────────────
// Finds the SAPI audio output token whose description contains 'nameSubstr'.
// Caller must Release() the returned token.
static ISpObjectToken* FindAudioOutputToken(const wchar_t* nameSubstr) {
    ISpObjectTokenCategory* pCat  = nullptr;
    IEnumSpObjectTokens*    pEnum = nullptr;
    SpGetCategoryFromId(SPCAT_AUDIOOUT, &pCat);
    if (!pCat) return nullptr;
    pCat->EnumTokens(nullptr, nullptr, &pEnum);
    pCat->Release();
    if (!pEnum) return nullptr;

    ISpObjectToken* pToken = nullptr;
    ISpObjectToken* found  = nullptr;
    while (pEnum->Next(1, &pToken, nullptr) == S_OK) {
        WCHAR* desc = nullptr;
        SpGetDescription(pToken, &desc);
        if (desc) {
            bool match = (wcsstr(desc, nameSubstr) != nullptr);
            CoTaskMemFree(desc);
            if (match) { found = pToken; break; }  // keep ref
        }
        pToken->Release();
    }
    pEnum->Release();
    return found;
}

// Post a tray balloon from any thread (avoids calling Shell_NotifyIcon off main thread)
static void ShowTrayBalloon(const wchar_t* title, const wchar_t* body) {
    // Encode as two pointers in a heap-allocated pair — main thread frees them
    // Simple approach: just post with lParam = 0, use fixed strings in WM_SHOW_BALLOON
    // For simplicity store in globals (balloon is rare / non-concurrent)
    static wchar_t s_title[64];
    static wchar_t s_body[256];
    wcscpy_s(s_title, title);
    wcscpy_s(s_body,  body);
    PostMessage(g_hwnd, WM_SHOW_BALLOON, (WPARAM)s_title, (LPARAM)s_body);
}

// ─── TTS Thread ──────────────────────────────────────────────────────────────
static void TTSThread() {
    CoInitializeEx(nullptr, COINIT_MULTITHREADED);

    ISpVoice* voice = nullptr;
    CoCreateInstance(CLSID_SpVoice, nullptr, CLSCTX_ALL, IID_ISpVoice, (void**)&voice);
    g_voice = voice;

    if (voice) {
        voice->SetRate(1);
        voice->SetVolume(100);

        // Route output to "Contrary TTS" virtual device (set up by setup_audio.ps1)
        ISpObjectToken* pAudioToken = FindAudioOutputToken(L"Contrary TTS");
        if (pAudioToken) {
            voice->SetOutput(pAudioToken, TRUE);
            pAudioToken->Release();
        } else {
            // Device not ready yet — warn user via tray balloon, fall back to default
            ShowTrayBalloon(
                L"Contrary TTS",
                L"Audio device not found. Run setup_audio.ps1 from the install folder.");
        }

        // Initial voice selection (English)
        SelectVoice(false);
    }

    while (g_appRunning.load()) {
        WaitForSingleObject(g_ttsEvent, INFINITE);
        if (!g_appRunning.load()) break;
        if (!g_hasNewText.load()) continue;

        // 400ms delay
        Sleep(400);

        std::wstring text;
        {
            EnterCriticalSection(&g_cs);
            text = g_pendingText;
            g_hasNewText = false;
            LeaveCriticalSection(&g_cs);
        }

        if (text.empty() || !voice) continue;

        bool needsHindi = HasDevanagari(text);
        SelectVoice(needsHindi);

        g_speaking = true;
        DrawLayered(g_hwnd, (BYTE)g_alpha.load()); // redraw dot white

        voice->Speak(text.c_str(), SPF_ASYNC | SPF_PURGEBEFORESPEAK, nullptr);
        voice->WaitUntilDone(INFINITE);

        g_speaking = false;
        DrawLayered(g_hwnd, (BYTE)g_alpha.load()); // redraw dot red

        // Auto-close
        PostMessage(g_hwnd, WM_COMMAND, MAKEWPARAM(0, 0xDEAD), 0);
    }

    if (voice) {
        voice->Release();
        g_voice = nullptr;
    }
    CoUninitialize();
}

// ─── Tray icon ────────────────────────────────────────────────────────────────
static HICON LoadAppIcon(int size) {
    // 1. Embedded resource
    HICON hIcon = (HICON)LoadImage(
        GetModuleHandle(nullptr), MAKEINTRESOURCE(IDI_ICON1),
        IMAGE_ICON, size, size, LR_DEFAULTCOLOR);
    if (hIcon) return hIcon;

    // 2. icon.ico beside the exe (absolute path)
    WCHAR path[MAX_PATH] = {};
    GetModuleFileName(nullptr, path, MAX_PATH);
    WCHAR* slash = wcsrchr(path, L'\\');
    if (slash) wcscpy_s(slash + 1, MAX_PATH - (int)(slash - path) - 1, L"icon.ico");
    hIcon = (HICON)LoadImage(nullptr, path, IMAGE_ICON,
                             size, size, LR_LOADFROMFILE | LR_DEFAULTCOLOR);
    if (hIcon) return hIcon;

    // 3. GDI fallback — red circle, never blank
    HDC     hdcScr = GetDC(nullptr);
    HDC     hdcMem = CreateCompatibleDC(hdcScr);
    HBITMAP hBmp   = CreateCompatibleBitmap(hdcScr, size, size);
    HBITMAP hMask  = CreateBitmap(size, size, 1, 1, nullptr);
    HBITMAP hOld   = (HBITMAP)SelectObject(hdcMem, hBmp);
    HBRUSH  hBg    = CreateSolidBrush(RGB(0x0f, 0x0e, 0x17));
    HBRUSH  hRed   = CreateSolidBrush(RGB(0xff, 0x46, 0x55));
    RECT    rc     = {0, 0, size, size};
    FillRect(hdcMem, &rc, hBg);
    SelectObject(hdcMem, hRed);
    SelectObject(hdcMem, GetStockObject(NULL_PEN));
    Ellipse(hdcMem, 1, 1, size - 1, size - 1);
    SelectObject(hdcMem, hOld);
    DeleteObject(hBg);
    DeleteObject(hRed);
    DeleteDC(hdcMem);
    ReleaseDC(nullptr, hdcScr);
    ICONINFO ii = {TRUE, 0, 0, hMask, hBmp};
    hIcon = CreateIconIndirect(&ii);
    DeleteObject(hBmp);
    DeleteObject(hMask);
    return hIcon;
}

static void AddTrayIcon(HWND hwnd) {
    g_nid.cbSize           = sizeof(g_nid);
    g_nid.hWnd             = hwnd;
    g_nid.uID              = 1;
    g_nid.uFlags           = NIF_ICON | NIF_MESSAGE | NIF_TIP;
    g_nid.uCallbackMessage = WM_TRAYICON;
    g_nid.hIcon            = LoadAppIcon(16);
    wcscpy_s(g_nid.szTip, L"Contrary Valorant TTS \x2014 Press F10");
    Shell_NotifyIcon(NIM_ADD, &g_nid);
}

static void ShowTrayMenu(HWND hwnd) {
    HMENU hMenu = CreatePopupMenu();
    AppendMenu(hMenu, MF_STRING | MF_GRAYED, IDM_TITLE,      L"Contrary Valorant TTS");
    AppendMenu(hMenu, MF_STRING,             IDM_HOTKEY_INFO, L"F10 \x2014 Toggle input");
    AppendMenu(hMenu, MF_STRING,             IDM_SETTINGS,    L"Settings");
    AppendMenu(hMenu, MF_SEPARATOR,          0,               nullptr);
    AppendMenu(hMenu, MF_STRING,             IDM_EXIT,        L"Exit");

    POINT pt;
    GetCursorPos(&pt);
    SetForegroundWindow(hwnd);
    TrackPopupMenu(hMenu, TPM_RIGHTBUTTON, pt.x, pt.y, 0, hwnd, nullptr);
    DestroyMenu(hMenu);
}

// ─── Settings window ─────────────────────────────────────────────────────────
static std::vector<std::wstring> g_voiceList; // populated when settings opens

static std::wstring GetVoiceCategory(const std::wstring& name) {
    if (name.find(L"Heera")!=std::wstring::npos || name.find(L"Ravi")!=std::wstring::npos)
        return L"Indian English";
    if (name.find(L"Hemant")!=std::wstring::npos || name.find(L"Kalpana")!=std::wstring::npos)
        return L"Hindi";
    if (name.find(L"Zira")!=std::wstring::npos || name.find(L"David")!=std::wstring::npos)
        return L"US English";
    if (name.find(L"Heather")!=std::wstring::npos || name.find(L"Mark")!=std::wstring::npos)
        return L"US English";
    return L"Other";
}

static LRESULT CALLBACK SettingsWndProc(HWND hw, UINT msg, WPARAM wp, LPARAM lp) {
    switch (msg) {
    case WM_CREATE: {
        // List box of voices
        CreateWindow(L"LISTBOX", nullptr,
            WS_CHILD|WS_VISIBLE|WS_VSCROLL|LBS_NOTIFY|LBS_NOINTEGRALHEIGHT,
            12, 50, 356, 200, hw, (HMENU)SETTINGS_LIST_ID, g_hInst, nullptr);
        // Apply button
        CreateWindow(L"BUTTON", L"Apply Voice",
            WS_CHILD|WS_VISIBLE|BS_PUSHBUTTON,
            12, 262, 110, 28, hw, (HMENU)SETTINGS_APPLY_ID, g_hInst, nullptr);
        // Re-run audio setup button
        CreateWindow(L"BUTTON", L"Re-run Audio Setup",
            WS_CHILD|WS_VISIBLE|BS_PUSHBUTTON,
            134, 262, 140, 28, hw, (HMENU)SETTINGS_SETUP_ID, g_hInst, nullptr);

        // Font for all controls
        LOGFONT lf={}; lf.lfHeight=-16; lf.lfQuality=CLEARTYPE_QUALITY;
        wcscpy_s(lf.lfFaceName, L"Segoe UI");
        HFONT hF = CreateFontIndirect(&lf);
        EnumChildWindows(hw, [](HWND c, LPARAM f)->BOOL{
            SendMessage(c, WM_SETFONT, f, TRUE); return TRUE;
        }, (LPARAM)hF);

        // Populate voices using STA COM (settings window is on main thread)
        CoInitialize(nullptr);
        g_voiceList.clear();
        HWND hList = GetDlgItem(hw, SETTINGS_LIST_ID);
        ISpObjectTokenCategory* pCat=nullptr;
        IEnumSpObjectTokens* pEnum=nullptr;
        SpGetCategoryFromId(SPCAT_VOICES, &pCat);
        if (pCat) { pCat->EnumTokens(nullptr,nullptr,&pEnum); pCat->Release(); }
        if (pEnum) {
            ISpObjectToken* pTok=nullptr;
            while (pEnum->Next(1,&pTok,nullptr)==S_OK) {
                WCHAR* d=nullptr; SpGetDescription(pTok,&d);
                if (d) {
                    std::wstring desc(d); CoTaskMemFree(d);
                    std::wstring cat = GetVoiceCategory(desc);
                    std::wstring label = cat + L"  —  " + desc;
                    SendMessage(hList, LB_ADDSTRING, 0, (LPARAM)label.c_str());
                    g_voiceList.push_back(desc); // store raw desc for saving
                    // Pre-select current voice
                    if (!g_selectedVoice.empty() &&
                        (g_selectedVoice==desc || desc.find(g_selectedVoice)!=std::wstring::npos))
                        SendMessage(hList, LB_SETCURSEL, g_voiceList.size()-1, 0);
                }
                pTok->Release();
            }
            pEnum->Release();
        }
        CoUninitialize();
        return 0;
    }
    case WM_COMMAND:
        if (LOWORD(wp)==SETTINGS_APPLY_ID || (LOWORD(wp)==SETTINGS_LIST_ID && HIWORD(wp)==LBN_DBLCLK)) {
            HWND hList = GetDlgItem(hw, SETTINGS_LIST_ID);
            int sel = (int)SendMessage(hList, LB_GETCURSEL, 0, 0);
            if (sel>=0 && sel<(int)g_voiceList.size()) {
                g_selectedVoice = g_voiceList[sel];
                RegSaveStr(L"SelectedVoice", g_selectedVoice);
                // Force re-select on TTS thread next speak
            }
            DestroyWindow(hw);
        }
        if (LOWORD(wp)==SETTINGS_SETUP_ID) {
            RunAudioSetupPS();
            MessageBox(hw, L"Audio setup started. Check Windows Sound Settings in ~30 seconds.",
                       L"Contrary TTS", MB_OK|MB_ICONINFORMATION);
        }
        return 0;
    case WM_ERASEBKGND: {
        HDC hdc=(HDC)wp; RECT r; GetClientRect(hw,&r);
        HBRUSH b=CreateSolidBrush(RGB(0x1a,0x1a,0x2e));
        FillRect(hdc,&r,b); DeleteObject(b);
        return 1;
    }
    case WM_PAINT: {
        PAINTSTRUCT ps; HDC hdc=BeginPaint(hw,&ps);
        SetBkMode(hdc,TRANSPARENT);
        SetTextColor(hdc,RGB(0xff,0xff,0xff));
        HFONT hF=(HFONT)GetStockObject(DEFAULT_GUI_FONT);
        SelectObject(hdc,hF);
        TextOut(hdc,12,12,L"Voice Settings — Contrary TTS",30);
        SetTextColor(hdc,RGB(0x99,0x99,0xbb));
        TextOut(hdc,12,30,L"Select voice then click Apply (or double-click):",48);
        EndPaint(hw,&ps);
        return 0;
    }
    case WM_CTLCOLORLISTBOX:
    case WM_CTLCOLORBTN:
    case WM_CTLCOLORSTATIC: {
        HDC hdc=(HDC)wp;
        SetTextColor(hdc,RGB(0xff,0xff,0xff));
        SetBkColor(hdc,RGB(0x12,0x12,0x20));
        static HBRUSH hbr=CreateSolidBrush(RGB(0x12,0x12,0x20));
        return (LRESULT)hbr;
    }
    case WM_DESTROY:
        g_settingsHwnd=nullptr;
        return 0;
    }
    return DefWindowProc(hw,msg,wp,lp);
}

static void ShowSettingsDialog() {
    if (g_settingsHwnd && IsWindow(g_settingsHwnd)) {
        SetForegroundWindow(g_settingsHwnd); return;
    }
    // Register settings class once
    static bool reg=false;
    if (!reg) {
        WNDCLASSEX wc={};
        wc.cbSize=sizeof(wc); wc.lpfnWndProc=SettingsWndProc;
        wc.hInstance=g_hInst; wc.lpszClassName=L"CVTTSSettings";
        wc.hbrBackground=(HBRUSH)GetStockObject(NULL_BRUSH);
        wc.hCursor=LoadCursor(nullptr,IDC_ARROW);
        RegisterClassEx(&wc); reg=true;
    }
    int sw=GetSystemMetrics(SM_CXSCREEN), sh=GetSystemMetrics(SM_CYSCREEN);
    g_settingsHwnd = CreateWindowEx(
        WS_EX_TOPMOST|WS_EX_TOOLWINDOW,
        L"CVTTSSettings", L"Contrary TTS — Settings",
        WS_POPUP|WS_CAPTION|WS_SYSMENU|WS_VISIBLE,
        (sw-380)/2, (sh-310)/2, 380, 310,
        g_hwnd, nullptr, g_hInst, nullptr);
}

// ─── Edit subclass: capture Enter/Esc, clear placeholder ─────────────────────
WNDPROC g_editOrigProc = nullptr;

static void TriggerSpeak(HWND hwnd) {
    int len = GetWindowTextLength(g_edit);
    if (len <= 0) { HideOverlay(); return; }
    std::wstring text(len + 1, L'\0');
    GetWindowText(g_edit, &text[0], len + 1);
    text.resize(len);

    if (text.empty()) { HideOverlay(); return; }

    EnterCriticalSection(&g_cs);
    g_pendingText  = text;
    g_hasNewText   = true;
    LeaveCriticalSection(&g_cs);
    SetEvent(g_ttsEvent);

    // Clear and close
    SetWindowText(g_edit, L"");
    HideOverlay();
}

static LRESULT CALLBACK EditSubclassProc(HWND hw, UINT msg, WPARAM wp, LPARAM lp) {
    if (msg == WM_KEYDOWN) {
        if (wp == VK_RETURN) { TriggerSpeak(hw); return 0; }
        if (wp == VK_ESCAPE) { HideOverlay(); return 0; }
    }
    if (msg == WM_CHAR) {
        if (g_placeholderActive) {
            if (wp != VK_BACK && wp != VK_RETURN && wp != VK_ESCAPE) {
                g_placeholderActive = false;
                SetWindowText(g_edit, L"");
                // Let the char fall through
            }
        }
    }
    return CallWindowProc(g_editOrigProc, hw, msg, wp, lp);
}

// ─── Main WndProc ─────────────────────────────────────────────────────────────
static LRESULT CALLBACK WndProc(HWND hwnd, UINT msg, WPARAM wp, LPARAM lp) {
    switch (msg) {
    case WM_CREATE: {
        // Create child EDIT — ES_CENTER for horizontal centering
        g_edit = CreateWindowEx(
            0, L"EDIT", L"",
            WS_CHILD | WS_VISIBLE | ES_AUTOHSCROLL | ES_CENTER,
            28, 0, OVL_W - 42, OVL_H,
            hwnd, (HMENU)EDIT_ID, g_hInst, nullptr);

        // Font: Segoe UI 15pt
        LOGFONT lf = {};
        lf.lfHeight         = -MulDiv(15, GetDeviceCaps(GetDC(nullptr), LOGPIXELSY), 72);
        lf.lfQuality        = CLEARTYPE_QUALITY;
        lf.lfCharSet        = DEFAULT_CHARSET;
        wcscpy_s(lf.lfFaceName, L"Segoe UI");
        HFONT hFont = CreateFontIndirect(&lf);
        SendMessage(g_edit, WM_SETFONT, (WPARAM)hFont, TRUE);

        // Transparent edit bg
        SetBkMode(GetDC(g_edit), TRANSPARENT);

        // Subclass
        g_editOrigProc = (WNDPROC)SetWindowLongPtr(g_edit, GWLP_WNDPROC, (LONG_PTR)EditSubclassProc);

        // Register F10 hotkey — use hwnd so WM_HOTKEY routes to WndProc
        RegisterHotKey(hwnd, HOTKEY_ID, 0, VK_F10);

        // Tray icon
        AddTrayIcon(hwnd);

        // Load saved voice name
        g_selectedVoice = RegLoadStr(L"SelectedVoice");

        // Auto audio setup on first run (background thread)
        CheckAndRunAudioSetup();

        // Start TTS thread
        g_ttsEvent = CreateEvent(nullptr, FALSE, FALSE, nullptr);
        InitializeCriticalSection(&g_cs);
        std::thread(TTSThread).detach();
        return 0;
    }

    case WM_HOTKEY:
        if (wp == HOTKEY_ID) {
            if (g_visible.load()) HideOverlay();
            else                  ShowOverlay();
        }
        return 0;

    case WM_COMMAND:
        // Auto-close signal from TTS thread
        if (HIWORD(wp) == 0xDEAD) {
            if (g_visible.load()) HideOverlay();
            return 0;
        }
        // Tray menu
        switch (LOWORD(wp)) {
        case IDM_SETTINGS:
            ShowSettingsDialog();
            return 0;
        case IDM_EXIT:
            g_appRunning = false;
            SetEvent(g_ttsEvent);
            Shell_NotifyIcon(NIM_DELETE, &g_nid);
            DestroyWindow(hwnd);
            return 0;
        }
        return 0;

    case WM_TRAYICON:
        if (lp == WM_RBUTTONUP || lp == WM_CONTEXTMENU)
            ShowTrayMenu(hwnd);
        return 0;

    case WM_TIMER:
        if (wp == FADE_TIMER_ID) {
            FadeDir dir = g_fadeDir.load();
            if (dir == FADE_IN) {
                int a = g_alpha.load() + FADE_IN_STEP;
                if (a >= TARGET_ALPHA) { a = TARGET_ALPHA; g_fadeDir = FADE_NONE; KillTimer(hwnd, FADE_TIMER_ID); }
                g_alpha = a;
                DrawLayered(hwnd, (BYTE)a);
            } else if (dir == FADE_OUT) {
                int a = g_alpha.load() - FADE_OUT_STEP;
                if (a <= 0) {
                    a = 0;
                    g_fadeDir = FADE_NONE;
                    KillTimer(hwnd, FADE_TIMER_ID);
                    ShowWindow(hwnd, SW_HIDE);
                    g_visible = false;
                }
                g_alpha = a;
                DrawLayered(hwnd, (BYTE)a);
            }
        }
        return 0;

    case WM_CTLCOLOREDIT: {
        HDC hdcEdit = (HDC)wp;
        SetTextColor(hdcEdit, RGB(0xff, 0xff, 0xff));  // white text
        SetBkColor(hdcEdit,   RGB(0x1a, 0x1a, 0x2e));  // match overlay bg
        SetBkMode(hdcEdit, OPAQUE);
        // Return a solid brush matching the bg so the edit is fully visible
        static HBRUSH hEditBg = CreateSolidBrush(RGB(0x1a, 0x1a, 0x2e));
        return (LRESULT)hEditBg;
    }

    case WM_ACTIVATE:
        SetWindowPos(hwnd, HWND_TOPMOST, 0, 0, 0, 0, SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE);
        return 0;

    case WM_SHOW_BALLOON: {
        // Called from TTS thread via PostMessage — safe to call Shell_NotifyIcon here
        const wchar_t* title = (const wchar_t*)wp;
        const wchar_t* body  = (const wchar_t*)lp;
        NOTIFYICONDATA nid   = g_nid;
        nid.uFlags           = NIF_INFO;
        nid.dwInfoFlags      = NIIF_WARNING;
        wcscpy_s(nid.szInfoTitle, title);
        wcscpy_s(nid.szInfo,      body);
        Shell_NotifyIcon(NIM_MODIFY, &nid);
        return 0;
    }

    case WM_DESTROY:
        UnregisterHotKey(hwnd, HOTKEY_ID);
        PostQuitMessage(0);
        return 0;
    }
    return DefWindowProc(hwnd, msg, wp, lp);
}

// ─── WinMain ─────────────────────────────────────────────────────────────────
int WINAPI WinMain(HINSTANCE hInst, HINSTANCE, LPSTR, int) {
    g_hInst = hInst;

    // Single-instance check
    HANDLE hMutex = CreateMutex(nullptr, TRUE, L"ContraryValorantTTS_Mutex");
    if (GetLastError() == ERROR_ALREADY_EXISTS) {
        CloseHandle(hMutex);
        return 0;
    }

    // GDI+
    Gdiplus::GdiplusStartupInput gdipInput;
    GdiplusStartup(&g_gdiplusToken, &gdipInput, nullptr);

    // Register window class
    WNDCLASSEX wc    = {};
    wc.cbSize        = sizeof(wc);
    wc.lpfnWndProc   = WndProc;
    wc.hInstance     = hInst;
    wc.lpszClassName = L"ContraryValorantTTSClass";
    wc.hCursor       = LoadCursor(nullptr, IDC_ARROW);
    wc.hbrBackground = (HBRUSH)GetStockObject(NULL_BRUSH);
    wc.hIcon         = LoadAppIcon(32);
    wc.hIconSm       = LoadAppIcon(16);
    RegisterClassEx(&wc);

    // Create the layered overlay window (hidden initially)
    int sw = GetSystemMetrics(SM_CXSCREEN);
    int x  = (sw - OVL_W) / 2;

    g_hwnd = CreateWindowEx(
        WS_EX_LAYERED | WS_EX_TOPMOST | WS_EX_TOOLWINDOW | WS_EX_NOACTIVATE,
        L"ContraryValorantTTSClass",
        L"Contrary Valorant TTS",
        WS_POPUP,
        x, OVL_TOP, OVL_W, OVL_H,
        nullptr, nullptr, hInst, nullptr);

    // Message loop
    MSG msg;
    while (GetMessage(&msg, nullptr, 0, 0)) {
        TranslateMessage(&msg);
        DispatchMessage(&msg);
    }

    Gdiplus::GdiplusShutdown(g_gdiplusToken);
    CloseHandle(hMutex);
    return (int)msg.wParam;
}
