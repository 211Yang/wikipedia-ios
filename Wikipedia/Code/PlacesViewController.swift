import UIKit
import Mapbox
import WMF
import TUSafariActivity

func MGLCoordinateRegionMakeWithDistance(_ centerCoordinate: CLLocationCoordinate2D, _ latitudinalMeters: CLLocationDistance, _ longitudinalMeters: CLLocationDistance) -> MGLCoordinateRegion {
    let mkRegion = MKCoordinateRegionMakeWithDistance(centerCoordinate, latitudinalMeters, longitudinalMeters)
    return MGLCoordinateRegion(center: mkRegion.center, span: MGLCoordinateSpan(latitudeDelta: mkRegion.span.latitudeDelta, longitudeDelta: mkRegion.span.longitudeDelta))
}

struct MGLCoordinateRegion {
    var center: CLLocationCoordinate2D
    var span: MGLCoordinateSpan
    
    var coordinateBounds: MGLCoordinateBounds {
        get {
            let sw = CLLocationCoordinate2D(latitude: center.latitude - span.latitudeDelta, longitude: center.longitude + span.longitudeDelta)
            let ne = CLLocationCoordinate2D(latitude: center.latitude + span.latitudeDelta, longitude: center.longitude - span.longitudeDelta)
            return MGLCoordinateBounds(sw: sw, ne: ne)
        }
    }
    
    init(center: CLLocationCoordinate2D, span: MGLCoordinateSpan) {
        self.center = center
        self.span = span
    }
    
    init(_ bounds: MGLCoordinateBounds) {
        let centerLat = 0.5*(bounds.ne.latitude + bounds.sw.latitude)
        let centerLon = 0.5*(bounds.ne.longitude + bounds.sw.longitude)
        let deltaLat = abs(bounds.ne.latitude - bounds.sw.latitude)
        let deltaLon = abs(bounds.ne.longitude - bounds.sw.longitude)
        
        self.init(center: CLLocationCoordinate2D(latitude: centerLat, longitude:centerLon), span: MGLCoordinateSpan(latitudeDelta: deltaLat, longitudeDelta: deltaLon))
    }
    
    init() {
        self.init(center: CLLocationCoordinate2D(latitude: 0, longitude:0), span: MGLCoordinateSpan(latitudeDelta: 0, longitudeDelta: 0))
    }
}

extension MGLMapView {
    func regionThatFits(_ region: MGLCoordinateRegion) -> MGLCoordinateRegion {
        return region
    }
    
    var region: MGLCoordinateRegion {
        get {
            return MGLCoordinateRegion(visibleCoordinateBounds)
        }
        set {
            visibleCoordinateBounds = newValue.coordinateBounds
        }
    }
}

class PlacesViewController: UIViewController, MGLMapViewDelegate, UISearchBarDelegate, ArticlePopoverViewControllerDelegate, UITableViewDataSource, UITableViewDelegate, PlaceSearchSuggestionControllerDelegate, WMFLocationManagerDelegate, NSFetchedResultsControllerDelegate {
    
    @IBOutlet weak var redoSearchButton: UIButton!
    let locationSearchFetcher = WMFLocationSearchFetcher()
    let searchFetcher = WMFSearchFetcher()
    let previewFetcher = WMFArticlePreviewFetcher()
    let wikidataFetcher = WikidataFetcher()
    
    let locationManager = WMFLocationManager.coarse()
    
    let animationDuration = 0.6
    let animationScale = CGFloat(0.6)
    let popoverFadeDuration = 0.3
    let popoverDelayDuration = 0.7
    
    var mapView: MGLMapView!
    @IBOutlet weak var progressView: UIProgressView!
    @IBOutlet weak var listView: UITableView!
    @IBOutlet weak var searchSuggestionView: UITableView!
    
    var searchSuggestionController: PlaceSearchSuggestionController!
    
    var searchBar: UISearchBar!
    var siteURL: URL = NSURL.wmf_URLWithDefaultSiteAndCurrentLocale()!
    var articleFetchedResultsController = NSFetchedResultsController<WMFArticle>() {
        didSet {
            oldValue.delegate = nil
            for article in oldValue.fetchedObjects ?? [] {
                article.placesSortOrder = nil
            }
            do {
                try dataStore.viewContext.save()
                try articleFetchedResultsController.performFetch()
            } catch let fetchError {
                DDLogError("Error fetching articles for places: \(fetchError)")
            }
            updatePlaces()
            articleFetchedResultsController.delegate = self
        }
    }

    var articleStore: WMFArticleDataStore!
    var dataStore: MWKDataStore!
    var segmentedControl: UISegmentedControl!
    
    var currentGroupingPrecision: QuadKeyPrecision = 1
    
    let searchHistoryGroup = "PlaceSearch"
    
    var maxGroupingPrecision: QuadKeyPrecision = 16
    var groupingPrecisionDelta: QuadKeyPrecision = 4
    var groupingAggressiveness: CLLocationDistance = 0.67
    
    var selectedArticlePopover: ArticlePopoverViewController?
    var selectedArticleKey: String?
    
    var placeToSelect: ArticlePlace?
    var articleKeyToSelect: String?
    
    var currentSearch: PlaceSearch? {
        didSet {
            guard let search = currentSearch else {
                return
            }
            
            searchBar.text = search.localizedDescription
            performSearch(search)
            
            
            switch search.type {
            case .saved:
                break
            case .top:
                break
            case .location:
                guard !search.needsWikidataQuery else {
                    break
                }
                fallthrough
            default:
                saveToHistory(search: search)
            }
        }
    }
    
    func keyValue(forPlaceSearch placeSearch: PlaceSearch, inManagedObjectContext moc: NSManagedObjectContext) -> WMFKeyValue? {
        var keyValue: WMFKeyValue?
        do {
            let key = placeSearch.key
            let request = WMFKeyValue.fetchRequest()
            request.predicate = NSPredicate(format: "key == %@ && group == %@", key, searchHistoryGroup)
            request.fetchLimit = 1
            let results = try moc.fetch(request)
            keyValue = results.first
        } catch let error {
            DDLogError("Error fetching place search key value: \(error.localizedDescription)")
        }
        return keyValue
    }
    
    func saveToHistory(search: PlaceSearch) {
        do {
            let moc = dataStore.viewContext
            if let keyValue = keyValue(forPlaceSearch: search, inManagedObjectContext: moc) {
                keyValue.date = Date()
            } else if let entity = NSEntityDescription.entity(forEntityName: "WMFKeyValue", in: moc) {
                let keyValue =  WMFKeyValue(entity: entity, insertInto: moc)
                keyValue.key = search.key
                keyValue.group = searchHistoryGroup
                keyValue.date = Date()
                keyValue.value = search.dictionaryValue as NSObject
            }
            try moc.save()
        } catch let error {
            DDLogError("error saving to place search history: \(error.localizedDescription)")
        }
    }
    
    func clearSearchHistory() {
        do {
            let moc = dataStore.viewContext
            let request = WMFKeyValue.fetchRequest()
            request.predicate = NSPredicate(format: "group == %@", searchHistoryGroup)
            request.sortDescriptors = [NSSortDescriptor(key: "date", ascending: false)]
            let results = try moc.fetch(request)
            for result in results {
                moc.delete(result)
            }
            try moc.save()
        } catch let error {
            DDLogError("Error clearing recent place searches: \(error)")
        }
    }
    
    var _mapRegion: MGLCoordinateRegion?
    
    var mapRegion: MGLCoordinateRegion? {
        set {
            guard let value = newValue else {
                _mapRegion = nil
                return
            }
            
            let region = mapView.regionThatFits(value)
            
            _mapRegion = region
            regroupArticlesIfNecessary(forVisibleRegion: region)
            showRedoSearchButtonIfNecessary(forVisibleRegion: region)
            
            mapView.setVisibleCoordinateBounds(region.coordinateBounds, animated: true)
        }
        
        get {
            return _mapRegion
        }
    }
    
    var currentSearchRegion: MGLCoordinateRegion?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        redoSearchButton.setTitle("          " + localizedStringForKeyFallingBackOnEnglish("places-search-this-area")  + "          ", for: .normal)
        
        let styleURL = URL(string: "mapbox://styles/joewalshwmf/cizfk5itc00c12so5x3mw48cf") //MGLStyle.lightStyleURL(withVersion: 9)//
        mapView = MGLMapView(frame: view.bounds, styleURL: styleURL)


        mapView.delegate = self
        mapView.allowsRotating = false
        mapView.allowsTilting = false
        mapView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.insertSubview(mapView, at: 0)
        // Setup map view
//        mapView.mapType = .standard
//        mapView.showsBuildings = false
//        mapView.showsTraffic = false
//        mapView.showsPointsOfInterest = false
//        mapView.showsScale = true
        
        // Setup location manager
        locationManager.delegate = self
        locationManager.startMonitoringLocation()
        
        view.tintColor = UIColor.wmf_blueTint()
        redoSearchButton.backgroundColor = view.tintColor
        
        // Setup map/list toggle
        if let map = UIImage(named: "places-map"), let list = UIImage(named: "places-list") {
            segmentedControl = UISegmentedControl(items: [map, list])
        } else {
            segmentedControl = UISegmentedControl(items: ["M", "L"])
        }
        mapView.logoView.isHidden = true
        //mapView.attributionButton.isHidden = true
        segmentedControl.selectedSegmentIndex = 0
        segmentedControl.addTarget(self, action: #selector(segmentedControlChanged), for: .valueChanged)
        segmentedControl.tintColor = UIColor.wmf_blueTint()
        navigationItem.rightBarButtonItem = UIBarButtonItem(customView: segmentedControl)
        
        // Setup list view
        listView.dataSource = self
        listView.delegate = self
        listView.register(WMFNearbyArticleTableViewCell.wmf_classNib(), forCellReuseIdentifier: WMFNearbyArticleTableViewCell.identifier())
        listView.estimatedRowHeight = WMFNearbyArticleTableViewCell.estimatedRowHeight()
        
        // Setup search bar
        searchBar = UISearchBar(frame: CGRect(x: 0, y: 0, width: view.bounds.size.width, height: 32))
        //searchBar.keyboardType = .webSearch
        searchBar.returnKeyType = .search
        searchBar.delegate = self
        searchBar.searchBarStyle = .minimal
        navigationItem.titleView = searchBar
        
        // Setup search suggestions
        searchSuggestionController = PlaceSearchSuggestionController()
        searchSuggestionController.tableView = searchSuggestionView
        searchSuggestionController.delegate = self
        
        // TODO: Remove
        let defaults = UserDefaults.wmf_userDefaults()
        let key = "WMFDidClearPlaceSearchHistory2"
        if !defaults.bool(forKey: key) {
            clearSearchHistory()
            defaults.set(true, forKey: key)
        }
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardChanged), name: NSNotification.Name.UIKeyboardWillShow, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardChanged), name: NSNotification.Name.UIKeyboardWillHide, object: nil)
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        NotificationCenter.default.removeObserver(self, name: NSNotification.Name.UIKeyboardWillShow, object: nil)
        NotificationCenter.default.removeObserver(self, name: NSNotification.Name.UIKeyboardWillHide, object: nil)
    }
    
    func keyboardChanged(notification: NSNotification) {
        guard let userInfo = notification.userInfo,
            let frameValue = userInfo[UIKeyboardFrameEndUserInfoKey] as? NSValue else {
                return
        }
        let frame = frameValue.cgRectValue
        var inset = searchSuggestionView.contentInset
        inset.bottom = frame.size.height
        searchSuggestionView.contentInset = inset
    }
    
    func mapView(_ mapView: MGLMapView, didFinishLoading style: MGLStyle) {
        let wikimediaVectorSource = MGLVectorSource(identifier: "WMFSource", tileURLTemplates: ["http://maps.wikimedia.org/osm-pbf/{z}/{x}/{y}.pbf"], options: [.minimumZoomLevel: 0,
                                                                                                                                                                .maximumZoomLevel: 26,
                                                                                                                                                                .attributionInfos: [
                                                                                                                                                                    MGLAttributionInfo(title: NSAttributedString(string: "Wikimedia"), url: URL(string: "http://wikimedia.org"))
            ]])
        style.addSource(wikimediaVectorSource)
        
        let layers = style.layers
        for layer in layers {
            style.removeLayer(layer)
            if let vectorLayer = layer as? MGLVectorStyleLayer {
                print("\(vectorLayer.sourceLayerIdentifier) : \(vectorLayer.predicate)")
            }
            if let fillLayer = layer as? MGLFillStyleLayer {
                let duplicateFillLayer = MGLFillStyleLayer(identifier: fillLayer.identifier, source: wikimediaVectorSource)
                duplicateFillLayer.sourceLayerIdentifier = fillLayer.sourceLayerIdentifier
                duplicateFillLayer.predicate = fillLayer.predicate
                duplicateFillLayer.fillAntialiased = fillLayer.fillAntialiased
                duplicateFillLayer.fillColor = fillLayer.fillColor
                duplicateFillLayer.fillOpacity = fillLayer.fillOpacity
                duplicateFillLayer.fillOutlineColor = fillLayer.fillOutlineColor
                duplicateFillLayer.fillPattern = fillLayer.fillPattern
                duplicateFillLayer.fillTranslation = fillLayer.fillTranslation
                duplicateFillLayer.fillTranslationAnchor = fillLayer.fillTranslationAnchor
                style.addLayer(duplicateFillLayer)
            } else if let lineLayer = layer as? MGLLineStyleLayer {
                let dupeLineLayer = MGLLineStyleLayer(identifier: lineLayer.identifier, source: wikimediaVectorSource)
                dupeLineLayer.sourceLayerIdentifier = lineLayer.sourceLayerIdentifier
                dupeLineLayer.predicate = lineLayer.predicate
                dupeLineLayer.lineCap = lineLayer.lineCap
                dupeLineLayer.lineJoin = lineLayer.lineJoin
                dupeLineLayer.lineMiterLimit = lineLayer.lineMiterLimit
                dupeLineLayer.lineRoundLimit = lineLayer.lineRoundLimit
                dupeLineLayer.lineBlur = lineLayer.lineBlur
                dupeLineLayer.lineColor = lineLayer.lineColor
                dupeLineLayer.lineDashPattern = lineLayer.lineDashPattern
                dupeLineLayer.lineGapWidth = lineLayer.lineGapWidth
                dupeLineLayer.lineOffset = lineLayer.lineOffset
                dupeLineLayer.lineOpacity = lineLayer.lineOpacity
                dupeLineLayer.linePattern = lineLayer.linePattern
                dupeLineLayer.lineTranslation = lineLayer.lineTranslation
                dupeLineLayer.lineTranslationAnchor = lineLayer.lineTranslationAnchor
                dupeLineLayer.lineWidth = lineLayer.lineWidth
                style.addLayer(dupeLineLayer)
            } else if let symbolLayer = layer as? MGLSymbolStyleLayer {
                let dupeSymbolLayer = MGLSymbolStyleLayer(identifier: symbolLayer.identifier, source: wikimediaVectorSource)
                dupeSymbolLayer.sourceLayerIdentifier = symbolLayer.sourceLayerIdentifier
                dupeSymbolLayer.predicate = symbolLayer.predicate
                dupeSymbolLayer.iconAllowsOverlap = symbolLayer.iconAllowsOverlap
                dupeSymbolLayer.iconIgnoresPlacement = symbolLayer.iconIgnoresPlacement
                dupeSymbolLayer.iconImageName = symbolLayer.iconImageName
                dupeSymbolLayer.iconOffset = symbolLayer.iconOffset
                dupeSymbolLayer.iconOptional = symbolLayer.iconOptional
                dupeSymbolLayer.iconPadding = symbolLayer.iconPadding
                dupeSymbolLayer.iconRotation = symbolLayer.iconRotation
                dupeSymbolLayer.iconRotationAlignment = symbolLayer.iconRotationAlignment
                dupeSymbolLayer.iconScale = symbolLayer.iconScale
                dupeSymbolLayer.iconTextFit = symbolLayer.iconTextFit
                dupeSymbolLayer.iconTextFitPadding = symbolLayer.iconTextFitPadding
                dupeSymbolLayer.keepsIconUpright = symbolLayer.keepsIconUpright
                dupeSymbolLayer.keepsTextUpright = symbolLayer.keepsTextUpright
                dupeSymbolLayer.maximumTextAngle = symbolLayer.maximumTextAngle
                dupeSymbolLayer.maximumTextWidth = symbolLayer.maximumTextWidth
                dupeSymbolLayer.symbolAvoidsEdges = symbolLayer.symbolAvoidsEdges
                dupeSymbolLayer.symbolPlacement = symbolLayer.symbolPlacement
                dupeSymbolLayer.symbolSpacing = symbolLayer.symbolSpacing
                dupeSymbolLayer.text = symbolLayer.text
                dupeSymbolLayer.textAllowsOverlap = symbolLayer.textAllowsOverlap
                dupeSymbolLayer.textAnchor = symbolLayer.textAnchor
                dupeSymbolLayer.textFontNames = symbolLayer.textFontNames
                dupeSymbolLayer.textFontSize = symbolLayer.textFontSize
                dupeSymbolLayer.textIgnoresPlacement = symbolLayer.textIgnoresPlacement
                dupeSymbolLayer.textJustification = symbolLayer.textJustification
                dupeSymbolLayer.textLetterSpacing = symbolLayer.textLetterSpacing
                dupeSymbolLayer.textLineHeight = symbolLayer.textLineHeight
                dupeSymbolLayer.textOffset = symbolLayer.textOffset
                dupeSymbolLayer.textOptional = symbolLayer.textOptional
                dupeSymbolLayer.textPadding = symbolLayer.textPadding
                dupeSymbolLayer.textPitchAlignment = symbolLayer.textPitchAlignment
                dupeSymbolLayer.textRotation = symbolLayer.textRotation
                dupeSymbolLayer.textRotationAlignment = symbolLayer.textRotationAlignment
                dupeSymbolLayer.textTransform = symbolLayer.textTransform
                dupeSymbolLayer.iconColor = symbolLayer.iconColor
                dupeSymbolLayer.iconHaloBlur = symbolLayer.iconHaloBlur
                dupeSymbolLayer.iconHaloColor = symbolLayer.iconHaloColor
                dupeSymbolLayer.iconHaloWidth = symbolLayer.iconHaloWidth
                dupeSymbolLayer.iconOpacity = symbolLayer.iconOpacity
                dupeSymbolLayer.iconTranslation = symbolLayer.iconTranslation
                dupeSymbolLayer.iconTranslationAnchor = symbolLayer.iconTranslationAnchor
                dupeSymbolLayer.textColor = symbolLayer.textColor
                dupeSymbolLayer.textHaloBlur = symbolLayer.textHaloBlur
                dupeSymbolLayer.textHaloColor = symbolLayer.textHaloColor
                dupeSymbolLayer.textHaloWidth = symbolLayer.textHaloWidth
                dupeSymbolLayer.textOpacity = symbolLayer.textOpacity
                dupeSymbolLayer.textTranslation = symbolLayer.textTranslation
                dupeSymbolLayer.textTranslationAnchor = symbolLayer.textTranslationAnchor
                style.addLayer(dupeSymbolLayer)
            } else if let backgroundLayer = layer as? MGLBackgroundStyleLayer {
                let dupeBackgroundLayer = MGLBackgroundStyleLayer(identifier: backgroundLayer.identifier)
                dupeBackgroundLayer.backgroundColor = backgroundLayer.backgroundColor
                dupeBackgroundLayer.backgroundOpacity = backgroundLayer.backgroundOpacity
                dupeBackgroundLayer.backgroundPattern = backgroundLayer.backgroundPattern
                style.addLayer(dupeBackgroundLayer)
            } else {
                print("\(layer)")
            }
        }
        
        
        for source in style.sources {
            guard source.identifier != wikimediaVectorSource.identifier else {
                continue
            }
            style.removeSource(source)
        }
        
    }
    func showRedoSearchButtonIfNecessary(forVisibleRegion visibleRegion: MGLCoordinateRegion) {
        guard let searchRegion = currentSearchRegion, let search = currentSearch, search.type != .location, search.type != .saved else {
            redoSearchButton.isHidden = true
            return
        }
        let searchWidth = searchRegion.width
        let searchHeight = searchRegion.height
        let searchRegionMinDimension = min(searchWidth, searchHeight)
        
        let visibleWidth = visibleRegion.width
        let visibleHeight = visibleRegion.height
        
        let distance = CLLocation(latitude: visibleRegion.center.latitude, longitude: visibleRegion.center.longitude).distance(from: CLLocation(latitude: searchRegion.center.latitude, longitude: searchRegion.center.longitude))
        let widthRatio = visibleWidth/searchWidth
        let heightRatio = visibleHeight/searchHeight
        let ratio = min(widthRatio, heightRatio)
        redoSearchButton.isHidden = !(ratio > 1.33 || ratio < 0.67 || distance/searchRegionMinDimension > 0.33)
    }
    
    func mapView(_ mapView: MGLMapView, regionWillChangeAnimated animated: Bool) {
        deselectAllAnnotations()
    }
    
    func showPopoverForSelectedAnnotationView() {
        guard let selectedAnnotation = mapView.selectedAnnotations.first as? ArticlePlace,
            let selectedAnnotationView = mapView.view(for: selectedAnnotation) as? ArticlePlaceView else {
                return
        }
        
        showPopover(forAnnotationView: selectedAnnotationView)
    }
    
    
    func mapView(_ mapView: MGLMapView, regionDidChangeAnimated animated: Bool) {
        _mapRegion = mapView.region
        regroupArticlesIfNecessary(forVisibleRegion: mapView.region)
        articleKeyToSelect = nil
        showRedoSearchButtonIfNecessary(forVisibleRegion: mapView.region)
        guard let toSelect = placeToSelect else {
            return
        }
        
        placeToSelect = nil
        
        guard let articleToSelect = toSelect.articles.first else {
            return
        }
        
        guard let annotations = mapView.annotations else {
            return
        }
        for annotation in annotations {
            guard let place = annotation as? ArticlePlace,
                place.articles.count == 1,
                let article = place.articles.first,
                article.key == articleToSelect.key else {
                    continue
            }
            selectArticlePlace(place)
            break
        }
        
    }
    
    var previouslySelectedArticlePlaceIdentifier: String?
    func selectArticlePlace(_ articlePlace: ArticlePlace) {
        mapView.selectAnnotation(articlePlace, animated: articlePlace.identifier != previouslySelectedArticlePlaceIdentifier)
        previouslySelectedArticlePlaceIdentifier = articlePlace.identifier
    }
    
    func mapView(_ mapView: MGLMapView, didUpdate userLocation: MGLUserLocation?) {
        guard !listView.isHidden, let indexPaths = listView.indexPathsForVisibleRows else {
            return
        }
        listView.reloadRows(at: indexPaths, with: .none)
    }
    
    func segmentedControlChanged() {
        switch segmentedControl.selectedSegmentIndex {
        case 0:
            listView.isHidden = true
        default:
            deselectAllAnnotations()
            listView.isHidden = false
            listView.reloadData()
        }
    }
    
    func regionThatFits(articles: [WMFArticle]) -> MGLCoordinateRegion {
        let coordinates: [CLLocationCoordinate2D] =  articles.flatMap({ (article) -> CLLocationCoordinate2D? in
            return article.coordinate
        })
        return coordinates.wmf_boundingRegion
    }
    
    func adjustLayout(ofPopover articleVC: ArticlePopoverViewController, withSize size: CGSize,  withAnnotationView annotationView: MGLAnnotationView) {
        let annotationCenter = view.convert(annotationView.center, from: mapView)
        let center = CGPoint(x: view.bounds.midX, y:  view.bounds.midY)
        let deltaX = annotationCenter.x - center.x
        let deltaY = annotationCenter.y - center.y
        
        let thresholdX = 0.5*(abs(view.bounds.width - size.width))
        let thresholdY = 0.5*(abs(view.bounds.height - size.height))
        
        var offsetX: CGFloat
        var offsetY: CGFloat
        
        let distanceFromAnnotationView: CGFloat = 5
        let distanceX: CGFloat = round(0.5*annotationView.bounds.size.width) + distanceFromAnnotationView
        let distanceY: CGFloat =  round(0.5*annotationView.bounds.size.height) + distanceFromAnnotationView

        if abs(deltaX) <= thresholdX {
            offsetX = -0.5 * size.width
            offsetY = deltaY > 0 ? 0 - distanceY - size.height : distanceY
        } else if abs(deltaY) <= thresholdY {
            offsetX = deltaX > 0 ? 0 - distanceX - size.width : distanceX
            offsetY = -0.5 * size.height
        } else {
            offsetX = deltaX > 0 ? 0 - distanceX - size.width : distanceX
            offsetY = deltaY > 0 ? 0 - distanceY - size.height : distanceY
        }
        
        articleVC.view.frame = CGRect(origin: CGPoint(x: annotationCenter.x + offsetX, y: annotationCenter.y + offsetY), size: articleVC.preferredContentSize)
    }
    
    func mapView(_ mapView: MGLMapView, didSelect annotationView: MGLAnnotationView) {
        guard let place = annotationView.annotation as? ArticlePlace else {
            return
        }
        
        previouslySelectedArticlePlaceIdentifier = place.identifier

        guard place.articles.count == 1 else {
            articleKeyToSelect = place.articles.first?.key
            mapRegion = regionThatFits(articles: place.articles)
            return
        }
        
        showPopover(forAnnotationView: annotationView)
    }
    
    
    func showPopover(forAnnotationView annotationView: MGLAnnotationView) {
        NSObject.cancelPreviousPerformRequests(withTarget: self, selector: #selector(showPopoverForSelectedAnnotationView), object: nil)
        guard let place = annotationView.annotation as? ArticlePlace else {
            return
        }
        
        guard let article = place.articles.first,
            let coordinate = article.coordinate,
            let articleKey = article.key else {
                return
        }
        
        guard selectedArticlePopover == nil else {
            return
        }
        
        let articleVC = ArticlePopoverViewController()
        articleVC.delegate = self
        articleVC.view.tintColor = view.tintColor
        
        articleVC.article = article
        articleVC.titleLabel.text = article.displayTitle
        articleVC.subtitleLabel.text = article.wikidataDescription
        
        let articleLocation = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        if let userCoordinate = mapView.userLocation?.coordinate {
            let userLocation = CLLocation(latitude: userCoordinate.latitude, longitude: userCoordinate.longitude)
            
            let distance = articleLocation.distance(from: userLocation)
            let distanceString = MKDistanceFormatter().string(fromDistance: distance)
            articleVC.descriptionLabel.text = distanceString
        } else {
            articleVC.descriptionLabel.text = nil
        }
        
        
        let size = articleVC.view.systemLayoutSizeFitting(UILayoutFittingCompressedSize)
        articleVC.preferredContentSize =  size
        articleVC.edgesForExtendedLayout = []
        
        selectedArticlePopover = articleVC
        selectedArticleKey = articleKey
        adjustLayout(ofPopover: articleVC, withSize:size, withAnnotationView: annotationView)
        
        articleVC.view.alpha = 0
        articleVC.view.transform = CGAffineTransform(scaleX: 0.5, y: 0.5)
        addChildViewController(articleVC)
        view.insertSubview(articleVC.view, aboveSubview: mapView)
        articleVC.didMove(toParentViewController: self)
        
        
        UIView.animate(withDuration: popoverFadeDuration) {
            articleVC.view.transform = CGAffineTransform.identity
            articleVC.view.alpha = 1
        }
    }
    
    
    func dismissCurrentArticlePopover() {
        guard let popover = selectedArticlePopover else {
            return
        }
        UIView.animate(withDuration: popoverFadeDuration, animations: {
            popover.view.alpha = 0
            popover.view.transform = CGAffineTransform(scaleX: 0.9, y: 0.9)
        }) { (done) in
            popover.willMove(toParentViewController: nil)
            popover.view.removeFromSuperview()
            popover.removeFromParentViewController()
        }
        selectedArticlePopover = nil
    }
    
    func mapView(_ mapView: MGLMapView, didDeselect view: MGLAnnotationView) {
        selectedArticleKey = nil
        dismissCurrentArticlePopover()
    }
    
    
    
    func mapView(_ mapView: MGLMapView, viewFor annotation: MGLAnnotation) -> MGLAnnotationView? {
        
        guard let place = annotation as? ArticlePlace else {
//            // CRASH WORKAROUND 
//            // The UIPopoverController that the map view presents from the default user location annotation is causing a crash. Using our own annotation view for the user location works around this issue.
//            if let userLocation = annotation as? MGLUserLocation {
//                let userViewReuseIdentifier = "org.wikimedia.userLocationAnnotationView"
//                let placeView = mapView.dequeueReusableAnnotationView(withIdentifier: userViewReuseIdentifier) as? UserLocationAnnotationView ?? UserLocationAnnotationView(reuseIdentifier: userViewReuseIdentifier)
//                placeView.annotation = userLocation
//                return placeView
//            }
            return nil
        }
        
        let reuseIdentifier = "org.wikimedia.articlePlaceView"
        var placeView = mapView.dequeueReusableAnnotationView(withIdentifier: reuseIdentifier) as! ArticlePlaceView?
        
        if placeView == nil {
            placeView = ArticlePlaceView(reuseIdentifier: reuseIdentifier)
        } else {
            placeView?.prepareForReuse()
            //placeView?.annotation = place
        }
        
        if showingAllImages {
            placeView?.set(alwaysShowImage: true, animated: false)
        }
        
        placeView?.update(withArticlePlace: place)
        
        if place.articles.count > 1 && place.nextCoordinate == nil {
            placeView?.alpha = 0
            placeView?.transform = CGAffineTransform(scaleX: animationScale, y: animationScale)
            dispatchOnMainQueue({
                UIView.animate(withDuration: self.animationDuration, delay: 0, options: .allowUserInteraction, animations: {
                    placeView?.transform = CGAffineTransform.identity
                    placeView?.alpha = 1
                }, completion: nil)
            })
        } else if let nextCoordinate = place.nextCoordinate {
            placeView?.alpha = 0
            dispatchOnMainQueue({
                UIView.animate(withDuration: 2*self.animationDuration, delay: 0, usingSpringWithDamping: 0.7, initialSpringVelocity: 0, options: .allowUserInteraction, animations: {
                    place.coordinate = nextCoordinate
                }, completion: nil)
                UIView.animate(withDuration: 0.5*self.animationDuration, delay: 0, options: .allowUserInteraction, animations: {
                    placeView?.alpha = 1
                }, completion: nil)
            })
        } else {
            placeView?.alpha = 0
            dispatchOnMainQueue({
                UIView.animate(withDuration: self.animationDuration, delay: 0, options: .allowUserInteraction, animations: {
                    placeView?.alpha = 1
                }, completion: nil)
            })
        }
        
        return placeView
    }
    
    
    func mapView(_ mapView: MGLMapView, annotationView view: MGLAnnotationView, didChange newState: MGLAnnotationViewDragState, fromOldState oldState: MGLAnnotationViewDragState) {
        
    }
    
    func deselectAllAnnotations() {
        for annotation in mapView.selectedAnnotations {
            mapView.deselectAnnotation(annotation, animated: true)
        }
    }
    
    var searching: Bool = false
    
    func showSavedArticles() {
        let moc = dataStore.viewContext
        let done = { (articlesToShow: [WMFArticle]) -> Void in
            let request = WMFArticle.fetchRequest()
            request.predicate = NSPredicate(format: "savedDate != NULL && signedQuadKey != NULL")
            request.sortDescriptors = [NSSortDescriptor(key: "savedDate", ascending: false)]
            self.articleFetchedResultsController = NSFetchedResultsController<WMFArticle>(fetchRequest: request, managedObjectContext: self.dataStore.viewContext, sectionNameKeyPath: nil, cacheName: nil)
            if articlesToShow.count > 0 {
                self.mapRegion = self.regionThatFits(articles: articlesToShow)
            }
            self.searching = false
            if articlesToShow.count == 0 {
                self.wmf_showAlertWithMessage(localizedStringForKeyFallingBackOnEnglish("places-no-saved-articles-have-location"))
            }
        }
        
        do {
            let savedPagesWithLocation = try moc.fetch(fetchRequestForSavedArticlesWithLocation)
            guard savedPagesWithLocation.count >= 99 else {
                let savedPagesWithoutLocationRequest = WMFArticle.fetchRequest()
                savedPagesWithoutLocationRequest.predicate = NSPredicate(format: "savedDate != NULL && signedQuadKey == NULL")
                savedPagesWithoutLocationRequest.sortDescriptors = [NSSortDescriptor(key: "savedDate", ascending: false)]
                savedPagesWithoutLocationRequest.propertiesToFetch = ["key"]
                let savedPagesWithoutLocation = try moc.fetch(savedPagesWithoutLocationRequest)
                guard savedPagesWithoutLocation.count > 0 else {
                    done(savedPagesWithLocation)
                    return
                }
                let urls = savedPagesWithoutLocation.flatMap({ (article) -> URL? in
                    return article.url
                })
                
                previewFetcher.fetchArticlePreviewResults(forArticleURLs: urls, siteURL: siteURL, completion: { (searchResults) in
                    var resultsByKey: [String: MWKSearchResult] = [:]
                    for searchResult in searchResults {
                        guard let title = searchResult.displayTitle, searchResult.location != nil else {
                            continue
                        }
                        guard let url = (self.siteURL as NSURL).wmf_URL(withTitle: title)  else {
                            continue
                        }
                        guard let key = (url as NSURL).wmf_articleDatabaseKey else {
                            continue
                        }
                        resultsByKey[key] = searchResult
                    }
                    guard resultsByKey.count > 0 else {
                        done(savedPagesWithLocation)
                        return
                    }
                    let articlesToUpdateFetchRequest = WMFArticle.fetchRequest()
                    articlesToUpdateFetchRequest.predicate = NSPredicate(format: "key IN %@", Array(resultsByKey.keys))
                    do {
                        var allArticlesWithLocation = savedPagesWithLocation
                        let articlesToUpdate = try moc.fetch(articlesToUpdateFetchRequest)
                        for articleToUpdate in articlesToUpdate {
                            guard let key = articleToUpdate.key,
                                let result = resultsByKey[key] else {
                                    continue
                            }
                            self.articleStore.updatePreview(articleToUpdate, with: result)
                            allArticlesWithLocation.append(articleToUpdate)
                        }
                        try moc.save()
                        done(allArticlesWithLocation)
                    } catch let error {
                        DDLogError("Error fetching saved articles: \(error.localizedDescription)")
                        done(savedPagesWithLocation)
                    }
                }, failure: { (error) in
                    DDLogError("Error fetching saved articles: \(error.localizedDescription)")
                    done(savedPagesWithLocation)
                })
                return
            }
        } catch let error {
            DDLogError("Error fetching saved articles: \(error.localizedDescription)")
        }
        done([])
    }
    
    func performWikidataQuery(forSearch search: PlaceSearch) {
        let fail = {
            dispatchOnMainQueue({
                if let region = search.region {
                    self.mapRegion = region
                }
                self.searching = false
                var newSearch = search
                newSearch.needsWikidataQuery = false
                self.currentSearch = newSearch
            })
        }
        guard let articleURL = search.searchResult?.articleURL(forSiteURL: siteURL) else {
            fail()
            return
        }
        
        wikidataFetcher.wikidataBoundingRegion(forArticleURL: articleURL, failure: { (error) in
            DDLogError("Error fetching bounding region from Wikidata: \(error)")
            fail()
        }, success: { (region) in
            dispatchOnMainQueue({
                self.mapRegion = region
                self.searching = false
                var newSearch = search
                newSearch.needsWikidataQuery = false
                newSearch.region = region
                self.currentSearch = newSearch
            })
        })
    }
    
    func performSearch(_ search: PlaceSearch) {
        guard !searching else {
            return
        }
        searching = true
        redoSearchButton.isHidden = true
        
        deselectAllAnnotations()
        
        let siteURL = self.siteURL
        var searchTerm: String? = nil
        let sortStyle = search.sortStyle
        let region = search.region ?? mapRegion ?? mapView.region
        currentSearchRegion = region
        
        switch search.type {
        case .saved:
            showSavedArticles()
            return
        case .top:
            break
        case .location:
            guard search.needsWikidataQuery else {
                fallthrough
            }
            performWikidataQuery(forSearch: search)
            return
        case .text:
            fallthrough
        default:
            searchTerm = search.string
        }
        
        let center = region.center
        let halfLatitudeDelta = region.span.latitudeDelta * 0.5
        let halfLongitudeDelta = region.span.longitudeDelta * 0.5
        let top = CLLocation(latitude: center.latitude + halfLatitudeDelta, longitude: center.longitude)
        let bottom = CLLocation(latitude: center.latitude - halfLatitudeDelta, longitude: center.longitude)
        let left =  CLLocation(latitude: center.latitude, longitude: center.longitude - halfLongitudeDelta)
        let right =  CLLocation(latitude: center.latitude, longitude: center.longitude + halfLongitudeDelta)
        let height = top.distance(from: bottom)
        let width = right.distance(from: left)
        
        let radius = round(0.25*(width + height))
        let searchRegion = CLCircularRegion(center: center, radius: radius, identifier: "")
        
        let done = {
            self.searching = false
            self.progressView.setProgress(1.0, animated: true)
            self.isProgressHidden = true
        }
        isProgressHidden = false
        progressView.setProgress(0, animated: false)
        perform(#selector(incrementProgress), with: nil, afterDelay: 0.3)
        locationSearchFetcher.fetchArticles(withSiteURL: siteURL, in: searchRegion, matchingSearchTerm: searchTerm, sortStyle: sortStyle, resultLimit: 50, completion: { (searchResults) in
            self.updatePlaces(withSearchResults: searchResults.results)
            done()
        }) { (error) in
            self.wmf_showAlertWithMessage(localizedStringForKeyFallingBackOnEnglish("empty-no-search-results-message"))
            done()
        }
    }
    
    func incrementProgress() {
        guard !isProgressHidden && progressView.progress <= 0.69 else {
            return
        }
        
        let rand = 0.15 + Float(arc4random_uniform(15))/100
        progressView.setProgress(progressView.progress + rand, animated: true)
        perform(#selector(incrementProgress), with: nil, afterDelay: 0.3)
    }
    
    func hideProgress() {
        UIView.animate(withDuration: 0.3, animations: { self.progressView.alpha = 0 } )
    }
    
    func showProgress() {
        progressView.alpha = 1
    }
    
    var isProgressHidden: Bool = false {
        didSet{
            if isProgressHidden {
                NSObject.cancelPreviousPerformRequests(withTarget: self, selector: #selector(showProgress), object: nil)
                NSObject.cancelPreviousPerformRequests(withTarget: self, selector: #selector(incrementProgress), object: nil)
                perform(#selector(hideProgress), with: nil, afterDelay: 0.7)
            } else {
                NSObject.cancelPreviousPerformRequests(withTarget: self, selector: #selector(hideProgress), object: nil)
                showProgress()
            }
        }
    }
    
    @IBAction func redoSearch(_ sender: Any) {
        guard let search = currentSearch else {
            return
        }
        currentSearch = PlaceSearch(type: search.type, sortStyle: search.sortStyle, string: search.string, region: nil, localizedDescription: search.localizedDescription, searchResult: search.searchResult)
        redoSearchButton.isHidden = true
    }
    
    var groupingTaskGroup: WMFTaskGroup?
    var needsRegroup = false
    var showingAllImages = false
    
    func regroupArticlesIfNecessary(forVisibleRegion visibleRegion: MGLCoordinateRegion) {
        guard groupingTaskGroup == nil else {
            needsRegroup = true
            return
        }
        assert(Thread.isMainThread)
        struct ArticleGroup {
            var articles: [WMFArticle] = []
            var latitudeSum: QuadKeyDegrees = 0
            var longitudeSum: QuadKeyDegrees = 0
            
            var location: CLLocation {
                get {
                    return CLLocation(latitude: latitudeSum/CLLocationDegrees(articles.count), longitude: longitudeSum/CLLocationDegrees(articles.count))
                }
            }
        }
        
        let deltaLon = visibleRegion.span.longitudeDelta
        let lowestPrecision = QuadKeyPrecision(deltaLongitude: deltaLon)
        let maxPrecision: QuadKeyPrecision = maxGroupingPrecision
        let currentPrecision = lowestPrecision + groupingPrecisionDelta
        let groupingPrecision = min(maxPrecision, currentPrecision)
        
        guard let searchRegion = currentSearchRegion else {
            return
        }
        
        let searchDeltaLon = searchRegion.span.longitudeDelta
        let lowestSearchPrecision = QuadKeyPrecision(deltaLongitude: searchDeltaLon)
        let currentSearchPrecision = lowestSearchPrecision + groupingPrecisionDelta
        let shouldShowAllImages = currentPrecision > maxPrecision + 1 || currentPrecision >= currentSearchPrecision + 1

        if shouldShowAllImages != showingAllImages {
            for annotation in mapView.annotations ?? [] {
                guard let view = mapView.view(for: annotation) as? ArticlePlaceView else {
                    continue
                }
                view.set(alwaysShowImage: shouldShowAllImages, animated: true)
            }
            showingAllImages = shouldShowAllImages
        }
        
        guard groupingPrecision != currentGroupingPrecision else {
            return
        }
        
        let taskGroup = WMFTaskGroup()
        groupingTaskGroup = taskGroup
        
        let groupingDeltaLatitude = groupingPrecision.deltaLatitude
        let groupingDeltaLongitude = groupingPrecision.deltaLongitude
        
        let centerLat = searchRegion.center.latitude
        let centerLon = searchRegion.center.longitude
        let groupingDistanceLocation = CLLocation(latitude:centerLat + groupingDeltaLatitude, longitude: centerLon + groupingDeltaLongitude)
        let centerLocation = CLLocation(latitude:centerLat, longitude: centerLon)
        let groupingDistance = groupingAggressiveness * groupingDistanceLocation.distance(from: centerLocation)
        
        var previousPlaceByArticle: [String: ArticlePlace] = [:]
        
        var annotationsToRemove: [String:ArticlePlace] = [:]
        
        for annotation in mapView.annotations ?? [] {
            guard let place = annotation as? ArticlePlace else {
                continue
            }
            
            annotationsToRemove[place.identifier] = place
            
            for article in place.articles {
                guard let key = article.key else {
                    continue
                }
                previousPlaceByArticle[key] = place
            }
        }
        
        var groups: [QuadKey: ArticleGroup] = [:]
        
        for article in articleFetchedResultsController.fetchedObjects ?? [] {
            guard let quadKey = article.quadKey else {
                continue
            }
            var group: ArticleGroup
            let adjustedQuadKey: QuadKey
            if groupingPrecision < maxPrecision && (articleKeyToSelect == nil || article.key != articleKeyToSelect) {
                adjustedQuadKey = quadKey.adjusted(downBy: QuadKeyPrecision.maxPrecision - groupingPrecision)
                group = groups[adjustedQuadKey] ?? ArticleGroup()
            } else {
                group = ArticleGroup()
                adjustedQuadKey = quadKey
            }
            if let keyToSelect = articleKeyToSelect, group.articles.first?.key == keyToSelect {
                // leave out articles that would be grouped with the one to select
                continue
            }
            group.articles.append(article)
            let coordinate = QuadKeyCoordinate(quadKey: quadKey)
            group.latitudeSum += coordinate.latitude
            group.longitudeSum += coordinate.longitude
            groups[adjustedQuadKey] = group
        }
        
        let keys = groups.keys
        
        for quadKey in keys {
            guard var group = groups[quadKey] else {
                continue
            }
            let location = group.location
            for t in -1...1 {
                for n in -1...1 {
                    let adjacentLatitude = location.coordinate.latitude + CLLocationDegrees(t)*groupingDeltaLatitude
                    let adjacentLongitude = location.coordinate.longitude + CLLocationDegrees(n)*groupingDeltaLongitude
                    
                    let adjacentQuadKey = QuadKey(latitude: adjacentLatitude, longitude: adjacentLongitude)
                    let adjustedQuadKey = adjacentQuadKey.adjusted(downBy: QuadKeyPrecision.maxPrecision - groupingPrecision)
                    guard adjustedQuadKey != quadKey, let adjacentGroup = groups[adjustedQuadKey], adjacentGroup.articles.count > 1 || group.articles.count > 1 else {
                        continue
                    }
                    if let keyToSelect = articleKeyToSelect,
                        group.articles.first?.key == keyToSelect || adjacentGroup.articles.first?.key == keyToSelect {
                        //no grouping with the article to select
                        continue
                    }
                    let distance = adjacentGroup.location.distance(from: location)
                    if distance < groupingDistance {
                        group.articles.append(contentsOf: adjacentGroup.articles)
                        group.latitudeSum += adjacentGroup.latitudeSum
                        group.longitudeSum += adjacentGroup.longitudeSum
                        groups.removeValue(forKey: adjustedQuadKey)
                    }
                }
            }
            
            var nextCoordinate: CLLocationCoordinate2D?
            var coordinate = group.location.coordinate
            
            let identifier = ArticlePlace.identifierForArticles(articles: group.articles)
            
            let checkAndSelect = { (place: ArticlePlace) in
                if let keyToSelect = self.articleKeyToSelect, place.articles.count == 1, place.articles.first?.key == keyToSelect {
                    // hacky workaround for now
                    self.deselectAllAnnotations()
                    self.placeToSelect = place
                    dispatchAfterDelayInSeconds(0.7, DispatchQueue.main, {
                        self.placeToSelect = nil
                        guard self.mapView.selectedAnnotations.count == 0 else {
                            return
                        }
                        self.selectArticlePlace(place)
                    })
                    self.articleKeyToSelect = nil
                }
            }
            
            //check for identical place already on the map
            if let place = annotationsToRemove.removeValue(forKey: identifier) {
                checkAndSelect(place)
                continue
            }
            
            if group.articles.count == 1 {
                if let article = group.articles.first, let key = article.key, let previousPlace = previousPlaceByArticle[key] {
                    nextCoordinate = coordinate
                    coordinate = previousPlace.coordinate
                }
            } else {
                let groupCount = group.articles.count
                for article in group.articles {
                    guard let key = article.key,
                        let previousPlace = previousPlaceByArticle[key] else {
                            continue
                    }
                    
                    guard previousPlace.articles.count < groupCount else {
                            nextCoordinate = coordinate
                            coordinate = previousPlace.coordinate
                        break
                    }
                    
                    guard annotationsToRemove.removeValue(forKey: previousPlace.identifier) != nil else {
                        continue
                    }
                    
                    let placeView = mapView.view(for: previousPlace)
                    taskGroup.enter()
                    UIView.animate(withDuration:animationDuration, delay: 0, options: [], animations: {
                        placeView?.alpha = 0
                        if (previousPlace.articles.count > 1) {
                            placeView?.transform = CGAffineTransform(scaleX: self.animationScale, y: self.animationScale)
                        }
                        previousPlace.coordinate = coordinate
                    }, completion: { (finished) in
                        taskGroup.leave()
                        self.mapView.removeAnnotation(previousPlace)
                    })
                }
            }
            
            guard let place = ArticlePlace(coordinate: coordinate, nextCoordinate: nextCoordinate, articles: group.articles, identifier: identifier) else {
                continue
            }
            
            mapView.addAnnotation(place)
            
            checkAndSelect(place)
        }
        
        
        
        for (_, annotation) in annotationsToRemove {
            let placeView = mapView.view(for: annotation)
            taskGroup.enter()
            UIView.animate(withDuration: 0.5*animationDuration, animations: {
                placeView?.transform = CGAffineTransform(scaleX: self.animationScale, y: self.animationScale)
                placeView?.alpha = 0
            }, completion: { (finished) in
                taskGroup.leave()
                self.mapView.removeAnnotation(annotation)
            })
        }
        currentGroupingPrecision = groupingPrecision
        taskGroup.waitInBackground {
            self.groupingTaskGroup = nil
            if (self.needsRegroup) {
                self.needsRegroup = false
                self.regroupArticlesIfNecessary(forVisibleRegion: self.mapRegion ?? self.mapView.region)
            }
        }
    }
    
    func updatePlaces(withSearchResults searchResults: [MWKLocationSearchResult]) {
        let articleURLToSelect = currentSearch?.searchResult?.articleURL(forSiteURL: siteURL) ?? searchResults.first?.articleURL(forSiteURL: siteURL)
        articleKeyToSelect = (articleURLToSelect as NSURL?)?.wmf_articleDatabaseKey
        var foundKey = false
        var keysToFetch: [String] = []
        var sort = 0
        for result in searchResults {
            guard let displayTitle = result.displayTitle,
                let articleURL = (siteURL as NSURL).wmf_URL(withTitle: displayTitle),
                let article = self.articleStore?.addPreview(with: articleURL, updatedWith: result),
                let _ = article.quadKey,
                let articleKey = article.key else {
                    continue
            }
            article.placesSortOrder = NSNumber(value: sort)
            if articleKeyToSelect != nil && articleKeyToSelect == articleKey {
                foundKey = true
            }
            keysToFetch.append(articleKey)
            sort += 1
        }
        
        if !foundKey, let keyToFetch = articleKeyToSelect, let URL = articleURLToSelect, let searchResult = currentSearch?.searchResult {
            articleStore.addPreview(with: URL, updatedWith: searchResult)
            keysToFetch.append(keyToFetch)
        }

        let request = WMFArticle.fetchRequest()
        request.predicate = NSPredicate(format: "key in %@", keysToFetch)
        request.sortDescriptors = [NSSortDescriptor(key: "placesSortOrder", ascending: true)]
        articleFetchedResultsController = NSFetchedResultsController<WMFArticle>(fetchRequest: request, managedObjectContext: dataStore.viewContext, sectionNameKeyPath: nil, cacheName: nil)
    }
    
    func updatePlaces() {
        listView.reloadData()
        currentGroupingPrecision = 0
        regroupArticlesIfNecessary(forVisibleRegion: mapRegion ?? mapView.region)
    }
    
    
    // ArticlePopoverViewControllerDelegate
    func articlePopoverViewController(articlePopoverViewController: ArticlePopoverViewController, didSelectAction: ArticlePopoverViewControllerAction) {
        
        
        guard let article = articlePopoverViewController.article, let url = article.url else {
            return
        }
        
        switch didSelectAction {
        case .read:
            wmf_pushArticle(with: url, dataStore: dataStore, previewStore: articleStore, animated: true)
            break
        case .save:
            deselectAllAnnotations()
            dataStore.savedPageList.toggleSavedPage(for: url)
            break
        case .share:
            let activityVC = UIActivityViewController(activityItems: [url], applicationActivities: [TUSafariActivity()])
            present(activityVC, animated: true, completion: nil)
            break
        case .none:
            fallthrough
        default:
            break
        }
        
    }
    
    var fetchRequestForSavedArticles: NSFetchRequest<WMFArticle> {
        get {
            let savedRequest = WMFArticle.fetchRequest()
            savedRequest.predicate = NSPredicate(format: "savedDate != NULL")
            return savedRequest
        }
    }
    
    var fetchRequestForSavedArticlesWithLocation: NSFetchRequest<WMFArticle> {
        get {
            let savedRequest = WMFArticle.fetchRequest()
            savedRequest.predicate = NSPredicate(format: "savedDate != NULL && signedQuadKey != NULL")
            return savedRequest
        }
    }
    
    // Search completions
    
    func updateSearchSuggestions(withCompletions completions: [PlaceSearch]) {
        guard let currentSearchString = searchBar.text?.trimmingCharacters(in: NSCharacterSet.whitespacesAndNewlines), currentSearchString != "" || completions.count > 0 else {
            let topNearbySuggestion = PlaceSearch(type: .top, sortStyle: .links, string: nil, region: nil, localizedDescription: localizedStringForKeyFallingBackOnEnglish("places-search-top-articles"), searchResult: nil)
            
            var suggestedSearches = [topNearbySuggestion]
            var recentSearches: [PlaceSearch] = []
            do {
                let moc = dataStore.viewContext
                if try moc.count(for: fetchRequestForSavedArticles) > 0 {
                    let saved = PlaceSearch(type: .saved, sortStyle: .none, string: nil, region: nil, localizedDescription: localizedStringForKeyFallingBackOnEnglish("places-search-saved-articles"), searchResult: nil)
                    suggestedSearches.append(saved)
                }
                
                let request = WMFKeyValue.fetchRequest()
                request.predicate = NSPredicate(format: "group == %@", searchHistoryGroup)
                request.sortDescriptors = [NSSortDescriptor(key: "date", ascending: false)]
                let results = try moc.fetch(request)
                recentSearches = try results.map({ (kv) -> PlaceSearch in
                    guard let dictionary = kv.value as? [String : Any],
                        let ps = PlaceSearch(dictionary: dictionary) else {
                            throw NSError()
                    }
                    return ps
                })
            } catch let error {
                DDLogError("Error fetching recent place searches: \(error)")
            }
            
            searchSuggestionController.searches = [suggestedSearches, recentSearches, [], []]
            return
        }
        
        guard currentSearchString != "" else {
            searchSuggestionController.searches = [[], [], [], completions]
            return
        }
        
        let currentStringSuggeston = PlaceSearch(type: .text, sortStyle: .links, string: currentSearchString, region: nil, localizedDescription: currentSearchString, searchResult: nil)
        searchSuggestionController.searches = [[], [], [currentStringSuggeston], completions]
    }
    
    func handleCompletion(searchResults: [MWKSearchResult]) -> [PlaceSearch] {
        var set = Set<String>()
        let completions = searchResults.flatMap { (result) -> PlaceSearch? in
            guard let location = result.location,
                let dimension = result.geoDimension?.doubleValue,
                let title = result.displayTitle,
                let url = (self.siteURL as NSURL).wmf_URL(withTitle: title),
                let key = (url as NSURL).wmf_articleDatabaseKey,
                !set.contains(key) else {
                    return nil
            }
            set.insert(key)
            let region = MGLCoordinateRegionMakeWithDistance(location.coordinate, dimension, dimension)
            
            return PlaceSearch(type: .location, sortStyle: .links, string: nil, region: region, localizedDescription: result.displayTitle, searchResult: result)
        }
        updateSearchSuggestions(withCompletions: completions)
        return completions
    }

    
    func updateSearchCompletionsFromSearchBarText() {
        guard let text = searchBar.text?.trimmingCharacters(in: NSCharacterSet.whitespacesAndNewlines), text != "" else {
            updateSearchSuggestions(withCompletions: [])
            return
        }
        searchFetcher.fetchArticles(forSearchTerm: text, siteURL: siteURL, resultLimit: 24, failure: { (error) in
            guard text == self.searchBar.text else {
                return
            }
            self.updateSearchSuggestions(withCompletions: [])
        }) { (searchResult) in
            guard text == self.searchBar.text else {
                return
            }
            
            let completions = self.handleCompletion(searchResults: searchResult.results ?? [])
            guard completions.count < 10 else {
                return
            }
            
            let center = self.mapView.userLocation?.coordinate ?? CLLocationCoordinate2D(latitude: 0, longitude: 0)
            let region = CLCircularRegion(center: center, radius: 40075000, identifier: "world")
            self.locationSearchFetcher.fetchArticles(withSiteURL: self.siteURL, in: region, matchingSearchTerm: text, sortStyle: .links, resultLimit: 24, completion: { (locationSearchResults) in
                guard text == self.searchBar.text else {
                    return
                }
                var combinedResults: [MWKSearchResult] = searchResult.results ?? []
                let newResults = locationSearchResults.results as [MWKSearchResult]
                combinedResults.append(contentsOf: newResults)
                let _ = self.handleCompletion(searchResults: combinedResults)
            }) { (error) in
                guard text == self.searchBar.text else {
                    return
                }
            }
        }
    }
    
    var searchSuggestionsHidden = true {
        didSet {
            searchSuggestionView.isHidden = searchSuggestionsHidden
            segmentedControl.isEnabled = searchSuggestionsHidden
        }
    }
    
    // UISearchBarDelegate
    
    func searchBarTextDidBeginEditing(_ searchBar: UISearchBar) {
        if let type = currentSearch?.type, type != .text {
            searchBar.text = nil
        }
        searchSuggestionsHidden = false
        updateSearchSuggestions(withCompletions: [])
        deselectAllAnnotations()
    }
    
    func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
        updateSearchSuggestions(withCompletions: searchSuggestionController.searches[3])
        NSObject.cancelPreviousPerformRequests(withTarget: self)
        perform(#selector(updateSearchCompletionsFromSearchBarText), with: nil, afterDelay: 0.2)
    }
    
    func searchBarCancelButtonClicked(_ searchBar: UISearchBar) {
        
    }
    
    func searchBarSearchButtonClicked(_ searchBar: UISearchBar) {
        currentSearch = PlaceSearch(type: .text, sortStyle: .links, string: searchBar.text, region: nil, localizedDescription: searchBar.text, searchResult: nil)
        searchBar.endEditing(true)
    }
    
    func searchBarTextDidEndEditing(_ searchBar: UISearchBar) {
        searchSuggestionsHidden = true
    }
    
    //UITableViewDataSource
    
    func numberOfSections(in tableView: UITableView) -> Int {
        return articleFetchedResultsController.sections?.count ?? 0
    }
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return articleFetchedResultsController.sections?[section].numberOfObjects ?? 0
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let cell = tableView.dequeueReusableCell(withIdentifier: WMFNearbyArticleTableViewCell.identifier(), for: indexPath) as? WMFNearbyArticleTableViewCell else {
            return UITableViewCell()
        }
        
        let article = articleFetchedResultsController.object(at: indexPath)
        cell.titleText = article.displayTitle
        cell.descriptionText = article.wikidataDescription
        cell.setImageURL(article.thumbnailURL)
        
        
        update(userLocation: locationManager.location, onLocationCell: cell, withArticle: article)
        
        return cell
    }
    
    func update(userLocation: CLLocation, onLocationCell cell: WMFNearbyArticleTableViewCell, withArticle article: WMFArticle) {
        guard let articleLocation = article.location else {
            return
        }
        
        let distance = articleLocation.distance(from: userLocation)
        cell.setDistance(distance)
        
        if let heading = mapView.userLocation?.heading  {
            let bearing = userLocation.wmf_bearing(to: articleLocation, forCurrentHeading: heading)
            cell.setBearing(bearing)
        } else {
            let bearing = userLocation.wmf_bearing(to: articleLocation)
            cell.setBearing(bearing)
        }
    }
    
    // UITableViewDelegate
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let article = articleFetchedResultsController.object(at: indexPath)
        guard let url = article.url else {
            return
        }
        wmf_pushArticle(with: url, dataStore: dataStore, previewStore: articleStore, animated: true)
    }
    
    // PlaceSearchSuggestionControllerDelegate
    
    func placeSearchSuggestionController(_ controller: PlaceSearchSuggestionController, didSelectSearch search: PlaceSearch) {
        currentSearch = search
        searchBar.endEditing(true)
    }
    
    func placeSearchSuggestionControllerClearButtonPressed(_ controller: PlaceSearchSuggestionController) {
        clearSearchHistory()
        updateSearchSuggestions(withCompletions: [])
    }
    
    func placeSearchSuggestionController(_ controller: PlaceSearchSuggestionController, didDeleteSearch search: PlaceSearch) {
        let moc = dataStore.viewContext
        guard let kv = keyValue(forPlaceSearch: search, inManagedObjectContext: moc) else {
            return
        }
        moc.delete(kv)
        do {
            try moc.save()
        } catch let error {
            DDLogError("Error removing kv: \(error.localizedDescription)")
        }
        updateSearchSuggestions(withCompletions: [])
    }
    
    // WMFLocationManagerDelegate
    
    func locationManager(_ controller: WMFLocationManager, didUpdate location: CLLocation) {
        let region = MGLCoordinateRegionMakeWithDistance(location.coordinate, 5000, 5000)
        mapRegion = region
        if currentSearch == nil {
            currentSearch = PlaceSearch(type: .top, sortStyle: .links, string: nil, region: region, localizedDescription: localizedStringForKeyFallingBackOnEnglish("places-search-top-articles"), searchResult: nil)
        }
        locationManager.stopMonitoringLocation()
    }
    
    func locationManager(_ controller: WMFLocationManager, didReceiveError error: Error) {
        locationManager.stopMonitoringLocation()
    }
    
    func locationManager(_ controller: WMFLocationManager, didUpdate heading: CLHeading) {
    }
    
    func locationManager(_ controller: WMFLocationManager, didChangeEnabledState enabled: Bool) {
    }
    
    @IBAction func recenterOnUserLocation(_ sender: Any) {
        locationManager.startMonitoringLocation()
    }
    
    // NSFetchedResultsControllerDelegate
    
    func controllerDidChangeContent(_ controller: NSFetchedResultsController<NSFetchRequestResult>) {
        updatePlaces()
    }
    
    // Grouping debug view
    
    @IBOutlet weak var secretSettingsView: UIView!
    
    
    @IBOutlet weak var maxZoomLabel: UILabel!
    @IBOutlet weak var maxZoomSlider: UISlider!
    @IBAction func maxZoomValueChanged(_ sender: Any) {
        maxZoomLabel.text = "max: \(Int(round(maxZoomSlider.value)))"
        applySecretSettings()
    }
    
    @IBOutlet weak var groupZoomDeltaLabel: UILabel!
    @IBOutlet weak var groupZoomDeltaSlider: UISlider!
    @IBAction func groupZoomDeltaSliderChanged(_ sender: Any) {
        groupZoomDeltaLabel.text = "delta: \(Int(8 - round(groupZoomDeltaSlider.value)))"
        applySecretSettings()
    }
    
    @IBOutlet weak var groupAggressivenessLabel: UILabel!
    @IBOutlet weak var groupAggressivenessSlider: UISlider!
    @IBAction func groupAggressivenessChanged(_ sender: Any) {
        groupAggressivenessLabel.text = String(format: "agg: %.2f", groupAggressivenessSlider.value)
        applySecretSettings()
    }
    
    func applySecretSettings() {
        groupingAggressiveness = CLLocationDistance(groupAggressivenessSlider.value)
        groupingPrecisionDelta = QuadKeyPrecision(8 - round(groupZoomDeltaSlider.value))
        maxGroupingPrecision = QuadKeyPrecision(round(maxZoomSlider.value))
        currentGroupingPrecision = 0
        regroupArticlesIfNecessary(forVisibleRegion: mapRegion ?? mapView.region)
    }
    
    override func motionEnded(_ motion: UIEventSubtype, with event: UIEvent?) {
        switch motion {
        case .motionShake:
            secretSettingsView.isHidden = !secretSettingsView.isHidden
            guard secretSettingsView.isHidden else {
                return
            }
            applySecretSettings()
        default:
            break
        }
    }
}

