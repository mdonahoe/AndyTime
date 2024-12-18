import AVFoundation
import AVKit

class VideoViewController: UIViewController {
    
    var name : String = ""
    private var videoPlaylist: [URL] = []
    private var currentVideoIndex: Int = 0
    var player: AVPlayer?
    private var playerLayer: AVPlayerLayer?
    private var playerItemObserver: NSObjectProtocol?
    private var totalPlaylistDuration: TimeInterval = 0
    private var lastPauseTime: Date?
    private var accumulatedPlayTime: TimeInterval = 0
    private var playlistStartTime: Date?
    
    convenience init(name: String, videoPlaylist: [URL]) {
        self.init()
        self.name = name
        self.videoPlaylist = videoPlaylist
        calculateTotalDuration()
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        setupPlayer()
        print("player?.currentItem: \(player?.currentItem)")
        NotificationCenter.default.addObserver(self,
                                             selector: #selector(playerDidFinishPlaying),
                                             name: .AVPlayerItemDidPlayToEndTime,
                                             object: player?.currentItem)
        
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
    
    // TODO(matt): refactor this to accept an index.
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
        if playlistStartTime == nil {
            playlistStartTime = Date()
        } else if let pauseTime = lastPauseTime {
            accumulatedPlayTime += Date().timeIntervalSince(pauseTime)
        }
        lastPauseTime = nil
        player?.play()
    }
    
    func stopVideo() {
        lastPauseTime = Date()
        player?.pause()
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
    
    private func calculateTotalDuration() {
        func calculateDurationForVideo(at index: Int, totalDuration: TimeInterval) {
            guard index < videoPlaylist.count else {
                self.totalPlaylistDuration = totalDuration
                return
            }
            
            let asset = AVURLAsset(url: videoPlaylist[index])
            asset.loadValuesAsynchronously(forKeys: ["duration"]) { [weak self] in
                guard self != nil else { return }
                let duration = asset.duration
                let newTotal = totalDuration + CMTimeGetSeconds(duration)
                calculateDurationForVideo(at: index + 1, totalDuration: newTotal)
            }
        }
        
        calculateDurationForVideo(at: 0, totalDuration: 0)
    }
    
    func getCurrentPlaylistPosition() -> TimeInterval {
        guard let startTime = playlistStartTime else { return 0 }
        
        let totalElapsedTime = accumulatedPlayTime + 
            (lastPauseTime == nil ? Date().timeIntervalSince(startTime) : 0)
        
        // Calculate position within the total playlist duration
        return totalElapsedTime.truncatingRemainder(dividingBy: totalPlaylistDuration)
    }
    
    func seekToPlaylistPosition(_ position: TimeInterval) {
        var targetPosition = position
        var targetVideoIndex = 0
        
        // Find the target video and position within it
        for (index, url) in videoPlaylist.enumerated() {
            let asset = AVURLAsset(url: url)
            let duration = CMTimeGetSeconds(asset.duration)
            
            if targetPosition < duration {
                targetVideoIndex = index
                break
            }
            targetPosition -= duration
        }
        
        // Update current video and seek to position
        currentVideoIndex = targetVideoIndex
        let targetTime = CMTime(seconds: targetPosition, preferredTimescale: 600)
        player?.seek(to: targetTime)
    }
    
    @objc private func handleTimeUpdate(_ notification: Notification) {
        print("handleTimeUpdate \(name) index=\(currentVideoIndex) url=\(videoPlaylist[currentVideoIndex])")
        let playbackTime = PlaybackManager.shared.currentPlaybackTime
        // Implement video seeking logic here, with wrapping
        let videoLength = totalPlaylistDuration
        let seekTime = playbackTime.truncatingRemainder(dividingBy: videoLength)
        // Seek video to seekTime
        seekToPlaylistPosition(seekTime)
    }

}
