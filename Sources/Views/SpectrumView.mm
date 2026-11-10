#import "SpectrumView.h"
#import "DrawingHelpers.h"

static const NSInteger kBandCount = 32;

@implementation SpectrumView {
    float _levels[kBandCount];
    float _targets[kBandCount];
    NSTimer *_timer;
    CGFloat _phase;
}

- (instancetype)initWithFrame:(NSRect)frameRect {
    self = [super initWithFrame:frameRect];
    if (self) {
        for (NSInteger i = 0; i < kBandCount; i++) {
            _levels[i] = 0.15f;
            _targets[i] = 0.15f;
        }
        _animating = NO;
        _linkedToAudio = YES;
        _timer = [NSTimer scheduledTimerWithTimeInterval:1.0 / 30.0
                                                  target:self
                                                selector:@selector(tick)
                                                userInfo:nil
                                                 repeats:YES];
        [[NSRunLoop mainRunLoop] addTimer:_timer forMode:NSRunLoopCommonModes];
    }
    return self;
}

- (void)dealloc {
    [_timer invalidate];
}

- (BOOL)isFlipped { return YES; }

- (void)setAnimating:(BOOL)animating {
    _animating = animating;
    if (!animating) {
        for (NSInteger i = 0; i < kBandCount; i++) _targets[i] = 0.02f;
    }
}

- (void)setBandLevels:(const float *)levels count:(NSInteger)count {
    NSInteger n = MIN(count, kBandCount);
    for (NSInteger i = 0; i < n; i++) {
        _targets[i] = MAX(0.f, MIN(1.f, levels[i]));
    }
    for (NSInteger i = n; i < kBandCount; i++) _targets[i] = 0.02f;
}

- (void)setBandLevelsFromNumbers:(NSArray<NSNumber *> *)levels {
    NSInteger n = MIN((NSInteger)levels.count, kBandCount);
    for (NSInteger i = 0; i < n; i++) {
        _targets[i] = MAX(0.f, MIN(1.f, levels[i].floatValue));
    }
    for (NSInteger i = n; i < kBandCount; i++) _targets[i] = 0.02f;
}

- (void)tick {
    if (!self.linkedToAudio && self.animating) {
        _phase += 0.18;
        for (NSInteger i = 0; i < kBandCount; i++) {
            float wave = 0.35f + 0.35f * sinf(_phase * 0.7f + i * 0.35f);
            float pulse = 0.25f + 0.4f * fabsf(sinf(_phase * 1.3f + i * 0.55f));
            float bass = (i < 4) ? 0.25f : 0.f;
            _targets[i] = MIN(1.f, wave * pulse + bass + (arc4random_uniform(20) / 100.f));
        }
    } else if (self.linkedToAudio && !self.animating) {
        for (NSInteger i = 0; i < kBandCount; i++) {
            _targets[i] *= 0.9f;
        }
    }
    for (NSInteger i = 0; i < kBandCount; i++) {
        _levels[i] += (_targets[i] - _levels[i]) * 0.35f;
    }
    [self setNeedsDisplay:YES];
}

- (void)drawRect:(NSRect)dirtyRect {
    NSRect bounds = self.bounds;
    // Chrome instrument bezel around the analyzer glass
    NSBezierPath *outer = [NSBezierPath bezierPathWithRoundedRect:bounds xRadius:3 yRadius:3];
    NSGradient *bezel = [[NSGradient alloc] initWithColorsAndLocations:
                         [NSColor colorWithCalibratedWhite:0.48 alpha:1], 0.0,
                         [NSColor colorWithCalibratedWhite:0.18 alpha:1], 0.4,
                         [NSColor colorWithCalibratedWhite:0.08 alpha:1], 0.75,
                         [NSColor colorWithCalibratedWhite:0.32 alpha:1], 1.0, nil];
    [bezel drawInBezierPath:outer angle:125];
    SKDrawInsetBevel(NSInsetRect(bounds, 2, 2), 2.5);

    NSRect area = NSInsetRect(bounds, 6, 6);
    NSGradient *glass = [[NSGradient alloc] initWithColorsAndLocations:
                         [NSColor colorWithCalibratedRed:0.04 green:0.025 blue:0.01 alpha:1], 0.0,
                         [NSColor colorWithCalibratedRed:0.07 green:0.04 blue:0.015 alpha:1], 0.5,
                         [NSColor colorWithCalibratedRed:0.03 green:0.02 blue:0.008 alpha:1], 1.0, nil];
    [glass drawInRect:area angle:90];
    // Soft glass reflection
    [[NSColor colorWithCalibratedWhite:1 alpha:0.04] set];
    NSRectFill(NSMakeRect(NSMinX(area), NSMinY(area), NSWidth(area), NSHeight(area) * 0.18));

    // Grid
    [[NSColor colorWithCalibratedRed:0.35 green:0.18 blue:0.04 alpha:0.35] set];
    for (int i = 1; i < 8; i++) {
        CGFloat y = NSMinY(area) + NSHeight(area) * i / 8.0;
        NSRectFill(NSMakeRect(NSMinX(area), y, NSWidth(area), 0.5));
    }

    CGFloat gap = 2.0;
    CGFloat barW = (NSWidth(area) - gap * (kBandCount + 1)) / kBandCount;
    for (NSInteger i = 0; i < kBandCount; i++) {
        CGFloat h = NSHeight(area) * _levels[i];
        NSRect bar = NSMakeRect(NSMinX(area) + gap + i * (barW + gap),
                                NSMaxY(area) - h,
                                barW,
                                h);
        // Segmented LED look
        CGFloat segH = 3.0;
        CGFloat segGap = 1.0;
        for (CGFloat y = NSMinY(bar); y < NSMaxY(bar); y += segH + segGap) {
            CGFloat ratio = (y - NSMinY(area)) / NSHeight(area);
            NSColor *c;
            if (ratio > 0.78) c = SKRedLEDColor();
            else if (ratio > 0.55) c = [NSColor colorWithCalibratedRed:1 green:0.75 blue:0.1 alpha:1];
            else c = SKAmberColor();
            [c set];
            CGFloat hh = MIN(segH, NSMaxY(bar) - y);
            NSRectFill(NSMakeRect(NSMinX(bar), y, NSWidth(bar), hh));
        }
    }
}

@end
