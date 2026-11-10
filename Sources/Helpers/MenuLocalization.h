#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, MenuLanguage) {
    MenuLanguageEnglish    = 0, // default
    MenuLanguageChinese    = 1,
    MenuLanguageFrench     = 2,
    MenuLanguagePortuguese = 3,
};

/// Menu-bar strings only — does not affect the console UI language.
@interface MenuLocalization : NSObject

+ (MenuLanguage)currentLanguage;
+ (void)setCurrentLanguage:(MenuLanguage)language;
+ (NSString *)stringForKey:(NSString *)key;
+ (NSArray<NSDictionary *> *)languageChoices; // @{ @"lang": @(MenuLanguage), @"title": @"…" }

@end

NS_ASSUME_NONNULL_END
