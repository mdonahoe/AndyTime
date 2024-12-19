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
            videoDurations: [10, 10, 10],
            channelName: "Channel 1"
        )
        #expect(result1.videoIndex == 0)
        #expect(result1.seekTime == 5)
        
        // Test case 2: Time in second video
        let result2 = PlaybackManager.shared.calculatePlaylistPosition(
            playbackTime: 15,
            videoDurations: [10, 10, 10],
            channelName: "Channel 1"
        )
        #expect(result2.videoIndex == 1)
        #expect(result2.seekTime == 5)
        
        // Test case 3: Wrapping around playlist
        let result3 = PlaybackManager.shared.calculatePlaylistPosition(
            playbackTime: 35,
            videoDurations: [10, 10, 10],
            channelName: "Channel 1"
        )
        #expect(result3.videoIndex == 0 )
        #expect(result3.seekTime == 5)
        
        // Test case 4: Empty playlist
        let result4 = PlaybackManager.shared.calculatePlaylistPosition(
            playbackTime: 5,
            videoDurations: [],
            channelName: "Channel 1"
        )
        #expect(result4.videoIndex == 0)
        #expect(result4.seekTime == 0)
        
        // Test case 5: Exact video boundary
        let result5 = PlaybackManager.shared.calculatePlaylistPosition(
            playbackTime: 10,
            videoDurations: [10, 10, 10],
            channelName: "Channel 1"
        )
        #expect(result5.videoIndex == 1)
        #expect(result5.seekTime == 0)
        
        // Test case 6: Uneven video lengths
        let result6 = PlaybackManager.shared.calculatePlaylistPosition(
            playbackTime: 25,
            videoDurations: [5, 15, 10],
            channelName: "Channel 1"
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
        PlaybackManager.shared.adjustTime(by: 65)
        let state1 = PlaybackManager.shared.getState()
        #expect(state1.channelName == "animals")
        #expect(state1.videoIndex == 1)
        #expect(state1.seekTime >= 5 && state1.seekTime <= 6)
        
        PlaybackManager.shared.adjustTime(by: 25)
        let state2 = PlaybackManager.shared.getState()
        #expect(state2.channelName == "animals")
        #expect(state2.videoIndex == 2)
        #expect(state2.seekTime >= 0 && state2.seekTime <= 1)
        
        PlaybackManager.shared.setChannelIndex(index: 1)
        let state3 = PlaybackManager.shared.getState()
        #expect(state3.channelName == "people")
        #expect(state3.videoIndex == 0)
        #expect(state3.seekTime >= 0 && state3.seekTime <= 1)
        
        PlaybackManager.shared.setChannelIndex(index: 2)
        let state4 = PlaybackManager.shared.getState()
        #expect(state4.channelName == "movies")
        #expect(state4.videoIndex == 0)
        #expect(state4.seekTime >= 90 && state4.seekTime <= 91)
    }
}
