@echo off
setlocal enabledelayedexpansion
cd /d "%~dp0"

set "PYTHON_CMD="
for %%P in (py python python3) do (
  where %%P >nul 2>nul
  if not errorlevel 1 if not defined PYTHON_CMD set "PYTHON_CMD=%%P"
)

if not defined PYTHON_CMD (
  echo Python is required. Install Python 3.11+ from https://www.python.org/downloads/windows/
  echo Make sure py or python is available in PATH.
  pause
  exit /b 1
)

call :run_python --version
if errorlevel 1 (
  echo Failed to start Python with %PYTHON_CMD%.
  pause
  exit /b 1
)

call :run_python -m pip install --upgrade pyinstaller
if errorlevel 1 (
  echo Failed to install PyInstaller.
  echo Try this manually: %PYTHON_CMD% -m pip install --upgrade pyinstaller
  pause
  exit /b 1
)

set "FFMPEG_EXE=%cd%\ffmpeg.exe"
if not exist "%FFMPEG_EXE%" call :download_ffmpeg
if errorlevel 1 exit /b 1

call :run_python -m PyInstaller --noconfirm --clean --onefile --windowed --name MusicMaker-AI --icon "assets\app_icon.ico" --add-binary "ffmpeg.exe;." musicmaker_ai_windows.py
if errorlevel 1 (
  echo PyInstaller build failed.
  pause
  exit /b 1
)

echo.
echo Built: %cd%\dist\MusicMaker-AI.exe
echo.
echo FFmpeg is bundled inside the exe. No separate installation is required.
pause
exit /b 0

:run_python
if /i "%PYTHON_CMD%"=="py" (
  py -3 %*
) else (
  %PYTHON_CMD% %*
)
exit /b %errorlevel%

:download_ffmpeg
where powershell >nul 2>nul
if errorlevel 1 (
  echo PowerShell is required to download FFmpeg automatically.
  echo Place ffmpeg.exe in this folder and run the script again.
  pause
  exit /b 1
)

echo Downloading FFmpeg...
powershell -NoProfile -Command "$ProgressPreference='SilentlyContinue'; [Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12; try { Invoke-WebRequest -Uri 'https://www.gyan.dev/ffmpeg/builds/ffmpeg-release-essentials.zip' -OutFile \"$env:TEMP\\ffmpeg.zip\" -TimeoutSec 30 } catch { exit 1 }"
if not exist "%TEMP%\ffmpeg.zip" (
  echo Primary download timed out. Trying GitHub mirror...
  powershell -NoProfile -Command "$ProgressPreference='SilentlyContinue'; [Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12; try { Invoke-WebRequest -Uri 'https://github.com/BtbN/FFmpeg-Builds/releases/download/latest/ffmpeg-master-latest-win64-gpl.zip' -OutFile \"$env:TEMP\\ffmpeg.zip\" -TimeoutSec 60 } catch { exit 1 }"
)

if not exist "%TEMP%\ffmpeg.zip" (
  echo.
  echo ERROR: Failed to download FFmpeg from both sources.
  echo Download ffmpeg.exe manually from https://ffmpeg.org/download.html
  echo Then place it in: %cd%
  pause
  exit /b 1
)

echo Extracting FFmpeg...
powershell -NoProfile -Command "Expand-Archive -Path \"$env:TEMP\\ffmpeg.zip\" -DestinationPath \"$env:TEMP\\ffmpeg_extract\" -Force"
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
  echo ERROR: ffmpeg.exe not found after extraction.
  echo Place ffmpeg.exe in the project folder and run the script again.
  pause
  exit /b 1
)

echo FFmpeg ready: %FFMPEG_EXE%
exit /b 0
