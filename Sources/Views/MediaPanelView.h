#import <Cocoa/Cocoa.h>
#import "AudioEngine.h"
#import "LyricsService.h"

/// Media panel tabs
typedef NS_ENUM(NSInteger, MediaPanelTab) {
    MediaPanelTabCover  = 0, // 封面
    MediaPanelTabLocal  = 1, // 清单 — 本地 MP3，持久保留
    MediaPanelTabRadio  = 2, // 电台 — 当前地区频率
    MediaPanelTabLyrics = 3, // 歌词
};

@interface MediaPanelView : NSView

@property (nonatomic, assign) MediaPanelTab selectedTab;
@property (nonatomic, copy) NSString *titleText;
@property (nonatomic, copy) NSString *subtitleText;
@property (nonatomic, strong, nullable) NSImage *coverImage;

/// 本地曲目清单（EJECT 装载，不被电台覆盖）
@property (nonatomic, copy) NSArray<RadioStation *> *localTracks;
@property (nonatomic, assign) NSInteger selectedLocalIndex;

/// 当前地区电台频率
@property (nonatomic, copy, nullable) NSString *radioCityName;
@property (nonatomic, copy) NSArray<RadioStation *> *radioStations;
@property (nonatomic, assign) NSInteger selectedRadioIndex;

/// 歌词
@property (nonatomic, copy, nullable) NSArray<LyricsLine *> *lyricsLines;
@property (nonatomic, assign) NSTimeInterval lyricsTime;
@property (nonatomic, copy, nullable) NSString *lyricsStatus; // 搜索中 / 未找到…
@property (nonatomic, copy, nullable) NSString *lyricsSource;

@property (nonatomic, copy, nullable) void (^onSelectLocalAtIndex)(NSInteger index);
@property (nonatomic, copy, nullable) void (^onSelectRadioAtIndex)(NSInteger index);

- (void)reloadStationList;
- (void)clearLyrics;

@end
