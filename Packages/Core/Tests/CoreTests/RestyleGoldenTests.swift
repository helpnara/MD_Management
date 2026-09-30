import XCTest
@testable import Core

/// 193 — **목록 모양 바꾸기** (번호 · 글머리표 · 체크상자 · 없음).
///
/// 기댓값은 `Tools/golden/generate.py` 의 `restyleCases` — 같은 규칙을 파이썬으로 적고, 목록 줄끼리 바꾼
/// 사례는 **파서가 세는 단계가 그대로인지** 거기서 확인하고 왔다.
final class RestyleGoldenTests: XCTestCase {

    struct Golden: Decodable {
        struct Case: Decodable {
            let name: String
            let lines: [String]
            let first: Int
            let count: Int
            let to: String
            let resolved: String
            let restyled: [String]
        }
        let restyleCases: [Case]
    }

    static func load() throws -> Golden {
        let here = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let url = here.appendingPathComponent("Golden/expected.json")
        return try JSONDecoder().decode(Golden.self, from: try Data(contentsOf: url))
    }

    func testMatchesGolden() throws {
        let cases = try Self.load().restyleCases
        XCTAssertFalse(cases.isEmpty, "정답표가 비었다")
        for item in cases {
            let marker = try XCTUnwrap(ListMarker(rawValue: item.resolved), "[\(item.name)]")
            if item.to == "toggle" {
                XCTAssertEqual(ListEditing.toggleTarget(item.lines[item.first]), marker, "단추 한 번 — [\(item.name)]")
            }
            XCTAssertEqual(ListEditing.restyle(lines: item.lines, first: item.first, count: item.count, to: marker),
                           item.restyled, "[\(item.name)]")
        }
    }

    /// **두 번 바꾸면 한 번 바꾼 것과 같다** — 누른 단추를 또 눌러도 글이 더 흔들리지 않는다.
    func testRestylingTwiceChangesNothingMore() throws {
        for item in try Self.load().restyleCases {
            guard let marker = ListMarker(rawValue: item.resolved) else { continue }
            let again = ListEditing.restyle(lines: item.restyled, first: item.first, count: item.count, to: marker)
            XCTAssertEqual(again, item.restyled, "[\(item.name)]")
        }
    }
}
