#import <Cocoa/Cocoa.h>

/// Physical raised metal key with optional LED (Sony-style preset / source key)
@interface MetalKeyView : NSView

@property (nonatomic, copy) NSString *title;
@property (nonatomic, assign) BOOL selected;
@property (nonatomic, assign) BOOL showLED;      // red/amber LED above key face
@property (nonatomic, assign) BOOL ledOn;
@property (nonatomic, assign) BOOL ledRed;       // YES=red (EQ), NO=amber (source)
@property (nonatomic, copy, nullable) void (^onClick)(void);

@end
