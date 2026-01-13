//
//  AppDelegate.swift
//  AndyTime2
//
//  Created by Matt Donahoe on 7/1/23.
//

import UIKit

/// The main application delegate that bootstraps the AndyTime app.
///
/// This class is responsible for setting up the initial window and root view controller
/// when the application launches. It creates the main window and sets `StartViewController`
/// as the root, which then initializes all video and photo content before presenting the
/// main navigation interface.
@main
class AppDelegate: UIResponder, UIApplicationDelegate {

    var window: UIWindow?
    
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        window = UIWindow(frame: UIScreen.main.bounds)
        window?.makeKeyAndVisible()
        let rootViewController = StartViewController()
        window?.rootViewController = rootViewController
        return true
    }
}


