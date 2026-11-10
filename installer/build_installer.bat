@echo off
setlocal
cd /d "%~dp0\.."

echo [1/3] Building FH_KAOK...
call build.bat || exit /b 1

echo [2/3] Deploying Qt runtime...
call deploy.bat || exit /b 1

echo [3/3] Staging payload and compiling installer...
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0stage_payload.ps1" || exit /b 1

set "ISCC=%LOCALAPPDATA%\Programs\Inno Setup 6\ISCC.exe"
if not exist "%ISCC%" set "ISCC=C:\Program Files (x86)\Inno Setup 6\ISCC.exe"
if not exist "%ISCC%" (
  echo ERROR: Inno Setup 6 not found. Install with: winget install JRSoftware.InnoSetup
  exit /b 1
)

"%ISCC%" "%~dp0FH_KAOK.iss" || exit /b 1
echo.
echo Installer ready:
dir /b "%~dp0output\*.exe"
exit /b 0
