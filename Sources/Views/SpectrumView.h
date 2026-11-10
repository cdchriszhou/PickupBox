#import <Cocoa/Cocoa.h>

@interface SpectrumView : NSView

@property (nonatomic, assign) BOOL animating;
/// When YES, only external setBandLevels drive the display (no fake demo motion)
@property (nonatomic, assign) BOOL linkedToAudio;
- (void)setBandLevels:(const float *)levels count:(NSInteger)count;
- (void)setBandLevelsFromNumbers:(NSArray<NSNumber *> *)levels;

@end
