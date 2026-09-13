import XCTest
@testable import Core

/// 라이브 편집기(ADR-0005 L1)가 한 줄에 거는 모습을 **파이썬이 따로 계산한 값**과 견준다.
///
/// 기댓값은 `Tools/golden/generate.py` 가 `markdown-it-py` 로 만든다. 손으로 적지
/// 않는 이유는 `GoldenTests` 와 같다 — 컴파일 못 하는 환경에서 손으로 적은 기댓값은
/// 테스트가 버그를 승인하게 만든다.
///
/// **무엇을 견주나.** 구간의 오프셋을 직접 견주지 않고, 오프셋으로 **원문을 잘라**
/// 그 글자를 견준다. 오프셋이 한 칸이라도 틀리면 잘린 글자가 달라진다 — 이모지가
/// 낀 줄(UTF-16 두 칸)이 사례에 있는 이유다.
final class LineStylerGoldenTests: XCTestCase {

    struct Golden: Decodable {
        struct Span: Decodable {
            let token: String
            let text: String
        }
        struct Case: Decodable {
            let name: String
            let text: String
            let block: String?
            let content: String
            let spans: [Span]
        }
        let styleCases: [Case]
    }

    static func load() throws -> Golden {
        let here = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let url = here.appendingPathComponent("Golden/expected.json")
        return try JSONDecoder().decode(Golden.self, from: try Data(contentsOf: url))
    }

    // MARK: - 대조

    func testMatchesGolden() throws {
        for item in try Self.load().styleCases {
            let style = LineStyler.style(paragraph: item.text)
            let where_ = "[\(item.name)] \(item.text)"

            XCTAssertEqual(style.block?.rawValue, item.block, "블록 종류가 다르다 — \(where_)")

            // 마커를 뗀 나머지. markdown-it 은 뒤쪽 빈칸을 떼고 주므로 여기서도 뗀다.
            let rest = slice(item.text, start: style.contentStart,
                             length: utf16Count(item.text) - style.contentStart)
            XCTAssertEqual(trimmedTrailing(rest ?? "<잘못된 자리>"), item.content,
                           "마커 뗀 내용이 다르다 — \(where_)")

            let actual = style.inlineSpans.map { span -> String in
                let text = slice(item.text, start: span.start, length: span.length) ?? "<잘못된 자리>"
                return "\(span.token.rawValue):\(span.token == .inlineCode ? strippedCode(text) : text)"
            }
            let expected = item.spans.map { "\($0.token):\($0.text)" }
            XCTAssertEqual(actual, expected, "강조 구간이 다르다 — \(where_)")
        }
    }

    // MARK: - 스스로 지켜야 하는 것

    /// 오프셋이 문자열 밖으로 나가거나 글자 가운데를 자르면 `NSTextStorage` 가 죽는다.
    func testSpansStayInsideTheParagraph() throws {
        for item in try Self.load().styleCases {
            let style = LineStyler.style(paragraph: item.text)
            let length = utf16Count(item.text)
            let where_ = "[\(item.name)] \(item.text)"

            XCTAssertTrue((0...length).contains(style.contentStart), "contentStart 가 밖이다 — \(where_)")

            for span in style.inlineSpans {
                XCTAssertGreaterThanOrEqual(span.start, style.contentStart, "구간이 마커를 덮는다 — \(where_)")
                XCTAssertLessThanOrEqual(span.end, length, "구간이 줄 밖으로 나간다 — \(where_)")
                XCTAssertNotNil(slice(item.text, start: span.start, length: span.length),
                                "구간이 글자 가운데를 자른다 — \(where_)")
            }
            for marker in style.markers {
                XCTAssertGreaterThanOrEqual(marker.start, 0, "마커가 밖이다 — \(where_)")
                XCTAssertLessThanOrEqual(marker.end, length, "마커가 줄 밖으로 나간다 — \(where_)")
                XCTAssertNotNil(slice(item.text, start: marker.start, length: marker.length),
                                "마커가 글자 가운데를 자른다 — \(where_)")
            }
        }
    }

    /// 마커는 정렬돼 있고 서로 겹치지 않는다. 겹치면 흐리게 두 번 칠해진다.
    func testMarkersAreSortedAndDisjoint() throws {
        for item in try Self.load().styleCases {
            let markers = LineStyler.style(paragraph: item.text).markers
            for (previous, next) in zip(markers, markers.dropFirst()) {
                XCTAssertLessThanOrEqual(previous.end, next.start,
                                         "마커가 겹친다 — [\(item.name)] \(item.text)")
            }
            XCTAssertTrue(markers.allSatisfy { $0.length > 0 },
                          "빈 마커가 있다 — [\(item.name)] \(item.text)")
        }
    }

    /// 빈 줄과 빈칸만 있는 줄에서 죽지 않는다. 편집기가 가장 자주 보는 줄이다.
    func testBlankLines() {
        XCTAssertEqual(LineStyler.style(paragraph: ""), .plain)
        let spaces = LineStyler.style(paragraph: "   ")
        XCTAssertNil(spaces.block)
        XCTAssertEqual(spaces.contentStart, 3)
        XCTAssertTrue(spaces.inlineSpans.isEmpty)
    }

    // MARK: - 자

    private func utf16Count(_ text: String) -> Int { text.utf16.count }

    /// UTF-16 오프셋으로 원문을 자른다. 글자 가운데를 자르면 `nil` 이다.
    private func slice(_ text: String, start: Int, length: Int) -> String? {
        guard start >= 0, length >= 0, start + length <= text.utf16.count else { return nil }
        let units = text.utf16
        guard let from = units.index(units.startIndex, offsetBy: start, limitedBy: units.endIndex),
              let to = units.index(from, offsetBy: length, limitedBy: units.endIndex),
              let lower = String.Index(from, within: text),
              let upper = String.Index(to, within: text) else { return nil }
        return String(text[lower..<upper])
    }

    /// CommonMark 는 `` ` 코드 ` `` 의 앞뒤 빈칸을 한 개씩 뗀다. markdown-it 도 그렇게 준다.
    /// 편집기는 원문을 그대로 덮어야 하므로 **견줄 때만** 뗀다.
    private func strippedCode(_ text: String) -> String {
        guard text.count >= 2, text.hasPrefix(" "), text.hasSuffix(" "),
              text.contains(where: { $0 != " " }) else { return text }
        return String(text.dropFirst().dropLast())
    }

    private func trimmedTrailing(_ text: String) -> String {
        var result = text
        while let last = result.last, last == " " || last == "\t" { result.removeLast() }
        return result
    }
}
