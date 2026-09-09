import CoreGraphics
import ImageIO
import XCTest
@testable import RightKitShared

final class ActionPackageUpdateTests: XCTestCase {
    private func baseline(environment: [ScriptEnvironmentVariable] = []) throws -> ActionPackage {
        var action = CustomAction()
        action.title = "Example"
        action.script = "exit 0"
        action.environment = environment
        return try ActionPackageExporter.make(from: action, packageID: "example")
    }

    private func installed(_ package: ActionPackage, icon: CustomActionIcon? = nil) throws -> CustomAction {
        var action = try package.makeCustomAction(icon: icon)
        action.packageMetadata = .init(id: package.id, version: package.version, source: .market,
                                      marketURL: URL(string: "https://market.example.com"))
        action.packageMetadata?.baseline = package
        return action
    }

    private func png(gray: CGFloat) throws -> Data {
        let context = try XCTUnwrap(CGContext(data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                              space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(gray: gray, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: 1, height: 1))
        let image = try XCTUnwrap(context.makeImage())
        let data = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(data, "public.png" as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return data as Data
    }

    func testPublisherIconUpdatesUnlessItConflictsWithACustomLocalIcon() throws {
        let originalPNG = try png(gray: 0)
        var original = try baseline()
        original.action.icon = .png(originalPNG)
        let local = try installed(original, icon: .image("installed.png"))
        var remote = original
        remote.version = "1.1.0"
        remote.action.icon = .png(try png(gray: 1))
        let incoming = try remote.makeCustomAction(icon: .image("updated.png"))
        XCTAssertEqual(ActionPackageUpdate.merge(incoming, with: local, package: remote, preferLocal: true,
                                                localIconData: originalPNG).icon, incoming.icon)

        let customPNG = try png(gray: 0.5)
        XCTAssertEqual(ActionPackageUpdate.merge(incoming, with: local, package: remote, preferLocal: true,
                                                localIconData: customPNG).icon, local.icon)
        XCTAssertEqual(ActionPackageUpdate.merge(incoming, with: local, package: remote, preferLocal: false,
                                                localIconData: customPNG).icon, incoming.icon)
        let unchanged = try original.makeCustomAction(icon: .image("unchanged.png"))
        XCTAssertEqual(ActionPackageUpdate.merge(unchanged, with: local, package: original, preferLocal: false,
                                                localIconData: customPNG).icon, local.icon)
    }

    func testUnrelatedReleasePreservesLocalVariableAdditionsAndDeletions() throws {
        let original = try baseline(environment: [
            .init(name: "OUTPUT", value: "default"),
            .init(name: "OLD_DEFAULT", value: "unused"),
            .init(name: "LOCALLY_REMOVED", value: "unused")
        ])
        var local = try installed(original)
        local.environment.removeAll { $0.name == "LOCALLY_REMOVED" }
        let localPath = ScriptEnvironmentVariable(name: "VIRTUAL_ENV", value: "/local/venv")
        local.environment.append(localPath)
        var remote = original
        remote.version = "1.1.0"
        remote.action.environment.removeAll { $0.name == "OLD_DEFAULT" }
        remote.action.environment[0].value = "new-default"
        remote.action.environment.append(.init(name: "NEW_DEFAULT", isSecret: false, value: "new"))
        let incoming = try remote.makeCustomAction()

        for preferLocal in [true, false] {
            let merged = ActionPackageUpdate.merge(incoming, with: local, package: remote, preferLocal: preferLocal)
            XCTAssertEqual(merged.environment.map(\.name), ["OUTPUT", "NEW_DEFAULT", "VIRTUAL_ENV"])
            XCTAssertEqual(merged.environment[0].value, "new-default")
            XCTAssertEqual(merged.environment[0].id, local.environment[0].id)
            XCTAssertEqual(merged.environment.last, localPath)
        }
    }

    func testConflictingVariableDeletionUsesTheSelectedPreference() throws {
        let original = try baseline(environment: [.init(name: "OUTPUT", value: "default")])
        var local = try installed(original)
        local.environment[0].value = "local-output"
        var remote = original
        remote.action.environment = []
        var incoming = try remote.makeCustomAction()
        XCTAssertEqual(ActionPackageUpdate.merge(incoming, with: local, package: remote, preferLocal: true).environment,
                       local.environment)
        XCTAssertTrue(ActionPackageUpdate.merge(incoming, with: local, package: remote, preferLocal: false).environment.isEmpty)

        local.environment = []
        remote.action.environment = [.init(name: "OUTPUT", isSecret: false, value: "remote-output")]
        incoming = try remote.makeCustomAction()
        XCTAssertTrue(ActionPackageUpdate.merge(incoming, with: local, package: remote, preferLocal: true).environment.isEmpty)
        XCTAssertEqual(ActionPackageUpdate.merge(incoming, with: local, package: remote, preferLocal: false).environment,
                       incoming.environment)
    }

    func testChangingSecretTypeDoesNotReuseItsKeychainReference() throws {
        let original = try baseline(environment: [.init(name: "TOKEN", isSecret: true)])
        let local = try installed(original)
        var remote = original
        remote.action.environment = [.init(name: "TOKEN", isSecret: false, value: "public-default")]
        let incoming = try remote.makeCustomAction()
        let merged = ActionPackageUpdate.merge(incoming, with: local, package: remote, preferLocal: true)
        XCTAssertFalse(merged.environment[0].isSecret)
        XCTAssertEqual(merged.environment[0].value, "public-default")
        XCTAssertNotEqual(merged.environment[0].id, local.environment[0].id)

        let publicOriginal = try baseline(environment: [.init(name: "TOKEN", value: "public-default")])
        var locallySecret = try installed(publicOriginal)
        locallySecret.environment[0].isSecret = true
        locallySecret.environment[0].value = ""
        let unchanged = try publicOriginal.makeCustomAction()
        XCTAssertEqual(ActionPackageUpdate.merge(unchanged, with: locallySecret, package: publicOriginal,
                                                preferLocal: false).environment, locallySecret.environment)
    }
}
