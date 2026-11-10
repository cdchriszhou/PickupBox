#import <Cocoa/Cocoa.h>

@interface FaderView : NSView

@property (nonatomic, copy) NSString *title;
@property (nonatomic, assign) CGFloat value; // 0..1
@property (nonatomic, copy) void (^onChange)(CGFloat value);

@end
