; ─── Contrary Valorant TTS — NSIS Installer ───────────────────────────────────
; Requires: NSIS 3.x + MUI2 plugin (bundled with NSIS)

Unicode true

!include "MUI2.nsh"
!include "LogicLib.nsh"

; ─── General ──────────────────────────────────────────────────────────────────
Name              "Contrary Valorant TTS"
OutFile           "ContraryValorantTTS-Setup.exe"
InstallDir        "$PROGRAMFILES64\ContraryValorantTTS"
InstallDirRegKey  HKCU "Software\ContraryValorantTTS" "InstallDir"
RequestExecutionLevel user
SetCompressor     /SOLID lzma
BrandingText      "Contrary — Valorant TTS Overlay"

; ─── Version info ─────────────────────────────────────────────────────────────
VIProductVersion  "1.0.0.0"
VIAddVersionKey   "ProductName"      "Contrary Valorant TTS"
VIAddVersionKey   "ProductVersion"   "1.0.0"
VIAddVersionKey   "CompanyName"      "Contrary"
VIAddVersionKey   "LegalCopyright"   "Copyright (c) 2025 Ayush (Contrary)"
VIAddVersionKey   "FileDescription"  "In-game TTS overlay for Valorant"
VIAddVersionKey   "FileVersion"      "1.0.0"

; ─── MUI2 Settings ────────────────────────────────────────────────────────────
!define MUI_ICON   "icon.ico"
!define MUI_UNICON "icon.ico"

!define MUI_HEADERIMAGE
!define MUI_ABORTWARNING
!define MUI_FINISHPAGE_RUN          "$INSTDIR\ContraryValorantTTS.exe"
!define MUI_FINISHPAGE_RUN_TEXT     "Launch Contrary Valorant TTS"
!define MUI_FINISHPAGE_RUN_CHECKED

; Optional desktop shortcut checkbox on finish page
!define MUI_FINISHPAGE_SHOWREADME          ""
!define MUI_FINISHPAGE_SHOWREADME_CHECKED

; ─── Pages ────────────────────────────────────────────────────────────────────
!insertmacro MUI_PAGE_WELCOME
!insertmacro MUI_PAGE_LICENSE "LICENSE_INSTALLER.txt"
!insertmacro MUI_PAGE_DIRECTORY
!insertmacro MUI_PAGE_INSTFILES
!insertmacro MUI_PAGE_FINISH

!insertmacro MUI_UNPAGE_CONFIRM
!insertmacro MUI_UNPAGE_INSTFILES

!insertmacro MUI_LANGUAGE "English"

; ─── Desktop shortcut var ─────────────────────────────────────────────────────
Var DesktopShortcut

; ─── Install Section ──────────────────────────────────────────────────────────
Section "Install" SecMain

    SetOutPath "$INSTDIR"

    ; Copy files
    File "ContraryValorantTTS.exe"
    File "icon.ico"

    ; Write uninstaller
    WriteUninstaller "$INSTDIR\uninstall.exe"

    ; Registry — install dir
    WriteRegStr HKCU "Software\ContraryValorantTTS" "InstallDir" "$INSTDIR"

    ; Add/Remove Programs entry
    WriteRegStr HKCU \
        "Software\Microsoft\Windows\CurrentVersion\Uninstall\ContraryValorantTTS" \
        "DisplayName"     "Contrary Valorant TTS"
    WriteRegStr HKCU \
        "Software\Microsoft\Windows\CurrentVersion\Uninstall\ContraryValorantTTS" \
        "DisplayIcon"     "$INSTDIR\icon.ico"
    WriteRegStr HKCU \
        "Software\Microsoft\Windows\CurrentVersion\Uninstall\ContraryValorantTTS" \
        "UninstallString" '"$INSTDIR\uninstall.exe"'
    WriteRegStr HKCU \
        "Software\Microsoft\Windows\CurrentVersion\Uninstall\ContraryValorantTTS" \
        "DisplayVersion"  "1.0.0"
    WriteRegStr HKCU \
        "Software\Microsoft\Windows\CurrentVersion\Uninstall\ContraryValorantTTS" \
        "Publisher"       "Contrary"
    WriteRegStr HKCU \
        "Software\Microsoft\Windows\CurrentVersion\Uninstall\ContraryValorantTTS" \
        "InstallLocation" "$INSTDIR"
    WriteRegDWORD HKCU \
        "Software\Microsoft\Windows\CurrentVersion\Uninstall\ContraryValorantTTS" \
        "NoModify" 1
    WriteRegDWORD HKCU \
        "Software\Microsoft\Windows\CurrentVersion\Uninstall\ContraryValorantTTS" \
        "NoRepair"  1

    ; Start Menu shortcut
    CreateDirectory "$SMPROGRAMS\Contrary"
    CreateShortcut  "$SMPROGRAMS\Contrary\Contrary Valorant TTS.lnk" \
                    "$INSTDIR\ContraryValorantTTS.exe" "" \
                    "$INSTDIR\icon.ico" 0

    ; Desktop shortcut
    CreateShortcut  "$DESKTOP\Contrary Valorant TTS.lnk" \
                    "$INSTDIR\ContraryValorantTTS.exe" "" \
                    "$INSTDIR\icon.ico" 0

SectionEnd

; ─── Uninstall Section ────────────────────────────────────────────────────────
Section "Uninstall"

    Delete "$INSTDIR\ContraryValorantTTS.exe"
    Delete "$INSTDIR\icon.ico"
    Delete "$INSTDIR\uninstall.exe"
    RMDir  "$INSTDIR"

    ; Shortcuts
    Delete "$SMPROGRAMS\Contrary\Contrary Valorant TTS.lnk"
    RMDir  "$SMPROGRAMS\Contrary"
    Delete "$DESKTOP\Contrary Valorant TTS.lnk"

    ; Registry
    DeleteRegKey HKCU "Software\ContraryValorantTTS"
    DeleteRegKey HKCU \
        "Software\Microsoft\Windows\CurrentVersion\Uninstall\ContraryValorantTTS"

SectionEnd
