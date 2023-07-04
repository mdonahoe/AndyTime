//
//  AppDelegate.swift
//  AndyTime2
//
//  Created by Matt Donahoe on 7/1/23.
//

import UIKit

@main
class AppDelegate: UIResponder, UIApplicationDelegate {

    var window: UIWindow?
    
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        window = UIWindow(frame: UIScreen.main.bounds)
        window?.makeKeyAndVisible()
        
        let rootViewController = StartViewController() // Replace with your root view controller class
        window?.rootViewController = rootViewController
        
        return true
    }
}


