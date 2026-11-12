@echo off
setlocal
call "C:\Program Files (x86)\Microsoft Visual Studio\18\BuildTools\VC\Auxiliary\Build\vcvars64.bat" || exit /b 1
cd /d "%~dp0"
if not exist build mkdir build
cmake -S . -B build -G "NMake Makefiles" -DCMAKE_PREFIX_PATH=D:/Qt/6.8.3/msvc2022_64 -DCMAKE_BUILD_TYPE=Release
if errorlevel 1 exit /b 1
cmake --build build
exit /b %ERRORLEVEL%
