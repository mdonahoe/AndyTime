import UIKit
import Foundation
import Photos


// This class is a wrapper around the AndyViewController.
// It is used to present the AndyViewController when the app is launched.
// It fetches the videos from the apps documents directory.
class StartViewController: UIViewController {
    
    override func viewDidLoad() {
        super.viewDidLoad()
    }
    
    private func getJPGFileURLs() -> [URL] {
        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let jpgFiles = try? FileManager.default.contentsOfDirectory(at: documentsURL, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension.lowercased() == "jpg" }
        return jpgFiles ?? []
    }
    
    override func viewDidAppear(_ animated: Bool) {
        // Create PhotoViewControllers for each jpg file
        let photoUrls = getJPGFileURLs()
        let photoViewControllers = photoUrls.map { PhotoViewController(url: $0) }
        
        // Create and present the AndyViewController with the photo views
        let viewController = AndyViewController(extras: photoViewControllers)
        viewController.modalPresentationStyle = .fullScreen
        self.present(viewController, animated: true, completion: nil)
    }
    

}
