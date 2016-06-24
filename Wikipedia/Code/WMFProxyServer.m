#import "WMFProxyServer.h"

#import "GCDWebServer.h"
#import "GCDWebServerDataResponse.h"
#import "GCDWebServerErrorResponse.h"
#import "GCDWebServerFileResponse.h"
#import "NSURL+WMFExtras.h"
#import "NSString+WMFExtras.h"
#import "NSURL+WMFProxyServer.h"

@interface WMFProxyServer ()
@property (nonatomic, strong, nonnull) GCDWebServer* webServer;
@property (nonatomic, copy, nonnull) NSString* secret;
@property (nonatomic, copy, nonnull) NSString* hostedFolderPath;
@property (nonatomic) NSURLComponents* hostURLComponents;
@property (nonatomic, readonly) GCDWebServerAsyncProcessBlock defaultHandler;
@end

@implementation WMFProxyServer

+ (WMFProxyServer*)sharedProxyServer {
    static dispatch_once_t onceToken;
    static WMFProxyServer* sharedProxyServer;
    dispatch_once(&onceToken, ^{
        sharedProxyServer = [[WMFProxyServer alloc] init];
    });
    return sharedProxyServer;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        [self setup];
    }
    return self;
}

- (void)setup {
    NSString* secret = [[NSUUID UUID] UUIDString];
    self.secret    = secret;
    self.webServer = [[GCDWebServer alloc] init];

    NSURL* documentsURL = [[[NSFileManager defaultManager] URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask] lastObject];
    NSURL* assetsURL    = [documentsURL URLByAppendingPathComponent:@"assets"];
    self.hostedFolderPath = assetsURL.path;

    [self.webServer addDefaultHandlerForMethod:@"GET" requestClass:[GCDWebServerRequest class] asyncProcessBlock:self.defaultHandler];

    NSDictionary* options = @{GCDWebServerOption_BindToLocalhost: @(YES), //only accept requests from localhost
                              GCDWebServerOption_Port: @(0)};// allow the OS to pick a random port

    NSError* serverStartError = nil;
    if (![self.webServer startWithOptions:options error:&serverStartError]) {
        DDLogError(@"Error starting proxy: %@", serverStartError);
    }
}

#pragma mark - Proxy Request Handler

- (GCDWebServerAsyncProcessBlock)defaultHandler {
    @weakify(self);
    return ^(GCDWebServerRequest* request, GCDWebServerCompletionBlock completionBlock) {
               dispatch_block_t notFound = ^{
                   completionBlock([GCDWebServerErrorResponse responseWithClientError:kGCDWebServerHTTPStatusCode_NotFound message:@"404"]);
               };

               @strongify(self);
               if (!self) {
                   notFound();
                   return;
               }

               NSString* path      = request.path;
               NSArray* components = [path pathComponents];

               if (components.count < 3) { //ensure components exist and there are at least three
                   notFound();
                   return;
               }

               if (![components[1] isEqualToString:self.secret]) { //ensure the second component is the secret
                   notFound();
                   return;
               }

               NSString* baseComponent = components[2];

               if ([baseComponent isEqualToString:WMFProxyFileBasePath]) {
                   NSArray* localPathComponents = [components subarrayWithRange:NSMakeRange(3, components.count - 3)];
                   NSString* relativePath       = [NSString pathWithComponents:localPathComponents];
                   [self handleFileRequestForRelativePath:relativePath completionBlock:completionBlock];
               } else if ([baseComponent isEqualToString:WMFProxyImageBasePath]) {
                   NSString* originalSrc = request.query[WMFProxyImageOriginalSrcKey];
                   if (!originalSrc) {
                       notFound();
                       return;
                   }

                   if ([originalSrc hasPrefix:@"//"]) {
                       originalSrc = [@"https:" stringByAppendingString:originalSrc];
                   }

                   NSURL* imgURL = [NSURL URLWithString:originalSrc];
                   if (!imgURL) {
                       notFound();
                       return;
                   }

                   [self handleImageRequestForURL:imgURL completionBlock:completionBlock];
               } else {
                   notFound();
               }
    };
}

#pragma mark - Specific Handlers

- (void)handleFileRequestForRelativePath:(NSString*)relativePath completionBlock:(GCDWebServerCompletionBlock)completionBlock {
    NSString* fullPath      = [self.hostedFolderPath stringByAppendingPathComponent:relativePath];
    NSURL* localFileURL     = [NSURL fileURLWithPath:fullPath];
    NSNumber* isRegularFile = nil;
    NSError* fileReadError  = nil;
    if ([localFileURL getResourceValue:&isRegularFile forKey:NSURLIsRegularFileKey error:&fileReadError] && [isRegularFile boolValue]) {
        completionBlock([GCDWebServerFileResponse responseWithFile:localFileURL.path]);
    } else {
        completionBlock([GCDWebServerErrorResponse responseWithClientError:kGCDWebServerHTTPStatusCode_NotFound message:@"404"]);
    }
}

- (void)handleImageRequestForURL:(NSURL*)imgURL completionBlock:(GCDWebServerCompletionBlock)completionBlock {
    GCDWebServerErrorResponse* notFound = [GCDWebServerErrorResponse responseWithClientError:kGCDWebServerHTTPStatusCode_NotFound message:@"Image not found"];
    NSAssert(imgURL, @"imageProxy URL should not be nil");

    NSURLCache* URLCache                = [NSURLCache sharedURLCache];
    NSURLRequest* request               = [NSURLRequest requestWithURL:imgURL];
    NSCachedURLResponse* cachedResponse = [URLCache cachedResponseForRequest:request];

    if (cachedResponse.response && cachedResponse.data) {
        NSString* mimeType = cachedResponse.response.MIMEType;
        if (mimeType == nil) {
            mimeType = [imgURL wmf_mimeTypeForExtension];
        }
        NSAssert(mimeType != nil, @"MIME type not found for URL %@", imgURL);
        GCDWebServerDataResponse* gcdResponse = [[GCDWebServerDataResponse alloc] initWithData:cachedResponse.data contentType:mimeType];
        completionBlock(gcdResponse);
    } else {
        NSURLSessionDataTask* downloadImgTask = [[NSURLSession sharedSession] dataTaskWithRequest:request completionHandler:^(NSData* imgData, NSURLResponse* response, NSError* error) {
            if (response && imgData) {
                GCDWebServerDataResponse* gcdResponse = [[GCDWebServerDataResponse alloc] initWithData:imgData contentType:response.MIMEType];
                completionBlock(gcdResponse);
                NSCachedURLResponse* responseToCache = [[NSCachedURLResponse alloc] initWithResponse:response data:imgData];
                [URLCache storeCachedResponse:responseToCache forRequest:request];
            } else {
                completionBlock(notFound);
            }
        }];
        [downloadImgTask resume];
    }
}

#pragma - File Proxy Paths & URLs

- (NSURL*)proxyURLForRelativeFilePath:(NSString*)relativeFilePath fragment:(NSString*)fragment {
    NSString* secret = self.secret;
    if (!relativeFilePath || !secret) {
        return nil;
    }
    NSURLComponents* components = [NSURLComponents componentsWithURL:self.webServer.serverURL resolvingAgainstBaseURL:NO];
    components.path     = [NSString pathWithComponents:@[@"/", secret, WMFProxyFileBasePath, relativeFilePath]];
    components.fragment = fragment;
    return components.URL;
}

- (NSString*)localFilePathForRelativeFilePath:(NSString*)relativeFilePath {
    return [self.hostedFolderPath stringByAppendingPathComponent:relativeFilePath];
}

#pragma - Image Proxy URLs

- (NSURL*)proxyURLForImageURLString:(NSString*)imageURLString {
    NSString* secret = self.secret;
    if (!secret) {
        return nil;
    }
    
    NSURLComponents* components = [NSURLComponents componentsWithURL:self.webServer.serverURL resolvingAgainstBaseURL:NO];
    components.path = [NSString pathWithComponents:@[@"/", secret, WMFProxyImageBasePath]];
    
    return [components.URL wmf_imageProxyURLWithOriginalSrc:imageURLString];
}

- (NSString*)stringByReplacingImageURLsWithProxyURLsInHTMLString:(NSString*)HTMLString targetImageWidth:(NSUInteger)targetImageWidth {
    static NSRegularExpression* imageTagRegex;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSString* pattern = @"(?:<img\\s)([^>]*)(?:>)";
        imageTagRegex = [NSRegularExpression regularExpressionWithPattern:pattern
                                                          options:NSRegularExpressionCaseInsensitive
                                                            error:nil];
    });
    
    //defensively copy
    HTMLString = [HTMLString copy];
    
    NSMutableString *newHTMLString = [NSMutableString stringWithString:@""];

    __block NSInteger location = 0;
    [imageTagRegex enumerateMatchesInString:HTMLString options:0 range:NSMakeRange(0, HTMLString.length) usingBlock:^(NSTextCheckingResult * _Nullable imageTagResult, NSMatchingFlags flags, BOOL * _Nonnull stop) {
        //append the next chunk that we didn't match on to the new string
        NSString *nonMatchingStringToAppend = [HTMLString substringWithRange:NSMakeRange(location, imageTagResult.range.location - location)];
        [newHTMLString appendString:nonMatchingStringToAppend];
        
        //get just the image tag contents - everything between <img and >
        NSString *imageTagContents = [imageTagRegex replacementStringForResult:imageTagResult inString:HTMLString offset:0 template:@"$1"];
        //update those contents by changing the src, disabling the srcset, and adding other attributes used for scaling
        NSString *newImageTagContents = [self stringByUpdatingImageTagAttributesForProxyAndScalingInImageTagContents:imageTagContents withTargetImageWidth:targetImageWidth];
        //append the updated image tag to the new string
        [newHTMLString appendString:[@[@"<img ", newImageTagContents, @">"] componentsJoinedByString:@""]];
        
        location = imageTagResult.range.location + imageTagResult.range.length;
        *stop = false;
    }];
    
    //append the final chunk of the original string
    [newHTMLString appendString:[HTMLString substringWithRange:NSMakeRange(location, HTMLString.length - location)]];

    return newHTMLString;
}

- (NSString *)stringByUpdatingImageTagAttributesForProxyAndScalingInImageTagContents:(NSString *)imageTagContents withTargetImageWidth:(NSUInteger)targetImageWidth {
    static NSRegularExpression* attributeRegex;
    static NSRegularExpression* sizeRegex;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSString *attributePattern = @"(src|data-file-width|width)=[\"']?((?:.(?![\"']?\\s+(?:\\S+)=|[>\"']))+.)[\"']?"; //match on the three attributes we need to read: src, data-file-width, width
        attributeRegex = [NSRegularExpression regularExpressionWithPattern:attributePattern options:NSRegularExpressionCaseInsensitive error:nil];
        
        NSString *sizePattern = @"^[0-9]+(?=px-)";//match on numerals followed by px- at the beginning of the filename
        sizeRegex = [NSRegularExpression regularExpressionWithPattern:sizePattern options:NSRegularExpressionCaseInsensitive error:nil];
    });
    
    __block NSString *src = nil; //the image src
    __block NSRange srcAttributeRange = NSMakeRange(NSNotFound, 0); //the range of the full src attribute - src=blah
    __block NSInteger dataFileWidth = 0; //the original file width from data-file-width=
    __block NSInteger width = 0; //the width of the image from width=
    NSInteger attributeOffset = 0;
    [attributeRegex enumerateMatchesInString:imageTagContents options:0 range:NSMakeRange(0, imageTagContents.length) usingBlock:^(NSTextCheckingResult * _Nullable attributeResult, NSMatchingFlags flags, BOOL * _Nonnull stop) {
        NSString *attributeName = [[attributeRegex replacementStringForResult:attributeResult inString:imageTagContents offset:attributeOffset template:@"$1"] lowercaseString];
        NSString *attributeValue = [attributeRegex replacementStringForResult:attributeResult inString:imageTagContents offset:attributeOffset template:@"$2"];
        if ([attributeName isEqualToString:@"src"]) {
            src = attributeValue;
            srcAttributeRange = attributeResult.range;
        } else if ([attributeName isEqualToString:@"data-file-width"]) {
            dataFileWidth = [attributeValue integerValue];
        } else if ([attributeName isEqualToString:@"width"]) {
            width = [attributeValue integerValue];
        }
        *stop = dataFileWidth > 0 && srcAttributeRange.location != NSNotFound && width > 0;
    }];
    
    NSMutableString *newImageTagContents = [imageTagContents mutableCopy];
    
    
    NSMutableArray *srcPathComponents = [[src pathComponents] mutableCopy];
    NSString *resizedSrc = nil;
    //check to see if we should change the image size being requested - if we know the original file width (dataFileWidth) and the width is present and greater than or equal to 64, and it's a thumbnail URL, we should request a larger size
    if (dataFileWidth > 0 && (width == 0 || width >= 64) && srcPathComponents.count > 4 && [[srcPathComponents[srcPathComponents.count - 5] lowercaseString] isEqualToString:@"thumb"]) {
        NSString *filename = srcPathComponents[srcPathComponents.count - 1];
        if (dataFileWidth > targetImageWidth) { //if the original file width is larger than the target width
            //replace the thumbnail width prefix with the target width
            [sizeRegex enumerateMatchesInString:filename options:0 range:NSMakeRange(0, filename.length) usingBlock:^(NSTextCheckingResult * _Nullable sizeResult, NSMatchingFlags flags, BOOL * _Nonnull stop) {
                NSMutableString *newFilename = [filename mutableCopy];
                NSString *newSizeString = [NSString stringWithFormat:@"%llu", (unsigned long long)targetImageWidth];
                [newFilename replaceCharactersInRange:sizeResult.range withString:newSizeString];
                [srcPathComponents replaceObjectAtIndex:srcPathComponents.count - 1 withObject:newFilename];
                *stop = YES;
            }];
        } else if ([filename rangeOfString:@".svg" options:NSCaseInsensitiveSearch].location == NSNotFound) { //otherwise the original file is smaller than the target width, and we should just request the original image (as long as it's not an svg)
            //remove /thumb/ and the /##px- filename leaving only the original file path
            NSMutableIndexSet *indexSet = [NSMutableIndexSet indexSetWithIndex:srcPathComponents.count - 5];
            [indexSet addIndex:srcPathComponents.count - 1];
            [srcPathComponents removeObjectsAtIndexes:indexSet];
        }

        resizedSrc = [NSString pathWithComponents:srcPathComponents];
        if (![resizedSrc hasPrefix:@"//"] && [resizedSrc hasPrefix:@"/"]) {
            resizedSrc = [@[@"/", resizedSrc] componentsJoinedByString:@""];
        }
        src = resizedSrc;
    }
    
    if (src) {
        NSString *srcWithProxy = [self proxyURLForImageURLString:src].absoluteString;
        if (srcWithProxy) {
            NSString *newSrcAttribute = [@[@"src=\"", srcWithProxy, @"\""] componentsJoinedByString:@""];
            [newImageTagContents replaceCharactersInRange:srcAttributeRange withString:newSrcAttribute];
        }
    }
    
    
    [newImageTagContents replaceOccurrencesOfString:@"srcset" withString:@"data-srcset-disabled" options:0 range:NSMakeRange(0, newImageTagContents.length)]; //disable the srcset since we put the correct resolution image in the src
    
    if (resizedSrc) {
        [newImageTagContents appendString:@" data-image-resized=\"true\""]; //the javascript looks for this so it doesn't try to change the src again
    }
    
    return newImageTagContents;
}

#pragma mark - BaseURL (for testing only)

- (NSURL*)baseURL {
    return [self.webServer.serverURL URLByAppendingPathComponent:self.secret];
}

@end
