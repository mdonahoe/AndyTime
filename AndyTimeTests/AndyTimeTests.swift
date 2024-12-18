//
//  AndyTimeTests.swift
//  AndyTimeTests
//
//  Created by Matt Donahoe on 12/18/24.
//

import Testing
@testable import AndyTime2

struct AndyTimeTests {

    @Test func example() async throws {
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
            videoDurations: [10, 10, 10]  // Total duration: 30
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
}
