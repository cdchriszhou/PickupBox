#import "DrawingHelpers.h"
#import "BrandProfile.h"

NSColor *SKAmberColor(void) {
    // 随当前面板主题变化的主发光色（经典琥珀 / 夜色 / 海浪 / 工作室）
    BrandProfile *b = [BrandProfile activeBrand];
    return b.accentColor ?: [NSColor colorWithCalibratedRed:1.0 green:0.62 blue:0.08 alpha:1.0];
}

NSColor *SKAmberDimColor(void) {
    BrandProfile *b = [BrandProfile activeBrand];
    return b.accentDimColor ?: [NSColor colorWithCalibratedRed:0.55 green:0.32 blue:0.05 alpha:1.0];
}

NSColor *SKPanelColor(void) {
    return [NSColor colorWithCalibratedRed:0.12 green:0.12 blue:0.125 alpha:1.0];
}

NSColor *SKMetalDarkColor(void) {
    return [NSColor colorWithCalibratedRed:0.08 green:0.08 blue:0.085 alpha:1.0];
}

NSColor *SKMetalMidColor(void) {
    return [NSColor colorWithCalibratedRed:0.22 green:0.22 blue:0.23 alpha:1.0];
}

NSColor *SKMetalLightColor(void) {
    return [NSColor colorWithCalibratedRed:0.38 green:0.38 blue:0.40 alpha:1.0];
}

NSColor *SKRedLEDColor(void) {
    return [NSColor colorWithCalibratedRed:1.0 green:0.18 blue:0.12 alpha:1.0];
}

void SKFillBrushedMetal(NSRect rect, CGFloat darkness) {
    // Cool steel base (slight blue-gray) — reads as real anodized / brushed aluminum
    CGFloat d = darkness;
    NSGradient *base = [[NSGradient alloc] initWithColorsAndLocations:
        [NSColor colorWithCalibratedRed:0.09+d*0.03 green:0.095+d*0.03 blue:0.11+d*0.035 alpha:1], 0.0,
        [NSColor colorWithCalibratedRed:0.17+d*0.04 green:0.175+d*0.04 blue:0.19+d*0.045 alpha:1], 0.22,
        [NSColor colorWithCalibratedRed:0.13+d*0.03 green:0.135+d*0.03 blue:0.15+d*0.035 alpha:1], 0.48,
        [NSColor colorWithCalibratedRed:0.21+d*0.05 green:0.215+d*0.05 blue:0.23+d*0.055 alpha:1], 0.72,
        [NSColor colorWithCalibratedRed:0.10+d*0.03 green:0.105+d*0.03 blue:0.12+d*0.035 alpha:1], 1.0,
        nil];
    [base drawInRect:rect angle:90.0];

    [[NSGraphicsContext currentContext] saveGraphicsState];
    [[NSBezierPath bezierPathWithRect:rect] addClip];

    // Primary horizontal brush (anisotropic)
    NSInteger idx = 0;
    for (CGFloat y = NSMinY(rect); y < NSMaxY(rect); y += 1.15, idx++) {
        NSInteger h = (idx * 47 + 13) % 17;
        CGFloat a = 0.010 + h * 0.0018;
        BOOL bright = (h % 5 == 0);
        [[NSColor colorWithCalibratedWhite:bright ? 0.82 : 0.55 alpha:a] set];
        NSRectFill(NSMakeRect(NSMinX(rect), y, NSWidth(rect), bright ? 0.7 : 0.45));
    }
    // Soft specular band across the face (overhead light)
    NSGradient *spec = [[NSGradient alloc] initWithColorsAndLocations:
                        [NSColor colorWithCalibratedWhite:1 alpha:0.0], 0.0,
                        [NSColor colorWithCalibratedWhite:1 alpha:0.07], 0.42,
                        [NSColor colorWithCalibratedWhite:1 alpha:0.0], 0.78, nil];
    [spec drawInRect:rect angle:78];

    // Left/right edge falloff — extruded panel depth
    NSGradient *side = [[NSGradient alloc] initWithColorsAndLocations:
                        [NSColor colorWithCalibratedWhite:0 alpha:0.22], 0.0,
                        [NSColor colorWithCalibratedWhite:0 alpha:0.0], 0.12,
                        [NSColor colorWithCalibratedWhite:0 alpha:0.0], 0.88,
                        [NSColor colorWithCalibratedWhite:0 alpha:0.28], 1.0, nil];
    [side drawInRect:rect angle:0];

    [[NSGraphicsContext currentContext] restoreGraphicsState];
}

void SKDrawInsetBevel(NSRect rect, CGFloat radius) {
    // Outer contact shadow
    NSBezierPath *shadow = [NSBezierPath bezierPathWithRoundedRect:NSOffsetRect(rect, 0, 0.8)
                                                           xRadius:radius yRadius:radius];
    [[NSColor colorWithCalibratedWhite:0 alpha:0.35] set];
    [shadow fill];

    NSBezierPath *path = [NSBezierPath bezierPathWithRoundedRect:rect xRadius:radius yRadius:radius];
    NSGradient *well = [[NSGradient alloc] initWithColorsAndLocations:
                        [NSColor colorWithCalibratedWhite:0.02 alpha:1], 0.0,
                        [NSColor colorWithCalibratedWhite:0.06 alpha:1], 0.55,
                        [NSColor colorWithCalibratedWhite:0.03 alpha:1], 1.0, nil];
    [well drawInBezierPath:path angle:90];

    // Inner face
    NSBezierPath *inner = [NSBezierPath bezierPathWithRoundedRect:NSInsetRect(rect, 1.2, 1.2)
                                                          xRadius:MAX(0, radius - 1)
                                                          yRadius:MAX(0, radius - 1)];
    [[NSColor colorWithCalibratedWhite:0.055 alpha:1.0] set];
    [inner fill];

    // Top lip (light catch into the recess) — MinY is top when flipped
    [[NSColor colorWithCalibratedWhite:0.0 alpha:0.65] set];
    NSRectFill(NSMakeRect(NSMinX(rect) + radius, NSMinY(rect) + 0.5, NSWidth(rect) - radius * 2, 1.0));
    // Bottom rim highlight
    [[NSColor colorWithCalibratedWhite:0.55 alpha:0.28] set];
    NSRectFill(NSMakeRect(NSMinX(rect) + radius, NSMaxY(rect) - 1.2, NSWidth(rect) - radius * 2, 1.0));
    // Side shadows
    [[NSColor colorWithCalibratedWhite:0 alpha:0.35] set];
    NSRectFill(NSMakeRect(NSMinX(rect) + 0.5, NSMinY(rect) + radius, 1.0, NSHeight(rect) - radius * 2));
    [[NSColor colorWithCalibratedWhite:0.4 alpha:0.12] set];
    NSRectFill(NSMakeRect(NSMaxX(rect) - 1.5, NSMinY(rect) + radius, 1.0, NSHeight(rect) - radius * 2));
}

void SKDrawRaisedBevel(NSRect rect, CGFloat radius) {
    // Drop shadow under raised plate
    [[NSColor colorWithCalibratedWhite:0 alpha:0.4] set];
    [[NSBezierPath bezierPathWithRoundedRect:NSOffsetRect(rect, 0, 1.4) xRadius:radius yRadius:radius] fill];

    // Chrome outer rim
    NSBezierPath *outer = [NSBezierPath bezierPathWithRoundedRect:rect xRadius:radius yRadius:radius];
    NSGradient *rim = [[NSGradient alloc] initWithColorsAndLocations:
                       [NSColor colorWithCalibratedWhite:0.48 alpha:1], 0.0,
                       [NSColor colorWithCalibratedWhite:0.22 alpha:1], 0.35,
                       [NSColor colorWithCalibratedWhite:0.10 alpha:1], 0.7,
                       [NSColor colorWithCalibratedWhite:0.32 alpha:1], 1.0, nil];
    [rim drawInBezierPath:outer angle:125];

    // Brushed face
    NSRect faceR = NSInsetRect(rect, 1.4, 1.4);
    NSBezierPath *face = [NSBezierPath bezierPathWithRoundedRect:faceR
                                                         xRadius:MAX(0, radius - 1)
                                                         yRadius:MAX(0, radius - 1)];
    [[NSGraphicsContext currentContext] saveGraphicsState];
    [face addClip];
    SKFillBrushedMetal(faceR, 0.08);
    // Top specular edge
    [[NSColor colorWithCalibratedWhite:1 alpha:0.22] set];
    NSRectFill(NSMakeRect(NSMinX(faceR) + 2, NSMinY(faceR) + 0.5, NSWidth(faceR) - 4, 1.1));
    [[NSGraphicsContext currentContext] restoreGraphicsState];

    [[NSColor colorWithCalibratedWhite:0.05 alpha:0.55] set];
    [face setLineWidth:0.8];
    [face stroke];
}

void SKDrawLEDBar(NSRect rect, CGFloat level, BOOL vertical) {
    level = MAX(0.0, MIN(1.0, level));
    [[NSColor colorWithCalibratedWhite:0.04 alpha:1.0] set];
    NSRectFill(rect);

    if (vertical) {
        CGFloat h = NSHeight(rect) * level;
        NSRect lit = NSMakeRect(NSMinX(rect), NSMinY(rect), NSWidth(rect), h);
        NSGradient *g = [[NSGradient alloc] initWithColors:@[
            [NSColor colorWithCalibratedRed:0.2 green:0.9 blue:0.2 alpha:1.0],
            SKAmberColor(),
            SKRedLEDColor()
        ]];
        [g drawInRect:lit angle:90.0];
    } else {
        CGFloat w = NSWidth(rect) * level;
        NSRect lit = NSMakeRect(NSMinX(rect), NSMinY(rect), w, NSHeight(rect));
        NSGradient *g = [[NSGradient alloc] initWithStartingColor:SKAmberDimColor()
                                                      endingColor:SKAmberColor()];
        [g drawInRect:lit angle:0.0];
    }
}

void SKDrawJewelLED(NSRect rect, NSColor *color, BOOL on) {
    // Chrome bezel cup
    NSBezierPath *rim = [NSBezierPath bezierPathWithOvalInRect:rect];
    NSGradient *bezel = [[NSGradient alloc] initWithColorsAndLocations:
                         [NSColor colorWithCalibratedWhite:0.55 alpha:1], 0.0,
                         [NSColor colorWithCalibratedWhite:0.22 alpha:1], 0.35,
                         [NSColor colorWithCalibratedWhite:0.06 alpha:1], 0.7,
                         [NSColor colorWithCalibratedWhite:0.38 alpha:1], 1.0, nil];
    [bezel drawInBezierPath:rim angle:140];

    // Recessed well under the lens
    NSRect well = NSInsetRect(rect, 1.2, 1.2);
    [[NSColor colorWithCalibratedWhite:0.02 alpha:1] set];
    [[NSBezierPath bezierPathWithOvalInRect:well] fill];

    NSRect face = NSInsetRect(rect, 1.8, 1.8);
    NSBezierPath *cap = [NSBezierPath bezierPathWithOvalInRect:face];
    if (on && color) {
        // Soft halo / scatter outside the cup
        [[color colorWithAlphaComponent:0.22] set];
        [[NSBezierPath bezierPathWithOvalInRect:NSInsetRect(rect, -3.5, -3.5)] fill];
        [[color colorWithAlphaComponent:0.4] set];
        [[NSBezierPath bezierPathWithOvalInRect:NSInsetRect(rect, -1.8, -1.8)] fill];

        // Domed lens body
        NSGradient *g = [[NSGradient alloc] initWithColorsAndLocations:
                         [color blendedColorWithFraction:0.55 ofColor:NSColor.whiteColor], 0.0,
                         color, 0.4,
                         [color blendedColorWithFraction:0.35 ofColor:NSColor.blackColor], 1.0, nil];
        [g drawInBezierPath:cap angle:125];

        // Fresnel / refractive ring inside the dome
        [[NSColor colorWithCalibratedWhite:1 alpha:0.28] set];
        NSBezierPath *fresnel = [NSBezierPath bezierPathWithOvalInRect:NSInsetRect(face, NSWidth(face) * 0.18, NSHeight(face) * 0.18)];
        [fresnel setLineWidth:MAX(0.8, NSWidth(face) * 0.08)];
        [fresnel stroke];

        // Hot caustic near center
        CGFloat hot = MAX(1.5, NSWidth(face) * 0.22);
        [[NSColor colorWithCalibratedWhite:1 alpha:0.55] set];
        [[NSBezierPath bezierPathWithOvalInRect:
          NSMakeRect(NSMinX(face) + NSWidth(face) * 0.22,
                     NSMinY(face) + NSHeight(face) * 0.18,
                     hot, hot * 0.75)] fill];
    } else {
        NSGradient *offG = [[NSGradient alloc] initWithColorsAndLocations:
                            [NSColor colorWithCalibratedWhite:0.18 alpha:1], 0.0,
                            [NSColor colorWithCalibratedWhite:0.08 alpha:1], 0.6,
                            [NSColor colorWithCalibratedWhite:0.12 alpha:1], 1.0, nil];
        [offG drawInBezierPath:cap angle:125];
        [[NSColor colorWithCalibratedWhite:1 alpha:0.1] set];
        [[NSBezierPath bezierPathWithOvalInRect:
          NSMakeRect(NSMinX(face) + 1.0, NSMinY(face) + 0.8, NSWidth(face) * 0.4, NSHeight(face) * 0.28)] fill];
    }

    // Glass rim catch-light
    [[NSColor colorWithCalibratedWhite:1 alpha:on ? 0.35 : 0.14] set];
    NSBezierPath *glassRim = [NSBezierPath bezierPathWithOvalInRect:NSInsetRect(face, 0.4, 0.4)];
    [glassRim setLineWidth:0.7];
    [glassRim stroke];
}

void SKDrawSegmentMeter(NSRect rect, CGFloat level, NSInteger segments, BOOL vertical) {
    level = MAX(0.0, MIN(1.0, level));
    segments = MAX(4, segments);
    SKDrawInsetBevel(rect, 2);
    NSRect well = NSInsetRect(rect, 3, 3);
    [[NSColor colorWithCalibratedWhite:0.02 alpha:1] set];
    NSRectFill(well);

    CGFloat gap = 1.5;
    NSInteger lit = (NSInteger)llround(level * segments);
    for (NSInteger i = 0; i < segments; i++) {
        NSRect seg;
        if (vertical) {
            CGFloat h = (NSHeight(well) - (segments - 1) * gap) / (CGFloat)segments;
            // Flipped AppKit views: MaxY is visual bottom — quiet grows upward from there
            seg = NSMakeRect(NSMinX(well),
                             NSMaxY(well) - (i + 1) * h - i * gap,
                             NSWidth(well), h);
        } else {
            CGFloat w = (NSWidth(well) - (segments - 1) * gap) / (CGFloat)segments;
            seg = NSMakeRect(NSMinX(well) + i * (w + gap), NSMinY(well), w, NSHeight(well));
        }
        BOOL on = (i < lit);
        CGFloat t = (CGFloat)i / (CGFloat)MAX(1, segments - 1);
        NSColor *c;
        if (t < 0.55) c = [NSColor colorWithCalibratedRed:0.15 green:0.85 blue:0.25 alpha:1];
        else if (t < 0.8) c = SKAmberColor();
        else c = SKRedLEDColor();
        if (on) {
            [c set];
            NSRectFill(seg);
            [[c colorWithAlphaComponent:0.35] set];
            NSRectFill(NSInsetRect(seg, -0.5, -0.5));
        } else {
            [[NSColor colorWithCalibratedWhite:0.10 alpha:1] set];
            NSRectFill(seg);
        }
    }
}

void SKDrawGlowText(NSString *text, NSRect rect, NSFont *font, NSColor *color, NSTextAlignment align) {
    NSMutableParagraphStyle *style = [[NSMutableParagraphStyle alloc] init];
    style.alignment = align;
    style.lineBreakMode = NSLineBreakByTruncatingTail;

    NSDictionary *glow = @{
        NSFontAttributeName: font,
        NSForegroundColorAttributeName: [color colorWithAlphaComponent:0.35],
        NSParagraphStyleAttributeName: style
    };
    NSDictionary *attrs = @{
        NSFontAttributeName: font,
        NSForegroundColorAttributeName: color,
        NSParagraphStyleAttributeName: style
    };

    NSRect glowRect = NSOffsetRect(rect, 0, -0.5);
    [text drawInRect:glowRect withAttributes:glow];
    [text drawInRect:rect withAttributes:attrs];
}

void SKDrawVentGrille(NSRect rect, BOOL vertical) {
    if (NSWidth(rect) < 4 || NSHeight(rect) < 4) return;
    // Recessed stamped plate
    [[NSColor colorWithCalibratedWhite:0.04 alpha:1] set];
    NSRectFill(rect);
    [[NSColor colorWithCalibratedWhite:0.0 alpha:0.55] set];
    NSFrameRect(rect);
    [[NSColor colorWithCalibratedWhite:0.4 alpha:0.18] set];
    NSFrameRect(NSInsetRect(rect, 0.5, 0.5));

    [[NSGraphicsContext currentContext] saveGraphicsState];
    [[NSBezierPath bezierPathWithRect:NSInsetRect(rect, 1.5, 1.5)] addClip];

    if (vertical) {
        CGFloat slotW = 2.2;
        CGFloat gap = 2.4;
        CGFloat x = NSMinX(rect) + 2.5;
        while (x + slotW < NSMaxX(rect) - 2) {
            NSRect slot = NSMakeRect(x, NSMinY(rect) + 3, slotW, NSHeight(rect) - 6);
            // Deep punched hole
            [[NSColor colorWithCalibratedWhite:0.0 alpha:0.85] set];
            NSRectFill(slot);
            // Inner lip highlight (right edge catches light)
            [[NSColor colorWithCalibratedWhite:0.45 alpha:0.22] set];
            NSRectFill(NSMakeRect(NSMaxX(slot) - 0.6, NSMinY(slot) + 1, 0.6, NSHeight(slot) - 2));
            [[NSColor colorWithCalibratedWhite:0.0 alpha:0.5] set];
            NSRectFill(NSMakeRect(NSMinX(slot), NSMinY(slot), 0.7, NSHeight(slot)));
            x += slotW + gap;
        }
    } else {
        CGFloat slotH = 2.0;
        CGFloat gap = 2.2;
        CGFloat y = NSMinY(rect) + 2.5;
        while (y + slotH < NSMaxY(rect) - 2) {
            NSRect slot = NSMakeRect(NSMinX(rect) + 3, y, NSWidth(rect) - 6, slotH);
            [[NSColor colorWithCalibratedWhite:0.0 alpha:0.85] set];
            NSRectFill(slot);
            [[NSColor colorWithCalibratedWhite:0.5 alpha:0.2] set];
            NSRectFill(NSMakeRect(NSMinX(slot) + 1, NSMinY(slot), NSWidth(slot) - 2, 0.5));
            y += slotH + gap;
        }
    }
    [[NSGraphicsContext currentContext] restoreGraphicsState];
}

void SKDrawScrew(NSPoint center, CGFloat radius) {
    [[NSColor colorWithCalibratedWhite:0 alpha:0.45] set];
    [[NSBezierPath bezierPathWithOvalInRect:
      NSMakeRect(center.x - radius, center.y - radius + 0.7, radius * 2, radius * 2)] fill];

    NSRect r = NSMakeRect(center.x - radius, center.y - radius, radius * 2, radius * 2);
    NSBezierPath *c = [NSBezierPath bezierPathWithOvalInRect:r];
    NSGradient *g = [[NSGradient alloc] initWithColorsAndLocations:
                     [NSColor colorWithCalibratedWhite:0.62 alpha:1], 0.0,
                     [NSColor colorWithCalibratedWhite:0.32 alpha:1], 0.4,
                     [NSColor colorWithCalibratedWhite:0.14 alpha:1], 0.85,
                     [NSColor colorWithCalibratedWhite:0.38 alpha:1], 1.0, nil];
    [g drawInBezierPath:c angle:140];

    [[NSColor colorWithCalibratedWhite:1 alpha:0.35] set];
    [[NSBezierPath bezierPathWithOvalInRect:
      NSMakeRect(center.x - radius * 0.45, center.y - radius * 0.55, radius * 0.7, radius * 0.45)] fill];

    // Phillips cross
    [[NSColor colorWithCalibratedWhite:0.04 alpha:0.85] set];
    CGFloat arm = radius * 0.55;
    CGFloat thick = MAX(0.9, radius * 0.28);
    NSRectFill(NSMakeRect(center.x - arm, center.y - thick * 0.5, arm * 2, thick));
    NSRectFill(NSMakeRect(center.x - thick * 0.5, center.y - arm, thick, arm * 2));
}

void SKDrawRackModule(NSRect rect, NSString *title, CGFloat darkness) {
    // Thick chassis shadow under the panel (rack gap depth)
    [[NSColor colorWithCalibratedWhite:0 alpha:0.55] set];
    NSRectFill(NSMakeRect(NSMinX(rect) + 1, NSMaxY(rect), NSWidth(rect) - 2, 3.5));
    [[NSColor colorWithCalibratedWhite:0.02 alpha:1] set];
    NSRectFill(NSMakeRect(NSMinX(rect) + 3, NSMaxY(rect) - 0.5, NSWidth(rect) - 6, 1.5));

    SKFillBrushedMetal(rect, darkness);

    // Extruded aluminum outer rail (2px lip)
    [[NSColor colorWithCalibratedWhite:0.55 alpha:0.32] set];
    NSFrameRect(NSInsetRect(rect, 1, 1));
    [[NSColor colorWithCalibratedWhite:0.28 alpha:0.4] set];
    NSFrameRect(NSInsetRect(rect, 0.5, 0.5));
    [[NSColor colorWithCalibratedWhite:0.0 alpha:0.82] set];
    NSFrameRect(rect);

    // Deep face well
    SKDrawInsetBevel(NSInsetRect(rect, 4, 4), 4);

    // Top edge catch-light (machined step)
    [[NSColor colorWithCalibratedWhite:0.85 alpha:0.32] set];
    NSRectFill(NSMakeRect(NSMinX(rect) + 6, NSMinY(rect) + 1.2, NSWidth(rect) - 12, 1.1));
    [[NSColor colorWithCalibratedWhite:0.55 alpha:0.14] set];
    NSRectFill(NSMakeRect(NSMinX(rect) + 8, NSMinY(rect) + 2.4, NSWidth(rect) - 16, 0.7));

    // Bottom return shadow (panel thickness)
    [[NSColor colorWithCalibratedWhite:0.0 alpha:0.7] set];
    NSRectFill(NSMakeRect(NSMinX(rect), NSMaxY(rect) - 2.2, NSWidth(rect), 2.2));
    [[NSColor colorWithCalibratedWhite:0.45 alpha:0.16] set];
    NSRectFill(NSMakeRect(NSMinX(rect) + 1, NSMaxY(rect) - 3.0, NSWidth(rect) - 2, 0.9));

    // Side cheek shadows — reads as 1U extrusion
    [[NSColor colorWithCalibratedWhite:0 alpha:0.22] set];
    NSRectFill(NSMakeRect(NSMinX(rect) + 1, NSMinY(rect) + 4, 1.5, NSHeight(rect) - 8));
    [[NSColor colorWithCalibratedWhite:0.55 alpha:0.08] set];
    NSRectFill(NSMakeRect(NSMaxX(rect) - 2.5, NSMinY(rect) + 4, 1.5, NSHeight(rect) - 8));

    if (title.length) {
        SKDrawGlowText(title,
                       NSMakeRect(NSMinX(rect) + 18, NSMinY(rect) + 5, NSWidth(rect) - 36, 12),
                       [NSFont systemFontOfSize:9 weight:NSFontWeightBold],
                       [NSColor colorWithCalibratedWhite:0.68 alpha:1],
                       NSTextAlignmentLeft);
    }

    SKDrawScrew(NSMakePoint(NSMinX(rect) + 11, NSMinY(rect) + 11), 2.8);
    SKDrawScrew(NSMakePoint(NSMaxX(rect) - 11, NSMinY(rect) + 11), 2.8);
    SKDrawScrew(NSMakePoint(NSMinX(rect) + 11, NSMaxY(rect) - 11), 2.8);
    SKDrawScrew(NSMakePoint(NSMaxX(rect) - 11, NSMaxY(rect) - 11), 2.8);
}

void SKDrawVFDScreen(NSRect rect) {
    // Chrome instrument bezel
    NSBezierPath *outer = [NSBezierPath bezierPathWithRoundedRect:rect xRadius:3 yRadius:3];
    NSGradient *bezel = [[NSGradient alloc] initWithColorsAndLocations:
                         [NSColor colorWithCalibratedWhite:0.5 alpha:1], 0.0,
                         [NSColor colorWithCalibratedWhite:0.18 alpha:1], 0.4,
                         [NSColor colorWithCalibratedWhite:0.07 alpha:1], 0.75,
                         [NSColor colorWithCalibratedWhite:0.34 alpha:1], 1.0, nil];
    [bezel drawInBezierPath:outer angle:125];

    SKDrawInsetBevel(NSInsetRect(rect, 2, 2), 2.5);
    NSRect inner = NSInsetRect(rect, 5, 5);
    NSGradient *g = [[NSGradient alloc] initWithColorsAndLocations:
                     [NSColor colorWithCalibratedRed:0.04 green:0.025 blue:0.01 alpha:1], 0.0,
                     [NSColor colorWithCalibratedRed:0.085 green:0.05 blue:0.018 alpha:1], 0.5,
                     [NSColor colorWithCalibratedRed:0.03 green:0.02 blue:0.008 alpha:1], 1.0, nil];
    [g drawInRect:inner angle:90];

    // Soft glass reflection
    [[NSColor colorWithCalibratedWhite:1 alpha:0.045] set];
    NSRectFill(NSMakeRect(NSMinX(inner), NSMinY(inner), NSWidth(inner), NSHeight(inner) * 0.2));

    // Dot matrix grid
    [[NSColor colorWithCalibratedRed:0.45 green:0.22 blue:0.05 alpha:0.18] set];
    for (CGFloat y = NSMinY(inner) + 4; y < NSMaxY(inner); y += 4) {
        for (CGFloat x = NSMinX(inner) + 4; x < NSMaxX(inner); x += 4) {
            NSRectFill(NSMakeRect(x, y, 1.2, 1.2));
        }
    }
}

static void SKFillVFDSeg(NSRect r, BOOL on, NSColor *color) {
    if (NSWidth(r) < 0.5 || NSHeight(r) < 0.5) return;
    NSBezierPath *p = [NSBezierPath bezierPathWithRoundedRect:r xRadius:1.1 yRadius:1.1];
    if (on) {
        [[color colorWithAlphaComponent:0.22] set];
        [[NSBezierPath bezierPathWithRoundedRect:NSInsetRect(r, -1.2, -1.2) xRadius:2 yRadius:2] fill];
        [color set];
        [p fill];
    } else {
        [[color colorWithAlphaComponent:0.10] set];
        [p fill];
    }
}

void SKDrawVFDDigit(NSRect rect, NSInteger digit, NSColor *color) {
    // Classic 7-seg bit order: a b c d e f g
    static const uint8_t map[10] = {
        0x3F, 0x06, 0x5B, 0x4F, 0x66, 0x6D, 0x7D, 0x07, 0x7F, 0x6F
    };
    uint8_t bits = (digit >= 0 && digit <= 9) ? map[digit] : 0x00;
    NSColor *c = color ?: SKAmberColor();

    CGFloat w = NSWidth(rect);
    CGFloat h = NSHeight(rect);
    CGFloat t = MAX(1.15, MIN(w, h) * 0.13); // thinner for compact clock/date
    CGFloat inset = 0.6;
    CGFloat x = NSMinX(rect) + inset;
    CGFloat y = NSMinY(rect) + inset;
    w -= inset * 2;
    h -= inset * 2;
    CGFloat midY = y + h * 0.5 - t * 0.5;

    // a (top) b (upper-right) c (lower-right) d (bottom) e (lower-left) f (upper-left) g (middle)
    SKFillVFDSeg(NSMakeRect(x + t * 0.6, y, w - t * 1.2, t), bits & 0x01, c);                 // a
    SKFillVFDSeg(NSMakeRect(x + w - t, y + t * 0.5, t, h * 0.5 - t * 0.7), bits & 0x02, c);  // b
    SKFillVFDSeg(NSMakeRect(x + w - t, midY + t * 0.6, t, h * 0.5 - t * 0.7), bits & 0x04, c); // c
    SKFillVFDSeg(NSMakeRect(x + t * 0.6, y + h - t, w - t * 1.2, t), bits & 0x08, c);         // d
    SKFillVFDSeg(NSMakeRect(x, midY + t * 0.6, t, h * 0.5 - t * 0.7), bits & 0x10, c);       // e
    SKFillVFDSeg(NSMakeRect(x, y + t * 0.5, t, h * 0.5 - t * 0.7), bits & 0x20, c);          // f
    SKFillVFDSeg(NSMakeRect(x + t * 0.6, midY, w - t * 1.2, t), bits & 0x40, c);             // g
}

static void SKDrawVFDColonOrDash(NSRect slot, unichar ch, NSColor *c, CGFloat digitH) {
    CGFloat dot = MAX(1.6, MIN(NSWidth(slot), digitH) * 0.22);
    CGFloat cx = NSMidX(slot) - dot * 0.5;
    CGFloat y = NSMinY(slot);
    if (ch == ':') {
        NSRect upper = NSMakeRect(cx, y + digitH * 0.28, dot, dot);
        NSRect lower = NSMakeRect(cx, y + digitH * 0.62, dot, dot);
        [[c colorWithAlphaComponent:0.22] set];
        [[NSBezierPath bezierPathWithOvalInRect:NSInsetRect(upper, -0.8, -0.8)] fill];
        [[NSBezierPath bezierPathWithOvalInRect:NSInsetRect(lower, -0.8, -0.8)] fill];
        [c set];
        [[NSBezierPath bezierPathWithOvalInRect:upper] fill];
        [[NSBezierPath bezierPathWithOvalInRect:lower] fill];
    } else if (ch == '-' || ch == '.') {
        CGFloat barH = MAX(1.4, digitH * 0.12);
        NSRect bar = NSMakeRect(NSMinX(slot) + 1, y + digitH * 0.5 - barH * 0.5,
                                NSWidth(slot) - 2, barH);
        if (ch == '.') {
            bar = NSMakeRect(cx, y + digitH * 0.72, dot, dot);
            [c set];
            [[NSBezierPath bezierPathWithOvalInRect:bar] fill];
        } else {
            SKFillVFDSeg(bar, YES, c);
        }
    }
}

void SKDrawVFDPattern(NSRect rect, NSString *pattern, NSColor *color, NSTextAlignment align) {
    if (pattern.length == 0 || NSWidth(rect) < 4 || NSHeight(rect) < 4) return;
    NSColor *c = color ?: SKAmberColor();
    CGFloat h = NSHeight(rect);
    CGFloat dh = h * 0.94;

    // Measure relative widths: digit=1, sep=0.32, gap=0.10
    CGFloat units = 0;
    for (NSUInteger i = 0; i < pattern.length; i++) {
        unichar ch = [pattern characterAtIndex:i];
        if (ch >= '0' && ch <= '9') units += 1.0;
        else if (ch == ':' || ch == '-' || ch == '.') units += 0.32;
        else units += 0.5; // space / unknown
        if (i + 1 < pattern.length) units += 0.10;
    }
    CGFloat unitW = MIN(NSWidth(rect) / MAX(units, 0.01), dh * 0.62);
    CGFloat digitW = unitW;
    CGFloat sepW = unitW * 0.32;
    CGFloat gap = unitW * 0.10;
    CGFloat totalW = units * unitW;
    CGFloat x;
    if (align == NSTextAlignmentLeft) x = NSMinX(rect);
    else if (align == NSTextAlignmentCenter) x = NSMinX(rect) + (NSWidth(rect) - totalW) * 0.5;
    else x = NSMaxX(rect) - totalW;
    CGFloat y = NSMinY(rect) + (h - dh) * 0.5;

    for (NSUInteger i = 0; i < pattern.length; i++) {
        unichar ch = [pattern characterAtIndex:i];
        if (ch >= '0' && ch <= '9') {
            SKDrawVFDDigit(NSMakeRect(x, y, digitW, dh), ch - '0', c);
            x += digitW;
        } else if (ch == ':' || ch == '-' || ch == '.') {
            SKDrawVFDColonOrDash(NSMakeRect(x, y, sepW, dh), ch, c, dh);
            x += sepW;
        } else {
            x += digitW * 0.5;
        }
        if (i + 1 < pattern.length) x += gap;
    }
}

void SKDrawVFDTime(NSRect rect, NSInteger totalSeconds, NSColor *color, NSTextAlignment align) {
    NSInteger sec = MAX(0, totalSeconds);
    NSInteger mm = sec / 60;
    NSInteger ss = sec % 60;
    if (mm > 99) mm = 99;
    NSString *pat = [NSString stringWithFormat:@"%02ld:%02ld", (long)mm, (long)ss];
    SKDrawVFDPattern(rect, pat, color, align);
}
