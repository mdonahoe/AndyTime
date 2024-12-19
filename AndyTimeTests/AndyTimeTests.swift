//
//  AndyTimeTests.swift
//  AndyTimeTests
//
//  Created by Matt Donahoe on 12/18/24.
//

import Testing
import Foundation
@testable import AndyTime2

struct AndyTimeTests {

    @Test func testCalculatePlaylistPosition() async throws {
        // Write your test here and use APIs like `#expect(...)` to check expected conditions.
        // Test case 1: Simple playlist, time within first video
        let result1 = PlaybackManager.shared.calculatePlaylistPosition(
            playbackTime: 5,
            videoDurations: [10, 10, 10]
        )
        #expect(result1.videoIndex == 0)
        #expect(result1.seekTime == 5)
        
        // Test case 2: Time in second video
        let result2 = PlaybackManager.shared.calculatePlaylistPosition(
            playbackTime: 15,
            videoDurations: [10, 10, 10]
        )
        #expect(result2.videoIndex == 1)
        #expect(result2.seekTime == 5)
        
        // Test case 3: Wrapping around playlist
        let result3 = PlaybackManager.shared.calculatePlaylistPosition(
            playbackTime: 35,
            videoDurations: [10, 10, 10]
        )
        #expect(result3.videoIndex == 0 )
        #expect(result3.seekTime == 5)
        
        // Test case 4: Empty playlist
        let result4 = PlaybackManager.shared.calculatePlaylistPosition(
            playbackTime: 5,
            videoDurations: []
        )
        #expect(result4.videoIndex == 0)
        #expect(result4.seekTime == 0)
        
        // Test case 5: Exact video boundary
        let result5 = PlaybackManager.shared.calculatePlaylistPosition(
            playbackTime: 10,
            videoDurations: [10, 10, 10]
        )
        #expect(result5.videoIndex == 1)
        #expect(result5.seekTime == 0)
        
        // Test case 6: Uneven video lengths
        let result6 = PlaybackManager.shared.calculatePlaylistPosition(
            playbackTime: 25,
            videoDurations: [5, 15, 10]
        )
        #expect(result6.videoIndex == 2)
        #expect(result6.seekTime == 5)
    }

    @Test func testGetState() async throws {
        // Add some videos to the playlist
        PlaybackManager.shared.addVideo(url: "file:///Foo/animals-bear.mp4", duration: 60)
        PlaybackManager.shared.addVideo(url: "file:///Foo/animals-cat.mp4", duration: 30)
        PlaybackManager.shared.addVideo(url: "file:///Foo/animals-dog.mp4", duration: 30)
        PlaybackManager.shared.addVideo(url: "file:///Foo/people-santa.mp4", duration: 10)
        PlaybackManager.shared.addVideo(url: "file:///Foo/movies-the-rock.mp4", duration: 1000)
        PlaybackManager.shared.setChannelIndex(index: 0)
        PlaybackManager.shared.resetTime()
        
        // Should be at the beginning of the first video.
        let state0 = PlaybackManager.shared.getState()
        #expect(state0.channelName == "animals")
        #expect(state0.playlistPosition.videoIndex == 0)
        #expect(state0.playlistPosition.seekTime >= 0 && state0.playlistPosition.seekTime <= 1)
        
        // Advance to second video.
        PlaybackManager.shared.adjustTime(by: 65)
        let state1 = PlaybackManager.shared.getState()
        #expect(state1.channelName == "animals")
        #expect(state1.playlistPosition.videoIndex == 1)
        #expect(state1.playlistPosition.seekTime >= 5 && state1.playlistPosition.seekTime <= 6)
        
        // Advance to third video
        PlaybackManager.shared.adjustTime(by: 25)
        let state2 = PlaybackManager.shared.getState()
        #expect(state2.channelName == "animals")
        #expect(state2.playlistPosition.videoIndex == 2)
        #expect(state2.playlistPosition.seekTime >= 0 && state2.playlistPosition.seekTime <= 1)
        
        // Switching channels should bring us to a different video.
        PlaybackManager.shared.setChannelIndex(index: 1)
        let state3 = PlaybackManager.shared.getState()
        #expect(state3.channelName == "people")
        #expect(state3.playlistPosition.videoIndex == 0)
        #expect(state3.playlistPosition.seekTime >= 0 && state3.playlistPosition.seekTime <= 1)
        
        // Switching again without advancing time, and the long video has not looped.
        PlaybackManager.shared.setChannelIndex(index: 2)
        let state4 = PlaybackManager.shared.getState()
        #expect(state4.channelName == "movies")
        #expect(state4.playlistPosition.videoIndex == 0)
        #expect(state4.playlistPosition.seekTime >= 90 && state4.playlistPosition.seekTime <= 91)
        
        // Switch back to first channel, and advance time so it loops
        PlaybackManager.shared.setChannelIndex(index: 0)
        PlaybackManager.shared.adjustTime(by: 40)
        let state5 = PlaybackManager.shared.getState()
        #expect(state5.channelName == "animals")
        #expect(state5.playlistPosition.videoIndex == 0)
        #expect(state5.playlistPosition.seekTime >= 10 && state5.playlistPosition.seekTime <= 11)
    }
}
