@echo off
call "C:\Program Files (x86)\Microsoft Visual Studio\18\BuildTools\VC\Auxiliary\Build\vcvars64.bat" || exit /b 1
cd /d "%~dp0..\build"
cl /nologo /EHsc /std:c++17 /Zc:__cplusplus /permissive- /MD /I "D:\Qt\6.8.3\msvc2022_64\include" /I "D:\Qt\6.8.3\msvc2022_64\include\QtCore" /I "D:\Qt\6.8.3\msvc2022_64\include\QtMultimedia" /I "D:\Qt\6.8.3\msvc2022_64\include\QtGui" /DQT_CORE_LIB /DQT_MULTIMEDIA_LIB /DQT_GUI_LIB /Fe:playtest.exe ..\tools\playtest.cpp /link /LIBPATH:"D:\Qt\6.8.3\msvc2022_64\lib" Qt6Core.lib Qt6Multimedia.lib Qt6Gui.lib /SUBSYSTEM:CONSOLE || exit /b 1
set QT_PLUGIN_PATH=D:\Qt\6.8.3\msvc2022_64\plugins
set PATH=D:\Qt\6.8.3\msvc2022_64\bin;%PATH%
playtest.exe "D:\Works\CursorSpace\KaLaOK\assets\demo_tone.mp3"
echo EXIT=%ERRORLEVEL%
exit /b %ERRORLEVEL%
