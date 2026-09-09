import XCTest
@testable import RightKitShared

final class CustomActionTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws { try FileManager.default.removeItem(at: directory) }

    private func file(_ name: String) throws -> URL {
        let url = directory.appendingPathComponent(name)
        try Data().write(to: url)
        return url
    }

    private func makeAction() -> CustomAction {
        var action = CustomAction()
        action.title = "Test Action"
        action.script = "exit 0"
        return action
    }

    func testExtensionRulesNormalizeCaseAndRequireEverySelectedItem() throws {
        var rules = ActionInputRules()
        rules.target = .files
        rules.fileType = .extensions
        rules.extensions = "*.JPG, .png；webp\n jpg"
        XCTAssertEqual(rules.normalizedExtensions, ["jpg", "png", "webp"])
        let jpeg = try file("photo.JPG")
        let png = try file("photo.png")
        let text = try file("readme.txt")
        XCTAssertTrue(rules.matches(ActionContext(targets: [jpeg, png], container: directory)))
        XCTAssertFalse(rules.matches(ActionContext(targets: [jpeg, text], container: directory)))
        XCTAssertFalse(rules.matches(ActionContext(targets: [], container: directory)))
    }

    func testFoldersAreNotClassifiedAsImagesByTheirNames() throws {
        let folder = directory.appendingPathComponent("folder.jpg", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let image = try file("photo.HEIC")
        var rules = ActionInputRules()
        rules.target = .files
        rules.fileType = .images
        XCTAssertFalse(rules.matches(ActionContext(targets: [folder], container: directory)))
        XCTAssertTrue(rules.matches(ActionContext(targets: [image], container: directory)))
        rules.target = .both
        XCTAssertTrue(rules.matches(ActionContext(targets: [image, folder], container: directory)))
        rules.target = .folders
        XCTAssertFalse(rules.matches(ActionContext(targets: [image, folder], container: directory)))
    }

    func testSingleAndMultipleSelectionRules() throws {
        let one = try file("one")
        let two = try file("two")
        var rules = ActionInputRules()
        rules.selection = .single
        XCTAssertTrue(rules.matches(ActionContext(targets: [one], container: nil)))
        XCTAssertFalse(rules.matches(ActionContext(targets: [one, two], container: nil)))
        rules.selection = .multiple
        XCTAssertFalse(rules.matches(ActionContext(targets: [one], container: nil)))
        XCTAssertTrue(rules.matches(ActionContext(targets: [one, two], container: nil)))
    }

    func testSecretValuesAreNeverEncodedAndInjectedValuesAreIgnoredOnDecode() throws {
        let secret = ScriptEnvironmentVariable(name: "TOKEN", value: "private-test-value", isSecret: true)
        let encoded = try JSONEncoder().encode(secret)
        XCTAssertFalse(String(decoding: encoded, as: UTF8.self).contains("private-test-value"))
        XCTAssertEqual(try JSONDecoder().decode(ScriptEnvironmentVariable.self, from: encoded).value, "")
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        json["value"] = "injected-value"
        let modified = try JSONSerialization.data(withJSONObject: json)
        XCTAssertEqual(try JSONDecoder().decode(ScriptEnvironmentVariable.self, from: modified).value, "")
    }

    func testReservedDuplicateAndInvalidEnvironmentNamesAreRejected() throws {
        for names in [["RIGHTKIT_CONTEXT_FILE"], ["9TOKEN"], ["A=B"], ["TOKEN", "TOKEN"]] {
            var action = makeAction()
            action.environment = names.map { ScriptEnvironmentVariable(name: $0, value: "test") }
            XCTAssertThrowsError(try action.validate(), names.joined(separator: ","))
        }
        var action = makeAction()
        action.environment = [ScriptEnvironmentVariable(name: "TOKEN", value: "a\0b")]
        XCTAssertThrowsError(try action.validate())
    }

    func testDisabledEmptyDraftCanBeSavedButCannotBeExecuted() throws {
        var action = CustomAction()
        action.title = "Later"
        action.isEnabled = false
        XCTAssertNoThrow(try action.validate())
        XCTAssertThrowsError(try action.validate(forExecution: true))
    }

    func testFolderOnlyRuleIgnoresUnusedExtensionFilter() throws {
        var action = makeAction()
        action.rules.target = .folders
        action.rules.fileType = .extensions
        XCTAssertNoThrow(try action.validate())
    }
}
