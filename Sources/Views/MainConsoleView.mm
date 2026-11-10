#import "MainConsoleView.h"
#import "DrawingHelpers.h"
#import "SpeakerView.h"
#import "SpectrumView.h"
#import "KnobView.h"
#import "FaderView.h"
#import "WorldTunerView.h"
#import "CassetteView.h"
#import "MediaPanelView.h"
#import "ToggleButtonView.h"
#import "MetalKeyView.h"
#import "AudioEngine.h"
#import "LyricsService.h"
#import "RadioCatalog.h"
#import "BrandProfile.h"
#import "MenuLocalization.h"
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

@interface MainConsoleView ()
@property (nonatomic, strong) SpeakerView *leftSpeaker;
@property (nonatomic, strong) SpeakerView *rightSpeaker;
@property (nonatomic, strong) SpectrumView *spectrum;
@property (nonatomic, strong) WorldTunerView *worldTuner;
@property (nonatomic, strong) CassetteView *cassette;
@property (nonatomic, strong) MediaPanelView *media;
@property (nonatomic, strong) NSMutableArray<FaderView *> *faders;
@property (nonatomic, strong) NSMutableArray<KnobView *> *knobs;
@property (nonatomic, strong) NSMutableArray<ToggleButtonView *> *toggles;
@property (nonatomic, strong) NSMutableArray<MetalKeyView *> *eqKeys;
@property (nonatomic, strong) NSMutableArray<MetalKeyView *> *sourceKeys;
@property (nonatomic, strong) NSMutableArray<MetalKeyView *> *modeKeys;
@property (nonatomic, assign) NSInteger eqIndex;
@property (nonatomic, assign) NSInteger sourceIndex;
@property (nonatomic, assign) NSInteger modeIndex;
@property (nonatomic, copy) NSString *statusLine;
@property (nonatomic, copy) NSString *stationLine;
@property (nonatomic, copy) NSString *freqLine;
@property (nonatomic, strong) NSTextField *clockLabel;
@property (nonatomic, assign) CGFloat volume;
@property (nonatomic, assign) BOOL muted;
@property (nonatomic, assign) float meterL;
@property (nonatomic, assign) float meterR;
@property (nonatomic, assign) float peakL;
@property (nonatomic, assign) float peakR;
@property (nonatomic, assign) NSRect ampMeterRect;
@property (nonatomic, assign) BOOL mediaShowsLocalPlaylist;
@property (nonatomic, assign) NSInteger lastLocalPlaylistIndex; // for auto-advance tonearm/tape anim
@property (nonatomic, copy, nullable) NSString *lyricsTrackKey; // avoid duplicate fetches
@property (nonatomic, assign) NSRect vfdProgressHitRect;   // click / drag target
@property (nonatomic, assign) NSRect vfdProgressTrackRect; // fill groove only
@property (nonatomic, assign) BOOL scrubbingProgress;
@property (nonatomic, assign) float scrubProgress; // 0..1 while dragging
/// Sleep timer (night auto-quit): preset minutes cycle OFF→15→30→45→60→90
@property (nonatomic, strong) MetalKeyView *sleepKey;
@property (nonatomic, strong) MetalKeyView *powerOffKey; // main POWER OFF — quits app
@property (nonatomic, assign) NSInteger sleepPresetMinutes; // 0 = off
@property (nonatomic, assign) NSInteger sleepSecondsRemaining;
@property (nonatomic, assign) CGFloat sleepVolumeBase; // restore / fade from
/// Cached rack frames for drawing
@property (nonatomic, assign) NSRect rackDisplay;
@property (nonatomic, assign) NSRect rackControl;
@property (nonatomic, assign) NSRect rackTuner;
@property (nonatomic, assign) NSRect rackMedia;
@property (nonatomic, assign) NSRect rackBrand;   // bottom brand plinth
@property (nonatomic, assign) NSRect chassisRect;
@property (nonatomic, strong, readwrite) BrandProfile *brandProfile;
@end

@implementation MainConsoleView

- (instancetype)initWithFrame:(NSRect)frameRect {
    self = [super initWithFrame:frameRect];
    if (self) {
        _eqIndex = 0;
        _sourceIndex = 0;
        _modeIndex = 0;
        _volume = 0.62;
        _muted = NO;
        _statusLine = @"STANDBY";
        _stationLine = @"选择城市收听网络电台";
        _freqLine = @"— — .- MHz";
        _lastLocalPlaylistIndex = -1;
        _sleepPresetMinutes = 0;
        _sleepSecondsRemaining = 0;
        _sleepVolumeBase = 0.62;
        _faders = [NSMutableArray array];
        _knobs = [NSMutableArray array];
        _toggles = [NSMutableArray array];
        _eqKeys = [NSMutableArray array];
        _sourceKeys = [NSMutableArray array];
        _modeKeys = [NSMutableArray array];
        _brandProfile = [BrandProfile preferredBrand];
        [BrandProfile setActiveBrand:_brandProfile];
        [self buildSubviews];
        [self bindAudioEngine];
    }
    return self;
}

- (void)refreshThemeDeep:(NSView *)view {
    [view setNeedsDisplay:YES];
    for (NSView *child in view.subviews) {
        [self refreshThemeDeep:child];
    }
}

- (void)applyBrandProfile:(BrandProfile *)profile {
    if (!profile) return;
    self.brandProfile = profile;
    [BrandProfile setPreferredBrandIdentifier:profile.identifier];
    [BrandProfile setActiveBrand:profile];
    self.leftSpeaker.brandRailText = profile.identifier;
    self.rightSpeaker.brandRailText = profile.identifier;
    [self refreshThemeDeep:self];
}

- (BOOL)isFlipped { return YES; }

- (CGFloat)speakerWidth { return 218; }

#pragma mark - Audio

- (void)bindAudioEngine {
    AudioEngine *eng = [AudioEngine shared];
    eng.volume = (float)self.volume;
    __weak MainConsoleView *weakSelf = self;
    eng.onLevelsUpdated = ^{ [weakSelf applyAudioLevels]; };
    eng.onStatusChanged = ^{ [weakSelf refreshFromEngine]; };
    eng.onError = ^(NSString *message) {
        NSAlert *alert = [[NSAlert alloc] init];
        alert.messageText = [MenuLocalization stringForKey:@"play_failed_title"];
        alert.informativeText = message;
        [alert addButtonWithTitle:[MenuLocalization stringForKey:@"ok"]];
        [alert runModal];
    };
    // 初始推子 → 实听 EQ（buildSubviews 之后会再调一次）
    dispatch_async(dispatch_get_main_queue(), ^{ [weakSelf pushEQToEngine]; });
}

- (void)applyAudioLevels {
    AudioEngine *eng = [AudioEngine shared];
    BOOL playing = eng.playing && !eng.muted;
    self.leftSpeaker.playing = playing;
    self.rightSpeaker.playing = playing;
    self.leftSpeaker.bassLevel = eng.bassLevel;
    self.rightSpeaker.bassLevel = eng.bassLevel;
    self.leftSpeaker.midLevel = eng.midLevel;
    self.rightSpeaker.midLevel = eng.midLevel;
    self.leftSpeaker.trebleLevel = eng.trebleLevel;
    self.rightSpeaker.trebleLevel = eng.trebleLevel;
    self.leftSpeaker.channelLevel = eng.leftLevel;
    self.rightSpeaker.channelLevel = eng.rightLevel;
    self.leftSpeaker.activity = self.muted ? 0.05 : (0.2 + self.volume * 0.8);
    self.rightSpeaker.activity = self.muted ? 0.05 : (0.2 + self.volume * 0.8);
    float sampleL = (eng.leftLevel - 0.45f) * 2.4f;
    float sampleR = (eng.rightLevel - 0.45f) * 2.4f;
    [self.leftSpeaker pushWaveformSample:sampleL * (playing ? 1.f : 0.f)];
    [self.rightSpeaker pushWaveformSample:sampleR * (playing ? 1.f : 0.f)];
    if (eng.spectrumBands.count > 0) {
        [self.spectrum setBandLevelsFromNumbers:eng.spectrumBands];
    }
    self.spectrum.animating = playing;
    float l = eng.leftLevel;
    float r = eng.rightLevel;
    self.meterL = l;
    self.meterR = r;
    self.peakL = MAX(l, self.peakL * 0.92f);
    self.peakR = MAX(r, self.peakR * 0.92f);
    if (self.worldTuner.powerOn) {
        self.worldTuner.signalLevel = playing ? MAX(l, r) : 0.05f;
    } else {
        self.worldTuner.signalLevel = 0;
    }
    self.cassette.playing = eng.playing && eng.hasLocalPlaylist;
    if (eng.hasLocalPlaylist) {
        self.cassette.tapeProgress = eng.trackProgress;
        if (eng.nowPlayingTitle.length) self.cassette.tapeTitle = eng.nowPlayingTitle;
        self.media.lyricsTime = eng.trackCurrentTime;
    }
    self.cassette.playMode = eng.playMode;
    [self.worldTuner setNeedsDisplay:YES];
    [self setNeedsDisplayInRect:self.rackControl];
    if (eng.hasLocalPlaylist) {
        [self setNeedsDisplayInRect:self.rackDisplay]; // VFD track progress
    }
}

- (void)drawVFDTrackProgressInRect:(NSRect)row
                          progress:(float)progress
                           elapsed:(NSTimeInterval)elapsed
                          duration:(NSTimeInterval)duration {
    progress = MAX(0.f, MIN(1.f, progress));
    BOOL withTime = (NSWidth(row) > 160 && duration > 0);
    CGFloat timeW = withTime ? 38.0 : 0.0;
    // Vertical centering of the thin groove inside a taller hit row
    CGFloat grooveH = 5.0;
    CGFloat grooveY = NSMinY(row) + (NSHeight(row) - grooveH) * 0.5;
    NSRect bar = NSMakeRect(NSMinX(row) + timeW,
                            grooveY,
                            MAX(20, NSWidth(row) - timeW * 2),
                            grooveH);
    self.vfdProgressTrackRect = bar;
    self.vfdProgressHitRect = NSInsetRect(row, 0, -2); // easier grab

    if (withTime) {
        NSInteger e = (NSInteger)MAX(0, elapsed);
        NSInteger r = (NSInteger)MAX(0, duration - elapsed);
        NSString *left = [NSString stringWithFormat:@"%ld:%02ld", (long)(e / 60), (long)(e % 60)];
        NSString *right = [NSString stringWithFormat:@"-%ld:%02ld", (long)(r / 60), (long)(r % 60)];
        SKDrawGlowText(left,
                       NSMakeRect(NSMinX(row), NSMinY(row), timeW - 3, NSHeight(row)),
                       [NSFont monospacedDigitSystemFontOfSize:8 weight:NSFontWeightSemibold],
                       [SKAmberColor() colorWithAlphaComponent:0.85], NSTextAlignmentLeft);
        SKDrawGlowText(right,
                       NSMakeRect(NSMaxX(row) - timeW + 3, NSMinY(row), timeW - 3, NSHeight(row)),
                       [NSFont monospacedDigitSystemFontOfSize:8 weight:NSFontWeightSemibold],
                       [SKAmberColor() colorWithAlphaComponent:0.85], NSTextAlignmentRight);
    }

    // Dim track groove
    NSBezierPath *groove = [NSBezierPath bezierPathWithRoundedRect:bar xRadius:1.5 yRadius:1.5];
    [[NSColor colorWithCalibratedRed:0.28 green:0.14 blue:0.02 alpha:0.55] set];
    [groove fill];
    [[NSColor colorWithCalibratedRed:0.65 green:0.35 blue:0.06 alpha:0.55] set];
    [groove setLineWidth:0.7];
    [groove stroke];

    // Filled amber progress
    CGFloat innerW = NSWidth(bar) - 2;
    CGFloat fillW = MAX(0, innerW * progress);
    if (fillW > 0.5) {
        NSRect fill = NSMakeRect(NSMinX(bar) + 1, NSMinY(bar) + 1, fillW, NSHeight(bar) - 2);
        NSBezierPath *fp = [NSBezierPath bezierPathWithRoundedRect:fill xRadius:1 yRadius:1];
        NSGradient *g = [[NSGradient alloc] initWithColorsAndLocations:
                         [SKAmberColor() colorWithAlphaComponent:0.55], 0.0,
                         SKAmberColor(), 0.5,
                         [SKAmberColor() colorWithAlphaComponent:0.8], 1.0, nil];
        [g drawInBezierPath:fp angle:0];
    }

    // Draggable thumb (cue marker)
    CGFloat thumbX = NSMinX(bar) + 1 + innerW * progress;
    CGFloat thumbW = 5.0, thumbH = NSHeight(bar) + 4;
    NSRect thumb = NSMakeRect(thumbX - thumbW * 0.5,
                              NSMidY(bar) - thumbH * 0.5,
                              thumbW, thumbH);
    NSBezierPath *tp = [NSBezierPath bezierPathWithRoundedRect:thumb xRadius:1.2 yRadius:1.2];
    NSGradient *tg = [[NSGradient alloc] initWithColorsAndLocations:
                      [NSColor colorWithCalibratedWhite:0.95 alpha:1], 0.0,
                      SKAmberColor(), 0.45,
                      [NSColor colorWithCalibratedRed:0.55 green:0.25 blue:0.04 alpha:1], 1.0, nil];
    [tg drawInBezierPath:tp angle:90];
    [[NSColor colorWithCalibratedWhite:0 alpha:0.45] set];
    [tp setLineWidth:0.6];
    [tp stroke];
}

- (float)progressForPointInTrack:(NSPoint)p {
    NSRect track = self.vfdProgressTrackRect;
    if (NSWidth(track) < 1) return 0;
    CGFloat t = (p.x - NSMinX(track)) / NSWidth(track);
    return (float)MAX(0.0, MIN(1.0, t));
}

- (void)beginScrubAtPoint:(NSPoint)p {
    AudioEngine *eng = [AudioEngine shared];
    if (!eng.hasLocalPlaylist || eng.trackDuration <= 1) return;
    if (NSIsEmptyRect(self.vfdProgressHitRect)) return;
    if (!NSPointInRect(p, NSInsetRect(self.vfdProgressHitRect, -4, -6))) return;
    self.scrubbingProgress = YES;
    self.scrubProgress = [self progressForPointInTrack:p];
    [self setNeedsDisplayInRect:self.rackDisplay];
}

- (void)updateScrubAtPoint:(NSPoint)p {
    if (!self.scrubbingProgress) return;
    self.scrubProgress = [self progressForPointInTrack:p];
    [self setNeedsDisplayInRect:self.rackDisplay];
}

- (void)endScrubCommit:(BOOL)commit {
    if (!self.scrubbingProgress) return;
    float p = self.scrubProgress;
    self.scrubbingProgress = NO;
    if (commit) {
        [[AudioEngine shared] seekToProgress:p];
    }
    [self setNeedsDisplayInRect:self.rackDisplay];
}

- (void)requestLyricsForCurrentTrack {
    AudioEngine *eng = [AudioEngine shared];
    if (!eng.hasLocalPlaylist || eng.playlistURLs.count == 0) {
        [self.media clearLyrics];
        self.lyricsTrackKey = nil;
        return;
    }
    NSURL *url = eng.playlistURLs[eng.playlistIndex];
    NSString *title = eng.nowPlayingTitle ?: @"";
    NSString *artist = eng.nowPlayingArtist ?: @"";
    NSString *key = [NSString stringWithFormat:@"%@|%@|%@",
                     url.absoluteString ?: @"", title, artist];
    if ([key isEqualToString:self.lyricsTrackKey]) return; // already tried this track identity
    self.lyricsTrackKey = key;

    self.media.lyricsLines = @[];
    self.media.lyricsSource = nil;
    self.media.lyricsStatus = @"正在搜索歌词…";
    self.media.lyricsTime = eng.trackCurrentTime;

    __weak MainConsoleView *weakSelf = self;
    [[LyricsService shared] fetchLyricsForTitle:title
                                         artist:artist
                                          album:eng.nowPlayingAlbum
                                       duration:eng.trackDuration
                                        fileURL:url
                                     completion:^(LyricsResult *result, NSString *errorMessage) {
        if (![weakSelf.lyricsTrackKey isEqualToString:key]) return;
        if (result.lines.count > 0) {
            weakSelf.media.lyricsLines = result.lines;
            weakSelf.media.lyricsSource = result.sourceLabel;
            weakSelf.media.lyricsStatus = nil;
            weakSelf.media.lyricsTime = [AudioEngine shared].trackCurrentTime;
        } else {
            weakSelf.media.lyricsLines = @[];
            weakSelf.media.lyricsSource = nil;
            weakSelf.media.lyricsStatus = errorMessage.length ? errorMessage : @"未找到歌词";
        }
        [weakSelf.media setNeedsDisplay:YES];
    }];
}

- (void)refreshFromEngine {
    AudioEngine *eng = [AudioEngine shared];
    // 仅本地磁带播放时转盘；听电台时卡带静止
    self.cassette.playing = eng.playing && eng.hasLocalPlaylist;
    self.cassette.playMode = eng.playMode;
    if (eng.hasLocalPlaylist) {
        self.cassette.tapeProgress = eng.trackProgress;
        if (eng.nowPlayingTitle.length) self.cassette.tapeTitle = eng.nowPlayingTitle;
        // 本地清单索引始终跟播放器对齐（电台页不覆盖这份数据）
        if (self.lastLocalPlaylistIndex >= 0 &&
            eng.playlistIndex != self.lastLocalPlaylistIndex) {
            [self.cassette playTrackChangeAnimation];
        }
        self.lastLocalPlaylistIndex = eng.playlistIndex;
        self.media.selectedLocalIndex = eng.playlistIndex;
        if (self.mediaShowsLocalPlaylist) {
            self.media.titleText = eng.nowPlayingTitle;
            NSString *artistBit = eng.nowPlayingArtist.length
                ? [NSString stringWithFormat:@"%@  ·  ", eng.nowPlayingArtist] : @"";
            self.media.subtitleText = [NSString stringWithFormat:@"%@%@  ·  %lu 首",
                                       artistBit, [eng playModeLabel],
                                       (unsigned long)eng.playlistURLs.count];
            self.media.coverImage = eng.nowPlayingArtwork;
        }
        [self requestLyricsForCurrentTrack];
    } else {
        if (!self.mediaShowsLocalPlaylist && self.media.coverImage) {
            self.media.coverImage = nil;
        }
        if (self.media.lyricsLines.count > 0 || self.lyricsTrackKey) {
            [self.media clearLyrics];
            self.lyricsTrackKey = nil;
        }
    }
    self.spectrum.animating = eng.playing;
    // 状态字跟随源键，避免切 TAPE/PHONO 后被统一刷成 ON AIR
    if (!eng.playing) {
        if (eng.hasItem) self.statusLine = @"PAUSE";
    } else if (eng.hasLocalPlaylist) {
        NSArray *labels = @[@"TUNER", @"TAPE", @"AUX", @"PHONO"];
        if (self.sourceIndex >= 0 && self.sourceIndex < (NSInteger)labels.count) {
            self.statusLine = labels[self.sourceIndex];
        }
    } else if (eng.sourceLabel.length) {
        self.statusLine = @"ON AIR";
    }
    if (eng.nowPlayingTitle.length) {
        self.stationLine = eng.nowPlayingTitle;
        self.media.titleText = eng.nowPlayingTitle;
        self.media.subtitleText = eng.sourceLabel ?: @"";
        [self.media setNeedsDisplay:YES];
    }
    [self setNeedsDisplay:YES];
    if (self.window) {
        self.window.title = [NSString stringWithFormat:@"拾音盒子 — %@", eng.nowPlayingTitle ?: @"待机"];
    }
}

- (void)playStation:(RadioStation *)station {
    [[AudioEngine shared] playStation:station];
    self.mediaShowsLocalPlaylist = NO;
    [self highlightSourceAt:0]; // TUNER
    [self setRadioPowered:YES]; // radio path lights the dial backlight
    [self.cassette resetTransportToStop]; // 听电台 → 磁带走带键回 STOP
    [self setStatusFrequency:station.frequency station:station.name];
    self.worldTuner.frequency = station.frequency;
    self.worldTuner.selectedStation = station;
    self.worldTuner.tuned = YES;
    self.worldTuner.stereo = YES;
    self.worldTuner.statusText = station.name;
    [self.worldTuner setNeedsDisplay:YES];
    self.media.titleText = station.name;
    self.media.subtitleText = [NSString stringWithFormat:@"%@  ·  FM %.1f", station.city ?: @"", station.frequency];
    self.media.coverImage = nil; // radio has no embedded album art
    self.media.selectedTab = MediaPanelTabRadio; // 听电台 → 地区频率页；本地清单保留
    [self.media setNeedsDisplay:YES];
}

- (void)selectCityNamed:(NSString *)name {
    RadioCity *city = [[RadioCatalog shared] cityNamed:name];
    if (!city) return;
    [self.worldTuner applyRegion:city.region selectFirstCity:NO];
    [self.worldTuner selectCity:city reload:YES];
}

- (void)setRadioPowered:(BOOL)on {
    // Visual/power only — does not pause audio (MP3 takeover must not kill itself)
    self.worldTuner.powerOn = on;
    [self.worldTuner setNeedsDisplay:YES];
}

- (void)syncLocalPlaylistToMedia {
    [self syncLocalPlaylistToMediaSwitchTab:NO];
}

- (void)syncLocalPlaylistToMediaSwitchTab:(BOOL)switchTab {
    AudioEngine *eng = [AudioEngine shared];
    NSMutableArray<RadioStation *> *list = [NSMutableArray array];
    for (NSURL *url in eng.playlistURLs) {
        RadioStation *s = [RadioStation stationWithName:[url.lastPathComponent stringByDeletingPathExtension] ?: @"Track"
                                                   city:@"LOCAL"
                                              frequency:0
                                                    url:url.absoluteString ?: @""];
        s.streamURL = url; // prefer file URL object
        [list addObject:s];
    }
    self.mediaShowsLocalPlaylist = YES;
    [self setRadioPowered:NO]; // MP3 on → radio off, scale dims
    // 只写入本地清单，绝不碰 radioStations
    self.media.localTracks = list;
    self.media.selectedLocalIndex = eng.playlistIndex;
    self.media.titleText = eng.nowPlayingTitle ?: @"LOCAL";
    self.media.subtitleText = [NSString stringWithFormat:@"%@  ·  %lu 首",
                               [eng playModeLabel], (unsigned long)list.count];
    self.cassette.tapeTitle = eng.nowPlayingTitle;
    self.cassette.playMode = eng.playMode;
    self.media.coverImage = eng.nowPlayingArtwork;
    if (switchTab) self.media.selectedTab = MediaPanelTabLocal;
    // 本地播放：卡带亮 TAPE，唱机亮 PHONO；若当前已是 AUX 则保持
    if (self.sourceIndex == 2) {
        self.statusLine = @"AUX";
        self.freqLine = @"AUX IN";
    } else {
        BOOL phono = (self.cassette.deckStyle == CassetteDeckStylePhono);
        [self highlightSourceAt:phono ? 3 : 1];
        self.statusLine = phono ? @"PHONO" : @"TAPE";
        self.freqLine = phono ? @"PHONO" : @"TAPE IN";
    }
    [self.media setNeedsDisplay:YES];
    [self.cassette setNeedsDisplay:YES];
}

- (BOOL)isAudioFileURL:(NSURL *)url {
    static NSSet *exts;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        exts = [NSSet setWithArray:@[@"mp3", @"m4a", @"aac", @"wav", @"aiff", @"aif", @"flac", @"caf", @"mp4"]];
    });
    return [exts containsObject:url.pathExtension.lowercaseString];
}

- (NSArray<NSURL *> *)collectAudioURLsFromSelection:(NSArray<NSURL *> *)selection {
    NSMutableArray<NSURL *> *out = [NSMutableArray array];
    NSFileManager *fm = [NSFileManager defaultManager];
    for (NSURL *url in selection) {
        BOOL isDir = NO;
        if (![fm fileExistsAtPath:url.path isDirectory:&isDir]) continue;
        if (isDir) {
            NSDirectoryEnumerator *en = [fm enumeratorAtURL:url
                                 includingPropertiesForKeys:@[NSURLIsDirectoryKey]
                                                    options:(NSDirectoryEnumerationSkipsHiddenFiles |
                                                             NSDirectoryEnumerationSkipsPackageDescendants)
                                               errorHandler:nil];
            for (NSURL *file in en) {
                NSNumber *dirFlag = nil;
                [file getResourceValue:&dirFlag forKey:NSURLIsDirectoryKey error:nil];
                if (dirFlag.boolValue) continue;
                if ([self isAudioFileURL:file]) [out addObject:file];
            }
        } else if ([self isAudioFileURL:url]) {
            [out addObject:url];
        }
    }
    return [out sortedArrayUsingComparator:^NSComparisonResult(NSURL *a, NSURL *b) {
        return [a.path localizedStandardCompare:b.path];
    }];
}

- (void)openLocalMusic {
    NSOpenPanel *panel = [NSOpenPanel openPanel];
    panel.canChooseFiles = YES;
    panel.canChooseDirectories = YES; // 可选文件夹，批量装载其中的 MP3
    panel.allowsMultipleSelection = YES;
    panel.canCreateDirectories = NO;
    // 同时允许音频文件与文件夹；具体音频过滤在收集阶段完成
    if (@available(macOS 11.0, *)) {
        NSMutableArray<UTType *> *types = [NSMutableArray arrayWithObjects:
            UTTypeFolder, UTTypeMP3, UTTypeMPEG4Audio, UTTypeWAV, UTTypeAIFF, UTTypeAudio, nil];
        UTType *flac = [UTType typeWithFilenameExtension:@"flac"];
        UTType *caf = [UTType typeWithFilenameExtension:@"caf"];
        if (flac) [types addObject:flac];
        if (caf) [types addObject:caf];
        panel.allowedContentTypes = types;
    }
    panel.title = [MenuLocalization stringForKey:@"open_panel_title"];
    panel.message = [MenuLocalization stringForKey:@"open_panel_message"];
    panel.prompt = [MenuLocalization stringForKey:@"open_panel_prompt"];
    __weak MainConsoleView *weakSelf = self;
    [panel beginWithCompletionHandler:^(NSModalResponse result) {
        if (result != NSModalResponseOK || panel.URLs.count == 0) return;
        NSArray *urls = [weakSelf collectAudioURLsFromSelection:panel.URLs];
        if (urls.count == 0) {
            NSAlert *alert = [[NSAlert alloc] init];
            alert.messageText = [MenuLocalization stringForKey:@"no_audio_title"];
            alert.informativeText = [MenuLocalization stringForKey:@"no_audio_body"];
            [alert addButtonWithTitle:[MenuLocalization stringForKey:@"ok"]];
            [alert runModal];
            return;
        }
        [[AudioEngine shared] playFileURLs:urls startAtIndex:0];
        // 从文件面板导入默认走磁带源（若已是唱机样式则亮 PHONO）
        if (weakSelf.sourceIndex != 2 && weakSelf.sourceIndex != 3) {
            [weakSelf highlightSourceAt:(weakSelf.cassette.deckStyle == CassetteDeckStylePhono) ? 3 : 1];
        }
        weakSelf.stationLine = [NSString stringWithFormat:@"LOCAL %lu", (unsigned long)urls.count];
        weakSelf.lastLocalPlaylistIndex = 0;
        [weakSelf syncLocalPlaylistToMediaSwitchTab:YES]; // 播 MP3 → 清单
        [weakSelf.cassette playMediaInsertAnimation];
        [weakSelf setNeedsDisplay:YES];
    }];
}

#pragma mark - Build

- (void)buildSubviews {
    self.leftSpeaker = [[SpeakerView alloc] initWithFrame:NSZeroRect];
    self.rightSpeaker = [[SpeakerView alloc] initWithFrame:NSZeroRect];
    self.rightSpeaker.mirrored = YES;
    BrandProfile *brand = self.brandProfile ?: [BrandProfile preferredBrand];
    self.leftSpeaker.brandRailText = brand.identifier;
    self.rightSpeaker.brandRailText = brand.identifier;
    [self addSubview:self.leftSpeaker];
    [self addSubview:self.rightSpeaker];

    self.spectrum = [[SpectrumView alloc] initWithFrame:NSZeroRect];
    self.spectrum.linkedToAudio = YES;
    self.spectrum.animating = NO;
    [self addSubview:self.spectrum];

    // 5-band graphic EQ + BAL — fills the left/center like a real FH amp
    NSArray *faderTitles = @[@"60", @"250", @"1K", @"4K", @"16K", @"BAL"];
    CGFloat faderVals[] = {0.62, 0.55, 0.50, 0.55, 0.60, 0.50};
    __weak MainConsoleView *weakSelf = self;
    for (NSInteger i = 0; i < 6; i++) {
        FaderView *f = [[FaderView alloc] initWithFrame:NSZeroRect];
        f.title = faderTitles[i];
        f.value = faderVals[i];
        f.onChange = ^(CGFloat v) {
            (void)v;
            [weakSelf pushEQToEngine];
        };
        [self.faders addObject:f];
        [self addSubview:f];
    }

    NSArray *sources = @[@"TUNER", @"TAPE", @"AUX", @"PHONO"];
    for (NSInteger i = 0; i < 4; i++) {
        MetalKeyView *key = [[MetalKeyView alloc] initWithFrame:NSZeroRect];
        key.title = sources[i];
        key.ledRed = NO;
        key.selected = (i == 0);
        NSInteger idx = i;
        key.onClick = ^{ [weakSelf selectSourceAt:idx]; };
        [self.sourceKeys addObject:key];
        [self addSubview:key];
    }

    // Sound field modes — fills the empty top-center gap
    NSArray *modes = @[@"STEREO", @"KARAOKE", @"WIDE"];
    for (NSInteger i = 0; i < 3; i++) {
        MetalKeyView *key = [[MetalKeyView alloc] initWithFrame:NSZeroRect];
        key.title = modes[i];
        key.ledRed = YES;
        key.selected = (i == 0);
        NSInteger idx = i;
        key.onClick = ^{
            weakSelf.modeIndex = idx;
            for (NSUInteger j = 0; j < weakSelf.modeKeys.count; j++) {
                weakSelf.modeKeys[j].selected = ((NSInteger)j == idx);
            }
        };
        [self.modeKeys addObject:key];
        [self addSubview:key];
    }

    NSArray *knobTitles = @[@"MIC", @"VOLUME", @"ECHO", @"PHONES"];
    CGFloat knobVals[] = {0.28, 0.62, 0.22, 0.40};
    for (NSInteger i = 0; i < 4; i++) {
        KnobView *k = [[KnobView alloc] initWithFrame:NSZeroRect];
        k.title = knobTitles[i];
        k.value = knobVals[i];
        k.accent = (i == 1);
        if (i == 1) {
            k.onChange = ^(CGFloat v) {
                weakSelf.volume = v;
                [AudioEngine shared].volume = (float)v;
            };
        }
        [self.knobs addObject:k];
        [self addSubview:k];
    }

    // Horizontal function bank — more switches like a real 90s amp panel
    NSArray *toggleTitles = @[@"M.BASS", @"LOUD", @"MUTE", @"SURR",
                              @"DBS", @"PRES", @"HPF", @"MON"];
    for (NSInteger i = 0; i < (NSInteger)toggleTitles.count; i++) {
        ToggleButtonView *t = [[ToggleButtonView alloc] initWithFrame:NSZeroRect];
        t.title = toggleTitles[i];
        t.on = (i == 0 || i == 1); // default Mega Bass + Loudness
        if (i == 2) { // MUTE
            t.onToggle = ^(BOOL on) {
                weakSelf.muted = on;
                [AudioEngine shared].muted = on;
            };
        }
        [self.toggles addObject:t];
        [self addSubview:t];
    }

    // SLEEP — cycle timer key at right of FUNCTION (night auto-quit)
    self.sleepKey = [[MetalKeyView alloc] initWithFrame:NSZeroRect];
    self.sleepKey.title = @"OFF";
    self.sleepKey.ledRed = NO; // amber like source keys
    self.sleepKey.selected = NO;
    self.sleepKey.onClick = ^{ [weakSelf cycleSleepTimer]; };
    [self addSubview:self.sleepKey];

    // Main POWER OFF — lives on the brand header (does not crowd FUNCTION row)
    self.powerOffKey = [[MetalKeyView alloc] initWithFrame:NSZeroRect];
    self.powerOffKey.title = @"OFF";
    self.powerOffKey.showLED = NO; // compact fascia key; "POWER" silk sits beside it
    self.powerOffKey.selected = YES; // amber face while unit is "on"
    self.powerOffKey.onClick = ^{ [weakSelf powerOffAndQuit]; };
    [self addSubview:self.powerOffKey];

    NSArray *eq = @[@"ROCK", @"POPS", @"CLASSIC", @"JAZZ", @"DISCO"];
    for (NSInteger i = 0; i < 5; i++) {
        MetalKeyView *key = [[MetalKeyView alloc] initWithFrame:NSZeroRect];
        key.title = eq[i];
        key.ledRed = YES;
        key.selected = (i == 0);
        NSInteger idx = i;
        key.onClick = ^{ [weakSelf selectEQAt:idx]; };
        [self.eqKeys addObject:key];
        [self addSubview:key];
    }

    self.worldTuner = [[WorldTunerView alloc] initWithFrame:NSZeroRect];
    self.worldTuner.onStationSelected = ^(RadioStation *station) {
        [weakSelf playStation:station];
    };
    self.worldTuner.onStationsUpdated = ^(NSArray<RadioStation *> *stations, NSInteger selectedIndex) {
        // 只更新「电台」页，本地「清单」原样保留
        weakSelf.media.radioCityName = weakSelf.worldTuner.selectedCity.nameCN;
        weakSelf.media.radioStations = stations;
        weakSelf.media.selectedRadioIndex = selectedIndex;
        if (stations.count > 0 && !weakSelf.mediaShowsLocalPlaylist) {
            weakSelf.media.subtitleText = [NSString stringWithFormat:@"%@  ·  %lu 台",
                                           weakSelf.worldTuner.selectedCity.nameCN ?: @"",
                                           (unsigned long)stations.count];
        }
        [weakSelf.media setNeedsDisplay:YES];
    };
    self.worldTuner.onCitySelected = ^(RadioCity *city) {
        weakSelf.statusLine = @"TUNING";
        weakSelf.stationLine = [NSString stringWithFormat:@"%@ · %@", city.nameCN, city.nameEN];
        weakSelf.media.titleText = city.nameCN;
        weakSelf.media.radioCityName = city.nameCN;
        weakSelf.media.radioStations = @[];
        weakSelf.media.selectedTab = MediaPanelTabRadio;
        weakSelf.media.subtitleText = [NSString stringWithFormat:@"%@  ·  搜索中…", city.countryName];
        [weakSelf.media setNeedsDisplay:YES];
        [weakSelf setNeedsDisplay:YES];
    };
    self.worldTuner.onTuneFrequency = ^(CGFloat mhz) {
        [weakSelf setStatusFrequency:mhz station:[NSString stringWithFormat:@"FM %.1f", mhz]];
    };
    self.worldTuner.onPowerChanged = ^(BOOL on) {
        AudioEngine *eng = [AudioEngine shared];
        if (on) {
            // 开收音机 → 磁带/唱机走带键回 STOP；本地清单数据仍保留可再切回
            [weakSelf.cassette resetTransportToStop];
            weakSelf.mediaShowsLocalPlaylist = NO;
            weakSelf.media.selectedTab = MediaPanelTabRadio;
            if (weakSelf.worldTuner.selectedStation) {
                [weakSelf playStation:weakSelf.worldTuner.selectedStation];
            } else if (eng.hasItem) {
                [eng play];
            }
            weakSelf.statusLine = @"ON AIR";
        } else {
            [eng pause];
            weakSelf.statusLine = @"STANDBY";
        }
        [weakSelf.worldTuner setNeedsDisplay:YES];
        [weakSelf setNeedsDisplay:YES];
    };
    [self addSubview:self.worldTuner];

    self.cassette = [[CassetteView alloc] initWithFrame:NSZeroRect];
    self.cassette.playing = NO;
    self.cassette.onTransport = ^(NSString *cmd) {
        AudioEngine *eng = [AudioEngine shared];
        if ([cmd isEqualToString:@"play"]) {
            // 磁带/唱机 PLAY → 强制关掉收音机电源，并点亮对应源键
            [weakSelf setRadioPowered:NO];
            NSInteger src = (weakSelf.cassette.deckStyle == CassetteDeckStylePhono) ? 3 : 1;
            [weakSelf highlightSourceAt:src];
            if (eng.playlistURLs.count > 0) {
                // 有本地曲库则续播清单（含刚听完电台再回来）
                [eng playPlaylistIndex:eng.playlistIndex];
                [weakSelf syncLocalPlaylistToMediaSwitchTab:YES];
            } else if (weakSelf.media.localTracks.count > 0) {
                [eng playPlaylistIndex:MAX(0, weakSelf.media.selectedLocalIndex)];
                [weakSelf syncLocalPlaylistToMediaSwitchTab:YES];
            } else {
                // 没有磁带/本地曲 → 关电台、停机，不顺手打开电台
                [eng pause];
                [weakSelf.cassette resetTransportToStop];
                weakSelf.statusLine = @"NO TAPE";
            }
        } else if ([cmd isEqualToString:@"pause"]) {
            [eng pause];
        } else if ([cmd isEqualToString:@"stop"]) {
            [eng stop];
            [weakSelf.cassette resetTransportToStop];
        } else if ([cmd isEqualToString:@"eject"]) {
            [eng stop];
            [weakSelf openLocalMusic];
        } else if ([cmd isEqualToString:@"prev"]) {
            if (eng.hasLocalPlaylist ||
                (weakSelf.media.selectedTab == MediaPanelTabLocal && eng.playlistURLs.count > 0)) {
                if (!eng.hasLocalPlaylist) [eng playPlaylistIndex:eng.playlistIndex];
                [eng playPreviousTrack];
                [weakSelf.cassette playTrackChangeAnimation];
                weakSelf.lastLocalPlaylistIndex = eng.playlistIndex;
                [weakSelf syncLocalPlaylistToMedia];
            } else {
                [weakSelf.worldTuner selectPreviousStation];
            }
        } else if ([cmd isEqualToString:@"next"]) {
            if (eng.hasLocalPlaylist ||
                (weakSelf.media.selectedTab == MediaPanelTabLocal && eng.playlistURLs.count > 0)) {
                if (!eng.hasLocalPlaylist) [eng playPlaylistIndex:eng.playlistIndex];
                [eng playNextTrack];
                [weakSelf.cassette playTrackChangeAnimation];
                weakSelf.lastLocalPlaylistIndex = eng.playlistIndex;
                [weakSelf syncLocalPlaylistToMedia];
            } else {
                [weakSelf.worldTuner selectNextStation];
            }
        }
    };
    self.cassette.onPlayModeChanged = ^(AudioPlayMode mode) {
        [AudioEngine shared].playMode = mode;
        if ([AudioEngine shared].hasLocalPlaylist) {
            weakSelf.media.subtitleText = [NSString stringWithFormat:@"%@  ·  %lu 首",
                                           [[AudioEngine shared] playModeLabel],
                                           (unsigned long)[AudioEngine shared].playlistURLs.count];
            [weakSelf.media setNeedsDisplay:YES];
        }
    };
    self.cassette.onDeckStyleChanged = ^(CassetteDeckStyle style) {
        if (!weakSelf.mediaShowsLocalPlaylist && ![AudioEngine shared].hasLocalPlaylist) return;
        // 卡带 ↔ 唱机切换时，功能区源键跟随
        if (weakSelf.sourceIndex == 2) return; // AUX 保持
        [weakSelf highlightSourceAt:(style == CassetteDeckStylePhono) ? 3 : 1];
        weakSelf.statusLine = (style == CassetteDeckStylePhono) ? @"PHONO" : @"TAPE";
        weakSelf.freqLine = (style == CassetteDeckStylePhono) ? @"PHONO" : @"TAPE IN";
        [weakSelf setNeedsDisplay:YES];
    };
    [self addSubview:self.cassette];

    self.media = [[MediaPanelView alloc] initWithFrame:NSZeroRect];
    self.media.titleText = @"拾音盒子";
    self.media.subtitleText = @"EJECT 导入 · 电台看「电台」页";
    self.media.onSelectLocalAtIndex = ^(NSInteger index) {
        BOOL changing = (index != weakSelf.lastLocalPlaylistIndex);
        [[AudioEngine shared] playPlaylistIndex:index];
        if (changing) [weakSelf.cassette playTrackChangeAnimation];
        weakSelf.lastLocalPlaylistIndex = index;
        [weakSelf syncLocalPlaylistToMediaSwitchTab:YES];
    };
    self.media.onSelectRadioAtIndex = ^(NSInteger index) {
        [weakSelf.worldTuner pickStationAtIndex:index];
        weakSelf.media.selectedTab = MediaPanelTabRadio;
    };
    [self addSubview:self.media];

    dispatch_async(dispatch_get_main_queue(), ^{
        RadioCity *cd = [[RadioCatalog shared] cityNamed:@"成都"];
        if (cd) [weakSelf.worldTuner selectCity:cd reload:YES];
    });

    // 壁钟改画在 VFD 数码管区；保留不可见 label 仅作兼容占位
    self.clockLabel = [[NSTextField alloc] initWithFrame:NSZeroRect];
    self.clockLabel.hidden = YES;
    self.clockLabel.bezeled = NO;
    self.clockLabel.drawsBackground = NO;
    self.clockLabel.editable = NO;
    self.clockLabel.selectable = NO;
    [self addSubview:self.clockLabel];
    [self updateClock];
    [NSTimer scheduledTimerWithTimeInterval:1.0 target:self selector:@selector(updateClock) userInfo:nil repeats:YES];
}

- (void)pushEQToEngine {
    NSMutableArray<NSNumber *> *vals = [NSMutableArray arrayWithCapacity:self.faders.count];
    for (FaderView *f in self.faders) {
        [vals addObject:@(f.value)];
    }
    [[AudioEngine shared] applyEQFromFaders:vals];
}

- (void)selectEQAt:(NSInteger)index {
    self.eqIndex = index;
    for (NSUInteger i = 0; i < self.eqKeys.count; i++) {
        self.eqKeys[i].selected = ((NSInteger)i == index);
    }
    // 60 / 250 / 1K / 4K / 16K / BAL — 曲线拉开，听感更明显（±约 12–15 dB）
    CGFloat presets[5][6] = {
        {0.92, 0.72, 0.32, 0.62, 0.88, 0.50}, // ROCK   — 重低音 + 高频，中频凹陷
        {0.55, 0.62, 0.78, 0.80, 0.72, 0.50}, // POPS   — 中高频前冲
        {0.30, 0.40, 0.55, 0.45, 0.35, 0.50}, // CLASSIC — 整体收敛、偏柔
        {0.42, 0.62, 0.75, 0.52, 0.38, 0.48}, // JAZZ   — 温暖中频
        {0.90, 0.52, 0.40, 0.78, 0.92, 0.50}  // DISCO  — 轰低音 + 闪亮高频
    };
    NSInteger n = MIN(6, (NSInteger)self.faders.count);
    for (NSInteger i = 0; i < n; i++) {
        self.faders[i].value = presets[self.eqIndex][i];
        [self.faders[i] setNeedsDisplay:YES];
    }
    [self pushEQToEngine];
}

/// 仅点亮源键，不触发切源副作用（供电台/本地播放路径调用）
- (void)highlightSourceAt:(NSInteger)index {
    if (index < 0 || index >= (NSInteger)self.sourceKeys.count) return;
    self.sourceIndex = index;
    for (NSUInteger i = 0; i < self.sourceKeys.count; i++) {
        self.sourceKeys[i].selected = ((NSInteger)i == index);
    }
    [self setNeedsDisplay:YES];
}

- (void)selectSourceAt:(NSInteger)index {
    NSInteger previous = self.sourceIndex;
    [self highlightSourceAt:index];
    NSArray *labels = @[@"TUNER", @"TAPE", @"AUX", @"PHONO"];
    self.statusLine = labels[index];
    AudioEngine *eng = [AudioEngine shared];

    if (index == 0) {
        // TUNER → 收音机（已在听电台则只亮键，勿重连流，否则频谱会卡住）
        self.mediaShowsLocalPlaylist = NO;
        self.media.selectedTab = MediaPanelTabRadio;
        [self.cassette resetTransportToStop];
        [self setRadioPowered:YES];
        BOOL alreadyRadio = (previous == 0) && !eng.hasLocalPlaylist && eng.playing;
        if (alreadyRadio) {
            [self setNeedsDisplay:YES];
            return;
        }
        if (self.worldTuner.selectedStation) {
            [self playStation:self.worldTuner.selectedStation];
        } else {
            self.freqLine = self.worldTuner.frequency > 0
                ? [NSString stringWithFormat:@"%.1f MHz", self.worldTuner.frequency]
                : @"— — .- MHz";
            [self.media setNeedsDisplay:YES];
        }
    } else {
        // TAPE / AUX / PHONO → 本地源
        if (index == 1) {
            self.cassette.deckStyle = CassetteDeckStyleTape;
            self.freqLine = @"TAPE IN";
        } else if (index == 2) {
            self.freqLine = @"AUX IN";
        } else if (index == 3) {
            self.cassette.deckStyle = CassetteDeckStylePhono;
            self.freqLine = @"PHONO";
        }
        [self setRadioPowered:NO];

        if (eng.playlistURLs.count == 0) {
            [self openLocalMusic];
            [self setNeedsDisplay:YES];
            return;
        }

        // 已在播本地：只切源键/机芯外观，禁止再次 replaceCurrentItem（会断 tap → 频谱假死）
        if (eng.hasLocalPlaylist) {
            if (!eng.playing) [eng play];
            [self syncLocalPlaylistToMediaSwitchTab:YES];
            [self setNeedsDisplay:YES];
            return;
        }

        // 从电台切回本地清单：需要恢复 hasLocalPlaylist 并播放
        [eng playPlaylistIndex:eng.playlistIndex];
        [self syncLocalPlaylistToMediaSwitchTab:YES];
    }
    [self setNeedsDisplay:YES];
}

- (void)cycleSleepTimer {
    // Sony-style SLEEP cycle: OFF → 15 → 30 → 45 → 60 → 90 → OFF
    static const NSInteger presets[] = {0, 15, 30, 45, 60, 90};
    static const NSInteger nPresets = 6;
    NSInteger idx = 0;
    for (NSInteger i = 0; i < nPresets; i++) {
        if (presets[i] == self.sleepPresetMinutes) { idx = i; break; }
    }
    idx = (idx + 1) % nPresets;
    NSInteger mins = presets[idx];
    self.sleepPresetMinutes = mins;
    if (mins == 0) {
        [self cancelSleepTimerRestoringVolume:YES];
        self.statusLine = @"SLEEP OFF";
    } else {
        self.sleepVolumeBase = self.volume;
        self.sleepSecondsRemaining = mins * 60;
        self.sleepKey.selected = YES;
        self.sleepKey.title = [NSString stringWithFormat:@"%ldm", (long)mins];
        // 状态栏轻提示；倒计时画在 VFD 右上数码管，不占用中间大字
        if (![self.statusLine isEqualToString:@"ON AIR"] &&
            ![self.statusLine isEqualToString:@"PHONO"] &&
            ![self.statusLine isEqualToString:@"PAUSE"]) {
            self.statusLine = @"ON AIR";
        }
    }
    [self refreshSleepKeyAppearance];
    [self refreshClockDisplay];
    [self setNeedsDisplay:YES];
}

- (void)cancelSleepTimerRestoringVolume:(BOOL)restore {
    self.sleepPresetMinutes = 0;
    self.sleepSecondsRemaining = 0;
    self.sleepKey.selected = NO;
    self.sleepKey.title = @"OFF";
    if (restore) {
        self.volume = self.sleepVolumeBase;
        [AudioEngine shared].volume = (float)self.sleepVolumeBase;
        if (self.knobs.count > 1) {
            self.knobs[1].value = self.sleepVolumeBase;
            [self.knobs[1] setNeedsDisplay:YES];
        }
    }
    [self refreshSleepKeyAppearance];
}

- (void)refreshSleepKeyAppearance {
    BOOL on = (self.sleepPresetMinutes > 0);
    self.sleepKey.selected = on;
    self.sleepKey.ledOn = on;
    [self.sleepKey setNeedsDisplay:YES];
}

- (void)powerOffAndQuit {
    // Main power switch — stop audio, flash status, then terminate
    [[AudioEngine shared] stop];
    self.powerOffKey.selected = NO;
    [self.powerOffKey setNeedsDisplay:YES];
    self.statusLine = @"POWER OFF";
    self.freqLine = @"— — .-";
    self.stationLine = @"关机中…";
    [self setNeedsDisplay:YES];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.35 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        [NSApp terminate:nil];
    });
}

- (void)tickSleepTimer {
    if (self.sleepPresetMinutes <= 0 || self.sleepSecondsRemaining <= 0) return;

    self.sleepSecondsRemaining -= 1;

    // Last minute: gentle fade-out (睡前听歌)
    if (self.sleepSecondsRemaining <= 60) {
        CGFloat fade = MAX(0.0, (CGFloat)self.sleepSecondsRemaining / 60.0);
        CGFloat v = self.sleepVolumeBase * fade;
        self.volume = v;
        [AudioEngine shared].volume = (float)v;
        if (self.knobs.count > 1) {
            self.knobs[1].value = v;
            [self.knobs[1] setNeedsDisplay:YES];
        }
    }

    if (self.sleepSecondsRemaining <= 0) {
        [[AudioEngine shared] stop];
        self.statusLine = @"GOOD NIGHT";
        self.freqLine = @"SLEEP";
        self.stationLine = @"自动关机";
        [self cancelSleepTimerRestoringVolume:NO];
        [self setNeedsDisplay:YES];
        // Brief readout, then quit
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.6 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            [NSApp terminate:nil];
        });
        return;
    }

    // Key face shows remaining whole minutes while counting
    NSInteger remMin = (self.sleepSecondsRemaining + 59) / 60;
    self.sleepKey.title = [NSString stringWithFormat:@"%ldm", (long)MAX(1, remMin)];
    [self.sleepKey setNeedsDisplay:YES];
}

- (void)refreshClockDisplay {
    // 日期 / 时钟 / SLEEP 均画在 VFD 右侧数码管，每秒刷新 DISPLAY
    [self setNeedsDisplayInRect:self.rackDisplay];
}

- (void)updateClock {
    // 1Hz timer: advance sleep countdown, then refresh readout
    if (self.sleepPresetMinutes > 0 && self.sleepSecondsRemaining > 0) {
        [self tickSleepTimer];
    }
    [self refreshClockDisplay];
}

- (void)setStatusFrequency:(CGFloat)mhz station:(NSString *)station {
    self.freqLine = [NSString stringWithFormat:@"%.1f MHz", mhz];
    self.statusLine = @"FM STEREO";
    self.stationLine = station;
    self.media.subtitleText = [NSString stringWithFormat:@"FM %.1f  ·  EJECT 导入歌曲", mhz];
    self.media.titleText = station;
    [self.media setNeedsDisplay:YES];
    [self setNeedsDisplay:YES];
}

- (void)setPlaying:(BOOL)playing {
    BOOL tape = playing && [AudioEngine shared].hasLocalPlaylist;
    self.cassette.playing = tape;
    self.spectrum.animating = playing;
    self.leftSpeaker.playing = playing;
    self.rightSpeaker.playing = playing;
}

#pragma mark - Layout (4 coordinated rack modules)

- (void)layout {
    [super layout];
    NSRect b = self.bounds;
    CGFloat speakerW = [self speakerWidth];
    CGFloat sideGap = 5;
    CGFloat centerX = speakerW + sideGap;
    CGFloat centerW = NSWidth(b) - speakerW * 2 - sideGap * 2;
    CGFloat chassisTop = 4;
    CGFloat chassisH = NSHeight(b) - 8;
    self.chassisRect = NSMakeRect(centerX, chassisTop, centerW, chassisH);

    self.leftSpeaker.frame = NSMakeRect(0, 0, speakerW, NSHeight(b));
    self.rightSpeaker.frame = NSMakeRect(NSWidth(b) - speakerW, 0, speakerW, NSHeight(b));

    // Brand header + four racks + bottom brand plinth (finger clearance under media keys)
    CGFloat headerH = 30; // room for POWER OFF key on fascia
    CGFloat brandH = 40;
    CGFloat gutter = 7; // thicker dark seam between 1U panels
    CGFloat innerPad = 8;
    CGFloat y0 = chassisTop + headerH + 4;
    CGFloat usable = chassisH - headerH - 4 - brandH - gutter * 4;

    CGFloat displayH = floor(usable * 0.15);
    CGFloat controlH = floor(usable * 0.28);
    CGFloat tunerH   = floor(usable * 0.16);
    CGFloat mediaH   = usable - displayH - controlH - tunerH;

    // Side inset leaves cheek room for punched vent grilles
    CGFloat sideInset = 18;
    self.rackDisplay = NSMakeRect(centerX + sideInset, y0, centerW - sideInset * 2, displayH);
    self.rackControl = NSMakeRect(centerX + sideInset, y0 + displayH + gutter, centerW - sideInset * 2, controlH);
    self.rackTuner   = NSMakeRect(centerX + sideInset, y0 + displayH + controlH + gutter * 2, centerW - sideInset * 2, tunerH);
    self.rackMedia   = NSMakeRect(centerX + sideInset, y0 + displayH + controlH + tunerH + gutter * 3, centerW - sideInset * 2, mediaH);
    self.rackBrand   = NSMakeRect(centerX + sideInset,
                                  y0 + displayH + controlH + tunerH + mediaH + gutter * 4,
                                  centerW - sideInset * 2,
                                  brandH - 4);

    // —— Layer 1: Display — spectrum | VFD  half / half ——
    NSRect d = self.rackDisplay;
    CGFloat gap = 8;
    CGFloat contentW = NSWidth(d) - innerPad * 2 - gap;
    CGFloat halfW = floor(contentW * 0.5);
    self.spectrum.frame = NSMakeRect(NSMinX(d) + innerPad,
                                     NSMinY(d) + 22,
                                     halfW,
                                     NSHeight(d) - 30);
    self.clockLabel.frame = NSZeroRect; // clock lives in VFD digits now

    // —— Layer 2: AMP — filled strip: keys / EQ+knobs / FUNCTION / tall VU ——
    NSRect c = self.rackControl;
    CGFloat left = NSMinX(c) + 10;
    CGFloat right = NSMaxX(c) - 8;
    CGFloat keyH = 26;
    CGFloat funcH = 40; // silk + dial + label with clear bank margins
    // Clear AMPLIFIER rack silk (title ~y+5..17) before key bank
    CGFloat topY = NSMinY(c) + 28;
    CGFloat meterColW = 72;

    // VU full height of amp face
    self.ampMeterRect = NSMakeRect(right - meterColW, topY, meterColW, NSMaxY(c) - 6 - topY);
    CGFloat workRight = NSMinX(self.ampMeterRect) - 10;
    CGFloat workW = workRight - left;

    // Top row: SOURCE | MODE | PRESET evenly across work width
    NSUInteger nSrc = self.sourceKeys.count;
    NSUInteger nMode = self.modeKeys.count;
    NSUInteger nPreset = self.eqKeys.count;
    NSUInteger nTop = nSrc + nMode + nPreset;
    CGFloat topGap = 5;
    CGFloat topKeyW = (workW - (nTop - 1) * topGap) / (CGFloat)nTop;
    topKeyW = MAX(42, MIN(58, topKeyW));
    CGFloat topTotal = nTop * topKeyW + (nTop - 1) * topGap;
    CGFloat topX = left + MAX(0, (workW - topTotal) * 0.5);
    NSUInteger ti = 0;
    for (NSUInteger i = 0; i < nSrc; i++, ti++) {
        self.sourceKeys[i].frame = NSMakeRect(topX + ti * (topKeyW + topGap), topY, topKeyW, keyH);
    }
    for (NSUInteger i = 0; i < nMode; i++, ti++) {
        self.modeKeys[i].frame = NSMakeRect(topX + ti * (topKeyW + topGap), topY, topKeyW, keyH);
    }
    for (NSUInteger i = 0; i < nPreset; i++, ti++) {
        self.eqKeys[i].frame = NSMakeRect(topX + ti * (topKeyW + topGap), topY, topKeyW, keyH);
    }

    CGFloat funcY = NSMaxY(c) - 8 - funcH;
    CGFloat faderTop = topY + keyH + 14;
    // Leave clearance so FUNCTION bank never covers EQ fader Hz labels (60/1K/…)
    CGFloat faderH = MAX(52, funcY - 20 - faderTop);

    // EQ faders — slightly narrower zone so LEVEL knobs can grow
    NSUInteger nFader = self.faders.count;
    CGFloat eqZoneW = workW * 0.46;
    CGFloat slotW = eqZoneW / (CGFloat)nFader;
    CGFloat faderW = MIN(38, MAX(32, slotW * 0.72));
    for (NSUInteger i = 0; i < nFader; i++) {
        CGFloat cx = left + i * slotW + slotW * 0.5;
        self.faders[i].frame = NSMakeRect(cx - faderW * 0.5, faderTop, faderW, faderH);
    }

    // Knobs — MIC | VOLUME | ECHO | PHONES
    // Frame width >= title width so VOLUME/PHONES never become "VOL…" / "PH…"
    CGFloat knobsLeft = left + eqZoneW + 10;
    CGFloat knobsW = workRight - knobsLeft;
    CGFloat knobsH = faderH;
    const CGFloat captionH = 16.0;
    const CGFloat bankPad = 6.0;
    CGFloat dialBudget = MAX(40, knobsH - captionH - bankPad * 2);
    CGFloat volDial = MIN(dialBudget * 0.95, MIN(72, knobsW * 0.28));
    CGFloat sideDial = volDial * 0.90; // was 0.78 — too small
    CGFloat volFrameW = MAX(volDial, 58);
    CGFloat sideFrameW = MAX(sideDial, 50);
    CGFloat volFrameH = volDial + captionH;
    CGFloat sideFrameH = sideDial + captionH;
    CGFloat groupH = MAX(volFrameH, sideFrameH);
    CGFloat knobGap = 8.0;
    CGFloat groupW = sideFrameW * 3 + volFrameW + knobGap * 3;
    if (groupW > knobsW - 2) {
        CGFloat scale = (knobsW - 2 - knobGap * 3) / (sideFrameW * 3 + volFrameW);
        volDial *= scale; sideDial *= scale;
        volFrameW = MAX(volDial, 52 * scale); sideFrameW = MAX(sideDial, 46 * scale);
        volFrameH = volDial + captionH; sideFrameH = sideDial + captionH;
        groupH = MAX(volFrameH, sideFrameH);
        groupW = sideFrameW * 3 + volFrameW + knobGap * 3;
    }
    CGFloat groupX = knobsLeft + (knobsW - groupW) * 0.5;
    CGFloat groupY = faderTop + (knobsH - groupH) * 0.5;
    CGFloat baseY = groupY + groupH;
    if (self.knobs.count >= 4) {
        CGFloat kx = groupX;
        self.knobs[0].frame = NSMakeRect(kx, baseY - sideFrameH, sideFrameW, sideFrameH);
        kx += sideFrameW + knobGap;
        self.knobs[1].frame = NSMakeRect(kx, baseY - volFrameH, volFrameW, volFrameH);
        kx += volFrameW + knobGap;
        self.knobs[2].frame = NSMakeRect(kx, baseY - sideFrameH, sideFrameW, sideFrameH);
        kx += sideFrameW + knobGap;
        self.knobs[3].frame = NSMakeRect(kx, baseY - sideFrameH, sideFrameW, sideFrameH);
    }

    // FUNCTION + SLEEP — content centered in bank with silk/label margins
    NSUInteger nFunc = self.toggles.count;
    CGFloat sleepW = 46;
    CGFloat sleepGap = 12;
    CGFloat funcGap = 4;
    CGFloat availForToggles = workW - sleepW - sleepGap;
    CGFloat funcW = (availForToggles - (nFunc - 1) * funcGap) / (CGFloat)nFunc;
    funcW = MAX(32, MIN(44, funcW));
    CGFloat funcTotal = nFunc * funcW + (nFunc - 1) * funcGap;
    CGFloat rowTotal = funcTotal + sleepGap + sleepW;
    CGFloat funcX0 = left + MAX(0, (workW - rowTotal) * 0.5);
    // Leave 12px top for FUNCTION silk, 4px bottom for bank lip
    CGFloat toggleH = funcH - 16;
    CGFloat toggleY = funcY + 12;
    for (NSUInteger i = 0; i < nFunc; i++) {
        self.toggles[i].frame = NSMakeRect(funcX0 + i * (funcW + funcGap), toggleY, funcW, toggleH);
    }
    if (self.sleepKey) {
        CGFloat sleepX = funcX0 + funcTotal + sleepGap;
        self.sleepKey.frame = NSMakeRect(sleepX, toggleY, sleepW, toggleH);
    }

    // POWER OFF — top fascia, right of brand header (keeps FUNCTION row intact)
    if (self.powerOffKey && !NSIsEmptyRect(self.chassisRect)) {
        NSRect header = NSMakeRect(NSMinX(self.chassisRect) + 6,
                                   NSMinY(self.chassisRect) + 4,
                                   NSWidth(self.chassisRect) - 12, 24);
        CGFloat pw = 48, ph = 20;
        self.powerOffKey.frame = NSMakeRect(NSMaxX(header) - pw - 6,
                                            NSMidY(header) - ph * 0.5,
                                            pw, ph);
    }

    // —— Layer 3: Tuner ——
    self.worldTuner.frame = NSInsetRect(self.rackTuner, 4, 4);

    // —— Layer 4: Cassette | Media ——
    NSRect m = self.rackMedia;
    CGFloat halfGap = 6;
    CGFloat half = (NSWidth(m) - halfGap - innerPad * 2) * 0.5;
    // Inset enough that panel titles clear the rack seam
    self.cassette.frame = NSMakeRect(NSMinX(m) + innerPad, NSMinY(m) + 4, half, NSHeight(m) - 10);
    self.media.frame = NSMakeRect(NSMinX(m) + innerPad + half + halfGap, NSMinY(m) + 4, half, NSHeight(m) - 10);
}

#pragma mark - Draw chassis + rack faces

- (void)drawRect:(NSRect)dirtyRect {
    NSRect bounds = self.bounds;
    [[NSColor colorWithCalibratedWhite:0.03 alpha:1] set];
    NSRectFill(bounds);

    NSRect chassis = self.chassisRect;
    if (NSIsEmptyRect(chassis)) return;

    // Chassis drop shadow for floating metal stack
    [[NSColor colorWithCalibratedWhite:0 alpha:0.55] set];
    NSRectFill(NSMakeRect(NSMinX(chassis) + 4, NSMaxY(chassis) - 2, NSWidth(chassis) - 8, 6));

    SKFillBrushedMetal(chassis, 0.16);
    // 面板主题染色：夜色/海浪/工作室 机壳色调明显不同
    BrandProfile *drawBrand = self.brandProfile ?: [BrandProfile activeBrand];
    if (drawBrand.chassisTint) {
        [drawBrand.chassisTint set];
        NSRectFillUsingOperation(chassis, NSCompositingOperationSourceOver);
    }
    // Thick extruded outer lip (double rail)
    [[NSColor colorWithCalibratedWhite:0.55 alpha:0.3] set];
    NSFrameRect(NSInsetRect(chassis, 2, 2));
    [[NSColor colorWithCalibratedWhite:0.35 alpha:0.35] set];
    NSFrameRect(NSInsetRect(chassis, 1, 1));
    [[NSColor colorWithCalibratedWhite:0.0 alpha:0.88] set];
    NSFrameRect(chassis);
    // Soft top specular across whole chassis
    NSGradient *chassisSpec = [[NSGradient alloc] initWithColorsAndLocations:
                               [NSColor colorWithCalibratedWhite:1 alpha:0.0], 0.0,
                               [NSColor colorWithCalibratedWhite:1 alpha:0.055], 0.07,
                               [NSColor colorWithCalibratedWhite:1 alpha:0.0], 0.2, nil];
    [chassisSpec drawInRect:chassis angle:90];
    // 主题高光带（顶沿细线）
    [[drawBrand.accentColor colorWithAlphaComponent:0.22] set];
    NSRectFill(NSMakeRect(NSMinX(chassis) + 6, NSMinY(chassis) + 1, NSWidth(chassis) - 12, 1.5));

    // Side cheek vent grilles (punched metal) + rack-ear handles
    CGFloat ventTop = NSMinY(self.rackDisplay) + 8;
    CGFloat ventBot = NSMaxY(self.rackMedia) - 8;
    CGFloat ventH = MAX(40, ventBot - ventTop);
    NSRect leftVent = NSMakeRect(NSMinX(chassis) + 5, ventTop, 11, ventH);
    NSRect rightVent = NSMakeRect(NSMaxX(chassis) - 16, ventTop, 11, ventH);
    SKDrawVentGrille(leftVent, YES);
    SKDrawVentGrille(rightVent, YES);
    // Small horizontal handle slots (rack ears)
    for (int ear = 0; ear < 2; ear++) {
        CGFloat ex = ear == 0 ? NSMinX(chassis) + 4 : NSMaxX(chassis) - 18;
        NSRect handle = NSMakeRect(ex, NSMinY(chassis) + 32, 14, 7);
        SKDrawInsetBevel(handle, 2);
        [[NSColor colorWithCalibratedWhite:0.0 alpha:0.75] set];
        NSRectFill(NSInsetRect(handle, 1.5, 1.5));
        NSRect handle2 = NSMakeRect(ex, NSMaxY(chassis) - 44, 14, 7);
        SKDrawInsetBevel(handle2, 2);
        [[NSColor colorWithCalibratedWhite:0.0 alpha:0.75] set];
        NSRectFill(NSInsetRect(handle2, 1.5, 1.5));
    }

    // Dark rack cavity behind module gutters
    [[NSColor colorWithCalibratedWhite:0.015 alpha:1] set];
    NSRectFill(NSMakeRect(NSMinX(chassis) + 18, NSMinY(self.rackDisplay),
                          NSWidth(chassis) - 36,
                          NSMaxY(self.rackMedia) - NSMinY(self.rackDisplay)));

    BrandProfile *brand = drawBrand;

    // Brand header strip — POWER OFF key sits on the right (laid out in -layout)
    // Soft accent wash behind header
    [[brand.accentColor colorWithAlphaComponent:0.08] set];
    NSRectFill(NSMakeRect(NSMinX(chassis) + 6, NSMinY(chassis) + 4, NSWidth(chassis) - 12, 24));
    NSRect header = NSMakeRect(NSMinX(chassis) + 6, NSMinY(chassis) + 4, NSWidth(chassis) - 12, 24);
    SKDrawRaisedBevel(header, 2);
    SKDrawScrew(NSMakePoint(NSMinX(header) + 9, NSMidY(header)), 2.0);
    CGFloat powerReserve = self.powerOffKey ? 58 : 20;
    SKDrawScrew(NSMakePoint(NSMaxX(header) - powerReserve - 8, NSMidY(header)), 2.0);
    NSString *headerLine = [NSString stringWithFormat:@"%@  %@", brand.systemLine, brand.modelTag];
    SKDrawGlowText(headerLine,
                   NSMakeRect(NSMinX(header) + 20, NSMinY(header) + 4,
                              NSWidth(header) - powerReserve - 36, 16),
                   [NSFont systemFontOfSize:12 weight:NSFontWeightBold],
                   [NSColor colorWithCalibratedWhite:0.88 alpha:1],
                   NSTextAlignmentLeft);
    // POWER silk just left of the OFF key
    if (self.powerOffKey) {
        NSRect pk = self.powerOffKey.frame;
        SKDrawGlowText(@"POWER",
                       NSMakeRect(NSMinX(pk) - 38, NSMidY(header) - 5, 36, 10),
                       [NSFont systemFontOfSize:7 weight:NSFontWeightBold],
                       [NSColor colorWithCalibratedWhite:0.55 alpha:1],
                       NSTextAlignmentRight);
    }

    // Layer faces
    SKDrawRackModule(self.rackDisplay, @"DISPLAY  ·  SPECTRUM / FLUORESCENT", 0.05);
    SKDrawRackModule(self.rackControl, @"AMPLIFIER", 0.02);
    // Tuner face is drawn by WorldTunerView; draw outer seam only
    SKDrawRackModule(self.rackTuner, @"", 0.04);
    SKDrawRackModule(self.rackMedia, @"", 0.0);

    // Bottom brand plinth — clearance under cassette/media keys + fascia identity
    if (!NSIsEmptyRect(self.rackBrand)) {
        NSRect br = self.rackBrand;
        SKDrawRaisedBevel(br, 3);
        NSRect face = NSInsetRect(br, 2, 2);
        SKFillBrushedMetal(face, 0.06);
        // Soft vignette plate
        NSGradient *plate = [[NSGradient alloc] initWithColorsAndLocations:
                             [NSColor colorWithCalibratedWhite:0.04 alpha:1], 0.0,
                             [NSColor colorWithCalibratedWhite:0.10 alpha:1], 0.45,
                             [NSColor colorWithCalibratedWhite:0.05 alpha:1], 1.0, nil];
        [plate drawInRect:NSInsetRect(face, 8, 4) angle:0];

        // Screws first at outer corners — captions inset so they never collide
        SKDrawScrew(NSMakePoint(NSMinX(face) + 9, NSMidY(face)), 2.2);
        SKDrawScrew(NSMakePoint(NSMaxX(face) - 9, NSMidY(face)), 2.2);

        CGFloat sidePad = 28; // clear of screws
        SKDrawGlowText(brand.modelTag,
                       NSMakeRect(NSMinX(face) + sidePad, NSMidY(face) - 5, 64, 12),
                       [NSFont systemFontOfSize:8 weight:NSFontWeightBold],
                       [NSColor colorWithCalibratedWhite:0.45 alpha:1],
                       NSTextAlignmentLeft);
        SKDrawGlowText(@"HI-FI",
                       NSMakeRect(NSMaxX(face) - sidePad - 52, NSMidY(face) - 5, 52, 12),
                       [NSFont systemFontOfSize:8 weight:NSFontWeightBold],
                       [NSColor colorWithCalibratedWhite:0.45 alpha:1],
                       NSTextAlignmentRight);

        // Center wordmark with generous side margins
        NSRect mark = NSMakeRect(NSMinX(face) + sidePad + 70, NSMinY(face) + 3,
                                 NSWidth(face) - (sidePad + 70) * 2, NSHeight(face) - 6);
        [brand drawWordmarkInRect:mark];
    }

    // VFD readout panel — right half, matching spectrum
    NSRect d = self.rackDisplay;
    CGFloat gap = 8;
    CGFloat innerPadD = 8;
    CGFloat contentW = NSWidth(d) - innerPadD * 2 - gap;
    CGFloat halfW = floor(contentW * 0.5);
    NSRect vfd = NSMakeRect(NSMinX(d) + innerPadD + halfW + gap,
                            NSMinY(d) + 22,
                            halfW,
                            NSHeight(d) - 30);
    SKDrawVFDScreen(vfd);

    BOOL sleepOn = (self.sleepPresetMinutes > 0 && self.sleepSecondsRemaining > 0);
    // 右列只放日期+时钟；SLEEP 倒计时占中间主读数位，避免挤在一列
    CGFloat rightColW = MIN(100.0, NSWidth(vfd) * 0.36);
    CGFloat leftPad = 8;
    CGFloat midW = NSWidth(vfd) - leftPad - rightColW - 10;

    // Top: 保留播放状态；SLEEP 仅作角标，不顶替频率信息
    SKDrawGlowText(self.statusLine ?: @"STANDBY",
                   NSMakeRect(NSMinX(vfd) + leftPad, NSMinY(vfd) + 5, midW * 0.55, 11),
                   [NSFont systemFontOfSize:10 weight:NSFontWeightBold],
                   SKAmberColor(), NSTextAlignmentLeft);
    if (sleepOn) {
        SKDrawGlowText(@"SLEEP",
                       NSMakeRect(NSMinX(vfd) + leftPad + midW * 0.55, NSMinY(vfd) + 5, midW * 0.45, 11),
                       [NSFont systemFontOfSize:9 weight:NSFontWeightBold],
                       [SKAmberColor() colorWithAlphaComponent:0.9],
                       NSTextAlignmentRight);
    }

    // Center: 频率/音源始终保留；底部留给曲名 + 可拖进度条
    AudioEngine *engLayout = [AudioEngine shared];
    CGFloat bottomPad = (engLayout.hasLocalPlaylist && engLayout.trackDuration > 1.0) ? 34.0 : 22.0;
    NSRect midRect = NSMakeRect(NSMinX(vfd) + leftPad, NSMinY(vfd) + 18,
                                midW, MAX(20, NSHeight(vfd) - 18 - bottomPad));
    if (sleepOn) {
        CGFloat freqW = MIN(midW * 0.42, 110);
        SKDrawGlowText(self.freqLine ?: @"",
                       NSMakeRect(NSMinX(midRect), NSMinY(midRect) + 4, freqW, 20),
                       [NSFont monospacedDigitSystemFontOfSize:16 weight:NSFontWeightMedium],
                       SKAmberColor(), NSTextAlignmentLeft);
        NSRect sleepDigits = NSMakeRect(NSMinX(midRect) + freqW + 4,
                                        NSMinY(midRect) + MAX(0, (NSHeight(midRect) - 28) * 0.5),
                                        NSWidth(midRect) - freqW - 4,
                                        MIN(28, NSHeight(midRect)));
        SKDrawVFDTime(sleepDigits, self.sleepSecondsRemaining, SKAmberColor(), NSTextAlignmentCenter);
    } else {
        SKDrawGlowText(self.freqLine ?: @"",
                       NSMakeRect(NSMinX(midRect), NSMinY(midRect) + 2, NSWidth(midRect), 22),
                       [NSFont monospacedDigitSystemFontOfSize:20 weight:NSFontWeightMedium],
                       SKAmberColor(), NSTextAlignmentLeft);
    }

    // Local MP3 progress — fluorescent strip inside VFD (keeps brand plinth untouched)
    AudioEngine *engNow = [AudioEngine shared];
    BOOL showProg = engNow.hasLocalPlaylist && engNow.trackDuration > 1.0;
    CGFloat progRowH = 11.0;
    CGFloat progReserve = showProg ? (progRowH + 6.0) : 0.0;
    if (!showProg) {
        self.vfdProgressHitRect = NSZeroRect;
        self.vfdProgressTrackRect = NSZeroRect;
    }

    // Prefer current lyric line on the VFD footer when available
    NSString *station = self.stationLine ?: @"";
    if (showProg && self.media.lyricsLines.count > 0) {
        NSInteger li = 0;
        NSTimeInterval t = self.scrubbingProgress
            ? (engNow.trackDuration * self.scrubProgress)
            : engNow.trackCurrentTime;
        for (NSInteger i = 0; i < (NSInteger)self.media.lyricsLines.count; i++) {
            if (self.media.lyricsLines[i].time <= t + 0.05) li = i;
            else break;
        }
        NSString *ly = self.media.lyricsLines[li].text;
        if (ly.length) station = ly;
    }
    NSInteger maxChars = showProg ? 22 : 16;
    if ((NSInteger)station.length > maxChars) {
        station = [[station substringToIndex:maxChars - 1] stringByAppendingString:@"…"];
    }
    SKDrawGlowText(station,
                   NSMakeRect(NSMinX(vfd) + leftPad, NSMaxY(vfd) - 14 - progReserve, midW, 12),
                   [NSFont systemFontOfSize:10 weight:NSFontWeightSemibold],
                   [SKAmberColor() colorWithAlphaComponent:0.9], NSTextAlignmentLeft);

    if (showProg) {
        float prog = self.scrubbingProgress ? self.scrubProgress : engNow.trackProgress;
        NSTimeInterval el = self.scrubbingProgress
            ? (engNow.trackDuration * self.scrubProgress)
            : engNow.trackCurrentTime;
        // Keep 3px clear of VFD bottom bezel so times / thumb aren't clipped
        [self drawVFDTrackProgressInRect:NSMakeRect(NSMinX(vfd) + leftPad,
                                                    NSMaxY(vfd) - 3 - progRowH,
                                                    NSWidth(vfd) - leftPad - 8,
                                                    progRowH)
                                progress:prog
                                 elapsed:el
                                duration:engNow.trackDuration];
    }

    // —— Right: date (small) + clock only ——
    NSRect rightCol = NSMakeRect(NSMaxX(vfd) - 8 - rightColW,
                                 NSMinY(vfd) + 6,
                                 rightColW,
                                 NSHeight(vfd) - 12 - progReserve);
    NSDate *now = [NSDate date];
    NSCalendar *cal = [NSCalendar currentCalendar];
    NSDateComponents *dc = [cal components:(NSCalendarUnitYear | NSCalendarUnitMonth |
                                            NSCalendarUnitDay | NSCalendarUnitHour |
                                            NSCalendarUnitMinute | NSCalendarUnitSecond)
                                  fromDate:now];
    NSString *datePat = [NSString stringWithFormat:@"%02ld-%02ld-%02ld",
                         (long)(dc.year % 100), (long)dc.month, (long)dc.day];
    NSString *timePat = [NSString stringWithFormat:@"%02ld:%02ld:%02ld",
                         (long)dc.hour, (long)dc.minute, (long)dc.second];

    CGFloat dateH = 11.0;
    CGFloat clockH = 15.0;
    CGFloat stackH = dateH + 4 + clockH;
    CGFloat y = NSMinY(rightCol) + MAX(0, (NSHeight(rightCol) - stackH) * 0.5);
    SKDrawVFDPattern(NSMakeRect(NSMinX(rightCol), y, NSWidth(rightCol), dateH),
                     datePat, [SKAmberColor() colorWithAlphaComponent:0.72], NSTextAlignmentRight);
    SKDrawVFDPattern(NSMakeRect(NSMinX(rightCol), y + dateH + 4, NSWidth(rightCol), clockH),
                     timePat, SKAmberColor(), NSTextAlignmentRight);

    // Band captions + key-bank plate / section dividers
    void (^drawMetalDivider)(CGFloat, NSRect) = ^(CGFloat midX, NSRect keyBand) {
        CGFloat x = midX - 1.0;
        CGFloat y = NSMinY(keyBand) + 2;
        CGFloat h = NSHeight(keyBand) - 4;
        [[NSColor colorWithCalibratedWhite:0.0 alpha:0.55] set];
        NSRectFill(NSMakeRect(x, y, 1.0, h));
        [[NSColor colorWithCalibratedWhite:0.55 alpha:0.35] set];
        NSRectFill(NSMakeRect(x + 1.0, y, 1.0, h));
        // Tiny rivet dots
        SKDrawScrew(NSMakePoint(midX, NSMinY(keyBand) + 4), 1.3);
        SKDrawScrew(NSMakePoint(midX, NSMaxY(keyBand) - 4), 1.3);
    };

    if (self.sourceKeys.count || self.modeKeys.count || self.eqKeys.count) {
        NSRect first = self.sourceKeys.count ? self.sourceKeys.firstObject.frame
                     : (self.modeKeys.count ? self.modeKeys.firstObject.frame
                                            : self.eqKeys.firstObject.frame);
        NSRect last = self.eqKeys.count ? self.eqKeys.lastObject.frame
                    : (self.modeKeys.count ? self.modeKeys.lastObject.frame
                                           : self.sourceKeys.lastObject.frame);
        NSRect keyBank = NSMakeRect(NSMinX(first) - 5, NSMinY(first) - 2,
                                    NSMaxX(last) - NSMinX(first) + 10, NSHeight(first) + 4);
        [[NSColor colorWithCalibratedWhite:0 alpha:0.22] set];
        [[NSBezierPath bezierPathWithRoundedRect:NSOffsetRect(keyBank, 0, 1) xRadius:3 yRadius:3] fill];
        SKFillBrushedMetal(keyBank, 0.05);
        [[NSColor colorWithCalibratedWhite:0.45 alpha:0.28] set];
        NSFrameRect(NSInsetRect(keyBank, 0.5, 0.5));
        [[NSColor colorWithCalibratedWhite:0.05 alpha:0.65] set];
        NSFrameRect(keyBank);

        if (self.sourceKeys.count && self.modeKeys.count) {
            CGFloat mid = (NSMaxX(self.sourceKeys.lastObject.frame) + NSMinX(self.modeKeys.firstObject.frame)) * 0.5;
            drawMetalDivider(mid, keyBank);
        }
        if (self.modeKeys.count && self.eqKeys.count) {
            CGFloat mid = (NSMaxX(self.modeKeys.lastObject.frame) + NSMinX(self.eqKeys.firstObject.frame)) * 0.5;
            drawMetalDivider(mid, keyBank);
        }
    }

    // Section captions sit just above their keys — never over AMPLIFIER silk
    if (self.sourceKeys.count) {
        NSRect sr0 = self.sourceKeys.firstObject.frame;
        NSRect sr1 = self.sourceKeys.lastObject.frame;
        SKDrawGlowText(@"SOURCE",
                       NSMakeRect(NSMinX(sr0), NSMinY(sr0) - 11, NSMaxX(sr1) - NSMinX(sr0), 10),
                       [NSFont systemFontOfSize:7 weight:NSFontWeightBold],
                       [NSColor colorWithCalibratedWhite:0.5 alpha:1], NSTextAlignmentCenter);
    }
    if (self.modeKeys.count) {
        NSRect mr0 = self.modeKeys.firstObject.frame;
        NSRect mr1 = self.modeKeys.lastObject.frame;
        SKDrawGlowText(@"MODE",
                       NSMakeRect(NSMinX(mr0), NSMinY(mr0) - 11, NSMaxX(mr1) - NSMinX(mr0), 10),
                       [NSFont systemFontOfSize:7 weight:NSFontWeightBold],
                       [NSColor colorWithCalibratedWhite:0.5 alpha:1], NSTextAlignmentCenter);
    }
    if (self.eqKeys.count) {
        NSRect er = self.eqKeys.firstObject.frame;
        NSRect erLast = self.eqKeys.lastObject.frame;
        SKDrawGlowText(@"PRESET",
                       NSMakeRect(NSMinX(er), NSMinY(er) - 11, NSMaxX(erLast) - NSMinX(er), 10),
                       [NSFont systemFontOfSize:7 weight:NSFontWeightBold],
                       [NSColor colorWithCalibratedWhite:0.5 alpha:1], NSTextAlignmentCenter);
    }
    if (self.faders.count) {
        NSRect fr0 = self.faders.firstObject.frame;
        NSRect fr1 = self.faders.lastObject.frame;
        // EQ bank faceplate under the graphic faders
        NSRect eqBank = NSMakeRect(NSMinX(fr0) - 6, NSMinY(fr0) - 2,
                                   NSMaxX(fr1) - NSMinX(fr0) + 12, NSHeight(fr0) + 4);
        [[NSColor colorWithCalibratedWhite:0 alpha:0.28] set];
        [[NSBezierPath bezierPathWithRoundedRect:NSOffsetRect(eqBank, 0, 1.2) xRadius:4 yRadius:4] fill];
        SKDrawRaisedBevel(eqBank, 3);
        SKDrawScrew(NSMakePoint(NSMinX(eqBank) + 7, NSMinY(eqBank) + 7), 1.7);
        SKDrawScrew(NSMakePoint(NSMaxX(eqBank) - 7, NSMinY(eqBank) + 7), 1.7);
        SKDrawScrew(NSMakePoint(NSMinX(eqBank) + 7, NSMaxY(eqBank) - 7), 1.7);
        SKDrawScrew(NSMakePoint(NSMaxX(eqBank) - 7, NSMaxY(eqBank) - 7), 1.7);
        SKDrawGlowText(@"GRAPHIC EQUALIZER",
                       NSMakeRect(NSMinX(fr0), NSMinY(fr0) - 12, NSMaxX(fr1) - NSMinX(fr0), 10),
                       [NSFont systemFontOfSize:7 weight:NSFontWeightBold],
                       [NSColor colorWithCalibratedWhite:0.5 alpha:1], NSTextAlignmentCenter);
        // dB silk on far left of bank
        SKDrawGlowText(@"dB",
                       NSMakeRect(NSMinX(eqBank) + 2, NSMidY(eqBank) - 5, 14, 10),
                       [NSFont systemFontOfSize:7 weight:NSFontWeightBold],
                       [NSColor colorWithCalibratedWhite:0.45 alpha:1], NSTextAlignmentCenter);
    }
    if (self.knobs.count) {
        // Union of all knob frames so VOLUME never overflows the plate
        NSRect unionK = self.knobs.firstObject.frame;
        for (KnobView *k in self.knobs) unionK = NSUnionRect(unionK, k.frame);
        NSRect lvlBank = NSInsetRect(unionK, -8, -6);
        [[NSColor colorWithCalibratedWhite:0 alpha:0.22] set];
        [[NSBezierPath bezierPathWithRoundedRect:NSOffsetRect(lvlBank, 0, 1) xRadius:4 yRadius:4] fill];
        SKDrawRaisedBevel(lvlBank, 3);
        SKDrawGlowText(@"LEVEL",
                       NSMakeRect(NSMinX(lvlBank), NSMinY(lvlBank) - 11, NSWidth(lvlBank), 10),
                       [NSFont systemFontOfSize:7 weight:NSFontWeightBold],
                       [NSColor colorWithCalibratedWhite:0.5 alpha:1], NSTextAlignmentCenter);
    }
    if (self.toggles.count) {
        NSRect tr0 = self.toggles.firstObject.frame;
        NSRect tr1 = self.toggles.lastObject.frame;
        NSRect lastKey = self.sleepKey ? self.sleepKey.frame : tr1;
        NSRect unionT = NSUnionRect(tr0, lastKey);
        for (ToggleButtonView *t in self.toggles) unionT = NSUnionRect(unionT, t.frame);
        // Bank = union + margins matching the layout insets (12 top / 4 bottom)
        NSRect funcBank = NSMakeRect(NSMinX(unionT) - 5, NSMinY(unionT) - 12,
                                     NSWidth(unionT) + 10, NSHeight(unionT) + 12 + 4);
        [[NSColor colorWithCalibratedWhite:0 alpha:0.22] set];
        [[NSBezierPath bezierPathWithRoundedRect:NSOffsetRect(funcBank, 0, 1) xRadius:3 yRadius:3] fill];
        SKFillBrushedMetal(funcBank, 0.05);
        [[NSColor colorWithCalibratedWhite:0.4 alpha:0.25] set];
        NSFrameRect(NSInsetRect(funcBank, 0.5, 0.5));
        [[NSColor colorWithCalibratedWhite:0.05 alpha:0.6] set];
        NSFrameRect(funcBank);

        SKDrawGlowText(@"FUNCTION",
                       NSMakeRect(NSMinX(tr0), NSMinY(funcBank) + 2, NSMaxX(tr1) - NSMinX(tr0), 9),
                       [NSFont systemFontOfSize:7 weight:NSFontWeightBold],
                       [NSColor colorWithCalibratedWhite:0.58 alpha:1], NSTextAlignmentCenter);

        if (self.sleepKey) {
            NSRect sk = self.sleepKey.frame;
            NSColor *cap = self.sleepPresetMinutes > 0
                ? [SKAmberColor() colorWithAlphaComponent:0.85]
                : [NSColor colorWithCalibratedWhite:0.58 alpha:1];
            SKDrawGlowText(@"SLEEP",
                           NSMakeRect(NSMinX(sk), NSMinY(funcBank) + 2, NSWidth(sk), 9),
                           [NSFont systemFontOfSize:7 weight:NSFontWeightBold],
                           cap, NSTextAlignmentCenter);
            CGFloat midX = (NSMaxX(self.toggles.lastObject.frame) + NSMinX(sk)) * 0.5;
            [[NSColor colorWithCalibratedWhite:0.0 alpha:0.55] set];
            NSRectFill(NSMakeRect(midX - 1.0, NSMinY(sk) + 2, 1.0, NSHeight(sk) - 4));
            [[NSColor colorWithCalibratedWhite:0.55 alpha:0.35] set];
            NSRectFill(NSMakeRect(midX, NSMinY(sk) + 2, 1.0, NSHeight(sk) - 4));
            SKDrawScrew(NSMakePoint(midX, NSMinY(sk) + 4), 1.3);
            SKDrawScrew(NSMakePoint(midX, NSMaxY(sk) - 4), 1.3);
        }
    }

    // Right-side L/R rhythm VU (segmented, peak hold)
    if (!NSIsEmptyRect(self.ampMeterRect)) {
        NSRect box = self.ampMeterRect;
        SKDrawRaisedBevel(box, 3);
        NSRect face = NSInsetRect(box, 2, 2);
        SKFillBrushedMetal(face, 0.08);
        // Corner screws on VU module
        SKDrawScrew(NSMakePoint(NSMinX(face) + 6, NSMinY(face) + 7), 1.6);
        SKDrawScrew(NSMakePoint(NSMaxX(face) - 6, NSMinY(face) + 7), 1.6);
        SKDrawGlowText(@"VU",
                       NSMakeRect(NSMinX(face) + 10, NSMinY(face) + 2, NSWidth(face) - 20, 10),
                       [NSFont systemFontOfSize:8 weight:NSFontWeightBold],
                       [NSColor colorWithCalibratedWhite:0.55 alpha:1], NSTextAlignmentCenter);

        CGFloat trackTop = NSMinY(face) + 14;
        CGFloat trackBot = NSMaxY(face) - 16;
        CGFloat trackH = trackBot - trackTop;
        CGFloat colW = 16;
        CGFloat gap = 6;
        CGFloat pairW = colW * 2 + gap;
        CGFloat x0 = NSMidX(face) - pairW * 0.5;
        NSRect lMeter = NSMakeRect(x0, trackTop, colW, trackH);
        NSRect rMeter = NSMakeRect(x0 + colW + gap, trackTop, colW, trackH);
        SKDrawSegmentMeter(lMeter, MAX(self.meterL, self.peakL * 0.15f), 18, YES);
        SKDrawSegmentMeter(rMeter, MAX(self.meterR, self.peakR * 0.15f), 18, YES);
        // Peak ticks
        void (^peakTick)(NSRect, float) = ^(NSRect m, float peak) {
            if (peak < 0.05f) return;
            CGFloat y = NSMaxY(m) - peak * NSHeight(m);
            [[SKRedLEDColor() colorWithAlphaComponent:0.9] set];
            NSRectFill(NSMakeRect(NSMinX(m) + 1, y - 1, NSWidth(m) - 2, 2));
        };
        peakTick(lMeter, self.peakL);
        peakTick(rMeter, self.peakR);
        SKDrawGlowText(@"L", NSMakeRect(NSMinX(lMeter), NSMaxY(face) - 14, NSWidth(lMeter), 10),
                       [NSFont systemFontOfSize:8 weight:NSFontWeightBold],
                       [NSColor colorWithCalibratedWhite:0.6 alpha:1], NSTextAlignmentCenter);
        SKDrawGlowText(@"R", NSMakeRect(NSMinX(rMeter), NSMaxY(face) - 14, NSWidth(rMeter), 10),
                       [NSFont systemFontOfSize:8 weight:NSFontWeightBold],
                       [NSColor colorWithCalibratedWhite:0.6 alpha:1], NSTextAlignmentCenter);
    }

    // Cassette / Media panels draw their own titles — avoid a second caption strip
    // that was getting clipped by the rack bevel.
}

#pragma mark - Progress scrubbing

- (void)mouseDown:(NSEvent *)event {
    NSPoint p = [self convertPoint:event.locationInWindow fromView:nil];
    [self beginScrubAtPoint:p];
    if (!self.scrubbingProgress) {
        [super mouseDown:event];
    }
}

- (void)mouseDragged:(NSEvent *)event {
    if (!self.scrubbingProgress) {
        [super mouseDragged:event];
        return;
    }
    NSPoint p = [self convertPoint:event.locationInWindow fromView:nil];
    [self updateScrubAtPoint:p];
}

- (void)mouseUp:(NSEvent *)event {
    if (self.scrubbingProgress) {
        [self endScrubCommit:YES];
        return;
    }
    [super mouseUp:event];
}

- (void)cursorUpdate:(NSEvent *)event {
    NSPoint p = [self convertPoint:event.locationInWindow fromView:nil];
    if (!NSIsEmptyRect(self.vfdProgressHitRect) &&
        NSPointInRect(p, NSInsetRect(self.vfdProgressHitRect, -2, -4))) {
        [[NSCursor pointingHandCursor] set];
    } else {
        [[NSCursor arrowCursor] set];
    }
}

- (void)updateTrackingAreas {
    [super updateTrackingAreas];
    for (NSTrackingArea *a in self.trackingAreas) {
        [self removeTrackingArea:a];
    }
    NSTrackingArea *area = [[NSTrackingArea alloc]
        initWithRect:self.bounds
             options:(NSTrackingMouseEnteredAndExited |
                      NSTrackingMouseMoved |
                      NSTrackingCursorUpdate |
                      NSTrackingActiveInKeyWindow |
                      NSTrackingInVisibleRect)
               owner:self
            userInfo:nil];
    [self addTrackingArea:area];
}

@end
