import XCTest
@testable import Core

/// 182 — **겹침이 너무 깊은 글에서 앱이 꺼지지 않는다.**
///
/// 기댓값은 `Tools/golden/generate.py` 의 `nestingCases` — 같은 셈을 파이썬으로 적고, 그 값이
/// **cmark 가 실제로 만든 깊이보다 늘 크거나 같은지**(위쪽 한계인지) 거기서 확인하고 왔다.
final class NestingGoldenTests: XCTestCase {

    struct Golden: Decodable {
        struct Case: Decodable {
            let name: String
            let text: String
            let depth: Int
            let tooDeep: Bool
        }
        let nestingCases: [Case]
    }

    static func load() throws -> Golden {
        let here = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let url = here.appendingPathComponent("Golden/expected.json")
        return try JSONDecoder().decode(Golden.self, from: try Data(contentsOf: url))
    }

    func testDepthMatchesGolden() throws {
        let cases = try Self.load().nestingCases
        XCTAssertFalse(cases.isEmpty, "정답표가 비었다")
        for item in cases {
            XCTAssertEqual(Nesting.depth(of: item.text), item.depth, "깊이 — [\(item.name)]")
            XCTAssertEqual(Nesting.isTooDeep(item.text), item.tooDeep, "막나 — [\(item.name)]")
        }
    }

    /// **막은 글은 글자 그대로 보이고, 안 막은 글은 평소대로 그린다.** 막은 글에서 트리를 만드는
    /// 세 자리(읽기 · 링크 뽑기 · 줄 지도)가 모두 파서를 건너뛰는지 본다.
    func testGuardedTextIsShownAsItIs() throws {
        for item in try Self.load().nestingCases {
            let html = MarkdownHTML.render(markdown: item.text, notePath: "노트.md", existing: []).bodyHTML
            XCTAssertEqual(html.contains("<pre>") && html.contains("겹침이 너무 깊은"), item.tooDeep,
                           "[\(item.name)]")
            if item.tooDeep {
                XCTAssertTrue(LineMap.blocks(markdown: item.text).isEmpty, "줄 지도 — [\(item.name)]")
            }
        }
    }

    /// **정말 깊은 글을 넣어도 꺼지지 않는다** — 이 테스트가 끝까지 도는 것이 심판이다. 가드가 없으면
    /// 리눅스 러너의 스택(8MB)도 넘친다. 기댓값을 적지 않는다 — 꺼지지 않고, 막았다는 것만 본다.
    func testVeryDeepTextDoesNotCrash() {
        let texts = [
            String(repeating: "> ", count: 50_000) + "x",
            String(repeating: "- ", count: 50_000) + "x",
            String(repeating: "*a ", count: 20_000) + "b" + String(repeating: " c*", count: 20_000),
            String(repeating: "> ", count: 50_000) + "![그림](assets/a.png)",
        ]
        for text in texts {
            XCTAssertTrue(Nesting.isTooDeep(text))
            _ = MarkdownHTML.render(markdown: text, notePath: "노트.md", existing: [])
            _ = MarkdownHTML.referencedPaths(markdown: text, notePath: "노트.md")
            _ = LineMap.blocks(markdown: text)
            _ = MarkdownLinks.rebased(text, from: "", to: "회의")
        }
    }

    /// 막은 글에서도 **링크는 놓치지 않는다** — 공유 묶음 · 안 쓰는 첨부 셈이 이것을 쓴다.
    /// 기댓값을 적지 않는다: 같은 꼬리를 **파서로** 읽은 답과 글자로 훑은 답이 같아야 한다.
    func testGuardedTextStillYieldsTheSameLinks() {
        let tail = "![그림](assets/a.png \"제목\") 과 [표](<assets/내 표.pdf>) 와 [노트](기록.md#절)"
        let deep = String(repeating: "> ", count: 300) + tail
        XCTAssertFalse(Nesting.isTooDeep(tail))
        XCTAssertTrue(Nesting.isTooDeep(deep))
        let parsed = MarkdownLinks.extract(from: tail)
        XCTAssertEqual(parsed.count, 3, "꼬리의 링크를 파서가 못 읽었다")
        XCTAssertEqual(MarkdownLinks.extract(from: deep), parsed)
    }
}
