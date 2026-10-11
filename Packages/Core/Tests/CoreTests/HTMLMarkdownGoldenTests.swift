import XCTest
@testable import Core

/// 206 · 207 — **붙여넣은 HTML 전체를 마크다운으로.** 표가 든 긴 글을 붙이면 표만 남고 글이 사라지던 것을 고쳤다.
///
/// 기댓값은 `Tools/golden/html_markdown.py` 가 같은 규칙으로 따로 셈했고, `generate.py` 가 그 답을 cmark-gfm 으로 그려
/// **글자가 차례까지 하나도 안 빠졌는지** · 제목 · 표 칸 · 목록 수가 맞는지 보고 왔다. 159 의 표 사례도 여기 들어 있다.
final class HTMLMarkdownGoldenTests: XCTestCase {

    struct Golden: Decodable {
        struct Slot: Decodable {
            let src: String
            let alt: String
        }
        struct Convert: Decodable {
            let name: String
            let html: String
            let markdown: String?
            let images: [Slot]
            let plain: String?
            let keeps: Bool?
        }
        struct Fill: Decodable {
            let name: String
            let markdown: String
            let links: [String?]
            let result: String
        }
        struct Keeps: Decodable {
            let name: String
            let plain: String
            let converted: String
            let result: Bool
        }
        struct Promote: Decodable {
            let name: String
            let markdown: String
            let result: String
        }
        struct TaskCase: Decodable {
            let name: String
            let markdown: String
            let line: Int
            let result: String?
        }
        struct TaskLines: Decodable {
            let name: String
            let markdown: String
            let lines: [Int]
        }
        struct CodeBlock: Decodable {
            let language: String
            let text: String
        }
        struct CodeBlocks: Decodable {
            let name: String
            let markdown: String
            let blocks: [CodeBlock]
        }
        struct Cases: Decodable {
            let convert: [Convert]
            let fill: [Fill]
            let keeps: [Keeps]
            let promote: [Promote]
            let tasks: [TaskCase]
            let taskLines: [TaskLines]
            let codeBlocks: [CodeBlocks]
        }
        let htmlMarkdownCases: Cases
    }

    static func goldenCases() throws -> Golden.Cases {
        let here = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let url = here.appendingPathComponent("Golden/expected.json")
        return try JSONDecoder().decode(Golden.self, from: try Data(contentsOf: url)).htmlMarkdownCases
    }

    func testConvertMatchesGolden() throws {
        let cases = try Self.goldenCases().convert
        XCTAssertFalse(cases.isEmpty, "정답표가 비었다")
        for item in cases {
            XCTAssertEqual(HTMLMarkdown.convert(item.html), item.markdown, "[\(item.name)]")
            let slots = HTMLMarkdown.imageSlots(item.html)
            XCTAssertEqual(slots.map(\.src), item.images.map(\.src), "사진 자리 — [\(item.name)]")
            XCTAssertEqual(slots.map(\.alt), item.images.map(\.alt), "사진 이름 — [\(item.name)]")
            if let plain = item.plain, let keeps = item.keeps {
                XCTAssertEqual(HTMLMarkdown.keepsLetters(plain: plain, converted: item.markdown ?? ""), keeps,
                               "안전장치 — [\(item.name)]")
            }
        }
    }

    func testFillImagesMatchesGolden() throws {
        for item in try Self.goldenCases().fill {
            XCTAssertEqual(HTMLMarkdown.fillImages(item.markdown, links: item.links), item.result, "[\(item.name)]")
        }
    }

    func testKeepsLettersMatchesGolden() throws {
        for item in try Self.goldenCases().keeps {
            XCTAssertEqual(HTMLMarkdown.keepsLetters(plain: item.plain, converted: item.converted), item.result,
                           "[\(item.name)]")
        }
    }

    /// 보낸 앱의 마크다운에 든 표 — 빈 머리줄을 첫 줄로 (2026-10-03 사용자).
    func testPromoteEmptyHeadersMatchesGolden() throws {
        for item in try Self.goldenCases().promote {
            XCTAssertEqual(HTMLMarkdown.promoteEmptyHeaders(item.markdown), item.result, "[\(item.name)]")
        }
    }

    /// 211 — 읽기 화면에서 누른 체크상자 하나만 뒤집는다.
    func testTaskToggleMatchesGolden() throws {
        for item in try Self.goldenCases().tasks {
            XCTAssertEqual(TaskToggle.toggled(item.markdown, line: item.line), item.result, "[\(item.name)]")
        }
    }

    /// 211 — 읽기 화면은 체크상자 줄마다 **그 줄 번호로** 누를 수 있는 링크를 단다.
    func testReaderLinksEveryTaskLine() throws {
        for item in try Self.goldenCases().taskLines {
            let html = MarkdownHTML.render(markdown: item.markdown, notePath: "노트.md", existing: []).bodyHTML
            var found: [Int] = []
            var rest = Substring(html)
            while let range = rest.range(of: "yb://task/") {
                let digits = rest[range.upperBound...].prefix { $0.isNumber }
                if let value = Int(digits) { found.append(value) }
                rest = rest[range.upperBound...]
            }
            XCTAssertEqual(found, item.lines, "[\(item.name)] \(html)")
            // 232 — 누를 수 있는 체크상자마다 보이스오버가 체크상자로 읽는다. 켜짐은 상자의 `checked` 와 같다.
            XCTAssertEqual(html.components(separatedBy: "role=\"checkbox\"").count - 1, found.count, "[\(item.name)] \(html)")
            XCTAssertEqual(html.components(separatedBy: "aria-checked=\"true\"").count - 1,
                           html.components(separatedBy: "checked=\"\"").count - 1, "[\(item.name)] \(html)")
            // 누른 줄을 뒤집으면 실제로 체크상자가 바뀐다 — 링크의 줄 번호와 뒤집기의 줄 번호가 같은 셈이다.
            for line in found {
                XCTAssertNotNil(TaskToggle.toggled(item.markdown, line: line), "[\(item.name)] \(line)번 줄")
            }
        }
    }

    /// 237 — 읽기 화면 코드 상자의 *복사* 가 넣을 글. 정답은 markdown-it 의 토큰(파이썬)이 계산했다.
    /// 상자마다 복사 · 크게 보기 단추가 **그 차례의 번호로** 하나씩 선다 — 단추 번호와 글의 자리가 같은 셈이다.
    func testCodeBlocksMatchGolden() throws {
        let cases = try Self.goldenCases().codeBlocks
        XCTAssertFalse(cases.isEmpty, "정답표가 비었다")
        for item in cases {
            let rendered = MarkdownHTML.render(markdown: item.markdown, notePath: "노트.md", existing: [])
            XCTAssertEqual(rendered.codeBlocks.map(\.language), item.blocks.map(\.language), "[\(item.name)] 언어")
            XCTAssertEqual(rendered.codeBlocks.map(\.text), item.blocks.map(\.text), "[\(item.name)] 글")
            for index in item.blocks.indices {
                XCTAssertTrue(rendered.bodyHTML.contains("yb://copy/\(index)\""), "[\(item.name)] 복사 단추 \(index)")
                XCTAssertTrue(rendered.bodyHTML.contains("yb://code/\(index)\""), "[\(item.name)] 크게 보기 단추 \(index)")
            }
            XCTAssertFalse(rendered.bodyHTML.contains("yb://copy/\(item.blocks.count)\""), "[\(item.name)] 단추가 상자보다 많다")
            // 울타리 뒤 글의 따옴표가 속성을 깨고 나오지 않는다.
            XCTAssertFalse(rendered.bodyHTML.contains("language-a\"b"), "[\(item.name)] \(rendered.bodyHTML)")
        }
    }
}
