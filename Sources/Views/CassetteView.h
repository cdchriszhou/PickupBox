#import <Cocoa/Cocoa.h>
#import "AudioEngine.h"

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, CassetteDeckStyle) {
    CassetteDeckStyleTape  = 0, // 卡带机：装带 / 切歌抖带
    CassetteDeckStylePhono = 1, // 留声机：落碟 / 抬杆换曲
};

@interface CassetteView : NSView

@property (nonatomic, assign) BOOL playing;
@property (nonatomic, copy, nullable) NSString *tapeTitle;
@property (nonatomic, assign) float tapeProgress; // 0..1 supply→takeup / vinyl angle
@property (nonatomic, assign) AudioPlayMode playMode;
@property (nonatomic, assign) CassetteDeckStyle deckStyle;

@property (nonatomic, copy, nullable) void (^onTransport)(NSString *command);
@property (nonatomic, copy, nullable) void (^onPlayModeChanged)(AudioPlayMode mode);
@property (nonatomic, copy, nullable) void (^onDeckStyleChanged)(CassetteDeckStyle style);

/// 导入 MP3 后：磁带滑入 / 黑胶落盘
- (void)playMediaInsertAnimation;
/// 切歌：磁带抖换 / 唱臂抬起再落针
- (void)playTrackChangeAnimation;
/// 走带键回到 STOP（电台开启 / 停带时）
- (void)resetTransportToStop;

@end

NS_ASSUME_NONNULL_END
