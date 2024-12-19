import Foundation
import AVKit

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
    
    func getChannels() -> [String] {
        return channels
    }
    
    func loadVideos() {
        func calculateDurationForVideo(videoUrl: URL) {
            let asset = AVURLAsset(url: videoUrl)
            asset.loadValuesAsynchronously(forKeys: ["duration"]) { [weak self] in
                guard self != nil else { return }
                let duration = asset.duration
                self?.addVideo(url: videoUrl.absoluteString, duration: duration.seconds)
            }
        }
        // Add video views
        let videoUrls = getMP4FileURLs()
        for videoUrl in videoUrls {
            calculateDurationForVideo(videoUrl: videoUrl)
        }
        // TODO(matt): how do we wait for the channels to be loaded?
        print("presorted channels = \(channels)")
        channels.sort()
        print("sorted channels = \(channels)")
    }
    
    func getMP4FileURLs() -> [URL] {
        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let mp4Files = try? FileManager.default.contentsOfDirectory(at: documentsURL, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "mp4" }
        return mp4Files ?? []
    }

    func addVideo(url: String, duration: TimeInterval) {
        // parse the channel name from the url
        let fileName = String(url.split(separator: "/").last!)
        let channelName = String(fileName.split(separator: "-").first!)
        videoDurations[url] = duration
        channelVideos[channelName] = (channelVideos[channelName] ?? []) + [url]
        if !channels.contains(channelName) {
            channels.append(channelName)
        }
        print("added \(fileName)")
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
    struct PlaybackState {
        let channelName: String
        let videoUrl: String
        let playlistPosition: PlaylistPosition
    }
    struct PlaylistPosition {
        let videoIndex: Int
        let seekTime: TimeInterval
    }
    
    func calculatePlaylistPosition(playbackTime: TimeInterval, videoDurations: [TimeInterval]) -> PlaylistPosition {
        guard !videoDurations.isEmpty else {
            return PlaylistPosition(videoIndex: 0, seekTime: 0)
        }
        
        let totalDuration = videoDurations.reduce(0, +)
        var remainingTime = playbackTime.truncatingRemainder(dividingBy: totalDuration)
        
        for (index, duration) in videoDurations.enumerated() {
            if remainingTime < duration {
                return PlaylistPosition(videoIndex: index, seekTime: remainingTime)
            }
            remainingTime -= duration
        }
        
        // This should never happen if we're using truncatingRemainder correctly
        return PlaylistPosition(videoIndex: 0, seekTime: 0)
    }

    func setChannelIndex(index: Int) {
        currentChannelIndex = index
    }

    func getState() -> PlaybackState {
        let channelName = channels[currentChannelIndex]
        let videos = channelVideos[channelName] ?? []
        let durations = videos.map { videoDurations[$0] ?? 0 }
        print("channel=\(channelName) videos=\(videos) durations=\(durations)")
        let playbackTime = currentPlaybackTime
        let playlistPosition = calculatePlaylistPosition(playbackTime: playbackTime, videoDurations: durations)
        let videoUrl : String = videos[playlistPosition.videoIndex]
        return PlaybackState(
            channelName: channelName,
            videoUrl: videoUrl,
            playlistPosition: playlistPosition)
    }

}
