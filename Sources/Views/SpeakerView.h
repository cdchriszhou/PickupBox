#import <Cocoa/Cocoa.h>

@interface SpeakerView : NSView

/// Overall activity / volume coupling 0..1
@property (nonatomic, assign) CGFloat activity;
/// Per-band drive from AudioEngine (0..1) — makes cones tremble with music
@property (nonatomic, assign) CGFloat bassLevel;
@property (nonatomic, assign) CGFloat midLevel;
@property (nonatomic, assign) CGFloat trebleLevel;
@property (nonatomic, assign) CGFloat channelLevel; // L or R RMS
@property (nonatomic, assign) BOOL mirrored;
@property (nonatomic, assign) BOOL playing;
/// BrandProfile identifier for nameplate (classic / night / ocean / studio)
@property (nonatomic, copy) NSString *brandRailText;

- (void)pushWaveformSample:(float)sample;

@end
