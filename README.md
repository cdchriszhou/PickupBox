# 拾音盒子 · PickupBox

复古高保真听音室：双卡仓、城市电台、琥珀色 VFD 与音箱律动。  
作者：KK-Files · QQ 827212416 · 2026 · 成都

## 仓库结构

本仓库用**平台长驻分支**分别存放 Windows / macOS 两套工程，安装包挂在 GitHub Releases，避免大二进制进入 Git 历史。

| 分支 / 产物 | 内容 |
|---|---|
| [`main`](https://github.com/cdchriszhou/PickupBox/tree/main) | 门户说明（本页） |
| [`windows`](https://github.com/cdchriszhou/PickupBox/tree/windows) | Windows 版 Qt6 / C++ 源码与安装脚本 |
| [`macos`](https://github.com/cdchriszhou/PickupBox/tree/macos) | macOS 版源码（待上传） |
| [Releases](https://github.com/cdchriszhou/PickupBox/releases) | 各平台安装包 |

## 下载安装包

- **Windows**：[PickupBox-Setup-Windows-V1.2.0.exe](https://github.com/cdchriszhou/PickupBox/releases/download/windows-v1.2.0/PickupBox-Setup-Windows-V1.2.0.exe) · [Release 说明](https://github.com/cdchriszhou/PickupBox/releases/tag/windows-v1.2.0)
- **macOS**：待发布

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
```

（工程与构建说明随 `macos` 分支一并提供。）

## 发版约定

- Windows 标签：`windows-vX.Y.Z`
- macOS 标签：`macos-vX.Y.Z`
- 对应平台分支打标签后，将安装包上传为该 Release 的附件
