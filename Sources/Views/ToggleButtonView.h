#import <Cocoa/Cocoa.h>

@interface ToggleButtonView : NSView

@property (nonatomic, copy) NSString *title;
@property (nonatomic, assign) BOOL on;
@property (nonatomic, copy) void (^onToggle)(BOOL on);

@end
