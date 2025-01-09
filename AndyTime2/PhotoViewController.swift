import UIKit

class PhotoViewController: UIViewController {
    private let imageView = UIImageView()
    private let imageUrl: URL
    
    init(url: URL) {
        self.imageUrl = url
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        setupImageView()
        loadImage()
    }
    
    private func setupImageView() {
        imageView.contentMode = .scaleAspectFit
        view.addSubview(imageView)
        
        imageView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            imageView.topAnchor.constraint(equalTo: view.topAnchor),
            imageView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            imageView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])
    }
    
    private func loadImage() {
        if let imageData = try? Data(contentsOf: imageUrl),
           let image = UIImage(data: imageData) {
            imageView.image = image
        }
    }
} 