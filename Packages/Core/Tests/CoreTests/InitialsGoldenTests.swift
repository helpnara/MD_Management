import XCTest
@testable import Core

/// **제목 초성 찾기** (246). 기댓값은 `Tools/golden/generate.py` 의 `initialsCases` — 글자 이름으로 셈한 파이썬 쌍둥이.
final class InitialsGoldenTests: XCTestCase {

    struct Golden: Decodable {
        struct Initial: Decodable {
            let name: String
            let title: String
            let result: String
        }
        struct Query: Decodable {
            let name: String
            let raw: String
            let result: String?
        }
        struct Match: Decodable {
            let name: String
            let title: String
            let raw: String
            let result: Bool
        }
        struct Cases: Decodable {
            let initials: [Initial]
            let queries: [Query]
            let matches: [Match]
        }
        let initialsCases: Cases
    }

    private func load() throws -> Golden.Cases {
        let here = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let url = here.appendingPathComponent("Golden/expected.json")
        return try JSONDecoder().decode(Golden.self, from: try Data(contentsOf: url)).initialsCases
    }

    func testInitialsMatchGolden() throws {
        let cases = try load().initials
        XCTAssertFalse(cases.isEmpty)
        for c in cases {
            XCTAssertEqual(HangulInitials.initials(of: c.title), c.result, c.name)
        }
    }

    func testQueriesMatchGolden() throws {
        let cases = try load().queries
        XCTAssertFalse(cases.isEmpty)
        for c in cases {
            XCTAssertEqual(HangulInitials.query(c.raw), c.result, c.name)
        }
    }

    func testMatchesMatchGolden() throws {
        let cases = try load().matches
        XCTAssertFalse(cases.isEmpty)
        for c in cases {
            let got = HangulInitials.query(c.raw).map { HangulInitials.matches(title: c.title, query: $0) } ?? false
            XCTAssertEqual(got, c.result, c.name)
        }
    }
}
