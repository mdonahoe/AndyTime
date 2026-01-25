import AVFoundation
import AVKit

/// A view controller that displays video playback for a single channel.
///
/// `VideoViewController` handles all aspects of video playback for one channel in the app.
/// Each instance is associated with a specific channel index and displays videos from that channel.
///
/// ## Key Features
/// - Uses `AVPlayer` and `AVPlayerLayer` for video rendering
/// - Displays the video filename as an overlay label that fades out after 5 seconds
/// - Black background that fills the screen
/// - Responds to playback time change notifications from `PlaybackManager`
///
/// ## Playback Logic
/// When `resumePlayback()` is called:
/// 1. Queries `PlaybackManager` for the current playback state
/// 2. Determines which video should be playing based on elapsed time
/// 3. If the same video is already loaded, seeks to the correct position
/// 4. If a different video is needed, replaces the player item entirely
///
/// ## Video Completion
/// When a video finishes playing, the controller automatically advances to the next video
/// in the channel by calling `resumePlayback()` again, which recalculates the correct
/// video and position based on the current time.
class VideoViewController: UIViewController {

    var name : String = ""
    var channelIndex : Int = 0
    var player: AVPlayer?
    private var playerLayer: AVPlayerLayer?
    private var playerItemObserver: NSObjectProtocol?
    private var stallObserver: NSObjectProtocol?
    private var errorObserver: NSObjectProtocol?
    private var playbackCheckTimer: Timer?
    private var playing: Bool = false
    
    // Add a black background view
    private let blackBackgroundView: UIView = {
        let view = UIView()
        view.backgroundColor = .black
        return view
    }()
    
    // Add this property near the top with other properties
    private let nameLabel: UILabel = {
        var label = UILabel()
        label.font = .systemFont(ofSize: 16, weight: .medium)
        label.textColor = .white
        label.alpha = 0
        return label
    }()
    
    convenience init(name: String, channelIndex: Int) {
        self.init()
        self.name = name
        self.channelIndex = channelIndex
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        // Add black background view first
        view.addSubview(blackBackgroundView)
        blackBackgroundView.frame = view.bounds
        

        
        setupPlayer()
        
        // Add and position the name label
        view.addSubview(nameLabel)
        nameLabel.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            nameLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
            nameLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16)
        ])
        NotificationCenter.default.addObserver(self,
            selector: #selector(handleTimeUpdate), 
            name: PlaybackManager.playbackTimeDidChange, 
            object: nil)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        print("viewWillAppear \(name)")
        let state = PlaybackManager.shared.getState(for: self.channelIndex)
        if !playing {
            print("not playing \(name), updating frame")
            self.playVideo(videoUrl: URL(string: state.videoUrl)!, seekTime: state.playlistPosition.seekTime)
            self.stopVideo()
        } else {
            print("is playing \(name), no-op")
        }
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        blackBackgroundView.frame = view.bounds
        playerLayer?.frame = view.bounds
    }
    
    private func setupPlayer() {
        player = AVPlayer()
        playerLayer = AVPlayerLayer(player: player)
        playerLayer?.videoGravity = .resizeAspectFill
        if let playerLayer = playerLayer {
            view.layer.addSublayer(playerLayer)
        }

        // Observe playback stalls
        stallObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemPlaybackStalled,
            object: nil,
            queue: .main) { [weak self] _ in
                print("Playback stalled, attempting to resume...")
                self?.handlePlaybackInterruption()
        }

        // Observe player errors
        errorObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemFailedToPlayToEndTime,
            object: nil,
            queue: .main) { [weak self] _ in
                print("Playback failed, attempting to resume...")
                self?.handlePlaybackInterruption()
        }
    }

    private func startPlaybackMonitor() {
        stopPlaybackMonitor()
        playbackCheckTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.checkPlaybackStatus()
        }
    }

    private func stopPlaybackMonitor() {
        playbackCheckTimer?.invalidate()
        playbackCheckTimer = nil
    }

    private func checkPlaybackStatus() {
        guard playing else { return }
        guard let player = player else { return }

        // If we should be playing but the player is paused, resume
        if player.timeControlStatus == .paused {
            print("Video unexpectedly paused, resuming...")
            player.play()
        }
    }

    private func handlePlaybackInterruption() {
        guard playing else { return }
        // Brief delay then resume playback
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.resumePlayback()
        }
    }
    
    @objc private func playerDidFinishPlaying() {
        print("playerDidFinishPlaying \(name)")
        // TODO(matt): Alert the PlaybackManager!
        // TODO(matt): could there be a race condition here?
        self.resumePlayback()
    }
    
    func resumePlayback() {
        let state = PlaybackManager.shared.getState()
        self.playVideo(videoUrl: URL(string: state.videoUrl)!, seekTime: state.playlistPosition.seekTime)
    }
    
    private func playVideo(videoUrl: URL, seekTime: TimeInterval) {
        // Extract the filename from the URL and show it
        let videoName = videoUrl.lastPathComponent
        nameLabel.text = videoName
        nameLabel.alpha = 1
        
        // Fade out after 5 seconds
        UIView.animate(withDuration: 1.0, delay: 3.0) {
            self.nameLabel.alpha = 0
        }

        // Check if we're already playing this URL
        if let currentItem = player?.currentItem,
           let currentURL = (currentItem.asset as? AVURLAsset)?.url,
           currentURL == videoUrl {
            print("same video \(name)")
            if playing {
            print("already playing \(name)")
            // TODO(matt): check the time
            return
        }
            // Same video, just seek to new position
            let t = CMTime(seconds: seekTime, preferredTimescale: 600)
            player?.seek(to: t)
            if !playing {
                playing = true
                player?.play()
                startPlaybackMonitor()
            }
            return
        }
        print("different video \(name)")
        // Different video, proceed with full replacement
        if let observer = playerItemObserver {
            NotificationCenter.default.removeObserver(observer)
            playerItemObserver = nil
        }
        
        let playerItem = AVPlayerItem(url: videoUrl)
        player?.replaceCurrentItem(with: playerItem)
        
        playerItemObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: playerItem,
            queue: .main) { [weak self] _ in
                self?.playerDidFinishPlaying()
        }
        
        playing = true
        let t = CMTime(seconds: seekTime, preferredTimescale: 600)
        player?.seek(to: t)
        player?.play()
        startPlaybackMonitor()
    }

    func stopVideo() {
        playing = false
        stopPlaybackMonitor()
        player?.pause()
    }

    deinit {
        stopPlaybackMonitor()
        if let observer = stallObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        if let observer = errorObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }
    
    @objc private func handleTimeUpdate(_ notification: Notification) {
        print("handleTimeUpdate \(name)")
    }

}
