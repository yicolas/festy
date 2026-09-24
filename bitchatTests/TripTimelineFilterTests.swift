//
// TripTimelineFilterTests.swift
// bitchatTests
//
// Trip channels are hashtag filters over the public mesh timeline. Media
// messages carry no text, so they show in every channel.
//

import Testing
import Foundation
import BitFoundation
@testable import bitchat

@MainActor
struct TripTimelineFilterTests {

    private func msg(_ content: String) -> BitchatMessage {
        BitchatMessage(sender: "a", content: content, timestamp: Date(timeIntervalSince1970: 0), isRelay: false)
    }

    private func visible(_ filter: String?, _ contents: [String]) -> [String] {
        TripTimelineFilter.visibleMessages(contents.map(msg), hashtagFilter: filter).map(\.content)
    }

    @Test func channelShowsTaggedPostsAndMedia() {
        let shown = visible("#gear", ["hi #main", "stove? #gear", "[image] IMG_1.jpg", "[voice] v.m4a", "lunch #meals"])
        #expect(shown == ["stove? #gear", "[image] IMG_1.jpg", "[voice] v.m4a"])
    }

    @Test func mainShowsMediaButNotMeals() {
        let shown = visible("#main", ["hi", "dinner #meals", "[image] IMG_2.jpg"])
        #expect(shown == ["hi", "[image] IMG_2.jpg"])
    }
}
