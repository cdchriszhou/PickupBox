#import "CassetteView.h"
#import "DrawingHelpers.h"

typedef NS_ENUM(NSInteger, CassetteAnimKind) {
    CassetteAnimNone = 0,
    CassetteAnimInsert = 1,
    CassetteAnimTrackChange = 2,
};

@implementation CassetteView {
    NSTimer *_timer;
    CGFloat _reelAngle;
    NSInteger _activeTransport; // 1 prev … 6 eject
    CassetteAnimKind _animKind;
    CGFloat _animT;       // 0..1
    CGFloat _platterSpin; // continuous vinyl rotation
    CGFloat _tonearmBase; // resting angle offset for visual variety
}

- (instancetype)initWithFrame:(NSRect)frameRect {
    self = [super initWithFrame:frameRect];
    if (self) {
        _playing = NO;
        _tapeProgress = 0.35f;
        _tapeTitle = @"拾音盒子  ·  TYPE II";
        _playMode = AudioPlayModeSequential;
        _deckStyle = CassetteDeckStyleTape;
        _activeTransport = 4;
        _animKind = CassetteAnimNone;
        _animT = 0;
        _platterSpin = 0;
        _tonearmBase = 0;
        _timer = [NSTimer scheduledTimerWithTimeInterval:1.0 / 30.0
                                                  target:self
                                                selector:@selector(tick)
                                                userInfo:nil
                                                 repeats:YES];
        [[NSRunLoop mainRunLoop] addTimer:_timer forMode:NSRunLoopCommonModes];
    }
    return self;
}

- (void)dealloc { [_timer invalidate]; }
- (BOOL)isFlipped { return YES; }

- (void)setPlaying:(BOOL)playing {
    _playing = playing;
    if (playing) {
        _activeTransport = 2; // PLAY
    }
    [self setNeedsDisplay:YES];
}

- (void)resetTransportToStop {
    _playing = NO;
    _activeTransport = 4; // STOP
    [self setNeedsDisplay:YES];
}

- (void)setTapeProgress:(float)tapeProgress {
    _tapeProgress = MAX(0.f, MIN(1.f, tapeProgress));
    [self setNeedsDisplay:YES];
}

- (void)setTapeTitle:(NSString *)tapeTitle {
    _tapeTitle = [tapeTitle copy];
    [self setNeedsDisplay:YES];
}

- (void)setPlayMode:(AudioPlayMode)playMode {
    _playMode = playMode;
    [self setNeedsDisplay:YES];
}

- (void)setDeckStyle:(CassetteDeckStyle)deckStyle {
    if (_deckStyle == deckStyle) return;
    _deckStyle = deckStyle;
    _tonearmBase = (deckStyle == CassetteDeckStylePhono) ? 12.0 : 0;
    [self setNeedsDisplay:YES];
    if (self.onDeckStyleChanged) self.onDeckStyleChanged(deckStyle);
}

- (void)playMediaInsertAnimation {
    _animKind = CassetteAnimInsert;
    _animT = 0;
    [self setNeedsDisplay:YES];
}

- (void)playTrackChangeAnimation {
    _animKind = CassetteAnimTrackChange;
    _animT = 0;
    [self setNeedsDisplay:YES];
}

- (void)tick {
    BOOL dirty = NO;
    if (self.playing) {
        _reelAngle += 8.0 + self.tapeProgress * 4.0;
        _platterSpin += (self.deckStyle == CassetteDeckStylePhono) ? 3.6 : 0;
        dirty = YES;
    }
    if (_animKind != CassetteAnimNone) {
        CGFloat speed = (_animKind == CassetteAnimInsert) ? 0.028 : 0.045;
        _animT += speed;
        if (_animT >= 1.0) {
            _animT = 1.0;
            _animKind = CassetteAnimNone;
        }
        dirty = YES;
    }
    if (dirty) [self setNeedsDisplay:YES];
}

#pragma mark - Frames

- (NSArray<NSValue *> *)styleFrames {
    CGFloat w = 48, h = 16, gap = 3;
    CGFloat x = 12, y = 6;
    return @[
        [NSValue valueWithRect:NSMakeRect(x, y, w, h)],
        [NSValue valueWithRect:NSMakeRect(x + w + gap, y, w, h)],
    ];
}

- (NSArray<NSValue *> *)modeFrames {
    CGFloat w = 52, h = 18, gap = 4;
    CGFloat total = 3 * w + 2 * gap;
    CGFloat x = NSWidth(self.bounds) - total - 12;
    CGFloat y = 6;
    return @[
        [NSValue valueWithRect:NSMakeRect(x, y, w, h)],
        [NSValue valueWithRect:NSMakeRect(x + w + gap, y, w, h)],
        [NSValue valueWithRect:NSMakeRect(x + 2 * (w + gap), y, w, h)],
    ];
}

- (NSArray<NSValue *> *)transportFrames {
    CGFloat h = 32;
    CGFloat y = NSHeight(self.bounds) - h - 8;
    CGFloat gap = 4;
    CGFloat totalGap = gap * 5;
    CGFloat w = (NSWidth(self.bounds) - 20 - totalGap) / 6.0;
    w = MIN(w, 54);
    CGFloat total = 6 * w + totalGap;
    CGFloat x = (NSWidth(self.bounds) - total) * 0.5;
    NSMutableArray *arr = [NSMutableArray array];
    for (int i = 0; i < 6; i++) {
        [arr addObject:[NSValue valueWithRect:NSMakeRect(x + i * (w + gap), y, w, h)]];
    }
    return arr;
}

- (NSRect)doorFrame {
    NSArray *frames = [self transportFrames];
    CGFloat transportTop = frames.count ? NSMinY([frames[0] rectValue]) : NSHeight(self.bounds) - 40;
    return NSMakeRect(14, 28, NSWidth(self.bounds) - 28, transportTop - 34);
}

#pragma mark - Animation helpers

/// Ease in-out
static CGFloat SKEase(CGFloat t) {
    t = MAX(0, MIN(1, t));
    return t * t * (3.0 - 2.0 * t);
}

- (CGFloat)insertPhase {
    if (_animKind != CassetteAnimInsert) return 1.0;
    return SKEase(_animT);
}

- (CGFloat)trackChangePhase {
    if (_animKind != CassetteAnimTrackChange) return 0.0;
    return _animT;
}

/// Tonearm lift amount 0..1 during track change (up then down)
- (CGFloat)tonearmLiftAmount {
    CGFloat t = [self trackChangePhase];
    if (t <= 0) return 0;
    if (t < 0.35) return SKEase(t / 0.35);           // lift
    if (t < 0.55) return 1.0;                          // hold
    return 1.0 - SKEase((t - 0.55) / 0.45);            // lower
}

#pragma mark - Shared hardware

- (void)drawSprocketHubAt:(NSPoint)c radius:(CGFloat)r angle:(CGFloat)angle {
    NSRect outer = NSMakeRect(c.x - r, c.y - r, r * 2, r * 2);
    NSBezierPath *hub = [NSBezierPath bezierPathWithOvalInRect:outer];
    NSGradient *hg = [[NSGradient alloc] initWithColorsAndLocations:
                      [NSColor colorWithCalibratedWhite:0.42 alpha:1], 0.0,
                      [NSColor colorWithCalibratedWhite:0.14 alpha:1], 0.4,
                      [NSColor colorWithCalibratedWhite:0.08 alpha:1], 0.75,
                      [NSColor colorWithCalibratedWhite:0.28 alpha:1], 1.0, nil];
    [hg drawInBezierPath:hub angle:135];
    [[NSColor colorWithCalibratedWhite:0.05 alpha:0.5] set];
    [hub setLineWidth:0.8];
    [hub stroke];

    for (int i = 0; i < 6; i++) {
        CGFloat a = (angle + i * 60.0) * M_PI / 180.0;
        NSPoint p1 = NSMakePoint(c.x + cos(a) * r * 0.28, c.y + sin(a) * r * 0.28);
        NSPoint p2 = NSMakePoint(c.x + cos(a) * r * 0.82, c.y + sin(a) * r * 0.82);
        NSBezierPath *tooth = [NSBezierPath bezierPath];
        [tooth moveToPoint:p1];
        [tooth lineToPoint:p2];
        [[NSColor colorWithCalibratedWhite:0.0 alpha:0.45] set];
        [tooth setLineWidth:2.6];
        [tooth stroke];
        [[NSColor colorWithCalibratedWhite:0.75 alpha:0.85] set];
        [tooth setLineWidth:1.6];
        [tooth stroke];
    }
    [[NSColor colorWithCalibratedWhite:0.06 alpha:1] set];
    [[NSBezierPath bezierPathWithOvalInRect:NSMakeRect(c.x - r * 0.22, c.y - r * 0.22, r * 0.44, r * 0.44)] fill];
    NSGradient *pin = [[NSGradient alloc] initWithStartingColor:[NSColor colorWithCalibratedWhite:0.55 alpha:1]
                                                    endingColor:[NSColor colorWithCalibratedWhite:0.18 alpha:1]];
    [pin drawInBezierPath:[NSBezierPath bezierPathWithOvalInRect:NSMakeRect(c.x - 2.4, c.y - 2.4, 4.8, 4.8)] angle:125];
}

- (void)drawTapePackAt:(NSPoint)c hubR:(CGFloat)hubR packR:(CGFloat)packR {
    if (packR <= hubR + 1) return;
    NSRect tape = NSMakeRect(c.x - packR, c.y - packR, packR * 2, packR * 2);
    NSBezierPath *path = [NSBezierPath bezierPathWithOvalInRect:tape];
    NSGradient *tg = [[NSGradient alloc] initWithColorsAndLocations:
                      [NSColor colorWithCalibratedRed:0.36 green:0.20 blue:0.08 alpha:1], 0.0,
                      [NSColor colorWithCalibratedRed:0.22 green:0.11 blue:0.04 alpha:1], 0.35,
                      [NSColor colorWithCalibratedRed:0.12 green:0.06 blue:0.025 alpha:1], 0.7,
                      [NSColor colorWithCalibratedRed:0.07 green:0.035 blue:0.015 alpha:1], 1.0, nil];
    [tg drawInBezierPath:path angle:110];

    [[NSGraphicsContext currentContext] saveGraphicsState];
    [path addClip];
    NSInteger layers = MAX(6, (NSInteger)((packR - hubR) / 1.6));
    for (NSInteger i = 1; i <= layers; i++) {
        CGFloat t = (CGFloat)i / (CGFloat)(layers + 1);
        CGFloat rr = hubR + (packR - hubR) * t;
        NSBezierPath *ring = [NSBezierPath bezierPathWithOvalInRect:
                              NSMakeRect(c.x - rr, c.y - rr, rr * 2, rr * 2)];
        BOOL dark = (i % 2 == 0);
        [[NSColor colorWithCalibratedRed:dark ? 0.08 : 0.28
                                   green:dark ? 0.04 : 0.14
                                    blue:dark ? 0.015 : 0.05
                                   alpha:dark ? 0.55 : 0.22] set];
        [ring setLineWidth:MAX(0.7, (packR - hubR) / layers)];
        [ring stroke];
    }
    for (int i = 0; i < 24; i++) {
        CGFloat a = i * (M_PI * 2.0 / 24.0) + 0.15;
        NSBezierPath *grain = [NSBezierPath bezierPath];
        [grain moveToPoint:NSMakePoint(c.x + cos(a) * (hubR + 1.5), c.y + sin(a) * (hubR + 1.5))];
        [grain lineToPoint:NSMakePoint(c.x + cos(a) * (packR - 0.8), c.y + sin(a) * (packR - 0.8))];
        [[NSColor colorWithCalibratedWhite:0.55 alpha:0.04 + (i % 3) * 0.015] set];
        [grain setLineWidth:0.6];
        [grain stroke];
    }
    NSGradient *sheen = [[NSGradient alloc] initWithColorsAndLocations:
                         [NSColor colorWithCalibratedWhite:1 alpha:0.0], 0.0,
                         [NSColor colorWithCalibratedWhite:1 alpha:0.08], 0.35,
                         [NSColor colorWithCalibratedWhite:1 alpha:0.0], 0.7, nil];
    [sheen drawInRect:tape angle:125];
    [[NSGraphicsContext currentContext] restoreGraphicsState];

    [[NSColor colorWithCalibratedRed:0.45 green:0.28 blue:0.12 alpha:0.45] set];
    [path setLineWidth:1.0];
    [path stroke];
}

- (void)drawDoorHardwareAround:(NSRect)door {
    CGFloat hingeW = 7;
    for (int side = 0; side < 2; side++) {
        CGFloat x = side == 0 ? NSMinX(door) - 1 : NSMaxX(door) - hingeW + 1;
        for (int i = 0; i < 3; i++) {
            CGFloat y = NSMinY(door) + 10 + i * ((NSHeight(door) - 28) / 2.0);
            NSRect barrel = NSMakeRect(x, y, hingeW, 12);
            NSBezierPath *bp = [NSBezierPath bezierPathWithRoundedRect:barrel xRadius:2 yRadius:2];
            NSGradient *hg = [[NSGradient alloc] initWithColorsAndLocations:
                              [NSColor colorWithCalibratedWhite:0.48 alpha:1], 0.0,
                              [NSColor colorWithCalibratedWhite:0.18 alpha:1], 0.5,
                              [NSColor colorWithCalibratedWhite:0.32 alpha:1], 1.0, nil];
            [hg drawInBezierPath:bp angle:0];
            [[NSColor colorWithCalibratedWhite:0.05 alpha:0.55] set];
            [bp setLineWidth:0.7];
            [bp stroke];
            [[NSColor colorWithCalibratedWhite:0.75 alpha:0.35] set];
            NSRectFill(NSMakeRect(NSMidX(barrel) - 0.5, NSMinY(barrel) + 2, 1, NSHeight(barrel) - 4));
        }
    }
    NSRect latch = NSMakeRect(NSMidX(door) - 18, NSMinY(door) - 3, 36, 7);
    NSBezierPath *lp = [NSBezierPath bezierPathWithRoundedRect:latch xRadius:2 yRadius:2];
    NSGradient *lg = [[NSGradient alloc] initWithColorsAndLocations:
                      [NSColor colorWithCalibratedWhite:0.42 alpha:1], 0.0,
                      [NSColor colorWithCalibratedWhite:0.16 alpha:1], 0.55,
                      [NSColor colorWithCalibratedWhite:0.28 alpha:1], 1.0, nil];
    [lg drawInBezierPath:lp angle:90];
    SKDrawScrew(NSMakePoint(NSMinX(latch) + 5, NSMidY(latch)), 1.4);
    SKDrawScrew(NSMakePoint(NSMaxX(latch) - 5, NSMidY(latch)), 1.4);
}

#pragma mark - Cassette door content

- (void)drawRealisticCassetteInRect:(NSRect)door {
    [[NSColor colorWithCalibratedWhite:0.02 alpha:1] set];
    NSRectFill(NSInsetRect(door, 1, 1));
    [[NSColor colorWithCalibratedWhite:0.35 alpha:0.25] set];
    NSFrameRect(NSInsetRect(door, 1.5, 1.5));

    NSRect glass = NSInsetRect(door, 5, 5);
    NSGradient *glassG = [[NSGradient alloc] initWithColorsAndLocations:
                          [NSColor colorWithCalibratedWhite:0.11 alpha:1], 0.0,
                          [NSColor colorWithCalibratedWhite:0.04 alpha:1], 0.55,
                          [NSColor colorWithCalibratedWhite:0.02 alpha:1], 1.0, nil];
    [glassG drawInRect:glass angle:90];
    [[NSColor colorWithCalibratedWhite:1 alpha:0.06] set];
    NSRectFill(NSMakeRect(NSMinX(glass), NSMinY(glass), NSWidth(glass), NSHeight(glass) * 0.14));
    [[NSColor colorWithCalibratedWhite:0.45 alpha:0.18] set];
    NSRectFill(NSMakeRect(NSMinX(glass), NSMinY(glass), NSWidth(glass), 1));

    CGFloat insert = [self insertPhase];
    CGFloat change = [self trackChangePhase];
    // Insert: slide up from below; track-change: brief dip then seat
    CGFloat yOff = 0;
    CGFloat alpha = 1.0;
    if (_animKind == CassetteAnimInsert) {
        yOff = (1.0 - insert) * (NSHeight(glass) * 0.95);
        alpha = 0.25 + insert * 0.75;
    } else if (_animKind == CassetteAnimTrackChange) {
        if (change < 0.4) yOff = SKEase(change / 0.4) * 10.0;
        else yOff = (1.0 - SKEase((change - 0.4) / 0.6)) * 10.0;
    }

    CGFloat maxW = NSWidth(glass) - 6;
    CGFloat maxH = NSHeight(glass) - 4;
    const CGFloat aspect = 100.3 / 63.8;
    CGFloat shellW = maxW;
    CGFloat shellH = shellW / aspect;
    if (shellH > maxH) {
        shellH = maxH;
        shellW = shellH * aspect;
    }
    NSRect shell = NSMakeRect(NSMidX(glass) - shellW * 0.5,
                              NSMidY(glass) - shellH * 0.5 + yOff,
                              shellW, shellH);

    [[NSGraphicsContext currentContext] saveGraphicsState];
    [NSBezierPath clipRect:glass];
    [[NSColor colorWithCalibratedWhite:1 alpha:alpha] set]; // modulate via layer below

    [[NSColor colorWithCalibratedWhite:0 alpha:0.4 * alpha] set];
    [[NSBezierPath bezierPathWithRoundedRect:NSOffsetRect(shell, 0, 1.5) xRadius:6 yRadius:6] fill];

    NSBezierPath *body = [NSBezierPath bezierPathWithRoundedRect:shell xRadius:6 yRadius:6];
    NSGradient *bodyG = [[NSGradient alloc] initWithColorsAndLocations:
                         [NSColor colorWithCalibratedWhite:0.22 alpha:alpha], 0.0,
                         [NSColor colorWithCalibratedWhite:0.12 alpha:alpha], 0.35,
                         [NSColor colorWithCalibratedWhite:0.07 alpha:alpha], 0.75,
                         [NSColor colorWithCalibratedWhite:0.10 alpha:alpha], 1.0, nil];
    [bodyG drawInBezierPath:body angle:90];
    [[NSColor colorWithCalibratedWhite:0.55 alpha:0.35 * alpha] set];
    NSRectFill(NSMakeRect(NSMinX(shell) + 8, NSMinY(shell) + 1.5, NSWidth(shell) - 16, 1));
    [[NSColor colorWithCalibratedWhite:0.0 alpha:0.55 * alpha] set];
    [body setLineWidth:1.2];
    [body stroke];

    CGFloat inset = 8;
    SKDrawScrew(NSMakePoint(NSMinX(shell) + inset, NSMinY(shell) + inset), 2.4);
    SKDrawScrew(NSMakePoint(NSMaxX(shell) - inset, NSMinY(shell) + inset), 2.4);
    SKDrawScrew(NSMakePoint(NSMinX(shell) + inset, NSMaxY(shell) - inset), 2.4);
    SKDrawScrew(NSMakePoint(NSMaxX(shell) - inset, NSMaxY(shell) - inset), 2.4);

    NSRect label = NSMakeRect(NSMinX(shell) + 14, NSMinY(shell) + 8, NSWidth(shell) - 28, NSHeight(shell) * 0.28);
    NSBezierPath *labelPath = [NSBezierPath bezierPathWithRoundedRect:label xRadius:2 yRadius:2];
    NSGradient *lg = [[NSGradient alloc] initWithColorsAndLocations:
                      [NSColor colorWithCalibratedRed:0.93 green:0.90 blue:0.78 alpha:alpha], 0.0,
                      [NSColor colorWithCalibratedRed:0.85 green:0.80 blue:0.62 alpha:alpha], 1.0, nil];
    [lg drawInBezierPath:labelPath angle:90];
    [[NSColor colorWithCalibratedRed:0.55 green:0.45 blue:0.25 alpha:0.35 * alpha] set];
    for (int i = 1; i <= 3; i++) {
        CGFloat y = NSMinY(label) + NSHeight(label) * (i / 4.0);
        NSRectFill(NSMakeRect(NSMinX(label) + 6, y, NSWidth(label) - 12, 0.6));
    }
    NSString *title = self.tapeTitle.length ? self.tapeTitle : @"BLANK TAPE";
    if (title.length > 28) title = [[title substringToIndex:27] stringByAppendingString:@"…"];
    NSMutableParagraphStyle *ps = [NSMutableParagraphStyle new];
    ps.alignment = NSTextAlignmentCenter;
    [title drawInRect:NSMakeRect(NSMinX(label), NSMinY(label) + 4, NSWidth(label), 14)
       withAttributes:@{NSFontAttributeName: [NSFont systemFontOfSize:10 weight:NSFontWeightBold],
                        NSForegroundColorAttributeName: [NSColor colorWithCalibratedWhite:0.12 alpha:alpha],
                        NSParagraphStyleAttributeName: ps}];
    NSString *side = self.playing ? @"SIDE A  ·  ▶ PLAY" : @"SIDE A  ·  STOP";
    [side drawInRect:NSMakeRect(NSMinX(label), NSMaxY(label) - 14, NSWidth(label), 12)
      withAttributes:@{NSFontAttributeName: [NSFont systemFontOfSize:8 weight:NSFontWeightMedium],
                       NSForegroundColorAttributeName: [NSColor colorWithCalibratedRed:0.45 green:0.2 blue:0.05 alpha:alpha],
                       NSParagraphStyleAttributeName: ps}];

    NSRect viewWin = NSMakeRect(NSMinX(shell) + 18,
                                NSMinY(shell) + NSHeight(shell) * 0.38,
                                NSWidth(shell) - 36,
                                NSHeight(shell) * 0.42);
    SKDrawInsetBevel(viewWin, 2);
    [[NSColor colorWithCalibratedWhite:0.02 alpha:alpha] set];
    NSRectFill(NSInsetRect(viewWin, 1.5, 1.5));

    CGFloat hubR = MIN(16, NSHeight(viewWin) * 0.28);
    CGFloat maxPack = MIN(NSHeight(viewWin) * 0.42, NSWidth(viewWin) * 0.18);
    CGFloat progress = self.tapeProgress;
    CGFloat leftPack = hubR + 2 + (1.0 - progress) * (maxPack - hubR);
    CGFloat rightPack = hubR + 2 + progress * (maxPack - hubR);
    NSPoint leftC = NSMakePoint(NSMinX(viewWin) + NSWidth(viewWin) * 0.28, NSMidY(viewWin));
    NSPoint rightC = NSMakePoint(NSMinX(viewWin) + NSWidth(viewWin) * 0.72, NSMidY(viewWin));

    CGFloat reelBoost = (_animKind == CassetteAnimTrackChange) ? _reelAngle + change * 120 : _reelAngle;
    [self drawTapePackAt:leftC hubR:hubR packR:leftPack];
    [self drawTapePackAt:rightC hubR:hubR packR:rightPack];
    [self drawSprocketHubAt:leftC radius:hubR angle:reelBoost];
    [self drawSprocketHubAt:rightC radius:hubR angle:-reelBoost * 1.15];

    CGFloat tapeY = NSMaxY(viewWin) - 6;
    NSBezierPath *tapePath = [NSBezierPath bezierPath];
    [tapePath moveToPoint:NSMakePoint(leftC.x + leftPack * 0.55, tapeY)];
    [tapePath lineToPoint:NSMakePoint(rightC.x - rightPack * 0.55, tapeY)];
    [[NSColor colorWithCalibratedWhite:0 alpha:0.35 * alpha] set];
    NSBezierPath *tapeShadow = [tapePath copy];
    [tapeShadow setLineWidth:3.4];
    [tapeShadow stroke];
    NSGradient *ribbon = [[NSGradient alloc] initWithColorsAndLocations:
                          [NSColor colorWithCalibratedRed:0.42 green:0.24 blue:0.09 alpha:alpha], 0.0,
                          [NSColor colorWithCalibratedRed:0.22 green:0.11 blue:0.04 alpha:alpha], 0.45,
                          [NSColor colorWithCalibratedRed:0.38 green:0.20 blue:0.07 alpha:alpha], 1.0, nil];
    [ribbon drawInRect:NSMakeRect(leftC.x + leftPack * 0.55, tapeY - 1.2,
                                  (rightC.x - rightPack * 0.55) - (leftC.x + leftPack * 0.55), 2.4)
                 angle:0];

    NSRect pad = NSMakeRect(NSMidX(viewWin) - 10, tapeY - 5, 20, 8);
    NSBezierPath *padP = [NSBezierPath bezierPathWithRoundedRect:pad xRadius:1.5 yRadius:1.5];
    NSGradient *padG = [[NSGradient alloc] initWithColorsAndLocations:
                        [NSColor colorWithCalibratedWhite:0.55 alpha:alpha], 0.0,
                        [NSColor colorWithCalibratedWhite:0.28 alpha:alpha], 1.0, nil];
    [padG drawInBezierPath:padP angle:90];

    CGFloat holeY = NSMaxY(shell) - 11;
    [[NSColor colorWithCalibratedWhite:0.02 alpha:alpha] set];
    for (int i = 0; i < 5; i++) {
        CGFloat hx = NSMinX(shell) + 22 + i * ((NSWidth(shell) - 44) / 4.0);
        [[NSBezierPath bezierPathWithOvalInRect:NSMakeRect(hx - 3, holeY, 6, 6)] fill];
    }
    [[NSColor colorWithCalibratedWhite:0.25 alpha:alpha] set];
    NSRectFill(NSMakeRect(NSMinX(shell) + 4, NSMaxY(shell) - 16, 7, 10));
    NSRectFill(NSMakeRect(NSMaxX(shell) - 11, NSMaxY(shell) - 16, 7, 10));

    [[NSGraphicsContext currentContext] restoreGraphicsState];

    // Door ajar during insert
    if (_animKind == CassetteAnimInsert && insert < 0.85) {
        [[NSColor colorWithCalibratedWhite:0.0 alpha:0.35 * (1.0 - insert)] set];
        NSRectFill(NSMakeRect(NSMinX(door), NSMinY(door), NSWidth(door), 4));
    }
}

#pragma mark - Phonograph door content

- (void)drawVinylAt:(NSPoint)c radius:(CGFloat)R spin:(CGFloat)spin alpha:(CGFloat)alpha {
    NSRect disc = NSMakeRect(c.x - R, c.y - R, R * 2, R * 2);
    NSBezierPath *outer = [NSBezierPath bezierPathWithOvalInRect:disc];
    // Soft floor contact shadow
    [[NSColor colorWithCalibratedWhite:0 alpha:0.5 * alpha] set];
    [[NSBezierPath bezierPathWithOvalInRect:NSOffsetRect(disc, 2.0, 3.0)] fill];

    NSGradient *vinylG = [[NSGradient alloc] initWithColorsAndLocations:
                          [NSColor colorWithCalibratedWhite:0.14 alpha:alpha], 0.0,
                          [NSColor colorWithCalibratedWhite:0.03 alpha:alpha], 0.4,
                          [NSColor colorWithCalibratedWhite:0.07 alpha:alpha], 0.75,
                          [NSColor colorWithCalibratedWhite:0.11 alpha:alpha], 1.0, nil];
    [vinylG drawInBezierPath:outer angle:130];

    [[NSGraphicsContext currentContext] saveGraphicsState];
    [outer addClip];
    for (int i = 1; i < 36; i++) {
        CGFloat t = (CGFloat)i / 36.0;
        CGFloat rr = R * (0.24 + t * 0.70);
        NSBezierPath *groove = [NSBezierPath bezierPathWithOvalInRect:
                                NSMakeRect(c.x - rr, c.y - rr, rr * 2, rr * 2)];
        [[NSColor colorWithCalibratedWhite:(i % 2 ? 0.02 : 0.20)
                                     alpha:(0.28 + (i % 3) * 0.04) * alpha] set];
        [groove setLineWidth:0.55];
        [groove stroke];
    }
    // Bright specular crescent (like photo)
    NSBezierPath *sheen = [NSBezierPath bezierPath];
    [sheen appendBezierPathWithArcWithCenter:c radius:R * 0.82
                                  startAngle:spin - 18 endAngle:spin + 42 clockwise:NO];
    [[NSColor colorWithCalibratedWhite:1 alpha:0.14 * alpha] set];
    [sheen setLineWidth:R * 0.10];
    [sheen stroke];
    [[NSGraphicsContext currentContext] restoreGraphicsState];

    // Bright red label (reference)
    CGFloat labelR = R * 0.24;
    NSRect label = NSMakeRect(c.x - labelR, c.y - labelR, labelR * 2, labelR * 2);
    NSBezierPath *lp = [NSBezierPath bezierPathWithOvalInRect:label];
    NSGradient *lg = [[NSGradient alloc] initWithColorsAndLocations:
                      [NSColor colorWithCalibratedRed:0.92 green:0.18 blue:0.14 alpha:alpha], 0.0,
                      [NSColor colorWithCalibratedRed:0.62 green:0.06 blue:0.05 alpha:alpha], 0.55,
                      [NSColor colorWithCalibratedRed:0.38 green:0.03 blue:0.03 alpha:alpha], 1.0, nil];
    [lg drawInBezierPath:lp angle:105];
    [[NSColor colorWithCalibratedWhite:1 alpha:0.18 * alpha] set];
    NSRectFill(NSMakeRect(c.x - labelR * 0.55, c.y - labelR * 0.7, labelR * 1.1, labelR * 0.35));
    // Spindle
    [[NSColor colorWithCalibratedWhite:0.85 alpha:0.9 * alpha] set];
    [[NSBezierPath bezierPathWithOvalInRect:NSMakeRect(c.x - 2.6, c.y - 2.6, 5.2, 5.2)] fill];
    [[NSColor colorWithCalibratedWhite:0.08 alpha:alpha] set];
    [[NSBezierPath bezierPathWithOvalInRect:NSMakeRect(c.x - 1.3, c.y - 1.3, 2.6, 2.6)] fill];

    NSString *title = self.tapeTitle.length ? self.tapeTitle : @"SIDE A";
    if (title.length > 14) title = [[title substringToIndex:13] stringByAppendingString:@"…"];
    NSMutableParagraphStyle *ps = [NSMutableParagraphStyle new];
    ps.alignment = NSTextAlignmentCenter;
    [title drawInRect:NSMakeRect(c.x - labelR + 3, c.y - 4, labelR * 2 - 6, 9)
       withAttributes:@{NSFontAttributeName: [NSFont systemFontOfSize:6 weight:NSFontWeightBold],
                        NSForegroundColorAttributeName: [NSColor colorWithCalibratedWhite:0.95 alpha:alpha],
                        NSParagraphStyleAttributeName: ps}];
}

/// Chrome S-curve tonearm inspired by pro DJ decks (pivot / cue / counterweight / headshell)
- (void)drawTonearmFrom:(NSPoint)pivot
               resting:(NSPoint)needleRest
                  lift:(CGFloat)lift
                 alpha:(CGFloat)alpha {
    lift = MAX(0, MIN(1, lift));
    // Horizontal swing toward rest post when raised + visual foreshorten for height
    CGFloat swing = lift * 22.0 * M_PI / 180.0;
    CGFloat dx = needleRest.x - pivot.x;
    CGFloat dy = needleRest.y - pivot.y;
    CGFloat len = hypot(dx, dy);
    CGFloat baseAng = atan2(dy, dx);
    CGFloat ang = baseAng - swing;
    CGFloat pull = 1.0 - lift * 0.08;
    NSPoint tip = NSMakePoint(pivot.x + cos(ang) * len * pull,
                              pivot.y + sin(ang) * len * pull);
    // Lift foreshortening: tip pulls slightly toward viewer / up in flipped coords
    tip.y -= lift * 7.0;
    tip.x += lift * 2.0;

    CGFloat cdx = cos(ang), sdy = sin(ang);
    CGFloat px = -sdy, py = cdx; // perpendicular for S-bend

    // S-curve control points along the wand
    NSPoint p0 = pivot;
    NSPoint p3 = tip;
    CGFloat bend = len * 0.11;
    NSPoint p1 = NSMakePoint(pivot.x + cdx * len * 0.32 + px * bend,
                             pivot.y + sdy * len * 0.32 + py * bend);
    NSPoint p2 = NSMakePoint(pivot.x + cdx * len * 0.68 - px * bend * 0.85,
                             pivot.y + sdy * len * 0.68 - py * bend * 0.85);

    NSBezierPath *wand = [NSBezierPath bezierPath];
    [wand moveToPoint:p0];
    [wand curveToPoint:p3 controlPoint1:p1 controlPoint2:p2];

    // Cast shadow (offset grows with lift → reads as height)
    NSAffineTransform *sh = [NSAffineTransform transform];
    [sh translateXBy:1.8 + lift * 2.5 yBy:2.2 + lift * 3.5];
    NSBezierPath *shadow = [wand copy];
    [shadow transformUsingAffineTransform:sh];
    [[NSColor colorWithCalibratedWhite:0 alpha:(0.28 + lift * 0.18) * alpha] set];
    [shadow setLineWidth:4.8];
    [shadow setLineCapStyle:NSLineCapStyleRound];
    [shadow stroke];

    // Chrome tube layers
    [[NSColor colorWithCalibratedWhite:0.08 alpha:0.55 * alpha] set];
    [wand setLineWidth:5.4];
    [wand setLineCapStyle:NSLineCapStyleRound];
    [wand stroke];
    [[NSColor colorWithCalibratedWhite:0.72 alpha:alpha] set];
    [wand setLineWidth:3.6];
    [wand stroke];
    [[NSColor colorWithCalibratedWhite:0.95 alpha:0.55 * alpha] set];
    [wand setLineWidth:1.15];
    [wand stroke];

    // Counterweight (cylindrical, behind pivot)
    NSPoint back = NSMakePoint(pivot.x - cdx * 16, pivot.y - sdy * 16);
    NSPoint backFar = NSMakePoint(pivot.x - cdx * 26, pivot.y - sdy * 26);
    NSBezierPath *stem = [NSBezierPath bezierPath];
    [stem moveToPoint:pivot];
    [stem lineToPoint:backFar];
    [[NSColor colorWithCalibratedWhite:0.55 alpha:alpha] set];
    [stem setLineWidth:2.4];
    [stem setLineCapStyle:NSLineCapStyleRound];
    [stem stroke];
    // Weight barrel (ellipse along arm axis)
    CGFloat wr = 6.5, wh = 5.0;
    NSRect weightR = NSMakeRect(back.x - wr, back.y - wh, wr * 2, wh * 2);
    NSBezierPath *weight = [NSBezierPath bezierPathWithOvalInRect:weightR];
    NSGradient *wg = [[NSGradient alloc] initWithColorsAndLocations:
                      [NSColor colorWithCalibratedWhite:0.88 alpha:alpha], 0.0,
                      [NSColor colorWithCalibratedWhite:0.42 alpha:alpha], 0.45,
                      [NSColor colorWithCalibratedWhite:0.18 alpha:alpha], 1.0, nil];
    [wg drawInBezierPath:weight angle:125];
    [[NSColor colorWithCalibratedWhite:0.95 alpha:0.4 * alpha] set];
    [[NSBezierPath bezierPathWithOvalInRect:NSInsetRect(weightR, 2.2, 2.8)] fill];
    // Locking ring on weight
    [[NSColor colorWithCalibratedWhite:0.2 alpha:0.6 * alpha] set];
    NSBezierPath *ring = [NSBezierPath bezierPathWithOvalInRect:NSInsetRect(weightR, 1.2, 1.2)];
    [ring setLineWidth:0.8];
    [ring stroke];

    // Cueing lever (black plastic) — flips with lift
    CGFloat cueAng = (-55.0 + lift * 70.0) * M_PI / 180.0;
    NSPoint cueBase = NSMakePoint(pivot.x + px * 11 - cdx * 2,
                                  pivot.y + py * 11 - sdy * 2);
    NSPoint cueTip = NSMakePoint(cueBase.x + cos(baseAng + cueAng) * 11,
                                 cueBase.y + sin(baseAng + cueAng) * 11);
    // Cue pedestal
    NSBezierPath *cuePed = [NSBezierPath bezierPathWithOvalInRect:
                            NSMakeRect(cueBase.x - 3.2, cueBase.y - 3.2, 6.4, 6.4)];
    [[NSColor colorWithCalibratedWhite:0.12 alpha:alpha] set];
    [cuePed fill];
    [[NSColor colorWithCalibratedWhite:0.45 alpha:0.5 * alpha] set];
    [cuePed setLineWidth:0.6];
    [cuePed stroke];
    NSBezierPath *cue = [NSBezierPath bezierPath];
    [cue moveToPoint:cueBase];
    [cue lineToPoint:cueTip];
    [[NSColor colorWithCalibratedWhite:0.05 alpha:alpha] set];
    [cue setLineWidth:2.6];
    [cue setLineCapStyle:NSLineCapStyleRound];
    [cue stroke];
    [[NSColor colorWithCalibratedWhite:0.25 alpha:alpha] set];
    [cue setLineWidth:1.4];
    [cue stroke];
    // Cue knob
    [[NSColor colorWithCalibratedWhite:0.15 alpha:alpha] set];
    [[NSBezierPath bezierPathWithOvalInRect:NSMakeRect(cueTip.x - 2.4, cueTip.y - 2.4, 4.8, 4.8)] fill];

    // Pivot gimbal + chrome cap
    NSBezierPath *basePlate = [NSBezierPath bezierPathWithOvalInRect:
                               NSMakeRect(pivot.x - 10, pivot.y - 10, 20, 20)];
    NSGradient *plateG = [[NSGradient alloc] initWithColorsAndLocations:
                          [NSColor colorWithCalibratedWhite:0.28 alpha:alpha], 0.0,
                          [NSColor colorWithCalibratedWhite:0.08 alpha:alpha], 1.0, nil];
    [plateG drawInBezierPath:basePlate angle:90];
    NSBezierPath *cap = [NSBezierPath bezierPathWithOvalInRect:
                         NSMakeRect(pivot.x - 7.5, pivot.y - 7.5, 15, 15)];
    NSGradient *capG = [[NSGradient alloc] initWithColorsAndLocations:
                        [NSColor colorWithCalibratedWhite:0.92 alpha:alpha], 0.0,
                        [NSColor colorWithCalibratedWhite:0.55 alpha:alpha], 0.35,
                        [NSColor colorWithCalibratedWhite:0.22 alpha:alpha], 0.7,
                        [NSColor colorWithCalibratedWhite:0.75 alpha:alpha], 1.0, nil];
    [capG drawInBezierPath:cap angle:135];
    // Concentric rings on cap
    for (int i = 1; i <= 3; i++) {
        CGFloat rr = 2.0 + i * 1.5;
        NSBezierPath *cr = [NSBezierPath bezierPathWithOvalInRect:
                            NSMakeRect(pivot.x - rr, pivot.y - rr, rr * 2, rr * 2)];
        [[NSColor colorWithCalibratedWhite:0.15 alpha:0.35 * alpha] set];
        [cr setLineWidth:0.6];
        [cr stroke];
    }
    [[NSColor colorWithCalibratedWhite:0.95 alpha:0.7 * alpha] set];
    [[NSBezierPath bezierPathWithOvalInRect:NSMakeRect(pivot.x - 1.6, pivot.y - 2.4, 2.4, 2.0)] fill];

    // Headshell (angular silver block) + finger lift
    CGFloat hx = tip.x, hy = tip.y;
    NSBezierPath *head = [NSBezierPath bezierPath];
    [head moveToPoint:NSMakePoint(hx - cdx * 2 - px * 4, hy - sdy * 2 - py * 4)];
    [head lineToPoint:NSMakePoint(hx + cdx * 10 - px * 5, hy + sdy * 10 - py * 5)];
    [head lineToPoint:NSMakePoint(hx + cdx * 12 + px * 4, hy + sdy * 12 + py * 4)];
    [head lineToPoint:NSMakePoint(hx - cdx * 1 + px * 5, hy - sdy * 1 + py * 5)];
    [head closePath];
    NSGradient *headG = [[NSGradient alloc] initWithColorsAndLocations:
                         [NSColor colorWithCalibratedWhite:0.82 alpha:alpha], 0.0,
                         [NSColor colorWithCalibratedWhite:0.38 alpha:alpha], 0.55,
                         [NSColor colorWithCalibratedWhite:0.18 alpha:alpha], 1.0, nil];
    [headG drawInBezierPath:head angle:120];
    [[NSColor colorWithCalibratedWhite:0.95 alpha:0.35 * alpha] set];
    [head setLineWidth:0.7];
    [head stroke];

    // Finger lift wire
    NSPoint liftA = NSMakePoint(hx + cdx * 4 - px * 5, hy + sdy * 4 - py * 5);
    NSPoint liftB = NSMakePoint(hx + cdx * 6 - px * 12, hy + sdy * 6 - py * 12);
    NSBezierPath *finger = [NSBezierPath bezierPath];
    [finger moveToPoint:liftA];
    [finger lineToPoint:liftB];
    [[NSColor colorWithCalibratedWhite:0.75 alpha:alpha] set];
    [finger setLineWidth:1.3];
    [finger setLineCapStyle:NSLineCapStyleRound];
    [finger stroke];
    [[NSBezierPath bezierPathWithOvalInRect:NSMakeRect(liftB.x - 1.6, liftB.y - 1.6, 3.2, 3.2)] fill];

    // Cartridge body under headshell
    NSPoint cart = NSMakePoint(hx + cdx * 8, hy + sdy * 8 + (1.0 - lift) * 1.5);
    [[NSColor colorWithCalibratedWhite:0.12 alpha:alpha] set];
    [[NSBezierPath bezierPathWithRoundedRect:NSMakeRect(cart.x - 3, cart.y - 2, 7, 4)
                                    xRadius:1 yRadius:1] fill];
    // Stylus — only clearly touching when not lifted
    if (lift < 0.85) {
        NSBezierPath *needle = [NSBezierPath bezierPath];
        [needle moveToPoint:NSMakePoint(cart.x + 2, cart.y + 2)];
        [needle lineToPoint:NSMakePoint(cart.x + 4, cart.y + 5 + (1.0 - lift) * 2)];
        [[NSColor colorWithCalibratedWhite:0.7 alpha:alpha] set];
        [needle setLineWidth:1.0];
        [needle stroke];
        // Tiny contact highlight on groove
        if (lift < 0.2) {
            [[NSColor colorWithCalibratedWhite:1 alpha:0.35 * alpha] set];
            [[NSBezierPath bezierPathWithOvalInRect:
              NSMakeRect(cart.x + 3.2, cart.y + 5.5, 2.2, 1.4)] fill];
        }
    }
}

- (void)drawDeckKnobAt:(NSPoint)c radius:(CGFloat)r {
    NSBezierPath *knob = [NSBezierPath bezierPathWithOvalInRect:
                          NSMakeRect(c.x - r, c.y - r, r * 2, r * 2)];
    NSGradient *kg = [[NSGradient alloc] initWithColorsAndLocations:
                      [NSColor colorWithCalibratedWhite:0.35 alpha:1], 0.0,
                      [NSColor colorWithCalibratedWhite:0.08 alpha:1], 0.55,
                      [NSColor colorWithCalibratedWhite:0.18 alpha:1], 1.0, nil];
    [kg drawInBezierPath:knob angle:110];
    [[NSColor colorWithCalibratedWhite:0.55 alpha:0.45] set];
    [knob setLineWidth:0.7];
    [knob stroke];
    [[NSColor colorWithCalibratedWhite:0.7 alpha:0.5] set];
    NSRectFill(NSMakeRect(c.x - 0.6, c.y - r + 2, 1.2, r * 0.55));
}

- (void)drawPhonographInRect:(NSRect)door {
    [[NSColor colorWithCalibratedWhite:0.02 alpha:1] set];
    NSRectFill(NSInsetRect(door, 1, 1));
    [[NSColor colorWithCalibratedWhite:0.35 alpha:0.25] set];
    NSFrameRect(NSInsetRect(door, 1.5, 1.5));

    NSRect glass = NSInsetRect(door, 5, 5);
    // Matte black plinth (pro deck, not wood)
    NSGradient *plinth = [[NSGradient alloc] initWithColorsAndLocations:
                          [NSColor colorWithCalibratedWhite:0.11 alpha:1], 0.0,
                          [NSColor colorWithCalibratedWhite:0.045 alpha:1], 0.45,
                          [NSColor colorWithCalibratedWhite:0.03 alpha:1], 0.85,
                          [NSColor colorWithCalibratedWhite:0.06 alpha:1], 1.0, nil];
    [plinth drawInRect:glass angle:90];
    // Fine texture
    [[NSGraphicsContext currentContext] saveGraphicsState];
    [[NSBezierPath bezierPathWithRect:glass] addClip];
    for (CGFloat y = NSMinY(glass); y < NSMaxY(glass); y += 2.5) {
        [[NSColor colorWithCalibratedWhite:0.5 alpha:0.018] set];
        NSRectFill(NSMakeRect(NSMinX(glass), y, NSWidth(glass), 0.6));
    }
    [[NSGraphicsContext currentContext] restoreGraphicsState];

    CGFloat insert = [self insertPhase];
    CGFloat lift = [self tonearmLiftAmount];
    if (_animKind == CassetteAnimInsert) {
        lift = insert < 0.72 ? 1.0 : (1.0 - SKEase((insert - 0.72) / 0.28));
    }

    CGFloat R = MIN(NSWidth(glass), NSHeight(glass)) * 0.40;
    // Platter sits right-of-center; tonearm lives on the left like the reference
    NSPoint center = NSMakePoint(NSMinX(glass) + NSWidth(glass) * 0.58,
                                 NSMidY(glass) + 1);

    // Platter under-mat / rim
    CGFloat matR = R + 5;
    NSBezierPath *mat = [NSBezierPath bezierPathWithOvalInRect:
                         NSMakeRect(center.x - matR, center.y - matR, matR * 2, matR * 2)];
    NSGradient *matG = [[NSGradient alloc] initWithColorsAndLocations:
                        [NSColor colorWithCalibratedWhite:0.18 alpha:1], 0.0,
                        [NSColor colorWithCalibratedWhite:0.05 alpha:1], 1.0, nil];
    [matG drawInBezierPath:mat angle:90];
    [[NSColor colorWithCalibratedWhite:0.35 alpha:0.25] set];
    [mat setLineWidth:1.0];
    [mat stroke];

    CGFloat discY = 0;
    CGFloat discA = 1.0;
    CGFloat discScale = 1.0;
    CGFloat spin = _platterSpin + self.tapeProgress * 40.0;
    if (_animKind == CassetteAnimInsert) {
        discY = -(1.0 - insert) * (NSHeight(glass) * 0.7);
        discA = 0.2 + insert * 0.8;
        discScale = 0.75 + insert * 0.25;
        spin += (1.0 - insert) * 180.0;
    }

    [[NSGraphicsContext currentContext] saveGraphicsState];
    [NSBezierPath clipRect:glass];
    NSPoint discC = NSMakePoint(center.x, center.y + discY);
    CGFloat drawR = R * discScale;
    [self drawVinylAt:discC radius:drawR spin:spin alpha:discA];

    // Side control cluster (left rail) — decorative, matches reference deck
    CGFloat railX = NSMinX(glass) + 14;
    [self drawDeckKnobAt:NSMakePoint(railX, NSMinY(glass) + 18) radius:7];
    [self drawDeckKnobAt:NSMakePoint(railX, NSMinY(glass) + 38) radius:5];
    [self drawDeckKnobAt:NSMakePoint(railX, NSMinY(glass) + 54) radius:5];
    // Pitch slider slot
    NSRect slider = NSMakeRect(railX - 3, NSMinY(glass) + 66, 6, 28);
    SKDrawInsetBevel(slider, 1.5);
    [[NSColor colorWithCalibratedWhite:0.02 alpha:1] set];
    NSRectFill(NSInsetRect(slider, 1.5, 1.5));
    NSRect thumb = NSMakeRect(NSMinX(slider) - 1, NSMinY(slider) + 10, NSWidth(slider) + 2, 7);
    NSBezierPath *tp = [NSBezierPath bezierPathWithRoundedRect:thumb xRadius:1.5 yRadius:1.5];
    NSGradient *tg = [[NSGradient alloc] initWithColorsAndLocations:
                      [NSColor colorWithCalibratedWhite:0.45 alpha:1], 0.0,
                      [NSColor colorWithCalibratedWhite:0.15 alpha:1], 1.0, nil];
    [tg drawInBezierPath:tp angle:90];

    // Tonearm: pivot on left, needle on outer grooves of disc
    NSPoint pivot = NSMakePoint(NSMinX(glass) + 36, NSMaxY(glass) - 28);
    NSPoint needleRest = NSMakePoint(center.x - R * 0.42, center.y - R * 0.18);
    // Rest post (arm park)
    NSPoint restPost = NSMakePoint(pivot.x - 8, pivot.y - 22);
    NSBezierPath *post = [NSBezierPath bezierPathWithOvalInRect:
                          NSMakeRect(restPost.x - 4, restPost.y - 4, 8, 8)];
    [[NSColor colorWithCalibratedWhite:0.2 alpha:1] set];
    [post fill];
    [[NSColor colorWithCalibratedWhite:0.55 alpha:0.4] set];
    [post setLineWidth:0.7];
    [post stroke];

    [self drawTonearmFrom:pivot resting:needleRest lift:lift alpha:1.0];

    NSRect plaque = NSMakeRect(NSMaxX(glass) - 78, NSMaxY(glass) - 20, 70, 13);
    NSBezierPath *pp = [NSBezierPath bezierPathWithRoundedRect:plaque xRadius:2 yRadius:2];
    NSGradient *pg = [[NSGradient alloc] initWithColorsAndLocations:
                      [NSColor colorWithCalibratedWhite:0.28 alpha:1], 0.0,
                      [NSColor colorWithCalibratedWhite:0.08 alpha:1], 1.0, nil];
    [pg drawInBezierPath:pp angle:90];
    SKDrawScrew(NSMakePoint(NSMinX(plaque) + 4, NSMidY(plaque)), 1.2);
    SKDrawScrew(NSMakePoint(NSMaxX(plaque) - 4, NSMidY(plaque)), 1.2);
    SKDrawGlowText(@"PHONO 33⅓", plaque,
                   [NSFont systemFontOfSize:7.5 weight:NSFontWeightBold],
                   [NSColor colorWithCalibratedWhite:0.9 alpha:1],
                   NSTextAlignmentCenter);

    [[NSGraphicsContext currentContext] restoreGraphicsState];
}

#pragma mark - Chrome UI

- (void)drawModeButton:(NSRect)r title:(NSString *)title active:(BOOL)active {
    if (active) {
        NSBezierPath *p = [NSBezierPath bezierPathWithRoundedRect:r xRadius:3 yRadius:3];
        [[NSColor colorWithCalibratedRed:0.4 green:0.2 blue:0.04 alpha:1] set];
        [p fill];
        [SKAmberColor() set];
        [p setLineWidth:1];
        [p stroke];
    } else {
        SKDrawRaisedBevel(r, 2);
    }
    SKDrawGlowText(title, NSInsetRect(r, 1, 2),
                   [NSFont systemFontOfSize:8 weight:NSFontWeightBold],
                   active ? SKAmberColor() : [NSColor colorWithCalibratedWhite:0.7 alpha:1],
                   NSTextAlignmentCenter);
}

- (void)drawStyleToggle {
    NSArray *titles = @[@"磁带", @"唱机"];
    NSArray *frames = [self styleFrames];
    for (NSInteger i = 0; i < 2; i++) {
        NSRect r = [frames[i] rectValue];
        BOOL active = (self.deckStyle == (CassetteDeckStyle)i);
        if (active) {
            NSBezierPath *p = [NSBezierPath bezierPathWithRoundedRect:r xRadius:2 yRadius:2];
            NSGradient *g = [[NSGradient alloc] initWithColorsAndLocations:
                             [NSColor colorWithCalibratedWhite:0.32 alpha:1], 0.0,
                             [NSColor colorWithCalibratedWhite:0.12 alpha:1], 1.0, nil];
            [g drawInBezierPath:p angle:90];
            [[NSColor colorWithCalibratedWhite:0.85 alpha:0.9] set];
            [p setLineWidth:0.8];
            [p stroke];
            SKDrawScrew(NSMakePoint(NSMinX(r) + 4, NSMidY(r)), 1.2);
            SKDrawScrew(NSMakePoint(NSMaxX(r) - 4, NSMidY(r)), 1.2);
        } else {
            SKDrawRaisedBevel(r, 2);
        }
        SKDrawGlowText(titles[i], NSInsetRect(r, 4, 1),
                       [NSFont systemFontOfSize:8 weight:NSFontWeightBold],
                       active ? [NSColor colorWithCalibratedWhite:0.95 alpha:1]
                              : [NSColor colorWithCalibratedWhite:0.55 alpha:1],
                       NSTextAlignmentCenter);
    }
}

- (void)drawTransportIconInRect:(NSRect)r kind:(NSInteger)kind active:(BOOL)active {
    NSColor *c = active ? SKAmberColor() : [NSColor colorWithCalibratedWhite:0.85 alpha:1];
    [c set];
    CGFloat cx = NSMidX(r), cy = NSMidY(r) - 3;
    NSBezierPath *p = [NSBezierPath bezierPath];
    switch (kind) {
        case 0:
            NSRectFill(NSMakeRect(cx - 7, cy - 5, 2, 10));
            [p moveToPoint:NSMakePoint(cx + 6, cy - 6)];
            [p lineToPoint:NSMakePoint(cx + 6, cy + 6)];
            [p lineToPoint:NSMakePoint(cx - 3, cy)];
            [p closePath];
            [p fill];
            break;
        case 1:
            [p moveToPoint:NSMakePoint(cx - 5, cy - 7)];
            [p lineToPoint:NSMakePoint(cx - 5, cy + 7)];
            [p lineToPoint:NSMakePoint(cx + 7, cy)];
            [p closePath];
            [p fill];
            break;
        case 2:
            NSRectFill(NSMakeRect(cx - 5, cy - 6, 3.5, 12));
            NSRectFill(NSMakeRect(cx + 1.5, cy - 6, 3.5, 12));
            break;
        case 3:
            NSRectFill(NSMakeRect(cx - 5, cy - 5, 10, 10));
            break;
        case 4:
            [p moveToPoint:NSMakePoint(cx - 7, cy - 6)];
            [p lineToPoint:NSMakePoint(cx - 7, cy + 6)];
            [p lineToPoint:NSMakePoint(cx + 2, cy)];
            [p closePath];
            [p fill];
            NSRectFill(NSMakeRect(cx + 4, cy - 5, 2, 10));
            break;
        case 5: {
            [p moveToPoint:NSMakePoint(cx, cy - 6)];
            [p lineToPoint:NSMakePoint(cx - 6, cy + 2)];
            [p lineToPoint:NSMakePoint(cx + 6, cy + 2)];
            [p closePath];
            [p fill];
            NSRectFill(NSMakeRect(cx - 6, cy + 4, 12, 2.5));
            break;
        }
        default: break;
    }
}

- (void)drawRect:(NSRect)dirtyRect {
    NSRect bounds = self.bounds;
    SKFillBrushedMetal(bounds, 0.02);
    SKDrawInsetBevel(NSInsetRect(bounds, 2, 2), 4);

    [self drawStyleToggle];

    NSString *deckTitle = (self.deckStyle == CassetteDeckStylePhono)
        ? @"PHONO TURNTABLE" : @"CASSETTE DECK";
    SKDrawGlowText(deckTitle,
                   NSMakeRect(120, 8, 160, 12),
                   [NSFont systemFontOfSize:10 weight:NSFontWeightBold],
                   [NSColor colorWithCalibratedWhite:0.72 alpha:1],
                   NSTextAlignmentLeft);

    NSArray *modeTitles = @[@"顺序", @"单曲", @"随机"];
    NSArray *modeFrames = [self modeFrames];
    for (NSInteger i = 0; i < 3; i++) {
        [self drawModeButton:[modeFrames[i] rectValue]
                       title:modeTitles[i]
                      active:(self.playMode == (AudioPlayMode)i)];
    }

    NSArray *frames = [self transportFrames];
    NSRect door = [self doorFrame];
    SKDrawInsetBevel(door, 3);
    if (self.deckStyle == CassetteDeckStylePhono) {
        [self drawPhonographInRect:door];
    } else {
        [self drawRealisticCassetteInRect:door];
    }
    [self drawDoorHardwareAround:door];

    if (frames.count) {
        NSRect first = [frames[0] rectValue];
        NSRect last = [frames[5] rectValue];
        NSRect bank = NSMakeRect(NSMinX(first) - 4, NSMinY(first) - 3,
                                 NSMaxX(last) - NSMinX(first) + 8, NSHeight(first) + 6);
        [[NSColor colorWithCalibratedWhite:0 alpha:0.25] set];
        [[NSBezierPath bezierPathWithRoundedRect:NSOffsetRect(bank, 0, 1) xRadius:3 yRadius:3] fill];
        SKFillBrushedMetal(bank, 0.06);
        [[NSColor colorWithCalibratedWhite:0.4 alpha:0.25] set];
        NSFrameRect(NSInsetRect(bank, 0.5, 0.5));
        [[NSColor colorWithCalibratedWhite:0.05 alpha:0.6] set];
        NSFrameRect(bank);
    }

    NSArray *captions = @[@"PREV", @"PLAY", @"PAUSE", @"STOP", @"NEXT", @"EJECT"];
    for (NSInteger i = 0; i < 6; i++) {
        NSRect r = [frames[i] rectValue];
        BOOL active = (_activeTransport == i + 1);
        if (active) {
            NSBezierPath *p = [NSBezierPath bezierPathWithRoundedRect:r xRadius:3 yRadius:3];
            NSGradient *g = [[NSGradient alloc] initWithStartingColor:[NSColor colorWithCalibratedRed:0.55 green:0.28 blue:0.05 alpha:1]
                                                          endingColor:[NSColor colorWithCalibratedRed:0.2 green:0.08 blue:0.02 alpha:1]];
            [g drawInBezierPath:p angle:90];
            [[NSColor colorWithCalibratedWhite:0 alpha:0.4] set];
            NSRectFill(NSMakeRect(NSMinX(r) + 2, NSMinY(r) + 1, NSWidth(r) - 4, 1.2));
        } else {
            SKDrawRaisedBevel(r, 3);
        }
        [self drawTransportIconInRect:r kind:i active:active];
        SKDrawGlowText(captions[i],
                       NSMakeRect(NSMinX(r), NSMaxY(r) - 11, NSWidth(r), 9),
                       [NSFont systemFontOfSize:7 weight:NSFontWeightBold],
                       active ? SKAmberColor() : [NSColor colorWithCalibratedWhite:0.65 alpha:1],
                       NSTextAlignmentCenter);
    }
}

- (void)mouseDown:(NSEvent *)event {
    NSPoint p = [self convertPoint:event.locationInWindow fromView:nil];

    NSArray *styleFrames = [self styleFrames];
    for (NSInteger i = 0; i < 2; i++) {
        if (NSPointInRect(p, [styleFrames[i] rectValue])) {
            self.deckStyle = (CassetteDeckStyle)i;
            // Soft re-seat animation when flipping mechanism
            [self playMediaInsertAnimation];
            return;
        }
    }

    NSArray *modeFrames = [self modeFrames];
    for (NSInteger i = 0; i < 3; i++) {
        if (NSPointInRect(p, [modeFrames[i] rectValue])) {
            self.playMode = (AudioPlayMode)i;
            if (self.onPlayModeChanged) self.onPlayModeChanged(self.playMode);
            [self setNeedsDisplay:YES];
            return;
        }
    }

    NSArray *frames = [self transportFrames];
    NSArray *cmds = @[@"prev", @"play", @"pause", @"stop", @"next", @"eject"];
    for (NSInteger i = 0; i < 6; i++) {
        if (NSPointInRect(p, [frames[i] rectValue])) {
            _activeTransport = i + 1;
            if (i == 1) self.playing = YES;
            if (i == 2 || i == 3) self.playing = NO;
            [self setNeedsDisplay:YES];
            if (self.onTransport) self.onTransport(cmds[i]);
            break;
        }
    }
}

@end
