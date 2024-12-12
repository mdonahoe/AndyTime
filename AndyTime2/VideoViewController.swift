import AVFoundation
import AVKit

class VideoViewController: UIViewController {
    
    var name : String = ""
    private var videoPlaylist: [URL] = []
    private var currentVideoIndex: Int = 0
    var player: AVPlayer?
    private var playerLayer: AVPlayerLayer?
    private var playerItemObserver: NSObjectProtocol?
    
    convenience init(name: String, videoPlaylist: [URL]) {
        self.init()
        self.name = name
        self.videoPlaylist = videoPlaylist
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        setupPlayer()
        print("player?.currentItem: \(player?.currentItem)")
        NotificationCenter.default.addObserver(self,
                                             selector: #selector(playerDidFinishPlaying),
                                             name: .AVPlayerItemDidPlayToEndTime,
                                             object: player?.currentItem)
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        
        playerLayer?.frame = view.bounds
    }
    
    private func setupPlayer() {
        guard !videoPlaylist.isEmpty else { return }
        
        player = AVPlayer(url: videoPlaylist[currentVideoIndex])
        playerLayer = AVPlayerLayer(player: player)
        playerLayer?.videoGravity = .resizeAspectFill
        
        if let playerLayer = playerLayer {
            view.layer.addSublayer(playerLayer)
        }
    }
    
    @objc private func playerDidFinishPlaying() {
        print("playerDidFinishPlaying \(name) index=\(currentVideoIndex) url=\(videoPlaylist[currentVideoIndex])")
        playNextVideo()
    }
    
    private func playNextVideo() {
        // Remove previous observer
        if let observer = playerItemObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        
        currentVideoIndex += 1
        
        if currentVideoIndex >= videoPlaylist.count {
            currentVideoIndex = 0
        }
        
        let nextURL = videoPlaylist[currentVideoIndex]
        let playerItem = AVPlayerItem(url: nextURL)
        player?.replaceCurrentItem(with: playerItem)
        
        // Add new observer for the new item
        playerItemObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: playerItem,
            queue: .main) { [weak self] _ in
                self?.playerDidFinishPlaying()
        }
        
        player?.play()
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
            print("would restarting \(name) index=\(currentVideoIndex) url=\(videoPlaylist[currentVideoIndex])")
            // p.seek(to: CMTime.zero)
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
