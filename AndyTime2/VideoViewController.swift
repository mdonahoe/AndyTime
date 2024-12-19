import AVFoundation
import AVKit

class VideoViewController: UIViewController {
    
    var name : String = ""
    var channelIndex : Int = 0
    var player: AVPlayer?
    private var playerLayer: AVPlayerLayer?
    private var playerItemObserver: NSObjectProtocol?
    private var playing: Bool = false
    
    convenience init(name: String, channelIndex: Int) {
        self.init()
        self.name = name
        self.channelIndex = channelIndex
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupPlayer()
        NotificationCenter.default.addObserver(self, 
            selector: #selector(handleTimeUpdate), 
            name: PlaybackManager.playbackTimeDidChange, 
            object: nil)
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        playerLayer?.frame = view.bounds
    }
    
    private func setupPlayer() {
        player = AVPlayer()
        playerLayer = AVPlayerLayer(player: player)
        playerLayer?.videoGravity = .resizeAspectFill
        if let playerLayer = playerLayer {
            view.layer.addSublayer(playerLayer)
        }
    }
    
    @objc private func playerDidFinishPlaying() {
        print("playerDidFinishPlaying \(name)")
        // playNextVideo()
        // TODO(matt): Alert the PlaybackManager!
    }
    
    func resumePlayback() {
        let state = PlaybackManager.shared.getState()
        self.playVideo(videoUrl: URL(string: state.videoUrl)!, seekTime: state.playlistPosition.seekTime)
    }
    
    private func playVideo(videoUrl: URL, seekTime: TimeInterval) {
        // Remove previous observer
        if let observer = playerItemObserver {
            NotificationCenter.default.removeObserver(observer)
            playerItemObserver = nil
        }
        
        let playerItem = AVPlayerItem(url: videoUrl)
        player?.replaceCurrentItem(with: playerItem)
        
        // Add new observer for the new item
        playerItemObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: playerItem,
            queue: .main) { [weak self] _ in
                self?.playerDidFinishPlaying()
        }
        playing = true
        let t = CMTime(seconds: seekTime, preferredTimescale: 600) // Why 600?
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

}
