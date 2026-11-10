#import <Cocoa/Cocoa.h>
#import "AudioEngine.h"
#import "BrandProfile.h"

@interface MainConsoleView : NSView

@property (nonatomic, strong, readonly) BrandProfile *brandProfile;

- (void)setStatusFrequency:(CGFloat)mhz station:(NSString *)station;
- (void)setPlaying:(BOOL)playing;
- (void)playStation:(RadioStation *)station;
- (void)selectCityNamed:(NSString *)name;
- (void)openLocalMusic;
- (void)refreshFromEngine;
- (void)applyBrandProfile:(BrandProfile *)profile;

@end
