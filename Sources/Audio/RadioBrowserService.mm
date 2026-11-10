#import "RadioBrowserService.h"

static NSString * const kUserAgent = @"PickupBox/1.1 (macOS; 拾音盒子 / Pickup Box)";

@implementation RadioBrowserService {
    NSURLSession *_session;
    NSString *_apiHost;
}

+ (instancetype)shared {
    static RadioBrowserService *s;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ s = [[RadioBrowserService alloc] init]; });
    return s;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        NSURLSessionConfiguration *cfg = [NSURLSessionConfiguration defaultSessionConfiguration];
        cfg.timeoutIntervalForRequest = 18;
        cfg.HTTPAdditionalHeaders = @{ @"User-Agent": kUserAgent };
        _session = [NSURLSession sessionWithConfiguration:cfg];
        _apiHost = @"https://de1.api.radio-browser.info";
        [self resolveMirror];
    }
    return self;
}

- (void)resolveMirror {
    NSURL *url = [NSURL URLWithString:@"https://all.api.radio-browser.info/json/servers"];
    NSURLSessionDataTask *task = [_session dataTaskWithURL:url completionHandler:^(NSData *data, NSURLResponse *resp, NSError *err) {
        (void)resp;
        if (err || data.length == 0) return;
        NSArray *arr = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
        if (![arr isKindOfClass:[NSArray class]] || arr.count == 0) return;
        NSDictionary *first = arr.firstObject;
        NSString *name = first[@"name"];
        if ([name isKindOfClass:[NSString class]] && name.length) {
            self->_apiHost = [NSString stringWithFormat:@"https://%@", name];
        }
    }];
    [task resume];
}

- (NSArray<RadioStation *> *)curatedFallbacksForCity:(RadioCity *)city {
    // Safety net when Radio Browser has sparse city coverage
    NSMutableArray *out = [NSMutableArray array];
    void (^add)(NSString *, NSString *, CGFloat) = ^(NSString *name, NSString *url, CGFloat mhz) {
        RadioStation *s = [RadioStation stationWithName:name city:city.nameCN frequency:mhz url:url];
        s.country = city.countryName;
        s.codec = @"MP3";
        [out addObject:s];
    };

    if (city.region == RadioRegionChina) {
        // National / regional Chinese streams that usually resolve
        add(@"CNR-1 中国之声", @"https://ngcdn001.cnr.cn/live/zgzs/index.m3u8", 106.1);
        add(@"CNR-2 经济之声", @"https://ngcdn002.cnr.cn/live/jjzs/index.m3u8", 96.6);
        add(([NSString stringWithFormat:@"%@ · 华语金曲", city.nameCN]),
            @"https://ice1.somafm.com/suburbsofgoa-128-mp3", city.defaultFrequency);
    } else if ([city.nameEN isEqualToString:@"San Francisco"]) {
        add(@"SomaFM Groove Salad", @"https://ice1.somafm.com/groovesalad-128-mp3", city.defaultFrequency);
        add(@"SomaFM Drone Zone", @"https://ice1.somafm.com/dronezone-128-mp3", city.defaultFrequency - 1.2);
        add(@"SomaFM Left Coast 70s", @"https://ice1.somafm.com/seventies-128-mp3", city.defaultFrequency - 2.0);
    } else if (city.region == RadioRegionJapan) {
        add(@"NHK World Radio Japan (fallback)", @"https://ice1.somafm.com/dronezone-128-mp3", city.defaultFrequency);
        add(@"SomaFM Indie Pop Rocks", @"https://ice1.somafm.com/indiepop-128-mp3", city.defaultFrequency - 1.0);
    } else if ([city.nameEN isEqualToString:@"London"]) {
        add(@"SomaFM Indie Pop", @"https://ice1.somafm.com/indiepop-128-mp3", 95.8);
        add(@"SomaFM Groove Salad", @"https://ice1.somafm.com/groovesalad-128-mp3", 94.5);
    } else {
        add(([NSString stringWithFormat:@"%@ World Mix", city.nameCN]),
            @"https://ice1.somafm.com/groovesalad-128-mp3",
            city.defaultFrequency);
    }
    return out;
}

- (RadioStation *)stationFromJSON:(NSDictionary *)dict city:(RadioCity *)city index:(NSInteger)idx {
    NSString *name = dict[@"name"] ?: @"Unknown Station";
    NSString *urlStr = dict[@"url_resolved"];
    if (![urlStr isKindOfClass:[NSString class]] || urlStr.length == 0) {
        urlStr = dict[@"url"];
    }
    if (![urlStr isKindOfClass:[NSString class]] || urlStr.length == 0) return nil;

    if ([dict[@"lastcheckok"] respondsToSelector:@selector(intValue)] && [dict[@"lastcheckok"] intValue] == 0) {
        return nil;
    }

    CGFloat mhz = 88.0 + fmod(city.defaultFrequency - 88.0 + idx * 0.7, 20.0);
    RadioStation *s = [RadioStation stationWithName:name
                                               city:city.nameCN
                                          frequency:mhz
                                                url:urlStr];
    s.country = dict[@"country"] ?: city.countryName;
    s.codec = dict[@"codec"];
    if ([dict[@"bitrate"] respondsToSelector:@selector(integerValue)]) {
        s.bitrate = [dict[@"bitrate"] integerValue];
    }
    NSString *home = dict[@"homepage"];
    if ([home isKindOfClass:[NSString class]]) s.homepage = home;
    return s;
}

- (void)getJSON:(NSString *)pathQuery completion:(void (^)(id json, NSError *error))completion {
    NSString *full = [NSString stringWithFormat:@"%@%@", _apiHost, pathQuery];
    NSURL *url = [NSURL URLWithString:full];
    if (!url) {
        completion(nil, [NSError errorWithDomain:@"RadioBrowser" code:1 userInfo:@{NSLocalizedDescriptionKey: @"无效请求"}]);
        return;
    }
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:url];
    [req setValue:kUserAgent forHTTPHeaderField:@"User-Agent"];
    [req setValue:@"application/json" forHTTPHeaderField:@"Accept"];

    NSURLSessionDataTask *task = [_session dataTaskWithRequest:req completionHandler:^(NSData *data, NSURLResponse *resp, NSError *err) {
        if (err) { completion(nil, err); return; }
        NSHTTPURLResponse *http = (NSHTTPURLResponse *)resp;
        if (http.statusCode < 200 || http.statusCode >= 300 || data.length == 0) {
            completion(nil, [NSError errorWithDomain:@"RadioBrowser" code:http.statusCode userInfo:@{NSLocalizedDescriptionKey: @"电台目录请求失败"}]);
            return;
        }
        NSError *jerr = nil;
        id json = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jerr];
        completion(json, jerr);
    }];
    [task resume];
}

- (NSString *)encode:(NSString *)s {
    return [s stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLQueryAllowedCharacterSet]] ?: s;
}

- (BOOL)dictionary:(NSDictionary *)d matchesCity:(RadioCity *)city {
    NSString *name = [d[@"name"] description] ?: @"";
    NSString *state = [d[@"state"] description] ?: @"";
    NSString *tags = [d[@"tags"] description] ?: @"";
    NSMutableArray *terms = [NSMutableArray arrayWithArray:city.searchTerms ?: @[]];
    if (city.nameCN.length) [terms addObject:city.nameCN];
    if (city.nameEN.length) [terms addObject:city.nameEN];
    for (NSString *term in terms) {
        if (term.length == 0) continue;
        if ([name localizedCaseInsensitiveContainsString:term] ||
            [state localizedCaseInsensitiveContainsString:term] ||
            [tags localizedCaseInsensitiveContainsString:term]) {
            return YES;
        }
    }
    return NO;
}

- (void)fetchStationsForCity:(RadioCity *)city
                  completion:(void (^)(NSArray<RadioStation *> *stations, NSError * _Nullable error))completion {
    if (!city) {
        completion(@[], [NSError errorWithDomain:@"RadioBrowser" code:2 userInfo:@{NSLocalizedDescriptionKey: @"未选择城市"}]);
        return;
    }

    dispatch_group_t group = dispatch_group_create();
    NSMutableArray *merged = [NSMutableArray array];
    __block NSError *lastError = nil;
    NSObject *lock = [[NSObject alloc] init];

    void (^appendJSON)(id) = ^(id json) {
        if (![json isKindOfClass:[NSArray class]]) return;
        NSInteger idx = 0;
        for (NSDictionary *d in (NSArray *)json) {
            if (![d isKindOfClass:[NSDictionary class]]) continue;
            RadioStation *s = [self stationFromJSON:d city:city index:idx];
            if (!s) continue;
            @synchronized (lock) {
                BOOL exists = NO;
                for (RadioStation *e in merged) {
                    if ([e.streamURL.absoluteString isEqualToString:s.streamURL.absoluteString]) { exists = YES; break; }
                    if ([e.name isEqualToString:s.name]) { exists = YES; break; }
                }
                if (!exists) [merged addObject:s];
            }
            idx++;
            if (idx > 50) break;
        }
    };

    void (^enterSearch)(NSString *) = ^(NSString *pathQuery) {
        dispatch_group_enter(group);
        [self getJSON:pathQuery completion:^(id json, NSError *error) {
            if (error) lastError = error; else appendJSON(json);
            dispatch_group_leave(group);
        }];
    };

    // Build unique search terms — Chinese name first for CN cities (API often only indexes 中文)
    NSMutableOrderedSet *terms = [NSMutableOrderedSet orderedSet];
    if (city.region == RadioRegionChina && city.nameCN.length) {
        [terms addObject:city.nameCN];
    }
    for (NSString *t in city.searchTerms) {
        if ([t isKindOfClass:[NSString class]] && t.length) [terms addObject:t];
    }
    if (city.nameEN.length) [terms addObject:city.nameEN];
    if (city.nameCN.length) [terms addObject:city.nameCN];

    NSInteger termBudget = 0;
    for (NSString *term in terms) {
        if (termBudget >= 4) break;
        // name search WITHOUT forcing English-only country filter miss
        enterSearch([NSString stringWithFormat:
            @"/json/stations/search?name=%@&hidebroken=true&order=clickcount&reverse=true&limit=20",
            [self encode:term]]);
        enterSearch([NSString stringWithFormat:
            @"/json/stations/search?name=%@&countrycode=%@&hidebroken=true&order=clickcount&reverse=true&limit=20",
            [self encode:term], city.countryCode]);
        enterSearch([NSString stringWithFormat:
            @"/json/stations/search?tag=%@&hidebroken=true&order=clickcount&reverse=true&limit=15",
            [self encode:term]]);
        termBudget++;
    }

    // State search (EN + CN). Many CN entries use province English like Szechuan.
    enterSearch([NSString stringWithFormat:
        @"/json/stations/search?state=%@&countrycode=%@&hidebroken=true&order=clickcount&reverse=true&limit=25",
        [self encode:city.nameEN], city.countryCode]);
    if (city.region == RadioRegionChina) {
        enterSearch([NSString stringWithFormat:
            @"/json/stations/search?state=%@&hidebroken=true&order=clickcount&reverse=true&limit=20",
            [self encode:city.nameCN]]);
    }

    // Country pool — only keep rows that actually mention the city
    dispatch_group_enter(group);
    NSString *qCountry = [NSString stringWithFormat:
        @"/json/stations/search?countrycode=%@&hidebroken=true&order=clickcount&reverse=true&limit=60",
        city.countryCode];
    [self getJSON:qCountry completion:^(id json, NSError *error) {
        if (error) {
            lastError = error;
        } else if ([json isKindOfClass:[NSArray class]]) {
            NSMutableArray *filtered = [NSMutableArray array];
            for (NSDictionary *d in (NSArray *)json) {
                if ([self dictionary:d matchesCity:city]) [filtered addObject:d];
            }
            // Do NOT dump unrelated national top stations — that made Chengdu look like random CN radio
            if (filtered.count > 0) appendJSON(filtered);
        }
        dispatch_group_leave(group);
    }];

    dispatch_group_notify(group, dispatch_get_main_queue(), ^{
        NSArray *result = [merged copy];
        // Prefer stations whose name/tags mention the city when we have mixed results
        NSMutableArray *preferred = [NSMutableArray array];
        NSMutableArray *rest = [NSMutableArray array];
        for (RadioStation *s in result) {
            BOOL hit = NO;
            for (NSString *term in terms) {
                if ([s.name localizedCaseInsensitiveContainsString:term]) { hit = YES; break; }
            }
            if (hit) [preferred addObject:s]; else [rest addObject:s];
        }
        result = preferred.count ? [preferred arrayByAddingObjectsFromArray:rest] : result;

        if (result.count == 0) {
            result = [self curatedFallbacksForCity:city];
        } else if (result.count < 3) {
            result = [result arrayByAddingObjectsFromArray:[self curatedFallbacksForCity:city]];
        }
        if (result.count > 24) result = [result subarrayWithRange:NSMakeRange(0, 24)];
        completion(result, result.count ? nil : lastError);
    });
}

@end
