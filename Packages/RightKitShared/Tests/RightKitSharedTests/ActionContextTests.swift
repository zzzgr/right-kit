import XCTest
@testable import RightKitShared

/// Directory derivation is the part of the domain that silently ruins actions when
/// it is wrong (new file in the parent folder, terminal in the wrong place), so it
/// gets the most coverage.
final class ActionContextTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("rightkit-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func makeDirectory(_ name: String) throws -> URL {
        let url = root.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func makeFile(_ name: String) throws -> URL {
        let url = root.appendingPathComponent(name)
        try Data().write(to: url)
        return url
    }

    func testEmptySelectionFallsBackToTargetedFolder() throws {
        let folder = try makeDirectory("project")
        let context = ActionContext(selection: [], targetedURL: folder)

        XCTAssertEqual(context.targets, [folder])
        XCTAssertEqual(context.workingDirectory, folder)
        XCTAssertEqual(context.creationDirectory, folder)
    }

    func testSelectedFileUsesItsParent() throws {
        let file = try makeFile("notes.txt")
        let context = ActionContext(selection: [file], targetedURL: nil)

        XCTAssertEqual(context.workingDirectory?.standardizedFileURL, root.standardizedFileURL)
        XCTAssertEqual(context.creationDirectory?.standardizedFileURL, root.standardizedFileURL)
    }

    func testSelectedFolderIsUsedAsIs() throws {
        let folder = try makeDirectory("src")
        let context = ActionContext(selection: [folder], targetedURL: nil)

        XCTAssertEqual(context.workingDirectory, folder)
    }

    /// Right-clicking a file inside a folder: Finder reports both. New items belong
    /// in the folder the user is looking at, not next to the selection's own parent.
    func testContainerWinsForCreation() throws {
        let folder = try makeDirectory("assets")
        let file = folder.appendingPathComponent("logo.png")
        try Data().write(to: file)
        let context = ActionContext(selection: [file], targetedURL: folder)

        XCTAssertEqual(context.creationDirectory, folder)
    }

    func testMultiSelectionUsesCommonParent() throws {
        let first = try makeFile("a.txt")
        let second = try makeFile("b.txt")
        let context = ActionContext(selection: [first, second], targetedURL: nil)

        XCTAssertEqual(context.workingDirectory?.standardizedFileURL, root.standardizedFileURL)
    }

    func testMultiSelectionWithoutCommonParentFallsBackToContainer() throws {
        let nested = try makeDirectory("nested")
        let inside = nested.appendingPathComponent("deep.txt")
        try Data().write(to: inside)
        let outside = try makeFile("top.txt")
        let context = ActionContext(selection: [inside, outside], targetedURL: root)

        XCTAssertEqual(context.workingDirectory, root)
    }

    func testEmptyContextHasNoDirectories() {
        let context = ActionContext(selection: [], targetedURL: nil)

        XCTAssertTrue(context.isEmpty)
        XCTAssertNil(context.workingDirectory)
        XCTAssertNil(context.creationDirectory)
    }
}
