import UIKit
import MapKit
import WMF
import CoreLocation.CLLocation

class ArticlePlace: NSObject, MKAnnotation {
    public dynamic var coordinate: CLLocationCoordinate2D
    public var nextCoordinate: CLLocationCoordinate2D?
    public let title: String?
    public let subtitle: String?
    public let articles: [WMFArticle]
    public let identifier: String
    
    init?(coordinate: CLLocationCoordinate2D, nextCoordinate: CLLocationCoordinate2D?, articles: [WMFArticle], identifier: String) {
        self.title = nil
        self.subtitle = nil
        self.coordinate = coordinate
        self.nextCoordinate = nextCoordinate
        self.articles = articles
        self.identifier = identifier
    }
    
    public static func identifierForArticles(articles: [WMFArticle]) -> String {
        return articles.reduce("", { (result, article) -> String in
            guard let key = article.key else {
                return result
            }
            return result.appending(key)
        })
    }
}
