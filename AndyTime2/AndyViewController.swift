//
//  AndyViewController.swift
//  AndyTime2
//
//  Created by Matt Donahoe on 7/1/23.
//

import UIKit
import AVFoundation
import AVKit
import LiveKit

class AndyViewController: UIViewController, UIPageViewControllerDataSource, UIPageViewControllerDelegate {

    private var extraViews: [UIViewController]
    private var pageViewController: UIPageViewController!
    private var viewControllers: [UIViewController] = []
    private var customTabBar: UIView!
    private var currentVideoView: VideoViewController?

    // Boundary VC used as insertion anchor for RemoteCameraViewControllers
    private var greenViewController: UIViewController!

    // Kept around so they can be added/removed as Guided Access toggles.
    // The camera VC keeps streaming either way — only its page is hidden.
    private let adminViewController = AdminViewController()
    private let cameraViewController = CameraViewController()

    // App-wide playback monitoring
    private var playbackCheckTimer: Timer?
    private var stallObserver: NSObjectProtocol?
    private var errorObserver: NSObjectProtocol?

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

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleChannelsLoaded),
            name: PlaybackManager.channelsDidLoad,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleParticipantConnected(_:)),
            name: LiveKitManager.participantConnectedNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleParticipantDisconnected(_:)),
            name: LiveKitManager.participantDisconnectedNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleGuidedAccessStatusChange),
            name: UIAccessibility.guidedAccessStatusDidChangeNotification,
            object: nil
        )
    }

    // MARK: - Guided Access

    /// `true` while the device is locked into this app — either Guided Access
    /// (triple-click) or MDM Single App Mode, both of which report through the
    /// same flag.
    private var isGuidedAccessActive: Bool {
        UIAccessibility.isGuidedAccessEnabled
    }

    /// Pages hidden while the device is locked into the app, so whoever is
    /// locked in can't reach the playback controls or drop the camera stream.
    /// Listed in the order they sit at the front of the page list.
    private var restrictedViewControllers: [UIViewController] {
        [adminViewController, cameraViewController]
    }

    /// The page to open on, Guided Access or not: the green placeholder. It is
    /// always present and never restricted, and it puts the app in the same
    /// known spot every launch rather than on whichever page happens to be
    /// visible.
    private var landingViewController: UIViewController? {
        greenViewController ?? fallbackViewController
    }

    /// Where to send the user when the page they are on gets hidden. Green for
    /// the same reason, falling back to any unrestricted page if it somehow
    /// isn't in the list yet.
    private var fallbackViewController: UIViewController? {
        greenViewController
            ?? viewControllers.first(where: { !restrictedViewControllers.contains($0) })
    }

    @objc private func handleGuidedAccessStatusChange() {
        // Posted on the main thread by UIKit.
        updateRestrictedPageVisibility()
    }

    /// Adds or removes the restricted pages in place. Deliberately not a full
    /// `customizeViewControllers()` rebuild — Guided Access can be toggled at
    /// any time, including while a video is playing.
    private func updateRestrictedPageVisibility() {
        if isGuidedAccessActive {
            for vc in restrictedViewControllers {
                guard let index = viewControllers.firstIndex(of: vc) else { continue }
                // Page away first if this one is on screen, so the page view
                // controller is never left showing a controller that's no longer
                // in the list (its neighbours would come back nil and paging
                // would dead-end).
                if pageViewController.viewControllers?.first === vc {
                    guard let fallback = fallbackViewController else { continue }
                    show(page: fallback, animated: true)
                }
                viewControllers.remove(at: index)
            }
        } else {
            // Restore them at the front, in order, around whichever are already there.
            var insertIndex = 0
            for vc in restrictedViewControllers {
                if let existing = viewControllers.firstIndex(of: vc) {
                    insertIndex = existing + 1
                } else {
                    viewControllers.insert(vc, at: insertIndex)
                    insertIndex += 1
                }
            }
        }
    }

    /// Moves the page view controller to `page`, keeping `currentVideoView` in
    /// step — `didFinishAnimating` only fires for user-driven swipes.
    /// Unlike `didFinishAnimating` this doesn't bump the outgoing channel's
    /// offset — the user didn't swipe away, the page was moved out from under them.
    private func show(page: UIViewController, animated: Bool) {
        let incoming = page as? VideoViewController
        if let outgoing = currentVideoView, outgoing !== incoming {
            outgoing.stopVideo()
        }

        pageViewController.setViewControllers([page], direction: .forward, animated: animated, completion: nil)

        currentVideoView = incoming
        if let incoming {
            PlaybackManager.shared.setChannelIndex(index: incoming.channelIndex)
            incoming.resumePlayback()
        }
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
        customTabBar.frame = CGRect(x: 0, y: view.bounds.height - tabBarHeight,
                                    width: view.bounds.width, height: tabBarHeight)
    }

    private func setupPageViewController() {
        pageViewController = UIPageViewController(transitionStyle: .scroll,
                                                   navigationOrientation: .horizontal,
                                                   options: nil)
        pageViewController.dataSource = self
        pageViewController.delegate = self

        pageViewController.view.subviews.forEach { view in
            if let pageControl = view as? UIPageControl {
                pageControl.isHidden = true
            }
        }

        // Always start on the green placeholder, Guided Access or not.
        let initialVC = landingViewController ?? viewControllers.first
        if let initialVC {
            pageViewController.setViewControllers([initialVC], direction: .forward, animated: false, completion: nil)
            // viewDidAppear starts playback; this just keeps the playback
            // watchdog's reference in step, since didFinishAnimating only
            // fires for user-driven swipes.
            currentVideoView = initialVC as? VideoViewController
        }

        addChild(pageViewController)
        view.addSubview(pageViewController.view)
        pageViewController.didMove(toParent: self)

        pageViewController.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            pageViewController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            pageViewController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            pageViewController.view.topAnchor.constraint(equalTo: view.topAnchor),
            pageViewController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    private func customizeViewControllers() {
        // Camera — landing page. Hidden while locked into the app, but it still
        // connects and publishes either way; only the page goes away.
        if !isGuidedAccessActive {
            viewControllers.append(cameraViewController)
        }
        cameraViewController.autoConnect()

        // Boundary: RemoteCameraViewControllers are inserted just before this
        greenViewController = UIViewController()
        greenViewController.view.backgroundColor = .green
        viewControllers.append(greenViewController)

        let channels = PlaybackManager.shared.getChannels()
        print("vc channels = \(channels)")
        for (channelIndex, name) in channels.enumerated() {
            let videoViewController = VideoViewController(name: name, channelIndex: channelIndex)
            viewControllers.append(videoViewController)
        }

        viewControllers.append(contentsOf: self.extraViews)

        let redViewController = UIViewController()
        redViewController.view.backgroundColor = .red
        viewControllers.append(redViewController)

        if !isGuidedAccessActive {
            viewControllers.insert(adminViewController, at: 0)
        }

        // Re-add any currently connected remote participants (e.g. after channels reload)
        for participant in LiveKitManager.shared.room.remoteParticipants.values {
            insertRemoteCameraVC(for: participant)
        }
    }

    // MARK: - Remote participant pages

    private func insertRemoteCameraVC(for participant: RemoteParticipant) {
        let identity = participant.identity?.description ?? ""
        // Avoid duplicates
        guard !viewControllers.contains(where: {
            ($0 as? RemoteCameraViewController)?.participantIdentity == identity
        }) else { return }
        let vc = RemoteCameraViewController(participant: participant)
        let insertAt = viewControllers.firstIndex(of: greenViewController) ?? viewControllers.count - 1
        viewControllers.insert(vc, at: insertAt)
    }

    @objc private func handleParticipantConnected(_ notification: Notification) {
        guard let participant = notification.object as? RemoteParticipant else { return }
        DispatchQueue.main.async { [weak self] in
            self?.insertRemoteCameraVC(for: participant)
        }
    }

    @objc private func handleParticipantDisconnected(_ notification: Notification) {
        guard let participant = notification.object as? RemoteParticipant else { return }
        let identity = participant.identity?.description ?? ""
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            viewControllers.removeAll {
                ($0 as? RemoteCameraViewController)?.participantIdentity == identity
            }
        }
    }

    // MARK: UIPageViewControllerDataSource

    func pageViewController(_ pageViewController: UIPageViewController, viewControllerBefore viewController: UIViewController) -> UIViewController? {
        guard let index = viewControllers.firstIndex(of: viewController), index > 0 else {
            return nil
        }
        return viewControllers[index - 1]
    }

    func pageViewController(_ pageViewController: UIPageViewController, viewControllerAfter viewController: UIViewController) -> UIViewController? {
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
        setupPlaybackMonitoring()
        startVideoPlayback()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        teardownPlaybackMonitoring()
        stopVideoPlayback()
    }

    // MARK: - App-wide Playback Monitoring

    private func setupPlaybackMonitoring() {
        playbackCheckTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.checkActiveVideoPlayback()
        }
        stallObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemPlaybackStalled,
            object: nil,
            queue: .main) { [weak self] _ in
                self?.handlePlaybackInterruption()
        }
        errorObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemFailedToPlayToEndTime,
            object: nil,
            queue: .main) { [weak self] _ in
                self?.handlePlaybackInterruption()
        }
    }

    private func teardownPlaybackMonitoring() {
        playbackCheckTimer?.invalidate()
        playbackCheckTimer = nil
        if let observer = stallObserver {
            NotificationCenter.default.removeObserver(observer)
            stallObserver = nil
        }
        if let observer = errorObserver {
            NotificationCenter.default.removeObserver(observer)
            errorObserver = nil
        }
    }

    private func checkActiveVideoPlayback() {
        guard let activeVideo = currentVideoView, activeVideo.playing else { return }
        guard let player = activeVideo.player else { return }
        if player.timeControlStatus == .paused {
            player.play()
        }
    }

    private func handlePlaybackInterruption() {
        guard let activeVideo = currentVideoView, activeVideo.playing else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.currentVideoView?.resumePlayback()
        }
    }

    func pageViewController(_ pageViewController: UIPageViewController, didFinishAnimating finished: Bool, previousViewControllers: [UIViewController], transitionCompleted completed: Bool) {
        if let oldplayer = currentVideoView, oldplayer != pageViewController.viewControllers?.first as? VideoViewController {
            oldplayer.stopVideo()
            PlaybackManager.shared.incrementChannelOffset(channelIndex: oldplayer.channelIndex)
        }

        guard let currentViewController = pageViewController.viewControllers?.first as? VideoViewController else {
            currentVideoView = nil
            return
        }

        if currentVideoView == currentViewController { return }

        print("starting \(currentViewController.name)")
        PlaybackManager.shared.setChannelIndex(index: currentViewController.channelIndex)
        currentVideoView = currentViewController
        currentVideoView?.resumePlayback()
    }

    @objc private func handleChannelsLoaded() {
        print("handleChannelsLoaded")
        viewControllers.removeAll()
        customizeViewControllers()
        // Reuse the existing page view controller rather than building a second
        // one on top of it — the admin and camera pages are reused instances and
        // can only be parented by one page view controller at a time.
        if let landing = landingViewController ?? viewControllers.first {
            show(page: landing, animated: false)
        }
        print("done loading channels")
    }
}
