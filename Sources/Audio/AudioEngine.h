#import <Foundation/Foundation.h>
#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, AudioPlayMode) {
    AudioPlayModeSequential = 0, // 顺序播放
    AudioPlayModeRepeatOne  = 1, // 单曲循环
    AudioPlayModeShuffle    = 2, // 随机播放
};

@interface RadioStation : NSObject
@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy) NSString *city;
@property (nonatomic, copy, nullable) NSString *country;
@property (nonatomic, copy, nullable) NSString *codec;
@property (nonatomic, assign) NSInteger bitrate;
@property (nonatomic, assign) CGFloat frequency;
@property (nonatomic, copy, nullable) NSURL *streamURL;
@property (nonatomic, copy, nullable) NSString *homepage;
+ (instancetype)stationWithName:(NSString *)name
                           city:(NSString *)city
                      frequency:(CGFloat)mhz
                            url:(NSString *)urlString;
@end

@interface AudioEngine : NSObject

+ (instancetype)shared;

@property (nonatomic, assign) float volume; // 0..1
@property (nonatomic, assign) BOOL muted;
/// Graphic EQ: 5 band faders 0..1 (0.5 = flat). Freqs: 60 / 250 / 1k / 4k / 16k
@property (nonatomic, assign) float eq60;
@property (nonatomic, assign) float eq250;
@property (nonatomic, assign) float eq1k;
@property (nonatomic, assign) float eq4k;
@property (nonatomic, assign) float eq16k;
/// Balance 0..1 (0.5 = center)
@property (nonatomic, assign) float balance;
@property (nonatomic, readonly) BOOL playing;
@property (nonatomic, readonly) BOOL paused;
@property (nonatomic, readonly) BOOL hasItem;
@property (nonatomic, readonly, nullable) NSString *nowPlayingTitle;
@property (nonatomic, readonly, nullable) NSString *nowPlayingArtist;
@property (nonatomic, readonly, nullable) NSString *nowPlayingAlbum;
@property (nonatomic, readonly, nullable) NSString *sourceLabel;
@property (nonatomic, readonly, nullable) NSImage *nowPlayingArtwork;

/// Local MP3 playlist
@property (nonatomic, readonly) BOOL hasLocalPlaylist;
@property (nonatomic, readonly, copy) NSArray<NSURL *> *playlistURLs;
@property (nonatomic, readonly) NSInteger playlistIndex;
@property (nonatomic, assign) AudioPlayMode playMode;
/// 0..1 position within current local track (for cassette reels)
@property (nonatomic, readonly) float trackProgress;
/// Absolute playback clock (seconds) for lyric sync
@property (nonatomic, readonly) NSTimeInterval trackCurrentTime;
@property (nonatomic, readonly) NSTimeInterval trackDuration;

/// Stereo / band meters 0..1 (smoothed)
@property (nonatomic, readonly) float leftLevel;
@property (nonatomic, readonly) float rightLevel;
@property (nonatomic, readonly) float bassLevel;
@property (nonatomic, readonly) float midLevel;
@property (nonatomic, readonly) float trebleLevel;
@property (nonatomic, readonly) NSArray<NSNumber *> *spectrumBands; // 32 bands

@property (nonatomic, copy, nullable) void (^onLevelsUpdated)(void);
@property (nonatomic, copy, nullable) void (^onStatusChanged)(void);
@property (nonatomic, copy, nullable) void (^onError)(NSString *message);

- (NSArray<RadioStation *> *)builtinStations;
- (void)playStation:(RadioStation *)station;
- (void)playFileURL:(NSURL *)fileURL;
- (void)playFileURLs:(NSArray<NSURL *> *)urls startAtIndex:(NSInteger)index;
- (void)playPlaylistIndex:(NSInteger)index;
- (void)playNextTrack;
- (void)playPreviousTrack;
- (AudioPlayMode)cyclePlayMode;
- (NSString *)playModeLabel;
- (void)play;
- (void)pause;
- (void)stop;
- (void)togglePlayPause;
/// Seek local track to 0..1 position (no-op for radio streams)
- (void)seekToProgress:(float)progress;
/// Push UI fader values (5 EQ + optional BAL as 6th) into the live EQ
- (void)applyEQFromFaders:(NSArray<NSNumber *> *)faderValues;

@end

NS_ASSUME_NONNULL_END
