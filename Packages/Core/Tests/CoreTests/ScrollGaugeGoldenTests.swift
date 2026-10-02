import XCTest
@testable import Core

/// 202 — **늘 보이는 스크롤 막대.** 쓰기 · 읽기 화면이 같은 셈으로 막대를 그린다.
///
/// 기댓값은 `Tools/golden/generate.py` 의 `scrollGaugeCases` — 같은 셈을 파이썬으로 적고, 막대가 트랙 안에 있는지 거기서 보고 왔다.
final class ScrollGaugeGoldenTests: XCTestCase {

    struct Golden: Decodable {
        struct Thumb: Decodable {
            let start: Double
            let length: Double
        }
        struct Case: Decodable {
            let name: String
            let content: Double
            let viewport: Double
            let offset: Double
            let track: Double
            let minimum: Double
            let thumb: Thumb?
        }
        let scrollGaugeCases: [Case]
    }

    func testMatchesGolden() throws {
        let here = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let url = here.appendingPathComponent("Golden/expected.json")
        let cases = try JSONDecoder().decode(Golden.self, from: try Data(contentsOf: url)).scrollGaugeCases
        XCTAssertFalse(cases.isEmpty, "정답표가 비었다")
        for item in cases {
            let got = ScrollGauge.thumb(content: item.content, viewport: item.viewport, offset: item.offset,
                                        track: item.track, minimum: item.minimum)
            guard let want = item.thumb else {
                XCTAssertNil(got, "[\(item.name)]")
                continue
            }
            let thumb = try XCTUnwrap(got, "[\(item.name)]")
            XCTAssertEqual(thumb.start, want.start, accuracy: 1e-9, "자리 — [\(item.name)]")
            XCTAssertEqual(thumb.length, want.length, accuracy: 1e-9, "길이 — [\(item.name)]")
        }
    }
}
