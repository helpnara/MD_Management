import XCTest
@testable import Core

/// `#태그` 를 어디서 찾나 (빌드 34 · T2).
///
/// 기댓값은 `Tools/golden/generate.py` 가 같은 규칙을 파이썬으로 다시 구현해 계산한다.
/// **자리(오프셋)를 직접 견주지 않고 그 자리로 글자를 잘라** 견준다 — 이모지가 낀 줄
/// (UTF-16 두 칸)이 사례에 있는 이유다.
final class TagGoldenTests: XCTestCase {

    struct Golden: Decodable {
        struct Tag: Decodable {
            let start: Int
            let length: Int
            let text: String
        }
        struct Case: Decodable {
            let name: String
            let text: String
            let tags: [Tag]
        }
        let tagCases: [Case]
    }

    static func load() throws -> Golden {
        let here = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let url = here.appendingPathComponent("Golden/expected.json")
        return try JSONDecoder().decode(Golden.self, from: try Data(contentsOf: url))
    }

    func testMatchesGolden() throws {
        for item in try Self.load().tagCases {
            let found = Tags.scan(item.text)
            let where_ = "[\(item.name)] \(item.text)"
            XCTAssertEqual(found.count, item.tags.count, "찾은 개수가 다르다 — \(where_)")

            let utf16 = Array(item.text.utf16)
            for (made, want) in zip(found, item.tags) {
                XCTAssertEqual(made.start, want.start, "자리 — \(where_)")
                XCTAssertEqual(made.length, want.length, "길이 — \(where_)")
                guard made.start + made.length <= utf16.count else {
                    XCTFail("자리가 글 밖이다 — \(where_)")
                    continue
                }
                let sliced = String(decoding: utf16[made.start..<(made.start + made.length)], as: UTF16.self)
                XCTAssertEqual(sliced, want.text, "그 자리의 글자 — \(where_)")
            }
        }
    }

    /// **제목과 안 부딪힌다.** `# 제목` 은 태그가 아니고, 태그가 있는 줄의 블록 종류도 안 바뀐다.
    func testDoesNotFightHeadings() {
        XCTAssertTrue(Tags.scan("# 제목").isEmpty)
        XCTAssertTrue(Tags.scan("### 셋째 제목").isEmpty)
        XCTAssertEqual(LineStyler.style(paragraph: "# 제목").block, .heading1)
        XCTAssertNil(LineStyler.style(paragraph: "#태그만").block, "`#` 뒤에 빈칸이 없으면 제목이 아니다")
    }

    /// 읽기 모드도 같은 규칙으로 감싼다 — 편집기와 다르게 그리면 그것이 버그 자리다 (93).
    func testReadingModeWrapsTheSameTags() {
        XCTAssertEqual(MarkdownHTML.escapeMarkingTags("오늘 #회의 다"),
                       "오늘 <span class=\"yb-tag\">#회의</span> 다")
        XCTAssertEqual(MarkdownHTML.escapeMarkingTags("# 제목"), "# 제목", "제목은 안 감싼다")
        XCTAssertEqual(MarkdownHTML.escapeMarkingTags("<b>글</b> #태그"),
                       "&lt;b&gt;글&lt;/b&gt; <span class=\"yb-tag\">#태그</span>",
                       "감싸면서도 이스케이프는 그대로다")
    }
}
