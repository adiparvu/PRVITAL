import XCTest
@testable import Prvital

final class GlucoseSpeakerTests: XCTestCase {

    func testNoReadingSentence() {
        let snapshot = GlucoseSnapshot()  // updatedAt is .distantPast by default
        let sentence = GlucoseSpeaker.sentence(for: snapshot)
        XCTAssertTrue(sentence.lowercased().contains("no glucose"))
    }

    func testFreshSentenceIncludesValueAndTrend() {
        var s = GlucoseSnapshot()
        s.updatedAt = Date()
        s.isStale = false
        s.valueText = "124"
        s.unitText = "mg/dL"
        s.trendLabel = "Stable"
        s.zoneLabel = "In range"
        let sentence = GlucoseSpeaker.sentence(for: s)
        XCTAssertTrue(sentence.contains("124 mg/dL"))
        XCTAssertTrue(sentence.contains("Stable"))
    }

    func testStaleSentenceMentionsLast() {
        var s = GlucoseSnapshot()
        s.updatedAt = Date().addingTimeInterval(-3600)
        s.isStale = true
        s.valueText = "100"
        s.unitText = "mg/dL"
        s.zoneLabel = "In range"
        let sentence = GlucoseSpeaker.sentence(for: s)
        XCTAssertTrue(sentence.lowercased().contains("last"))
    }
}
