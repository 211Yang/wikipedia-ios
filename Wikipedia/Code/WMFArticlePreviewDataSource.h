//  Created by Monte Hurd on 12/16/15.
//  Copyright (c) 2015 Wikimedia Foundation. All rights reserved.

#import <Foundation/Foundation.h>
#import "WMFDataSource.h"
#import "WMFTitleListDataSource.h"

NS_ASSUME_NONNULL_BEGIN

@class MWKSearchResult;
@class WMFArticlePreviewFetcher;
@class MWKSavedPageList;
@class MWKDataStore;

@interface WMFArticlePreviewDataSource : WMFDataSource
    <WMFTitleListDataSource>

@property (nonatomic, strong, readonly, nullable) NSArray<MWKSearchResult*>* previewResults;
@property (nonatomic, strong, readonly) MWKDataStore* dataStore;

- (instancetype)initWithArticleURLs:(NSArray<NSURL*>*)articleURLs
                     domainURL:(NSURL*)domainURL
                     dataStore:(MWKDataStore*)dataStore
                       fetcher:(WMFArticlePreviewFetcher*)fetcher NS_DESIGNATED_INITIALIZER;

@end

NS_ASSUME_NONNULL_END
