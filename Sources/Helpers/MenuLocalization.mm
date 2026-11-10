#import "MenuLocalization.h"

static NSString * const kMenuLangKey = @"com.kkfiles.PickupBox.menuLanguage";

@implementation MenuLocalization

+ (MenuLanguage)currentLanguage {
    if (![[NSUserDefaults standardUserDefaults] objectForKey:kMenuLangKey]) {
        return MenuLanguageEnglish; // default English
    }
    NSInteger v = [[NSUserDefaults standardUserDefaults] integerForKey:kMenuLangKey];
    if (v < MenuLanguageEnglish || v > MenuLanguagePortuguese) return MenuLanguageEnglish;
    return (MenuLanguage)v;
}

+ (void)setCurrentLanguage:(MenuLanguage)language {
    [[NSUserDefaults standardUserDefaults] setInteger:language forKey:kMenuLangKey];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

+ (NSArray<NSDictionary *> *)languageChoices {
    return @[
        @{ @"lang": @(MenuLanguageEnglish),    @"title": @"English" },
        @{ @"lang": @(MenuLanguageChinese),    @"title": @"中文" },
        @{ @"lang": @(MenuLanguageFrench),     @"title": @"Français" },
        @{ @"lang": @(MenuLanguagePortuguese), @"title": @"Português" },
    ];
}

+ (NSDictionary<NSString *, NSDictionary<NSString *, NSString *> *> *)catalog {
    // key → { en, zh, fr, pt }
    return @{
        @"app": @{
            @"en": @"Pickup Box", @"zh": @"拾音盒子",
            @"fr": @"Pickup Box", @"pt": @"Pickup Box"
        },
        @"about": @{
            @"en": @"About Pickup Box", @"zh": @"关于拾音盒子",
            @"fr": @"À propos de Pickup Box", @"pt": @"Sobre o Pickup Box"
        },
        @"quit": @{
            @"en": @"Quit Pickup Box", @"zh": @"退出拾音盒子",
            @"fr": @"Quitter Pickup Box", @"pt": @"Sair do Pickup Box"
        },
        @"file": @{
            @"en": @"File", @"zh": @"文件",
            @"fr": @"Fichier", @"pt": @"Arquivo"
        },
        @"open_music": @{
            @"en": @"Open Local Music…", @"zh": @"打开本地音乐…",
            @"fr": @"Ouvrir la musique locale…", @"pt": @"Abrir música local…"
        },
        @"close_window": @{
            @"en": @"Close Window", @"zh": @"关闭窗口",
            @"fr": @"Fermer la fenêtre", @"pt": @"Fechar janela"
        },
        @"playback": @{
            @"en": @"Playback", @"zh": @"播放",
            @"fr": @"Lecture", @"pt": @"Reprodução"
        },
        @"play_pause": @{
            @"en": @"Play / Pause", @"zh": @"播放 / 暂停",
            @"fr": @"Lecture / Pause", @"pt": @"Reproduzir / Pausar"
        },
        @"stop": @{
            @"en": @"Stop", @"zh": @"停止",
            @"fr": @"Arrêt", @"pt": @"Parar"
        },
        @"radio": @{
            @"en": @"Radio", @"zh": @"电台",
            @"fr": @"Radio", @"pt": @"Rádio"
        },
        @"china_cities": @{
            @"en": @"Major Cities in China", @"zh": @"中国主要城市",
            @"fr": @"Grandes villes de Chine", @"pt": @"Principais cidades da China"
        },
        @"china": @{
            @"en": @"China", @"zh": @"中国",
            @"fr": @"Chine", @"pt": @"China"
        },
        @"japan": @{
            @"en": @"Japan", @"zh": @"日本",
            @"fr": @"Japon", @"pt": @"Japão"
        },
        @"world_cities": @{
            @"en": @"World Cities", @"zh": @"全球城市",
            @"fr": @"Villes du monde", @"pt": @"Cidades do mundo"
        },
        @"world": @{
            @"en": @"World", @"zh": @"全球",
            @"fr": @"Monde", @"pt": @"Mundo"
        },
        @"brand": @{
            @"en": @"Fascia", @"zh": @"面板",
            @"fr": @"Façade", @"pt": @"Painel"
        },
        @"settings": @{
            @"en": @"Settings", @"zh": @"设置",
            @"fr": @"Réglages", @"pt": @"Ajustes"
        },
        @"language": @{
            @"en": @"Language", @"zh": @"语言",
            @"fr": @"Langue", @"pt": @"Idioma"
        },
        @"help": @{
            @"en": @"Help", @"zh": @"帮助",
            @"fr": @"Aide", @"pt": @"Ajuda"
        },
        @"howto": @{
            @"en": @"How to Use", @"zh": @"操作说明",
            @"fr": @"Mode d’emploi", @"pt": @"Como usar"
        },
        @"ok": @{
            @"en": @"OK", @"zh": @"好",
            @"fr": @"OK", @"pt": @"OK"
        },
        @"about_title": @{
            @"en": @"Pickup Box", @"zh": @"拾音盒子",
            @"fr": @"Pickup Box", @"pt": @"Pickup Box"
        },
        @"about_body": @{
            @"en":
                @"Pickup Box — a player that lets you see the music\n"
                @"Skeuomorphic hi-fi with spectrum, cassette / phono deck, and world tuner\n\n"
                @"· Internet radio for major cities in China / Japan / worldwide\n"
                @"· Local music playback\n"
                @"· Tower speakers that pulse with the audio\n\n"
                @"Station directory from the Radio Browser public database.",
            @"zh":
                @"拾音盒子 — 一个看得见音乐的播放器\n"
                @"拟物 Hi-Fi：频谱、卡带 / 唱机、世界调谐器\n\n"
                @"· 中国 / 日本 / 全球主要城市网络电台\n"
                @"· 本地音乐播放\n"
                @"· 塔箱喇叭随音频颤动\n\n"
                @"电台目录来自 Radio Browser 公共数据库。",
            @"fr":
                @"Pickup Box — un lecteur qui laisse voir la musique\n"
                @"Hi-Fi réaliste : spectre, cassette / phono, tuner monde\n\n"
                @"· Radios Internet des grandes villes (Chine / Japon / monde)\n"
                @"· Lecture de musique locale\n"
                @"· Enceintes colonnes qui vibrent avec l’audio\n\n"
                @"Annuaire des stations issu de la base publique Radio Browser.",
            @"pt":
                @"Pickup Box — um leitor que deixa ver a música\n"
                @"Hi-Fi realista: espectro, cassete / phono, sintonizador mundial\n\n"
                @"· Rádio pela Internet de grandes cidades (China / Japão / mundo)\n"
                @"· Reprodução de música local\n"
                @"· Caixas de som que vibram com o áudio\n\n"
                @"Lista de estações da base pública Radio Browser."
        },
        // %@ = CFBundleShortVersionString
        @"about_credits": @{
            @"en":
                @"Version: %@\n"
                @"Author: KK-Files\n"
                @"Contact: WeChat / QQ 827212416",
            @"zh":
                @"版本：%@\n"
                @"作者：KK-Files\n"
                @"联系：微信 / QQ 827212416",
            @"fr":
                @"Version : %@\n"
                @"Auteur : KK-Files\n"
                @"Contact : WeChat / QQ 827212416",
            @"pt":
                @"Versão: %@\n"
                @"Autor: KK-Files\n"
                @"Contato: WeChat / QQ 827212416"
        },
        @"howto_title": @{
            @"en": @"How to Use", @"zh": @"操作说明",
            @"fr": @"Mode d’emploi", @"pt": @"Como usar"
        },
        @"howto_body": @{
            @"en":
                @"[Listen to radio]\n"
                @"1. Switch China / Japan / WORLD on the tuner\n"
                @"2. Browse cities with ◀ ▶ and click the city key\n"
                @"3. Pick a station in the amber list to play\n\n"
                @"You can also use the Radio menu to jump to a city.\n\n"
                @"[Local music] File → Open, or press EJECT\n"
                @"[Volume] VOLUME knob · MUTE\n"
                @"[Speakers] Woofer cones pulse while playing",
            @"zh":
                @"【选城收听】\n"
                @"1. 中间调谐器切换「中国 / 日本 / WORLD」\n"
                @"2. 用 ◀ ▶ 浏览城市，点击城市按键\n"
                @"3. 在琥珀色电台列表中点选电台即播放\n\n"
                @"也可使用菜单「电台」直接选择城市。\n\n"
                @"【本地音乐】文件 → 打开，或点 EJECT\n"
                @"【音量】大旋钮 VOLUME · MUTE 静音\n"
                @"【喇叭】播放时左右塔箱低音单元颤动",
            @"fr":
                @"[Écouter la radio]\n"
                @"1. Choisissez Chine / Japon / WORLD sur le tuner\n"
                @"2. Parcourez les villes avec ◀ ▶ et cliquez la touche ville\n"
                @"3. Sélectionnez une station dans la liste ambre\n\n"
                @"Le menu Radio permet aussi d’ouvrir une ville.\n\n"
                @"[Musique locale] Fichier → Ouvrir, ou touche EJECT\n"
                @"[Volume] Bouton VOLUME · MUTE\n"
                @"[Enceintes] Les woofers vibrent pendant la lecture",
            @"pt":
                @"[Ouvir rádio]\n"
                @"1. Alterne China / Japão / WORLD no sintonizador\n"
                @"2. Navegue pelas cidades com ◀ ▶ e toque a tecla da cidade\n"
                @"3. Escolha uma estação na lista âmbar para tocar\n\n"
                @"O menu Rádio também permite saltar para uma cidade.\n\n"
                @"[Música local] Arquivo → Abrir, ou tecla EJECT\n"
                @"[Volume] Botão VOLUME · MUTE\n"
                @"[Caixas] Os woofers vibram durante a reprodução"
        },
        @"open_panel_title": @{
            @"en": @"Load Local Music", @"zh": @"装载本地音乐",
            @"fr": @"Charger la musique locale", @"pt": @"Carregar música local"
        },
        @"open_panel_message": @{
            @"en": @"Choose a folder to import in bulk, or select multiple MP3 and other audio files.",
            @"zh": @"可选择文件夹批量导入，或直接多选 MP3 等音频文件",
            @"fr": @"Choisissez un dossier pour importer en lot, ou sélectionnez plusieurs fichiers MP3 et autres.",
            @"pt": @"Escolha uma pasta para importar em lote, ou selecione vários ficheiros MP3 e outros."
        },
        @"open_panel_prompt": @{
            @"en": @"Load", @"zh": @"装载",
            @"fr": @"Charger", @"pt": @"Carregar"
        },
        @"no_audio_title": @{
            @"en": @"No Playable Audio Found", @"zh": @"未找到可播放的音频",
            @"fr": @"Aucun fichier audio lisible", @"pt": @"Nenhum áudio reproduzível"
        },
        @"no_audio_body": @{
            @"en": @"Select a folder that contains MP3 / M4A / WAV files, or choose the audio files directly.",
            @"zh": @"请选择包含 MP3 / M4A / WAV 等文件的文件夹，或直接选择音频文件。",
            @"fr": @"Sélectionnez un dossier contenant des fichiers MP3 / M4A / WAV, ou choisissez les fichiers audio.",
            @"pt": @"Selecione uma pasta com ficheiros MP3 / M4A / WAV, ou escolha os ficheiros de áudio."
        },
        @"play_failed_title": @{
            @"en": @"Playback Failed", @"zh": @"播放失败",
            @"fr": @"Échec de la lecture", @"pt": @"Falha na reprodução"
        },
    };
}

+ (NSString *)langCode {
    switch ([self currentLanguage]) {
        case MenuLanguageChinese:    return @"zh";
        case MenuLanguageFrench:     return @"fr";
        case MenuLanguagePortuguese: return @"pt";
        default:                     return @"en";
    }
}

+ (NSString *)stringForKey:(NSString *)key {
    NSDictionary *entry = [self catalog][key];
    if (!entry) return key ?: @"";
    NSString *code = [self langCode];
    NSString *s = entry[code];
    if (s.length) return s;
    return entry[@"en"] ?: key;
}

@end
