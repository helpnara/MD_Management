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

    /// 들여썼다가 **왔던 칸으로** 도로 내어쓰면 처음으로 돌아온다.
    ///
    /// 내어쓰기는 *한 단계*가 아니라 **얕은 위 줄의 칸까지** 나온다 (139). 그래서
    /// 되돌아오는지 보려면 *왔던 칸*을 알려 줘야 한다 — 그것이 곧 **들여쓰기 전의 첫 줄**이다.
    ///
    /// **처음에는 사례의 부모 줄을 그대로 넘겼다가 두 곳에서 깨졌다** — 이미 들여쓴 채로
    /// 시작하는 블록(`  - 둘째`)은 그 칸에 부모가 없어서, 내어쓰면 맨 앞까지 나오는 것이
    /// 맞다. 깨진 것은 코드가 아니라 이 시험이 고른 문맥이었다.
    func testIndentThenOutdentRoundTrips() throws {
        for item in try Self.load().indentCases {
            guard let indented = ListEditing.indent(item.text, under: item.under) else { continue }
            let cameFrom = item.text.components(separatedBy: "\n")
                .first { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            let back = ListEditing.outdent(indented.text, to: cameFrom)
            XCTAssertEqual(back?.text, item.text, "되돌아오지 않는다 — [\(item.name)]")
        }
    }

    /// **부모의 글칸에서 멈춘다 — 한 번 더 눌러도 안 깊어진다** (141).
    ///
    /// 139 에서는 누를 때마다 마커폭만큼 더 들어갔다. 부모 글칸보다 네 칸을 넘기면
    /// 마크다운은 그 줄을 목록이 아니라 **앞 문단에 딸린 글**로 읽는다 — 사용자 화면에
    /// `공유 1. 테스트 2. 테스트` 한 줄로 나온 자리다.
    func testSecondPressDoesNothing() throws {
        for item in try Self.load().indentCases {
            guard let parent = item.under,
                  let once = ListEditing.indent(item.text, under: parent) else { continue }
            XCTAssertNil(ListEditing.indent(once.text, under: parent),
                         "한 번 더 눌렀더니 또 들어갔다 — [\(item.name)] \(once.text)")
        }
    }

    /// **들여쓴 줄은 부모보다 딱 한 단계 깊다.** 두 단계를 뛰면 파일이 무너진다.
    func testIndentGoesExactlyOneLevelDeeper() throws {
        for item in try Self.load().indentCases {
            guard let parent = item.under, ListEditing.isItem(parent),
                  let once = ListEditing.indent(item.text, under: parent) else { continue }
            let lines = [parent] + once.text.components(separatedBy: "\n")
            let depths = ListEditing.depths(in: lines)
            guard let parentDepth = depths.first, depths.count > 1 else { continue }
            for (line, depth) in zip(lines, depths).dropFirst() where ListEditing.isItem(line) {
                XCTAssertEqual(depth, parentDepth + 1,
                               "부모보다 한 단계가 아니다 — [\(item.name)] \(line)")
            }
        }
    }
}
