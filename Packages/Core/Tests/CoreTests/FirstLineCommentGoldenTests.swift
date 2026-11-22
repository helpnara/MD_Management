import XCTest
@testable import Core

/// 326 · 327 — **제목 앞의 HTML 주석** (2026-11-22 사용자 — 머리말 뒤 `<!-- 방향 …` 22줄이 읽기 화면에 큰 명조 제목으로 보였다).
///
/// 기댓값은 `Tools/golden/generate.py` 의 `firstLineCases`. 주석 줄은 파이썬 셈(`context_roles`)을 **markdown-it · cmark-gfm 에
/// 대어 본 뒤에** 싣는다. 첫 줄 · 이름 바꾸기 · 칸 이름은 파이썬 쌍둥이(`first_line` · `replacing_first_line` · `comment_label`)가 셈한다.
final class FirstLineCommentGoldenTests: XCTestCase {

    struct Golden: Decodable {
        struct Case: Decodable {
            let name: String
            let text: String
            let firstLine: String?
            let retitled: String?
            let commentLines: [Bool]
            let commentBlocks: Int
            let commentLabels: [String]
        }
        let firstLineCases: [Case]
    }

    static func goldenCases() throws -> [Golden.Case] {
        let here = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let url = here.appendingPathComponent("Golden/expected.json")
        return try JSONDecoder().decode(Golden.self, from: try Data(contentsOf: url)).firstLineCases
    }

    /// 첫 줄(목록 제목 · 파일 이름)은 주석 안의 줄을 건너뛴다.
    func testFirstLineSkipsComments() throws {
        let cases = try Self.goldenCases()
        XCTAssertFalse(cases.isEmpty, "정답표가 비었다")
        for item in cases {
            XCTAssertEqual(FrontMatterParser.firstLine(of: item.text), item.firstLine, "[\(item.name)]")
        }
    }

    /// **이름을 바꾸면 첫 줄 셈이 읽은 그 줄**을 바꾼다 — `<!--` 줄을 덮어 주석을 풀지 않는다 (327).
    func testRetitleReplacesTheLineFirstLineRead() throws {
        for item in try Self.goldenCases() {
            XCTAssertEqual(FrontMatterParser.replacingFirstLine(in: item.text, with: "새 제목"), item.retitled, "[\(item.name)]")
        }
    }

    /// 주석 줄 — 편집기 칠하기 · 첫 줄 셈 · 목록 미리보기가 같은 셈(`BlockContext`)을 쓴다.
    func testCommentLinesMatchJudges() throws {
        for item in try Self.goldenCases() {
            let body = FrontMatterParser.parse(item.text).body.components(separatedBy: "\n")
            XCTAssertEqual(BlockContext.commentLines(in: body), item.commentLines, "[\(item.name)]")
            XCTAssertEqual(BlockContext.roles(of: body).map { $0 == .comment }, item.commentLines, "역할 — [\(item.name)]")
        }
    }

    /// 편집기가 위쪽을 훑어 넘기는 *열린 덩이* 는 줄 역할 셈과 같아야 한다 — 어느 줄에서 잘라 넘겨도 아래 역할이 그대로.
    func testOpenBlockAgreesWithRoles() throws {
        for item in try Self.goldenCases() {
            let body = FrontMatterParser.parse(item.text).body.components(separatedBy: "\n")
            let whole = BlockContext.roles(of: body)
            var open = BlockContext.Open.none
            for cut in 0..<body.count {
                let rest = BlockContext.roles(of: Array(body[cut...]), insideFence: open == .fence,
                                              insideComment: open == .comment)
                XCTAssertEqual(rest.map { $0 == .comment }, whole[cut...].map { $0 == .comment },
                               "[\(item.name)] \(cut)째 줄부터")
                open = BlockContext.openBlock(after: body[cut], from: open)
            }
        }
    }

    /// 읽기 화면 — 주석 덩이마다 접힌 칸 하나, 칸 이름은 줄 수. 줄 지도(`data-line`)도 그대로 붙는다.
    func testReadingViewFoldsComments() throws {
        for item in try Self.goldenCases() {
            let html = MarkdownHTML.render(markdown: item.text, notePath: "노트.md", existing: []).bodyHTML
            XCTAssertEqual(html.components(separatedBy: "<details class=\"yb-comment\">").count - 1, item.commentBlocks,
                           "[\(item.name)] 접힌 칸 수\n\(html)")
            let labels = html.components(separatedBy: "<summary data-label=\"").dropFirst()
                .map { piece in String(piece.prefix { character in character != "\"" }) }
            XCTAssertEqual(labels, item.commentLabels, "[\(item.name)] 칸 이름")
            if !LineMap.blocks(markdown: item.text).isEmpty {
                XCTAssertTrue(html.contains("data-line=\""), "[\(item.name)] 블록 짝이 어긋나 줄 지도가 빠졌다\n\(html)")
            }
        }
    }

    /// 칸 안의 글은 **이스케이프한 그대로**다 — 주석 안의 태그가 실행되지 않는다 (ADR-0004 안전 1겹).
    func testCommentTextIsEscaped() {
        let html = MarkdownHTML.render(markdown: "<!--\n<script>x</script>\n-->\n제목", notePath: "노트.md", existing: []).bodyHTML
        XCTAssertFalse(html.contains("<script>"), html)
        XCTAssertTrue(html.contains("&lt;script&gt;"), html)
    }
}
