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
    private var timeObserver: Any?
    private(set) var playing: Bool = false

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

    // Progress bar views
    private let progressBarTrack: UIView = {
        let view = UIView()
        view.backgroundColor = UIColor.white.withAlphaComponent(0.3)
        return view
    }()

    private let progressBarFill: UIView = {
        let view = UIView()
        view.backgroundColor = .white
        return view
    }()

    private let timeRemainingLabel: UILabel = {
        let label = UILabel()
        label.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        label.textColor = .white
        label.alpha = 0.8
        return label
    }()

    private var progressBarFillWidthConstraint: NSLayoutConstraint?
    
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

        setupProgressBar()

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

        // Add periodic time observer for progress bar updates
        let interval = CMTime(seconds: 0.5, preferredTimescale: 600)
        timeObserver = player?.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            self?.updateProgressBar()
        }
    }

    private func setupProgressBar() {
        let barHeight: CGFloat = 3

        view.addSubview(progressBarTrack)
        progressBarTrack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            progressBarTrack.topAnchor.constraint(equalTo: view.topAnchor),
            progressBarTrack.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            progressBarTrack.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            progressBarTrack.heightAnchor.constraint(equalToConstant: barHeight)
        ])

        progressBarTrack.addSubview(progressBarFill)
        progressBarFill.translatesAutoresizingMaskIntoConstraints = false
        let fillWidth = progressBarFill.widthAnchor.constraint(equalToConstant: 0)
        progressBarFillWidthConstraint = fillWidth
        NSLayoutConstraint.activate([
            progressBarFill.topAnchor.constraint(equalTo: progressBarTrack.topAnchor),
            progressBarFill.leadingAnchor.constraint(equalTo: progressBarTrack.leadingAnchor),
            progressBarFill.bottomAnchor.constraint(equalTo: progressBarTrack.bottomAnchor),
            fillWidth
        ])

        view.addSubview(timeRemainingLabel)
        timeRemainingLabel.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            timeRemainingLabel.topAnchor.constraint(equalTo: progressBarTrack.bottomAnchor, constant: 4),
            timeRemainingLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -8)
        ])
    }

    private func updateProgressBar() {
        guard let currentItem = player?.currentItem,
              currentItem.status == .readyToPlay else { return }

        let duration = currentItem.duration.seconds
        guard duration.isFinite && duration > 0 else { return }

        let currentTime = player?.currentTime().seconds ?? 0
        let progress = min(max(currentTime / duration, 0), 1)
        let trackWidth = progressBarTrack.bounds.width
        progressBarFillWidthConstraint?.constant = trackWidth * CGFloat(progress)

        let remaining = max(duration - currentTime, 0)
        let minutes = Int(remaining) / 60
        let seconds = Int(remaining) % 60
        timeRemainingLabel.text = String(format: "-%d:%02d", minutes, seconds)
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
    }

    func stopVideo() {
        playing = false
        player?.pause()
    }
    
    @objc private func handleTimeUpdate(_ notification: Notification) {
        print("handleTimeUpdate \(name)")
    }

    deinit {
        if let timeObserver = timeObserver {
            player?.removeTimeObserver(timeObserver)
        }
    }

}
