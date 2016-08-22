#ifndef Wikipedia_Global_h
#define Wikipedia_Global_h
/**
   Global header included in every app and test file (see Wikipedia-Prefix.pch).

   Done as a separate header so it can be reused in unit tests.
 */

#import "WMFLogging.h"
#import "WMFDirectoryPaths.h"
#import "WMFGCDHelpers.h"
#import "WMFLocalization.h"
#import "WMFMath.h"
#import "NSObjectUtilities.h"
#import "WMFOutParamUtils.h"
#import "UIColor+WMFStyle.h"

#import <libextobjc/EXTScope.h>
#import <KVOController/FBKVOController.h>
#import <BlocksKit/BlocksKit.h>

// Need to import it this way since umbrella header doesn't have AnyPromise declarations
#import <PromiseKit/PromiseKit.h>

@import WMFKit;

#define URL_PRIVACY_POLICY @"https://m.wikimediafoundation.org/wiki/Privacy_policy"

#endif
