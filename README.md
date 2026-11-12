# 拾音盒子 — 原生 Qt6 / C++ 双卡听音室

这是用 **Qt6 Widgets + C++** 重写的版本（非 Python/PySide6）。

## 依赖

- Qt 6.8+（需 **Widgets** + **Multimedia**）
- CMake ≥ 3.21
- MSVC 2022 / Build Tools（与 `msvc2022_64` kit 匹配）

本机示例路径：`D:\Qt\6.8.3\msvc2022_64`

## 编译

在 **x64 Native Tools / vcvars64** 环境中：

```bat
call "C:\Program Files (x86)\Microsoft Visual Studio\18\BuildTools\VC\Auxiliary\Build\vcvars64.bat"
cd /d D:\Works\CursorSpace\KaLaOK\qt6
cmake -S . -B build -G "Ninja" -DCMAKE_PREFIX_PATH=D:/Qt/6.8.3/msvc2022_64
cmake --build build --config Release
```

若无 Visual Studio 生成器：

```bat
cmake -S . -B build -G "Visual Studio 17 2022" -A x64 -DCMAKE_PREFIX_PATH=D:/Qt/6.8.3/msvc2022_64
cmake --build build --config Release
```

## 运行

```bat
build\Release\FH_KAOK.exe
build\Release\FH_KAOK.exe D:\path\to\song.mp3
```

首次运行若缺 DLL，可：

```bat
D:\Qt\6.8.3\msvc2022_64\bin\windeployqt.exe build\Release\FH_KAOK.exe
```

## 说明

- 界面为 `QPainter` 精细绘制（音箱 / VFD / 旋钮 / 双卡）
- 播放：`QMediaPlayer` + `QAudioOutput`
- 实时电平：`QAudioBufferOutput`（需 FFmpeg 后端，Qt Multimedia 自带）
