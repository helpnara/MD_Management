import XCTest
@testable import Core

/// **지도 앱의 장소 글을 링크로** (252). 기댓값은 `Tools/golden/generate.py` 의 `mapCases` — 같은 셈을 파이썬으로 적고
/// cmark-gfm 으로 그려 장소마다 링크 하나인지 본다. 공유(`IncomingShare`)에 물린 것은 `shareCases` · `shareEntryCases` 가 본다.
final class MapPlacesGoldenTests: XCTestCase {

    struct Golden: Decodable {
        struct Case: Decodable {
            let name: String
            /// 클립보드 항목들 — 카카오맵은 글과 주소를 따로 싣는다 (빌드 110).
            let pieces: [String]
            let result: String?
        }
        let mapCases: [Case]
    }

    func testPastedMatchesGolden() throws {
        let here = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let url = here.appendingPathComponent("Golden/expected.json")
        let cases = try JSONDecoder().decode(Golden.self, from: try Data(contentsOf: url)).mapCases
        XCTAssertFalse(cases.isEmpty)
        for c in cases {
            XCTAssertEqual(MapPlaces.pasted(c.pieces), c.result, c.name)
        }
    }
}
