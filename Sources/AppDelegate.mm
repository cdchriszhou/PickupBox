#import "AppDelegate.h"
#import "MainConsoleView.h"
#import "AudioEngine.h"
#import "RadioCatalog.h"
#import "BrandProfile.h"
#import "MenuLocalization.h"

@interface AppDelegate ()
@property (nonatomic, strong) NSWindow *window;
@property (nonatomic, strong) MainConsoleView *console;
@end

@implementation AppDelegate

- (void)applyAppIcon {
    // Force Dock / app switcher icon (LaunchServices often caches .icns for unsigned local builds)
    NSBundle *bundle = [NSBundle mainBundle];
    NSString *pngPath = [bundle pathForResource:@"AppIcon" ofType:@"png"];
    NSString *icnsPath = [bundle pathForResource:@"AppIcon" ofType:@"icns"];
    NSImage *icon = nil;
    if (pngPath.length) icon = [[NSImage alloc] initWithContentsOfFile:pngPath];
    if (!icon && icnsPath.length) icon = [[NSImage alloc] initWithContentsOfFile:icnsPath];
    if (icon) {
        icon = [icon copy];
        icon.size = NSMakeSize(1024, 1024);
        [NSApp setApplicationIconImage:icon];
    }
}

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    [self applyAppIcon];

    NSRect screen = [[NSScreen mainScreen] visibleFrame];
    CGFloat width = MIN(1360, screen.size.width - 40);
    CGFloat height = MIN(860, screen.size.height - 40);
    NSRect frame = NSMakeRect(NSMidX(screen) - width * 0.5,
                              NSMidY(screen) - height * 0.5,
                              width, height);

    NSUInteger style = NSWindowStyleMaskTitled
                     | NSWindowStyleMaskClosable
                     | NSWindowStyleMaskMiniaturizable
                     | NSWindowStyleMaskResizable;

    self.window = [[NSWindow alloc] initWithContentRect:frame
                                              styleMask:style
                                                backing:NSBackingStoreBuffered
                                                  defer:NO];
    self.window.title = @"拾音盒子 — Pickup Box";
    self.window.backgroundColor = [NSColor colorWithCalibratedWhite:0.05 alpha:1];
    self.window.minSize = NSMakeSize(1100, 720);

    self.console = [[MainConsoleView alloc] initWithFrame:((NSView *)self.window.contentView).bounds];
    self.console.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    [self.window.contentView addSubview:self.console];

    [self buildMenu];
    [self.window makeKeyAndOrderFront:nil];
    [NSApp activateIgnoringOtherApps:YES];
    // Re-apply after activation — Dock sometimes ignores the first set
    dispatch_async(dispatch_get_main_queue(), ^{ [self applyAppIcon]; });
}

- (NSString *)L:(NSString *)key {
    return [MenuLocalization stringForKey:key];
}

- (void)addCities:(NSArray<RadioCity *> *)cities toMenu:(NSMenu *)menu {
    for (RadioCity *c in cities) {
        // City names stay bilingual (catalog data) — menu language only wraps section titles
        NSString *title = [NSString stringWithFormat:@"%@  (%@)", c.nameCN, c.nameEN];
        NSMenuItem *item = [menu addItemWithTitle:title action:@selector(selectCity:) keyEquivalent:@""];
        item.target = self;
        item.representedObject = c.nameCN;
    }
}

- (void)buildMenu {
    NSMenu *menubar = [[NSMenu alloc] init];
    NSApp.mainMenu = menubar;

    // —— App ——
    NSMenuItem *appItem = [[NSMenuItem alloc] init];
    [menubar addItem:appItem];
    NSMenu *appMenu = [[NSMenu alloc] initWithTitle:[self L:@"app"]];
    [appMenu addItemWithTitle:[self L:@"about"] action:@selector(showAbout:) keyEquivalent:@""];
    [appMenu addItem:[NSMenuItem separatorItem]];
    [appMenu addItemWithTitle:[self L:@"quit"] action:@selector(terminate:) keyEquivalent:@"q"];
    appItem.submenu = appMenu;

    // —— File ——
    NSMenuItem *fileItem = [[NSMenuItem alloc] init];
    [menubar addItem:fileItem];
    NSMenu *fileMenu = [[NSMenu alloc] initWithTitle:[self L:@"file"]];
    NSMenuItem *openItem = [fileMenu addItemWithTitle:[self L:@"open_music"]
                                               action:@selector(openMusic:)
                                        keyEquivalent:@"o"];
    openItem.target = self;
    [fileMenu addItem:[NSMenuItem separatorItem]];
    [fileMenu addItemWithTitle:[self L:@"close_window"] action:@selector(performClose:) keyEquivalent:@"w"];
    fileItem.submenu = fileMenu;

    // —— Playback ——
    NSMenuItem *ctrlItem = [[NSMenuItem alloc] init];
    [menubar addItem:ctrlItem];
    NSMenu *ctrlMenu = [[NSMenu alloc] initWithTitle:[self L:@"playback"]];
    NSMenuItem *playItem = [ctrlMenu addItemWithTitle:[self L:@"play_pause"]
                                               action:@selector(togglePlay:)
                                        keyEquivalent:@" "];
    playItem.target = self;
    playItem.keyEquivalentModifierMask = 0;
    NSMenuItem *stopItem = [ctrlMenu addItemWithTitle:[self L:@"stop"]
                                               action:@selector(stopPlay:)
                                        keyEquivalent:@"."];
    stopItem.target = self;
    ctrlItem.submenu = ctrlMenu;

    // —— Radio ——
    NSMenuItem *radioItem = [[NSMenuItem alloc] init];
    [menubar addItem:radioItem];
    NSMenu *radioMenu = [[NSMenu alloc] initWithTitle:[self L:@"radio"]];

    NSMenuItem *chinaItem = [[NSMenuItem alloc] initWithTitle:[self L:@"china_cities"] action:nil keyEquivalent:@""];
    NSMenu *chinaMenu = [[NSMenu alloc] initWithTitle:[self L:@"china"]];
    [self addCities:[[RadioCatalog shared] citiesForRegion:RadioRegionChina] toMenu:chinaMenu];
    chinaItem.submenu = chinaMenu;
    [radioMenu addItem:chinaItem];

    NSMenuItem *japanItem = [[NSMenuItem alloc] initWithTitle:[self L:@"japan"] action:nil keyEquivalent:@""];
    NSMenu *japanMenu = [[NSMenu alloc] initWithTitle:[self L:@"japan"]];
    [self addCities:[[RadioCatalog shared] citiesForRegion:RadioRegionJapan] toMenu:japanMenu];
    japanItem.submenu = japanMenu;
    [radioMenu addItem:japanItem];

    NSMenuItem *worldItem = [[NSMenuItem alloc] initWithTitle:[self L:@"world_cities"] action:nil keyEquivalent:@""];
    NSMenu *worldMenu = [[NSMenu alloc] initWithTitle:[self L:@"world"]];
    [self addCities:[[RadioCatalog shared] citiesForRegion:RadioRegionWorld] toMenu:worldMenu];
    worldItem.submenu = worldMenu;
    [radioMenu addItem:worldItem];

    radioItem.submenu = radioMenu;

    // —— Brand ——
    NSMenuItem *brandItem = [[NSMenuItem alloc] init];
    [menubar addItem:brandItem];
    NSMenu *brandMenu = [[NSMenu alloc] initWithTitle:[self L:@"brand"]];
    BrandProfile *current = [BrandProfile preferredBrand];
    for (BrandProfile *b in [BrandProfile allBrands]) {
        NSMenuItem *item = [brandMenu addItemWithTitle:b.displayName
                                                action:@selector(selectBrand:)
                                         keyEquivalent:@""];
        item.target = self;
        item.representedObject = b.identifier;
        item.state = [b.identifier isEqualToString:current.identifier]
            ? NSControlStateValueOn : NSControlStateValueOff;
    }
    brandItem.submenu = brandMenu;

    // —— Settings → Language ——
    NSMenuItem *settingsItem = [[NSMenuItem alloc] init];
    [menubar addItem:settingsItem];
    NSMenu *settingsMenu = [[NSMenu alloc] initWithTitle:[self L:@"settings"]];
    NSMenuItem *langItem = [[NSMenuItem alloc] initWithTitle:[self L:@"language"] action:nil keyEquivalent:@""];
    NSMenu *langMenu = [[NSMenu alloc] initWithTitle:[self L:@"language"]];
    MenuLanguage curLang = [MenuLocalization currentLanguage];
    for (NSDictionary *choice in [MenuLocalization languageChoices]) {
        NSMenuItem *item = [langMenu addItemWithTitle:choice[@"title"]
                                               action:@selector(selectMenuLanguage:)
                                        keyEquivalent:@""];
        item.target = self;
        item.representedObject = choice[@"lang"];
        item.state = ([choice[@"lang"] integerValue] == curLang)
            ? NSControlStateValueOn : NSControlStateValueOff;
    }
    langItem.submenu = langMenu;
    [settingsMenu addItem:langItem];
    settingsItem.submenu = settingsMenu;

    // —— Help ——
    NSMenuItem *helpItem = [[NSMenuItem alloc] init];
    [menubar addItem:helpItem];
    NSMenu *helpMenu = [[NSMenu alloc] initWithTitle:[self L:@"help"]];
    NSMenuItem *aboutHelp = [helpMenu addItemWithTitle:[self L:@"howto"]
                                                action:@selector(showHelp:)
                                         keyEquivalent:@"?"];
    aboutHelp.target = self;
    helpItem.submenu = helpMenu;
}

- (void)selectMenuLanguage:(NSMenuItem *)sender {
    NSNumber *langNum = sender.representedObject;
    if (![langNum isKindOfClass:[NSNumber class]]) return;
    [MenuLocalization setCurrentLanguage:(MenuLanguage)langNum.integerValue];
    [self buildMenu]; // rebuild menubar only — console UI unchanged
}

- (void)selectBrand:(NSMenuItem *)sender {
    NSString *identifier = sender.representedObject;
    if (![identifier isKindOfClass:[NSString class]]) return;
    BrandProfile *profile = [BrandProfile brandWithIdentifier:identifier];
    [self.console applyBrandProfile:profile];
    self.window.title = [NSString stringWithFormat:@"拾音盒子 · %@ — Pickup Box",
                         profile.displayName];
    for (NSMenuItem *item in sender.menu.itemArray) {
        NSString *bid = item.representedObject;
        item.state = ([bid isKindOfClass:[NSString class]] && [bid isEqualToString:identifier])
            ? NSControlStateValueOn : NSControlStateValueOff;
    }
}

/// NSAlert 默认说明文常居中；用左对齐 accessory 承载正文。
- (NSTextField *)leftAlignedAlertBody:(NSString *)text {
    NSTextField *field = [NSTextField wrappingLabelWithString:text ?: @""];
    field.alignment = NSTextAlignmentLeft;
    field.preferredMaxLayoutWidth = 400;
    field.font = [NSFont systemFontOfSize:[NSFont systemFontSize]];
    field.textColor = [NSColor labelColor];
    [field sizeToFit];
    return field;
}

- (void)showAbout:(id)sender {
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = [self L:@"about_title"];
    alert.informativeText = @"";
    NSString *version = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleShortVersionString"] ?: @"1.0.0";
    NSString *credits = [NSString stringWithFormat:[self L:@"about_credits"], version];
    NSString *body = [NSString stringWithFormat:@"%@\n\n%@", [self L:@"about_body"], credits];
    alert.accessoryView = [self leftAlignedAlertBody:body];
    NSImage *icon = [NSApp applicationIconImage];
    if (icon) alert.icon = icon;
    [alert addButtonWithTitle:[self L:@"ok"]];
    [alert runModal];
}

- (void)showHelp:(id)sender {
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = [self L:@"howto_title"];
    alert.informativeText = @"";
    alert.accessoryView = [self leftAlignedAlertBody:[self L:@"howto_body"]];
    [alert addButtonWithTitle:[self L:@"ok"]];
    [alert runModal];
}

- (void)openMusic:(id)sender {
    [self.console openLocalMusic];
}

- (void)togglePlay:(id)sender {
    [[AudioEngine shared] togglePlayPause];
}

- (void)stopPlay:(id)sender {
    [[AudioEngine shared] stop];
}

- (void)selectCity:(NSMenuItem *)sender {
    NSString *name = sender.representedObject;
    if ([name isKindOfClass:[NSString class]]) {
        [self.console selectCityNamed:name];
    }
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender {
    return YES;
}

- (BOOL)application:(NSApplication *)sender openFile:(NSString *)filename {
    NSURL *url = [NSURL fileURLWithPath:filename];
    [[AudioEngine shared] playFileURLs:@[url] startAtIndex:0];
    [self.console refreshFromEngine];
    return YES;
}

@end
