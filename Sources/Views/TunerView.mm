#import "TunerView.h"
#import "DrawingHelpers.h"

@implementation TunerView {
    BOOL _dragging;
}

- (instancetype)initWithFrame:(NSRect)frameRect {
    self = [super initWithFrame:frameRect];
    if (self) {
        _frequency = 106.3;
        _stationName = @"CITY 成都 106.3 MHz";
    }
    return self;
}

- (BOOL)isFlipped { return YES; }

- (NSRect)scaleRect {
    return NSMakeRect(16, 28, NSWidth(self.bounds) - 100, 36);
}

- (void)drawRect:(NSRect)dirtyRect {
    NSRect bounds = self.bounds;
    SKFillBrushedMetal(bounds, 0.05);
    SKDrawInsetBevel(NSInsetRect(bounds, 4, 4), 3);

    // Title
    NSFont *titleFont = [NSFont systemFontOfSize:10 weight:NSFontWeightSemibold];
    SKDrawGlowText(@"FM / AM QUARTZ LOCK SYNTHESIZER TUNER",
                   NSMakeRect(12, 8, 360, 14),
                   titleFont,
                   [NSColor colorWithCalibratedWhite:0.75 alpha:1],
                   NSTextAlignmentLeft);

    // Scale background
    NSRect scale = [self scaleRect];
    SKDrawInsetBevel(scale, 2);
    NSRect scaleInner = NSInsetRect(scale, 2, 2);
    [[NSColor colorWithCalibratedRed:0.95 green:0.92 blue:0.82 alpha:1] set];
    NSRectFill(scaleInner);

    // Frequency marks 88..108
    NSFont *markFont = [NSFont monospacedDigitSystemFontOfSize:8 weight:NSFontWeightMedium];
    for (int mhz = 88; mhz <= 108; mhz += 2) {
        CGFloat t = (mhz - 88) / 20.0;
        CGFloat x = NSMinX(scaleInner) + 8 + t * (NSWidth(scaleInner) - 16);
        [[NSColor colorWithCalibratedWhite:0.15 alpha:1] set];
        NSRectFill(NSMakeRect(x, NSMinY(scaleInner) + 4, 1, NSHeight(scaleInner) - 18));
        NSString *lab = [NSString stringWithFormat:@"%d", mhz];
        [lab drawInRect:NSMakeRect(x - 10, NSMaxY(scaleInner) - 12, 20, 10)
         withAttributes:@{NSFontAttributeName: markFont,
                          NSForegroundColorAttributeName: [NSColor blackColor],
                          NSParagraphStyleAttributeName: ({
                              NSMutableParagraphStyle *p = [NSMutableParagraphStyle new];
                              p.alignment = NSTextAlignmentCenter; p;
                          })}];
    }

    // Needle
    CGFloat ft = (self.frequency - 88.0) / 20.0;
    CGFloat nx = NSMinX(scaleInner) + 8 + ft * (NSWidth(scaleInner) - 16);
    [[NSColor colorWithCalibratedRed:0.85 green:0.05 blue:0.05 alpha:1] set];
    NSBezierPath *needle = [NSBezierPath bezierPath];
    [needle moveToPoint:NSMakePoint(nx, NSMinY(scaleInner) + 2)];
    [needle lineToPoint:NSMakePoint(nx, NSMaxY(scaleInner) - 2)];
    [needle setLineWidth:1.5];
    [needle stroke];

    // Signal LEDs
    NSRect ledBox = NSMakeRect(NSMaxX(scale) + 10, 28, 70, 50);
    SKDrawInsetBevel(ledBox, 2);
    NSArray *labels = @[@"TUNED", @"STEREO", @"SIGNAL"];
    for (NSInteger i = 0; i < 3; i++) {
        CGFloat y = NSMinY(ledBox) + 6 + i * 14;
        NSRect led = NSMakeRect(NSMinX(ledBox) + 6, y, 8, 8);
        NSBezierPath *dot = [NSBezierPath bezierPathWithOvalInRect:led];
        BOOL on = (i < 2) || YES;
        [(on ? SKAmberColor() : SKAmberDimColor()) set];
        [dot fill];
        SKDrawGlowText(labels[i],
                       NSMakeRect(NSMinX(ledBox) + 18, y - 1, 48, 12),
                       [NSFont systemFontOfSize:8 weight:NSFontWeightMedium],
                       SKAmberColor(),
                       NSTextAlignmentLeft);
    }

    // Station readout
    NSRect readout = NSMakeRect(16, NSHeight(bounds) - 28, 280, 18);
    SKDrawInsetBevel(readout, 2);
    SKDrawGlowText(self.stationName ?: @"",
                   NSInsetRect(readout, 6, 2),
                   [NSFont monospacedDigitSystemFontOfSize:11 weight:NSFontWeightMedium],
                   SKAmberColor(),
                   NSTextAlignmentLeft);

    // Tuning knob
    NSPoint kc = NSMakePoint(NSWidth(bounds) - 36, NSMidY(bounds) + 4);
    CGFloat kr = 16;
    NSRect krRect = NSMakeRect(kc.x - kr, kc.y - kr, kr * 2, kr * 2);
    NSBezierPath *knob = [NSBezierPath bezierPathWithOvalInRect:krRect];
    NSGradient *kg = [[NSGradient alloc] initWithStartingColor:[NSColor colorWithCalibratedWhite:0.4 alpha:1]
                                                   endingColor:[NSColor colorWithCalibratedWhite:0.12 alpha:1]];
    [kg drawInBezierPath:knob angle:135];
    SKDrawGlowText(@"TUNING",
                   NSMakeRect(kc.x - 28, kc.y + kr + 2, 56, 12),
                   [NSFont systemFontOfSize:8 weight:NSFontWeightMedium],
                   [NSColor colorWithCalibratedWhite:0.65 alpha:1],
                   NSTextAlignmentCenter);

    // Quartz lock badge
    SKDrawGlowText(@"QUARTZ LOCK",
                   NSMakeRect(NSWidth(bounds) - 120, 8, 100, 12),
                   [NSFont systemFontOfSize:9 weight:NSFontWeightBold],
                   SKAmberColor(),
                   NSTextAlignmentRight);
}

- (void)mouseDown:(NSEvent *)event {
    NSPoint p = [self convertPoint:event.locationInWindow fromView:nil];
    if (NSPointInRect(p, [self scaleRect])) {
        _dragging = YES;
        [self tuneFromPoint:p];
    }
}

- (void)mouseDragged:(NSEvent *)event {
    if (!_dragging) return;
    NSPoint p = [self convertPoint:event.locationInWindow fromView:nil];
    [self tuneFromPoint:p];
}

- (void)mouseUp:(NSEvent *)event { _dragging = NO; }

- (void)tuneFromPoint:(NSPoint)p {
    NSRect scale = NSInsetRect([self scaleRect], 2, 2);
    CGFloat t = (p.x - (NSMinX(scale) + 8)) / (NSWidth(scale) - 16);
    t = MAX(0, MIN(1, t));
    self.frequency = 88.0 + t * 20.0;
    self.stationName = [NSString stringWithFormat:@"FM %.1f MHz", self.frequency];
    [self setNeedsDisplay:YES];
    if (self.onTune) self.onTune(self.frequency);
}

@end
