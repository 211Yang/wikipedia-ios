#import "WMFRandomContentSource.h"
#import "WMFContentGroupDataStore.h"
#import "WMFArticleDataStore.h"
#import "WMFRandomArticleFetcher.h"

NS_ASSUME_NONNULL_BEGIN

@interface WMFRandomContentSource ()

@property (readwrite, nonatomic, strong) NSURL *siteURL;

@property (readwrite, nonatomic, strong) WMFContentGroupDataStore *contentStore;
@property (readwrite, nonatomic, strong) WMFArticleDataStore *previewStore;

@property (nonatomic, strong) WMFRandomArticleFetcher *fetcher;

@end

@implementation WMFRandomContentSource

- (instancetype)initWithSiteURL:(NSURL *)siteURL contentGroupDataStore:(WMFContentGroupDataStore *)contentStore articlePreviewDataStore:(WMFArticleDataStore *)previewStore {
    NSParameterAssert(siteURL);
    NSParameterAssert(contentStore);
    NSParameterAssert(previewStore);
    self = [super init];
    if (self) {
        self.siteURL = siteURL;
        self.contentStore = contentStore;
        self.previewStore = previewStore;
    }
    return self;
}

- (WMFRandomArticleFetcher *)fetcher {
    if (_fetcher == nil) {
        _fetcher = [[WMFRandomArticleFetcher alloc] init];
    }
    return _fetcher;
}
#pragma mark - WMFContentSource

- (void)startUpdating {
}

- (void)stopUpdating {
}

- (void)loadNewContentForce:(BOOL)force completion:(nullable dispatch_block_t)completion {
    [self loadContentForDate:[NSDate date] force:force completion:completion];
}

- (void)preloadContentForNumberOfDays:(NSInteger)days force:(BOOL)force completion:(nullable dispatch_block_t)completion {
    if (days < 1) {
        if (completion) {
            completion();
        }
        return;
    }

    NSDate *now = [NSDate date];

    NSCalendar *calendar = [NSCalendar wmf_gregorianCalendar];

    WMFTaskGroup *group = [WMFTaskGroup new];

    for (NSUInteger i = 0; i < days; i++) {
        [group enter];
        NSDate *date = [calendar dateByAddingUnit:NSCalendarUnitDay value:-i toDate:now options:NSCalendarMatchStrictly];
        [self loadContentForDate:date
                           force:force
                      completion:^{
                          [group leave];
                      }];
    }

    [group waitInBackgroundWithCompletion:completion];
}

- (void)loadContentForDate:(NSDate *)date intoManagedObjectContext:(NSManagedObjectContext *)managedObjectContext completion:(nullable dispatch_block_t)completion {
    NSURL *siteURL = self.siteURL;
    
    if (!siteURL) {
        if (completion) {
            completion();
        }
        return;
    }
    
    NSURL *contentGroupURL = [WMFContentGroup randomContentGroupURLForSiteURL:siteURL date:date];
    WMFContentGroup *existingGroup = [self.contentStore contentGroupForURL:contentGroupURL inManagedObjectContext:managedObjectContext];
    if (existingGroup) {
        if (completion) {
            completion();
        }
        return;
    }

    @weakify(self)
    [self.fetcher fetchRandomArticleWithSiteURL:self.siteURL
        failure:^(NSError *error) {
            if (completion) {
                completion();
            }
        }
        success:^(MWKSearchResult *result) {
            @strongify(self);
            if (!self) {
                if (completion) {
                    completion();
                }
                return;
            }

            NSURL *articleURL = [siteURL wmf_URLWithTitle:result.displayTitle];
            if (!articleURL) {
                if (completion) {
                    completion();
                }
                return;
            }
            
            [self.contentStore fetchOrCreateGroupForURL:contentGroupURL ofKind:WMFContentGroupKindRandom forDate:date withSiteURL:siteURL associatedContent:@[articleURL] inManagedObjectContext:managedObjectContext  withCustomizationBlock:^(WMFContentGroup * _Nonnull group) {
                
            }];
            [self.previewStore addPreviewWithURL:articleURL updatedWithSearchResult:result];
            
            if (completion) {
                completion();
            }
        }];
}

- (void)removeAllContentFromManagedObjectContext:(NSManagedObjectContext *)managedObjectContext {
    [self.contentStore removeAllContentGroupsOfKind:WMFContentGroupKindRandom fromManagedObjectContext:managedObjectContext];
}

@end

NS_ASSUME_NONNULL_END
