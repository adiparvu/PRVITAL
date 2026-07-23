import XCTest
@testable import Prvital

final class LearnProgressTests: XCTestCase {

    func testEmptyProgressIsZero() {
        let p = LearnProgress()
        XCTAssertEqual(p.readCount(among: ["a", "b", "c"]), 0)
        XCTAssertEqual(p.fraction(among: ["a", "b", "c"]), 0)
        XCTAssertFalse(p.isRead("a"))
    }

    func testMarkReadCountsAndIsIdempotent() {
        var p = LearnProgress()
        p.markRead("a")
        p.markRead("a") // second time changes nothing
        p.markRead("b")
        XCTAssertTrue(p.isRead("a"))
        XCTAssertEqual(p.readCount(among: ["a", "b", "c"]), 2)
        XCTAssertEqual(p.fraction(among: ["a", "b", "c"]), 2.0 / 3.0, accuracy: 1e-9)
    }

    func testStaleIDsNeverInflateProgress() {
        // "x" was read but is no longer in the library — it must not count.
        let p = LearnProgress(readIDs: ["a", "b", "x", "y"])
        XCTAssertEqual(p.readCount(among: ["a", "b", "c"]), 2)
        XCTAssertLessThanOrEqual(p.fraction(among: ["a", "b", "c"]), 1)
    }

    func testFractionOfEmptyLibraryIsZero() {
        let p = LearnProgress(readIDs: ["a"])
        XCTAssertEqual(p.fraction(among: []), 0)
        XCTAssertEqual(p.readCount(among: []), 0)
    }

    func testEncodeDecodeRoundTrips() {
        var p = LearnProgress()
        p.markRead("hypoglycemia")
        p.markRead("carb-counting")
        p.markRead("cgm-basics")
        let restored = LearnProgress.decode(p.encoded())
        XCTAssertEqual(restored, p)
        XCTAssertEqual(restored.readIDs, p.readIDs)
    }

    func testDecodeIgnoresEmptyStringAndBlanks() {
        XCTAssertEqual(LearnProgress.decode("").readIDs, [])
        XCTAssertEqual(LearnProgress.decode("\t\t").readIDs, [])
        XCTAssertEqual(LearnProgress.decode("a\t\tb").readIDs, ["a", "b"])
    }

    func testEncodedOutputIsOrderIndependent() {
        let a = LearnProgress(readIDs: ["z", "a", "m"])
        let b = LearnProgress(readIDs: ["m", "z", "a"])
        XCTAssertEqual(a.encoded(), b.encoded(), "same set → same stored string regardless of insertion order")
    }

    func testFirstUnreadFollowsReadingOrder() {
        let ids = ["a", "b", "c", "d"]
        var p = LearnProgress()
        XCTAssertEqual(p.firstUnread(among: ids), "a") // nothing read → the very first
        p.markRead("a")
        p.markRead("b")
        XCTAssertEqual(p.firstUnread(among: ids), "c") // skips read ones, keeps order
    }

    func testFirstUnreadIsNilWhenComplete() {
        let ids = ["a", "b"]
        let p = LearnProgress(readIDs: ["a", "b"])
        XCTAssertNil(p.firstUnread(among: ids))
        XCTAssertTrue(p.isComplete(among: ids))
    }

    func testEmptyLibraryIsNeitherUnreadNorComplete() {
        let p = LearnProgress(readIDs: ["a"])
        XCTAssertNil(p.firstUnread(among: []))
        XCTAssertFalse(p.isComplete(among: []), "an empty library is not 'complete'")
    }
}
