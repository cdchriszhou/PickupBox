#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface LyricsLine : NSObject
@property (nonatomic, assign) NSTimeInterval time;
@property (nonatomic, copy) NSString *text;
+ (instancetype)lineWithTime:(NSTimeInterval)time text:(NSString *)text;
@end

@interface LyricsResult : NSObject
@property (nonatomic, copy) NSArray<LyricsLine *> *lines;
@property (nonatomic, copy, nullable) NSString *sourceLabel; // 本地 / 内嵌 / 网络
@property (nonatomic, assign) BOOL synced; // 是否带时间轴
@end

/// 本地 .lrc → 文件内嵌 → LRCLIB 在线搜索
@interface LyricsService : NSObject
+ (instancetype)shared;

/// 取消进行中的请求
- (void)cancel;

/// 按曲目拉取歌词（异步，主线程回调）
- (void)fetchLyricsForTitle:(NSString *)title
                     artist:(nullable NSString *)artist
                      album:(nullable NSString *)album
                   duration:(NSTimeInterval)duration
                    fileURL:(nullable NSURL *)fileURL
                 completion:(void (^)(LyricsResult * _Nullable result, NSString * _Nullable errorMessage))completion;

/// 解析 LRC / 纯文本
- (LyricsResult *)parseLyricsText:(NSString *)text source:(NSString *)source;

@end

NS_ASSUME_NONNULL_END
