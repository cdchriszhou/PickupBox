; 拾音盒子 Windows Installer
; Version 1.0.0  Author: KK-Files  Contact: QQ 827212416  2026.11 Chengdu

#define MyAppName "拾音盒子"
#define MyAppDisplayName "拾音盒子"
#define MyAppVersion "1.0.0"
#define MyAppPublisher "KK-Files"
#define MyAppExeName "FH_KAOK.exe"

[Setup]
AppId={{E8C4A7B1-5D2F-4A91-9C3E-7B6A1F0D8E22}
AppName={#MyAppDisplayName}
AppVersion={#MyAppVersion}
AppVerName={#MyAppDisplayName} V{#MyAppVersion}
AppPublisher={#MyAppPublisher}
AppCopyright=Copyright (C) 2026 KK-Files
DefaultDirName={autopf}\{#MyAppName}
DefaultGroupName={#MyAppDisplayName}
DisableProgramGroupPage=no
LicenseFile=assets\license.txt
OutputDir=output
OutputBaseFilename=拾音盒子-Setup-V{#MyAppVersion}
SetupIconFile=assets\setup.ico
Compression=lzma2/ultra64
SolidCompression=yes
WizardStyle=modern
WizardSizePercent=140
WizardImageFile=assets\wizard.bmp
WizardSmallImageFile=assets\wizard-small.bmp
WizardImageStretch=yes
DisableWelcomePage=no
ShowLanguageDialog=no
PrivilegesRequired=admin
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
UninstallDisplayIcon={app}\{#MyAppExeName}
UninstallDisplayName={#MyAppDisplayName} V{#MyAppVersion}
VersionInfoVersion={#MyAppVersion}.0
VersionInfoCompany={#MyAppPublisher}
VersionInfoDescription={#MyAppDisplayName} Installer
VersionInfoProductName={#MyAppDisplayName}
VersionInfoProductVersion={#MyAppVersion}
VersionInfoCopyright=Copyright (C) 2026 KK-Files
CloseApplications=yes
MinVersion=10.0

[Languages]
; Use Default.isl keys; Chinese UI strings overridden below
Name: "zh"; MessagesFile: "compiler:Default.isl"; LicenseFile: "assets\license.txt"

[Messages]
WelcomeLabel1=欢迎来到 [name]
WelcomeLabel2=这不是一台冰冷的播放器，而是一间被缩小的听音室。%n%n双卡仓静候磁带，FM 刻度游走城市电台，琥珀色 VFD 随节拍呼吸，音箱纸盆随着波形微微颤动。%n%n作者：KK-Files%n联系：QQ 827212416%n版本：V1.0.0%n时间：2026.11 · 成都%n%n安装只需片刻——像按下 PLAY 之前，先深吸一口气。
FinishedHeadingLabel=[name] 已就位
FinishedLabel=安装完成。%n%n从今晚起，让旋律慢慢铺开。%n愿琥珀色的灯火，陪您把每一首歌听到尽头。%n%n— KK-Files%nQQ 827212416 · 2026.11 成都
ClickFinish=点击「完成」，推开听音室的门。
SelectDirDesc=为 [name] 安一个安静的角落
SelectDirLabel3=它将被安置在下列文件夹——您也可以另择一处，如同给音箱选位置。
SelectDirBrowseLabel=准备好了请点「下一步」；想换个地方，请点「浏览」。
WizardSelectDir=选择安放位置
WizardReady=准备按下 PLAY
ReadyLabel1=一切就绪。接下来，只差轻轻一按。
ReadyLabel2a=点击「安装」开始，或返回上一步再确认一次。
ReadyLabel2b=点击「安装」，让机身落定。
WizardInstalling=正在装配
InstallingLabel=请稍候——螺丝旋紧，指示灯即将点亮…
WizardLicense=听音前的约定
LicenseLabel=请先读完这段短简，再继续。
LicenseLabel3=以下是许可约定。接受后，才可推开仓门。
LicenseAccepted=我接受这份约定(&A)
LicenseNotAccepted=我暂不接受(&D)
ButtonBack=< 上一步(&B)
ButtonNext=下一步(&N) >
ButtonInstall=安装(&I)
ButtonFinish=完成(&F)
ButtonCancel=取消
ButtonBrowse=浏览(&R)...
BeveledLabel=拾音盒子 V1.0.0  ·  KK-Files  ·  QQ 827212416  ·  2026.11 成都
SetupAppTitle=安装向导
SetupWindowTitle=安装向导 — %1
ExitSetupTitle=先离开吗？
ExitSetupMessage=安装尚未完成。若现在离开，机身还不会出现在您的电脑上。%n%n以后随时可以再次运行本向导。%n%n确定退出吗？
StatusExtractFiles=正在展开零件…
StatusCreateIcons=正在摆放快捷方式…
StatusCreateDirs=正在铺设目录…
StatusSavingUninstall=正在记下卸载线索…
StatusRunProgram=正在完成最后一圈…
ConfirmUninstall=确定要将 %1 从这间听音室里完全撤走吗？
UninstallStatusLabel=请稍候，正在轻轻拆除 %1…
UninstalledAll=%1 已离开这台电脑。有缘，旋律再会。

[CustomMessages]
LaunchAfter=安装完成后，立刻推开听音室的门
CreateDesktopIcon=在桌面留下一枚快捷方式(&D)
AdditionalIcons=附加图标：
AssocHint=复古高保真 · 城市电台 · 本地磁带
UninstallProgram=卸载 %1

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
Source: "payload\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "payload\vc_redist.x64.exe"; DestDir: "{tmp}"; Flags: deleteafterinstall

[Icons]
Name: "{group}\{#MyAppDisplayName}"; Filename: "{app}\{#MyAppExeName}"; Comment: "{cm:AssocHint}"
Name: "{group}\{cm:UninstallProgram,{#MyAppDisplayName}}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\{#MyAppDisplayName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon; Comment: "{cm:AssocHint}"

[Run]
Filename: "{tmp}\vc_redist.x64.exe"; Parameters: "/install /quiet /norestart"; StatusMsg: "正在安放运行库，请稍候…"; Flags: waituntilterminated
Filename: "{app}\{#MyAppExeName}"; Description: "{cm:LaunchAfter}"; Flags: nowait postinstall skipifsilent

[Code]
procedure InitializeWizard();
begin
  WizardForm.WelcomeLabel1.Font.Size := 16;
  WizardForm.WelcomeLabel1.Font.Style := [fsBold];
  WizardForm.WelcomeLabel2.Font.Size := 10;
  WizardForm.FinishedLabel.Font.Size := 10;
end;
