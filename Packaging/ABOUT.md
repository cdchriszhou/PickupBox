# 拾音盒子 · Pickup Box

**一个看得见音乐的播放器**  
**版本** V1.0.0  
**作者** KK-Files  
**联系** 827212416（微信同号）

## 安装包内容

| 文件 | 说明 |
|------|------|
| `dist/拾音盒子 Install.app` | **推荐**：先选语言，再打开系统安装向导 |
| `dist/PickupBox-1.0.0.pkg` | 裸 PKG（语言跟随系统偏好） |
| `dist/PickupBox-1.0.0.dmg` | 磁盘映像：含 Install.app、App、Applications 快捷方式 |

## 安装流程（多语言）

1. 打开 **拾音盒子 Install.app**
2. 选择 **English / 中文 / Français / Português**
3. 系统 Installer 按所选语言显示欢迎 / 手札 / 许可 / 完成页

## 生成

```bash
bash Packaging/build_installer.sh
# 或
make dist
```

## 自签名安装包

默认是 **ad-hoc**（`codesign -s -`）：本机可开，别人机器仍会提示无法验证开发者。

若要 **自签证书** 签 App + PKG：

1. 打开 **钥匙串访问** → 菜单 **证书助理** → **创建证书…**
2. 名称例如 `拾音盒子 Developer`
3. 身份类型：**自签名根证书**
4. 证书类型：**代码签名**
5. 勾选「覆盖默认值」→ 一直下一步，把「密钥用法」里的代码签名勾上

```bash
# 查看可用签名身份
security find-identity -v -p codesigning

# 用该身份打包（App + Install.app + PKG）
SIGN_IDENTITY="拾音盒子 Developer" make installer

# PKG 若要用另一张「Installer」类证书：
SIGN_IDENTITY="拾音盒子 Developer" \
INSTALLER_IDENTITY="拾音盒子 Installer" \
make installer
```

说明：自签**不能**通过 Gatekeeper / 公证；分发时对方仍需右键 → 打开，或到「隐私与安全性」里允许。要免提示分发需 Apple **Developer ID** + `notarytool` 公证。
