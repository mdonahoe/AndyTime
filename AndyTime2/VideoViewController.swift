import AVFoundation
import AVKit

class VideoViewController: UIViewController {
    
    public var videoURL: URL?
    public var player: AVPlayer?
    private var playerLayer: AVPlayerLayer?
    
    convenience init(videoURL: URL) {
        self.init()
        self.videoURL = videoURL
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        setupPlayer()
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        
        playerLayer?.frame = view.bounds
    }
    
    private func setupPlayer() {
        guard let videoURL = videoURL else {
            return
        }
        
        player = AVPlayer(url: videoURL)
        playerLayer = AVPlayerLayer(player: player)
        playerLayer?.videoGravity = .resizeAspectFill
        
        if let playerLayer = playerLayer {
            view.layer.addSublayer(playerLayer)
        }
    }
    
    func playVideo() {
        player?.play()
    }
    
    func stopVideo() {
        player?.pause()
        player?.seek(to: .zero)
    }
    
    func restartIfNeeded() {
        if let p = player, isPlayerAtEnd(thePlayer: p) {
            print("restarting \(videoURL)")
            p.seek(to: CMTime.zero)
        }
    }
    
    func isPlayerAtEnd(thePlayer: AVPlayer) -> Bool {
        guard let currentItem = thePlayer.currentItem else {
            return false
        }
        
        let currentTime = thePlayer.currentTime()
        let duration = currentItem.duration
        
        return currentTime >= duration
    }
}
