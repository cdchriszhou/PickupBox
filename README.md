# 拾音盒子 · PickupBox

复古高保真听音室：双卡仓、城市电台、琥珀色 VFD 与音箱律动。  
作者：KK-Files · QQ 827212416 · 2026 · 成都

## 仓库结构

本仓库用**平台长驻分支**分别存放 Windows / macOS 两套工程，安装包挂在 GitHub Releases，避免大二进制进入 Git 历史。

| 分支 / 产物 | 内容 |
|---|---|
| [`main`](https://github.com/cdchriszhou/PickupBox/tree/main) | 门户说明（本页） |
| [`windows`](https://github.com/cdchriszhou/PickupBox/tree/windows) | Windows 版 Qt6 / C++ 源码与安装脚本 |
| [`macos`](https://github.com/cdchriszhou/PickupBox/tree/macos) | macOS 版 AppKit / ObjC++ 源码与安装脚本 |
| [Releases](https://github.com/cdchriszhou/PickupBox/releases) | 各平台安装包 |

## 下载安装包

- **Windows**：[PickupBox-Setup-Windows-V1.0.0.exe](https://github.com/cdchriszhou/PickupBox/releases/download/windows-v1.0.0/PickupBox-Setup-Windows-V1.0.0.exe) · [Release 说明](https://github.com/cdchriszhou/PickupBox/releases/tag/windows-v1.0.0)
- **macOS**：[PickupBox-macOS-V1.0.0.dmg](https://github.com/cdchriszhou/PickupBox/releases/download/macos-v1.0.0/PickupBox-macOS-V1.0.0.dmg) · [PKG](https://github.com/cdchriszhou/PickupBox/releases/download/macos-v1.0.0/PickupBox-macOS-V1.0.0.pkg) · [语言安装器 ZIP](https://github.com/cdchriszhou/PickupBox/releases/download/macos-v1.0.0/PickupBox-Install-macOS-V1.0.0.zip) · [Release 说明](https://github.com/cdchriszhou/PickupBox/releases/tag/macos-v1.0.0)

macOS 推荐：下载 DMG 后打开 **「拾音盒子 Install.app」**（先选语言再安装），或将 App 拖入 Applications。

## 开发指引

### Windows

```bat
git clone -b windows https://github.com/cdchriszhou/PickupBox.git
cd PickupBox
build.bat
```

生成安装包：

```bat
cd installer
build_installer.bat
```

依赖：Qt 6.8+（Widgets + Multimedia）、CMake、MSVC、Inno Setup 6。

### macOS

```bash
git clone -b macos https://github.com/cdchriszhou/PickupBox.git
cd PickupBox
make
open build/PickupBox.app
```

生成安装包：

```bash
make dist
```

依赖：Xcode Command Line Tools（`clang++`、AppKit）。

## 发版约定

- Windows 标签：`windows-vX.Y.Z`
- macOS 标签：`macos-vX.Y.Z`
- 对应平台分支打标签后，将安装包上传为该 Release 的附件
