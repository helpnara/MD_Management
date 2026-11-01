import XCTest
@testable import Core

/// **마크다운이 줄바꿈 · 빈칸으로 안 보는 글자 고치기** (287) — `U+2028` · `U+2029` 등 → `\n`, 줄 앞의 `U+00A0` → 빈칸.
/// 기댓값은 `Tools/golden/generate.py` 가 계산한다 — 고친 뒤 글 길이 · 보이는 글자가 같고, 제목 · 목록 수가 줄지 않는지도 거기서 본다.
final class LineBreakGoldenTests: XCTestCase {

    struct Golden: Decodable {
        struct Case: Decodable {
            let name: String
            let text: String
            let repaired: String
            let breaks: Int
            let spaces: Int
        }
        let lineBreakCases: [Case]
    }

    static func load() throws -> Golden {
        let here = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let url = here.appendingPathComponent("Golden/expected.json")
        return try JSONDecoder().decode(Golden.self, from: try Data(contentsOf: url))
    }

    func testMatchesGolden() throws {
        let cases = try Self.load().lineBreakCases
        XCTAssertFalse(cases.isEmpty)
        for item in cases {
            XCTAssertEqual(LineBreaks.repaired(item.text), item.repaired, "[\(item.name)] 고친 글")
            XCTAssertEqual(LineBreaks.count(item.text), LineBreaks.Count(breaks: item.breaks, spaces: item.spaces),
                           "[\(item.name)] 센 수")
        }
    }

    /// 글 길이(UTF-16)가 같다 — 편집기가 커서 자리를 옮기지 않아도 되는 근거.
    func testKeepsLength() throws {
        for item in try Self.load().lineBreakCases {
            XCTAssertEqual((LineBreaks.repaired(item.text) as NSString).length, (item.text as NSString).length,
                           "[\(item.name)] 길이")
        }
    }

    /// 지도 장소가 줄을 나누는 글자는 이 목록과 `\n` · `\r` 이다 — 적는 자리가 하나다.
    func testMapPlacesUseSameBreaks() {
        XCTAssertEqual(MapPlaces.breaks, LineBreaks.foreign.union(["\n", "\r"]))
    }
}
