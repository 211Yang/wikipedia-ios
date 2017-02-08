
public enum WMFCaptchaResetterError: LocalizedError {
    case cannotExtractCaptchaIndex
    case zeroLengthIndex
    public var errorDescription: String? {
        switch self {
        case .cannotExtractCaptchaIndex:
            return "Could not extract captcha index"
        case .zeroLengthIndex:
            return "Valid captcha reset index not obtained"
        }
    }
}

public typealias WMFCaptchaResetterResultBlock = (WMFCaptchaResetterResult) -> Void

public class WMFCaptchaResetterResult: NSObject {
    var index: String
    init(index:String) {
        self.index = index
    }
}

public class WMFCaptchaResetter: NSObject {
    private let manager = AFHTTPSessionManager.wmf_createDefault()
    public func isFetching() -> Bool {
        return manager!.operationQueue.operationCount > 0
    }
    
    public func resetCaptcha(siteURL: URL, success: @escaping WMFCaptchaResetterResultBlock, failure: @escaping WMFErrorHandler){
        let manager = AFHTTPSessionManager(baseURL: siteURL)
        manager.responseSerializer = WMFApiJsonResponseSerializer.init();
        let parameters = [
            "action": "fancycaptchareload",
            "format": "json"
        ];
        _ = manager.wmf_apiPOSTWithParameters(parameters, success: {
            (_, response: Any?) in
            guard
                let response = response as? [String : AnyObject],
                let fancycaptchareload = response["fancycaptchareload"] as? [String: Any],
                let index = fancycaptchareload["index"] as? String
                else {
                    failure(WMFCaptchaResetterError.cannotExtractCaptchaIndex)
                    return
            }
            guard index.characters.count > 0 else {
                failure(WMFCaptchaResetterError.zeroLengthIndex)
                return
            }
            success(WMFCaptchaResetterResult.init(index: index))
        }, failure: {
            (_, error: Error) in
            failure(error)
        })
    }
    static public func newCaptchaImageURLFromOldURL(_ oldURL: String, newID: String) -> String? {
        do {
            let regex = try NSRegularExpression(pattern: "wpCaptchaId=([^&]*)", options: .caseInsensitive)
            return regex.stringByReplacingMatches(in: oldURL, options: [], range: NSMakeRange(0, oldURL.characters.count), withTemplate: "wpCaptchaId=\(newID)")
        } catch {
            return nil
        }
    }
}
