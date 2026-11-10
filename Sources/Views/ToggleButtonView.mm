#import "ToggleButtonView.h"
#import "DrawingHelpers.h"

@implementation ToggleButtonView

- (instancetype)initWithFrame:(NSRect)frameRect {
    self = [super initWithFrame:frameRect];
    if (self) {
        _title = @"MUTE";
        _on = NO;
    }
    return self;
}

- (BOOL)isFlipped { return YES; }

- (void)drawRect:(NSRect)dirtyRect {
    NSRect bounds = self.bounds;

    // Scale dial to frame — caption band fixed at bottom with clear margin
    const CGFloat captionReserve = 12.0;
    CGFloat d = MIN(18.0, MAX(14.0, NSHeight(bounds) - captionReserve - 2.0));
    CGFloat btnTop = MAX(1.0, (NSHeight(bounds) - captionReserve - d) * 0.5);
    NSRect btn = NSMakeRect(NSMidX(bounds) - d * 0.5, btnTop, d, d);

    // Soft contact shadow
    [[NSColor colorWithCalibratedWhite:0 alpha:0.45] set];
    [[NSBezierPath bezierPathWithOvalInRect:NSMakeRect(btn.origin.x, btn.origin.y + 1.2, d, d)] fill];

    // Chrome bezel ring
    NSBezierPath *outer = [NSBezierPath bezierPathWithOvalInRect:btn];
    NSGradient *bezel = [[NSGradient alloc] initWithColorsAndLocations:
                         [NSColor colorWithCalibratedWhite:0.58 alpha:1], 0.0,
                         [NSColor colorWithCalibratedWhite:0.22 alpha:1], 0.4,
                         [NSColor colorWithCalibratedWhite:0.08 alpha:1], 0.75,
                         [NSColor colorWithCalibratedWhite:0.38 alpha:1], 1.0, nil];
    [bezel drawInBezierPath:outer angle:140];

    // Cap face
    NSRect face = NSInsetRect(btn, 2.0, 2.0);
    NSBezierPath *cap = [NSBezierPath bezierPathWithOvalInRect:face];
    if (self.on) {
        NSGradient *g = [[NSGradient alloc] initWithStartingColor:[NSColor colorWithCalibratedRed:0.55 green:0.28 blue:0.06 alpha:1]
                                                      endingColor:[NSColor colorWithCalibratedRed:0.18 green:0.08 blue:0.02 alpha:1]];
        [g drawInBezierPath:cap angle:90];
    } else {
        [[NSGraphicsContext currentContext] saveGraphicsState];
        [cap addClip];
        SKFillBrushedMetal(face, 0.12);
        [[NSGraphicsContext currentContext] restoreGraphicsState];
        [[NSColor colorWithCalibratedWhite:0.05 alpha:0.5] set];
        [cap setLineWidth:0.8];
        [cap stroke];
    }

    // Specular arc
    NSBezierPath *spec = [NSBezierPath bezierPath];
    [spec appendBezierPathWithArcWithCenter:NSMakePoint(NSMidX(face), NSMidY(face) - 1)
                                     radius:d * 0.22
                                 startAngle:200
                                   endAngle:330
                                  clockwise:NO];
    [[NSColor colorWithCalibratedWhite:1 alpha:0.28] set];
    [spec setLineWidth:1.0];
    [spec stroke];

    // LED jewel
    CGFloat ledS = MAX(4.0, d * 0.28);
    NSRect led = NSMakeRect(NSMidX(btn) - ledS * 0.5, NSMinY(btn) + d * 0.22, ledS, ledS);
    [(self.on ? SKAmberColor() : SKAmberDimColor()) set];
    [[NSBezierPath bezierPathWithOvalInRect:led] fill];
    if (self.on) {
        [[SKAmberColor() colorWithAlphaComponent:0.35] set];
        [[NSBezierPath bezierPathWithOvalInRect:NSInsetRect(led, -1.2, -1.2)] fill];
    }

    // Caption — pinned above bottom margin so bank lip never clips
    NSString *line = self.title ?: @"";
    CGFloat textTop = NSMaxY(btn) + 1;
    CGFloat textBot = NSHeight(bounds) - 2;
    CGFloat textH = MAX(8, textBot - textTop);
    SKDrawGlowText(line,
                   NSMakeRect(0.5, textTop, NSWidth(bounds) - 1, textH),
                   [NSFont systemFontOfSize:6 weight:NSFontWeightBold],
                   [NSColor colorWithCalibratedWhite:0.72 alpha:1],
                   NSTextAlignmentCenter);
}

- (void)mouseDown:(NSEvent *)event {
    (void)event;
    self.on = !self.on;
    [self setNeedsDisplay:YES];
    if (self.onToggle) self.onToggle(self.on);
}

@end
