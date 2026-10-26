import XCTest
@testable import Core

/// **글 맨 앞(마커 바로 뒤)에서 지우기** (280, 2026-10-26 번호 점검) — 글자 대신 마커를 뗀다.
/// 겹친 항목이면 한 단계 나온다 — 빈 항목에서 엔터와 같은 셈(`unlist`)이라 그쪽 시험 둘(진짜 단계 · 한 번에 한 단계)을 그대로 둔다.
/// 기댓값은 `Tools/golden/generate.py` 가 계산한다.
final class BackspaceGoldenTests: XCTestCase {

    struct Golden: Decodable {
        struct Action: Decodable {
            let kind: String
            let text: String
            let length: Int?
            let at: Int?
        }
        struct Case: Decodable {
            let name: String
            let above: [String]
            let line: String
            let shallower: String?
            /// 줄 안 커서 자리(UTF-16) — 지우기는 그 앞 한 글자를 지우려는 것이다.
            let caret: Int
            let action: Action?
        }
        let backspaceCases: [Case]
    }

    static func load() throws -> Golden {
        let here = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let url = here.appendingPathComponent("Golden/expected.json")
        return try JSONDecoder().decode(Golden.self, from: try Data(contentsOf: url))
    }

    func testMatchesGolden() throws {
        for item in try Self.load().backspaceCases {
            let made = ListEditing.backspacePressed(in: item.line, caret: item.caret, outdentingTo: item.shallower)
            let where_ = "[\(item.name)] \(item.line) · 커서 \(item.caret)"
            guard let golden = item.action else {
                XCTAssertNil(made, "목록이 아닌데 무언가 했다 — \(where_)")
                continue
            }
            switch golden.kind {
            case "insert":
                XCTAssertEqual(made, .insert(golden.text), "이어 줄 글 — \(where_)")
            case "replacePrefix":
                XCTAssertEqual(made, .replacePrefix(length: golden.length ?? 0, with: golden.text),
                               "앞머리를 바꿀 것 — \(where_)")
            default:
                XCTFail("모르는 동작 \(golden.kind) — \(where_)")
            }
        }
    }

    /// **나온 자리는 진짜 단계다.** 빠져나온 줄을 위 줄들과 붙여 보면, 그 줄의 단계가
    /// 얕은 위 줄과 **같아야** 한다 — 어느 단계에도 없는 칸에 서면 안 된다.
    func testLandsOnARealLevel() throws {
        for item in try Self.load().backspaceCases {
            guard let golden = item.action, golden.kind == "replacePrefix",
                  !golden.text.isEmpty, let shallower = item.shallower else { continue }
            let lines = item.above + [golden.text + "글"]
            let depths = ListEditing.depths(in: lines)
            guard let mine = depths.last,
                  let index = item.above.lastIndex(of: shallower) else { continue }
            XCTAssertEqual(mine, depths[index],
                           "얕은 위 줄과 같은 단계가 아니다 — [\(item.name)] \(golden.text)")
        }
    }

    /// **한 번에 한 단계씩만 나온다.** 세 단계에서 엔터 한 번에 맨 앞까지 튀면 안 된다.
    func testComesOutOneLevelAtATime() throws {
        for item in try Self.load().backspaceCases {
            guard let golden = item.action, golden.kind == "replacePrefix",
                  item.shallower != nil else { continue }
            let before = ListEditing.depths(in: item.above + [item.line + "글"]).last ?? 0
            let after = ListEditing.depths(in: item.above + [golden.text + "글"]).last ?? 0
            XCTAssertEqual(after, max(before - 1, 0),
                           "한 번에 한 단계가 아니다 — [\(item.name)] \(before) → \(after)")
        }
    }
}
