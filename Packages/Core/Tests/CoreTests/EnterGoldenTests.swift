import XCTest
@testable import Core

/// **빈 항목에서 엔터를 치면 어디로 나오나** (141 뒷이야기 · 사용자 · 빌드 43 —
/// *커서가 저 위치에 있다가 글자를 쓰면 다시 처음 위치로 간다*).
///
/// 예전에는 무조건 빈칸 **둘**을 뺐다. 단계의 너비는 부모의 마커에 따라 둘 · 셋 · 넷으로
/// 다르므로, 둘만 빼면 **어느 단계에도 없는 칸**에 선다. 화면은 그 칸을 제 나름대로
/// 그리고, 글자를 치면 단계가 다시 매겨져 자리가 튄다.
///
/// 기댓값은 `Tools/golden/generate.py` 가 계산하고, **나온 결과가 여전히 제대로 된
/// 목록인지**를 심판 둘(markdown-it · cmark-gfm)에게 물어 확인한 것이다.
final class EnterGoldenTests: XCTestCase {

    struct Golden: Decodable {
        struct Action: Decodable {
            let kind: String
            let text: String
            let length: Int?
        }
        struct Case: Decodable {
            let name: String
            let above: [String]
            let line: String
            let shallower: String?
            let action: Action?
        }
        let enterCases: [Case]
    }

    static func load() throws -> Golden {
        let here = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let url = here.appendingPathComponent("Golden/expected.json")
        return try JSONDecoder().decode(Golden.self, from: try Data(contentsOf: url))
    }

    func testMatchesGolden() throws {
        for item in try Self.load().enterCases {
            let made = ListEditing.returnPressed(in: item.line, outdentingTo: item.shallower)
            let where_ = "[\(item.name)] \(item.line)"
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
        for item in try Self.load().enterCases {
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
        for item in try Self.load().enterCases {
            guard let golden = item.action, golden.kind == "replacePrefix",
                  item.shallower != nil else { continue }
            let before = ListEditing.depths(in: item.above + [item.line + "글"]).last ?? 0
            let after = ListEditing.depths(in: item.above + [golden.text + "글"]).last ?? 0
            XCTAssertEqual(after, max(before - 1, 0),
                           "한 번에 한 단계가 아니다 — [\(item.name)] \(before) → \(after)")
        }
    }
}
