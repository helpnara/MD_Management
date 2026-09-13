import XCTest
@testable import Core

/// 뷰어 HTML (ADR-0004).
///
/// **HTML 문자열을 통째로 견주지 않는다.** 두 구현(`swift-markdown` 과
/// `markdown-it-py`)의 줄바꿈 · 속성 순서 같은 껍데기 차이가 진짜 차이를 덮는다.
/// 파이썬이 따로 센 **구조**(제목 단계 · 목록 · 표 · 이미지 주소)와 견준다.
final class MarkdownHTMLTests: XCTestCase {

    // MARK: - 파이썬 대조

    func testStructureMatchesPython() throws {
        for item in try GoldenTests.loadGolden().cases {
            let existing = Set(item.existing)
            let rendered = MarkdownHTML.render(
                markdown: item.source,
                notePath: item.notePath,
                exists: { existing.contains($0) })
            let html = rendered.bodyHTML
            let expected = item.html

            for level in 1...6 {
                XCTAssertEqual(
                    count(of: "<h\(level)>", in: html),
                    expected.headings.filter { $0 == level }.count,
                    "[\(item.name)] h\(level) 개수")
            }
            XCTAssertEqual(count(of: "<li>", in: html), expected.listItems,
                           "[\(item.name)] 목록 항목 개수")
            XCTAssertEqual(count(of: "<table>", in: html), expected.tables,
                           "[\(item.name)] 표 개수")
            XCTAssertEqual(count(of: "<pre>", in: html), expected.codeBlocks,
                           "[\(item.name)] 코드 블록 개수")
            XCTAssertEqual(count(of: "type=\"checkbox\"", in: html),
                           expected.checkboxes.checked + expected.checkboxes.unchecked,
                           "[\(item.name)] 체크박스 개수")
            XCTAssertEqual(count(of: " checked=", in: html), expected.checkboxes.checked,
                           "[\(item.name)] 켜진 체크박스 개수")
        }
    }

    func testImageSourcesMatchPython() throws {
        for item in try GoldenTests.loadGolden().cases {
            let existing = Set(item.existing)
            let rendered = MarkdownHTML.render(
                markdown: item.source,
                notePath: item.notePath,
                exists: { existing.contains($0) })
            XCTAssertEqual(imageSources(in: rendered.bodyHTML), item.html.imageSrcs,
                           "[\(item.name)] 이미지 주소")
        }
    }

    func testMissingAttachmentsMatchPython() throws {
        for item in try GoldenTests.loadGolden().cases {
            let existing = Set(item.existing)
            let rendered = MarkdownHTML.render(
                markdown: item.source,
                notePath: item.notePath,
                exists: { existing.contains($0) })
            // 인코딩 차이를 걷어내고 견준다 (GoldenTests 의 같은 이유).
            let decoded = rendered.missingAttachments.map {
                Paths.normalized($0.removingPercentEncoding ?? $0)
            }
            XCTAssertEqual(decoded, item.html.missingDecoded, "[\(item.name)] 없는 첨부")
        }
    }

    // MARK: - 안전 (설계서 ADR-0004 "안전")

    func testRawHTMLIsShownAsTextNotExecuted() {
        let rendered = render("<script>alert(1)</script>\n\n<b>굵게?</b>")
        XCTAssertFalse(rendered.bodyHTML.contains("<script>"),
            "남이 쓴 노트의 스크립트가 그대로 들어가면 안 된다")
        XCTAssertTrue(rendered.bodyHTML.contains("&lt;script&gt;"))
        XCTAssertFalse(rendered.bodyHTML.contains("<b>굵게?</b>"))
    }

    func testCodeBlockShowsHTMLLiterally() {
        // 개발자가 쓰는 가장 흔한 코드 블록이다. 이스케이프가 없으면 코드가
        // 코드로 안 보이고 **진짜 굵은 글씨**가 된다.
        let rendered = render("```html\n<b>x</b>\n```")
        XCTAssertTrue(rendered.bodyHTML.contains("&lt;b&gt;x&lt;/b&gt;"))
        XCTAssertTrue(rendered.bodyHTML.contains("<pre><code class=\"language-html\">"))
    }

    func testInlineCodeAndTextAreEscaped() {
        XCTAssertTrue(render("`a < b`").bodyHTML.contains("<code>a &lt; b</code>"))
        XCTAssertTrue(render("5 < 6 & 7").bodyHTML.contains("5 &lt; 6 &amp; 7"))
    }

    func testQuotesStayStraight() {
        // 파일이 원본이다 — 화면에서 따옴표 모양을 바꾸지 않는다 (ADR-0001).
        let html = render("그가 \"안녕\" 이라고 했다").bodyHTML
        XCTAssertTrue(html.contains("&quot;안녕&quot;"))
        XCTAssertFalse(html.contains("\u{201C}"), "둥근 따옴표로 바뀌면 안 된다")
    }

    // MARK: - 주소

    func testAssetURLEncodesKoreanAndSpaces() {
        XCTAssertEqual(MarkdownHTML.assetURL("assets/내 사진.jpg"),
                       "yb://note/assets/%EB%82%B4%20%EC%82%AC%EC%A7%84.jpg")
    }

    func testAssetURLRemovesQuotes() {
        // `HTMLFormatter` 가 src 를 이스케이프 없이 넣는다. 따옴표가 살아 있으면
        // 속성이 깨진다 — 인코딩이 그것을 막는 유일한 장치다.
        XCTAssertFalse(MarkdownHTML.assetURL("a\"b.png").contains("\""))
    }

    func testRelativePathRoundTrip() {
        let original = "아이디어/assets/내 사진.jpg"
        let url = MarkdownHTML.assetURL(original)
        let path = String(url.dropFirst("yb://note/".count))
        XCTAssertEqual(MarkdownHTML.relativePath(fromURLPath: "/" + path), original)
    }

    func testExternalImageBecomesMissingBox() {
        // 네트워크를 안 쓰는 앱이라 CSP 가 막는다. 조용히 안 뜨는 것보다
        // 왜 안 뜨는지 보이는 편이 낫다.
        let rendered = render("![](https://example.com/a.png)")
        XCTAssertTrue(rendered.bodyHTML.contains("yb-missing"))
        XCTAssertEqual(rendered.missingAttachments, ["https://example.com/a.png"])
    }

    func testExternalLinkIsLeftAlone() {
        let html = render("[사이트](https://example.com)").bodyHTML
        XCTAssertTrue(html.contains("href=\"https://example.com\""))
    }

    // MARK: - 페이지

    func testPageHasCSPAndNoScript() {
        let page = MarkdownHTML.page(bodyHTML: "<p>가</p>", css: ":root{--yb-ink:#000}")
        XCTAssertTrue(page.contains("Content-Security-Policy"))
        XCTAssertTrue(page.contains("default-src 'none'"))
        XCTAssertTrue(page.contains("--yb-ink:#000"))
        XCTAssertTrue(page.contains("font: -apple-system-body"),
            "글꼴을 px 로 적으면 Dynamic Type 이 죽는다")
        XCTAssertFalse(page.contains("<script"))
    }

    // MARK: - 속

    private func render(_ markdown: String) -> RenderedNote {
        MarkdownHTML.render(markdown: markdown, notePath: "노트.md", exists: { _ in true })
    }

    private func count(of needle: String, in haystack: String) -> Int {
        guard !needle.isEmpty else { return 0 }
        var total = 0
        var index = haystack.startIndex
        while let found = haystack.range(of: needle, range: index..<haystack.endIndex) {
            total += 1
            index = found.upperBound
        }
        return total
    }

    /// `<img ... src="..." ...>` 의 주소를 나온 순서대로.
    private func imageSources(in html: String) -> [String] {
        var sources: [String] = []
        var index = html.startIndex
        while let img = html.range(of: "<img", range: index..<html.endIndex) {
            guard let close = html.range(of: ">", range: img.upperBound..<html.endIndex) else { break }
            let tag = html[img.upperBound..<close.lowerBound]
            if let src = tag.range(of: "src=\""),
               let end = tag.range(of: "\"", range: src.upperBound..<tag.endIndex) {
                sources.append(String(tag[src.upperBound..<end.lowerBound]))
            }
            index = close.upperBound
        }
        return sources
    }
}
