#import "RadioCatalog.h"

@implementation RadioCity
@end

@implementation RadioCatalog {
    NSArray<RadioCity *> *_china;
    NSArray<RadioCity *> *_japan;
    NSArray<RadioCity *> *_world;
}

+ (instancetype)shared {
    static RadioCatalog *c;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ c = [[RadioCatalog alloc] init]; });
    return c;
}

- (RadioCity *)city:(NSString *)cn
                 en:(NSString *)en
               code:(NSString *)code
            country:(NSString *)country
             region:(RadioRegion)region
                mhz:(CGFloat)mhz
              terms:(NSArray *)terms {
    RadioCity *c = [[RadioCity alloc] init];
    c.nameCN = cn;
    c.nameEN = en;
    c.countryCode = code;
    c.countryName = country;
    c.region = region;
    c.defaultFrequency = mhz;
    c.searchTerms = terms ?: @[en];
    return c;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _china = @[
            [self city:@"北京" en:@"Beijing" code:@"CN" country:@"China" region:RadioRegionChina mhz:97.4 terms:@[@"北京", @"Beijing"]],
            [self city:@"上海" en:@"Shanghai" code:@"CN" country:@"China" region:RadioRegionChina mhz:101.7 terms:@[@"上海", @"Shanghai"]],
            [self city:@"广州" en:@"Guangzhou" code:@"CN" country:@"China" region:RadioRegionChina mhz:96.2 terms:@[@"广州", @"Guangzhou", @"Kwangtung"]],
            [self city:@"深圳" en:@"Shenzhen" code:@"CN" country:@"China" region:RadioRegionChina mhz:97.1 terms:@[@"深圳", @"Shenzhen"]],
            [self city:@"成都" en:@"Chengdu" code:@"CN" country:@"China" region:RadioRegionChina mhz:106.3 terms:@[@"成都", @"Chengdu", @"Szechuan", @"Sichuan", @"四川"]],
            [self city:@"重庆" en:@"Chongqing" code:@"CN" country:@"China" region:RadioRegionChina mhz:101.5 terms:@[@"重庆", @"Chongqing"]],
            [self city:@"杭州" en:@"Hangzhou" code:@"CN" country:@"China" region:RadioRegionChina mhz:91.8 terms:@[@"杭州", @"Hangzhou"]],
            [self city:@"南京" en:@"Nanjing" code:@"CN" country:@"China" region:RadioRegionChina mhz:99.7 terms:@[@"南京", @"Nanjing"]],
            [self city:@"武汉" en:@"Wuhan" code:@"CN" country:@"China" region:RadioRegionChina mhz:104.0 terms:@[@"武汉", @"Wuhan"]],
            [self city:@"西安" en:@"Xi'an" code:@"CN" country:@"China" region:RadioRegionChina mhz:98.2 terms:@[@"西安", @"Xian", @"Xi'an"]],
            [self city:@"天津" en:@"Tianjin" code:@"CN" country:@"China" region:RadioRegionChina mhz:97.2 terms:@[@"天津", @"Tianjin"]],
            [self city:@"苏州" en:@"Suzhou" code:@"CN" country:@"China" region:RadioRegionChina mhz:94.8 terms:@[@"苏州", @"Suzhou"]],
            [self city:@"长沙" en:@"Changsha" code:@"CN" country:@"China" region:RadioRegionChina mhz:102.2 terms:@[@"长沙", @"Changsha"]],
            [self city:@"郑州" en:@"Zhengzhou" code:@"CN" country:@"China" region:RadioRegionChina mhz:98.6 terms:@[@"郑州", @"Zhengzhou"]],
            [self city:@"青岛" en:@"Qingdao" code:@"CN" country:@"China" region:RadioRegionChina mhz:89.7 terms:@[@"青岛", @"Qingdao"]],
            [self city:@"大连" en:@"Dalian" code:@"CN" country:@"China" region:RadioRegionChina mhz:93.1 terms:@[@"大连", @"Dalian"]],
            [self city:@"厦门" en:@"Xiamen" code:@"CN" country:@"China" region:RadioRegionChina mhz:90.9 terms:@[@"厦门", @"Xiamen"]],
            [self city:@"昆明" en:@"Kunming" code:@"CN" country:@"China" region:RadioRegionChina mhz:99.8 terms:@[@"昆明", @"Kunming"]],
            [self city:@"哈尔滨" en:@"Harbin" code:@"CN" country:@"China" region:RadioRegionChina mhz:99.8 terms:@[@"哈尔滨", @"Harbin"]],
            [self city:@"沈阳" en:@"Shenyang" code:@"CN" country:@"China" region:RadioRegionChina mhz:95.9 terms:@[@"沈阳", @"Shenyang"]],
            [self city:@"福州" en:@"Fuzhou" code:@"CN" country:@"China" region:RadioRegionChina mhz:94.4 terms:@[@"福州", @"Fuzhou"]],
            [self city:@"济南" en:@"Jinan" code:@"CN" country:@"China" region:RadioRegionChina mhz:100.6 terms:@[@"济南", @"Jinan"]],
            [self city:@"合肥" en:@"Hefei" code:@"CN" country:@"China" region:RadioRegionChina mhz:98.8 terms:@[@"合肥", @"Hefei"]],
            [self city:@"南昌" en:@"Nanchang" code:@"CN" country:@"China" region:RadioRegionChina mhz:104.0 terms:@[@"南昌", @"Nanchang"]],
            [self city:@"南宁" en:@"Nanning" code:@"CN" country:@"China" region:RadioRegionChina mhz:101.4 terms:@[@"南宁", @"Nanning"]],
            [self city:@"海口" en:@"Haikou" code:@"CN" country:@"China" region:RadioRegionChina mhz:88.6 terms:@[@"海口", @"Haikou"]],
            [self city:@"兰州" en:@"Lanzhou" code:@"CN" country:@"China" region:RadioRegionChina mhz:99.5 terms:@[@"兰州", @"Lanzhou"]],
            [self city:@"贵阳" en:@"Guiyang" code:@"CN" country:@"China" region:RadioRegionChina mhz:94.6 terms:@[@"贵阳", @"Guiyang"]],
            [self city:@"乌鲁木齐" en:@"Urumqi" code:@"CN" country:@"China" region:RadioRegionChina mhz:97.4 terms:@[@"乌鲁木齐", @"Urumqi"]],
            [self city:@"拉萨" en:@"Lhasa" code:@"CN" country:@"China" region:RadioRegionChina mhz:101.6 terms:@[@"拉萨", @"Lhasa"]],
            [self city:@"呼和浩特" en:@"Hohhot" code:@"CN" country:@"China" region:RadioRegionChina mhz:95.9 terms:@[@"呼和浩特", @"Hohhot"]],
            [self city:@"银川" en:@"Yinchuan" code:@"CN" country:@"China" region:RadioRegionChina mhz:100.8 terms:@[@"银川", @"Yinchuan"]],
            [self city:@"西宁" en:@"Xining" code:@"CN" country:@"China" region:RadioRegionChina mhz:97.2 terms:@[@"西宁", @"Xining"]],
            [self city:@"台北" en:@"Taipei" code:@"TW" country:@"Taiwan" region:RadioRegionChina mhz:105.7 terms:@[@"台北", @"Taipei"]],
            [self city:@"香港" en:@"Hong Kong" code:@"HK" country:@"Hong Kong" region:RadioRegionChina mhz:96.9 terms:@[@"香港", @"Hong Kong", @"HongKong"]],
            [self city:@"澳门" en:@"Macau" code:@"MO" country:@"Macau" region:RadioRegionChina mhz:100.7 terms:@[@"澳门", @"Macau", @"Macao"]],
        ];

        _japan = @[
            [self city:@"东京" en:@"Tokyo" code:@"JP" country:@"Japan" region:RadioRegionJapan mhz:80.0 terms:@[@"東京", @"Tokyo"]],
            [self city:@"大阪" en:@"Osaka" code:@"JP" country:@"Japan" region:RadioRegionJapan mhz:85.1 terms:@[@"大阪", @"Osaka"]],
            [self city:@"京都" en:@"Kyoto" code:@"JP" country:@"Japan" region:RadioRegionJapan mhz:82.8 terms:@[@"京都", @"Kyoto"]],
            [self city:@"名古屋" en:@"Nagoya" code:@"JP" country:@"Japan" region:RadioRegionJapan mhz:78.9 terms:@[@"名古屋", @"Nagoya"]],
            [self city:@"横浜" en:@"Yokohama" code:@"JP" country:@"Japan" region:RadioRegionJapan mhz:84.7 terms:@[@"横浜", @"Yokohama"]],
            [self city:@"札幌" en:@"Sapporo" code:@"JP" country:@"Japan" region:RadioRegionJapan mhz:85.2 terms:@[@"札幌", @"Sapporo"]],
            [self city:@"福冈" en:@"Fukuoka" code:@"JP" country:@"Japan" region:RadioRegionJapan mhz:80.7 terms:@[@"福岡", @"Fukuoka"]],
            [self city:@"神户" en:@"Kobe" code:@"JP" country:@"Japan" region:RadioRegionJapan mhz:89.9 terms:@[@"神戸", @"Kobe"]],
            [self city:@"广岛" en:@"Hiroshima" code:@"JP" country:@"Japan" region:RadioRegionJapan mhz:78.2 terms:@[@"広島", @"Hiroshima"]],
            [self city:@"仙台" en:@"Sendai" code:@"JP" country:@"Japan" region:RadioRegionJapan mhz:77.1 terms:@[@"仙台", @"Sendai"]],
            [self city:@"冲绳" en:@"Okinawa" code:@"JP" country:@"Japan" region:RadioRegionJapan mhz:87.0 terms:@[@"沖縄", @"Okinawa"]],
        ];

        _world = @[
            [self city:@"纽约" en:@"New York" code:@"US" country:@"USA" region:RadioRegionWorld mhz:101.1 terms:@[@"New York", @"NYC"]],
            [self city:@"洛杉矶" en:@"Los Angeles" code:@"US" country:@"USA" region:RadioRegionWorld mhz:98.7 terms:@[@"Los Angeles", @"LA"]],
            [self city:@"芝加哥" en:@"Chicago" code:@"US" country:@"USA" region:RadioRegionWorld mhz:97.1 terms:@[@"Chicago"]],
            [self city:@"旧金山" en:@"San Francisco" code:@"US" country:@"USA" region:RadioRegionWorld mhz:98.5 terms:@[@"San Francisco", @"SomaFM"]],
            [self city:@"伦敦" en:@"London" code:@"GB" country:@"UK" region:RadioRegionWorld mhz:95.8 terms:@[@"London", @"BBC"]],
            [self city:@"巴黎" en:@"Paris" code:@"FR" country:@"France" region:RadioRegionWorld mhz:96.9 terms:@[@"Paris"]],
            [self city:@"柏林" en:@"Berlin" code:@"DE" country:@"Germany" region:RadioRegionWorld mhz:94.3 terms:@[@"Berlin"]],
            [self city:@"慕尼黑" en:@"Munich" code:@"DE" country:@"Germany" region:RadioRegionWorld mhz:93.3 terms:@[@"Munich", @"München"]],
            [self city:@"阿姆斯特丹" en:@"Amsterdam" code:@"NL" country:@"Netherlands" region:RadioRegionWorld mhz:95.2 terms:@[@"Amsterdam"]],
            [self city:@"罗马" en:@"Rome" code:@"IT" country:@"Italy" region:RadioRegionWorld mhz:102.5 terms:@[@"Rome", @"Roma"]],
            [self city:@"马德里" en:@"Madrid" code:@"ES" country:@"Spain" region:RadioRegionWorld mhz:91.0 terms:@[@"Madrid"]],
            [self city:@"莫斯科" en:@"Moscow" code:@"RU" country:@"Russia" region:RadioRegionWorld mhz:103.0 terms:@[@"Moscow", @"Москва"]],
            [self city:@"悉尼" en:@"Sydney" code:@"AU" country:@"Australia" region:RadioRegionWorld mhz:96.9 terms:@[@"Sydney"]],
            [self city:@"墨尔本" en:@"Melbourne" code:@"AU" country:@"Australia" region:RadioRegionWorld mhz:105.1 terms:@[@"Melbourne"]],
            [self city:@"多伦多" en:@"Toronto" code:@"CA" country:@"Canada" region:RadioRegionWorld mhz:99.1 terms:@[@"Toronto"]],
            [self city:@"温哥华" en:@"Vancouver" code:@"CA" country:@"Canada" region:RadioRegionWorld mhz:96.9 terms:@[@"Vancouver"]],
            [self city:@"新加坡" en:@"Singapore" code:@"SG" country:@"Singapore" region:RadioRegionWorld mhz:95.8 terms:@[@"Singapore"]],
            [self city:@"首尔" en:@"Seoul" code:@"KR" country:@"Korea" region:RadioRegionWorld mhz:89.1 terms:@[@"Seoul", @"서울"]],
            [self city:@"曼谷" en:@"Bangkok" code:@"TH" country:@"Thailand" region:RadioRegionWorld mhz:105.5 terms:@[@"Bangkok"]],
            [self city:@"迪拜" en:@"Dubai" code:@"AE" country:@"UAE" region:RadioRegionWorld mhz:92.0 terms:@[@"Dubai"]],
            [self city:@"开罗" en:@"Cairo" code:@"EG" country:@"Egypt" region:RadioRegionWorld mhz:95.4 terms:@[@"Cairo"]],
            [self city:@"约翰内斯堡" en:@"Johannesburg" code:@"ZA" country:@"South Africa" region:RadioRegionWorld mhz:94.7 terms:@[@"Johannesburg"]],
            [self city:@"墨西哥城" en:@"Mexico City" code:@"MX" country:@"Mexico" region:RadioRegionWorld mhz:97.7 terms:@[@"Mexico City"]],
            [self city:@"圣保罗" en:@"Sao Paulo" code:@"BR" country:@"Brazil" region:RadioRegionWorld mhz:100.9 terms:@[@"Sao Paulo", @"São Paulo"]],
            [self city:@"布宜诺斯艾利斯" en:@"Buenos Aires" code:@"AR" country:@"Argentina" region:RadioRegionWorld mhz:95.9 terms:@[@"Buenos Aires"]],
            [self city:@"维也纳" en:@"Vienna" code:@"AT" country:@"Austria" region:RadioRegionWorld mhz:89.9 terms:@[@"Vienna", @"Wien"]],
            [self city:@"斯德哥尔摩" en:@"Stockholm" code:@"SE" country:@"Sweden" region:RadioRegionWorld mhz:103.3 terms:@[@"Stockholm"]],
            [self city:@"伊斯坦布尔" en:@"Istanbul" code:@"TR" country:@"Turkey" region:RadioRegionWorld mhz:94.0 terms:@[@"Istanbul"]],
            [self city:@"孟买" en:@"Mumbai" code:@"IN" country:@"India" region:RadioRegionWorld mhz:98.3 terms:@[@"Mumbai"]],
            [self city:@"新德里" en:@"New Delhi" code:@"IN" country:@"India" region:RadioRegionWorld mhz:102.6 terms:@[@"Delhi", @"New Delhi"]],
        ];
    }
    return self;
}

- (NSArray<RadioCity *> *)citiesForRegion:(RadioRegion)region {
    switch (region) {
        case RadioRegionChina: return _china;
        case RadioRegionJapan: return _japan;
        case RadioRegionWorld: return _world;
    }
    return @[];
}

- (NSArray<RadioCity *> *)allCities {
    return [[_china arrayByAddingObjectsFromArray:_japan] arrayByAddingObjectsFromArray:_world];
}

- (RadioCity *)cityNamed:(NSString *)nameCN {
    for (RadioCity *c in [self allCities]) {
        if ([c.nameCN isEqualToString:nameCN] || [c.nameEN caseInsensitiveCompare:nameCN] == NSOrderedSame) {
            return c;
        }
    }
    return nil;
}

@end
