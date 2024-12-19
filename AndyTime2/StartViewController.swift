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
    
    override func viewDidAppear(_ animated: Bool) {
        // show the videos as soon as the main view appears
        // (viewDidLoad is apparently too early to present a new vc)
        let viewController = AndyViewController(extras: [])
        viewController.modalPresentationStyle = .fullScreen
        self.present(viewController, animated: true, completion: nil)
    }
    

}
