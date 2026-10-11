import XCTest
@testable import Core

/// **앱 평가를 부탁할 때인가.** 기댓값은 `Tools/golden/generate.py` 의 `reviewCases` — 같은 셈을 파이썬으로 적었다.
final class ReviewPromptGoldenTests: XCTestCase {

    struct Golden: Decodable {
        struct Case: Decodable {
            let name: String
            let activeDays: Int
            let daysSinceFirstUse: Int
            let daysSinceLastAsk: Int?
            let askedThisVersion: Bool
            let result: Bool
        }
        let reviewCases: [Case]
    }

    func testMatchesGolden() throws {
        let here = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let url = here.appendingPathComponent("Golden/expected.json")
        let cases = try JSONDecoder().decode(Golden.self, from: try Data(contentsOf: url)).reviewCases
        XCTAssertFalse(cases.isEmpty, "정답표가 비었다")
        for item in cases {
            XCTAssertEqual(ReviewPrompt.isDue(activeDays: item.activeDays, daysSinceFirstUse: item.daysSinceFirstUse,
                                              daysSinceLastAsk: item.daysSinceLastAsk,
                                              askedThisVersion: item.askedThisVersion),
                           item.result, "[\(item.name)]")
        }
    }
}
