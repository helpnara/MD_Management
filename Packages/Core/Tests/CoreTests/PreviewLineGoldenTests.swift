import XCTest
@testable import Core

/// **목록 · 검색 결과에 보이는 한 줄** (242). 기댓값은 `Tools/golden/generate.py` 의 `previewCases` —
/// 파이썬 쌍둥이(`preview_line.py`)가 셈하고 줄 안 부분은 markdown-it 이 심판했다. 뜻을 적은 사례 + 같은 씨앗으로 뒤섞은 줄 300개.
final class PreviewLineGoldenTests: XCTestCase {

    struct Golden: Decodable {
        struct Case: Decodable {
            let name: String
            let line: String
            let result: String
        }
        let previewCases: [Case]
    }

    func testMatchesGolden() throws {
        let here = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let url = here.appendingPathComponent("Golden/expected.json")
        let cases = try JSONDecoder().decode(Golden.self, from: try Data(contentsOf: url)).previewCases
        XCTAssertGreaterThan(cases.count, 300, "정답표가 모자라다")
        for item in cases {
            XCTAssertEqual(PreviewLine.plain(item.line), item.result, "[\(item.name)] \(item.line.debugDescription)")
        }
    }
}
