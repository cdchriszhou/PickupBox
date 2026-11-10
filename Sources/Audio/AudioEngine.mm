#import "AudioEngine.h"
#import <AVFoundation/AVFoundation.h>
#import <MediaToolbox/MediaToolbox.h>
#import <Accelerate/Accelerate.h>

static const NSInteger kSpectrumBands = 32;

@implementation RadioStation
+ (instancetype)stationWithName:(NSString *)name
                           city:(NSString *)city
                      frequency:(CGFloat)mhz
                            url:(NSString *)urlString {
    RadioStation *s = [[RadioStation alloc] init];
    s.name = name;
    s.city = city;
    s.frequency = mhz;
    s.streamURL = [NSURL URLWithString:urlString];
    return s;
}
@end

@interface AudioEngine ()
@property (nonatomic, strong) AVPlayer *player;
@property (nonatomic, strong) id timeObserver;
@property (nonatomic, strong) id progressObserver;
@property (nonatomic, strong) id itemEndObserver;
@property (nonatomic, strong) AVPlayerItem *observedItem;
@property (nonatomic, copy) NSString *nowPlayingTitle;
@property (nonatomic, copy, nullable) NSString *nowPlayingArtist;
@property (nonatomic, copy, nullable) NSString *nowPlayingAlbum;
@property (nonatomic, copy) NSString *sourceLabel;
@property (nonatomic, strong, nullable) NSImage *nowPlayingArtwork;
@property (nonatomic, assign) NSTimeInterval trackCurrentTime;
@property (nonatomic, assign) NSTimeInterval trackDuration;
@property (nonatomic, assign) BOOL playing;
@property (nonatomic, assign) BOOL paused;
@property (nonatomic, assign) float leftLevel;
@property (nonatomic, assign) float rightLevel;
@property (nonatomic, assign) float bassLevel;
@property (nonatomic, assign) float midLevel;
@property (nonatomic, assign) float trebleLevel;
@property (nonatomic, strong) NSArray<NSNumber *> *spectrumBands;
@property (nonatomic, assign) BOOL hasTap;
@property (nonatomic, strong) NSTimer *fallbackTimer;
@property (nonatomic, assign) float fallbackPhase;
@property (nonatomic, copy) NSArray<NSURL *> *playlistURLs;
@property (nonatomic, assign) NSInteger playlistIndex;
@property (nonatomic, assign) BOOL hasLocalPlaylist;
@property (nonatomic, assign) float trackProgress;
@property (nonatomic, assign) BOOL playingLocalFile;
@end

typedef struct {
    float b0, b1, b2, a1, a2;
    float z1L, z2L, z1R, z2R;
} SKBiquad;

typedef struct {
    __unsafe_unretained AudioEngine *engine;
    double sampleRate;
    SKBiquad eq[5];
    float lastGains[5]; // dB, to detect rebuild
    BOOL filtersReady;
} SKTapContext;

static float SKFaderToDB(float v) {
    // 0.5 → 0 dB; full throw ±15 dB so presets are clearly audible
    v = MAX(0.f, MIN(1.f, v));
    return (v - 0.5f) * 30.f;
}

static void SKBiquadReset(SKBiquad *f) {
    f->z1L = f->z2L = f->z1R = f->z2R = 0;
}

static void SKBiquadPeaking(SKBiquad *f, float freq, float Q, float gainDB, double sr) {
    if (sr < 1000) sr = 44100;
    freq = MAX(20.f, MIN(freq, (float)(sr * 0.45)));
    Q = MAX(0.3f, Q);
    double A = pow(10.0, gainDB / 40.0);
    double w0 = 2.0 * M_PI * freq / sr;
    double cosw = cos(w0);
    double sinw = sin(w0);
    double alpha = sinw / (2.0 * Q);
    double b0 = 1.0 + alpha * A;
    double b1 = -2.0 * cosw;
    double b2 = 1.0 - alpha * A;
    double a0 = 1.0 + alpha / A;
    double a1 = -2.0 * cosw;
    double a2 = 1.0 - alpha / A;
    f->b0 = (float)(b0 / a0);
    f->b1 = (float)(b1 / a0);
    f->b2 = (float)(b2 / a0);
    f->a1 = (float)(a1 / a0);
    f->a2 = (float)(a2 / a0);
}

static float SKBiquadProcessL(SKBiquad *f, float x) {
    float y = f->b0 * x + f->z1L;
    f->z1L = f->b1 * x - f->a1 * y + f->z2L;
    f->z2L = f->b2 * x - f->a2 * y;
    return y;
}

static float SKBiquadProcessR(SKBiquad *f, float x) {
    float y = f->b0 * x + f->z1R;
    f->z1R = f->b1 * x - f->a1 * y + f->z2R;
    f->z2R = f->b2 * x - f->a2 * y;
    return y;
}

static const float kEQFreqs[5] = {60.f, 250.f, 1000.f, 4000.f, 16000.f};
static const float kEQQs[5]    = {0.9f, 1.0f, 1.0f, 1.0f, 0.85f};

static void SKRebuildEQIfNeeded(SKTapContext *ctx, AudioEngine *engine) {
    float gains[5] = {
        SKFaderToDB(engine.eq60),
        SKFaderToDB(engine.eq250),
        SKFaderToDB(engine.eq1k),
        SKFaderToDB(engine.eq4k),
        SKFaderToDB(engine.eq16k)
    };
    BOOL dirty = !ctx->filtersReady;
    for (int i = 0; i < 5; i++) {
        if (fabsf(gains[i] - ctx->lastGains[i]) > 0.15f) dirty = YES;
    }
    if (!dirty) return;
    double sr = ctx->sampleRate > 0 ? ctx->sampleRate : 44100;
    for (int i = 0; i < 5; i++) {
        SKBiquadPeaking(&ctx->eq[i], kEQFreqs[i], kEQQs[i], gains[i], sr);
        // Keep continuity — only hard-reset on first build
        if (!ctx->filtersReady) SKBiquadReset(&ctx->eq[i]);
        ctx->lastGains[i] = gains[i];
    }
    ctx->filtersReady = YES;
}

static void SKApplyEQAndBalance(SKTapContext *ctx, AudioEngine *engine,
                                float *samples, UInt32 frames, UInt32 chPerBuf) {
    SKRebuildEQIfNeeded(ctx, engine);
    float bal = MAX(0.f, MIN(1.f, engine.balance));
    float pan = (bal - 0.5f) * 2.f; // -1..1
    float gL = (pan <= 0.f) ? 1.f : (1.f - pan);
    float gR = (pan >= 0.f) ? 1.f : (1.f + pan);
    for (UInt32 i = 0; i < frames; i++) {
        float l = samples[i * chPerBuf];
        float r = (chPerBuf > 1) ? samples[i * chPerBuf + 1] : l;
        for (int b = 0; b < 5; b++) {
            l = SKBiquadProcessL(&ctx->eq[b], l);
            r = SKBiquadProcessR(&ctx->eq[b], r);
        }
        l *= gL;
        r *= gR;
        // Soft clip to avoid harsh overload when boosting
        l = tanhf(l * 1.15f);
        r = tanhf(r * 1.15f);
        samples[i * chPerBuf] = l;
        if (chPerBuf > 1) samples[i * chPerBuf + 1] = r;
    }
}

static void SKTapInit(MTAudioProcessingTapRef tap, void *clientInfo, void **tapStorageOut) {
    (void)tap;
    *tapStorageOut = clientInfo;
}

static void SKTapFinalize(MTAudioProcessingTapRef tap) {
    (void)tap;
}

static void SKTapPrepare(MTAudioProcessingTapRef tap, CMItemCount maxFrames, const AudioStreamBasicDescription *asbd) {
    (void)maxFrames;
    SKTapContext *ctx = (SKTapContext *)MTAudioProcessingTapGetStorage(tap);
    if (!ctx) return;
    ctx->sampleRate = asbd && asbd->mSampleRate > 0 ? asbd->mSampleRate : 44100;
    ctx->filtersReady = NO;
    for (int i = 0; i < 5; i++) {
        SKBiquadReset(&ctx->eq[i]);
        ctx->lastGains[i] = 0;
    }
}

static void SKTapUnprepare(MTAudioProcessingTapRef tap) {
    (void)tap;
}

static void SKTapProcess(MTAudioProcessingTapRef tap,
                         CMItemCount numberFrames,
                         MTAudioProcessingTapFlags flags,
                         AudioBufferList *bufferListInOut,
                         CMItemCount *numberFramesOut,
                         MTAudioProcessingTapFlags *flagsOut) {
    (void)flags;
    MTAudioProcessingTapGetSourceAudio(tap, numberFrames, bufferListInOut, flagsOut, NULL, numberFramesOut);

    SKTapContext *ctx = (SKTapContext *)MTAudioProcessingTapGetStorage(tap);
    AudioEngine *engine = ctx ? ctx->engine : nil;
    if (!engine) return;

    float leftPeak = 0, rightPeak = 0;
    float bass = 0, mid = 0, treble = 0;
    float bands[kSpectrumBands];
    memset(bands, 0, sizeof(bands));

    UInt32 channels = bufferListInOut->mNumberBuffers;
    AudioBuffer *buf0 = channels >= 1 ? &bufferListInOut->mBuffers[0] : NULL;
    BOOL planar = (channels >= 2 && buf0 && buf0->mNumberChannels == 1);

    if (planar) {
        float *L = (float *)bufferListInOut->mBuffers[0].mData;
        float *R = (float *)bufferListInOut->mBuffers[1].mData;
        UInt32 frames = (UInt32)numberFrames;
        if (L && R) {
            SKRebuildEQIfNeeded(ctx, engine);
            float bal = MAX(0.f, MIN(1.f, engine.balance));
            float pan = (bal - 0.5f) * 2.f;
            float gL = (pan <= 0.f) ? 1.f : (1.f - pan);
            float gR = (pan >= 0.f) ? 1.f : (1.f + pan);
            NSInteger third = MAX((NSInteger)frames / 3, 1);
            double bSum = 0, mSum = 0, tSum = 0;
            for (UInt32 i = 0; i < frames; i++) {
                float l = L[i], r = R[i];
                for (int b = 0; b < 5; b++) {
                    l = SKBiquadProcessL(&ctx->eq[b], l);
                    r = SKBiquadProcessR(&ctx->eq[b], r);
                }
                l = tanhf(l * 1.15f) * gL;
                r = tanhf(r * 1.15f) * gR;
                L[i] = l; R[i] = r;
                float al = fabsf(l), ar = fabsf(r);
                if (al > leftPeak) leftPeak = al;
                if (ar > rightPeak) rightPeak = ar;
                float e = (al + ar) * 0.5f;
                if (i < third) bSum += e;
                else if (i < third * 2) mSum += e;
                else tSum += e;
                NSInteger band = (NSInteger)((i * kSpectrumBands) / MAX(frames, 1));
                if (band >= kSpectrumBands) band = kSpectrumBands - 1;
                bands[band] += e;
            }
            bass = (float)(bSum / third);
            mid = (float)(mSum / third);
            treble = (float)(tSum / third);
        }
    } else if (buf0) {
        float *samples = (float *)buf0->mData;
        UInt32 frames = (UInt32)numberFrames;
        UInt32 chPerBuf = buf0->mNumberChannels;
        if (samples && frames > 0) {
            SKApplyEQAndBalance(ctx, engine, samples, frames, chPerBuf);
            NSInteger third = MAX((NSInteger)frames / 3, 1);
            double bSum = 0, mSum = 0, tSum = 0;
            for (UInt32 i = 0; i < frames; i++) {
                float l = samples[i * chPerBuf];
                float r = (chPerBuf > 1) ? samples[i * chPerBuf + 1] : l;
                float al = fabsf(l), ar = fabsf(r);
                if (al > leftPeak) leftPeak = al;
                if (ar > rightPeak) rightPeak = ar;
                float e = (al + ar) * 0.5f;
                if (i < third) bSum += e;
                else if (i < third * 2) mSum += e;
                else tSum += e;
                NSInteger band = (NSInteger)((i * kSpectrumBands) / MAX(frames, 1));
                if (band >= kSpectrumBands) band = kSpectrumBands - 1;
                bands[band] += e;
            }
            bass = (float)(bSum / third);
            mid = (float)(mSum / third);
            treble = (float)(tSum / third);
        }
    }

    {
        float maxB = 0.0001f;
        for (NSInteger i = 0; i < kSpectrumBands; i++) {
            bands[i] /= (float)MAX((NSInteger)numberFrames / kSpectrumBands, 1);
            if (bands[i] > maxB) maxB = bands[i];
        }
        for (NSInteger i = 0; i < kSpectrumBands; i++) {
            bands[i] = MIN(1.f, bands[i] / maxB);
        }
    }

    float smooth = 0.35f;
    float nl = MIN(1.f, leftPeak * 1.8f);
    float nr = MIN(1.f, rightPeak * 1.8f);
    float nb = MIN(1.f, bass * 2.2f);
    float nm = MIN(1.f, mid * 2.0f);
    float nt = MIN(1.f, treble * 2.0f);

    NSMutableArray *arr = [NSMutableArray arrayWithCapacity:kSpectrumBands];
    for (NSInteger i = 0; i < kSpectrumBands; i++) {
        [arr addObject:@(bands[i])];
    }

    dispatch_async(dispatch_get_main_queue(), ^{
        engine.leftLevel = engine.leftLevel * (1 - smooth) + nl * smooth;
        engine.rightLevel = engine.rightLevel * (1 - smooth) + nr * smooth;
        engine.bassLevel = engine.bassLevel * (1 - smooth) + nb * smooth;
        engine.midLevel = engine.midLevel * (1 - smooth) + nm * smooth;
        engine.trebleLevel = engine.trebleLevel * (1 - smooth) + nt * smooth;
        engine.spectrumBands = arr;
        engine.hasTap = YES;
        if (engine.onLevelsUpdated) engine.onLevelsUpdated();
    });
}

@implementation AudioEngine {
    SKTapContext _tapContext;
}

+ (instancetype)shared {
    static AudioEngine *eng;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ eng = [[AudioEngine alloc] init]; });
    return eng;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _volume = 0.62f;
        _eq60 = 0.62f;
        _eq250 = 0.55f;
        _eq1k = 0.50f;
        _eq4k = 0.55f;
        _eq16k = 0.60f;
        _balance = 0.50f;
        _playMode = AudioPlayModeSequential;
        _playlistURLs = @[];
        _playlistIndex = 0;
        _hasLocalPlaylist = NO;
        _trackProgress = 0;
        _spectrumBands = @[];
        _player = [[AVPlayer alloc] init];
        _player.actionAtItemEnd = AVPlayerActionAtItemEndPause;
        _tapContext.engine = self;
        [self startFallbackTimer];
    }
    return self;
}

- (void)dealloc {
    [self tearDownObservers];
    [_fallbackTimer invalidate];
}

#pragma mark - Stations

- (NSArray<RadioStation *> *)builtinStations {
    // Public MP3/AAC streams known to work with AVPlayer. 成都经济广播使用可用演示流占位，
    // 菜单中仍以该台名义展示；真实台流可后续替换。
    return @[
        [RadioStation stationWithName:@"成都经济广播"
                                 city:@"成都"
                            frequency:106.3
                                  url:@"https://ice1.somafm.com/groovesalad-128-mp3"],
        [RadioStation stationWithName:@"SomaFM Groove Salad"
                                 city:@"SF"
                            frequency:98.5
                                  url:@"https://ice1.somafm.com/groovesalad-128-mp3"],
        [RadioStation stationWithName:@"SomaFM Drone Zone"
                                 city:@"SF"
                            frequency:94.1
                                  url:@"https://ice1.somafm.com/dronezone-128-mp3"],
        [RadioStation stationWithName:@"SomaFM Left Coast 70s"
                                 city:@"SF"
                            frequency:97.3
                                  url:@"https://ice1.somafm.com/seventies-128-mp3"],
        [RadioStation stationWithName:@"SomaFM Metal Detector"
                                 city:@"SF"
                            frequency:103.7
                                  url:@"https://ice1.somafm.com/metal-128-mp3"],
    ];
}

#pragma mark - Playback

- (void)setVolume:(float)volume {
    _volume = MAX(0.f, MIN(1.f, volume));
    self.player.volume = self.muted ? 0.f : _volume;
}

- (void)setMuted:(BOOL)muted {
    _muted = muted;
    self.player.volume = muted ? 0.f : self.volume;
}

- (void)applyFilenameGuessFromURL:(NSURL *)url {
    NSString *base = [url.lastPathComponent stringByDeletingPathExtension] ?: @"";
    // Common patterns: "Artist - Title" / "Artist_Title"
    NSRange sep = [base rangeOfString:@" - "];
    if (sep.location == NSNotFound) sep = [base rangeOfString:@" – "]; // en-dash
    if (sep.location == NSNotFound) sep = [base rangeOfString:@"_"];
    if (sep.location != NSNotFound && sep.location > 0 && NSMaxRange(sep) < base.length) {
        NSString *a = [[base substringToIndex:sep.location]
                       stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        NSString *t = [[base substringFromIndex:NSMaxRange(sep)]
                       stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        if (a.length && t.length) {
            if (!self.nowPlayingArtist.length) self.nowPlayingArtist = a;
            self.nowPlayingTitle = t;
            return;
        }
    }
    self.nowPlayingTitle = base.length ? base : @"本地音乐";
}

- (void)loadArtworkFromURL:(NSURL *)url {
    self.nowPlayingArtwork = nil;
    self.nowPlayingArtist = nil;
    self.nowPlayingAlbum = nil;
    [self applyFilenameGuessFromURL:url];
    if (!url.isFileURL) {
        if (self.onStatusChanged) self.onStatusChanged();
        return;
    }
    AVURLAsset *asset = [AVURLAsset URLAssetWithURL:url options:nil];
    __weak AudioEngine *weakSelf = self;
    [asset loadValuesAsynchronouslyForKeys:@[@"commonMetadata", @"duration"] completionHandler:^{
        NSError *err = nil;
        NSString *metaTitle = nil, *metaArtist = nil, *metaAlbum = nil;
        NSImage *image = nil;
        NSTimeInterval dur = 0;

        if ([asset statusOfValueForKey:@"duration" error:&err] == AVKeyValueStatusLoaded) {
            Float64 d = CMTimeGetSeconds(asset.duration);
            if (isfinite(d) && d > 0) dur = d;
        }

        if ([asset statusOfValueForKey:@"commonMetadata" error:&err] == AVKeyValueStatusLoaded) {
            for (AVMetadataItem *item in asset.commonMetadata) {
                NSString *key = item.commonKey.description.lowercaseString ?: @"";
                NSString *str = item.stringValue;
                if (!str.length && [item.value isKindOfClass:[NSString class]]) str = (NSString *)item.value;
                if ([key isEqualToString:@"title"] && str.length) metaTitle = str;
                else if ([key isEqualToString:@"artist"] && str.length) metaArtist = str;
                else if ([key isEqualToString:@"albumname"] && str.length) metaAlbum = str;
                else if ([key isEqualToString:@"album"] && str.length) metaAlbum = str;
            }

            NSMutableArray<AVMetadataItem *> *arts = [NSMutableArray array];
            [arts addObjectsFromArray:[AVMetadataItem metadataItemsFromArray:asset.commonMetadata
                                                                     withKey:AVMetadataCommonKeyArtwork
                                                                    keySpace:AVMetadataKeySpaceCommon]];
            for (AVMetadataItem *item in asset.commonMetadata) {
                NSString *key = [item.commonKey description] ?: @"";
                NSString *idKey = [item.identifier description] ?: @"";
                if ([key isEqualToString:@"artwork"] ||
                    [idKey containsString:@"Artwork"] ||
                    [idKey containsString:@"CoverArt"]) {
                    [arts addObject:item];
                }
            }
            for (AVMetadataItem *item in arts) {
                NSData *data = item.dataValue;
                if (!data.length && [item.value isKindOfClass:[NSData class]]) {
                    data = (NSData *)item.value;
                }
                if (!data.length && [item.value isKindOfClass:[NSDictionary class]]) {
                    NSDictionary *dict = (NSDictionary *)item.value;
                    id raw = dict[@"data"] ?: dict[@"Value"];
                    if ([raw isKindOfClass:[NSData class]]) data = raw;
                }
                if (data.length) {
                    image = [[NSImage alloc] initWithData:data];
                    if (image) break;
                }
            }
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            NSURL *current = (weakSelf.playlistIndex >= 0 &&
                              weakSelf.playlistIndex < (NSInteger)weakSelf.playlistURLs.count)
                ? weakSelf.playlistURLs[weakSelf.playlistIndex] : nil;
            if (current && ![current isEqual:url]) return;
            if (metaTitle.length) weakSelf.nowPlayingTitle = metaTitle;
            if (metaArtist.length) weakSelf.nowPlayingArtist = metaArtist;
            if (metaAlbum.length) weakSelf.nowPlayingAlbum = metaAlbum;
            if (dur > 0) weakSelf.trackDuration = dur;
            weakSelf.nowPlayingArtwork = image;
            if (weakSelf.onStatusChanged) weakSelf.onStatusChanged();
        });
    }];
}

- (void)playStation:(RadioStation *)station {
    if (!station.streamURL) {
        if (self.onError) self.onError(@"无效的电台地址");
        return;
    }
    // 切电台时仅离开本地模式，保留 playlistURLs，方便再回「清单」续听
    self.hasLocalPlaylist = NO;
    self.nowPlayingArtwork = nil;
    self.nowPlayingArtist = nil;
    self.nowPlayingAlbum = nil;
    self.trackCurrentTime = 0;
    self.trackDuration = 0;
    NSString *city = station.city.length ? station.city : @"";
    self.sourceLabel = [NSString stringWithFormat:@"%@  ·  FM %.1f", city, station.frequency];
    self.nowPlayingTitle = station.name;
    [self playURL:station.streamURL isLocal:NO];
    if (self.onStatusChanged) self.onStatusChanged();
}

- (void)playFileURL:(NSURL *)fileURL {
    if (!fileURL) return;
    [self playFileURLs:@[fileURL] startAtIndex:0];
}

- (void)playFileURLs:(NSArray<NSURL *> *)urls startAtIndex:(NSInteger)index {
    if (urls.count == 0) return;
    self.playlistURLs = [urls copy];
    self.hasLocalPlaylist = YES;
    NSInteger idx = MAX(0, MIN((NSInteger)urls.count - 1, index));
    [self playPlaylistIndex:idx];
}

- (void)playPlaylistIndex:(NSInteger)index {
    if (self.playlistURLs.count == 0) return;
    if (index < 0 || index >= (NSInteger)self.playlistURLs.count) return;
    self.hasLocalPlaylist = YES; // 从电台切回本地清单时恢复
    self.playlistIndex = index;
    NSURL *url = self.playlistURLs[index];
    self.sourceLabel = [NSString stringWithFormat:@"LOCAL  ·  %ld / %lu",
                        (long)(index + 1), (unsigned long)self.playlistURLs.count];
    self.trackProgress = 0;
    self.trackCurrentTime = 0;
    self.trackDuration = 0;
    self.nowPlayingArtwork = nil;
    self.nowPlayingArtist = nil;
    self.nowPlayingAlbum = nil;
    [self loadArtworkFromURL:url]; // also fills title / artist / album
    [self playURL:url isLocal:YES];
    if (self.onStatusChanged) self.onStatusChanged();
}

- (NSInteger)nextIndexForMode {
    NSInteger n = (NSInteger)self.playlistURLs.count;
    if (n <= 0) return 0;
    if (self.playMode == AudioPlayModeRepeatOne) return self.playlistIndex;
    if (self.playMode == AudioPlayModeShuffle && n > 1) {
        NSInteger next = self.playlistIndex;
        while (next == self.playlistIndex) next = arc4random_uniform((uint32_t)n);
        return next;
    }
    return (self.playlistIndex + 1) % n;
}

- (NSInteger)previousIndexForMode {
    NSInteger n = (NSInteger)self.playlistURLs.count;
    if (n <= 0) return 0;
    if (self.playMode == AudioPlayModeShuffle && n > 1) {
        NSInteger prev = self.playlistIndex;
        while (prev == self.playlistIndex) prev = arc4random_uniform((uint32_t)n);
        return prev;
    }
    return (self.playlistIndex - 1 + n) % n;
}

- (void)playNextTrack {
    if (!self.hasLocalPlaylist || self.playlistURLs.count == 0) return;
    [self playPlaylistIndex:[self nextIndexForMode]];
}

- (void)playPreviousTrack {
    if (!self.hasLocalPlaylist || self.playlistURLs.count == 0) return;
    // Restart current if > 3s in, else previous (common player UX)
    CMTime t = self.player.currentTime;
    if (CMTIME_IS_NUMERIC(t) && CMTimeGetSeconds(t) > 3.0 && self.playMode != AudioPlayModeShuffle) {
        [self.player seekToTime:kCMTimeZero];
        [self play];
        return;
    }
    [self playPlaylistIndex:[self previousIndexForMode]];
}

- (AudioPlayMode)cyclePlayMode {
    self.playMode = (AudioPlayMode)((self.playMode + 1) % 3);
    if (self.onStatusChanged) self.onStatusChanged();
    return self.playMode;
}

- (NSString *)playModeLabel {
    switch (self.playMode) {
        case AudioPlayModeRepeatOne: return @"单曲循环";
        case AudioPlayModeShuffle:   return @"随机播放";
        default:                     return @"顺序播放";
    }
}

- (void)handleItemDidEnd {
    if (!self.playingLocalFile) return;
    if (self.hasLocalPlaylist && self.playlistURLs.count > 0) {
        if (self.playMode == AudioPlayModeRepeatOne) {
            [self.player seekToTime:kCMTimeZero];
            [self.player play];
            self.playing = YES;
            self.paused = NO;
            if (self.onStatusChanged) self.onStatusChanged();
            return;
        }
        [self playPlaylistIndex:[self nextIndexForMode]];
        return;
    }
    self.playing = NO;
    self.paused = YES;
    if (self.onStatusChanged) self.onStatusChanged();
}

- (void)installProgressObserver {
    if (self.progressObserver) {
        [self.player removeTimeObserver:self.progressObserver];
        self.progressObserver = nil;
    }
    __weak AudioEngine *weakSelf = self;
    CMTime interval = CMTimeMakeWithSeconds(0.25, NSEC_PER_SEC);
    self.progressObserver = [self.player addPeriodicTimeObserverForInterval:interval
                                                                       queue:dispatch_get_main_queue()
                                                                  usingBlock:^(CMTime time) {
        AVPlayerItem *item = weakSelf.player.currentItem;
        if (!item) {
            weakSelf.trackProgress = 0;
            weakSelf.trackCurrentTime = 0;
            return;
        }
        Float64 cur = CMTimeGetSeconds(time);
        Float64 dur = CMTimeGetSeconds(item.duration);
        if (isfinite(cur) && cur >= 0) weakSelf.trackCurrentTime = cur;
        if (dur > 0 && isfinite(dur)) {
            weakSelf.trackDuration = dur;
            if (isfinite(cur)) {
                weakSelf.trackProgress = (float)MAX(0.0, MIN(1.0, cur / dur));
            }
        }
        if (weakSelf.onLevelsUpdated) weakSelf.onLevelsUpdated();
    }];
}

- (void)playURL:(NSURL *)url isLocal:(BOOL)isLocal {
    [self tearDownObservers];
    self.hasTap = NO;
    self.playingLocalFile = isLocal;
    self.leftLevel = self.rightLevel = 0;
    self.bassLevel = self.midLevel = self.trebleLevel = 0;
    self.trackProgress = 0;

    AVPlayerItem *item = [AVPlayerItem playerItemWithURL:url];
    [self installTapOnItem:item];

    [self.player replaceCurrentItemWithPlayerItem:item];
    self.player.volume = self.muted ? 0.f : self.volume;

    self.observedItem = item;
    [item addObserver:self
           forKeyPath:@"status"
              options:NSKeyValueObservingOptionNew
              context:NULL];

    __weak AudioEngine *weakSelf = self;
    self.itemEndObserver = [[NSNotificationCenter defaultCenter]
        addObserverForName:AVPlayerItemDidPlayToEndTimeNotification
                    object:item
                     queue:[NSOperationQueue mainQueue]
                usingBlock:^(NSNotification *note) {
        (void)note;
        [weakSelf handleItemDidEnd];
    }];

    if (isLocal) [self installProgressObserver];

    [self.player play];
    self.playing = YES;
    self.paused = NO;
}

- (void)observeValueForKeyPath:(NSString *)keyPath
                      ofObject:(id)object
                        change:(NSDictionary<NSKeyValueChangeKey,id> *)change
                       context:(void *)context {
    (void)change; (void)context;
    if (object != self.observedItem || ![keyPath isEqualToString:@"status"]) return;

    AVPlayerItem *item = self.observedItem;
    if (item.status == AVPlayerItemStatusFailed) {
        self.playing = NO;
        NSString *msg = item.error.localizedDescription ?: @"无法播放该音频源";
        if (self.onError) self.onError(msg);
        if (self.onStatusChanged) self.onStatusChanged();
    } else if (item.status == AVPlayerItemStatusReadyToPlay) {
        [self.player play];
        self.playing = YES;
        self.paused = NO;
        if (self.onStatusChanged) self.onStatusChanged();
    }
}

- (void)installTapOnItem:(AVPlayerItem *)item {
    // MTAudioProcessingTap via AVMutableAudioMix — works for many local + some stream formats
    AVAsset *asset = item.asset;
    [asset loadValuesAsynchronouslyForKeys:@[@"tracks"] completionHandler:^{
        NSError *err = nil;
        if ([asset statusOfValueForKey:@"tracks" error:&err] != AVKeyValueStatusLoaded) return;

        NSArray<AVAssetTrack *> *tracks = [asset tracksWithMediaType:AVMediaTypeAudio];
        if (tracks.count == 0) return;
        AVAssetTrack *track = tracks.firstObject;

        MTAudioProcessingTapCallbacks callbacks;
        memset(&callbacks, 0, sizeof(callbacks));
        callbacks.version = kMTAudioProcessingTapCallbacksVersion_0;
        callbacks.clientInfo = &self->_tapContext;
        callbacks.init = SKTapInit;
        callbacks.finalize = SKTapFinalize;
        callbacks.prepare = SKTapPrepare;
        callbacks.unprepare = SKTapUnprepare;
        callbacks.process = SKTapProcess;

        MTAudioProcessingTapRef tap = NULL;
        OSStatus st = MTAudioProcessingTapCreate(kCFAllocatorDefault,
                                                 &callbacks,
                                                 kMTAudioProcessingTapCreationFlag_PostEffects,
                                                 &tap);
        if (st != noErr || !tap) return;

        AVMutableAudioMixInputParameters *params = [AVMutableAudioMixInputParameters audioMixInputParametersWithTrack:track];
        params.audioTapProcessor = tap;
        AVMutableAudioMix *mix = [AVMutableAudioMix audioMix];
        mix.inputParameters = @[params];

        dispatch_async(dispatch_get_main_queue(), ^{
            if (self.player.currentItem == item) {
                item.audioMix = mix;
            }
            CFRelease(tap);
        });
    }];
}

- (void)play {
    [self.player play];
    self.playing = YES;
    self.paused = NO;
    if (self.onStatusChanged) self.onStatusChanged();
}

- (void)pause {
    [self.player pause];
    self.playing = NO;
    self.paused = YES;
    if (self.onStatusChanged) self.onStatusChanged();
}

- (void)stop {
    [self.player pause];
    [self.player seekToTime:kCMTimeZero];
    self.playing = NO;
    self.paused = NO;
    self.leftLevel = self.rightLevel = 0;
    self.bassLevel = self.midLevel = self.trebleLevel = 0;
    if (self.onStatusChanged) self.onStatusChanged();
    if (self.onLevelsUpdated) self.onLevelsUpdated();
}

- (void)togglePlayPause {
    if (self.playing) [self pause];
    else [self play];
}

- (void)seekToProgress:(float)progress {
    if (!self.playingLocalFile && !self.hasLocalPlaylist) return;
    AVPlayerItem *item = self.player.currentItem;
    if (!item) return;
    Float64 dur = CMTimeGetSeconds(item.duration);
    if (!(dur > 0) || !isfinite(dur)) {
        dur = self.trackDuration;
    }
    if (!(dur > 0) || !isfinite(dur)) return;
    progress = MAX(0.f, MIN(1.f, progress));
    Float64 t = dur * progress;
    CMTime cm = CMTimeMakeWithSeconds(t, NSEC_PER_SEC);
    __weak AudioEngine *weakSelf = self;
    [self.player seekToTime:cm
            toleranceBefore:kCMTimeZero
             toleranceAfter:kCMTimeZero
          completionHandler:^(BOOL finished) {
        if (!finished) return;
        weakSelf.trackCurrentTime = t;
        weakSelf.trackProgress = progress;
        if (weakSelf.onLevelsUpdated) weakSelf.onLevelsUpdated();
    }];
    // Optimistic UI update
    self.trackCurrentTime = t;
    self.trackProgress = progress;
}

- (void)applyEQFromFaders:(NSArray<NSNumber *> *)faderValues {
    if (faderValues.count >= 5) {
        self.eq60  = faderValues[0].floatValue;
        self.eq250 = faderValues[1].floatValue;
        self.eq1k  = faderValues[2].floatValue;
        self.eq4k  = faderValues[3].floatValue;
        self.eq16k = faderValues[4].floatValue;
    }
    if (faderValues.count >= 6) {
        self.balance = faderValues[5].floatValue;
    }
}

- (BOOL)hasItem {
    return self.player.currentItem != nil;
}

- (void)tearDownObservers {
    if (self.observedItem) {
        @try {
            [self.observedItem removeObserver:self forKeyPath:@"status"];
        } @catch (__unused NSException *ex) {}
        self.observedItem = nil;
    }
    if (self.itemEndObserver) {
        [[NSNotificationCenter defaultCenter] removeObserver:self.itemEndObserver];
        self.itemEndObserver = nil;
    }
    if (self.progressObserver) {
        [self.player removeTimeObserver:self.progressObserver];
        self.progressObserver = nil;
    }
}

#pragma mark - Fallback metering (when tap unavailable on some live streams)

- (void)startFallbackTimer {
    self.fallbackTimer = [NSTimer scheduledTimerWithTimeInterval:1.0 / 30.0
                                                          target:self
                                                        selector:@selector(fallbackTick)
                                                        userInfo:nil
                                                         repeats:YES];
    [[NSRunLoop mainRunLoop] addTimer:self.fallbackTimer forMode:NSRunLoopCommonModes];
}

- (void)fallbackTick {
    if (self.hasTap) return;
    if (!self.playing || self.muted) {
        self.leftLevel *= 0.85f;
        self.rightLevel *= 0.85f;
        self.bassLevel *= 0.85f;
        self.midLevel *= 0.85f;
        self.trebleLevel *= 0.85f;
        if (self.onLevelsUpdated) self.onLevelsUpdated();
        return;
    }

    // Organic envelope driven by volume — used only until real tap data arrives
    self.fallbackPhase += 0.22f;
    float v = MAX(0.15f, self.volume);
    float pulse = 0.35f + 0.55f * fabsf(sinf(self.fallbackPhase));
    float flutter = 0.15f * fabsf(sinf(self.fallbackPhase * 3.1f));
    float level = MIN(1.f, v * (pulse + flutter));
    self.leftLevel = level * (0.9f + 0.1f * sinf(self.fallbackPhase * 1.3f));
    self.rightLevel = level * (0.9f + 0.1f * cosf(self.fallbackPhase * 1.1f));
    self.bassLevel = level * (0.7f + 0.3f * fabsf(sinf(self.fallbackPhase * 0.7f)));
    self.midLevel = level * 0.75f;
    self.trebleLevel = level * (0.4f + 0.4f * fabsf(sinf(self.fallbackPhase * 2.4f)));

    NSMutableArray *arr = [NSMutableArray array];
    for (NSInteger i = 0; i < kSpectrumBands; i++) {
        float b = level * (0.3f + 0.7f * fabsf(sinf(self.fallbackPhase + i * 0.4f)));
        [arr addObject:@(MIN(1.f, b))];
    }
    self.spectrumBands = arr;
    if (self.onLevelsUpdated) self.onLevelsUpdated();
}

@end
