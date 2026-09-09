import Foundation
import XCTest
@testable import RightKitShared

final class MarketQueryTests: XCTestCase {
    func testDefaultPageSizeAndQueryEncodingPreserveEndpointParameters() throws {
        let origin = URL(string: "https://market.example.com/catalog.json?token=local&page=9&cursor=160&q=old&sort=name")!
        let query = MarketQuery(page: 3, pageSize: 50, search: " 图片 & PDF ", language: "python", ids: ["two", "one", "two"])
        let url = try query.url(for: origin)
        let parameters = Dictionary(uniqueKeysWithValues: URLComponents(url: url, resolvingAgainstBaseURL: false)!.queryItems!.map { ($0.name, $0.value!) })
        XCTAssertEqual(url.path, "/catalog.json")
        XCTAssertEqual(parameters, ["token": "local", "page": "3", "pageSize": "50", "q": "图片 & PDF", "language": "python", "ids": "one,two"])
        XCTAssertEqual(MarketQuery().pageSize, 20)
        XCTAssertEqual(try MarketQuery().url(for: URL(string: "http://127.0.0.1:3000")!).path, "/.well-known/rightkit-market.json")
    }

    func testQueryValidationRejectsInvalidBoundsAndUnboundedUpdateRequests() {
        let url = URL(string: "https://market.example.com")!
        for query in [MarketQuery(page: 0), MarketQuery(page: 1_000_001), MarketQuery(pageSize: 101), MarketQuery(pageSize: 0),
                      MarketQuery(search: String(repeating: "x", count: 201)), MarketQuery(language: "ruby"),
                      MarketQuery(ids: [".."]), MarketQuery(ids: Array(repeating: "item", count: 101))] {
            XCTAssertThrowsError(try query.url(for: url))
        }
    }

    func testPaginationClampsAfterDeletionAndValidatesResponseCardinality() throws {
        let pagination = MarketPagination(total: 43, page: 99)
        XCTAssertEqual(pagination.page, 3)
        XCTAssertEqual(pagination.totalPages, 3)
        XCTAssertNoThrow(try pagination.validate(itemCount: 3))
        XCTAssertThrowsError(try pagination.validate(itemCount: 20))
        XCTAssertNoThrow(try MarketPagination(total: 0).validate(itemCount: 0))
        var corrupt = pagination
        corrupt.totalPages = 7
        XCTAssertThrowsError(try corrupt.validate(itemCount: 3))
        corrupt = pagination; corrupt.pageSize = 0
        XCTAssertThrowsError(try corrupt.validate(itemCount: 3))
    }
}
