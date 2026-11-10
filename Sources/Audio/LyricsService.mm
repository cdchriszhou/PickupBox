#import "LyricsService.h"
#import <AVFoundation/AVFoundation.h>

@implementation LyricsLine
+ (instancetype)lineWithTime:(NSTimeInterval)time text:(NSString *)text {
    LyricsLine *l = [LyricsLine new];
    l.time = time;
    l.text = text ?: @"";
    return l;
}
@end

@implementation LyricsResult
@end

@implementation LyricsService {
    NSURLSessionDataTask *_task;
    NSInteger _requestID;
}

+ (instancetype)shared {
    static LyricsService *s;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ s = [LyricsService new]; });
    return s;
}

- (void)cancel {
    [_task cancel];
    _task = nil;
    _requestID++;
}

#pragma mark - Public

- (void)fetchLyricsForTitle:(NSString *)title
                     artist:(NSString *)artist
                      album:(NSString *)album
                   duration:(NSTimeInterval)duration
                    fileURL:(NSURL *)fileURL
                 completion:(void (^)(LyricsResult *, NSString *))completion {
    if (!completion) return;
    [self cancel];
    NSInteger rid = _requestID;

    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        // 1) Sidecar .lrc next to the audio file
        if (fileURL.isFileURL) {
            LyricsResult *local = [self loadSidecarLRCBesideURL:fileURL];
            if (local.lines.count > 0) {
                if (rid != self->_requestID) return;
                dispatch_async(dispatch_get_main_queue(), ^{ completion(local, nil); });
                return;
            }
        }

        // 2) Embedded USLT / lyrics metadata
        if (fileURL.isFileURL) {
            LyricsResult *embedded = [self loadEmbeddedLyricsFromURL:fileURL];
            if (embedded.lines.count > 0) {
                if (rid != self->_requestID) return;
                dispatch_async(dispatch_get_main_queue(), ^{ completion(embedded, nil); });
                return;
            }
        }

        // 3) Online — LRCLIB (free, no API key)
        NSString *cleanTitle = [self scrubQuery:title];
        NSString *cleanArtist = [self scrubQuery:artist];
        if (cleanTitle.length == 0) {
            dispatch_async(dispatch_get_main_queue(), ^{
                completion(nil, @"缺少曲名，无法搜索歌词");
            });
            return;
        }

        // Try structured get first, then search
        [self fetchFromLRCLIBTitle:cleanTitle
                            artist:cleanArtist
                             album:[self scrubQuery:album]
                          duration:duration
                         requestID:rid
                        completion:completion];
    });
}

#pragma mark - Local

- (LyricsResult *)loadSidecarLRCBesideURL:(NSURL *)fileURL {
    NSString *base = fileURL.URLByDeletingPathExtension.path;
    if (base.length == 0) return nil;
    NSArray *candidates = @[
        [base stringByAppendingPathExtension:@"lrc"],
        [base stringByAppendingPathExtension:@"LRC"],
        [base stringByAppendingString:@".txt"],
    ];
    for (NSString *path in candidates) {
        NSError *err = nil;
        NSString *text = [NSString stringWithContentsOfFile:path
                                                   encoding:NSUTF8StringEncoding
                                                      error:&err];
        if (!text) {
            text = [NSString stringWithContentsOfFile:path
                                             encoding:CFStringConvertEncodingToNSStringEncoding(kCFStringEncodingGB_18030_2000)
                                                error:&err];
        }
        if (text.length == 0) continue;
        LyricsResult *r = [self parseLyricsText:text source:@"本地文件"];
        if (r.lines.count > 0) return r;
    }
    return nil;
}

- (LyricsResult *)loadEmbeddedLyricsFromURL:(NSURL *)fileURL {
    AVURLAsset *asset = [AVURLAsset URLAssetWithURL:fileURL options:nil];
    dispatch_semaphore_t sem = dispatch_semaphore_create(0);
    __block NSString *lyrics = nil;
    [asset loadValuesAsynchronouslyForKeys:@[@"commonMetadata", @"availableMetadataFormats"] completionHandler:^{
        NSMutableArray<AVMetadataItem *> *items = [NSMutableArray array];
        [items addObjectsFromArray:asset.commonMetadata];
        for (AVMetadataFormat fmt in asset.availableMetadataFormats) {
            [items addObjectsFromArray:[asset metadataForFormat:fmt]];
        }
        for (AVMetadataItem *item in items) {
            NSString *key = item.commonKey.description.lowercaseString ?: @"";
            NSString *idKey = ([item.key isKindOfClass:[NSString class]]
                               ? [(NSString *)item.key lowercaseString] : @"");
            BOOL isLyrics = [key containsString:@"lyric"] ||
                            [idKey containsString:@"uslt"] ||
                            [idKey containsString:@"©lyr"] ||
                            [idKey isEqualToString:@"lyrics"];
            if (!isLyrics) continue;
            id val = item.value;
            if ([val isKindOfClass:[NSString class]]) {
                lyrics = (NSString *)val;
                break;
            }
            if ([val isKindOfClass:[NSData class]]) {
                lyrics = [[NSString alloc] initWithData:(NSData *)val encoding:NSUTF8StringEncoding]
                      ?: [[NSString alloc] initWithData:(NSData *)val encoding:NSUnicodeStringEncoding];
                if (lyrics.length) break;
            }
        }
        dispatch_semaphore_signal(sem);
    }];
    dispatch_semaphore_wait(sem, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.5 * NSEC_PER_SEC)));
    if (lyrics.length == 0) return nil;
    return [self parseLyricsText:lyrics source:@"内嵌标签"];
}

#pragma mark - LRCLIB

- (void)fetchFromLRCLIBTitle:(NSString *)title
                      artist:(NSString *)artist
                       album:(NSString *)album
                    duration:(NSTimeInterval)duration
                   requestID:(NSInteger)rid
                  completion:(void (^)(LyricsResult *, NSString *))completion {
    // Prefer /api/get when we have artist + duration
    if (artist.length > 0 && duration > 5) {
        NSURLComponents *c = [NSURLComponents componentsWithString:@"https://lrclib.net/api/get"];
        NSMutableArray *items = [NSMutableArray array];
        [items addObject:[NSURLQueryItem queryItemWithName:@"track_name" value:title]];
        [items addObject:[NSURLQueryItem queryItemWithName:@"artist_name" value:artist]];
        if (album.length) [items addObject:[NSURLQueryItem queryItemWithName:@"album_name" value:album]];
        [items addObject:[NSURLQueryItem queryItemWithName:@"duration"
                                                     value:[NSString stringWithFormat:@"%.0f", duration]]];
        c.queryItems = items;
        [self getJSON:c.URL requestID:rid completion:^(NSDictionary *json, NSError *err) {
            if (rid != self->_requestID) return;
            LyricsResult *r = [self resultFromLRCLIBObject:json];
            if (r.lines.count > 0) {
                dispatch_async(dispatch_get_main_queue(), ^{ completion(r, nil); });
                return;
            }
            [self searchLRCLIBQuery:[self searchQueryTitle:title artist:artist]
                          requestID:rid
                         completion:completion];
        }];
        return;
    }
    [self searchLRCLIBQuery:[self searchQueryTitle:title artist:artist]
                  requestID:rid
                 completion:completion];
}

- (void)searchLRCLIBQuery:(NSString *)q
                requestID:(NSInteger)rid
               completion:(void (^)(LyricsResult *, NSString *))completion {
    NSURLComponents *c = [NSURLComponents componentsWithString:@"https://lrclib.net/api/search"];
    c.queryItems = @[ [NSURLQueryItem queryItemWithName:@"q" value:q] ];
    [self getJSON:c.URL requestID:rid completion:^(id json, NSError *err) {
        if (rid != self->_requestID) return;
        if (err) {
            dispatch_async(dispatch_get_main_queue(), ^{
                completion(nil, @"网络歌词搜索失败，请检查网络");
            });
            return;
        }
        NSArray *arr = [json isKindOfClass:[NSArray class]] ? json : @[];
        LyricsResult *best = nil;
        for (id obj in arr) {
            if (![obj isKindOfClass:[NSDictionary class]]) continue;
            LyricsResult *r = [self resultFromLRCLIBObject:obj];
            if (r.lines.count == 0) continue;
            if (r.synced) { best = r; break; }
            if (!best) best = r;
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            if (best) completion(best, nil);
            else completion(nil, @"未找到匹配歌词");
        });
    }];
}

- (LyricsResult *)resultFromLRCLIBObject:(NSDictionary *)json {
    if (![json isKindOfClass:[NSDictionary class]]) return nil;
    NSString *synced = json[@"syncedLyrics"];
    NSString *plain = json[@"plainLyrics"];
    if ([synced isKindOfClass:[NSString class]] && synced.length > 0) {
        return [self parseLyricsText:synced source:@"网络 LRCLIB"];
    }
    if ([plain isKindOfClass:[NSString class]] && plain.length > 0) {
        return [self parseLyricsText:plain source:@"网络 LRCLIB"];
    }
    return nil;
}

- (void)getJSON:(NSURL *)url
      requestID:(NSInteger)rid
     completion:(void (^)(id json, NSError *err))completion {
    if (!url) {
        completion(nil, [NSError errorWithDomain:@"Lyrics" code:-1 userInfo:nil]);
        return;
    }
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:url];
    req.timeoutInterval = 12;
    [req setValue:@"PickupBox/1.0 (macOS; lyrics)" forHTTPHeaderField:@"User-Agent"];
    __weak LyricsService *weakSelf = self;
    _task = [[NSURLSession sharedSession] dataTaskWithRequest:req
                                            completionHandler:^(NSData *data, NSURLResponse *resp, NSError *error) {
        LyricsService *strongSelf = weakSelf;
        if (!strongSelf) return;
        strongSelf->_task = nil;
        if (rid != strongSelf->_requestID) return;
        if (error || data.length == 0) {
            completion(nil, error ?: [NSError errorWithDomain:@"Lyrics" code:-2 userInfo:nil]);
            return;
        }
        NSInteger code = [(NSHTTPURLResponse *)resp statusCode];
        if (code == 404) {
            completion(@{}, nil);
            return;
        }
        NSError *jerr = nil;
        id obj = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jerr];
        completion(obj, jerr);
    }];
    [_task resume];
}

#pragma mark - Parse

- (LyricsResult *)parseLyricsText:(NSString *)text source:(NSString *)source {
    LyricsResult *result = [LyricsResult new];
    result.sourceLabel = source;
    if (text.length == 0) {
        result.lines = @[];
        return result;
    }

    // Normalize newlines
    text = [[text stringByReplacingOccurrencesOfString:@"\r\n" withString:@"\n"]
                   stringByReplacingOccurrencesOfString:@"\r" withString:@"\n"];

    NSMutableArray<LyricsLine *> *lines = [NSMutableArray array];
    NSRegularExpression *re = [NSRegularExpression
        regularExpressionWithPattern:@"\\[(\\d{1,2}):(\\d{1,2})(?:\\.(\\d{1,3}))?\\]"
                             options:0 error:nil];

    BOOL anyTimed = NO;
    for (NSString *raw in [text componentsSeparatedByString:@"\n"]) {
        NSString *line = [raw stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (line.length == 0) continue;
        // Skip LRC metadata tags [ti:][ar:][al:][by:][offset:]
        if ([line hasPrefix:@"["] && line.length > 4) {
            unichar c = [line characterAtIndex:1];
            if ((c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z')) continue;
        }

        NSArray<NSTextCheckingResult *> *matches = [re matchesInString:line options:0
                                                                 range:NSMakeRange(0, line.length)];
        if (matches.count > 0) {
            anyTimed = YES;
            NSTextCheckingResult *last = matches.lastObject;
            NSString *body = [[line substringFromIndex:NSMaxRange(last.range)]
                              stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
            if (body.length == 0) continue;
            for (NSTextCheckingResult *m in matches) {
                NSInteger min = [[line substringWithRange:[m rangeAtIndex:1]] integerValue];
                NSInteger sec = [[line substringWithRange:[m rangeAtIndex:2]] integerValue];
                NSTimeInterval frac = 0;
                if ([m rangeAtIndex:3].location != NSNotFound) {
                    NSString *f = [line substringWithRange:[m rangeAtIndex:3]];
                    if (f.length == 1) frac = f.doubleValue / 10.0;
                    else if (f.length == 2) frac = f.doubleValue / 100.0;
                    else frac = f.doubleValue / 1000.0;
                }
                NSTimeInterval t = min * 60.0 + sec + frac;
                [lines addObject:[LyricsLine lineWithTime:t text:body]];
            }
        } else {
            // Plain lyric line
            [lines addObject:[LyricsLine lineWithTime:-1 text:line]];
        }
    }

    if (anyTimed) {
        [lines sortUsingComparator:^NSComparisonResult(LyricsLine *a, LyricsLine *b) {
            if (a.time < b.time) return NSOrderedAscending;
            if (a.time > b.time) return NSOrderedDescending;
            return NSOrderedSame;
        }];
        // Drop untimed leftovers mixed in
        NSMutableArray *timed = [NSMutableArray array];
        for (LyricsLine *l in lines) if (l.time >= 0) [timed addObject:l];
        lines = timed;
    } else {
        // Assign fake spacing so UI can still scroll as a list
        for (NSUInteger i = 0; i < lines.count; i++) {
            lines[i].time = i * 3.0;
        }
    }

    result.lines = lines;
    result.synced = anyTimed;
    return result;
}

#pragma mark - Helpers

- (NSString *)scrubQuery:(NSString *)s {
    if (s.length == 0) return @"";
    NSString *t = [s stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    // Strip track numbers / brackets noise
    t = [t stringByReplacingOccurrencesOfString:@"^\\d+[\\s.\\-_]+" withString:@""
                                        options:NSRegularExpressionSearch range:NSMakeRange(0, t.length)];
    return t;
}

- (NSString *)searchQueryTitle:(NSString *)title artist:(NSString *)artist {
    if (artist.length && title.length) return [NSString stringWithFormat:@"%@ %@", artist, title];
    return title ?: @"";
}

@end
