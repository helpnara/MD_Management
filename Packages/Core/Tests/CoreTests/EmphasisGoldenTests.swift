import XCTest
@testable import Core

/// 197 — **강조를 여닫는 자리.** 편집기와 읽기 화면이 굵게 · 기울임 · 취소선을 **같은 규칙(CommonMark)**으로 판정한다.
///
/// 기댓값은 `Tools/golden/generate.py` 의 `emphasisCases` — 글을 **cmark-gfm 과 markdown-it 둘에** 넣어 강조 수가
/// 같은지 거기서 확인하고 왔다. 여기서는 앱의 두 자리가 둘 다 그 수를 내는지 본다 — 읽기(`MarkdownHTML`, swift-markdown)
/// 와 편집기(`LineStyler`).
final class EmphasisGoldenTests: XCTestCase {

    struct Golden: Decodable {
        struct Case: Decodable {
            let name: String
            let text: String
            let strong: Int
            let em: Int
            let del: Int
        }
        let emphasisCases: [Case]
    }

    static func load() throws -> [Golden.Case] {
        let here = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let url = here.appendingPathComponent("Golden/expected.json")
        return try JSONDecoder().decode(Golden.self, from: try Data(contentsOf: url)).emphasisCases
    }

    func testReaderDrawsTheSameEmphasis() throws {
        let cases = try Self.load()
        XCTAssertFalse(cases.isEmpty, "정답표가 비었다")
        for item in cases {
            let html = MarkdownHTML.render(markdown: item.text, notePath: "노트.md", existing: []).bodyHTML
            XCTAssertEqual(html.components(separatedBy: "<strong>").count - 1, item.strong, "굵게 — [\(item.name)] \(html)")
            XCTAssertEqual(html.components(separatedBy: "<em>").count - 1, item.em, "기울임 — [\(item.name)] \(html)")
            XCTAssertEqual(html.components(separatedBy: "<del>").count - 1
                           + html.components(separatedBy: "<s>").count - 1, item.del, "취소선 — [\(item.name)] \(html)")
        }
    }

    /// **편집기도 같은 수를 칠한다** — 읽기 화면에서 `**` 가 글자로 남는 글은 편집기에서도 굵게 안 칠한다.
    func testEditorPaintsTheSameEmphasis() throws {
        for item in try Self.load() {
            let spans = LineStyler.style(paragraph: item.text).inlineSpans
            XCTAssertEqual(spans.filter { $0.token == .strong }.count, item.strong, "굵게 — [\(item.name)]")
            XCTAssertEqual(spans.filter { $0.token == .emphasis }.count, item.em, "기울임 — [\(item.name)]")
            XCTAssertEqual(spans.filter { $0.token == .strikethrough }.count, item.del, "취소선 — [\(item.name)]")
        }
    }
}
