import XCTest
@testable import RightKitShared

final class PathUtilitiesTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("rightkit-paths-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    func testFirstNameIsUsedVerbatim() {
        let url = PathUtilities.uniqueURL(in: root, baseName: "未命名.txt", isDirectory: false)

        XCTAssertEqual(url.lastPathComponent, "未命名.txt")
    }

    func testExtensionIsKeptWhenDeduplicating() throws {
        try Data().write(to: root.appendingPathComponent("未命名.txt"))

        let url = PathUtilities.uniqueURL(in: root, baseName: "未命名.txt", isDirectory: false)
        XCTAssertEqual(url.lastPathComponent, "未命名 2.txt")
    }

    func testDeduplicationCountsUp() throws {
        try Data().write(to: root.appendingPathComponent("未命名.txt"))
        try Data().write(to: root.appendingPathComponent("未命名 2.txt"))

        let url = PathUtilities.uniqueURL(in: root, baseName: "未命名.txt", isDirectory: false)
        XCTAssertEqual(url.lastPathComponent, "未命名 3.txt")
    }

    func testFolderNamesAreNotTreatedAsExtensions() throws {
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("my.folder", isDirectory: true),
            withIntermediateDirectories: true
        )

        let url = PathUtilities.uniqueURL(in: root, baseName: "my.folder", isDirectory: true)
        XCTAssertEqual(url.lastPathComponent, "my.folder 2")
    }

    func testDotfilesKeepTheirLeadingDot() {
        let url = PathUtilities.uniqueURL(in: root, baseName: ".gitignore", isDirectory: false)

        XCTAssertEqual(url.lastPathComponent, ".gitignore")
    }

    func testIsDirectory() throws {
        let folder = root.appendingPathComponent("dir", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let file = root.appendingPathComponent("file.txt")
        try Data().write(to: file)

        XCTAssertTrue(PathUtilities.isDirectory(folder))
        XCTAssertFalse(PathUtilities.isDirectory(file))
    }
}

final class RightKitErrorTests: XCTestCase {
    /// A permission failure has a fix (the privacy pane); a generic one does not.
    /// Getting this mapping wrong is what makes an error notification useless.
    func testPermissionErrorsBecomeAccessDeniedWithARoute() {
        let cocoa = NSError(domain: NSCocoaErrorDomain, code: NSFileWriteNoPermissionError)
        let error = RightKitError.fromFileSystem(
            cocoa,
            name: "未命名.txt",
            directory: URL(fileURLWithPath: "/Users/x/Desktop")
        )

        XCTAssertEqual(error, .accessDenied(folderName: "Desktop"))
        XCTAssertEqual(error.recovery, .filesAndFolders)
    }

    func testWrappedPosixDenialIsDetected() {
        let underlying = NSError(domain: NSPOSIXErrorDomain, code: Int(EACCES))
        let cocoa = NSError(
            domain: NSCocoaErrorDomain,
            code: NSFileWriteUnknownError,
            userInfo: [NSUnderlyingErrorKey: underlying]
        )
        let error = RightKitError.fromFileSystem(
            cocoa,
            name: "x",
            directory: URL(fileURLWithPath: "/Volumes/Data")
        )

        XCTAssertEqual(error, .accessDenied(folderName: "Data"))
    }

    func testOtherFailuresStayGenericAndOfferNoFalseFix() {
        let full = NSError(domain: NSCocoaErrorDomain, code: NSFileWriteOutOfSpaceError)
        let error = RightKitError.fromFileSystem(full, name: "x.txt", directory: URL(fileURLWithPath: "/tmp"))

        guard case .createFailed = error else {
            return XCTFail("expected createFailed, got \(error)")
        }
        XCTAssertNil(error.recovery)
    }

    func testMissingAppSendsTheUserToSettings() {
        XCTAssertEqual(RightKitError.appNotFound(kind: .editor).recovery, .appSettings)
        XCTAssertNotNil(RightKitError.appNotFound(kind: .terminal).errorDescription)
    }
}
