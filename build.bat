@echo off
setlocal enabledelayedexpansion

echo [Contrary Valorant TTS] Build starting...
echo.

:: ─── 1. Generate icon via Python ─────────────────────────────────────────────
where python >nul 2>&1
if errorlevel 1 (
    echo [ERROR] Python not found in PATH. Install Python 3.11+.
    exit /b 1
)

echo [STEP 1/4] Generating icon...
python generate_icon.py
if errorlevel 1 (
    echo [ERROR] generate_icon.py failed.
    exit /b 1
)
if not exist "icon.ico" (
    echo [ERROR] icon.ico was not created. Check generate_icon.py output.
    exit /b 1
)
echo [OK] icon.ico ready.
echo.

:: ─── 2. Locate vswhere ────────────────────────────────────────────────────────
set VSWHERE="%ProgramFiles(x86)%\Microsoft Visual Studio\Installer\vswhere.exe"
if not exist %VSWHERE% set VSWHERE="%ProgramFiles%\Microsoft Visual Studio\Installer\vswhere.exe"
if not exist %VSWHERE% (
    echo [ERROR] vswhere.exe not found. Install Visual Studio 2019 or 2022 with C++ workload.
    exit /b 1
)

for /f "usebackq delims=" %%i in (`%VSWHERE% -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath`) do (
    set VS_PATH=%%i
)
if not defined VS_PATH (
    echo [ERROR] No Visual Studio with MSVC toolchain found.
    exit /b 1
)

set VCVARS="%VS_PATH%\VC\Auxiliary\Build\vcvarsall.bat"
if not exist %VCVARS% (
    echo [ERROR] vcvarsall.bat not found at: %VCVARS%
    exit /b 1
)

echo [INFO] Using VS at: %VS_PATH%
call %VCVARS% x64 > nul 2>&1
if errorlevel 1 (
    echo [ERROR] Failed to initialize MSVC environment.
    exit /b 1
)

:: ─── 3. Compile resource file ─────────────────────────────────────────────────
echo [STEP 2/4] Compiling resource file...

(
    echo // auto-generated
    echo #include ^<windows.h^>
    echo IDI_ICON1 ICON "icon.ico"
) > app.rc

rc.exe /nologo app.rc
if errorlevel 1 (
    echo [ERROR] rc.exe failed to compile app.rc
    exit /b 1
)
echo [OK] app.res ready.
echo.

:: ─── 4. Compile EXE ───────────────────────────────────────────────────────────
echo [STEP 3/4] Compiling ContraryValorantTTS.exe...

cl.exe /O2 /W3 /EHsc /DUNICODE /D_UNICODE /DWIN32 /D_WINDOWS /nologo ^
    main.cpp app.res ^
    /Fe:ContraryValorantTTS.exe ^
    /link user32.lib gdi32.lib gdiplus.lib sapi.lib ole32.lib shell32.lib kernel32.lib ^
    /SUBSYSTEM:WINDOWS

if errorlevel 1 (
    echo.
    echo [ERROR] Compilation failed.
    exit /b 1
)
echo [OK] ContraryValorantTTS.exe built.
echo.

:: ─── 5. NSIS installer ────────────────────────────────────────────────────────
echo [STEP 4/4] Building installer...

set MAKENSIS=
where makensis >nul 2>&1 && set MAKENSIS=makensis
if not defined MAKENSIS (
    if exist "C:\Program Files (x86)\NSIS\makensis.exe" (
        set MAKENSIS="C:\Program Files (x86)\NSIS\makensis.exe"
    )
)
if not defined MAKENSIS (
    if exist "C:\Program Files\NSIS\makensis.exe" (
        set MAKENSIS="C:\Program Files\NSIS\makensis.exe"
    )
)

if not defined MAKENSIS (
    echo [SKIP] NSIS not found — skipping installer.
    echo        Install from: https://nsis.sourceforge.io
    echo.
    goto :summary
)

:: NSIS requires a plain-text license file
if not exist "LICENSE_INSTALLER.txt" (
    copy LICENSE LICENSE_INSTALLER.txt > nul 2>&1
)

%MAKENSIS% /V2 installer.nsi
if errorlevel 1 (
    echo [ERROR] makensis failed.
    exit /b 1
)
echo [OK] ContraryValorantTTS-Setup.exe built.
echo.

:summary
echo ════════════════════════════════════
echo  BUILD COMPLETE
echo ════════════════════════════════════
if exist "ContraryValorantTTS.exe"       echo  [OK] ContraryValorantTTS.exe
if exist "ContraryValorantTTS-Setup.exe" echo  [OK] ContraryValorantTTS-Setup.exe
echo ════════════════════════════════════

endlocal
