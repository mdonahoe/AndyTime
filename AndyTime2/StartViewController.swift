import UIKit
import Foundation
import Photos

/// The initial view controller that handles app startup and content loading.
///
/// `StartViewController` serves as a loading bridge between app launch and the main UI.
/// It performs the following initialization tasks:
/// - Loads all MP4 videos from the app's documents directory via `PlaybackManager`
/// - Scans for JPG and HEIC photos in the documents directory
/// - Creates `PhotoViewController` instances for each discovered image
/// - Presents the main `AndyViewController` with all content ready for display
///
/// This controller is displayed briefly at launch while content is being indexed,
/// then immediately presents the full-screen `AndyViewController`.
class StartViewController: UIViewController {
    
    override func viewDidLoad() {
        super.viewDidLoad()
    }
    
    private func getJPGFileURLs() -> [URL] {
        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let jpgFiles = try? FileManager.default.contentsOfDirectory(at: documentsURL, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension.lowercased() == "jpg" || $0.pathExtension.lowercased() == "heic" }
        return jpgFiles ?? []
    }
    
    override func viewDidAppear(_ animated: Bool) {
        // Load the videos
        PlaybackManager.shared.loadVideos()

        // Check if there are any videos
        let videoUrls = PlaybackManager.shared.getMP4FileURLs()
        if videoUrls.isEmpty {
            // No videos found, show info page
            let infoViewController = InfoViewController()
            infoViewController.modalPresentationStyle = .fullScreen
            self.present(infoViewController, animated: true, completion: nil)
            return
        }

        // Create PhotoViewControllers for each jpg file
        let photoUrls = getJPGFileURLs()
        let photoViewControllers = photoUrls.map { PhotoViewController(url: $0) }

        // Create and present the AndyViewController with the photo views
        let viewController = AndyViewController(extras: photoViewControllers)
        viewController.modalPresentationStyle = .fullScreen
        self.present(viewController, animated: true, completion: nil)
    }
    

}
