import XCTest
@testable import RightKitShared

/// Scratch `UserDefaults` suite for the tests.
///
/// One fixed name, wiped before and after every test, rather than a fresh UUID suite
/// each time: `removePersistentDomain` empties a domain but cfprefsd re-creates the
/// stub plist moments after it is deleted, so unique names quietly pile up 42-byte
/// files in ~/Library/Preferences. A single reused name cannot accumulate.
///
/// Assumes tests in this bundle share one process (`swift test`'s default). Do not
/// enable per-class parallel testing without switching back to unique suites.
private enum TestSuite {
    static let name = "com.rightkit.tests"

    static func wipe() {
        let defaults = UserDefaults(suiteName: name)
        defaults?.removePersistentDomain(forName: name)
        defaults?.synchronize()
    }

    /// Best effort: drop the stub file too. If cfprefsd rewrites it, the next run
    /// reuses the same one.
    static func wipeAndRemoveFile() {
        wipe()
        let plist = URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Library/Preferences/\(name).plist")
        try? FileManager.default.removeItem(at: plist)
    }
}

final class PreferencesTests: XCTestCase {
    private var preferences: Preferences!

    override func setUp() {
        super.setUp()
        TestSuite.wipe()
        preferences = Preferences(suiteName: TestSuite.name)
    }

    override func tearDown() {
        TestSuite.wipeAndRemoveFile()
        super.tearDown()
    }

    func testFreshInstallEnablesEverything() {
        XCTAssertEqual(preferences.enabledActions, MenuAction.allCases)
        MenuAction.allCases.forEach { XCTAssertTrue(preferences.isEnabled($0)) }
    }

    func testOrderIsCanonicalRegardlessOfWriteOrder() {
        preferences.enabledActions = [.copyPath, .newFile, .openInTerminal]

        XCTAssertEqual(preferences.enabledActions, [.openInTerminal, .newFile, .copyPath])
    }

    /// Turning everything off is allowed and must not silently spring back to
    /// "all enabled" — that would make the toggles feel broken.
    func testEmptySelectionIsHonoured() {
        preferences.enabledActions = []

        XCTAssertEqual(preferences.enabledActions, [])
        XCTAssertFalse(preferences.isEnabled(.copyPath))
    }

    func testSetEnabledTogglesWithoutDuplicating() {
        preferences.setEnabled(.newFile, false)
        XCTAssertFalse(preferences.isEnabled(.newFile))

        preferences.setEnabled(.newFile, true)
        preferences.setEnabled(.newFile, true)
        XCTAssertEqual(preferences.enabledActions.filter { $0 == .newFile }.count, 1)
    }

    func testUnknownStoredIDsAreIgnored() {
        UserDefaults(suiteName: TestSuite.name)?
            .set(["open.vscode", "copy.path"], forKey: Preferences.Key.enabledActions)

        XCTAssertEqual(preferences.enabledActions, [.copyPath])
    }

    func testPreferredAppsDefaultToAuto() {
        XCTAssertNil(preferences.preferredTerminal)
        XCTAssertNil(preferences.preferredEditor)
    }

    func testPreferredAppsRoundTripAndClear() {
        preferences.preferredTerminal = .ghostty
        preferences.preferredEditor = .zed
        XCTAssertEqual(preferences.preferredTerminal, .ghostty)
        XCTAssertEqual(preferences.preferredEditor, .zed)

        preferences.preferredTerminal = nil
        preferences.preferredEditor = nil
        XCTAssertNil(preferences.preferredTerminal)
        XCTAssertNil(preferences.preferredEditor)
    }

    func testSetupFlagRoundTrips() {
        XCTAssertFalse(preferences.didCompleteSetup)
        preferences.didCompleteSetup = true
        XCTAssertTrue(preferences.didCompleteSetup)
    }
}

final class ExtensionCheckInTests: XCTestCase {
    private var preferences: Preferences!

    override func setUp() {
        super.setUp()
        TestSuite.wipe()
        preferences = Preferences(suiteName: TestSuite.name)
        ExtensionCheckIn.reset(preferences: preferences)
    }

    override func tearDown() {
        TestSuite.wipeAndRemoveFile()
        super.tearDown()
    }

    func testNothingReportedBeforeTheExtensionRuns() {
        let heartbeat = ExtensionCheckIn.read(preferences: preferences)

        XCTAssertFalse(heartbeat.didReport)
        XCTAssertFalse(heartbeat.didServeMenu)
        XCTAssertFalse(heartbeat.isLive())
    }

    func testLoadIsReportedButIsNotProofTheMenuWorks() {
        ExtensionCheckIn.recordLoad(version: "1.0.0", preferences: preferences)
        let heartbeat = ExtensionCheckIn.read(preferences: preferences)

        XCTAssertTrue(heartbeat.didReport)
        XCTAssertTrue(heartbeat.isLive())
        XCTAssertFalse(heartbeat.didServeMenu)
        XCTAssertEqual(heartbeat.version, "1.0.0")
    }

    func testServingAMenuIsTheVerificationSignal() {
        ExtensionCheckIn.recordMenu(preferences: preferences)
        let heartbeat = ExtensionCheckIn.read(preferences: preferences)

        XCTAssertTrue(heartbeat.didServeMenu)
        XCTAssertTrue(heartbeat.isLive())
    }

    func testVersionIsAlwaysRecordedEvenWhenUnknown() {
        ExtensionCheckIn.recordLoad(version: nil, preferences: preferences)

        // A missing key must not be confusable with "never checked in".
        XCTAssertNotNil(ExtensionCheckIn.read(preferences: preferences).version)
    }

    func testStaleCheckInIsNotLive() {
        let old = Date().addingTimeInterval(-3600)
        let heartbeat = ExtensionHeartbeat(loadedAt: old, lastMenuAt: old, version: nil)

        XCTAssertTrue(heartbeat.didServeMenu)
        XCTAssertFalse(heartbeat.isLive())
    }

    func testResetClearsEvidence() {
        ExtensionCheckIn.recordLoad(version: "1.0.0", preferences: preferences)
        ExtensionCheckIn.recordMenu(preferences: preferences)
        ExtensionCheckIn.reset(preferences: preferences)

        XCTAssertFalse(ExtensionCheckIn.read(preferences: preferences).didReport)
    }
}
