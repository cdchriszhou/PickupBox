#import <Foundation/Foundation.h>
#import "AudioEngine.h"

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, RadioRegion) {
    RadioRegionChina = 0,
    RadioRegionJapan = 1,
    RadioRegionWorld = 2,
};

@interface RadioCity : NSObject
@property (nonatomic, copy) NSString *nameCN;
@property (nonatomic, copy) NSString *nameEN;
@property (nonatomic, copy) NSString *countryCode; // CN / JP / US …
@property (nonatomic, copy) NSString *countryName;
@property (nonatomic, assign) RadioRegion region;
@property (nonatomic, assign) CGFloat defaultFrequency;
/// Extra search keywords for Radio Browser
@property (nonatomic, copy) NSArray<NSString *> *searchTerms;
@end

@interface RadioCatalog : NSObject
+ (instancetype)shared;
- (NSArray<RadioCity *> *)citiesForRegion:(RadioRegion)region;
- (NSArray<RadioCity *> *)allCities;
- (nullable RadioCity *)cityNamed:(NSString *)nameCN;
@end

NS_ASSUME_NONNULL_END
