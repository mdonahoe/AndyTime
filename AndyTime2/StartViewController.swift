import UIKit
import Foundation
import Photos



class StartViewController: UIViewController {
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupStartButton()
    }
    
    private func setupStartButton() {
        let startButton = UIButton(type: .system)
        startButton.setTitle("START", for: .normal)
        startButton.titleLabel?.font = UIFont.systemFont(ofSize: 20, weight: .bold)
        startButton.addTarget(self, action: #selector(startButtonTapped(_:)), for: .touchUpInside)
        view.backgroundColor = .black
        view.addSubview(startButton)
        startButton.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            startButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            startButton.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
    }
    
    func getMP4FileURLs() -> [URL] {
        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let mp4Files = try? FileManager.default.contentsOfDirectory(at: documentsURL, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "mp4" }
        
        return mp4Files ?? []
    }
    
    @objc private func startButtonTapped(_ sender: UIButton) {
        
        fetchVideosFromCameraRoll { [weak self] videoURLs in
            guard let self = self else { return }
            let gridVideoViewController = GridVideoViewController(videoURLs: videoURLs)
            let viewController = ViewController(videoURLs: getMP4FileURLs(), extras: [gridVideoViewController])
            viewController.modalPresentationStyle = .fullScreen
            self.present(viewController, animated: true, completion: nil)
        }
    }
    
    private func fetchVideosFromCameraRoll(completion: @escaping ([URL]) -> Void) {
        var videoURLs: [URL] = []
        
        let options = PHFetchOptions()
        options.predicate = NSPredicate(format: "mediaType = %d", PHAssetMediaType.video.rawValue)
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]
        
        let group = DispatchGroup()

        let fetchResult = PHAsset.fetchAssets(with: options)
        
        fetchResult.enumerateObjects { asset, _, _ in
            group.enter()
            PHImageManager.default().requestAVAsset(forVideo: asset, options: nil) { avAsset, _, _ in
                if let urlAsset = avAsset as? AVURLAsset {
                    let videoURL = urlAsset.url
                    videoURLs.append(videoURL)
                }
                group.leave()
            }
        }
        
        group.notify(queue: .main) {
            completion(videoURLs)
        }
    }
}
