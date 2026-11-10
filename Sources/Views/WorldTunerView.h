#import <Cocoa/Cocoa.h>
#import "RadioCatalog.h"
#import "AudioEngine.h"

@interface WorldTunerView : NSView

@property (nonatomic, assign) RadioRegion region;
@property (nonatomic, strong, nullable) RadioCity *selectedCity;
@property (nonatomic, strong, nullable) RadioStation *selectedStation;
@property (nonatomic, assign) CGFloat frequency;
@property (nonatomic, copy, null_unspecified) NSString *statusText;
@property (nonatomic, assign) BOOL loading;
@property (nonatomic, assign) BOOL tuned;
@property (nonatomic, assign) BOOL stereo;
@property (nonatomic, assign) BOOL powerOn;
/// Live signal / rhythm level 0..1 (driven by audio meter)
@property (nonatomic, assign) float signalLevel;

@property (nonatomic, copy, nullable) void (^onCitySelected)(RadioCity * _Nonnull city);
@property (nonatomic, copy, nullable) void (^onStationSelected)(RadioStation * _Nonnull station);
@property (nonatomic, copy, nullable) void (^onStationsUpdated)(NSArray<RadioStation *> * _Nonnull stations, NSInteger selectedIndex);
@property (nonatomic, copy, nullable) void (^onTuneFrequency)(CGFloat mhz);
@property (nonatomic, copy, nullable) void (^onPowerChanged)(BOOL on);

@property (nonatomic, readonly) NSArray<RadioStation *> *stations;
@property (nonatomic, readonly) NSInteger stationIndex;

- (void)setStations:(NSArray<RadioStation *> * _Nonnull)stations;
- (void)selectCity:(RadioCity * _Nonnull)city reload:(BOOL)reload;
- (void)applyRegion:(RadioRegion)region selectFirstCity:(BOOL)selectFirst;
- (void)selectPreviousStation;
- (void)selectNextStation;
- (void)pickStationAtIndex:(NSInteger)idx;

@end
