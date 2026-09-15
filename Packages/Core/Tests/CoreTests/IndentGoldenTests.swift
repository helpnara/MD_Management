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

            let indented = ListEditing.indent(item.text)
            XCTAssertEqual(indented?.text, item.indented?.text, "탭 — \(where_)")
            XCTAssertEqual(indented?.firstLineDelta, item.indented?.firstLineDelta,
                           "탭 커서 — \(where_)")

            let outdented = ListEditing.outdent(item.text)
            XCTAssertEqual(outdented?.text, item.outdented?.text, "시프트 탭 — \(where_)")
            XCTAssertEqual(outdented?.firstLineDelta, item.outdented?.firstLineDelta,
                           "시프트 탭 커서 — \(where_)")
        }
    }

    /// 들여썼다가 도로 내어쓰면 처음으로 돌아온다.
    func testIndentThenOutdentRoundTrips() throws {
        for item in try Self.load().indentCases {
            guard let indented = ListEditing.indent(item.text) else { continue }
            XCTAssertEqual(ListEditing.outdent(indented.text)?.text, item.text,
                           "되돌아오지 않는다 — [\(item.name)]")
        }
    }
}
