#import "KnobView.h"
#import "DrawingHelpers.h"

@implementation KnobView {
    BOOL _dragging;
}

- (instancetype)initWithFrame:(NSRect)frameRect {
    self = [super initWithFrame:frameRect];
    if (self) {
        _value = 0.55;
        _title = @"LEVEL";
        _accent = NO;
    }
    return self;
}

- (BOOL)isFlipped { return YES; }

- (CGFloat)captionHeight {
    return 16.0;
}

- (CGFloat)dialSize {
    NSRect bounds = self.bounds;
    return MIN(NSWidth(bounds) - 2.0, NSHeight(bounds) - [self captionHeight] - 2.0);
}

- (NSPoint)dialCenter {
    NSRect bounds = self.bounds;
    CGFloat dialAreaH = NSHeight(bounds) - [self captionHeight];
    return NSMakePoint(NSMidX(bounds), dialAreaH * 0.5);
}

- (void)drawRect:(NSRect)dirtyRect {
    NSRect bounds = self.bounds;
    const CGFloat captionH = [self captionHeight];
    CGFloat size = [self dialSize];
    if (size < 12) return;
    NSPoint c = [self dialCenter];
    CGFloat dialAreaH = NSHeight(bounds) - captionH;

    // Clip dial drawing to dial area so knurl never covers the title
    [[NSGraphicsContext currentContext] saveGraphicsState];
    [[NSBezierPath bezierPathWithRect:NSMakeRect(0, 0, NSWidth(bounds), dialAreaH)] addClip];

    // Mounting well / skirt
    CGFloat wellR = size * 0.50;
    NSRect well = NSMakeRect(c.x - wellR, c.y - wellR, wellR * 2, wellR * 2);
    NSBezierPath *wellPath = [NSBezierPath bezierPathWithOvalInRect:well];
    [[NSColor colorWithCalibratedWhite:0.02 alpha:1] set];
    [wellPath fill];
    [[NSColor colorWithCalibratedWhite:0.0 alpha:0.55] set];
    [wellPath setLineWidth:1.2];
    [wellPath stroke];

    // Soft contact shadow
    [[NSColor colorWithCalibratedWhite:0 alpha:0.45] set];
    [[NSBezierPath bezierPathWithOvalInRect:
      NSMakeRect(c.x - size * 0.47, c.y - size * 0.42 + 2.0, size * 0.94, size * 0.94)] fill];

    // Machined outer bezel
    NSRect outer = NSMakeRect(c.x - size * 0.47, c.y - size * 0.47, size * 0.94, size * 0.94);
    NSBezierPath *ring = [NSBezierPath bezierPathWithOvalInRect:outer];
    NSGradient *ringG = [[NSGradient alloc] initWithColorsAndLocations:
                         [NSColor colorWithCalibratedWhite:0.55 alpha:1], 0.0,
                         [NSColor colorWithCalibratedWhite:0.22 alpha:1], 0.35,
                         [NSColor colorWithCalibratedWhite:0.08 alpha:1], 0.7,
                         [NSColor colorWithCalibratedWhite:0.36 alpha:1], 1.0, nil];
    [ringG drawInBezierPath:ring angle:140];

    // Knurled grip
    CGFloat knurlR0 = size * 0.44;
    CGFloat knurlR1 = size * 0.47;
    for (int i = 0; i < 48; i++) {
        CGFloat a = i * (2.0 * M_PI / 48.0);
        BOOL dark = (i % 2 == 0);
        [[NSColor colorWithCalibratedWhite:dark ? 0.08 : 0.55 alpha:dark ? 0.55 : 0.28] set];
        NSBezierPath *tooth = [NSBezierPath bezierPath];
        [tooth moveToPoint:NSMakePoint(c.x + cos(a) * knurlR0, c.y + sin(a) * knurlR0)];
        [tooth lineToPoint:NSMakePoint(c.x + cos(a) * knurlR1, c.y + sin(a) * knurlR1)];
        [tooth setLineWidth:1.0];
        [tooth stroke];
    }

    // Brushed face
    NSRect face = NSInsetRect(outer, size * 0.08, size * 0.08);
    NSBezierPath *facePath = [NSBezierPath bezierPathWithOvalInRect:face];
    [[NSGraphicsContext currentContext] saveGraphicsState];
    [facePath addClip];
    SKFillBrushedMetal(face, 0.1);
    NSGradient *spec = [[NSGradient alloc] initWithColorsAndLocations:
                        [NSColor colorWithCalibratedWhite:1 alpha:0.0], 0.0,
                        [NSColor colorWithCalibratedWhite:1 alpha:0.16], 0.3,
                        [NSColor colorWithCalibratedWhite:1 alpha:0.0], 0.65, nil];
    [spec drawInRect:face angle:120];
    [[NSGraphicsContext currentContext] restoreGraphicsState];
    [[NSColor colorWithCalibratedWhite:0.05 alpha:0.55] set];
    [facePath setLineWidth:1];
    [facePath stroke];

    // Tick marks
    CGFloat startAngle = 135.0;
    CGFloat sweep = 270.0;
    for (int i = 0; i <= 10; i++) {
        CGFloat t = i / 10.0;
        CGFloat deg = startAngle + sweep * t;
        CGFloat rad = deg * M_PI / 180.0;
        CGFloat r0 = size * 0.34;
        CGFloat r1 = size * (i % 5 == 0 ? 0.40 : 0.37);
        NSBezierPath *tick = [NSBezierPath bezierPath];
        [tick moveToPoint:NSMakePoint(c.x + cos(rad) * r0, c.y + sin(rad) * r0)];
        [tick lineToPoint:NSMakePoint(c.x + cos(rad) * r1, c.y + sin(rad) * r1)];
        [[NSColor colorWithCalibratedWhite:0.65 alpha:0.7] set];
        [tick setLineWidth:i % 5 == 0 ? 1.4 : 0.9];
        [tick stroke];
    }

    // Pointer
    CGFloat deg = startAngle + sweep * self.value;
    CGFloat rad = deg * M_PI / 180.0;
    NSBezierPath *pointer = [NSBezierPath bezierPath];
    [pointer moveToPoint:c];
    [pointer lineToPoint:NSMakePoint(c.x + cos(rad) * size * 0.32, c.y + sin(rad) * size * 0.32)];
    [(self.accent ? SKRedLEDColor() : SKAmberColor()) set];
    [pointer setLineWidth:2.4];
    [pointer setLineCapStyle:NSLineCapStyleRound];
    [pointer stroke];

    // Domed center cap
    NSRect cap = NSMakeRect(c.x - size * 0.085, c.y - size * 0.085, size * 0.17, size * 0.17);
    NSBezierPath *capPath = [NSBezierPath bezierPathWithOvalInRect:cap];
    NSGradient *capG = [[NSGradient alloc] initWithColorsAndLocations:
                        [NSColor colorWithCalibratedWhite:0.42 alpha:1], 0.0,
                        [NSColor colorWithCalibratedWhite:0.12 alpha:1], 0.45,
                        [NSColor colorWithCalibratedWhite:0.05 alpha:1], 1.0, nil];
    [capG drawInBezierPath:capPath angle:125];
    [[NSColor colorWithCalibratedWhite:1 alpha:0.28] set];
    [[NSBezierPath bezierPathWithOvalInRect:NSMakeRect(c.x - size * 0.03, c.y - size * 0.045,
                                                       size * 0.045, size * 0.03)] fill];

    [[NSGraphicsContext currentContext] restoreGraphicsState];

    // Title strip — dedicated band under dial, never truncated into ellipsis if frame is wide enough
    NSFont *font = [NSFont systemFontOfSize:8 weight:NSFontWeightBold];
    NSMutableParagraphStyle *ps = [NSMutableParagraphStyle new];
    ps.alignment = NSTextAlignmentCenter;
    ps.lineBreakMode = NSLineBreakByClipping;
    NSDictionary *attrs = @{
        NSFontAttributeName: font,
        NSForegroundColorAttributeName: [NSColor colorWithCalibratedWhite:0.78 alpha:1],
        NSParagraphStyleAttributeName: ps
    };
    NSRect titleR = NSMakeRect(1, dialAreaH + 1, NSWidth(bounds) - 2, captionH - 2);
    [self.title drawInRect:titleR withAttributes:attrs];
}

- (void)mouseDown:(NSEvent *)event {
    _dragging = YES;
    [self updateValueFromEvent:event];
}

- (void)mouseDragged:(NSEvent *)event {
    if (_dragging) [self updateValueFromEvent:event];
}

- (void)mouseUp:(NSEvent *)event {
    _dragging = NO;
}

- (void)updateValueFromEvent:(NSEvent *)event {
    NSPoint p = [self convertPoint:event.locationInWindow fromView:nil];
    NSPoint c = [self dialCenter];
    CGFloat angle = atan2(p.y - c.y, p.x - c.x) * 180.0 / M_PI;
    CGFloat a = angle;
    if (a < 135) a += 360;
    CGFloat t = (a - 135.0) / 270.0;
    self.value = MAX(0.0, MIN(1.0, t));
    [self setNeedsDisplay:YES];
    if (self.onChange) self.onChange(self.value);
}

@end
