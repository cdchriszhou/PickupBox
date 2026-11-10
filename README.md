# 拾音盒子 · Pickup Box（macOS）

一个看得见音乐的播放器。拟物 Hi-Fi：频谱、卡带 / 唱机、世界调谐器与塔箱喇叭。

> 本分支仅含 **macOS** 工程。Windows 版见 [`windows`](https://github.com/cdchriszhou/PickupBox/tree/windows) 分支；总览见 [`main`](https://github.com/cdchriszhou/PickupBox/tree/main)。

**作者** KK-Files　·　**联系** 827212416（微信同号）　·　**版本** V1.0.0

## 环境

- macOS 13+（建议）
- Xcode Command Line Tools（`clang++`、AppKit）

## 构建

```bash
git clone -b macos https://github.com/cdchriszhou/PickupBox.git
cd PickupBox
make
open build/PickupBox.app
```

产物：`build/PickupBox.app`

## 安装包

```bash
make dist
# 或
make installer
```

| 文件 | 说明 |
|------|------|
| `dist/拾音盒子 Install.app` | 先选语言再安装（推荐） |
| `dist/PickupBox-1.0.0.pkg` | 标准 macOS 安装向导 |
| `dist/PickupBox-1.0.0.dmg` | 磁盘映像：App 拖装 + 安装器 |

预编译安装包见 [Releases · macos-v1.0.0](https://github.com/cdchriszhou/PickupBox/releases/tag/macos-v1.0.0)。

可选自签名：

```bash
SIGN_IDENTITY="你的证书名称" make installer
```

## 目录

```
Sources/     ObjC++ 应用（AppKit 拟物 UI + 音频）
Resources/   Info.plist、图标等
Packaging/   pkgbuild / productbuild / DMG 脚本
Makefile     编译与打包入口
```
