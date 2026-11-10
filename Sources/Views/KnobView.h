#import <Cocoa/Cocoa.h>

@interface KnobView : NSView

@property (nonatomic, copy) NSString *title;
@property (nonatomic, assign) CGFloat value; // 0..1
@property (nonatomic, assign) BOOL accent;   // volume style (larger/red pointer)
@property (nonatomic, copy) void (^onChange)(CGFloat value);

@end
