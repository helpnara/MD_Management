import XCTest
@testable import Core

/// 179 — **폴더 이름을 바꾸면 그 폴더 안을 가리키던 링크를 새 이름으로.**
///
/// 기댓값은 `Tools/golden/generate.py` 의 `retargetCases` — 같은 규칙을 파이썬으로 따로 적어 계산했고,
/// 거기서 *고친 링크가 새 자리의 같은 파일에 닿는지* 도 먼저 확인했다.
final class RetargetGoldenTests: XCTestCase {

    struct Golden: Decodable {
        struct Case: Decodable {
            let name: String
            let text: String
            let note: String
            let old: String
            let new: String
            let retargeted: String
            let fixed: Int
        }
        let retargetCases: [Case]
    }

    static func load() throws -> Golden {
        let here = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let url = here.appendingPathComponent("Golden/expected.json")
        return try JSONDecoder().decode(Golden.self, from: try Data(contentsOf: url))
    }

    func testMatchesGolden() throws {
        let cases = try Self.load().retargetCases
        XCTAssertFalse(cases.isEmpty, "정답표가 비었다")
        for item in cases {
            let got = MarkdownLinks.retargeted(item.text, notePath: item.note,
                                               fromFolder: item.old, toFolder: item.new)
            XCTAssertEqual(got.text, item.retargeted, "[\(item.name)]")
            XCTAssertEqual(got.fixed, item.fixed, "고친 수 — [\(item.name)]")
        }
    }

    /// **두 번 고쳐도 더 바뀌지 않는다** — 새 이름으로 고친 글을 다시 돌리면 가리킬 옛 폴더가 없다.
    func testSecondPassChangesNothing() throws {
        for item in try Self.load().retargetCases {
            let once = MarkdownLinks.retargeted(item.text, notePath: item.note,
                                                fromFolder: item.old, toFolder: item.new)
            let movedNote = item.note.hasPrefix(item.old + "/")
                ? item.new + String(item.note.dropFirst(item.old.count)) : item.note
            let twice = MarkdownLinks.retargeted(once.text, notePath: movedNote,
                                                 fromFolder: item.old, toFolder: item.new)
            XCTAssertEqual(twice.fixed, 0, "[\(item.name)]")
        }
    }
}
