#import "MetalKeyView.h"
#import "DrawingHelpers.h"

@implementation MetalKeyView {
    BOOL _pressed;
}

- (instancetype)initWithFrame:(NSRect)frameRect {
    self = [super initWithFrame:frameRect];
    if (self) {
        _title = @"KEY";
        _showLED = YES;
        _ledRed = YES;
    }
    return self;
}

- (BOOL)isFlipped { return YES; }

- (void)setSelected:(BOOL)selected {
    _selected = selected;
    _ledOn = selected;
    [self setNeedsDisplay:YES];
}

- (NSRect)keyFaceRect {
    CGFloat ledSpace = self.showLED ? 10 : 2;
    return NSMakeRect(1, ledSpace, NSWidth(self.bounds) - 2, NSHeight(self.bounds) - ledSpace - 1);
}

- (void)drawRect:(NSRect)dirtyRect {
    NSRect face = [self keyFaceRect];

    // Jewel LED above key (lens refraction)
    if (self.showLED) {
        NSRect led = NSMakeRect(NSMidX(self.bounds) - 4, 0.5, 8, 8);
        NSColor *on = self.ledRed ? SKRedLEDColor() : SKAmberColor();
        SKDrawJewelLED(led, on, self.ledOn);
    }

    // Outer shadow
    [[NSColor colorWithCalibratedWhite:0 alpha:0.5] set];
    [[NSBezierPath bezierPathWithRoundedRect:NSOffsetRect(face, 0, 1.4) xRadius:3 yRadius:3] fill];

    NSBezierPath *body = [NSBezierPath bezierPathWithRoundedRect:face xRadius:3 yRadius:3];
    BOOL down = _pressed || self.selected;
    if (down) {
        NSGradient *g = [[NSGradient alloc] initWithStartingColor:[NSColor colorWithCalibratedRed:0.28 green:0.14 blue:0.04 alpha:1]
                                                      endingColor:[NSColor colorWithCalibratedRed:0.12 green:0.06 blue:0.02 alpha:1]];
        [g drawInBezierPath:body angle:90];
    } else {
        // Chrome rim + brushed aluminum face
        NSGradient *rim = [[NSGradient alloc] initWithColorsAndLocations:
                           [NSColor colorWithCalibratedWhite:0.55 alpha:1], 0.0,
                           [NSColor colorWithCalibratedWhite:0.22 alpha:1], 0.45,
                           [NSColor colorWithCalibratedWhite:0.12 alpha:1], 0.8,
                           [NSColor colorWithCalibratedWhite:0.34 alpha:1], 1.0, nil];
        [rim drawInBezierPath:body angle:125];
        NSRect inner = NSInsetRect(face, 1.2, 1.2);
        NSBezierPath *facePath = [NSBezierPath bezierPathWithRoundedRect:inner xRadius:2 yRadius:2];
        [[NSGraphicsContext currentContext] saveGraphicsState];
        [facePath addClip];
        SKFillBrushedMetal(inner, 0.12);
        [[NSColor colorWithCalibratedWhite:1 alpha:0.18] set];
        NSRectFill(NSMakeRect(NSMinX(inner) + 2, NSMinY(inner) + 0.6, NSWidth(inner) - 4, 1));
        [[NSGraphicsContext currentContext] restoreGraphicsState];
    }

    if (!down) {
        [[NSColor colorWithCalibratedWhite:0.85 alpha:0.28] set];
        NSRectFill(NSMakeRect(NSMinX(face) + 3, NSMinY(face) + 1, NSWidth(face) - 6, 1));
        // Bottom return lip
        [[NSColor colorWithCalibratedWhite:0.0 alpha:0.35] set];
        NSRectFill(NSMakeRect(NSMinX(face) + 3, NSMaxY(face) - 1.4, NSWidth(face) - 6, 1));
    } else {
        // Recessed when pressed
        [[NSColor colorWithCalibratedWhite:0 alpha:0.35] set];
        NSRectFill(NSMakeRect(NSMinX(face) + 2, NSMinY(face) + 1, NSWidth(face) - 4, 1.2));
    }

    [[NSColor colorWithCalibratedWhite:0.05 alpha:0.75] set];
    [body setLineWidth:1];
    [body stroke];

    // Engraved legend plate inset
    NSRect legend = NSInsetRect(face, 3.5, MAX(3.0, NSHeight(face) * 0.22));
    if (!down && NSHeight(legend) > 8) {
        [[NSColor colorWithCalibratedWhite:0 alpha:0.22] set];
        [[NSBezierPath bezierPathWithRoundedRect:legend xRadius:1.5 yRadius:1.5] fill];
    }
    NSColor *tc = (self.selected || _pressed) ? SKAmberColor() : [NSColor colorWithCalibratedWhite:0.84 alpha:1];
    SKDrawGlowText(self.title ?: @"",
                   NSInsetRect(face, 2, (NSHeight(face) - 12) * 0.5),
                   [NSFont systemFontOfSize:MAX(8, MIN(10, NSWidth(face) * 0.18)) weight:NSFontWeightBold],
                   tc,
                   NSTextAlignmentCenter);
}

- (void)mouseDown:(NSEvent *)event {
    (void)event;
    _pressed = YES;
    [self setNeedsDisplay:YES];
}

- (void)mouseUp:(NSEvent *)event {
    _pressed = NO;
    NSPoint p = [self convertPoint:event.locationInWindow fromView:nil];
    [self setNeedsDisplay:YES];
    if (NSPointInRect(p, self.bounds) && self.onClick) self.onClick();
}

@end
