//
//  AndyViewController.swift
//  AndyTime2
//
//  Created by Matt Donahoe on 7/1/23.
//

import UIKit
import AVFoundation
import AVKit

/* 
 This class is the main view controller for the app.

 It is a UIPageViewController that contains a custom tab bar at the bottom.
 The view controllers are either VideoViewController or generic UIViewController.
 The VideoViewController is a subclass of UIViewController that contains an AVPlayer.
 The UIViewController is a generic view controller that contains a UIView.
*/
class AndyViewController: UIViewController, UIPageViewControllerDataSource, UIPageViewControllerDelegate {
    
    private var extraViews: [UIViewController]
    private var pageViewController: UIPageViewController!
    private var viewControllers: [UIViewController] = []
    private var customTabBar: UIView!
    private var currentVideoView: VideoViewController?

    
    init(extras: [UIViewController]) {
        self.extraViews = extras
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    
    override func viewDidLoad() {
        super.viewDidLoad()
        self.view.backgroundColor = .gray
        customizeViewControllers()
        setupPageViewController()
        setupCustomTabBar()
                // Add observer for channel loading
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleChannelsLoaded),
            name: PlaybackManager.channelsDidLoad,
            object: nil
        )
    }
    
    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        
        coordinator.animate(alongsideTransition: { [weak self] _ in
            self?.updateCustomTabBarFrame()
        }, completion: nil)
    }
    
    private func setupCustomTabBar() {
        let tabBarHeight: CGFloat = 50
        
        customTabBar = UIView()
        customTabBar.backgroundColor = .lightGray
        view.addSubview(customTabBar)
        
        // Set up constraints to position the custom tab bar at the bottom of the view
        customTabBar.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            customTabBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            customTabBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            customTabBar.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            customTabBar.heightAnchor.constraint(equalToConstant: tabBarHeight)
        ])
        
        updateCustomTabBarFrame()
    }
    
    private func updateCustomTabBarFrame() {
        let tabBarHeight: CGFloat = 50
        let tabBarFrame = CGRect(x: 0, y: view.bounds.height - tabBarHeight, width: view.bounds.width, height: tabBarHeight)
        customTabBar.frame = tabBarFrame
    }
    
    private func setupPageViewController() {
        pageViewController = UIPageViewController(transitionStyle: .scroll, navigationOrientation: .horizontal, options: nil)
        pageViewController.dataSource = self
        pageViewController.delegate = self
        
        // Set the first view controller
        if let firstViewController = viewControllers.first {
            pageViewController.setViewControllers([firstViewController], direction: .forward, animated: true, completion: nil)
        }
        
        // Add the page view controller as a child view controller
        addChild(pageViewController)
        view.addSubview(pageViewController.view)
        pageViewController.didMove(toParent: self)
        
        // Set the page view controller's frame to fill the entire view
        pageViewController.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            pageViewController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            pageViewController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            pageViewController.view.topAnchor.constraint(equalTo: view.topAnchor),
            pageViewController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }
    
    private func customizeViewControllers() {
        // Add green view first
        let greenViewController = UIViewController()
        greenViewController.view.backgroundColor = .green
        greenViewController.view.frame = CGRect(x: 0, y: 0, width: view.bounds.width, height: view.bounds.height)
        viewControllers.append(greenViewController)

        let channels = PlaybackManager.shared.getChannels()
        print("vc channels = \(channels)")
        for (channelIndex, name) in channels.enumerated() {
            let videoViewController = VideoViewController(name: name, channelIndex: channelIndex)
            viewControllers.append(videoViewController)
        }
        
        viewControllers.append(contentsOf: self.extraViews)
        
        // Add red view last
        let redViewController = UIViewController()
        redViewController.view.backgroundColor = .red
        redViewController.view.frame = CGRect(x: 0, y: 0, width: view.bounds.width, height: view.bounds.height)
        viewControllers.append(redViewController)

        let adminViewController = AdminViewController()
        adminViewController.view.frame = CGRect(x: 0, y: 0, width: view.bounds.width, height: view.bounds.height)
        viewControllers.insert(adminViewController, at: 0)
    }

    // TODO(matt): do we need this?
    private func reloadPageViewController(with viewControllers: [UIViewController]) {
        print("reloadPageViewController")
        guard let currentViewController = pageViewController.viewControllers?.first else {
            return
        }
        
        pageViewController.setViewControllers([currentViewController], direction: .forward, animated: false) { [weak self] _ in
            guard let self = self else {
                return
            }
            
            self.pageViewController.setViewControllers(viewControllers, direction: .forward, animated: false, completion: nil)
        }
    }
    
    // MARK: UIPageViewControllerDataSource
    
    func pageViewController(_ pageViewController: UIPageViewController, viewControllerBefore viewController: UIViewController) -> UIViewController? {
        //print("viewControllerBefore \(viewController)")
        guard let index = viewControllers.firstIndex(of: viewController), index > 0 else {
            return nil
        }
        return viewControllers[index - 1]
    }
    
    func pageViewController(_ pageViewController: UIPageViewController, viewControllerAfter viewController: UIViewController) -> UIViewController? {
        //print("viewControllerAfter \(viewController)")
        
        guard let index = viewControllers.firstIndex(of: viewController), index < viewControllers.count - 1 else {
            return nil
        }
        return viewControllers[index + 1]
    }
    
    func presentationCount(for pageViewController: UIPageViewController) -> Int {
        return viewControllers.count
    }
    
    func presentationIndex(for pageViewController: UIPageViewController) -> Int {
        guard let currentViewController = pageViewController.viewControllers?.first else {
            return 0
        }
        return viewControllers.firstIndex(of: currentViewController) ?? 0
    }
    
    func pageViewController(_ pageViewController: UIPageViewController, willTransitionTo pendingViewControllers: [UIViewController]) {
        print("pageViewController willTransitionTo")
        // Disable user interaction for the tab bar during the transition
    }
    
    private func startVideoPlayback() {
        guard let currentViewController = pageViewController.viewControllers?.first as? VideoViewController else {
            return
        }
        
        currentViewController.resumePlayback()
    }
    
    private func stopVideoPlayback() {
        guard let currentViewController = pageViewController.viewControllers?.first as? VideoViewController else {
            return
        }
        
        currentViewController.stopVideo()
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        print("atvc viewDidAppear")

        startVideoPlayback()
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        print("atvc viewWillDisappear")
        super.viewWillDisappear(animated)
        
        stopVideoPlayback()
    }
    
    func pageViewController(_ pageViewController: UIPageViewController, didFinishAnimating finished: Bool, previousViewControllers: [UIViewController], transitionCompleted completed: Bool) {
        print("atvc pageViewController didFinishAnimating")
        
        // Stop previous video player
        if let oldplayer = currentVideoView {
            print("pausing old player view")
            oldplayer.stopVideo()
        }
        currentVideoView = nil
        
        guard let currentViewController = pageViewController.viewControllers?.first as? VideoViewController else {
            return
        }

        // Start current video player
        print("starting \(currentViewController.name)")
        PlaybackManager.shared.setChannelIndex(index: currentViewController.channelIndex)
        currentVideoView = currentViewController
        currentVideoView?.resumePlayback()
    }

    @objc private func handleChannelsLoaded() {
        print("handleChannelsLoaded")
        // Recreate view controllers with new channels
        viewControllers.removeAll()
        customizeViewControllers()
        
        // Completely reset the page view controller
        setupPageViewController()
        print("done loading channels")
    }
}
