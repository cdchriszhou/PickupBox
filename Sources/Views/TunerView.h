#import <Cocoa/Cocoa.h>

@interface TunerView : NSView

@property (nonatomic, assign) CGFloat frequency; // MHz 88..108
@property (nonatomic, copy) NSString *stationName;
@property (nonatomic, copy) void (^onTune)(CGFloat mhz);

@end
