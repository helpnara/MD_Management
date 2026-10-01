import XCTest
@testable import Core

/// 198 — **줄 하나만 봐서는 모르는 것.** 밑줄(`---` · `===`)이 받친 글은 제목, 글 바로 밑의 `2. ` · 네 칸 줄은 이어지는 글.
///
/// 기댓값은 `Tools/golden/generate.py` 의 `contextCases` — 같은 셈을 파이썬으로 적고 **cmark-gfm 이 그린 HTML**
/// (제목 · 수평선 수, 이어지는 줄이 글 그대로인지)에 대어 보고 왔다.
final class BlockContextGoldenTests: XCTestCase {

    struct Golden: Decodable {
        struct Case: Decodable {
            let name: String
            let lines: [String]
            let roles: [String]
        }
        let contextCases: [Case]
    }

    func testRolesMatchGolden() throws {
        let here = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let url = here.appendingPathComponent("Golden/expected.json")
        let cases = try JSONDecoder().decode(Golden.self, from: try Data(contentsOf: url)).contextCases
        XCTAssertFalse(cases.isEmpty, "정답표가 비었다")
        for item in cases {
            XCTAssertEqual(BlockContext.roles(of: item.lines).map(\.rawValue), item.roles, "[\(item.name)]")
        }
    }

    /// 이어지는 줄은 **보통 글로** 칠한다 — 목록 마커도 코드도 아니다. 줄 혼자 볼 때와 글자는 같다.
    func testContinuationLineIsStyledAsText() {
        for line in ["2. 나", "    나", "1. "] {
            let style = LineStyler.style(paragraph: line, asText: true)
            XCTAssertNil(style.block, line)
            XCTAssertTrue(style.markers.isEmpty, line)
        }
    }
}
