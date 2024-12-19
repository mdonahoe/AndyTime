import Foundation

class PlaybackManager {
    static let shared = PlaybackManager()
    
    // Notification name for time updates
    static let playbackTimeDidChange = Notification.Name("playbackTimeDidChange")
    
    private var startTime: Date
    private var currentVideoIndex: Int
    private var currentChannelIndex: Int
    private var videoDurations: Dictionary<String, TimeInterval>
    private var channelVideos: Dictionary<String, [String]>
    private var channels: [String]
    
    private init() {
        startTime = Date()
        currentVideoIndex = 0
        currentChannelIndex = 0
        channels = []
        channelVideos = [:]
        videoDurations = [:]
    }
    
    // Current playback time in seconds
    var currentPlaybackTime: TimeInterval {
        return -startTime.timeIntervalSinceNow
    }

    func addVideo(url: String, duration: TimeInterval) {
        // parse the channel name from the url
        let fileName = String(url.split(separator: "/").last!)
        let channelName = String(fileName.split(separator: "-").first!)
        videoDurations[fileName] = duration
        channelVideos[channelName] = (channelVideos[channelName] ?? []) + [fileName]
        if !channels.contains(channelName) {
            channels.append(channelName)
        }
        print(channels, channelVideos, videoDurations)
    }
    
    // Adjust time by modifying the start time in the opposite direction
    func adjustTime(by seconds: TimeInterval) {
        startTime = startTime.addingTimeInterval(-seconds)
        notifyTimeChange()
    }
    
    func resetTime() {
        startTime = Date()
        notifyTimeChange()
    }
    
    private func notifyTimeChange() {
        NotificationCenter.default.post(name: PlaybackManager.playbackTimeDidChange,
                                     object: nil, 
                                     userInfo: ["playbackTime": currentPlaybackTime])
    }
    
    struct PlaylistPosition {
        let channelName: String
        let videoIndex: Int
        let seekTime: TimeInterval
    }
    
    func calculatePlaylistPosition(playbackTime: TimeInterval, videoDurations: [TimeInterval], channelName: String) -> PlaylistPosition {
        guard !videoDurations.isEmpty else {
            return PlaylistPosition(channelName: channelName, videoIndex: 0, seekTime: 0)
        }
        
        let totalDuration = videoDurations.reduce(0, +)
        var remainingTime = playbackTime.truncatingRemainder(dividingBy: totalDuration)
        
        for (index, duration) in videoDurations.enumerated() {
            if remainingTime < duration {
                return PlaylistPosition(channelName: channelName, videoIndex: index, seekTime: remainingTime)
            }
            remainingTime -= duration
        }
        
        // This should never happen if we're using truncatingRemainder correctly
        return PlaylistPosition(channelName: channelName, videoIndex: 0, seekTime: 0)
    }

    func setChannelIndex(index: Int) {
        currentChannelIndex = index
    }

    func getState() -> PlaylistPosition {
        let channelName = channels[currentChannelIndex]
        let videos = channelVideos[channelName] ?? []
        let durations = videos.map { videoDurations[$0] ?? 0 }
        print("videos = \(videos) durations \(durations)")
        let playbackTime = currentPlaybackTime
        return calculatePlaylistPosition(playbackTime: playbackTime, videoDurations: durations, channelName: channelName)
    }

}
