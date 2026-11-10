#import "MediaPanelView.h"
#import "DrawingHelpers.h"

@implementation MediaPanelView {
    NSTimer *_timer;
    CGFloat _radarPhase;
    CGFloat _localScroll;
    CGFloat _radioScroll;
    CGFloat _lyricsScroll;
    NSInteger _lyricsFocus;
    NSRect _listContentRect;
    NSRect _lyricsContentRect;
}

- (instancetype)initWithFrame:(NSRect)frameRect {
    self = [super initWithFrame:frameRect];
    if (self) {
        _selectedTab = MediaPanelTabCover;
        _titleText = @"成都经济广播";
        _subtitleText = @"FM 106.3  ·  拾音盒子";
        _localTracks = @[];
        _radioStations = @[];
        _selectedLocalIndex = 0;
        _selectedRadioIndex = 0;
        _localScroll = 0;
        _radioScroll = 0;
        _lyricsScroll = 0;
        _lyricsFocus = -1;
        _lyricsLines = @[];
        _lyricsStatus = @"播放本地歌曲后自动搜索歌词";
        _timer = [NSTimer scheduledTimerWithTimeInterval:1.0 / 20.0
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

- (void)tick {
    _radarPhase += 0.08;
    if (self.selectedTab == MediaPanelTabCover || self.selectedTab == MediaPanelTabLyrics) {
        [self setNeedsDisplay:YES];
    }
}

- (void)clearLyrics {
    self.lyricsLines = @[];
    self.lyricsStatus = @"播放本地歌曲后自动搜索歌词";
    self.lyricsSource = nil;
    self.lyricsTime = 0;
    _lyricsScroll = 0;
    _lyricsFocus = -1;
    [self setNeedsDisplay:YES];
}

- (void)setLyricsLines:(NSArray<LyricsLine *> *)lyricsLines {
    _lyricsLines = lyricsLines ?: @[];
    _lyricsScroll = 0;
    _lyricsFocus = -1;
    [self setNeedsDisplay:YES];
}

- (void)setLyricsStatus:(NSString *)lyricsStatus {
    _lyricsStatus = [lyricsStatus copy];
    [self setNeedsDisplay:YES];
}

- (void)setLyricsTime:(NSTimeInterval)lyricsTime {
    _lyricsTime = lyricsTime;
    if (self.selectedTab == MediaPanelTabLyrics) {
        [self syncLyricsScrollToTime];
    }
}

- (NSInteger)lyricsIndexForTime:(NSTimeInterval)t {
    if (self.lyricsLines.count == 0) return -1;
    NSInteger idx = 0;
    for (NSInteger i = 0; i < (NSInteger)self.lyricsLines.count; i++) {
        if (self.lyricsLines[i].time <= t + 0.05) idx = i;
        else break;
    }
    return idx;
}

- (void)syncLyricsScrollToTime {
    NSInteger idx = [self lyricsIndexForTime:self.lyricsTime];
    if (idx < 0 || idx == _lyricsFocus) return;
    _lyricsFocus = idx;
    CGFloat rowH = 22;
    CGFloat viewH = MAX(40, NSHeight(_lyricsContentRect));
    CGFloat target = idx * rowH - viewH * 0.38;
    CGFloat maxScroll = MAX(0, self.lyricsLines.count * rowH - viewH);
    _lyricsScroll = MAX(0, MIN(maxScroll, target));
}

- (void)setLocalTracks:(NSArray<RadioStation *> *)localTracks {
    _localTracks = localTracks ?: @[];
    _localScroll = 0;
    [self setNeedsDisplay:YES];
}

- (void)setRadioStations:(NSArray<RadioStation *> *)radioStations {
    _radioStations = radioStations ?: @[];
    _radioScroll = 0;
    [self setNeedsDisplay:YES];
}

- (void)setSelectedLocalIndex:(NSInteger)selectedLocalIndex {
    _selectedLocalIndex = selectedLocalIndex;
    [self ensureSelectionVisible];
    [self setNeedsDisplay:YES];
}

- (void)setSelectedRadioIndex:(NSInteger)selectedRadioIndex {
    _selectedRadioIndex = selectedRadioIndex;
    [self ensureSelectionVisible];
    [self setNeedsDisplay:YES];
}

- (void)setSelectedTab:(MediaPanelTab)selectedTab {
    _selectedTab = selectedTab;
    [self ensureSelectionVisible];
    [self setNeedsDisplay:YES];
}

- (void)reloadStationList {
    _localScroll = 0;
    _radioScroll = 0;
    [self setNeedsDisplay:YES];
}

- (NSArray<RadioStation *> *)activeList {
    if (self.selectedTab == MediaPanelTabLocal) return self.localTracks;
    if (self.selectedTab == MediaPanelTabRadio) return self.radioStations;
    return @[];
}

- (NSInteger)activeSelectedIndex {
    if (self.selectedTab == MediaPanelTabLocal) return self.selectedLocalIndex;
    if (self.selectedTab == MediaPanelTabRadio) return self.selectedRadioIndex;
    return 0;
}

- (CGFloat *)activeScrollPtr {
    if (self.selectedTab == MediaPanelTabLocal) return &_localScroll;
    return &_radioScroll;
}

- (void)ensureSelectionVisible {
    NSArray *list = [self activeList];
    if (list.count == 0) return;
    if (self.selectedTab != MediaPanelTabLocal && self.selectedTab != MediaPanelTabRadio) return;

    CGFloat rowH = 22;
    CGFloat headerH = 24;
    NSInteger sel = [self activeSelectedIndex];
    CGFloat y = headerH + sel * rowH;
    CGFloat viewH = MAX(40, NSHeight(_listContentRect) - 4);
    if (NSIsEmptyRect(_listContentRect)) return;
    CGFloat *scroll = [self activeScrollPtr];
    if (y < *scroll) *scroll = y;
    if (y + rowH > *scroll + viewH) *scroll = y + rowH - viewH;
    *scroll = MAX(0, *scroll);
}

- (NSArray<NSValue *> *)tabFrames {
    NSArray *titles = @[@"封面", @"清单", @"电台", @"歌词"];
    CGFloat x = 8;
    CGFloat gap = 3;
    CGFloat tabW = 46;
    // Fit four tabs before DOLBY badge
    CGFloat avail = NSWidth(self.bounds) - 118 - 8;
    if (avail > 40) {
        tabW = MIN(52, MAX(40, (avail - (titles.count - 1) * gap) / (CGFloat)titles.count));
    }
    NSMutableArray *arr = [NSMutableArray array];
    for (NSInteger i = 0; i < (NSInteger)titles.count; i++) {
        [arr addObject:[NSValue valueWithRect:NSMakeRect(x + i * (tabW + gap), 8, tabW, 22)]];
    }
    return arr;
}

- (void)setCoverImage:(NSImage *)coverImage {
    _coverImage = coverImage;
    [self setNeedsDisplay:YES];
}

- (void)drawCoverInRect:(NSRect)art {
    NSBezierPath *path = [NSBezierPath bezierPathWithRoundedRect:art xRadius:4 yRadius:4];
    [[NSGraphicsContext currentContext] saveGraphicsState];
    [path addClip];

    if (self.coverImage) {
        [[NSColor colorWithCalibratedWhite:0.02 alpha:1] set];
        NSRectFill(art);
        NSSize isz = self.coverImage.size;
        if (isz.width < 1 || isz.height < 1) isz = NSMakeSize(1, 1);
        CGFloat scale = MAX(NSWidth(art) / isz.width, NSHeight(art) / isz.height);
        CGFloat dw = isz.width * scale;
        CGFloat dh = isz.height * scale;
        NSRect dest = NSMakeRect(NSMidX(art) - dw * 0.5, NSMidY(art) - dh * 0.5, dw, dh);
        [self.coverImage drawInRect:dest
                           fromRect:NSZeroRect
                          operation:NSCompositingOperationSourceOver
                           fraction:1.0
                     respectFlipped:YES
                              hints:@{NSImageHintInterpolation: @(NSImageInterpolationHigh)}];
        NSGradient *scrim = [[NSGradient alloc] initWithStartingColor:[NSColor colorWithCalibratedWhite:0 alpha:0]
                                                          endingColor:[NSColor colorWithCalibratedWhite:0 alpha:0.72]];
        [scrim drawInRect:NSMakeRect(NSMinX(art), NSMaxY(art) - 56, NSWidth(art), 56) angle:90];
        SKDrawGlowText(self.titleText ?: @"",
                       NSMakeRect(NSMinX(art) + 10, NSMaxY(art) - 40, NSWidth(art) - 20, 18),
                       [NSFont systemFontOfSize:13 weight:NSFontWeightBold],
                       [NSColor colorWithCalibratedWhite:0.95 alpha:1],
                       NSTextAlignmentCenter);
        SKDrawGlowText(self.subtitleText ?: @"",
                       NSMakeRect(NSMinX(art) + 10, NSMaxY(art) - 22, NSWidth(art) - 20, 14),
                       [NSFont systemFontOfSize:10 weight:NSFontWeightMedium],
                       [NSColor colorWithCalibratedWhite:0.8 alpha:0.9],
                       NSTextAlignmentCenter);
        [[NSGraphicsContext currentContext] restoreGraphicsState];
        return;
    }

    NSGradient *g = [[NSGradient alloc] initWithColorsAndLocations:
                     [NSColor colorWithCalibratedRed:0.55 green:0.42 blue:0.08 alpha:1], 0.0,
                     [NSColor colorWithCalibratedRed:0.12 green:0.35 blue:0.18 alpha:1], 0.55,
                     [NSColor colorWithCalibratedRed:0.05 green:0.12 blue:0.08 alpha:1], 1.0, nil];
    [g drawInBezierPath:path angle:135];

    NSPoint c = NSMakePoint(NSMidX(art), NSMidY(art) + 8);
    for (int i = 1; i <= 4; i++) {
        CGFloat rr = 12 + i * 14 + fmod(_radarPhase * 10, 14);
        NSBezierPath *ring = [NSBezierPath bezierPathWithOvalInRect:
                              NSMakeRect(c.x - rr, c.y - rr, rr * 2, rr * 2)];
        [[NSColor colorWithCalibratedRed:0.9 green:0.75 blue:0.2 alpha:0.18] set];
        [ring setLineWidth:1];
        [ring stroke];
    }
    NSBezierPath *sweep = [NSBezierPath bezierPath];
    [sweep moveToPoint:c];
    CGFloat a = _radarPhase;
    [sweep appendBezierPathWithArcWithCenter:c radius:70 startAngle:a * 180 / M_PI endAngle:(a + 0.6) * 180 / M_PI clockwise:NO];
    [sweep closePath];
    [[NSColor colorWithCalibratedRed:1 green:0.85 blue:0.3 alpha:0.12] set];
    [sweep fill];

    SKDrawGlowText(self.titleText ?: @"",
                   NSMakeRect(NSMinX(art), NSMinY(art) + 18, NSWidth(art), 28),
                   [NSFont systemFontOfSize:20 weight:NSFontWeightBold],
                   [NSColor colorWithCalibratedRed:1 green:0.9 blue:0.55 alpha:1],
                   NSTextAlignmentCenter);
    SKDrawGlowText(self.subtitleText ?: @"",
                   NSMakeRect(NSMinX(art), NSMinY(art) + 48, NSWidth(art), 18),
                   [NSFont systemFontOfSize:11 weight:NSFontWeightMedium],
                   [NSColor colorWithCalibratedWhite:0.85 alpha:0.9],
                   NSTextAlignmentCenter);
    [[NSGraphicsContext currentContext] restoreGraphicsState];
}

- (void)drawLyricsInRect:(NSRect)inner {
    [[NSColor colorWithCalibratedWhite:0.035 alpha:1] set];
    NSRectFill(inner);
    _lyricsContentRect = NSInsetRect(inner, 0, 0);

    NSString *header = self.lyricsSource.length
        ? [NSString stringWithFormat:@"歌词  ·  %@", self.lyricsSource]
        : @"歌词";
    SKDrawGlowText(header,
                   NSMakeRect(NSMinX(inner) + 8, NSMinY(inner) + 4, NSWidth(inner) - 16, 14),
                   [NSFont systemFontOfSize:10 weight:NSFontWeightBold],
                   SKAmberColor(), NSTextAlignmentLeft);

    CGFloat headerH = 22;
    NSRect clip = NSMakeRect(NSMinX(inner), NSMinY(inner) + headerH,
                             NSWidth(inner), NSHeight(inner) - headerH - 2);
    _lyricsContentRect = clip;

    if (self.lyricsLines.count == 0) {
        SKDrawGlowText(self.lyricsStatus ?: @"暂无歌词",
                       NSMakeRect(NSMinX(clip) + 12, NSMidY(clip) - 10, NSWidth(clip) - 24, 20),
                       [NSFont systemFontOfSize:12 weight:NSFontWeightMedium],
                       [NSColor colorWithCalibratedWhite:0.55 alpha:1],
                       NSTextAlignmentCenter);
        return;
    }

    [self syncLyricsScrollToTime];
    NSInteger focus = [self lyricsIndexForTime:self.lyricsTime];

    [[NSGraphicsContext currentContext] saveGraphicsState];
    [NSBezierPath clipRect:clip];
    CGFloat rowH = 22;
    for (NSInteger i = 0; i < (NSInteger)self.lyricsLines.count; i++) {
        CGFloat y = NSMinY(clip) + i * rowH - _lyricsScroll;
        if (y + rowH < NSMinY(clip) || y > NSMaxY(clip)) continue;
        NSRect row = NSMakeRect(NSMinX(clip) + 6, y, NSWidth(clip) - 12, rowH);
        BOOL on = (i == focus);
        if (on) {
            NSBezierPath *bg = [NSBezierPath bezierPathWithRoundedRect:NSInsetRect(row, 2, 1)
                                                               xRadius:3 yRadius:3];
            [[NSColor colorWithCalibratedRed:0.35 green:0.18 blue:0.04 alpha:0.55] set];
            [bg fill];
            [[SKAmberColor() colorWithAlphaComponent:0.35] set];
            [bg setLineWidth:0.8];
            [bg stroke];
        }
        NSString *text = self.lyricsLines[i].text ?: @"";
        SKDrawGlowText(text, NSInsetRect(row, 6, 2),
                       [NSFont systemFontOfSize:on ? 13 : 11
                                         weight:on ? NSFontWeightBold : NSFontWeightRegular],
                       on ? SKAmberColor() : [NSColor colorWithCalibratedWhite:0.62 alpha:1],
                       NSTextAlignmentCenter);
    }
    [[NSGraphicsContext currentContext] restoreGraphicsState];
}

- (void)drawList:(NSArray<RadioStation *> *)stations
           title:(NSString *)title
       emptyHint:(NSString *)emptyHint
   selectedIndex:(NSInteger)selectedIndex
          scroll:(CGFloat)scroll
          inRect:(NSRect)inner
   showFrequency:(BOOL)showFrequency {
    [[NSColor colorWithCalibratedWhite:0.04 alpha:1] set];
    NSRectFill(inner);
    _listContentRect = inner;

    NSString *header = [NSString stringWithFormat:@"%@  ·  %lu",
                        title ?: @"", (unsigned long)stations.count];
    SKDrawGlowText(header,
                   NSMakeRect(NSMinX(inner) + 8, NSMinY(inner) + 4, NSWidth(inner) - 16, 16),
                   [NSFont systemFontOfSize:11 weight:NSFontWeightBold],
                   SKAmberColor(), NSTextAlignmentLeft);

    if (stations.count == 0) {
        SKDrawGlowText(emptyHint ?: @"暂无内容",
                       NSMakeRect(NSMinX(inner) + 10, NSMidY(inner) - 8, NSWidth(inner) - 20, 18),
                       [NSFont systemFontOfSize:12 weight:NSFontWeightMedium],
                       [NSColor colorWithCalibratedWhite:0.55 alpha:1],
                       NSTextAlignmentCenter);
        return;
    }

    CGFloat rowH = 22;
    CGFloat headerH = 24;
    CGFloat listTop = NSMinY(inner) + headerH;
    CGFloat listH = NSMaxY(inner) - listTop - 4;
    NSRect clip = NSMakeRect(NSMinX(inner), listTop, NSWidth(inner), listH);

    [[NSGraphicsContext currentContext] saveGraphicsState];
    [[NSBezierPath bezierPathWithRect:clip] addClip];

    CGFloat contentH = stations.count * rowH;
    CGFloat maxScroll = MAX(0, contentH - listH);
    scroll = MAX(0, MIN(maxScroll, scroll));
    if (self.selectedTab == MediaPanelTabLocal) _localScroll = scroll;
    else if (self.selectedTab == MediaPanelTabRadio) _radioScroll = scroll;

    for (NSUInteger i = 0; i < stations.count; i++) {
        CGFloat y = listTop + i * rowH - scroll;
        if (y + rowH < listTop || y > NSMaxY(clip)) continue;

        RadioStation *s = stations[i];
        BOOL on = ((NSInteger)i == selectedIndex);
        NSRect row = NSMakeRect(NSMinX(inner) + 4, y, NSWidth(inner) - 8, rowH - 1);
        if (on) {
            [[NSColor colorWithCalibratedRed:0.35 green:0.18 blue:0.04 alpha:0.85] set];
            [[NSBezierPath bezierPathWithRoundedRect:row xRadius:3 yRadius:3] fill];
        } else if (i % 2 == 1) {
            [[NSColor colorWithCalibratedWhite:1 alpha:0.03] set];
            NSRectFill(row);
        }

        NSString *line = [NSString stringWithFormat:@"%02lu  %@", (unsigned long)(i + 1), s.name ?: @"—"];
        CGFloat textW = showFrequency ? NSWidth(row) - 70 : NSWidth(row) - 12;
        if (line.length > 36) line = [[line substringToIndex:35] stringByAppendingString:@"…"];
        SKDrawGlowText(line,
                       NSMakeRect(NSMinX(row) + 6, NSMinY(row) + 2, textW, 16),
                       [NSFont systemFontOfSize:11 weight:on ? NSFontWeightBold : NSFontWeightMedium],
                       on ? SKAmberColor() : [NSColor colorWithCalibratedWhite:0.78 alpha:1],
                       NSTextAlignmentLeft);

        if (showFrequency) {
            NSString *mhz = s.frequency > 0 ? [NSString stringWithFormat:@"%.1f", s.frequency] : @"";
            SKDrawGlowText(mhz,
                           NSMakeRect(NSMaxX(row) - 58, NSMinY(row) + 2, 50, 16),
                           [NSFont monospacedDigitSystemFontOfSize:10 weight:NSFontWeightMedium],
                           on ? SKAmberColor() : [NSColor colorWithCalibratedWhite:0.5 alpha:1],
                           NSTextAlignmentRight);
        }
    }

    [[NSGraphicsContext currentContext] restoreGraphicsState];

    if (maxScroll > 1) {
        SKDrawGlowText(@"滚轮浏览",
                       NSMakeRect(NSMaxX(inner) - 58, NSMinY(inner) + 4, 50, 12),
                       [NSFont systemFontOfSize:8 weight:NSFontWeightMedium],
                       [NSColor colorWithCalibratedWhite:0.4 alpha:1],
                       NSTextAlignmentRight);
    }
}

- (void)drawRect:(NSRect)dirtyRect {
    NSRect bounds = self.bounds;
    SKFillBrushedMetal(bounds, 0.02);
    SKDrawInsetBevel(NSInsetRect(bounds, 2, 2), 4);

    NSRect dolby = NSMakeRect(NSWidth(bounds) - 108, 8, 96, 18);
    SKDrawRaisedBevel(dolby, 2);
    // Tiny engraved screws on DOLBY badge
    SKDrawScrew(NSMakePoint(NSMinX(dolby) + 6, NSMidY(dolby)), 1.5);
    SKDrawScrew(NSMakePoint(NSMaxX(dolby) - 6, NSMidY(dolby)), 1.5);
    SKDrawGlowText(@"DOLBY B-C NR",
                   NSInsetRect(dolby, 10, 2),
                   [NSFont systemFontOfSize:9 weight:NSFontWeightBold],
                   [NSColor colorWithCalibratedWhite:0.78 alpha:1],
                   NSTextAlignmentCenter);

    NSArray *titles = @[@"封面", @"清单", @"电台", @"歌词"];
    NSArray *frames = [self tabFrames];
    for (NSInteger i = 0; i < (NSInteger)titles.count; i++) {
        NSRect r = [frames[i] rectValue];
        BOOL on = (self.selectedTab == i);
        if (on) {
            NSBezierPath *p = [NSBezierPath bezierPathWithRoundedRect:r xRadius:3 yRadius:3];
            NSGradient *g = [[NSGradient alloc] initWithColorsAndLocations:
                             [NSColor colorWithCalibratedWhite:0.28 alpha:1], 0.0,
                             [NSColor colorWithCalibratedWhite:0.12 alpha:1], 1.0, nil];
            [g drawInBezierPath:p angle:90];
            [[SKAmberColor() colorWithAlphaComponent:0.95] set];
            NSRectFill(NSMakeRect(NSMinX(r) + 6, NSMaxY(r) - 2.2, NSWidth(r) - 12, 2.2));
            [[NSColor colorWithCalibratedWhite:1 alpha:0.12] set];
            NSRectFill(NSMakeRect(NSMinX(r) + 4, NSMinY(r) + 1, NSWidth(r) - 8, 1));
        } else {
            SKDrawRaisedBevel(r, 3);
        }
        SKDrawGlowText(titles[i], NSInsetRect(r, 0, 3),
                       [NSFont systemFontOfSize:10 weight:NSFontWeightSemibold],
                       on ? SKAmberColor() : [NSColor colorWithCalibratedWhite:0.7 alpha:1],
                       NSTextAlignmentCenter);
    }

    NSRect content = NSMakeRect(10, 36, NSWidth(bounds) - 20, NSHeight(bounds) - 68);
    // Chrome lip around media glass
    NSBezierPath *contentOuter = [NSBezierPath bezierPathWithRoundedRect:content xRadius:3 yRadius:3];
    NSGradient *cBezel = [[NSGradient alloc] initWithColorsAndLocations:
                          [NSColor colorWithCalibratedWhite:0.42 alpha:1], 0.0,
                          [NSColor colorWithCalibratedWhite:0.14 alpha:1], 0.5,
                          [NSColor colorWithCalibratedWhite:0.28 alpha:1], 1.0, nil];
    [cBezel drawInBezierPath:contentOuter angle:125];
    SKDrawInsetBevel(NSInsetRect(content, 2, 2), 2);
    NSRect inner = NSInsetRect(content, 4, 4);

    if (self.selectedTab == MediaPanelTabCover) {
        [self drawCoverInRect:inner];
    } else if (self.selectedTab == MediaPanelTabLocal) {
        [self drawList:self.localTracks
                 title:@"本地曲目"
             emptyHint:@"EJECT 装载 MP3 后显示在此"
         selectedIndex:self.selectedLocalIndex
                scroll:_localScroll
                inRect:inner
         showFrequency:NO];
    } else if (self.selectedTab == MediaPanelTabRadio) {
        NSString *city = self.radioCityName.length ? self.radioCityName : @"地区频率";
        [self drawList:self.radioStations
                 title:city
             emptyHint:@"暂无电台 · 请选择城市或稍候搜索"
         selectedIndex:self.selectedRadioIndex
                scroll:_radioScroll
                inRect:inner
         showFrequency:YES];
    } else if (self.selectedTab == MediaPanelTabLyrics) {
        [self drawLyricsInRect:inner];
    }

    SKDrawGlowText(self.titleText ?: @"",
                   NSMakeRect(12, NSHeight(bounds) - 28, NSWidth(bounds) - 24, 12),
                   [NSFont systemFontOfSize:11 weight:NSFontWeightBold],
                   [NSColor colorWithCalibratedWhite:0.85 alpha:1],
                   NSTextAlignmentCenter);
    SKDrawGlowText(self.subtitleText ?: @"EJECT 导入歌曲",
                   NSMakeRect(12, NSHeight(bounds) - 16, NSWidth(bounds) - 24, 10),
                   [NSFont systemFontOfSize:9 weight:NSFontWeightMedium],
                   [NSColor colorWithCalibratedWhite:0.55 alpha:1],
                   NSTextAlignmentCenter);
}

- (NSInteger)listIndexAtPoint:(NSPoint)p {
    NSArray *list = [self activeList];
    if (list.count == 0) return -1;
    if (self.selectedTab != MediaPanelTabLocal && self.selectedTab != MediaPanelTabRadio) return -1;
    CGFloat rowH = 22;
    CGFloat headerH = 24;
    CGFloat listTop = NSMinY(_listContentRect) + headerH;
    if (p.y < listTop || p.y > NSMaxY(_listContentRect)) return -1;
    CGFloat scroll = (self.selectedTab == MediaPanelTabLocal) ? _localScroll : _radioScroll;
    NSInteger idx = (NSInteger)((p.y - listTop + scroll) / rowH);
    if (idx < 0 || idx >= (NSInteger)list.count) return -1;
    return idx;
}

- (void)mouseDown:(NSEvent *)event {
    NSPoint p = [self convertPoint:event.locationInWindow fromView:nil];
    NSArray *frames = [self tabFrames];
    for (NSInteger i = 0; i < (NSInteger)frames.count; i++) {
        if (NSPointInRect(p, [frames[i] rectValue])) {
            self.selectedTab = (MediaPanelTab)i;
            return;
        }
    }
    if (self.selectedTab == MediaPanelTabLocal || self.selectedTab == MediaPanelTabRadio) {
        NSInteger idx = [self listIndexAtPoint:p];
        if (idx >= 0) {
            if (self.selectedTab == MediaPanelTabLocal) {
                self.selectedLocalIndex = idx;
                if (self.onSelectLocalAtIndex) self.onSelectLocalAtIndex(idx);
            } else {
                self.selectedRadioIndex = idx;
                if (self.onSelectRadioAtIndex) self.onSelectRadioAtIndex(idx);
            }
            [self setNeedsDisplay:YES];
        }
    }
}

- (void)scrollWheel:(NSEvent *)event {
    if (self.selectedTab == MediaPanelTabLyrics) {
        if (self.lyricsLines.count == 0) return;
        CGFloat rowH = 22;
        CGFloat listH = MAX(40, NSHeight(_lyricsContentRect));
        CGFloat maxScroll = MAX(0, self.lyricsLines.count * rowH - listH);
        _lyricsScroll -= event.scrollingDeltaY;
        _lyricsScroll = MAX(0, MIN(maxScroll, _lyricsScroll));
        [self setNeedsDisplay:YES];
        return;
    }
    if (self.selectedTab != MediaPanelTabLocal && self.selectedTab != MediaPanelTabRadio) return;
    NSArray *list = [self activeList];
    if (list.count == 0) return;
    CGFloat *scroll = [self activeScrollPtr];
    *scroll -= event.scrollingDeltaY;
    CGFloat rowH = 22;
    CGFloat headerH = 24;
    CGFloat listH = MAX(40, NSHeight(_listContentRect) - headerH - 4);
    CGFloat maxScroll = MAX(0, list.count * rowH - listH);
    *scroll = MAX(0, MIN(maxScroll, *scroll));
    [self setNeedsDisplay:YES];
}

@end
