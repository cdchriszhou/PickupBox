-- 拾音盒子 / Pickup Box install launcher: pick language, then open Installer.app

on run
	set languageChoices to {"English", "中文", "Français", "Português"}
	set picked to choose from list languageChoices ¬
		with title "拾音盒子 · Pickup Box" ¬
		with prompt "Select installation language
选择安装语言
Choisir la langue d’installation
Escolha o idioma da instalação" ¬
		default items {"中文"} ¬
		OK button name "Continue" ¬
		cancel button name "Cancel"
	if picked is false then return
	
	set chosen to item 1 of picked as text
	set langCode to "en"
	if chosen is "中文" then
		set langCode to "zh-Hans"
	else if chosen is "Français" then
		set langCode to "fr"
	else if chosen is "Português" then
		set langCode to "pt"
	end if
	
	set myPath to POSIX path of (path to me)
	if myPath ends with "/" then set myPath to text 1 thru -2 of myPath
	set pkgPath to myPath & "/Contents/Resources/PickupBox.pkg"
	
	try
		do shell script "/bin/test -f " & quoted form of pkgPath
	on error
		display alert "拾音盒子" message "Installer package missing:
" & pkgPath as critical
		return
	end try
	
	set installerBin to "/System/Library/CoreServices/Installer.app/Contents/MacOS/Installer"
	set cmd to "AppleLanguages='(" & langCode & ")' " & ¬
		quoted form of installerBin & " -AppleLanguages '(" & langCode & ")' " & ¬
		quoted form of pkgPath & " >/dev/null 2>&1 &"
	do shell script cmd
end run
