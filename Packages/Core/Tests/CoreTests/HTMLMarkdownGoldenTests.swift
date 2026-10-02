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
        struct Cases: Decodable {
            let convert: [Convert]
            let fill: [Fill]
            let keeps: [Keeps]
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
}
