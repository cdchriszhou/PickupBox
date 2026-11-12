@echo off
call "C:\Program Files (x86)\Microsoft Visual Studio\18\BuildTools\VC\Auxiliary\Build\vcvars64.bat" || exit /b 1
"D:\Qt\6.8.3\msvc2022_64\bin\windeployqt.exe" --release --no-translations "%~dp0build\FH_KAOK.exe"
exit /b %ERRORLEVEL%
