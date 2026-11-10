#import "FaderView.h"
#import "DrawingHelpers.h"

@implementation FaderView {
    BOOL _dragging;
}

- (instancetype)initWithFrame:(NSRect)frameRect {
    self = [super initWithFrame:frameRect];
    if (self) {
        _value = 0.5;
        _title = @"BASS";
    }
    return self;
}

- (BOOL)isFlipped { return YES; }

- (NSRect)trackRect {
    CGFloat w = 8;
    CGFloat top = 16;
    CGFloat bottom = 16;
    return NSMakeRect(NSMidX(self.bounds) - w * 0.5, top, w, MAX(24, NSHeight(self.bounds) - top - bottom));
}

- (void)drawRect:(NSRect)dirtyRect {
    NSRect bounds = self.bounds;
    NSRect track = [self trackRect];
    BOOL isBalance = [self.title.uppercaseString isEqualToString:@"BAL"];

    // Recessed channel plate (wider for silk legends)
    NSRect plate = NSInsetRect(track, -9, -4);
    SKDrawInsetBevel(plate, 3);
    [[NSColor colorWithCalibratedWhite:0.045 alpha:1] set];
    NSRectFill(NSInsetRect(plate, 1.5, 1.5));
    // Faint brushed strip inside plate
    [[NSGraphicsContext currentContext] saveGraphicsState];
    [[NSBezierPath bezierPathWithRect:NSInsetRect(plate, 2, 2)] addClip];
    SKFillBrushedMetal(NSInsetRect(plate, 2, 2), 0.02);
    [[NSColor colorWithCalibratedWhite:0.02 alpha:0.55] set];
    NSRectFill(NSInsetRect(track, -3, -1));
    [[NSGraphicsContext currentContext] restoreGraphicsState];

    // Machined metal slot with V-groove highlight
    NSRect slot = NSInsetRect(track, 1, 0);
    NSGradient *slotG = [[NSGradient alloc] initWithColorsAndLocations:
                         [NSColor colorWithCalibratedWhite:0.06 alpha:1], 0.0,
                         [NSColor colorWithCalibratedWhite:0.22 alpha:1], 0.45,
                         [NSColor colorWithCalibratedWhite:0.08 alpha:1], 1.0, nil];
    [slotG drawInRect:slot angle:0];
    [[NSColor colorWithCalibratedWhite:0.55 alpha:0.35] set];
    NSRectFill(NSMakeRect(NSMidX(slot) - 0.5, NSMinY(slot), 1.0, NSHeight(slot)));
    [[NSColor colorWithCalibratedWhite:0.0 alpha:0.45] set];
    NSRectFill(NSMakeRect(NSMinX(slot), NSMinY(slot), 1, NSHeight(slot)));
    NSRectFill(NSMakeRect(NSMaxX(slot) - 1, NSMinY(slot), 1, NSHeight(slot)));

    // Engraved scale ticks
    for (int i = 0; i <= 10; i++) {
        CGFloat t = i / 10.0;
        CGFloat y = NSMinY(track) + t * NSHeight(track);
        CGFloat tickW = (i % 5 == 0) ? 5.5 : 3.0;
        [[NSColor colorWithCalibratedWhite:0.0 alpha:0.55] set];
        NSRectFill(NSMakeRect(NSMaxX(track) + 2, y - 0.5, tickW, 1.0));
        NSRectFill(NSMakeRect(NSMinX(track) - 2 - tickW, y - 0.5, tickW, 1.0));
        [[NSColor colorWithCalibratedWhite:0.7 alpha:0.35] set];
        NSRectFill(NSMakeRect(NSMaxX(track) + 2, y - 0.9, tickW, 0.45));
        NSRectFill(NSMakeRect(NSMinX(track) - 2 - tickW, y - 0.9, tickW, 0.45));
    }

    // Silk-screen dB / L-R legends (right of track)
    NSFont *silk = [NSFont monospacedDigitSystemFontOfSize:6.5 weight:NSFontWeightBold];
    NSColor *silkC = [NSColor colorWithCalibratedWhite:0.62 alpha:1];
    NSString *topL = isBalance ? @"L" : @"+10";
    NSString *midL = isBalance ? @"C" : @"0";
    NSString *botL = isBalance ? @"R" : @"-10";
    CGFloat lx = NSMaxX(track) + 8;
    CGFloat lw = MAX(14, NSMaxX(bounds) - lx - 1);
    SKDrawGlowText(topL, NSMakeRect(lx, NSMinY(track) - 1, lw, 9), silk, silkC, NSTextAlignmentLeft);
    SKDrawGlowText(midL, NSMakeRect(lx, NSMidY(track) - 4, lw, 9), silk, silkC, NSTextAlignmentLeft);
    SKDrawGlowText(botL, NSMakeRect(lx, NSMaxY(track) - 8, lw, 9), silk, silkC, NSTextAlignmentLeft);

    // Amber center detent
    [[NSColor colorWithCalibratedRed:0.9 green:0.55 blue:0.1 alpha:0.85] set];
    NSRectFill(NSMakeRect(NSMinX(track) - 5, NSMidY(track) - 0.7, NSWidth(track) + 10, 1.4));
    [[NSColor colorWithCalibratedWhite:1 alpha:0.25] set];
    NSRectFill(NSMakeRect(NSMinX(track) - 4, NSMidY(track) - 0.9, NSWidth(track) + 8, 0.5));

    // Machined aluminum fader cap
    CGFloat travel = NSHeight(track) - 18;
    CGFloat y = NSMinY(track) + (1.0 - self.value) * travel;
    NSRect cap = NSMakeRect(NSMidX(bounds) - 12, y, 24, 18);
    [[NSColor colorWithCalibratedWhite:0 alpha:0.4] set];
    [[NSBezierPath bezierPathWithRoundedRect:NSOffsetRect(cap, 0, 1.2) xRadius:2.5 yRadius:2.5] fill];
    NSBezierPath *capPath = [NSBezierPath bezierPathWithRoundedRect:cap xRadius:2.5 yRadius:2.5];
    NSGradient *rim = [[NSGradient alloc] initWithColorsAndLocations:
                       [NSColor colorWithCalibratedWhite:0.6 alpha:1], 0.0,
                       [NSColor colorWithCalibratedWhite:0.25 alpha:1], 0.55,
                       [NSColor colorWithCalibratedWhite:0.4 alpha:1], 1.0, nil];
    [rim drawInBezierPath:capPath angle:90];
    NSRect capFace = NSInsetRect(cap, 1.2, 1.2);
    NSBezierPath *capInner = [NSBezierPath bezierPathWithRoundedRect:capFace xRadius:1.8 yRadius:1.8];
    [[NSGraphicsContext currentContext] saveGraphicsState];
    [capInner addClip];
    SKFillBrushedMetal(capFace, 0.15);
    [[NSGraphicsContext currentContext] restoreGraphicsState];
    // Grip ribs
    [[NSColor colorWithCalibratedWhite:0.05 alpha:0.45] set];
    for (int r = 0; r < 3; r++) {
        NSRectFill(NSMakeRect(NSMinX(cap) + 4, NSMinY(cap) + 5 + r * 3.2, NSWidth(cap) - 8, 1.0));
    }
    [[NSColor colorWithCalibratedWhite:0.85 alpha:0.25] set];
    NSRectFill(NSMakeRect(NSMinX(cap) + 3, NSMinY(cap) + 1, NSWidth(cap) - 6, 1));
    [[NSColor colorWithCalibratedWhite:0.05 alpha:0.6] set];
    [capPath setLineWidth:1];
    [capPath stroke];

    NSFont *font = [NSFont systemFontOfSize:8 weight:NSFontWeightBold];
    SKDrawGlowText(self.title,
                   NSMakeRect(0, NSHeight(bounds) - 14, NSWidth(bounds), 12),
                   font,
                   [NSColor colorWithCalibratedWhite:0.72 alpha:1],
                   NSTextAlignmentCenter);
}

- (void)mouseDown:(NSEvent *)event {
    _dragging = YES;
    [self updateFromEvent:event];
}

- (void)mouseDragged:(NSEvent *)event {
    if (_dragging) [self updateFromEvent:event];
}

- (void)mouseUp:(NSEvent *)event { (void)event; _dragging = NO; }

- (void)updateFromEvent:(NSEvent *)event {
    NSPoint p = [self convertPoint:event.locationInWindow fromView:nil];
    NSRect track = [self trackRect];
    CGFloat travel = NSHeight(track) - 18;
    CGFloat t = 1.0 - (p.y - NSMinY(track)) / MAX(1, travel);
    self.value = MAX(0.0, MIN(1.0, t));
    [self setNeedsDisplay:YES];
    if (self.onChange) self.onChange(self.value);
}

@end
