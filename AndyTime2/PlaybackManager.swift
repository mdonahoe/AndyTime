import Foundation
import AVKit

class PlaybackManager {
    static var shared = PlaybackManager()
    
    // Add reset method for testing
    static func resetForTesting() {
        shared = PlaybackManager()
    }
    
    // Notification name for time updates
    static let playbackTimeDidChange = Notification.Name("playbackTimeDidChange")
    
    // Add new notification name
    static let channelsDidLoad = Notification.Name("channelsDidLoad")
    
    private var startTime: Date
    private var currentVideoIndex: Int
    private var currentChannelIndex: Int
    private var videoDurations: Dictionary<String, TimeInterval>
    private var channelVideos: Dictionary<String, [String]>
    private var channels: [String]
    
    private init() {
        startTime = ISO8601DateFormatter().date(from: "2019-01-09T02:20:00Z")!
        currentVideoIndex = 0
        currentChannelIndex = 0
        channels = []
        channelVideos = [:]
        videoDurations = [:]
        print("created")
    }
    
    // Current playback time in seconds
    var currentPlaybackTime: TimeInterval {
        return -startTime.timeIntervalSinceNow
    }
    
    func getChannels() -> [String] {
        return channels
    }
    
    func loadVideos() {
        let dispatchGroup = DispatchGroup()
        let videoUrls = getMP4FileURLs()
        
        for videoUrl in videoUrls {
            dispatchGroup.enter()
            let asset = AVURLAsset(url: videoUrl)
            asset.loadValuesAsynchronously(forKeys: ["duration"]) { [weak self] in
                guard let self = self else {
                    dispatchGroup.leave()
                    return
                }
                let duration = asset.duration
                DispatchQueue.main.async {
                    self.addVideo(url: videoUrl.absoluteString, duration: duration.seconds)
                    dispatchGroup.leave()
                }
            }
        }
        
        dispatchGroup.notify(queue: .main) { [weak self] in
            self?.channels.sort()
            // Post both notifications
            NotificationCenter.default.post(name: PlaybackManager.channelsDidLoad, object: nil)
        }
    }
    
    func getMP4FileURLs() -> [URL] {
        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        print("documents url = \(documentsURL)")
        let mp4Files = try? FileManager.default.contentsOfDirectory(at: documentsURL, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "mp4" }
        return mp4Files ?? []
    }

    func addVideo(url: String, duration: TimeInterval) {
        // parse the channel name from the url
        let fileName = String(url.split(separator: "/").last!)
        let channelName = String(fileName.split(separator: "-").first!)
        print("videoDurations \(videoDurations)")
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
        let channelIndex: Int
        let videoUrl: String
        let videoTitle: String
        let playlistPosition: PlaylistPosition
    }
    struct PlaylistPosition {
        let videoIndex: Int
        let seekTime: TimeInterval
        let videoDuration: TimeInterval
    }
    
    func calculatePlaylistPosition(playbackTime: TimeInterval, videoDurations: [TimeInterval]) -> PlaylistPosition {
        guard !videoDurations.isEmpty else {
            return PlaylistPosition(videoIndex: 0, seekTime: 0, videoDuration: 0)
        }
        
        let totalDuration = videoDurations.reduce(0, +)
        var remainingTime = playbackTime.truncatingRemainder(dividingBy: totalDuration)
        
        for (index, duration) in videoDurations.enumerated() {
            if remainingTime < duration {
                return PlaylistPosition(videoIndex: index, seekTime: remainingTime, videoDuration: duration)
            }
            remainingTime -= duration
        }
        
        // This should never happen if we're using truncatingRemainder correctly
        return PlaylistPosition(videoIndex: 0, seekTime: 0, videoDuration: 0)
    }

    func setChannelIndex(index: Int) {
        guard !channels.isEmpty else {
            print("No channels available")
            return
        }
        let wrappedIndex = ((index % channels.count) + channels.count) % channels.count
        currentChannelIndex = wrappedIndex
        notifyTimeChange()
    }

    func getState() -> PlaybackState {
        guard !channels.isEmpty else {
            print("No channels available")
            return PlaybackState(
                channelName: "",
                channelIndex: currentChannelIndex,
                videoUrl: "",
                videoTitle: "",
                playlistPosition: PlaylistPosition(videoIndex: 0, seekTime: 0, videoDuration: 0))
        }
        return getState(for: currentChannelIndex)
    }
    
    func getState(for channelIndex: Int) -> PlaybackState {
        if channelIndex >= channels.count {
            print("no channels yet")
            return PlaybackState(
                channelName: "",
                channelIndex: channelIndex,
                videoUrl: "",
                videoTitle: "",
                playlistPosition: PlaylistPosition(videoIndex: 0, seekTime: 0, videoDuration: 0))
        }
        let channelName = channels[channelIndex]
        let videos = channelVideos[channelName] ?? []
        let durations = videos.map { videoDurations[$0] ?? 0 }
        let playbackTime = currentPlaybackTime
        let playlistPosition = calculatePlaylistPosition(playbackTime: playbackTime, videoDurations: durations)
        let videoUrl : String = videos[playlistPosition.videoIndex]
        let videoTitle = String(String(videoUrl.split(separator: "/").last!).split(separator: "-", maxSplits: 1).last!)
        return PlaybackState(
            channelName: channelName,
            channelIndex: channelIndex,
            videoUrl: videoUrl,
            videoTitle: videoTitle,
            playlistPosition: playlistPosition)
    }

}
