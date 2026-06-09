# OneTapFPS — Launcher Documentation

## Overview

The launcher is a **separate Godot project** (`PapaLeech/OneTapFPSLauncher`, branch `master`) that handles version checking, downloading the game PCK, and launching the game executable. It is distributed as a zip per platform and lives in `~/Games/OneTapFPS/` on the user's machine.

---

## Files on Disk (user machine)

```
~/Games/OneTapFPS/
├── OneTapFPS.x86_64          ← game binary (Linux)
├── OneTapFPS.pck             ← game data (downloaded/updated)
├── OneTapFPSLauncher.x86_64  ← launcher binary
├── OneTapFPSLauncher.sh      ← shell wrapper
└── version.cfg               ← stores local version string
```

### version.cfg format
```ini
[version]
local="0.4.99"
```

If this file is deleted, the launcher treats it as a fresh install and downloads the latest PCK.

---

## Architecture

The launcher is a single-scene Godot project with a `Launcher.gd` script. It uses `use_threads = true` for HTTP downloads and polls disk for progress every 0.5s (do NOT use `request_completed` signal with threads — use a timer poll instead).

### Scene Structure

```
Control (Launcher.gd)
├── CanvasLayer                   ← username prompt overlay
│   └── UsernamePanel             ← shown if no username saved
├── VBoxContainer
│   ├── LogoTexture               ← OneTapFPS logo
│   ├── StatusLabel               ← "Checking for updates...", "Up to date", etc.
│   ├── ProgressBar               ← download progress (0–100)
│   ├── VersionLabel              ← shows current version string
│   └── LaunchButton              ← "PLAY" button
└── Timer (0.5s)                  ← polls download progress
```

---

## Version Check Flow

On launch:
1. Read `version.cfg` → get `local` version string
2. HTTP GET `http://161.35.41.206:8000/version` → get `remote` version string
3. If versions match → show "Up to date", enable PLAY button
4. If versions differ → download new PCK, then launch

### Version endpoint response
```json
{"version": "0.4.99"}
```

---

## Download Flow

1. HTTP GET `http://161.35.41.206:8000/updates/file/size` → get file size in bytes
2. HTTP GET `http://161.35.41.206:8000/updates/file` → stream download to `~/Games/OneTapFPS/OneTapFPS.pck`
3. Poll disk every 0.5s: `actual_file_size / expected_size * 100` → update ProgressBar
4. On completion: write new version to `version.cfg`, enable PLAY button

### Progress Bar

- `ProgressBar` node, value 0–100
- `show_percentage = false` (clean look)
- Polled via Timer (0.5s interval) while download active
- Hidden when not downloading

---

## Server Endpoints Used by Launcher

| Endpoint | Method | Purpose |
|----------|--------|---------|
| `/version` | GET | Returns current game version |
| `/updates/file` | GET | Download client PCK |
| `/updates/file/size` | GET | Get PCK file size in bytes |
| `/download/linux` | GET | Alternative full download |
| `/download/windows` | GET | Windows PCK download |
| `/download/mac` | GET | Mac PCK download |

All endpoints are on `http://161.35.41.206:8000` (presence server, FastAPI).

---

## Username Prompt

If no username is saved, a `CanvasLayer` overlay appears (NOT a `Window` node — required for fullscreen focus). The player types their username and clicks confirm. Username is saved to `user://config.cfg` via `PresenceManager` or a local ConfigFile.

**Important**: Username prompt uses `CanvasLayer` overlay, not `Window`. This is intentional — `Window` nodes lose focus in fullscreen on Linux.

---

## Background Version Check

Added in Jun 2026: a Timer fires every 5 minutes while the launcher is idle. If a new version is detected, the launcher automatically downloads and updates without user interaction.

```gdscript
var _bg_check_timer : Timer  # 300s interval, autostart
```

---

## IPv4/IPv6 Detection

The launcher uses `_detect_server_url()` — same pattern as `PresenceManager.gd` in the game:
1. Try IPv6: `http://[2a03:b0c0:1:e0::1:7a5e:2001]:8000`
2. On failure, fall back to IPv4: `http://161.35.41.206:8000`

---

## Deploy / Distribution

Launcher zips are created from INSIDE each platform folder:
```bash
cd ~/Exports/OneTapFPS/Launchers/Linux
zip ../OneTapFPSLauncher_Linux.zip *
```

**No `-r` flag. No version numbers in filenames.** Always: `OneTapFPSLauncher_Linux.zip`, `OneTapFPSLauncher_Windows.zip`, `OneTapFPSLauncher_Mac.zip`.

Uploaded to: `onetapfps.itch.io/onetapfps`

---

## Key Variables in Launcher.gd

```gdscript
const SERVER_URL    : String  # e.g. "http://161.35.41.206:8000"
const VERSION_PATH  : String  # "user://version.cfg" or path next to exe
const PCK_SAVE_PATH : String  # path to save downloaded PCK

var _http_version   : HTTPRequest
var _http_download  : HTTPRequest
var _poll_timer     : Timer    # 0.5s disk poll for download progress
var _bg_timer       : Timer    # 300s background version check
var _expected_size  : int      # bytes expected for current download
```

---

## Important Notes for Other AI

1. **DO NOT use `request_completed` signal for download progress** — use a 0.5s Timer polling actual file size on disk instead. `use_threads = true` makes the signal unreliable for progress.
2. **Username prompt is a CanvasLayer overlay**, not a Window node. This is required for fullscreen focus on Linux.
3. **Deleting `version.cfg`** forces a full re-download on next launch — useful for troubleshooting stale PCKs.
4. The launcher downloads to `~/Games/OneTapFPS/OneTapFPS.pck` — the game binary (`OneTapFPS.x86_64`) is NOT updated by the launcher. Binary updates require manual upload via `deploy_server_binary.sh` equivalent for client.
5. Both presence server instances (IPv4 + IPv6) serve the same PCK via shared SQLite state.
6. The launcher and game are **separate Godot projects** with separate git repos.
