@echo off
setlocal
cd /d "%~dp0"
call build.bat || exit /b 1
call deploy.bat || exit /b 1
start "" "%~dp0build\FH_KAOK.exe" %*
exit /b 0
