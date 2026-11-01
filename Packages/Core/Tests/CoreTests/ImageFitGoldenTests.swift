import XCTest
@testable import Core

/// **사진을 줄일 때의 긴 변** (299) — 기댓값은 파이썬 쌍둥이(`image_fit_long_side`)가 계산한 것뿐이다.
final class ImageFitGoldenTests: XCTestCase {

    private struct Golden: Decodable {
        struct Case: Decodable {
            let name: String
            let width: Double
            let height: Double
            let longSide: Double
        }
        let imageFitCases: [Case]
    }

    private static func cases() throws -> [Golden.Case] {
        let here = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let url = here.appendingPathComponent("Golden/expected.json")
        return try JSONDecoder().decode(Golden.self, from: try Data(contentsOf: url)).imageFitCases
    }

    func testLongSideMatchesPython() throws {
        let cases = try Self.cases()
        XCTAssertFalse(cases.isEmpty)
        for item in cases {
            XCTAssertEqual(ImageFit.longSide(width: item.width, height: item.height), item.longSide, "[\(item.name)] 긴 변")
        }
    }
}
