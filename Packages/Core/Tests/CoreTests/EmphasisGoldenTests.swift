import XCTest
@testable import Core

/// 197 — **한글 곁의 강조.** 편집기와 읽기 화면이 같은 규칙으로 굵게 · 기울임 · 취소선을 판정한다.
///
/// 기댓값은 `Tools/golden/generate.py` 의 `emphasisCases` — 같은 규칙을 파이썬으로 적고, 끼운 글을 **cmark-gfm 과
/// markdown-it 둘에** 넣어 강조 수가 같은지 거기서 확인하고 왔다. 편집기 쪽은 `styleCases` 의 한글 곁 사례가 본다.
final class EmphasisGoldenTests: XCTestCase {

    struct Golden: Decodable {
        struct Case: Decodable {
            let name: String
            let text: String
            let prepared: String
            let strong: Int
            let em: Int
            let del: Int
        }
        let emphasisCases: [Case]
    }

    static func load() throws -> Golden {
        let here = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let url = here.appendingPathComponent("Golden/expected.json")
        return try JSONDecoder().decode(Golden.self, from: try Data(contentsOf: url))
    }

    func testPreparedTextMatchesGolden() throws {
        let cases = try Self.load().emphasisCases
        XCTAssertFalse(cases.isEmpty, "정답표가 비었다")
        for item in cases {
            XCTAssertEqual(Emphasis.cjkFriendly(item.text), item.prepared, "[\(item.name)]")
        }
    }

    /// **읽기 화면이 실제로 굵게 그린다** — 앱의 파서(swift-markdown)가 파이썬의 cmark-gfm 과 같은 수를 내야 한다.
    /// 끼운 `⸱` 는 HTML 에 남지 않는다.
    func testReaderDrawsTheSameEmphasis() throws {
        for item in try Self.load().emphasisCases {
            let html = MarkdownHTML.render(markdown: item.text, notePath: "노트.md", existing: []).bodyHTML
            XCTAssertEqual(html.components(separatedBy: "<strong>").count - 1, item.strong, "굵게 — [\(item.name)] \(html)")
            XCTAssertEqual(html.components(separatedBy: "<em>").count - 1, item.em, "기울임 — [\(item.name)] \(html)")
            XCTAssertEqual(html.components(separatedBy: "<del>").count - 1
                           + html.components(separatedBy: "<s>").count - 1, item.del, "취소선 — [\(item.name)] \(html)")
            XCTAssertFalse(html.contains("\u{2E31}"), "⸱ 가 남았다 — [\(item.name)]")
        }
    }

    /// 글에 이미 `⸱` 가 있으면 **아무것도 안 끼운다** — 뺄 때 사용자의 글자까지 빠지지 않게.
    func testTextWithSentinelIsLeftAlone() {
        let text = "가⸱나 **(괄호)**는"
        XCTAssertEqual(Emphasis.cjkFriendly(text), text)
    }

    /// 주소 안에 끼어도 첨부를 찾는다 — `자료~(최종).png` 처럼 `~` 가 한글과 괄호 사이에 있는 파일명.
    func testAttachmentPathSurvivesTheSentinel() {
        let text = "![](assets/자료~(최종).png)"
        XCTAssertNotEqual(Emphasis.cjkFriendly(text), text, "이 사례는 ⸱ 가 끼는 자리여야 시험이 된다")
        let rendered = MarkdownHTML.render(markdown: text, notePath: "노트.md", existing: ["assets/자료~(최종).png"])
        XCTAssertTrue(rendered.missingAttachments.isEmpty, "\(rendered.missingAttachments)")
    }
}
