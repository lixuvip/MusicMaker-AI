@echo off
chcp 65001 >nul
setlocal enabledelayedexpansion
cd /d "%~dp0"

set "PYTHON_CMD="
for %%P in (py python python3) do (
  where %%P >nul 2>nul
  if not errorlevel 1 if not defined PYTHON_CMD set "PYTHON_CMD=%%P"
)

if not defined PYTHON_CMD (
  echo 未找到 Python 启动器.
  echo 请先安装 Python 3.11+:
  echo https://www.python.org/downloads/windows/
  echo 并确保 PATH 里可以使用 py 或 python.
  pause
  exit /b 1
)

echo Using Python launcher: %PYTHON_CMD%
%PYTHON_CMD% --version
if errorlevel 1 (
  echo 无法通过 "%PYTHON_CMD%" 启动 Python.
  echo 请检查 Python 安装, 然后重新打开终端再试.
  pause
  exit /b 1
)

where powershell >nul 2>nul
if errorlevel 1 (
  echo 当前系统没有可用的 PowerShell.
  echo 自动下载和解压 FFmpeg 需要 PowerShell.
  echo 请先把 ffmpeg.exe 放到当前目录, 然后再运行脚本.
  pause
  exit /b 1
)

%PYTHON_CMD% -m pip install --upgrade pip pyinstaller
if errorlevel 1 (
  echo pip 或 PyInstaller 安装失败.
  echo 请检查网络, 或手动执行:
  echo %PYTHON_CMD% -m pip install --upgrade pip pyinstaller
  pause
  exit /b 1
)

:: FFmpeg
set "FFMPEG_EXE=%cd%\ffmpeg.exe"

if not exist "%FFMPEG_EXE%" (
  echo Downloading FFmpeg...

  :: Primary - gyan.dev (30s timeout)
  powershell -NoProfile -Command ^
    "$ProgressPreference = 'SilentlyContinue'; " ^
    "[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; " ^
    "try { Invoke-WebRequest -Uri 'https://www.gyan.dev/ffmpeg/builds/ffmpeg-release-essentials.zip' -OutFile '%TEMP%\ffmpeg.zip' -TimeoutSec 30 } catch { exit 1 }"
  if exist "%TEMP%\ffmpeg.zip" (set "FFMPEG_OK=1") else (set "FFMPEG_OK=0")

  :: Fallback - BtbN GitHub release (60s timeout)
  if "!FFMPEG_OK!"=="0" (
    echo Primary download timed out. Trying GitHub mirror...
    powershell -NoProfile -Command ^
      "$ProgressPreference = 'SilentlyContinue'; " ^
      "[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; " ^
      "try { Invoke-WebRequest -Uri 'https://github.com/BtbN/FFmpeg-Builds/releases/download/latest/ffmpeg-master-latest-win64-gpl.zip' -OutFile '%TEMP%\ffmpeg.zip' -TimeoutSec 60 } catch { exit 1 }"
    if exist "%TEMP%\ffmpeg.zip" (set "FFMPEG_OK=1") else (set "FFMPEG_OK=0")
  )

  if "!FFMPEG_OK!"=="0" (
    echo.
    echo ERROR: Failed to download FFmpeg from both sources.
    echo 无法自动下载 FFmpeg.
    echo 请手动下载 ffmpeg.exe:
    echo https://ffmpeg.org/download.html
    echo 然后放到当前目录:
    echo %cd%
    pause
    exit /b 1
  )

  echo Extracting FFmpeg...
  powershell -NoProfile -Command ^
    "Expand-Archive -Path '%TEMP%\ffmpeg.zip' -DestinationPath '%TEMP%\ffmpeg_extract' -Force"
  if errorlevel 1 (
    echo ERROR: Failed to extract FFmpeg archive.
    echo FFmpeg 压缩包已下载, 但解压失败.
    pause
    exit /b 1
  )

  for /d %%d in ("%TEMP%\ffmpeg_extract\*") do (
    copy /y "%%d\bin\ffmpeg.exe" "%FFMPEG_EXE%" >nul 2>nul
  )

  if exist "%TEMP%\ffmpeg.zip" del "%TEMP%\ffmpeg.zip"
  if exist "%TEMP%\ffmpeg_extract" rmdir /s /q "%TEMP%\ffmpeg_extract"

  if not exist "%FFMPEG_EXE%" (
    echo ERROR: ffmpeg.exe not found after extraction.
    echo 自动解压后没有找到 ffmpeg.exe.
    echo 请手动把 ffmpeg.exe 放到项目目录后再运行.
    pause
    exit /b 1
  )
  echo FFmpeg ready: %FFMPEG_EXE%
)

:: PyInstaller build
%PYTHON_CMD% -m PyInstaller ^
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
echo FFmpeg is bundled inside the exe. No separate installation is required.
pause
