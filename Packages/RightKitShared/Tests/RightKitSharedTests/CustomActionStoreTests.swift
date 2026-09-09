import XCTest
@testable import RightKitShared

final class CustomActionStoreTests: XCTestCase {
    private var directory: URL!
    private var store: CustomActionStore!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        store = CustomActionStore(directory: directory)
        try store.prepare()
    }

    override func tearDownWithError() throws { try FileManager.default.removeItem(at: directory) }

    private func makeAction() -> CustomAction {
        var action = CustomAction()
        action.title = "Test Action"
        action.script = "exit 0"
        return action
    }

    func testRoundTripKeepsOrderAndFinderProjectionOmitsExecutionDetails() throws {
        var first = makeAction()
        first.group = "Tools"
        var second = makeAction()
        second.language = .python
        second.script = "print('test')"
        second.isEnabled = false
        try store.save([second, first])
        XCTAssertEqual(try store.load(), [second, first])
        XCTAssertEqual(try store.loadMenu(), [second.menuItem, first.menuItem])
        let permissions = try FileManager.default.attributesOfItem(atPath: store.catalogURL.path)[.posixPermissions] as? NSNumber
        XCTAssertEqual(permissions?.intValue, 0o600)
    }

    func testSavingSecretsCannotLeakThemToTheSharedCatalog() throws {
        var action = makeAction()
        action.environment = [ScriptEnvironmentVariable(name: "TOKEN", value: "catalog-must-not-contain-me", isSecret: true)]
        try store.save([action])
        XCTAssertFalse(try String(contentsOf: store.catalogURL).contains("catalog-must-not-contain-me"))
        XCTAssertEqual(try store.load().first?.environment.first?.value, "")
    }

    func testDuplicateIDsAndUnsafeIconPathsAreRejectedWithoutChangingSavedData() throws {
        var action = makeAction()
        try store.save([action])
        let original = try Data(contentsOf: store.catalogURL)
        XCTAssertThrowsError(try store.save([action, action]))
        action.icon = .image("../../secret.png")
        XCTAssertNil(store.iconURL(named: "../../secret.png"))
        XCTAssertThrowsError(try store.save([action]))
        XCTAssertEqual(try Data(contentsOf: store.catalogURL), original)
    }

    func testCorruptAndFutureCatalogsArePreservedOnReadFailure() throws {
        for data in [Data("broken-json".utf8), Data(#"{"version":900,"actions":[]}"#.utf8)] {
            try data.write(to: store.catalogURL)
            XCTAssertThrowsError(try store.load())
            XCTAssertThrowsError(try store.loadMenu())
            XCTAssertEqual(try Data(contentsOf: store.catalogURL), data)
        }
    }

    func testCacheRefreshesAfterAtomicSaveAndDeletion() throws {
        let cache = CustomMenuCache()
        var action = makeAction()
        try store.save([action])
        XCTAssertEqual(try cache.load(from: store).first?.title, action.title)
        action.title = "Changed"
        try store.save([action])
        XCTAssertEqual(try cache.load(from: store).first?.title, "Changed")
        try FileManager.default.removeItem(at: store.catalogURL)
        XCTAssertEqual(try cache.load(from: store), [])
    }
}
