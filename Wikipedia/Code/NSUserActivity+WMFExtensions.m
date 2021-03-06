#import "NSUserActivity+WMFExtensions.h"
#import <WMF/WMF-Swift.h>

@import CoreSpotlight;
@import MobileCoreServices;

@implementation NSUserActivity (WMFExtensions)

+ (void)wmf_makeActivityActive:(NSUserActivity *)activity {
    static NSUserActivity *_current = nil;

    if (_current) {
        [_current invalidate];
        _current = nil;
    }

    _current = activity;
    [_current becomeCurrent];
}

+ (instancetype)wmf_activityWithType:(NSString *)type {
    NSUserActivity *activity = [[NSUserActivity alloc] initWithActivityType:[NSString stringWithFormat:@"org.wikimedia.wikipedia.%@", [type lowercaseString]]];

    activity.eligibleForHandoff = YES;
    activity.eligibleForSearch = YES;
    activity.eligibleForPublicIndexing = YES;
    activity.keywords = [NSSet setWithArray:@[@"Wikipedia", @"Wikimedia", @"Wiki"]];

    return activity;
}

+ (instancetype)wmf_pageActivityWithName:(NSString *)pageName {
    NSUserActivity *activity = [self wmf_activityWithType:[pageName lowercaseString]];
    activity.title = pageName;
    activity.userInfo = @{ @"WMFPage": pageName };

    if ([[NSProcessInfo processInfo] wmf_isOperatingSystemMajorVersionAtLeast:9]) {
        NSMutableSet *set = [activity.keywords mutableCopy];
        [set addObjectsFromArray:[pageName componentsSeparatedByString:@" "]];
        activity.keywords = set;
    }

    return activity;
}

+ (instancetype)wmf_contentActivityWithURL:(NSURL *)url {
    NSUserActivity *activity = [self wmf_activityWithType:@"Content"];
    activity.userInfo = @{ @"WMFURL": url };
    return activity;
}

+ (instancetype)wmf_placesActivityWithURL:(NSURL *)activityURL {
    NSURLComponents *components = [NSURLComponents componentsWithURL:activityURL resolvingAgainstBaseURL:NO];
    NSURL *articleURL = nil;
    for (NSURLQueryItem *item in components.queryItems) {
        if ([item.name isEqualToString:@"WMFArticleURL"]) {
            NSString *articleURLString = item.value;
            articleURL = [NSURL URLWithString:articleURLString];
            break;
        }
    }
    NSUserActivity *activity = [self wmf_pageActivityWithName:@"Places"];
    activity.webpageURL = articleURL;
    return activity;
}

+ (instancetype)wmf_exploreViewActivity {
    NSUserActivity *activity = [self wmf_pageActivityWithName:@"Explore"];
    return activity;
}

+ (instancetype)wmf_savedPagesViewActivity {
    NSUserActivity *activity = [self wmf_pageActivityWithName:@"Saved"];
    return activity;
}

+ (instancetype)wmf_recentViewActivity {
    NSUserActivity *activity = [self wmf_pageActivityWithName:@"History"];
    return activity;
}

+ (instancetype)wmf_searchViewActivity {
    NSUserActivity *activity = [self wmf_pageActivityWithName:@"Search"];
    return activity;
}

+ (instancetype)wmf_settingsViewActivity {
    NSUserActivity *activity = [self wmf_pageActivityWithName:@"Settings"];
    return activity;
}

+ (nullable instancetype)wmf_activityForWikipediaScheme:(NSURL *)url {
    if (![url.scheme isEqualToString:@"wikipedia"] && ![url.scheme isEqualToString:@"wikipedia-official"]) {
        return nil;
    }

    if ([url.host isEqualToString:@"content"]) {
        return [self wmf_contentActivityWithURL:url];
    } else if ([url.host isEqualToString:@"explore"]) {
        return [self wmf_exploreViewActivity];
    } else if ([url.host isEqualToString:@"places"]) {
        return [self wmf_placesActivityWithURL:url];
    } else if ([url.host isEqualToString:@"saved"]) {
        return [self wmf_savedPagesViewActivity];
    } else if ([url.host isEqualToString:@"history"]) {
        return [self wmf_recentViewActivity];
    } else if ([url wmf_valueForQueryKey:@"search"] != nil) {
        NSURLComponents *components = [NSURLComponents componentsWithURL:url resolvingAgainstBaseURL:NO];
        components.scheme = @"https";
        return [self wmf_searchResultsActivitySearchSiteURL:components.URL
                                                 searchTerm:[url wmf_valueForQueryKey:@"search"]];
    } else {
        NSURLComponents *components = [NSURLComponents componentsWithURL:url resolvingAgainstBaseURL:NO];
        components.scheme = @"https";
        NSURL *wikipediaURL = components.URL;
        if ([wikipediaURL wmf_isWikiResource]) {
            return [self wmf_articleViewActivityWithURL:wikipediaURL];
        }
    }
    return nil;
}

+ (instancetype)wmf_articleViewActivityWithArticle:(MWKArticle *)article {
    NSParameterAssert(article.url.wmf_title);
    NSParameterAssert(article.displaytitle);

    NSUserActivity *activity = [self wmf_articleViewActivityWithURL:article.url];
    if ([[NSProcessInfo processInfo] wmf_isOperatingSystemMajorVersionAtLeast:9]) {
        activity.contentAttributeSet = article.searchableItemAttributes;
    }
    return activity;
}

+ (instancetype)wmf_articleViewActivityWithURL:(NSURL *)url {
    NSParameterAssert(url.wmf_title);

    NSUserActivity *activity = [self wmf_activityWithType:@"article"];
    activity.title = url.wmf_title;
    activity.webpageURL = [NSURL wmf_desktopURLForURL:url];

    if ([[NSProcessInfo processInfo] wmf_isOperatingSystemMajorVersionAtLeast:9]) {
        NSMutableSet *set = [activity.keywords mutableCopy];
        [set addObjectsFromArray:[url.wmf_title componentsSeparatedByString:@" "]];
        activity.keywords = set;
        activity.expirationDate = [[NSDate date] dateByAddingTimeInterval:60 * 60 * 24 * 7];
        activity.contentAttributeSet = url.searchableItemAttributes;
    }
    return activity;
}

+ (instancetype)wmf_searchResultsActivitySearchSiteURL:(NSURL *)url searchTerm:(NSString *)searchTerm {
    NSURLComponents *components = [[NSURLComponents alloc] initWithURL:url resolvingAgainstBaseURL:NO];
    components.path = @"/w/index.php";
    components.query = [NSString stringWithFormat:@"search=%@&title=Special:Search&fulltext=1", searchTerm];
    url = [components URL];

    NSUserActivity *activity = [self wmf_activityWithType:@"Searchresults"];

    activity.title = [NSString stringWithFormat:@"Search for %@", searchTerm];
    activity.webpageURL = url;

    activity.eligibleForSearch = NO;
    activity.eligibleForPublicIndexing = NO;

    return activity;
}

- (WMFUserActivityType)wmf_type {
    if (self.userInfo[@"WMFPage"] != nil) {
        NSString *page = self.userInfo[@"WMFPage"];
        if ([page isEqualToString:@"Explore"]) {
            return WMFUserActivityTypeExplore;
        } else if ([page isEqualToString:@"Places"]) {
            return WMFUserActivityTypePlaces;
        } else if ([page isEqualToString:@"Saved"]) {
            return WMFUserActivityTypeSavedPages;
        } else if ([page isEqualToString:@"History"]) {
            return WMFUserActivityTypeHistory;
        } else if ([page isEqualToString:@"Search"]) {
            return WMFUserActivityTypeSearch;
        } else {
            return WMFUserActivityTypeSettings;
        }
    } else if ([self wmf_contentURL]) {
        return WMFUserActivityTypeContent;
    } else if ([self.webpageURL.absoluteString containsString:@"/w/index.php?search="]) {
        return WMFUserActivityTypeSearchResults;
    } else if ([[NSProcessInfo processInfo] wmf_isOperatingSystemMajorVersionAtLeast:10] && [self.activityType isEqualToString:CSQueryContinuationActionType]) {
        return WMFUserActivityTypeSearchResults;
    } else {
        if (self.webpageURL.wmf_isWikiResource) {
            return WMFUserActivityTypeArticle;
        } else {
            return WMFUserActivityTypeGenericLink;
        }
    }
}

- (nullable NSString *)wmf_searchTerm {
    if (self.wmf_type != WMFUserActivityTypeSearchResults) {
        return nil;
    }

    if ([[NSProcessInfo processInfo] wmf_isOperatingSystemMajorVersionAtLeast:10] && [self.activityType isEqualToString:CSQueryContinuationActionType]) {
        return self.userInfo[CSSearchQueryString];
    } else {
        NSURLComponents *components = [NSURLComponents componentsWithString:self.webpageURL.absoluteString];
        NSArray *queryItems = components.queryItems;
        NSURLQueryItem *item = [queryItems wmf_match:^BOOL(NSURLQueryItem *obj) {
            if ([[obj name] isEqualToString:@"search"]) {
                return YES;
            } else {
                return NO;
            }
        }];
        return [item value];
    }
}

- (NSURL *)wmf_articleURL {
    if (self.userInfo[CSSearchableItemActivityIdentifier] != nil) {
        return [NSURL URLWithString:self.userInfo[CSSearchableItemActivityIdentifier]];
    } else {
        return self.webpageURL;
    }
}

- (NSURL *)wmf_contentURL {
    return self.userInfo[@"WMFURL"];
}

+ (NSURLComponents *)wmf_baseURLComponentsForActivityOfType:(WMFUserActivityType)type {
    NSString *host = nil;
    switch (type) {
        case WMFUserActivityTypeSavedPages:
            host = @"saved";
            break;
        case WMFUserActivityTypeHistory:
            host = @"history";
            break;
        case WMFUserActivityTypeSearchResults:
        case WMFUserActivityTypeSearch:
            host = @"search";
            break;
        case WMFUserActivityTypeSettings:
            host = @"settings";
            break;
        case WMFUserActivityTypeContent:
            host = @"content";
            break;
        case WMFUserActivityTypeArticle:
            host = @"article";
            break;
        case WMFUserActivityTypePlaces:
            host = @"places";
            break;
        case WMFUserActivityTypeExplore:
        default:
            host = @"explore";
            break;
    }
    NSURLComponents *components = [NSURLComponents new];
    components.host = host;
    components.scheme = @"wikipedia";
    components.path = @"/";
    return components;
}

+ (NSURL *)wmf_baseURLForActivityOfType:(WMFUserActivityType)type {
    return [self wmf_baseURLComponentsForActivityOfType:type].URL;
}

+ (NSURL *)wmf_URLForActivityOfType:(WMFUserActivityType)type withArticleURL:(NSURL *)articleURL {
    NSURLComponents *components = [self wmf_baseURLComponentsForActivityOfType:type];
    NSURLQueryItem *item = [NSURLQueryItem queryItemWithName:@"WMFArticleURL" value:articleURL.absoluteString];
    if (item) {
        components.queryItems = @[item];
    }
    return components.URL;
}

@end
