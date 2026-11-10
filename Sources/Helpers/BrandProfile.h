#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

/// 拾音盒子面板色主题（不再使用第三方商标仿冒）
typedef NS_ENUM(NSInteger, SKBrandID) {
    SKBrandClassic = 0, // 经典琥珀
    SKBrandNight,       // 夜色
    SKBrandOcean,       // 海浪
    SKBrandStudio,      // 工作室
};

@interface BrandProfile : NSObject
@property (nonatomic, assign, readonly) SKBrandID brandID;
@property (nonatomic, copy, readonly) NSString *identifier;   // defaults key
@property (nonatomic, copy, readonly) NSString *displayName;  // 菜单：主题名
@property (nonatomic, copy, readonly) NSString *systemLine;   // 顶栏
@property (nonatomic, copy, readonly) NSString *modelTag;     // e.g. PB-1
@property (nonatomic, strong, readonly) NSColor *accentColor;   // VFD / LED 主发光
@property (nonatomic, strong, readonly) NSColor *accentDimColor;
@property (nonatomic, strong, readonly) NSColor *chassisTint;   // 机壳金属染色（半透明）
@property (nonatomic, strong, readonly) NSColor *trimColor;     // 喇叭金圈 / 铭牌饰边

+ (NSArray<BrandProfile *> *)allBrands;
+ (BrandProfile *)brandWithIdentifier:(NSString *)identifier;
+ (BrandProfile *)brandWithID:(SKBrandID)brandID;
+ (BrandProfile *)preferredBrand;
+ (void)setPreferredBrandIdentifier:(NSString *)identifier;

/// 当前生效主题（绘制层 SKAmberColor 等读取）
+ (BrandProfile *)activeBrand;
+ (void)setActiveBrand:(BrandProfile *)profile;

/// 面板铭牌：绘制「拾音盒子」字标
- (void)drawWordmarkInRect:(NSRect)rect;

@end

NS_ASSUME_NONNULL_END
