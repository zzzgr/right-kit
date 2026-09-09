import XCTest
@testable import RightKitShared

final class PythonInterpreterTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("RightKitPythonTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: directory)
    }

    func testAutomaticSelectionReusesDedicatedEnvironmentBeforePathPython() throws {
        let dedicated = try executable(".venvs/rightkit/bin/python")
        let system = try executable("system/bin/python3")

        XCTAssertEqual(try resolve(environment: ["PATH": system.deletingLastPathComponent().path]), dedicated.path)
    }

    func testExplicitInterpreterTakesPrecedenceOverBothVirtualEnvironments() throws {
        _ = try executable(".venvs/rightkit/bin/python")
        let virtual = try executable("custom environment/bin/python3")
        let explicit = try executable("selected/bin/python")

        XCTAssertEqual(try resolve(preferredPath: explicit.path, environment: [
            "VIRTUAL_ENV": virtual.deletingLastPathComponent().deletingLastPathComponent().path
        ]), explicit.path)
    }

    func testVirtualEnvironmentTakesPrecedenceOverDedicatedEnvironment() throws {
        _ = try executable(".venvs/rightkit/bin/python")
        let virtual = try executable("custom environment/bin/python3")

        XCTAssertEqual(try resolve(environment: [
            "VIRTUAL_ENV": virtual.deletingLastPathComponent().deletingLastPathComponent().path
        ]), virtual.path)
    }

    func testPathPythonIsUsedWhenDedicatedEnvironmentIsAbsent() throws {
        let python = try executable("system/bin/python3")

        XCTAssertEqual(try resolve(environment: ["PATH": python.deletingLastPathComponent().path]), python.path)
    }

    func testDedicatedInterpreterSymlinkIsPreservedToKeepItsPackages() throws {
        let basePython = try executable("base/bin/python3")
        let dedicated = directory.appendingPathComponent(".venvs/rightkit/bin/python")
        try FileManager.default.createDirectory(at: dedicated.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: dedicated, withDestinationURL: basePython)

        XCTAssertEqual(try resolve(), dedicated.path)
    }

    func testMissingExplicitInterpreterDoesNotSwitchEnvironments() throws {
        _ = try executable(".venvs/rightkit/bin/python")

        XCTAssertThrowsError(try resolve(preferredPath: directory.appendingPathComponent("missing-python").path)) {
            XCTAssertEqual($0 as? CustomActionError, .message(Strings.Custom.missingInterpreter))
        }
    }

    func testAutomaticSelectionSkipsSymlinksToSystemInstallerStub() throws {
        let dedicated = directory.appendingPathComponent(".venvs/rightkit/bin/python")
        try FileManager.default.createDirectory(at: dedicated.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(atPath: dedicated.path, withDestinationPath: "/usr/bin/python3")
        let fallback = try executable("system/bin/python3")

        XCTAssertEqual(try resolve(environment: ["PATH": fallback.deletingLastPathComponent().path]), fallback.path)
    }

    private func resolve(preferredPath: String = "", environment: [String: String] = [:]) throws -> String {
        try PythonInterpreter.resolve(preferredPath: preferredPath, environment: environment, homeDirectory: directory)
    }

    private func executable(_ path: String) throws -> URL {
        let url = directory.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("#!/bin/sh\nexit 0\n".utf8).write(to: url)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
        return url
    }
}
