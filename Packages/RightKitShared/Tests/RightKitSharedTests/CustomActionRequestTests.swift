import XCTest
@testable import RightKitShared

final class CustomActionRequestTests: XCTestCase {
    private var directory: URL!
    private var store: CustomActionStore!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        store = CustomActionStore(directory: directory)
        try store.prepare()
    }

    override func tearDownWithError() throws { try FileManager.default.removeItem(at: directory) }

    private func request(at date: Date = Date()) -> CustomActionRequest {
        CustomActionRequest(actionID: UUID(), context: ActionContext(
            targets: [directory.appendingPathComponent("中文 & ' file.txt")], container: directory
        ), createdAt: date)
    }

    func testTicketRoundTripPreservesContextAndCannotBeReplayed() throws {
        let request = request()
        let url = try CustomActionRequest.enqueue(request, in: store)
        XCTAssertFalse(url.absoluteString.contains(request.targets[0].lastPathComponent))
        XCTAssertFalse(url.absoluteString.contains(request.actionID.uuidString))
        XCTAssertEqual(try CustomActionRequest.consume(url, from: store), request)
        XCTAssertThrowsError(try CustomActionRequest.consume(url, from: store))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: store.requestsDirectory.path), [])
    }

    func testBareForgedAndAmbiguousURLsCannotStartAnAction() throws {
        let url = try CustomActionRequest.enqueue(request(), in: store)
        for value in [
            "rightkit://custom?action=upload&target=/tmp/file", "rightkit://custom?ticket=../actions",
            "rightkit://custom?ticket=\(UUID().uuidString)", url.absoluteString + "&ticket=\(UUID().uuidString)",
            url.absoluteString + "#fragment", url.absoluteString.replacingOccurrences(of: "rightkit:", with: "https:")
        ] {
            XCTAssertThrowsError(try CustomActionRequest.consume(try XCTUnwrap(URL(string: value)), from: store))
        }
        XCTAssertNoThrow(try CustomActionRequest.consume(url, from: store))
    }

    func testExpiredAndFutureRequestsAreConsumedWithoutExecution() throws {
        for date in [Date().addingTimeInterval(-121), Date().addingTimeInterval(10)] {
            let url = try CustomActionRequest.enqueue(request(at: date), in: store)
            XCTAssertThrowsError(try CustomActionRequest.consume(url, from: store))
            XCTAssertThrowsError(try CustomActionRequest.consume(url, from: store))
        }
    }

    func testNonFileSelectionCannotBeEnqueued() throws {
        let context = ActionContext(targets: [try XCTUnwrap(URL(string: "https://example.com/file"))], container: nil)
        XCTAssertThrowsError(try CustomActionRequest.enqueue(CustomActionRequest(actionID: UUID(), context: context), in: store))
    }

    func testSymlinkTicketIsRejectedAndItsTargetIsPreserved() throws {
        let data = try JSONEncoder().encode(request())
        let target = directory.appendingPathComponent("outside.json")
        try data.write(to: target)
        let token = UUID().uuidString
        let link = store.requestsDirectory.appendingPathComponent(token + ".json")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
        let url = try XCTUnwrap(URL(string: "rightkit://custom?ticket=\(token)"))
        XCTAssertThrowsError(try CustomActionRequest.consume(url, from: store))
        XCTAssertEqual(try Data(contentsOf: target), data)
    }
}
