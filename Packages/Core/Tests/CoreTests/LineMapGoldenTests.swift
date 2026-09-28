import XCTest
@testable import Core

/// 176 — **읽기 ↔ 쓰기를 오가도 보던 자리.**
///
/// 기댓값은 `Tools/golden/generate.py` 의 `lineMapCases` — markdown-it 의 `token.map`(블록의 줄 범위)으로
/// 따로 계산했다. 앱은 swift-markdown(cmark) 의 원문 범위를 쓴다 — **다른 파서 둘이 같은 줄을 말하는지** 본다.
final class LineMapGoldenTests: XCTestCase {

    struct Golden: Decodable {
        struct Block: Decodable {
            let tag: String
            let line: Int
            let lineEnd: Int
        }
        struct Anchor: Decodable {
            let index: Int
            let fraction: Double
        }
        struct Case: Decodable {
            let name: String
            let text: String
            let blocks: [Block]
            let anchors: [Anchor?]
        }
        let lineMapCases: [Case]
    }

    static func load() throws -> Golden {
        let here = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let url = here.appendingPathComponent("Golden/expected.json")
        return try JSONDecoder().decode(Golden.self, from: try Data(contentsOf: url))
    }

    func testBlocksMatchGolden() throws {
        let cases = try Self.load().lineMapCases
        XCTAssertFalse(cases.isEmpty, "정답표가 비었다")
        for item in cases {
            let blocks = LineMap.blocks(markdown: item.text)
            XCTAssertEqual(blocks.map(\.tag), item.blocks.map(\.tag), "태그 — [\(item.name)]")
            XCTAssertEqual(blocks.map(\.line), item.blocks.map(\.line), "시작 줄 — [\(item.name)]")
            XCTAssertEqual(blocks.map(\.lineEnd), item.blocks.map(\.lineEnd), "끝 줄 — [\(item.name)]")
        }
    }

    func testAnchorsMatchGolden() throws {
        for item in try Self.load().lineMapCases {
            let blocks = item.blocks.map { LineBlock(tag: $0.tag, line: $0.line, lineEnd: $0.lineEnd) }
            for (line, expected) in item.anchors.enumerated() {
                let anchor = LineMap.anchor(forLine: line, in: blocks)
                XCTAssertEqual(anchor?.index, expected?.index, "[\(item.name)] \(line)줄의 블록")
                if let anchor, let expected {
                    XCTAssertEqual(anchor.fraction, expected.fraction, accuracy: 1e-9,
                                   "[\(item.name)] \(line)줄의 비율")
                }
            }
        }
    }

    /// **블록 안의 줄은 오가도 같은 줄로 돌아온다** — 쓰기 → 읽기 → 쓰기에서 자리가 흐르지 않는다.
    func testRoundTripReturnsTheSameLine() throws {
        for item in try Self.load().lineMapCases {
            let blocks = LineMap.blocks(markdown: item.text)
            for line in 0..<item.text.components(separatedBy: "\n").count {
                guard let anchor = LineMap.anchor(forLine: line, in: blocks) else { continue }
                let block = blocks[anchor.index]
                guard block.line <= line, line <= block.lineEnd else { continue }
                XCTAssertEqual(LineMap.line(forBlock: anchor.index, fraction: anchor.fraction, in: blocks),
                               line, "[\(item.name)] \(line)줄")
            }
        }
    }

    /// **읽기 HTML 에 붙은 속성이 표와 같다** — 웹뷰가 말하는 순번이 이 표의 순번이어야 한다.
    func testRenderedHTMLCarriesTheSameLines() throws {
        let pattern = try NSRegularExpression(pattern: #"data-line="(\d+)" data-line-end="(\d+)""#)
        for item in try Self.load().lineMapCases {
            let html = MarkdownHTML.render(markdown: item.text, notePath: "노트.md", existing: []).bodyHTML
            let text = html as NSString
            let found = pattern.matches(in: html, range: NSRange(location: 0, length: text.length)).map {
                (Int(text.substring(with: $0.range(at: 1)))!, Int(text.substring(with: $0.range(at: 2)))!)
            }
            let blocks = LineMap.blocks(markdown: item.text)
            XCTAssertEqual(found.map { $0.0 }, blocks.map(\.line), "HTML 의 시작 줄 — [\(item.name)]")
            XCTAssertEqual(found.map { $0.1 }, blocks.map(\.lineEnd), "HTML 의 끝 줄 — [\(item.name)]")
        }
    }

    /// 짝이 안 맞으면 **손대지 않는다** — 틀린 줄로 데려가느니 비율로 물러선다.
    func testMismatchLeavesHTMLUntouched() {
        let html = "<p>하나</p>\n<p>둘</p>\n"
        XCTAssertEqual(LineMap.annotate(html, markdown: "하나\n"), html)
    }
}
