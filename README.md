<div align="center">

<img src="icon_256.png" width="120" alt="Contrary Valorant TTS Logo" />

# Contrary Valorant TTS

**Press F10. Type. Speak. That's it.**

[![Build](https://github.com/USERNAME/Contrary-Valorant-TTS/actions/workflows/build.yml/badge.svg)](https://github.com/USERNAME/Contrary-Valorant-TTS/actions/workflows/build.yml)
[![Release](https://img.shields.io/github/v/release/USERNAME/Contrary-Valorant-TTS)](https://github.com/USERNAME/Contrary-Valorant-TTS/releases/latest)
![License](https://img.shields.io/badge/license-MIT-blue)
![Platform](https://img.shields.io/badge/platform-Windows%2010%2F11-0078d4)

</div>

---

## Table of Contents

- [What is this?](#what-is-this)
- [Download & Install](#download--install)
- [Features](#features)
- [Build from Source](#build-from-source)
- [Voices & Hinglish](#voices--hinglish)
- [License](#license)

---

## What is this?

A small tool that sits in your system tray. Press F10 while in Valorant, type what you want to say, hit Enter — your computer speaks it out loud through your mic. No alt-tab, no window switching, nothing.

It works with any fullscreen app, not just Valorant.

<!-- demo.gif -->

---

## Download & Install

### [⬇ Download Latest Installer](../../releases/latest)

1. Download `ContraryValorantTTS-Setup.exe` from the link above
2. Run the installer, click Next a few times
3. Launch from the Start Menu or Desktop shortcut
4. Press **F10** in Valorant to open the text box
5. Type what you want said, press **Enter**

> **Note:** Valorant must be in **Borderless Window** mode for the overlay to appear on top of the game.

> **Mic routing:** To speak through your mic in-game, install [VB-Cable](https://vb-audio.com/Cable/) (free) and set it as your default playback device. Valorant mic input = VB-Cable Output.

---

## Features

- **F10 hotkey toggle** — works while any app is fullscreen
- **400ms natural delay** before speaking (sounds less robotic)
- **Hinglish support** — mix English and Hindi freely (`"bhai 1v1 kar"`, `"I'll entry"`)
- **Devanagari script support** — auto-selects Hindi voice if installed on Windows
- **Semi-transparent overlay** — doesn't block your screen, fades in/out smoothly
- **System tray icon** — runs silently in the background, no taskbar clutter
- **No internet required** — fully offline, uses Windows built-in voices

---

## Build from Source

### Requirements

- Windows 10 or 11
- Visual Studio 2019 or 2022 with **"Desktop development with C++"** workload
- Python 3.11+ with Pillow: `pip install pillow`
- NSIS *(optional, for installer)*: https://nsis.sourceforge.io
- Git + GitHub CLI (`gh`) for repo management

### Quick Build

```bat
git clone https://github.com/USERNAME/Contrary-Valorant-TTS
cd Contrary-Valorant-TTS
build.bat
```

Outputs: `ContraryValorantTTS.exe` and `ContraryValorantTTS-Setup.exe` (if NSIS is installed).

### What build.bat Does

- Runs `generate_icon.py` (Pillow) → `icon.ico` + `icon_256.png`
- Compiles `app.rc` resource file via `rc.exe` → `app.res`
- MSVC `cl.exe` compiles `main.cpp` + `app.res` with SAPI + GDI+ + Win32
- `makensis` compiles `installer.nsi` → Setup EXE *(skipped if NSIS not installed)*

### CI/CD

- GitHub Actions workflow: `.github/workflows/build.yml`
- Every push to `main`: builds EXE + installer, uploads as artifacts
- Tagged push (`v*`): auto-creates a GitHub Release with both files attached
- Uses: `ilammy/msvc-dev-cmd` (MSVC), Chocolatey (NSIS), Pillow (icon gen)

### Project Structure

```
Contrary-Valorant-TTS/
├── main.cpp                  # Full Win32 + SAPI overlay implementation
├── generate_icon.py          # Pillow icon generator
├── app.rc                    # Windows resource file (icon embed)
├── installer.nsi             # NSIS installer script
├── build.bat                 # Local build script (MSVC + NSIS)
├── .github/
│   └── workflows/
│       └── build.yml         # GitHub Actions CI pipeline
└── README.md
```

---

## Voices & Hinglish

The app uses Windows SAPI (Speech API) — the same engine as Windows Narrator. No third-party voices needed.

**Install more voices:**
Settings → Time & Language → Speech → Add voices.
Recommended: **English (United States)** for Romanized Hinglish. For actual Devanagari, install the **Hindi (India)** voice pack.

| Input type | Example | Recommended Voice |
|---|---|---|
| English | `"I'm going mid"` | Microsoft Zira / David |
| Romanized Hindi | `"bhai entry de"` | Microsoft Zira / David |
| Devanagari Hindi | `"भाई एंट्री दे"` | Microsoft Kalpana / Hemant |
| Hinglish mixed | `"1v1 kar na yaar"` | Microsoft Zira / David |

The app auto-detects Devanagari characters (Unicode U+0900–U+097F) and switches to a Hindi voice automatically. If no Hindi voice is installed, it falls back to English — SAPI skips characters it can't pronounce gracefully.

---

## License

```
MIT License

Copyright (c) 2025 Ayush (Contrary)

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```
