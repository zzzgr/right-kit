import XCTest
@testable import RightKitShared

final class ActionLinkTests: XCTestCase {
    func testRoundTripPreservesSelectionAndContainer() throws {
        let context = ActionContext(
            targets: [URL(fileURLWithPath: "/tmp/a b.txt"), URL(fileURLWithPath: "/tmp/正体字.md")],
            container: URL(fileURLWithPath: "/tmp")
        )
        let request = ActionLink.Request(action: .openInEditor, context: context)

        let url = try XCTUnwrap(ActionLink.url(for: request))
        let parsed = try XCTUnwrap(ActionLink.request(from: url))

        XCTAssertEqual(parsed.action, .openInEditor)
        XCTAssertEqual(parsed.context.targets.map(\.path), context.targets.map(\.path))
        XCTAssertEqual(parsed.context.container?.path, "/tmp")
    }

    func testRoundTripWithoutContainer() throws {
        let context = ActionContext(targets: [URL(fileURLWithPath: "/tmp/x")], container: nil)
        let url = try XCTUnwrap(ActionLink.url(for: .init(action: .copyPath, context: context)))

        let parsed = try XCTUnwrap(ActionLink.request(from: url))
        XCTAssertNil(parsed.context.container)
        XCTAssertEqual(parsed.context.targets.map(\.path), ["/tmp/x"])
    }

    func testPathsWithSpacesAndAmpersandsSurviveEncoding() throws {
        let path = "/tmp/weird & name #1/file?.txt"
        let context = ActionContext(targets: [URL(fileURLWithPath: path)], container: nil)
        let url = try XCTUnwrap(ActionLink.url(for: .init(action: .copyPath, context: context)))

        let parsed = try XCTUnwrap(ActionLink.request(from: url))
        XCTAssertEqual(parsed.context.targets.first?.path, path)
    }

    func testRejectsForeignAndMalformedURLs() {
        XCTAssertNil(ActionLink.request(from: URL(string: "https://example.com/run?action=copy.path")!))
        XCTAssertNil(ActionLink.request(from: URL(string: "rightkit://other?action=copy.path")!))
        XCTAssertNil(ActionLink.request(from: URL(string: "rightkit://run")!))
        XCTAssertNil(ActionLink.request(from: URL(string: "rightkit://run?action=does.not.exist")!))
    }
}
