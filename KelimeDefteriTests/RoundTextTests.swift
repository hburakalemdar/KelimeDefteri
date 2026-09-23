import Foundation
import Testing
@testable import KelimeDefteri

struct RoundTextTests {
    @Test func estimateRoundsUp() {
        #expect(RoundText.estimate(wordCount: 7) == "yaklaşık 3 dk")
        #expect(RoundText.estimate(wordCount: 1) == "yaklaşık 1 dk")
        #expect(RoundText.estimate(wordCount: 12) == "yaklaşık 5 dk")
    }

    @Test func durations() {
        #expect(RoundText.duration(42) == "42 sn")
        #expect(RoundText.duration(65) == "1 dk 5 sn")
        #expect(RoundText.duration(180) == "3 dk")
        #expect(RoundText.summary(correct: 4, total: 5, seconds: 42.4) == "4/5 doğru · 42 sn")
    }

    @Test func dailyLine() {
        #expect(RoundText.daily(weak: 7, new: 0) == "7 kelime zayıfladı · yaklaşık 3 dk")
        #expect(RoundText.daily(weak: 5, new: 2) == "5 kelime zayıfladı · 2 yeni · yaklaşık 3 dk")
        #expect(RoundText.daily(weak: 0, new: 3) == "3 yeni kelime · yaklaşık 2 dk")
    }
}
