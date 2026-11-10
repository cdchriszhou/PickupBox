#import "WorldTunerView.h"
#import "DrawingHelpers.h"
#import "RadioBrowserService.h"

#pragma mark - Hi-Fi city picker（级联并排：父菜单 + 右侧子菜单同时可见）

static const CGFloat kCityRowH = 24.0;
static const CGFloat kCityColW = 168.0;

@interface SKCityColumnView : NSView
@property (nonatomic, copy) NSArray<NSDictionary *> *rows;
@property (nonatomic, assign) NSInteger hoverIndex;
@property (nonatomic, assign) NSInteger activeFolderIndex; // 当前展开的 folder 行，-1 无
@property (nonatomic, assign) CGFloat scrollY;
@property (nonatomic, assign) CGFloat maxScroll;
@property (nonatomic, copy, nullable) void (^onActivate)(NSDictionary *row, NSInteger index);
@end

@implementation SKCityColumnView

- (BOOL)isFlipped { return YES; }

- (instancetype)initWithFrame:(NSRect)frameRect {
    self = [super initWithFrame:frameRect];
    if (self) {
        _hoverIndex = -1;
        _activeFolderIndex = -1;
        _rows = @[];
    }
    return self;
}

- (void)setRows:(NSArray<NSDictionary *> *)rows {
    _rows = [rows copy] ?: @[];
    _scrollY = 0;
    _hoverIndex = -1;
    [self setNeedsDisplay:YES];
}

- (void)recomputeScroll {
    CGFloat content = self.rows.count * kCityRowH + 8;
    self.maxScroll = MAX(0, content - NSHeight(self.bounds));
    self.scrollY = MAX(0, MIN(self.scrollY, self.maxScroll));
}

- (NSInteger)rowAtPoint:(NSPoint)p {
    CGFloat y = p.y + self.scrollY - 4;
    if (y < 0) return -1;
    NSInteger idx = (NSInteger)(y / kCityRowH);
    if (idx < 0 || idx >= (NSInteger)self.rows.count) return -1;
    return idx;
}

- (void)drawRect:(NSRect)dirtyRect {
    NSRect b = self.bounds;
    NSBezierPath *outer = [NSBezierPath bezierPathWithRoundedRect:b xRadius:4 yRadius:4];
    NSGradient *bezel = [[NSGradient alloc] initWithColorsAndLocations:
                         [NSColor colorWithCalibratedWhite:0.36 alpha:1], 0.0,
                         [NSColor colorWithCalibratedWhite:0.09 alpha:1], 0.5,
                         [NSColor colorWithCalibratedWhite:0.16 alpha:1], 1.0, nil];
    [bezel drawInBezierPath:outer angle:125];
    NSRect glass = NSInsetRect(b, 3, 3);
    [[NSColor colorWithCalibratedRed:0.04 green:0.03 blue:0.02 alpha:1] set];
    NSRectFill(glass);

    [self recomputeScroll];
    [[NSGraphicsContext currentContext] saveGraphicsState];
    [NSBezierPath clipRect:glass];

    for (NSInteger i = 0; i < (NSInteger)self.rows.count; i++) {
        NSDictionary *row = self.rows[i];
        NSString *type = row[@"type"] ?: @"";
        NSRect rowR = NSMakeRect(NSMinX(glass) + 3,
                                 NSMinY(glass) + 4 + i * kCityRowH - self.scrollY,
                                 NSWidth(glass) - 6, kCityRowH - 1);
        if (NSMaxY(rowR) < NSMinY(glass) || NSMinY(rowR) > NSMaxY(glass)) continue;

        BOOL hover = (i == self.hoverIndex);
        BOOL folderOpen = (i == self.activeFolderIndex);
        BOOL selected = [row[@"selected"] boolValue];

        if (hover || folderOpen) {
            [[SKAmberColor() colorWithAlphaComponent:folderOpen ? 0.32 : 0.22] set];
            [[NSBezierPath bezierPathWithRoundedRect:rowR xRadius:2 yRadius:2] fill];
        } else if (selected) {
            [[SKAmberColor() colorWithAlphaComponent:0.16] set];
            [[NSBezierPath bezierPathWithRoundedRect:rowR xRadius:2 yRadius:2] fill];
        }

        NSColor *tc = (hover || folderOpen || selected)
            ? SKAmberColor()
            : [SKAmberColor() colorWithAlphaComponent:0.88];
        NSString *title = row[@"title"] ?: @"";
        if ([type isEqualToString:@"folder"]) title = [title stringByAppendingString:@"  ›"];
        SKDrawGlowText(title,
                       NSMakeRect(NSMinX(rowR) + 5, NSMinY(rowR) + 3, NSWidth(rowR) - 10, 16),
                       [NSFont systemFontOfSize:11 weight:NSFontWeightSemibold],
                       tc, NSTextAlignmentLeft);
    }
    [[NSGraphicsContext currentContext] restoreGraphicsState];
    [SKAmberColor() set];
    [outer setLineWidth:1];
    [outer stroke];
}

- (void)mouseMoved:(NSEvent *)event {
    NSPoint p = [self convertPoint:event.locationInWindow fromView:nil];
    NSInteger idx = [self rowAtPoint:p];
    if (idx != self.hoverIndex) {
        self.hoverIndex = idx;
        [self setNeedsDisplay:YES];
    }
}

- (void)mouseDown:(NSEvent *)event {
    NSPoint p = [self convertPoint:event.locationInWindow fromView:nil];
    NSInteger idx = [self rowAtPoint:p];
    if (idx < 0 || idx >= (NSInteger)self.rows.count) return;
    if (self.onActivate) self.onActivate(self.rows[idx], idx);
}

- (void)scrollWheel:(NSEvent *)event {
    self.scrollY -= event.scrollingDeltaY;
    [self recomputeScroll];
    [self setNeedsDisplay:YES];
}

- (void)updateTrackingAreas {
    [super updateTrackingAreas];
    for (NSTrackingArea *a in self.trackingAreas) [self removeTrackingArea:a];
    [self addTrackingArea:[[NSTrackingArea alloc] initWithRect:self.bounds
                                                       options:(NSTrackingMouseMoved | NSTrackingActiveInKeyWindow | NSTrackingInVisibleRect)
                                                         owner:self userInfo:nil]];
}

@end

@interface SKCityPickerView : NSView
@property (nonatomic, copy, nullable) NSString *selectedCityName;
@property (nonatomic, copy, nullable) void (^onPickCity)(NSString *nameCN);
@property (nonatomic, copy, nullable) void (^onFrameNeedsUpdate)(NSSize size);
@property (nonatomic, strong) SKCityColumnView *col0;
@property (nonatomic, strong) SKCityColumnView *col1;
@property (nonatomic, strong) SKCityColumnView *col2;
@property (nonatomic, copy, nullable) NSString *openFolder0; // china | overseas
@property (nonatomic, copy, nullable) NSString *openFolder1; // japan | world
@end

@implementation SKCityPickerView

- (BOOL)isFlipped { return YES; }

- (NSArray *)rootRows {
    BOOL sfOn = [self.selectedCityName isEqualToString:@"旧金山"];
    return @[
        @{ @"type": @"city", @"title": @"环球精选", @"city": @"旧金山", @"selected": @(sfOn) },
        @{ @"type": @"folder", @"title": @"国内", @"folder": @"china",
           @"selected": @([self.openFolder0 isEqualToString:@"china"]) },
        @{ @"type": @"folder", @"title": @"海外", @"folder": @"overseas",
           @"selected": @([self.openFolder0 isEqualToString:@"overseas"]) },
    ];
}

- (NSArray *)overseasRows {
    return @[
        @{ @"type": @"folder", @"title": @"日本", @"folder": @"japan",
           @"selected": @([self.openFolder1 isEqualToString:@"japan"]) },
        @{ @"type": @"folder", @"title": @"世界各地", @"folder": @"world",
           @"selected": @([self.openFolder1 isEqualToString:@"world"]) },
    ];
}

- (NSArray *)cityRowsForRegion:(RadioRegion)region {
    NSMutableArray *rows = [NSMutableArray array];
    for (RadioCity *c in [[RadioCatalog shared] citiesForRegion:region]) {
        BOOL on = [self.selectedCityName isEqualToString:c.nameCN];
        [rows addObject:@{
            @"type": @"city",
            @"title": [NSString stringWithFormat:@"%@  %@", c.nameCN, c.nameEN],
            @"city": c.nameCN ?: @"",
            @"selected": @(on),
        }];
    }
    return rows;
}

- (instancetype)initWithFrame:(NSRect)frameRect {
    self = [super initWithFrame:frameRect];
    if (self) {
        __weak SKCityPickerView *weakSelf = self;
        _col0 = [[SKCityColumnView alloc] initWithFrame:NSZeroRect];
        _col1 = [[SKCityColumnView alloc] initWithFrame:NSZeroRect];
        _col2 = [[SKCityColumnView alloc] initWithFrame:NSZeroRect];
        _col1.hidden = YES;
        _col2.hidden = YES;
        [self addSubview:_col0];
        [self addSubview:_col1];
        [self addSubview:_col2];

        _col0.onActivate = ^(NSDictionary *row, NSInteger index) {
            [weakSelf handleColumn:0 row:row index:index];
        };
        _col1.onActivate = ^(NSDictionary *row, NSInteger index) {
            [weakSelf handleColumn:1 row:row index:index];
        };
        _col2.onActivate = ^(NSDictionary *row, NSInteger index) {
            [weakSelf handleColumn:2 row:row index:index];
        };
        [self reloadAll];
    }
    return self;
}

- (void)reloadAll {
    self.col0.rows = [self rootRows];
    // restore active folder highlight
    if ([self.openFolder0 isEqualToString:@"china"]) self.col0.activeFolderIndex = 1;
    else if ([self.openFolder0 isEqualToString:@"overseas"]) self.col0.activeFolderIndex = 2;
    else self.col0.activeFolderIndex = -1;

    if ([self.openFolder0 isEqualToString:@"china"]) {
        self.col1.hidden = NO;
        self.col1.rows = [self cityRowsForRegion:RadioRegionChina];
        self.col1.activeFolderIndex = -1;
        self.col2.hidden = YES;
        self.col2.rows = @[];
        self.openFolder1 = nil;
    } else if ([self.openFolder0 isEqualToString:@"overseas"]) {
        self.col1.hidden = NO;
        self.col1.rows = [self overseasRows];
        if ([self.openFolder1 isEqualToString:@"japan"]) self.col1.activeFolderIndex = 0;
        else if ([self.openFolder1 isEqualToString:@"world"]) self.col1.activeFolderIndex = 1;
        else self.col1.activeFolderIndex = -1;

        if ([self.openFolder1 isEqualToString:@"japan"]) {
            self.col2.hidden = NO;
            self.col2.rows = [self cityRowsForRegion:RadioRegionJapan];
        } else if ([self.openFolder1 isEqualToString:@"world"]) {
            self.col2.hidden = NO;
            self.col2.rows = [self cityRowsForRegion:RadioRegionWorld];
        } else {
            self.col2.hidden = YES;
            self.col2.rows = @[];
        }
    } else {
        self.col1.hidden = YES;
        self.col1.rows = @[];
        self.col2.hidden = YES;
        self.col2.rows = @[];
        self.openFolder1 = nil;
    }
    [self layoutColumns];
}

- (NSInteger)visibleColumnCount {
    NSInteger n = 1;
    if (!self.col1.hidden) n++;
    if (!self.col2.hidden) n++;
    return n;
}

- (CGFloat)preferredHeight {
    NSInteger maxRows = (NSInteger)self.col0.rows.count;
    if (!self.col1.hidden) maxRows = MAX(maxRows, (NSInteger)self.col1.rows.count);
    if (!self.col2.hidden) maxRows = MAX(maxRows, (NSInteger)self.col2.rows.count);
    return MIN(320, MAX(120, maxRows * kCityRowH + 16));
}

- (NSSize)preferredSize {
    return NSMakeSize(kCityColW * [self visibleColumnCount] + 6, [self preferredHeight]);
}

- (void)positionColumns {
    // 用当前 bounds 高度排版；尺寸变更由外层面板负责，避免 setFrame ↔ 回调死循环
    CGFloat h = MAX(NSHeight(self.bounds), [self preferredHeight]);
    CGFloat x = 3;
    self.col0.frame = NSMakeRect(x, 3, kCityColW, h - 6);
    x += kCityColW;
    if (!self.col1.hidden) {
        self.col1.frame = NSMakeRect(x, 3, kCityColW, h - 6);
        x += kCityColW;
    }
    if (!self.col2.hidden) {
        self.col2.frame = NSMakeRect(x, 3, kCityColW, h - 6);
    }
    [self.col0 setNeedsDisplay:YES];
    [self.col1 setNeedsDisplay:YES];
    [self.col2 setNeedsDisplay:YES];
}

- (void)layoutColumns {
    NSSize sz = [self preferredSize];
    [self positionColumns];
    if (self.onFrameNeedsUpdate && !NSEqualSizes(self.bounds.size, sz)) {
        self.onFrameNeedsUpdate(sz);
    }
}

- (void)setFrameSize:(NSSize)newSize {
    [super setFrameSize:newSize];
    [self positionColumns]; // 勿再触发 onFrameNeedsUpdate
}

- (void)handleColumn:(NSInteger)col row:(NSDictionary *)row index:(NSInteger)index {
    NSString *type = row[@"type"] ?: @"";
    if ([type isEqualToString:@"city"]) {
        NSString *name = row[@"city"];
        if (name.length && self.onPickCity) self.onPickCity(name);
        return;
    }
    if (![type isEqualToString:@"folder"]) return;
    NSString *folder = row[@"folder"] ?: @"";

    if (col == 0) {
        if ([folder isEqualToString:self.openFolder0]) {
            // 再点一次收起
            self.openFolder0 = nil;
            self.openFolder1 = nil;
        } else {
            self.openFolder0 = folder;
            self.openFolder1 = nil;
        }
        [self reloadAll];
        return;
    }
    if (col == 1 && [self.openFolder0 isEqualToString:@"overseas"]) {
        if ([folder isEqualToString:self.openFolder1]) {
            self.openFolder1 = nil;
        } else {
            self.openFolder1 = folder;
        }
        [self reloadAll];
    }
}

@end

@implementation WorldTunerView {
    NSArray<RadioStation *> *_stations;
    NSInteger _stationIndex;
    BOOL _draggingScale;
    BOOL _menuOpen;
    NSInteger _hotControl; // 1 prev 2 next 3 city 4 power
    NSPanel *_cityPanel;
    id _cityClickMonitor;
}

- (instancetype)initWithFrame:(NSRect)frameRect {
    self = [super initWithFrame:frameRect];
    if (self) {
        _region = RadioRegionChina;
        _frequency = 106.3;
        _statusText = @"SELECT CITY";
        _stations = @[];
        _stationIndex = 0;
        _powerOn = YES;
        _hotControl = -1;
        RadioCity *cd = [[RadioCatalog shared] cityNamed:@"成都"];
        if (cd) {
            _selectedCity = cd;
            _frequency = cd.defaultFrequency;
        }
    }
    return self;
}

- (BOOL)isFlipped { return YES; }

- (void)setPowerOn:(BOOL)powerOn {
    if (_powerOn == powerOn) return;
    _powerOn = powerOn;
    [self setNeedsDisplay:YES];
}

#pragma mark - Public API

- (void)setRegion:(RadioRegion)region {
    [self applyRegion:region selectFirstCity:NO];
}

- (void)applyRegion:(RadioRegion)region selectFirstCity:(BOOL)selectFirst {
    _region = region;
    if (selectFirst) {
        NSArray *cities = [[RadioCatalog shared] citiesForRegion:region];
        if (cities.count) [self selectCity:cities.firstObject reload:YES];
    }
    [self setNeedsDisplay:YES];
}

- (void)selectCity:(RadioCity *)city reload:(BOOL)reload {
    if (!city) return;
    self.selectedCity = city;
    self.region = city.region;
    self.frequency = city.defaultFrequency;
    self.statusText = [NSString stringWithFormat:@"%@  ·  TUNING…", city.nameCN];
    self.loading = YES;
    self.tuned = NO;
    _stationIndex = 0;
    [self setNeedsDisplay:YES];
    if (self.onCitySelected) self.onCitySelected(city);
    if (!reload) return;

    __weak WorldTunerView *weakSelf = self;
    [[RadioBrowserService shared] fetchStationsForCity:city completion:^(NSArray<RadioStation *> *stations, NSError *error) {
        (void)error;
        if (weakSelf.selectedCity != city) return;
        [weakSelf setStations:stations];
        weakSelf.loading = NO;
        weakSelf.tuned = stations.count > 0;
        weakSelf.stereo = stations.count > 0;
        if (stations.count) {
            weakSelf.statusText = [NSString stringWithFormat:@"%@  ·  %lu", city.nameCN, (unsigned long)stations.count];
            [weakSelf pickStationAtIndex:0];
        } else {
            weakSelf.statusText = [NSString stringWithFormat:@"%@  ·  NO SIGNAL", city.nameCN];
            [weakSelf setNeedsDisplay:YES];
        }
    }];
}

- (NSArray<RadioStation *> *)stations { return _stations ?: @[]; }
- (NSInteger)stationIndex { return _stationIndex; }

- (void)setStations:(NSArray<RadioStation *> *)stations {
    _stations = stations ?: @[];
    _stationIndex = 0;
    [self setNeedsDisplay:YES];
    if (self.onStationsUpdated) self.onStationsUpdated(self.stations, _stationIndex);
}

- (void)pickStationAtIndex:(NSInteger)idx {
    if (idx < 0 || idx >= (NSInteger)_stations.count) return;
    _stationIndex = idx;
    RadioStation *station = _stations[idx];
    self.selectedStation = station;
    self.frequency = station.frequency > 0 ? station.frequency : self.frequency;
    self.statusText = station.name;
    self.tuned = YES;
    self.stereo = YES;
    [self setNeedsDisplay:YES];
    if (self.onStationsUpdated) self.onStationsUpdated(self.stations, _stationIndex);
    if (self.powerOn && self.onStationSelected) self.onStationSelected(station);
}

- (void)selectPreviousStation {
    if (_stations.count == 0) return;
    NSInteger idx = (_stationIndex - 1 + (NSInteger)_stations.count) % (NSInteger)_stations.count;
    [self pickStationAtIndex:idx];
}

- (void)selectNextStation {
    if (_stations.count == 0) return;
    NSInteger idx = (_stationIndex + 1) % (NSInteger)_stations.count;
    [self pickStationAtIndex:idx];
}

#pragma mark - Layout frames

- (NSRect)scaleRect {
    // Leave a clear control strip under the dial so PREV/CITY never sit inside the scale
    CGFloat left = 12;
    CGFloat right = 164; // meters + power
    CGFloat top = 18;
    CGFloat bottomReserve = 56;
    CGFloat h = MAX(40, NSHeight(self.bounds) - top - bottomReserve);
    return NSMakeRect(left, top, NSWidth(self.bounds) - left - right, h);
}
- (NSRect)prevBtnFrame {
    CGFloat y = NSMaxY([self scaleRect]) + 10;
    return NSMakeRect(12, y, 30, 28);
}
- (NSRect)nextBtnFrame {
    CGFloat y = NSMaxY([self scaleRect]) + 10;
    return NSMakeRect(46, y, 30, 28);
}
- (NSRect)cityBtnFrame {
    CGFloat y = NSMaxY([self scaleRect]) + 10;
    return NSMakeRect(84, y, 96, 28);
}
- (NSRect)meterBox {
    NSRect scale = [self scaleRect];
    CGFloat h = MIN(56, MAX(44, NSHeight(scale) - 4));
    // Wide enough for TUNED/STEREO + signal bars, clear of power switch
    return NSMakeRect(NSWidth(self.bounds) - 156, NSMinY(scale) + (NSHeight(scale) - h) * 0.5, 104, h);
}
- (NSRect)powerFrame {
    NSRect scale = [self scaleRect];
    return NSMakeRect(NSWidth(self.bounds) - 42, NSMidY(scale) - 14, 28, 28);
}

#pragma mark - Drawing

- (void)drawSkipIconInRect:(NSRect)r next:(BOOL)next hot:(BOOL)hot {
    SKDrawRaisedBevel(r, 4);
    if (hot) {
        [[NSColor colorWithCalibratedWhite:1 alpha:0.08] set];
        NSRectFill(NSInsetRect(r, 1, 1));
    }
    // Icon in upper half; caption inside the key so nothing is clipped outside
    NSColor *c = SKAmberColor();
    [c set];
    CGFloat cx = NSMidX(r), cy = NSMinY(r) + 11;
    NSBezierPath *p = [NSBezierPath bezierPath];
    if (next) {
        [p moveToPoint:NSMakePoint(cx - 6, cy - 5)];
        [p lineToPoint:NSMakePoint(cx - 6, cy + 5)];
        [p lineToPoint:NSMakePoint(cx + 2, cy)];
        [p closePath];
        [p fill];
        NSRectFill(NSMakeRect(cx + 3.5, cy - 5, 2.2, 10));
    } else {
        NSRectFill(NSMakeRect(cx - 5.5, cy - 5, 2.2, 10));
        [p moveToPoint:NSMakePoint(cx + 6, cy - 5)];
        [p lineToPoint:NSMakePoint(cx + 6, cy + 5)];
        [p lineToPoint:NSMakePoint(cx - 2, cy)];
        [p closePath];
        [p fill];
    }
    SKDrawGlowText(next ? @"NEXT" : @"PREV",
                   NSMakeRect(NSMinX(r), NSMaxY(r) - 11, NSWidth(r), 9),
                   [NSFont systemFontOfSize:7 weight:NSFontWeightBold],
                   [NSColor colorWithCalibratedWhite:0.7 alpha:1],
                   NSTextAlignmentCenter);
}

- (void)drawCityButton:(NSRect)r {
    BOOL hot = (_hotControl == 3) || _menuOpen;
    if (_menuOpen) {
        NSBezierPath *p = [NSBezierPath bezierPathWithRoundedRect:r xRadius:4 yRadius:4];
        [[NSColor colorWithCalibratedRed:0.35 green:0.18 blue:0.04 alpha:1] set];
        [p fill];
        [SKAmberColor() set];
        [p setLineWidth:1];
        [p stroke];
    } else {
        SKDrawRaisedBevel(r, 4);
        if (hot) {
            [[NSColor colorWithCalibratedWhite:1 alpha:0.06] set];
            NSRectFill(NSInsetRect(r, 1, 1));
        }
    }
    // Show selected city name on the CITY key — 已选地区用金色字
    BOOL hasCity = self.selectedCity.nameCN.length > 0;
    NSString *label = hasCity ? self.selectedCity.nameCN : @"CITY";
    if (label.length > 5) label = [[label substringToIndex:4] stringByAppendingString:@"…"];
    NSColor *labelColor = (_menuOpen || hasCity)
        ? SKAmberColor()
        : [NSColor colorWithCalibratedWhite:0.9 alpha:1];
    SKDrawGlowText(label,
                   NSMakeRect(NSMinX(r) + 2, NSMidY(r) - 7, NSWidth(r) - 16, 14),
                   [NSFont systemFontOfSize:(label.length > 3 ? 10 : 11) weight:NSFontWeightBold],
                   labelColor,
                   NSTextAlignmentCenter);
    // Chevron
    NSBezierPath *ch = [NSBezierPath bezierPath];
    CGFloat cx = NSMaxX(r) - 10, cy = NSMidY(r);
    [ch moveToPoint:NSMakePoint(cx - 4, cy - 2)];
    [ch lineToPoint:NSMakePoint(cx, cy + 3)];
    [ch lineToPoint:NSMakePoint(cx + 4, cy - 2)];
    NSColor *chevron = (_menuOpen || hasCity)
        ? SKAmberColor()
        : [NSColor colorWithCalibratedWhite:0.7 alpha:1];
    [chevron set];
    [ch setLineWidth:1.5];
    [ch stroke];
}

- (void)drawPowerSwitch:(NSRect)r {
    SKDrawRaisedBevel(r, 3);
    // Recessed well under the jewel
    NSRect well = NSInsetRect(r, 4, 4);
    [[NSColor colorWithCalibratedWhite:0.02 alpha:1] set];
    [[NSBezierPath bezierPathWithOvalInRect:well] fill];
    NSRect knob = NSInsetRect(r, 6, 6);
    NSColor *onC = [NSColor colorWithCalibratedRed:0.25 green:0.9 blue:0.4 alpha:1];
    NSColor *offC = [NSColor colorWithCalibratedWhite:0.22 alpha:1];
    SKDrawJewelLED(knob, onC, self.powerOn);
    if (!self.powerOn) {
        [offC set];
        [[NSBezierPath bezierPathWithOvalInRect:knob] fill];
        [[NSColor colorWithCalibratedWhite:0.45 alpha:0.25] set];
        [[NSBezierPath bezierPathWithOvalInRect:NSInsetRect(knob, 2, 3)] fill];
    }
    SKDrawGlowText(self.powerOn ? @"ON" : @"OFF",
                   NSMakeRect(NSMinX(r) - 4, NSMaxY(r) + 2, NSWidth(r) + 8, 10),
                   [NSFont systemFontOfSize:7 weight:NSFontWeightBold],
                   self.powerOn ? SKAmberColor() : [NSColor colorWithCalibratedWhite:0.45 alpha:1],
                   NSTextAlignmentCenter);
}

- (void)drawRect:(NSRect)dirtyRect {
    NSRect bounds = self.bounds;
    SKFillBrushedMetal(bounds, 0.06);

    SKDrawGlowText(@"FM/AM  QUARTZ LOCK  SYNTHESIZER TUNER",
                   NSMakeRect(12, 4, 320, 10),
                   [NSFont systemFontOfSize:8 weight:NSFontWeightBold],
                   [NSColor colorWithCalibratedWhite:0.58 alpha:1],
                   NSTextAlignmentLeft);

    // Frequency scale — backlit when radio ON, dimmed when OFF / MP3 takeover
    NSRect scale = [self scaleRect];
    BOOL lit = self.powerOn;
    if (lit) {
        // Soft amber backlight bloom behind the glass
        [[NSColor colorWithCalibratedRed:1.0 green:0.72 blue:0.25 alpha:0.18] set];
        [[NSBezierPath bezierPathWithRoundedRect:NSInsetRect(scale, -3, -3) xRadius:4 yRadius:4] fill];
        [[NSColor colorWithCalibratedRed:1.0 green:0.85 blue:0.45 alpha:0.12] set];
        [[NSBezierPath bezierPathWithRoundedRect:NSInsetRect(scale, -6, -5) xRadius:5 yRadius:5] fill];
    }
    // Chrome dial bezel around the frequency glass
    NSBezierPath *scaleOuter = [NSBezierPath bezierPathWithRoundedRect:scale xRadius:3 yRadius:3];
    NSGradient *dialBezel = [[NSGradient alloc] initWithColorsAndLocations:
                             [NSColor colorWithCalibratedWhite:0.5 alpha:1], 0.0,
                             [NSColor colorWithCalibratedWhite:0.18 alpha:1], 0.4,
                             [NSColor colorWithCalibratedWhite:0.08 alpha:1], 0.75,
                             [NSColor colorWithCalibratedWhite:0.34 alpha:1], 1.0, nil];
    [dialBezel drawInBezierPath:scaleOuter angle:125];
    SKDrawInsetBevel(NSInsetRect(scale, 2.2, 2.2), 2);
    NSRect inner = NSInsetRect(scale, 4, 4);
    if (lit) {
        NSGradient *ivory = [[NSGradient alloc] initWithColorsAndLocations:
                             [NSColor colorWithCalibratedRed:1.0 green:0.96 blue:0.78 alpha:1], 0.0,
                             [NSColor colorWithCalibratedRed:0.98 green:0.90 blue:0.55 alpha:1], 0.45,
                             [NSColor colorWithCalibratedRed:0.92 green:0.82 blue:0.48 alpha:1], 1.0, nil];
        [ivory drawInRect:inner angle:90];
        // Edge light strip (fluorescent tube feel)
        [[NSColor colorWithCalibratedRed:1.0 green:0.92 blue:0.55 alpha:0.55] set];
        NSRectFill(NSMakeRect(NSMinX(inner), NSMinY(inner), NSWidth(inner), 2.5));
        [[NSColor colorWithCalibratedRed:1.0 green:0.85 blue:0.35 alpha:0.2] set];
        NSRectFill(NSMakeRect(NSMinX(inner), NSMinY(inner) + 2.5, NSWidth(inner), 6));
        // Glass specular stripe
        [[NSColor colorWithCalibratedWhite:1 alpha:0.12] set];
        NSRectFill(NSMakeRect(NSMinX(inner), NSMinY(inner) + NSHeight(inner) * 0.12,
                              NSWidth(inner), NSHeight(inner) * 0.08));
    } else {
        NSGradient *dim = [[NSGradient alloc] initWithColorsAndLocations:
                           [NSColor colorWithCalibratedWhite:0.22 alpha:1], 0.0,
                           [NSColor colorWithCalibratedWhite:0.12 alpha:1], 0.55,
                           [NSColor colorWithCalibratedWhite:0.08 alpha:1], 1.0, nil];
        [dim drawInRect:inner angle:90];
    }

    NSFont *markFont = [NSFont monospacedDigitSystemFontOfSize:9 weight:NSFontWeightMedium];
    CGFloat labelH = 12;
    CGFloat majorTick = MAX(18, NSHeight(inner) - labelH - 6);
    CGFloat minorTick = MAX(8, majorTick * 0.35);
    NSColor *tickColor = lit ? [NSColor colorWithCalibratedWhite:0.08 alpha:1]
                             : [NSColor colorWithCalibratedWhite:0.35 alpha:1];
    NSColor *numColor = lit ? [NSColor colorWithCalibratedWhite:0.05 alpha:1]
                            : [NSColor colorWithCalibratedWhite:0.4 alpha:1];
    for (int mhz = 88; mhz <= 108; mhz++) {
        CGFloat t = (mhz - 88) / 20.0;
        CGFloat x = NSMinX(inner) + 6 + t * (NSWidth(inner) - 12);
        BOOL major = (mhz % 2 == 0);
        [tickColor set];
        NSRectFill(NSMakeRect(x, NSMinY(inner) + 3, major ? 1.4 : 0.7, major ? majorTick : minorTick));
        if (major) {
            NSMutableParagraphStyle *ps = [NSMutableParagraphStyle new];
            ps.alignment = NSTextAlignmentCenter;
            [[NSString stringWithFormat:@"%d", mhz] drawInRect:NSMakeRect(x - 12, NSMaxY(inner) - labelH - 1, 24, labelH)
                                               withAttributes:@{NSFontAttributeName: markFont,
                                                                NSForegroundColorAttributeName: numColor,
                                                                NSParagraphStyleAttributeName: ps}];
        }
    }
    CGFloat ft = MAX(0, MIN(1, (self.frequency - 88.0) / 20.0));
    CGFloat nx = NSMinX(inner) + 6 + ft * (NSWidth(inner) - 12);
    CGFloat needleTop = NSMinY(inner) + 2;
    CGFloat needleH = NSHeight(inner) - 4;
    // Soft shadow behind needle
    [[NSColor colorWithCalibratedWhite:0 alpha:lit ? 0.35 : 0.2] set];
    NSRectFill(NSMakeRect(nx - 0.2, needleTop + 1.5, 2.8, needleH));
    if (lit) {
        // Thick red metal needle with glow
        [[NSColor colorWithCalibratedRed:1 green:0.25 blue:0.08 alpha:0.28] set];
        NSRectFill(NSMakeRect(nx - 3.2, needleTop, 6.4, needleH));
        NSGradient *blade = [[NSGradient alloc] initWithColorsAndLocations:
                             [NSColor colorWithCalibratedRed:0.55 green:0.05 blue:0.02 alpha:1], 0.0,
                             [NSColor colorWithCalibratedRed:1.0 green:0.28 blue:0.12 alpha:1], 0.35,
                             [NSColor colorWithCalibratedRed:0.85 green:0.08 blue:0.04 alpha:1], 0.7,
                             [NSColor colorWithCalibratedRed:0.4 green:0.03 blue:0.01 alpha:1], 1.0, nil];
        [blade drawInRect:NSMakeRect(nx - 1.35, needleTop, 2.7, needleH) angle:0];
        // Triangular tip at top of dial
        NSBezierPath *tip = [NSBezierPath bezierPath];
        [tip moveToPoint:NSMakePoint(nx, needleTop - 1)];
        [tip lineToPoint:NSMakePoint(nx - 4.5, needleTop + 7)];
        [tip lineToPoint:NSMakePoint(nx + 4.5, needleTop + 7)];
        [tip closePath];
        [[NSColor colorWithCalibratedRed:0.95 green:0.12 blue:0.06 alpha:1] set];
        [tip fill];
        // Specular on blade
        [[NSColor colorWithCalibratedWhite:1 alpha:0.35] set];
        NSRectFill(NSMakeRect(nx - 0.4, needleTop + 2, 0.7, needleH - 4));
    } else {
        [[NSColor colorWithCalibratedWhite:0.28 alpha:1] set];
        NSRectFill(NSMakeRect(nx - 1.0, needleTop, 2.0, needleH));
    }

    // Control strip under the dial — drawn after scale so labels stay visible
    [self drawSkipIconInRect:[self prevBtnFrame] next:NO hot:(_hotControl == 1)];
    [self drawSkipIconInRect:[self nextBtnFrame] next:YES hot:(_hotControl == 2)];
    [self drawCityButton:[self cityBtnFrame]];

    NSRect cityR = [self cityBtnFrame];
    CGFloat hintX = NSMaxX(cityR) + 12;
    CGFloat hintY = NSMinY(cityR) + 6;
    CGFloat hintW = MAX(80, NSMinX([self meterBox]) - hintX - 8);
    NSColor *hintColor = lit ? SKAmberColor() : [NSColor colorWithCalibratedWhite:0.4 alpha:1];
    if (_stations.count > 0) {
        NSString *hint = [NSString stringWithFormat:@"CH %ld / %lu", (long)(_stationIndex + 1), (unsigned long)_stations.count];
        if (self.loading) hint = @"SEARCHING…";
        SKDrawGlowText(hint,
                       NSMakeRect(hintX, hintY, MIN(100, hintW), 14),
                       [NSFont monospacedDigitSystemFontOfSize:10 weight:NSFontWeightMedium],
                       hintColor, NSTextAlignmentLeft);
        SKDrawGlowText(self.statusText ?: @"",
                       NSMakeRect(hintX + 96, hintY, MAX(40, hintW - 96), 14),
                       [NSFont systemFontOfSize:11 weight:NSFontWeightMedium],
                       [hintColor colorWithAlphaComponent:lit ? 0.95 : 0.7], NSTextAlignmentLeft);
    } else if (self.loading) {
        SKDrawGlowText(@"SEARCHING WORLD BAND…",
                       NSMakeRect(hintX, hintY, MAX(120, hintW), 14),
                       [NSFont systemFontOfSize:10 weight:NSFontWeightMedium],
                       hintColor, NSTextAlignmentLeft);
    }

    // TUNED / STEREO + live signal bars (fully inside the well)
    NSRect meters = [self meterBox];
    SKDrawInsetBevel(meters, 2);
    NSRect well = NSInsetRect(meters, 4, 4);
    [[NSColor colorWithCalibratedWhite:0.015 alpha:1] set];
    NSRectFill(well);

    BOOL tunedOn = self.tuned && self.powerOn;
    BOOL stereoOn = self.stereo && self.powerOn;
    CGFloat rowH = NSHeight(well) * 0.5;
    NSRect tLed = NSMakeRect(NSMinX(well) + 3, NSMinY(well) + rowH * 0.5 - 5, 10, 10);
    NSRect sLed = NSMakeRect(NSMinX(well) + 3, NSMinY(well) + rowH + rowH * 0.5 - 5, 10, 10);
    SKDrawJewelLED(tLed, [NSColor colorWithCalibratedRed:0.2 green:0.95 blue:0.35 alpha:1], tunedOn);
    SKDrawJewelLED(sLed, [NSColor colorWithCalibratedRed:0.3 green:0.55 blue:1.0 alpha:1], stereoOn);
    SKDrawGlowText(@"TUNED",
                   NSMakeRect(NSMinX(well) + 16, NSMinY(well) + rowH * 0.5 - 6, 46, 12),
                   [NSFont systemFontOfSize:8 weight:NSFontWeightBold],
                   tunedOn ? [NSColor colorWithCalibratedRed:0.35 green:1 blue:0.45 alpha:1] : SKAmberDimColor(),
                   NSTextAlignmentLeft);
    SKDrawGlowText(@"STEREO",
                   NSMakeRect(NSMinX(well) + 16, NSMinY(well) + rowH + rowH * 0.5 - 6, 48, 12),
                   [NSFont systemFontOfSize:8 weight:NSFontWeightBold],
                   stereoOn ? [NSColor colorWithCalibratedRed:0.5 green:0.75 blue:1 alpha:1] : SKAmberDimColor(),
                   NSTextAlignmentLeft);

    // Rhythm / signal column — clipped inside well
    NSRect barCol = NSMakeRect(NSMaxX(well) - 28, NSMinY(well) + 1, 24, NSHeight(well) - 2);
    CGFloat base = self.powerOn ? (self.tuned ? 0.35 : 0.08) : 0;
    CGFloat sig = self.powerOn ? MIN(1.0, base + self.signalLevel * 0.75) : 0;
    const NSInteger nSeg = 10;
    CGFloat gap = 1.2;
    CGFloat segH = (NSHeight(barCol) - (nSeg - 1) * gap) / (CGFloat)nSeg;
    NSInteger litSegs = (NSInteger)llround(sig * nSeg);
    for (NSInteger i = 0; i < nSeg; i++) {
        // flipped: MaxY is visual bottom — quiet at bottom
        NSRect seg = NSMakeRect(NSMinX(barCol),
                                NSMaxY(barCol) - (i + 1) * segH - i * gap,
                                NSWidth(barCol), segH);
        BOOL on = (i < litSegs);
        CGFloat t = (CGFloat)i / (CGFloat)(nSeg - 1);
        NSColor *c = (t < 0.55) ? SKAmberColor()
                   : (t < 0.8)  ? [NSColor colorWithCalibratedRed:1 green:0.45 blue:0.08 alpha:1]
                                : SKRedLEDColor();
        [(on ? c : [NSColor colorWithCalibratedWhite:0.11 alpha:1]) set];
        NSRectFill(seg);
        if (on) {
            [[c colorWithAlphaComponent:0.3] set];
            NSRectFill(NSInsetRect(seg, -0.6, -0.4));
        }
    }

    [self drawPowerSwitch:[self powerFrame]];
}

#pragma mark - City dropdown (custom hi-fi panel)

- (void)dismissCityPanel {
    if (_cityClickMonitor) {
        [NSEvent removeMonitor:_cityClickMonitor];
        _cityClickMonitor = nil;
    }
    if (_cityPanel) {
        [self.window removeChildWindow:_cityPanel];
        [_cityPanel orderOut:nil];
        _cityPanel = nil;
    }
    _menuOpen = NO;
    [self setNeedsDisplay:YES];
}

- (void)repositionCityPanelWithSize:(NSSize)size {
    if (!_cityPanel) return;
    NSRect btn = [self cityBtnFrame];
    NSPoint btnBottomInWin = [self convertPoint:NSMakePoint(NSMinX(btn), NSMaxY(btn)) toView:nil];
    NSRect panelInWin = NSMakeRect(btnBottomInWin.x, btnBottomInWin.y - size.height - 4,
                                   size.width, size.height);
    if (NSMinY(panelInWin) < 8) {
        NSPoint btnTopInWin = [self convertPoint:NSMakePoint(NSMinX(btn), NSMinY(btn)) toView:nil];
        panelInWin.origin.y = btnTopInWin.y + 4;
    }
    // 右侧不够时向左收一点
    NSRect vis = self.window.screen.visibleFrame;
    NSRect screenRect = [self.window convertRectToScreen:panelInWin];
    if (NSMaxX(screenRect) > NSMaxX(vis) - 8) {
        screenRect.origin.x = NSMaxX(vis) - 8 - NSWidth(screenRect);
    }
    [_cityPanel setFrame:screenRect display:YES];
}

- (void)showCityMenu {
    if (_cityPanel) {
        [self dismissCityPanel];
        return;
    }

    _menuOpen = YES;
    [self setNeedsDisplay:YES];

    NSSize initial = NSMakeSize(kCityColW + 6, 120);
    SKCityPickerView *picker = [[SKCityPickerView alloc] initWithFrame:NSMakeRect(0, 0, initial.width, initial.height)];
    picker.selectedCityName = self.selectedCity.nameCN;
    [picker reloadAll];
    initial = [picker preferredSize];
    picker.frame = NSMakeRect(0, 0, initial.width, initial.height);

    __weak WorldTunerView *weakSelf = self;
    picker.onPickCity = ^(NSString *nameCN) {
        [weakSelf dismissCityPanel];
        RadioCity *city = [[RadioCatalog shared] cityNamed:nameCN];
        if (city) [weakSelf selectCity:city reload:YES];
    };
    picker.onFrameNeedsUpdate = ^(NSSize size) {
        WorldTunerView *strongSelf = weakSelf;
        if (!strongSelf || !strongSelf->_cityPanel) return;
        NSView *cv = strongSelf->_cityPanel.contentView;
        if (!NSEqualSizes(cv.frame.size, size)) {
            cv.frame = NSMakeRect(0, 0, size.width, size.height);
        }
        [strongSelf repositionCityPanelWithSize:size];
    };

    NSRect btn = [self cityBtnFrame];
    NSPoint btnBottomInWin = [self convertPoint:NSMakePoint(NSMinX(btn), NSMaxY(btn)) toView:nil];
    NSRect panelInWin = NSMakeRect(btnBottomInWin.x, btnBottomInWin.y - initial.height - 4,
                                   initial.width, initial.height);
    NSRect panelScreen = [self.window convertRectToScreen:panelInWin];

    _cityPanel = [[NSPanel alloc] initWithContentRect:panelScreen
                                            styleMask:NSWindowStyleMaskBorderless
                                              backing:NSBackingStoreBuffered
                                                defer:NO];
    _cityPanel.opaque = NO;
    _cityPanel.backgroundColor = [NSColor clearColor];
    _cityPanel.hasShadow = YES;
    _cityPanel.level = NSPopUpMenuWindowLevel;
    _cityPanel.contentView = picker;
    [self.window addChildWindow:_cityPanel ordered:NSWindowAbove];
    [_cityPanel makeKeyAndOrderFront:nil];
    [self repositionCityPanelWithSize:initial];

    _cityClickMonitor = [NSEvent addLocalMonitorForEventsMatchingMask:NSEventMaskLeftMouseDown
                                                              handler:^NSEvent *(NSEvent *event) {
        WorldTunerView *strongSelf = weakSelf;
        if (!strongSelf) return event;
        if (event.window != strongSelf->_cityPanel) {
            [strongSelf dismissCityPanel];
        }
        return event;
    }];
}

#pragma mark - Mouse

- (void)updateHotFromEvent:(NSEvent *)event {
    NSPoint p = [self convertPoint:event.locationInWindow fromView:nil];
    NSInteger hot = -1;
    if (NSPointInRect(p, [self prevBtnFrame])) hot = 1;
    else if (NSPointInRect(p, [self nextBtnFrame])) hot = 2;
    else if (NSPointInRect(p, [self cityBtnFrame])) hot = 3;
    else if (NSPointInRect(p, [self powerFrame])) hot = 4;
    if (hot != _hotControl) {
        _hotControl = hot;
        [self setNeedsDisplay:YES];
    }
}

- (void)mouseMoved:(NSEvent *)event { [self updateHotFromEvent:event]; }
- (void)mouseEntered:(NSEvent *)event { (void)event; }
- (BOOL)acceptsFirstResponder { return YES; }

- (void)viewDidMoveToWindow {
    [super viewDidMoveToWindow];
    if (!self.window) {
        [self dismissCityPanel];
        return;
    }
    [self.window setAcceptsMouseMovedEvents:YES];
    NSTrackingArea *area = [[NSTrackingArea alloc] initWithRect:self.bounds
                                                        options:(NSTrackingMouseMoved | NSTrackingActiveInKeyWindow | NSTrackingInVisibleRect)
                                                          owner:self
                                                       userInfo:nil];
    [self addTrackingArea:area];
}

- (void)mouseDown:(NSEvent *)event {
    NSPoint p = [self convertPoint:event.locationInWindow fromView:nil];

    if (NSPointInRect(p, [self prevBtnFrame])) {
        [self selectPreviousStation];
        return;
    }
    if (NSPointInRect(p, [self nextBtnFrame])) {
        [self selectNextStation];
        return;
    }
    if (NSPointInRect(p, [self cityBtnFrame])) {
        [self showCityMenu];
        return;
    }
    if (NSPointInRect(p, [self powerFrame])) {
        self.powerOn = !self.powerOn;
        [self setNeedsDisplay:YES];
        if (self.onPowerChanged) self.onPowerChanged(self.powerOn);
        return;
    }
    if (NSPointInRect(p, [self scaleRect])) {
        _draggingScale = YES;
        [self tuneFromPoint:p];
    }
}

- (void)mouseDragged:(NSEvent *)event {
    [self updateHotFromEvent:event];
    if (!_draggingScale) return;
    NSPoint p = [self convertPoint:event.locationInWindow fromView:nil];
    [self tuneFromPoint:p];
}

- (void)mouseUp:(NSEvent *)event {
    (void)event;
    _draggingScale = NO;
}

- (void)tuneFromPoint:(NSPoint)p {
    NSRect scale = NSInsetRect([self scaleRect], 2, 2);
    CGFloat t = (p.x - (NSMinX(scale) + 6)) / (NSWidth(scale) - 12);
    t = MAX(0, MIN(1, t));
    self.frequency = 88.0 + t * 20.0;

    RadioStation *best = nil;
    CGFloat bestD = 0.55;
    NSInteger bestIdx = -1;
    for (NSInteger i = 0; i < (NSInteger)_stations.count; i++) {
        RadioStation *s = _stations[i];
        CGFloat d = fabs(s.frequency - self.frequency);
        if (d < bestD) { bestD = d; best = s; bestIdx = i; }
    }
    if (best && bestIdx >= 0) {
        [self pickStationAtIndex:bestIdx];
    } else {
        [self setNeedsDisplay:YES];
        if (self.onTuneFrequency) self.onTuneFrequency(self.frequency);
    }
}

- (void)scrollWheel:(NSEvent *)event {
    if (fabs(event.scrollingDeltaY) < 0.5) return;
    if (event.scrollingDeltaY > 0) [self selectPreviousStation];
    else [self selectNextStation];
}

@end
