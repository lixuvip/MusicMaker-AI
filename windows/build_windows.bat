@echo off
setlocal enabledelayedexpansion
cd /d "%~dp0"

python --version >nul 2>nul
if errorlevel 1 (
  echo Python is required. Install Python 3.11+ from https://www.python.org/downloads/windows/
  pause
  exit /b 1
)

python -m pip install --upgrade pyinstaller
if errorlevel 1 (
  pause
  exit /b 1
)

:: ── FFmpeg ─────────────────────────────────────────────────────
set "FFMPEG_EXE=%cd%\ffmpeg.exe"

if not exist "%FFMPEG_EXE%" (
  echo Downloading FFmpeg …

  :: Primary — gyan.dev (30s timeout)
  powershell -NoProfile -Command ^
    "$ProgressPreference = 'SilentlyContinue'; " ^
    "[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; " ^
    "try { Invoke-WebRequest -Uri 'https://www.gyan.dev/ffmpeg/builds/ffmpeg-release-essentials.zip' -OutFile '%TEMP%\ffmpeg.zip' -TimeoutSec 30 } catch { exit 1 }"
  if exist "%TEMP%\ffmpeg.zip" (set "FFMPEG_OK=1") else (set "FFMPEG_OK=0")

  :: Fallback — BtbN GitHub release (60s timeout)
  if "!FFMPEG_OK!"=="0" (
    echo Primary timed out, trying GitHub mirror …
    powershell -NoProfile -Command ^
      "$ProgressPreference = 'SilentlyContinue'; " ^
      "[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; " ^
      "try { Invoke-WebRequest -Uri 'https://github.com/BtbN/FFmpeg-Builds/releases/download/latest/ffmpeg-master-latest-win64-gpl.zip' -OutFile '%TEMP%\ffmpeg.zip' -TimeoutSec 60 } catch { exit 1 }"
    if exist "%TEMP%\ffmpeg.zip" (set "FFMPEG_OK=1") else (set "FFMPEG_OK=0")
  )

  if "!FFMPEG_OK!"=="0" (
    echo.
    echo ERROR: Failed to download FFmpeg from both sources.
    echo Please manually download ffmpeg.exe from https://ffmpeg.org/download.html
    echo and place it in: %cd%
    pause
    exit /b 1
  )

  echo Extracting FFmpeg …
  powershell -NoProfile -Command ^
    "Expand-Archive -Path '%TEMP%\ffmpeg.zip' -DestinationPath '%TEMP%\ffmpeg_extract' -Force"
  if errorlevel 1 (
    echo ERROR: Failed to extract FFmpeg archive.
    pause
    exit /b 1
  )

  for /d %%d in ("%TEMP%\ffmpeg_extract\*") do (
    copy /y "%%d\bin\ffmpeg.exe" "%FFMPEG_EXE%" >nul 2>nul
  )

  if exist "%TEMP%\ffmpeg.zip" del "%TEMP%\ffmpeg.zip"
  if exist "%TEMP%\ffmpeg_extract" rmdir /s /q "%TEMP%\ffmpeg_extract"

  if not exist "%FFMPEG_EXE%" (
    echo ERROR: ffmpeg.exe not found after extraction. Place ffmpeg.exe in the project root manually.
    pause
    exit /b 1
  )
  echo FFmpeg ready: %FFMPEG_EXE%
)

:: ── PyInstaller build ──────────────────────────────────────────
python -m PyInstaller ^
  --noconfirm ^
  --clean ^
  --onefile ^
  --windowed ^
  --name "MusicMaker-AI" ^
  --icon "assets\app_icon.ico" ^
  --add-binary "ffmpeg.exe;." ^
  musicmaker_ai_windows.py

echo.
echo Built: %cd%\dist\MusicMaker-AI.exe
echo.
echo FFmpeg bundled inside the exe — no separate installation needed.
pause
