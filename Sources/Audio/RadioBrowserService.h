#import <Foundation/Foundation.h>
#import "RadioCatalog.h"
#import "AudioEngine.h"

NS_ASSUME_NONNULL_BEGIN

@interface RadioBrowserService : NSObject
+ (instancetype)shared;

/// Fetch live stations for a city (Radio Browser + curated fallbacks)
- (void)fetchStationsForCity:(RadioCity *)city
                  completion:(void (^)(NSArray<RadioStation *> *stations, NSError * _Nullable error))completion;

@end

NS_ASSUME_NONNULL_END
