import XCTest
@testable import Core

/// 탭 · 시프트 탭이 고른 줄들에 하는 일 (빌드 29 · 1번).
///
/// 기댓값은 `Tools/golden/generate.py` 가 **같은 규칙을 파이썬으로 다시 구현해**
/// 계산한다 — `Paths` · `ShareBundle` 과 같은 방식이다. 손으로 적으면 옮겨 적은
/// 실수를 테스트가 그대로 승인한다.
final class IndentGoldenTests: XCTestCase {

    struct Golden: Decodable {
        struct Shift: Decodable {
            let text: String
            let firstLineDelta: Int
        }
        struct Case: Decodable {
            let name: String
            let text: String
            /// 바로 위 줄 (139). 들여쓰기가 여기 글이 시작하는 칸까지 간다.
            let under: String?
            /// 더 얕은 위 줄 (139). 내어쓰기가 여기까지 나온다.
            let shallower: String?
            let indented: Shift?
            let outdented: Shift?
        }
        let indentCases: [Case]
    }

    static func load() throws -> Golden {
        let here = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let url = here.appendingPathComponent("Golden/expected.json")
        return try JSONDecoder().decode(Golden.self, from: try Data(contentsOf: url))
    }

    func testMatchesGolden() throws {
        for item in try Self.load().indentCases {
            let where_ = "[\(item.name)] \(item.text)"

            let indented = ListEditing.indent(item.text, under: item.under)
            XCTAssertEqual(indented?.text, item.indented?.text, "탭 — \(where_)")
            XCTAssertEqual(indented?.firstLineDelta, item.indented?.firstLineDelta,
                           "탭 커서 — \(where_)")

            let outdented = ListEditing.outdent(item.text, to: item.shallower)
            XCTAssertEqual(outdented?.text, item.outdented?.text, "시프트 탭 — \(where_)")
            XCTAssertEqual(outdented?.firstLineDelta, item.outdented?.firstLineDelta,
                           "시프트 탭 커서 — \(where_)")
        }
    }

    /// 들여썼다가 도로 내어쓰면 처음으로 돌아온다.
    ///
    /// **위 줄을 같이 준다** (139) — 들여쓰기는 부모의 글이 시작하는 칸까지 가고,
    /// 내어쓰기는 그 부모의 들여쓰기까지 나온다. 같은 문맥을 줘야 제자리로 돌아온다.
    func testIndentThenOutdentRoundTrips() throws {
        for item in try Self.load().indentCases {
            guard let indented = ListEditing.indent(item.text, under: item.under) else { continue }
            let back = ListEditing.outdent(indented.text, to: item.under ?? item.shallower)
            XCTAssertEqual(back?.text, item.text, "되돌아오지 않는다 — [\(item.name)]")
        }
    }
}
