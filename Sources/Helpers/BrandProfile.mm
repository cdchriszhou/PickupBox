#import "BrandProfile.h"
#import "DrawingHelpers.h"

static NSString * const kBrandDefaultsKey = @"SKPreferredBrand";
static BrandProfile *gActiveBrand = nil;

@implementation BrandProfile

- (instancetype)initWithID:(SKBrandID)bid
                identifier:(NSString *)identifier
               displayName:(NSString *)name
                systemLine:(NSString *)systemLine
                  modelTag:(NSString *)model
                    accent:(NSColor *)accent
                 accentDim:(NSColor *)accentDim
              chassisTint:(NSColor *)chassisTint
                     trim:(NSColor *)trim {
    self = [super init];
    if (self) {
        _brandID = bid;
        _identifier = [identifier copy];
        _displayName = [name copy];
        _systemLine = [systemLine copy];
        _modelTag = [model copy];
        _accentColor = accent;
        _accentDimColor = accentDim;
        _chassisTint = chassisTint;
        _trimColor = trim;
    }
    return self;
}

+ (NSArray<BrandProfile *> *)allBrands {
    static NSArray *brands;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        brands = @[
            // 经典琥珀 — 暖金 VFD + 轻微暖调机壳
            [[BrandProfile alloc] initWithID:SKBrandClassic
                                  identifier:@"classic"
                                 displayName:@"经典琥珀 Classic"
                                  systemLine:@"拾音盒子  ·  看得见音乐的播放器"
                                    modelTag:@"PB-1"
                                      accent:[NSColor colorWithCalibratedRed:1.00 green:0.62 blue:0.08 alpha:1]
                                   accentDim:[NSColor colorWithCalibratedRed:0.55 green:0.32 blue:0.05 alpha:1]
                                 chassisTint:[NSColor colorWithCalibratedRed:0.55 green:0.32 blue:0.06 alpha:0.10]
                                        trim:[NSColor colorWithCalibratedRed:0.92 green:0.72 blue:0.28 alpha:1]],
            // 夜色 — 冷蓝光 + 钢蓝机壳
            [[BrandProfile alloc] initWithID:SKBrandNight
                                  identifier:@"night"
                                 displayName:@"夜色 Night"
                                  systemLine:@"PICKUP BOX  ·  SEE THE MUSIC"
                                    modelTag:@"PB-1"
                                      accent:[NSColor colorWithCalibratedRed:0.55 green:0.78 blue:1.00 alpha:1]
                                   accentDim:[NSColor colorWithCalibratedRed:0.18 green:0.32 blue:0.55 alpha:1]
                                 chassisTint:[NSColor colorWithCalibratedRed:0.12 green:0.22 blue:0.48 alpha:0.22]
                                        trim:[NSColor colorWithCalibratedRed:0.62 green:0.78 blue:0.98 alpha:1]],
            // 海浪 — 青绿荧光 + 青绿机壳
            [[BrandProfile alloc] initWithID:SKBrandOcean
                                  identifier:@"ocean"
                                 displayName:@"海浪 Ocean"
                                  systemLine:@"拾音盒子  ·  Pickup Box"
                                    modelTag:@"PB-1"
                                      accent:[NSColor colorWithCalibratedRed:0.18 green:0.88 blue:0.82 alpha:1]
                                   accentDim:[NSColor colorWithCalibratedRed:0.06 green:0.38 blue:0.40 alpha:1]
                                 chassisTint:[NSColor colorWithCalibratedRed:0.04 green:0.32 blue:0.38 alpha:0.24]
                                        trim:[NSColor colorWithCalibratedRed:0.28 green:0.78 blue:0.72 alpha:1]],
            // 工作室 — 血红指示 + 暖暗红机壳
            [[BrandProfile alloc] initWithID:SKBrandStudio
                                  identifier:@"studio"
                                 displayName:@"工作室 Studio"
                                  systemLine:@"PICKUP BOX  VISUAL MUSIC PLAYER"
                                    modelTag:@"PB-1"
                                      accent:[NSColor colorWithCalibratedRed:1.00 green:0.32 blue:0.22 alpha:1]
                                   accentDim:[NSColor colorWithCalibratedRed:0.48 green:0.10 blue:0.08 alpha:1]
                                 chassisTint:[NSColor colorWithCalibratedRed:0.42 green:0.06 blue:0.05 alpha:0.22]
                                        trim:[NSColor colorWithCalibratedRed:0.88 green:0.28 blue:0.22 alpha:1]],
        ];
    });
    return brands;
}

+ (BrandProfile *)brandWithID:(SKBrandID)brandID {
    for (BrandProfile *b in [self allBrands]) {
        if (b.brandID == brandID) return b;
    }
    return [self allBrands].firstObject;
}

+ (BrandProfile *)brandWithIdentifier:(NSString *)identifier {
    NSString *key = identifier.lowercaseString ?: @"classic";
    // 旧版索尼等偏好迁移到经典琥珀
    if ([key isEqualToString:@"sony"] || [key isEqualToString:@"pioneer"] ||
        [key isEqualToString:@"panasonic"] || [key isEqualToString:@"kenwood"]) {
        key = @"classic";
    }
    for (BrandProfile *b in [self allBrands]) {
        if ([b.identifier isEqualToString:key]) return b;
    }
    return [self allBrands].firstObject;
}

+ (BrandProfile *)preferredBrand {
    NSString *id = [[NSUserDefaults standardUserDefaults] stringForKey:kBrandDefaultsKey];
    return [self brandWithIdentifier:id ?: @"classic"];
}

+ (void)setPreferredBrandIdentifier:(NSString *)identifier {
    NSString *key = identifier.lowercaseString ?: @"classic";
    if ([key isEqualToString:@"sony"] || [key isEqualToString:@"pioneer"] ||
        [key isEqualToString:@"panasonic"] || [key isEqualToString:@"kenwood"]) {
        key = @"classic";
    }
    [[NSUserDefaults standardUserDefaults] setObject:key forKey:kBrandDefaultsKey];
}

+ (BrandProfile *)activeBrand {
    return gActiveBrand ?: [self preferredBrand];
}

+ (void)setActiveBrand:(BrandProfile *)profile {
    gActiveBrand = profile ?: [self preferredBrand];
}

- (void)drawWordmarkInRect:(NSRect)rect {
    [self drawPickupBoxInRect:rect];
}

- (void)drawPickupBoxInRect:(NSRect)rect {
    // 「拾音盒子」铭牌：略宽字距，浅银字 + 主题色微光
    CGFloat fontSize = MIN(15.0, NSHeight(rect) * 0.62);
    NSFont *font = [NSFont systemFontOfSize:fontSize weight:NSFontWeightSemibold];
    NSMutableParagraphStyle *ps = [NSMutableParagraphStyle new];
    ps.alignment = NSTextAlignmentCenter;
    NSDictionary *shadow = @{
        NSFontAttributeName: font,
        NSForegroundColorAttributeName: [NSColor colorWithCalibratedWhite:0 alpha:0.55],
        NSKernAttributeName: @1.2,
        NSParagraphStyleAttributeName: ps,
    };
    NSDictionary *attrs = @{
        NSFontAttributeName: font,
        NSForegroundColorAttributeName: [NSColor colorWithCalibratedWhite:0.94 alpha:1],
        NSKernAttributeName: @1.2,
        NSParagraphStyleAttributeName: ps,
    };
    NSString *s = @"拾音盒子";
    NSSize sz = [s sizeWithAttributes:attrs];
    NSRect r = NSMakeRect(NSMidX(rect) - sz.width * 0.5,
                          NSMidY(rect) - sz.height * 0.5 - 0.5,
                          sz.width, sz.height);
    [s drawInRect:NSOffsetRect(r, 0, 0.6) withAttributes:shadow];
    [s drawInRect:r withAttributes:attrs];
    // 主题色细线点缀
    [[self.accentColor colorWithAlphaComponent:0.85] set];
    NSRectFill(NSMakeRect(NSMidX(rect) - MIN(28, sz.width * 0.35),
                           NSMaxY(r) + 1.0,
                           MIN(56, sz.width * 0.7), 1.2));
}

@end
