import XCTest
@testable import Prvital

final class AlertSoundsTests: XCTestCase {

    // MARK: Mode → file resolution

    func testSoundModeResolvesToneFile() {
        let setting = AlertSoundSetting(mode: .sound, tone: .chime)
        XCTAssertEqual(setting.resolvedFileName, "prvital-chime.wav")
        XCTAssertFalse(setting.usesSystemDefault)
    }

    func testClassicToneUsesSystemDefault() {
        let setting = AlertSoundSetting(mode: .sound, tone: .classic)
        XCTAssertNil(setting.resolvedFileName)
        XCTAssertTrue(setting.usesSystemDefault)
    }

    func testVibrateOnlyResolvesSilenceClip() {
        let setting = AlertSoundSetting(mode: .vibrateOnly, tone: .alarm)
        XCTAssertEqual(setting.resolvedFileName, AlertSoundSetting.silenceFile)
        XCTAssertFalse(setting.usesSystemDefault)
    }

    func testSilentResolvesToNothing() {
        let setting = AlertSoundSetting(mode: .silent, tone: .alarm)
        XCTAssertNil(setting.resolvedFileName)
        XCTAssertFalse(setting.usesSystemDefault)
    }

    // MARK: Defaults

    func testDefaultsAreLoudWhereItMatters() {
        let prefs = AlertSoundPreferences.default
        XCTAssertEqual(prefs.critical.mode, .sound)
        XCTAssertEqual(prefs.critical.tone, .alarm)
        XCTAssertEqual(prefs.important.tone, .classic)
        XCTAssertEqual(prefs.reminders.tone, .classic)
    }

    /// Every non-classic tone must name a file that actually ships in the app
    /// bundle — a renamed asset would silently downgrade alerts to the default
    /// sound. Skips when the tests aren't hosted in the app (no app bundle to
    /// inspect) instead of failing falsely.
    func testEveryToneFileIsBundled() throws {
        let appBundle = Bundle.allBundles.first { $0.bundleIdentifier == "com.prvital.app" }
        try XCTSkipIf(appBundle == nil, "unit tests not hosted in the app bundle")
        guard let appBundle else { return }

        var files = AlertTone.allCases.compactMap(\.fileName)
        files.append(AlertSoundSetting.silenceFile)
        for fileName in files {
            let base = (fileName as NSString).deletingPathExtension
            let ext = (fileName as NSString).pathExtension
            XCTAssertNotNil(appBundle.url(forResource: base, withExtension: ext),
                            "missing bundled sound \(fileName)")
        }
    }

    // MARK: Persistence round-trip

    func testEncodeDecodeRoundTrip() throws {
        var prefs = AlertSoundPreferences.default
        prefs.critical = AlertSoundSetting(mode: .vibrateOnly, tone: .pulse)
        prefs.important = AlertSoundSetting(mode: .silent, tone: .gentle)
        prefs.reminders = AlertSoundSetting(mode: .sound, tone: .chime)
        let data = try JSONEncoder().encode(prefs)
        let decoded = try JSONDecoder().decode(AlertSoundPreferences.self, from: data)
        XCTAssertEqual(decoded, prefs)
    }

    func testSummaryLabelFollowsMode() {
        XCTAssertEqual(AlertSoundSetting(mode: .sound, tone: .pulse).summaryLabel,
                       AlertTone.pulse.label)
        XCTAssertEqual(AlertSoundSetting(mode: .silent, tone: .pulse).summaryLabel,
                       AlertSoundMode.silent.label)
        XCTAssertEqual(AlertSoundSetting(mode: .vibrateOnly, tone: .pulse).summaryLabel,
                       AlertSoundMode.vibrateOnly.label)
    }
}
