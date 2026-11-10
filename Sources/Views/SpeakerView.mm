#import "SpeakerView.h"
#import "DrawingHelpers.h"
#import "BrandProfile.h"

@implementation SpeakerView {
    NSTimer *_timer;
    CGFloat _phase;
    float _wave[64];
    CGFloat _tweeterExcursion;
    CGFloat _midExcursion;
    CGFloat _wooferExcursion;
    CGFloat _woofer2Excursion;
}

- (instancetype)initWithFrame:(NSRect)frameRect {
    self = [super initWithFrame:frameRect];
    if (self) {
        _activity = 0.5;
        _playing = NO;
        _brandRailText = @"classic";
        for (int i = 0; i < 64; i++) _wave[i] = 0;
        _timer = [NSTimer scheduledTimerWithTimeInterval:1.0 / 40.0
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

- (void)pushWaveformSample:(float)sample {
    for (int i = 0; i < 63; i++) _wave[i] = _wave[i + 1];
    _wave[63] = sample;
}

- (void)tick {
    _phase += 0.35 + self.channelLevel * 0.8;

    CGFloat drive = self.playing ? 1.0 : 0.0;
    // Stronger envelope so cones travel farther at typical listening levels
    CGFloat targetW = drive * self.bassLevel * (0.85 + self.activity * 0.65) * (0.75 + 0.45 * self.channelLevel);
    CGFloat targetM = drive * self.midLevel * (0.65 + self.activity * 0.55);
    CGFloat targetT = drive * self.trebleLevel * (0.55 + self.activity * 0.5);

    _wooferExcursion += (targetW - _wooferExcursion) * (targetW > _wooferExcursion ? 0.62 : 0.20);
    _woofer2Excursion += (targetW * 0.9 - _woofer2Excursion) * (targetW > _woofer2Excursion ? 0.58 : 0.18);
    _midExcursion += (targetM - _midExcursion) * (targetM > _midExcursion ? 0.58 : 0.22);
    _tweeterExcursion += (targetT - _tweeterExcursion) * (targetT > _tweeterExcursion ? 0.68 : 0.26);

    if (self.playing && self.channelLevel > 0.015) {
        _wooferExcursion += sin(_phase * 2.2) * self.bassLevel * 0.18;
        _woofer2Excursion += sin(_phase * 2.0 + 0.7) * self.bassLevel * 0.16;
        _midExcursion += sin(_phase * 4.5) * self.midLevel * 0.14;
        _tweeterExcursion += sin(_phase * 9.0) * self.trebleLevel * 0.12;
    }

    if (!self.playing) {
        for (int i = 0; i < 63; i++) _wave[i] = _wave[i + 1] * 0.92f;
        _wave[63] *= 0.9f;
    } else if (fabsf(_wave[63]) < 0.001f) {
        float s = sinf(_phase) * self.channelLevel * 1.35f
                + 0.4f * sinf(_phase * 2.7f) * self.midLevel;
        [self pushWaveformSample:s];
    }

    [self setNeedsDisplay:YES];
}

#pragma mark - Cabinet

- (void)fillCabinet:(NSRect)bounds {
    // Thick black-ash tower with depth falloff
    NSGradient *cab = [[NSGradient alloc] initWithColorsAndLocations:
                       [NSColor colorWithCalibratedWhite:0.038 alpha:1], 0.0,
                       [NSColor colorWithCalibratedWhite:0.095 alpha:1], 0.16,
                       [NSColor colorWithCalibratedWhite:0.072 alpha:1], 0.48,
                       [NSColor colorWithCalibratedWhite:0.052 alpha:1], 0.80,
                       [NSColor colorWithCalibratedWhite:0.025 alpha:1], 1.0, nil];
    [cab drawInRect:bounds angle:0];
    // 面板主题轻染箱体（与主机壳同步）
    NSColor *cabTint = [BrandProfile activeBrand].chassisTint;
    if (cabTint) {
        [cabTint set];
        NSRectFillUsingOperation(bounds, NSCompositingOperationSourceOver);
    }

    [[NSGraphicsContext currentContext] saveGraphicsState];
    [[NSBezierPath bezierPathWithRect:bounds] addClip];
    // Fine vertical veneer grain
    for (CGFloat x = NSMinX(bounds); x < NSMaxX(bounds); x += 1.5) {
        NSInteger i = (NSInteger)(x * 10);
        CGFloat a = 0.014 + ((i * 17) % 9) * 0.0035;
        [[NSColor colorWithCalibratedWhite:0.58 alpha:a] set];
        NSRectFill(NSMakeRect(x, NSMinY(bounds), 0.65, NSHeight(bounds)));
    }
    // Soft horizontal baffle shadow bands
    for (CGFloat y = NSMinY(bounds) + 40; y < NSMaxY(bounds) - 40; y += 26) {
        [[NSColor colorWithCalibratedWhite:0 alpha:0.05] set];
        NSRectFill(NSMakeRect(NSMinX(bounds) + 8, y, NSWidth(bounds) - 16, 1));
    }
    // Soft overhead specular on baffle
    NSGradient *topLit = [[NSGradient alloc] initWithColorsAndLocations:
                          [NSColor colorWithCalibratedWhite:1 alpha:0.055], 0.0,
                          [NSColor colorWithCalibratedWhite:1 alpha:0.0], 0.14, nil];
    [topLit drawInRect:bounds angle:90];
    [[NSGraphicsContext currentContext] restoreGraphicsState];

    // Raised front baffle cheek
    NSRect baffle = NSInsetRect(bounds, 7, 10);
    [[NSColor colorWithCalibratedWhite:0.0 alpha:0.6] set];
    NSFrameRect(baffle);
    [[NSColor colorWithCalibratedWhite:0.22 alpha:0.28] set];
    NSRectFill(NSMakeRect(NSMinX(baffle), NSMinY(baffle), NSWidth(baffle), 1));
    [[NSColor colorWithCalibratedWhite:0.0 alpha:0.4] set];
    NSRectFill(NSMakeRect(NSMinX(baffle), NSMaxY(baffle) - 1, NSWidth(baffle), 1));

    // Chrome-ish outer cabinet lip
    [[NSColor colorWithCalibratedWhite:0.42 alpha:0.32] set];
    NSFrameRect(NSInsetRect(bounds, 1, 1));
    [[NSColor colorWithCalibratedWhite:0.0 alpha:0.88] set];
    NSFrameRect(bounds);
}

- (void)drawRadialFillInOval:(NSRect)oval
                  innerColor:(NSColor *)inner
                  outerColor:(NSColor *)outer
                       steps:(NSInteger)steps {
    // Approximate radial gradient: rim = outer (lit), throat = inner (deep)
    steps = MAX(6, steps);
    for (NSInteger i = steps; i >= 0; i--) {
        CGFloat t = (CGFloat)i / (CGFloat)steps; // 1 = rim, 0 = center
        CGFloat inset = (1.0 - t) * MIN(NSWidth(oval), NSHeight(oval)) * 0.5;
        NSRect ring = NSInsetRect(oval, inset, inset);
        if (NSWidth(ring) < 1 || NSHeight(ring) < 1) continue;
        NSColor *c = [inner blendedColorWithFraction:t ofColor:outer];
        [c set];
        [[NSBezierPath bezierPathWithOvalInRect:ring] fill];
    }
}

- (void)drawBaffleRingAt:(NSPoint)c radius:(CGFloat)r gold:(BOOL)gold {
    // Deep recessed baffle well — thick MDF cutout
    CGFloat wellPad = MAX(6.0, r * 0.12);
    NSBezierPath *well = [NSBezierPath bezierPathWithOvalInRect:
                          NSMakeRect(c.x - r - wellPad, c.y - r - wellPad,
                                     (r + wellPad) * 2, (r + wellPad) * 2)];
    NSGradient *wellG = [[NSGradient alloc] initWithColorsAndLocations:
                         [NSColor colorWithCalibratedWhite:0.0 alpha:1], 0.0,
                         [NSColor colorWithCalibratedWhite:0.045 alpha:1], 0.55,
                         [NSColor colorWithCalibratedWhite:0.0 alpha:1], 1.0, nil];
    [wellG drawInBezierPath:well angle:110];

    // Cast shadow under the rim (depth into cabinet)
    [[NSColor colorWithCalibratedWhite:0 alpha:0.58] set];
    [[NSBezierPath bezierPathWithOvalInRect:
      NSMakeRect(c.x - r - 2.5, c.y - r + 2.2, (r + 2.5) * 2, (r + 1.2) * 2)] fill];

    // —— Outer mounting flange (anodized / theme trim) ——
    NSRect outer = NSMakeRect(c.x - r, c.y - r, r * 2, r * 2);
    NSBezierPath *rim = [NSBezierPath bezierPathWithOvalInRect:outer];
    if (gold) {
        NSColor *trim = [BrandProfile activeBrand].trimColor
            ?: [NSColor colorWithCalibratedRed:0.92 green:0.72 blue:0.28 alpha:1];
        CGFloat tr, tg, tb, ta;
        [[trim colorUsingColorSpace:NSColorSpace.genericRGBColorSpace]
         getRed:&tr green:&tg blue:&tb alpha:&ta];
        NSGradient *g = [[NSGradient alloc] initWithColorsAndLocations:
                         [NSColor colorWithCalibratedRed:tr*0.55 green:tg*0.55 blue:tb*0.45 alpha:1], 0.0,
                         [NSColor colorWithCalibratedRed:MIN(1, tr*1.05) green:MIN(1, tg*1.05) blue:MIN(1, tb*0.95) alpha:1], 0.2,
                         [NSColor colorWithCalibratedRed:tr*0.42 green:tg*0.38 blue:tb*0.32 alpha:1], 0.52,
                         [NSColor colorWithCalibratedRed:tr*0.18 green:tg*0.14 blue:tb*0.12 alpha:1], 0.78,
                         [NSColor colorWithCalibratedRed:tr*0.85 green:tg*0.78 blue:tb*0.65 alpha:1], 1.0, nil];
        [g drawInBezierPath:rim angle:145];
    } else {
        NSGradient *g = [[NSGradient alloc] initWithColorsAndLocations:
                         [NSColor colorWithCalibratedWhite:0.55 alpha:1], 0.0,
                         [NSColor colorWithCalibratedWhite:0.24 alpha:1], 0.32,
                         [NSColor colorWithCalibratedWhite:0.06 alpha:1], 0.68,
                         [NSColor colorWithCalibratedWhite:0.38 alpha:1], 1.0, nil];
        [g drawInBezierPath:rim angle:140];
    }

    // —— Secondary stepped chrome ring (inner flange) ——
    CGFloat step = MAX(2.0, r * 0.055);
    NSRect stepR = NSInsetRect(outer, step, step);
    NSBezierPath *stepPath = [NSBezierPath bezierPathWithOvalInRect:stepR];
    NSGradient *stepG = [[NSGradient alloc] initWithColorsAndLocations:
                         [NSColor colorWithCalibratedWhite:0.42 alpha:1], 0.0,
                         [NSColor colorWithCalibratedWhite:0.12 alpha:1], 0.45,
                         [NSColor colorWithCalibratedWhite:0.05 alpha:1], 0.75,
                         [NSColor colorWithCalibratedWhite:0.28 alpha:1], 1.0, nil];
    [stepG drawInBezierPath:stepPath angle:125];

    // Inner chamfer catch-light
    [[NSColor colorWithCalibratedWhite:0.75 alpha:0.28] set];
    NSBezierPath *hi = [NSBezierPath bezierPathWithOvalInRect:NSInsetRect(stepR, 0.6, 0.6)];
    [hi setLineWidth:0.9];
    [hi stroke];
    [[NSColor colorWithCalibratedWhite:0.0 alpha:0.55] set];
    NSBezierPath *midPath = [NSBezierPath bezierPathWithOvalInRect:NSInsetRect(stepR, step * 0.35, step * 0.35)];
    [midPath setLineWidth:MAX(1.0, r * 0.028)];
    [midPath stroke];

    // Mount screws (6 for larger drivers)
    NSInteger nScrew = (r > 40) ? 6 : 4;
    CGFloat screwR = MAX(1.5, r * 0.042);
    for (NSInteger i = 0; i < nScrew; i++) {
        CGFloat ang = -M_PI_2 + i * (2.0 * M_PI / nScrew) + M_PI / nScrew;
        NSPoint sp = NSMakePoint(c.x + cos(ang) * r * 0.935,
                                 c.y + sin(ang) * r * 0.935);
        SKDrawScrew(sp, screwR);
    }

    // Basket throat (dark cylinder into magnet)
    NSBezierPath *throat = [NSBezierPath bezierPathWithOvalInRect:NSInsetRect(outer, r * 0.105, r * 0.105)];
    [[NSColor colorWithCalibratedWhite:0.012 alpha:1] set];
    [throat fill];
}

- (void)drawDriverAt:(NSPoint)center
              radius:(CGFloat)r
           excursion:(CGFloat)exc
             dustCap:(CGFloat)capRatio
                gold:(BOOL)gold
              woofer:(BOOL)woofer
           phasePlug:(BOOL)phasePlug {
    exc = MAX(0, MIN(1.65, exc));
    // Membrane-only radial pulse (scale), baffle fixed — no vertical "crawl"
    CGFloat osc = sin(_phase * (woofer ? 2.4 : 5.2));
    CGFloat pulse = 1.0 + osc * exc * (woofer ? 0.11 : 0.07); // radius magnification
    // Throat foreshortens slightly when cone "comes forward"
    CGFloat throat = 1.0 - MAX(0, osc) * exc * (woofer ? 0.06 : 0.04);
    CGFloat lightBiasX = -r * 0.08;
    CGFloat lightBiasY = -r * 0.10;
    NSPoint baffle = center;
    NSPoint c = center; // cone stays concentric with baffle

    [self drawBaffleRingAt:baffle radius:r gold:gold];

    // —— Half-roll rubber surround — outer fixed, inner breathes with pulse ——
    CGFloat surOuter = r * 0.91;
    CGFloat surInner = r * 0.76 * pulse * throat;
    for (int k = 0; k < 4; k++) {
        CGFloat t0 = (CGFloat)k / 4.0;
        CGFloat t1 = (CGFloat)(k + 1) / 4.0;
        CGFloat r0 = surOuter + (surInner - surOuter) * t0;
        CGFloat r1 = surOuter + (surInner - surOuter) * t1;
        NSRect band = NSMakeRect(c.x - r0, c.y - r0, r0 * 2, r0 * 2);
        NSBezierPath *bandPath = [NSBezierPath bezierPathWithOvalInRect:band];
        CGFloat shade = (k % 2 == 0) ? 0.14 : 0.045;
        [[NSColor colorWithCalibratedWhite:shade alpha:1] set];
        [bandPath fill];
        NSBezierPath *innerCut = [NSBezierPath bezierPathWithOvalInRect:
                                  NSMakeRect(c.x - r1, c.y - r1, r1 * 2, r1 * 2)];
        [[NSColor colorWithCalibratedWhite:0.012 alpha:1] set];
        [innerCut fill];
    }
    NSBezierPath *surLip = [NSBezierPath bezierPathWithOvalInRect:
                            NSMakeRect(baffle.x - surOuter, baffle.y - surOuter, surOuter * 2, surOuter * 2)];
    [[NSColor colorWithCalibratedWhite:0.28 alpha:0.35] set];
    [surLip setLineWidth:1.1];
    [surLip stroke];

    // —— Paper / pulp cone — radial scale only ——
    CGFloat coneR = surInner * 0.98;
    NSRect cone = NSMakeRect(c.x - coneR + lightBiasX * 0.15,
                             c.y - coneR + lightBiasY * 0.1,
                             coneR * 2, coneR * 2);
    NSColor *coneInner = woofer
        ? [NSColor colorWithCalibratedRed:0.10 green:0.07 blue:0.035 alpha:1]
        : [NSColor colorWithCalibratedWhite:0.06 alpha:1];
    NSColor *coneOuter = woofer
        ? [NSColor colorWithCalibratedRed:0.28 green:0.20 blue:0.10 alpha:1]
        : [NSColor colorWithCalibratedWhite:0.22 alpha:1];
    [self drawRadialFillInOval:cone innerColor:coneInner outerColor:coneOuter steps:woofer ? 14 : 10];

    [[NSGraphicsContext currentContext] saveGraphicsState];
    [[NSBezierPath bezierPathWithOvalInRect:cone] addClip];
    NSGradient *spec = [[NSGradient alloc] initWithColorsAndLocations:
                        [NSColor colorWithCalibratedWhite:1 alpha:0.0], 0.0,
                        [NSColor colorWithCalibratedWhite:1 alpha:0.10 + exc * 0.05], 0.35,
                        [NSColor colorWithCalibratedWhite:1 alpha:0.0], 0.7, nil];
    [spec drawInRect:cone angle:125];
    NSGradient *shade = [[NSGradient alloc] initWithColorsAndLocations:
                         [NSColor colorWithCalibratedWhite:0 alpha:0.0], 0.0,
                         [NSColor colorWithCalibratedWhite:0 alpha:0.28], 1.0, nil];
    [shade drawInRect:cone angle:310];
    [[NSGraphicsContext currentContext] restoreGraphicsState];

    NSInteger rings = woofer ? 7 : 5;
    for (NSInteger i = 1; i <= rings; i++) {
        CGFloat rr = coneR * (1.0 - i * (0.55 / rings));
        NSPoint rc = NSMakePoint(c.x + lightBiasX * 0.08 * i / rings,
                                 c.y + lightBiasY * 0.06 * i / rings);
        NSBezierPath *ring = [NSBezierPath bezierPathWithOvalInRect:
                              NSMakeRect(rc.x - rr, rc.y - rr, rr * 2, rr * 2)];
        [[NSColor colorWithCalibratedWhite:0.0 alpha:0.22] set];
        [ring setLineWidth:MAX(0.6, r * 0.012)];
        [ring stroke];
        [[NSColor colorWithCalibratedWhite:0.45 alpha:0.08] set];
        NSBezierPath *hi = [NSBezierPath bezierPathWithOvalInRect:
                            NSMakeRect(rc.x - rr + 0.5, rc.y - rr + 0.5, rr * 2 - 1, rr * 2 - 1)];
        [hi setLineWidth:0.5];
        [hi stroke];
    }

    if (woofer) {
        [[NSColor colorWithCalibratedWhite:0.0 alpha:0.18] set];
        for (int i = 0; i < 8; i++) {
            CGFloat ang = i * (M_PI / 4.0) + 0.2;
            NSBezierPath *spoke = [NSBezierPath bezierPath];
            [spoke moveToPoint:NSMakePoint(c.x + cos(ang) * coneR * 0.55,
                                           c.y + sin(ang) * coneR * 0.55)];
            [spoke lineToPoint:NSMakePoint(baffle.x + cos(ang) * surOuter * 0.98,
                                           baffle.y + sin(ang) * surOuter * 0.98)];
            [spoke setLineWidth:1.1];
            [spoke stroke];
        }
    }

    if (phasePlug) {
        CGFloat pr = r * 0.16 * (0.92 + 0.08 * pulse);
        NSPoint pc = NSMakePoint(c.x + lightBiasX * 0.2, c.y + lightBiasY * 0.15);
        NSRect plugR = NSMakeRect(pc.x - pr, pc.y - pr, pr * 2, pr * 2);
        [self drawRadialFillInOval:plugR
                        innerColor:[NSColor colorWithCalibratedWhite:0.62 alpha:1]
                        outerColor:[NSColor colorWithCalibratedWhite:0.18 alpha:1]
                             steps:8];
        [[NSColor colorWithCalibratedWhite:0.85 alpha:0.45] set];
        [[NSBezierPath bezierPathWithOvalInRect:NSInsetRect(plugR, pr * 0.35, pr * 0.45)] fill];
        [[NSColor colorWithCalibratedWhite:0.0 alpha:0.4] set];
        NSBezierPath *plugEdge = [NSBezierPath bezierPathWithOvalInRect:plugR];
        [plugEdge setLineWidth:1];
        [plugEdge stroke];
    } else {
        // Dust cap pulses harder — reads as excursion toward the listener
        CGFloat capR = r * capRatio * pulse * (1.0 + exc * 0.04);
        NSPoint capC = NSMakePoint(c.x + lightBiasX * 0.25, c.y + lightBiasY * 0.2);
        NSRect cap = NSMakeRect(capC.x - capR, capC.y - capR, capR * 2, capR * 2);
        [self drawRadialFillInOval:cap
                        innerColor:[NSColor colorWithCalibratedWhite:0.38 alpha:1]
                        outerColor:[NSColor colorWithCalibratedWhite:0.05 alpha:1]
                             steps:9];
        CGFloat hotR = capR * 0.28;
        NSRect hot = NSMakeRect(capC.x - hotR - capR * 0.15, capC.y - hotR - capR * 0.2, hotR * 2, hotR * 2);
        [[NSColor colorWithCalibratedWhite:1 alpha:0.22] set];
        [[NSBezierPath bezierPathWithOvalInRect:hot] fill];
        [[NSColor colorWithCalibratedWhite:0.55 alpha:0.3] set];
        NSBezierPath *capEdge = [NSBezierPath bezierPathWithOvalInRect:cap];
        [capEdge setLineWidth:1];
        [capEdge stroke];
    }

    // Soft bloom when driven — radial, not directional
    if (exc > 0.22) {
        CGFloat bloom = exc * (2.5 + MAX(0, osc) * 3.0);
        [[NSColor colorWithCalibratedWhite:1 alpha:0.035 * exc] set];
        [[NSBezierPath bezierPathWithOvalInRect:NSInsetRect(cone, -bloom, -bloom)] fill];
    }
}

- (void)drawDomeTweeterAt:(NSPoint)c radius:(CGFloat)r excursion:(CGFloat)exc {
    exc = MAX(0, MIN(1.5, exc));
    // Flange fixed; dome radius pulses (no upward crawl)
    CGFloat osc = sin(_phase * 10.0);
    CGFloat pulse = 1.0 + osc * exc * 0.12;
    NSPoint baffle = c;

    [self drawBaffleRingAt:baffle radius:r gold:NO];

    CGFloat guideR = r * 0.72;
    NSRect guide = NSMakeRect(baffle.x - guideR, baffle.y - guideR, guideR * 2, guideR * 2);
    [self drawRadialFillInOval:guide
                    innerColor:[NSColor colorWithCalibratedWhite:0.04 alpha:1]
                    outerColor:[NSColor colorWithCalibratedWhite:0.20 alpha:1]
                         steps:8];
    [[NSColor colorWithCalibratedWhite:0.55 alpha:0.2] set];
    NSBezierPath *guideEdge = [NSBezierPath bezierPathWithOvalInRect:guide];
    [guideEdge setLineWidth:1];
    [guideEdge stroke];

    CGFloat domeR = r * 0.48 * pulse;
    NSRect dome = NSMakeRect(c.x - domeR, c.y - domeR, domeR * 2, domeR * 2);
    [self drawRadialFillInOval:dome
                    innerColor:[NSColor colorWithCalibratedWhite:0.62 alpha:1]
                    outerColor:[NSColor colorWithCalibratedWhite:0.10 alpha:1]
                         steps:10];
    CGFloat hotR = domeR * 0.22;
    [[NSColor colorWithCalibratedWhite:1 alpha:0.3] set];
    [[NSBezierPath bezierPathWithOvalInRect:
      NSMakeRect(c.x - hotR - domeR * 0.18, c.y - hotR - domeR * 0.25, hotR * 2, hotR * 2)] fill];

    [[NSGraphicsContext currentContext] saveGraphicsState];
    [[NSBezierPath bezierPathWithOvalInRect:dome] addClip];
    [[NSColor colorWithCalibratedWhite:0.0 alpha:0.24] set];
    CGFloat step = MAX(2.0, domeR * 0.16);
    for (CGFloat x = NSMinX(dome); x < NSMaxX(dome); x += step) {
        NSBezierPath *v = [NSBezierPath bezierPath];
        [v moveToPoint:NSMakePoint(x, NSMinY(dome))];
        [v lineToPoint:NSMakePoint(x, NSMaxY(dome))];
        [v setLineWidth:0.45];
        [v stroke];
    }
    for (CGFloat y = NSMinY(dome); y < NSMaxY(dome); y += step) {
        NSBezierPath *h = [NSBezierPath bezierPath];
        [h moveToPoint:NSMakePoint(NSMinX(dome), y)];
        [h lineToPoint:NSMakePoint(NSMaxX(dome), y)];
        [h setLineWidth:0.45];
        [h stroke];
    }
    [[NSGraphicsContext currentContext] restoreGraphicsState];
}

- (void)drawSlotPortInRect:(NSRect)r {
    SKDrawInsetBevel(r, 3);
    NSRect inner = NSInsetRect(r, 3, 3);
    NSGradient *g = [[NSGradient alloc] initWithColorsAndLocations:
                     [NSColor colorWithCalibratedWhite:0.0 alpha:1], 0.0,
                     [NSColor colorWithCalibratedWhite:0.09 alpha:1], 0.45,
                     [NSColor colorWithCalibratedWhite:0.0 alpha:1], 1.0, nil];
    [g drawInRect:inner angle:90];

    // Horizontal louvers inside the slot
    [[NSColor colorWithCalibratedWhite:0.12 alpha:0.55] set];
    for (CGFloat y = NSMinY(inner) + 4; y < NSMaxY(inner) - 3; y += 4.5) {
        NSRectFill(NSMakeRect(NSMinX(inner) + 4, y, NSWidth(inner) - 8, 1.1));
    }

    // Bass air shimmer when playing
    if (self.playing && self.bassLevel > 0.05) {
        CGFloat a = 0.06 + self.bassLevel * 0.16 * (0.5 + 0.5 * sin(_phase * 3.0));
        [[NSColor colorWithCalibratedWhite:1 alpha:a] set];
        NSRectFill(NSInsetRect(inner, 5, 1.5));
    }
}

- (void)drawStatusLEDAt:(NSPoint)c on:(BOOL)on {
    NSRect r = NSMakeRect(c.x - 3.5, c.y - 3.5, 7, 7);
    SKDrawJewelLED(r, SKAmberColor(), on);
}

- (void)drawRect:(NSRect)dirtyRect {
    NSRect bounds = self.bounds;
    [self fillCabinet:bounds];

    CGFloat w = NSWidth(bounds);
    CGFloat h = NSHeight(bounds);
    CGFloat midX = NSMidX(bounds);
    // Scale drivers to the wider tower
    CGFloat scale = MIN(w / 210.0, h / 720.0);
    scale = MAX(0.85, MIN(1.25, scale));

    // Narrow decorative side rails — brushed aluminum trim
    NSRect rail = self.mirrored
        ? NSMakeRect(NSMaxX(bounds) - 14, 36, 6, h - 72)
        : NSMakeRect(8, 36, 6, h - 72);
    SKFillBrushedMetal(rail, 0.04);
    [[NSColor colorWithCalibratedWhite:0.5 alpha:0.3] set];
    NSFrameRect(NSInsetRect(rail, 0.5, 0.5));
    [[NSColor colorWithCalibratedWhite:0.05 alpha:0.7] set];
    NSFrameRect(rail);

    // Top-center brand nameplate — 拾音盒子
    NSString *brandKey = self.brandRailText.length ? self.brandRailText : @"classic";
    BrandProfile *brand = [BrandProfile brandWithIdentifier:brandKey];
    CGFloat plateW = MIN(w - 28, 148);
    NSRect nameplate = NSMakeRect(midX - plateW * 0.5, 8, plateW, 24);
    SKDrawRaisedBevel(nameplate, 2.5);
    SKDrawScrew(NSMakePoint(NSMinX(nameplate) + 7, NSMidY(nameplate)), 1.7);
    SKDrawScrew(NSMakePoint(NSMaxX(nameplate) - 7, NSMidY(nameplate)), 1.7);
    NSRect markRect = NSMakeRect(NSMinX(nameplate) + 14, NSMinY(nameplate) + 2,
                                 NSWidth(nameplate) - 28, NSHeight(nameplate) - 4);
    [brand drawWordmarkInRect:markRect];

    // —— Classic 3-way + twin woofer floorstander ——
    // Drivers sit below the top nameplate
    // Tweeter (dome)
    [self drawDomeTweeterAt:NSMakePoint(midX, h * 0.095)
                     radius:18 * scale
                  excursion:_tweeterExcursion];

    // Midrange with phase plug
    [self drawDriverAt:NSMakePoint(midX, h * 0.215)
                radius:32 * scale
             excursion:_midExcursion
               dustCap:0.22
                  gold:NO
                woofer:NO
             phasePlug:YES];

    // Upper woofer (gold trim)
    [self drawDriverAt:NSMakePoint(midX, h * 0.40)
                radius:56 * scale
             excursion:_wooferExcursion
               dustCap:0.17
                  gold:YES
                woofer:YES
             phasePlug:NO];

    // Lower woofer (matched gold)
    [self drawDriverAt:NSMakePoint(midX, h * 0.615)
                radius:56 * scale
             excursion:_woofer2Excursion
               dustCap:0.17
                  gold:YES
                woofer:YES
             phasePlug:NO];

    // Slot bass-reflex
    CGFloat slotW = MIN(w - 48, 130 * scale);
    NSRect slot = NSMakeRect(midX - slotW * 0.5, h * 0.775, slotW, 20 * scale);
    [self drawSlotPortInRect:slot];

    // Compact amber scope under the port
    NSRect scope = NSMakeRect(midX - slotW * 0.5, NSMaxY(slot) + 6, slotW, 16 * scale);
    SKDrawInsetBevel(scope, 2);
    NSRect sa = NSInsetRect(scope, 2, 2);
    [[NSColor colorWithCalibratedWhite:0.015 alpha:1] set];
    NSRectFill(sa);
    NSBezierPath *wave = [NSBezierPath bezierPath];
    for (int i = 0; i < 64; i++) {
        CGFloat x = NSMinX(sa) + NSWidth(sa) * i / 63.0;
        CGFloat y = NSMidY(sa) + _wave[i] * NSHeight(sa) * 0.62;
        if (i == 0) [wave moveToPoint:NSMakePoint(x, y)];
        else [wave lineToPoint:NSMakePoint(x, y)];
    }
    [[SKAmberColor() colorWithAlphaComponent:self.playing ? 0.9 : 0.35] set];
    [wave setLineWidth:1.1];
    [wave stroke];

    // Bottom model plate
    NSRect badge = NSMakeRect(midX - 50, h - 48, 100, 18);
    SKDrawRaisedBevel(badge, 2);
    SKDrawGlowText(brand.modelTag.length ? brand.modelTag : @"PB-1",
                   NSMakeRect(NSMinX(badge) + 4, NSMinY(badge) + 1, NSWidth(badge) - 22, 14),
                   [NSFont systemFontOfSize:9 weight:NSFontWeightBold],
                   [NSColor colorWithCalibratedWhite:0.78 alpha:1],
                   NSTextAlignmentCenter);
    [self drawStatusLEDAt:NSMakePoint(NSMaxX(badge) - 9, NSMidY(badge)) on:self.playing];

    // Plinth / kick plate
    NSRect plinth = NSMakeRect(10, h - 22, w - 20, 10);
    NSGradient *plinthG = [[NSGradient alloc] initWithColorsAndLocations:
                           [NSColor colorWithCalibratedWhite:0.14 alpha:1], 0.0,
                           [NSColor colorWithCalibratedWhite:0.05 alpha:1], 0.55,
                           [NSColor colorWithCalibratedWhite:0.09 alpha:1], 1.0, nil];
    [plinthG drawInRect:plinth angle:90];
    [[NSColor colorWithCalibratedWhite:0.4 alpha:0.25] set];
    NSRectFill(NSMakeRect(NSMinX(plinth), NSMinY(plinth), NSWidth(plinth), 1));
    [[NSColor colorWithCalibratedWhite:0.0 alpha:0.55] set];
    NSFrameRect(plinth);

    // Soft floor contact shadow under the tower
    [[NSColor colorWithCalibratedWhite:0 alpha:0.45] set];
    NSRectFill(NSMakeRect(14, h - 4, w - 28, 3));
    [[NSColor colorWithCalibratedWhite:0 alpha:0.22] set];
    NSRectFill(NSMakeRect(22, h - 2, w - 44, 2));

    // Rubber isolation feet (4)
    CGFloat footY = h - 14;
    CGFloat feetX[] = { 22, w * 0.35, w * 0.65, w - 34 };
    for (int i = 0; i < 4; i++) {
        NSRect foot = NSMakeRect(feetX[i], footY, 12, 7);
        [[NSColor colorWithCalibratedWhite:0 alpha:0.5] set];
        [[NSBezierPath bezierPathWithRoundedRect:NSOffsetRect(foot, 0, 1) xRadius:2 yRadius:2] fill];
        NSBezierPath *fp = [NSBezierPath bezierPathWithRoundedRect:foot xRadius:2 yRadius:2];
        NSGradient *fg = [[NSGradient alloc] initWithColorsAndLocations:
                          [NSColor colorWithCalibratedWhite:0.18 alpha:1], 0.0,
                          [NSColor colorWithCalibratedWhite:0.04 alpha:1], 0.65,
                          [NSColor colorWithCalibratedWhite:0.10 alpha:1], 1.0, nil];
        [fg drawInBezierPath:fp angle:90];
        [[NSColor colorWithCalibratedWhite:0.35 alpha:0.3] set];
        NSRectFill(NSMakeRect(NSMinX(foot) + 2, NSMinY(foot) + 1, NSWidth(foot) - 4, 1));
    }

    // Corner cabinet screws — keep clear of top nameplate / feet
    SKDrawScrew(NSMakePoint(12, 12), 3.0);
    SKDrawScrew(NSMakePoint(w - 12, 12), 3.0);
    SKDrawScrew(NSMakePoint(12, h - 28), 3.0);
    SKDrawScrew(NSMakePoint(w - 12, h - 28), 3.0);
}

@end
