import UIKit
import Mapbox
import WMF

class ArticlePlaceView: MGLAnnotationView {
    let imageView: UIImageView
    let selectedImageView: UIImageView
    let dotView: UIView
    let groupView: UIView
    let countLabel: UILabel
    let dimension: CGFloat = 60
    let collapsedDimension: CGFloat = 15
    let groupDimension: CGFloat = 30
    let selectionAnimationDuration = 0.4
    
    var alwaysShowImage = false
    
    func set(alwaysShowImage: Bool, animated: Bool) {
        self.alwaysShowImage = alwaysShowImage
        let scale = collapsedDimension/groupDimension
        let imageViewScaleDownTransform = CGAffineTransform(scaleX: scale, y: scale)
        let dotViewScaleUpTransform = CGAffineTransform(scaleX: 1.0/scale, y: 1.0/scale)
        if alwaysShowImage {
            imageView.alpha = 0
            imageView.isHidden = false
            dotView.alpha = 1
            dotView.isHidden = false
            imageView.transform = imageViewScaleDownTransform
            dotView.transform = CGAffineTransform.identity
        } else {
            dotView.transform = dotViewScaleUpTransform
            imageView.transform = CGAffineTransform.identity
            imageView.alpha = 1
            imageView.isHidden = false
            dotView.alpha = 0
            dotView.isHidden = false
        }

        let transforms = {
            if alwaysShowImage {
                self.imageView.transform = CGAffineTransform.identity
                self.dotView.transform = dotViewScaleUpTransform
            } else {
                self.imageView.transform = imageViewScaleDownTransform
                self.dotView.transform = CGAffineTransform.identity
            }
        }
        let fadesIn = {
            if alwaysShowImage {
                self.imageView.alpha = 1
            } else {
                self.dotView.alpha = 1
            }
        }
        let fadesOut = {
            if alwaysShowImage {
                self.dotView.alpha = 0
            } else {
                self.imageView.alpha = 0
            }
        }
        let done = {
            self.updateDotAndImageHiddenState()
        }
        if animated {
            if alwaysShowImage {
                UIView.animateKeyframes(withDuration: 2*selectionAnimationDuration, delay: 0, options: [], animations: {
                    UIView.addKeyframe(withRelativeStartTime: 0, relativeDuration: 1, animations: {
                        UIView.animate(withDuration: 2*self.selectionAnimationDuration, delay: 0, usingSpringWithDamping: 0.6, initialSpringVelocity: 0, options: [], animations: transforms, completion:nil)
                        
                    })
                    UIView.addKeyframe(withRelativeStartTime: 0, relativeDuration: 0.25, animations:fadesIn)
                    UIView.addKeyframe(withRelativeStartTime: 0.25, relativeDuration: 0.25, animations:fadesOut)
                }) { (didFinish) in
                    done()
                }
            } else {
                UIView.animateKeyframes(withDuration: selectionAnimationDuration, delay: 0, options: [], animations: {
                    UIView.addKeyframe(withRelativeStartTime: 0, relativeDuration: 1, animations:transforms)
                    UIView.addKeyframe(withRelativeStartTime: 0, relativeDuration: 0.5, animations:fadesIn)
                    UIView.addKeyframe(withRelativeStartTime: 0.5, relativeDuration: 0.5, animations:fadesOut)
                }) { (didFinish) in
                    done()
                }
            }
        } else {
            transforms()
            fadesIn()
            fadesOut()
            done()
        }
    }
    
    override init(frame: CGRect) {
        selectedImageView = UIImageView()
        imageView = UIImageView()
        countLabel = UILabel()
        dotView = UIView()
        groupView = UIView()
        super.init(frame: frame)
    }
    
    override init(reuseIdentifier: String?) {
        selectedImageView = UIImageView()
        imageView = UIImageView()
        countLabel = UILabel()
        dotView = UIView()
        groupView = UIView()
        super.init(reuseIdentifier: reuseIdentifier)
        
        frame = CGRect(x: 0, y: 0, width: dimension, height: dimension)
        
        dotView.bounds = CGRect(x: 0, y: 0, width: collapsedDimension, height: collapsedDimension)
        dotView.layer.borderWidth = 2
        dotView.layer.borderColor = UIColor.white.cgColor
        dotView.layer.masksToBounds = true
        dotView.center = CGPoint(x: 0.5*bounds.size.width, y: 0.5*bounds.size.height)
        dotView.layer.cornerRadius = dotView.bounds.size.width * 0.5
        dotView.backgroundColor = UIColor.wmf_green()
        addSubview(dotView)
        
        groupView.bounds = CGRect(x: 0, y: 0, width: groupDimension, height: groupDimension)
        groupView.layer.borderWidth = 2
        groupView.layer.borderColor = UIColor.white.cgColor
        groupView.layer.masksToBounds = true
        groupView.layer.cornerRadius = groupView.bounds.size.width * 0.5
        groupView.backgroundColor = UIColor.wmf_green().withAlphaComponent(0.7)
        addSubview(groupView)
        
        imageView.bounds = CGRect(x: 0, y: 0, width: groupDimension, height: groupDimension)
        imageView.contentMode = .scaleAspectFill
        imageView.layer.borderWidth = 2
        imageView.layer.borderColor = UIColor.white.cgColor
        imageView.layer.masksToBounds = true
        imageView.layer.cornerRadius = imageView.bounds.size.width * 0.5
        addSubview(imageView)
        
        selectedImageView.frame = bounds
        selectedImageView.contentMode = .scaleAspectFill
        selectedImageView.layer.cornerRadius = selectedImageView.bounds.size.width * 0.5
        selectedImageView.layer.borderWidth = 2
        selectedImageView.layer.borderColor = UIColor.white.cgColor
        selectedImageView.layer.masksToBounds = true
        selectedImageView.frame = bounds
        addSubview(selectedImageView)
        
        countLabel.frame = groupView.bounds
        countLabel.textColor = UIColor.white
        countLabel.textAlignment = .center
        countLabel.font = UIFont.boldSystemFont(ofSize: 16)
        groupView.addSubview(countLabel)
        
        prepareForReuse()
    }
    
    var zPosition: CGFloat = 1 {
        didSet {
            guard !isSelected else {
                return
            }
            layer.zPosition = zPosition
        }
    }
    
    func update(withArticlePlace articlePlace: ArticlePlace) {
        if articlePlace.articles.count == 1 {
            zPosition = 1
            dotView.backgroundColor = UIColor.wmf_green()
            let article = articlePlace.articles[0]
            if let thumbnailURL = article.thumbnailURL {
                imageView.backgroundColor = UIColor.wmf_green()
                selectedImageView.backgroundColor = UIColor.wmf_green()
                imageView.wmf_setImage(with: thumbnailURL, detectFaces: true, onGPU: true, failure: { (error) in
                    self.imageView.backgroundColor = UIColor.wmf_green()
                    self.selectedImageView.backgroundColor = UIColor.wmf_green()
                    self.selectedImageView.image = nil
                    self.imageView.image = nil
                }, success: {
                    self.imageView.backgroundColor = UIColor.white
                    self.selectedImageView.wmf_setImage(with: thumbnailURL, detectFaces: true, onGPU: true, failure: { (error) in
                        self.selectedImageView.backgroundColor = UIColor.wmf_green()
                        self.selectedImageView.image = nil
                    }, success: {
                        self.selectedImageView.backgroundColor = UIColor.white
                    })
                })
            } else {
                selectedImageView.image = nil
                selectedImageView.backgroundColor = UIColor.wmf_green()
                imageView.image = nil
                imageView.backgroundColor = UIColor.wmf_green()
            }
        } else {
            zPosition = 2
            countLabel.text = "\(articlePlace.articles.count)"
        }
        updateDotAndImageHiddenState()
    }
    
    func updateDotAndImageHiddenState() {
        if countLabel.text != nil {
            imageView.isHidden = true
            dotView.isHidden = true
            groupView.isHidden = false
        } else {
            imageView.isHidden = !alwaysShowImage
            dotView.isHidden = alwaysShowImage
            groupView.isHidden = true
        }
    }
    
    override func prepareForReuse() {
        super.prepareForReuse()
        imageView.wmf_reset()
        selectedImageView.wmf_reset()
        countLabel.text = nil
        set(alwaysShowImage: false, animated: false)
        setSelected(false, animated: false)
        alpha = 1
        transform = CGAffineTransform.identity
    }
    
    required init?(coder aDecoder: NSCoder) {
        return nil
    }
    
    
    override func setSelected(_ selected: Bool, animated: Bool) {
        super.setSelected(selected, animated: animated)
        guard let place = annotation as? ArticlePlace, place.articles.count == 1 else {
            selectedImageView.alpha = 0
            return
        }
        let dotScale = collapsedDimension/dimension
        let imageViewScale = groupDimension/dimension
        let scale = alwaysShowImage ? imageViewScale : dotScale
        let selectedImageViewScaleDownTransform = CGAffineTransform(scaleX: scale, y: scale)
        let dotViewScaleUpTransform = CGAffineTransform(scaleX: 1.0/dotScale, y: 1.0/dotScale)
        let imageViewScaleUpTransform = CGAffineTransform(scaleX: 1.0/imageViewScale, y: 1.0/imageViewScale)
        layer.zPosition = 3
        if selected {
            selectedImageView.transform = selectedImageViewScaleDownTransform
            dotView.transform = CGAffineTransform.identity
            imageView.transform = CGAffineTransform.identity
            
            selectedImageView.alpha = 0
            imageView.alpha = 1
            dotView.alpha = 1
        } else {
            selectedImageView.transform = CGAffineTransform.identity
            dotView.transform = dotViewScaleUpTransform
            imageView.transform = imageViewScaleUpTransform
            
            selectedImageView.alpha = 1
            imageView.alpha = 0
            dotView.alpha = 0
        }
        let transforms = {
            if selected {
                self.selectedImageView.transform = CGAffineTransform.identity
                self.dotView.transform = dotViewScaleUpTransform
                self.imageView.transform = imageViewScaleUpTransform
            } else {
                self.selectedImageView.transform = selectedImageViewScaleDownTransform
                self.dotView.transform = CGAffineTransform.identity
                self.imageView.transform = CGAffineTransform.identity
            }
        }
        let fadesIn = {
            if selected {
                self.selectedImageView.alpha = 1
            } else {
                self.imageView.alpha = 1
                self.dotView.alpha = 1
            }
        }
        let fadesOut = {
            if selected {
                self.imageView.alpha = 0
                self.dotView.alpha = 0
            } else {
                self.selectedImageView.alpha = 0
            }
        }
        let done = {
            if !selected {
                self.layer.zPosition = self.zPosition
            }
        }
        if animated {
            let duration = alwaysShowImage ? 1.6*selectionAnimationDuration : 2*selectionAnimationDuration
            if selected {
                UIView.animateKeyframes(withDuration: duration, delay: 0, options: [], animations: {
                    UIView.addKeyframe(withRelativeStartTime: 0, relativeDuration: 1, animations: {
                        UIView.animate(withDuration: duration, delay: 0, usingSpringWithDamping: 0.6, initialSpringVelocity: 0, options: [], animations: transforms, completion:nil)

                    })
                    UIView.addKeyframe(withRelativeStartTime: 0, relativeDuration: 0.25, animations:fadesIn)
                    UIView.addKeyframe(withRelativeStartTime: 0.25, relativeDuration: 0.25, animations:fadesOut)
                }) { (didFinish) in
                    done()
                }
            } else {
                UIView.animateKeyframes(withDuration: 0.5*duration, delay: 0, options: [], animations: {
                    UIView.addKeyframe(withRelativeStartTime: 0, relativeDuration: 1, animations:transforms)
                    UIView.addKeyframe(withRelativeStartTime: 0, relativeDuration: 0.5, animations:fadesIn)
                    UIView.addKeyframe(withRelativeStartTime: 0.5, relativeDuration: 0.5, animations:fadesOut)
                }) { (didFinish) in
                    done()
                }
            }
        } else {
            transforms()
            fadesIn()
            fadesOut()
            done()
        }
    }
    
    func updateLayout() {
        let center = CGPoint(x: 0.5*bounds.size.width, y: 0.5*bounds.size.height)
        selectedImageView.center = center
        imageView.center = center
        dotView.center = center
        groupView.center = center
    }
    
    override var frame: CGRect {
        didSet {
           updateLayout()
        }
    }
    
    override var bounds: CGRect {
        didSet {
            updateLayout()
        }
    }
}
