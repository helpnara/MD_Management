import XCTest
@testable import Core

/// **접힌 줄이 글에 맞게 선다** (155, 사용자 · 2026-09-20).
///
/// 글이 길어 다음 줄로 넘어가면 그 줄은 **첫 줄의 글이 시작한 자리**에 서야 한다.
/// 화면은 `줄 맨 앞 ~ contentStart` 의 폭을 재서 그 자리를 잡는다. 폭은 UIKit 이라
/// 리눅스에서 못 재지만, **어디까지 재는지**는 여기서 못 박을 수 있다 — 그 자리를
/// 마커부터 잡는 바람에 **앞 빈칸이 빠져** 155 가 났다.
final class HangingGoldenTests: XCTestCase {

    struct Golden: Decodable {
        struct Case: Decodable {
            let name: String
            let text: String
            let contentStart: Int
            /// 탭을 빈칸으로 편 앞머리 — 화면이 실제로 재는 글자.
            let measured: String
        }
        let hangingCases: [Case]
    }

    static func load() throws -> Golden {
        let here = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let url = here.appendingPathComponent("Golden/expected.json")
        return try JSONDecoder().decode(Golden.self, from: try Data(contentsOf: url))
    }

    func testMatchesGolden() throws {
        for item in try Self.load().hangingCases {
            let style = LineStyler.style(paragraph: item.text)
            let where_ = "[\(item.name)]"
            XCTAssertTrue(style.block == .listItem || style.block == .orderedItem,
                          "목록 줄이라야 한다 — \(where_)")
            XCTAssertEqual(style.contentStart, item.contentStart, "글이 시작하는 자리 — \(where_)")

            let prefix = String(decoding: Array(item.text.utf16)[0..<style.contentStart],
                                as: UTF16.self)
            XCTAssertEqual(LineStyler.expandingTabs(prefix), item.measured,
                           "화면이 재는 앞머리 — \(where_)")
        }
    }

    /// **앞 빈칸이 재는 자리에 들어 있나.** 155 가 빠뜨린 바로 그 토막이다.
    func testLeadingBlanksAreMeasured() throws {
        for item in try Self.load().hangingCases {
            let leading = item.text.prefix { $0 == " " || $0 == "\t" }
            guard !leading.isEmpty else { continue }
            let style = LineStyler.style(paragraph: item.text)
            XCTAssertGreaterThan(style.contentStart, leading.utf16.count,
                                 "앞 빈칸이 빠졌다 — [\(item.name)]")
            let prefix = String(decoding: Array(item.text.utf16)[0..<style.contentStart],
                                as: UTF16.self)
            XCTAssertTrue(prefix.hasPrefix(String(leading)),
                          "재는 앞머리가 줄 맨 앞에서 시작하지 않는다 — [\(item.name)]")
        }
    }

    /// **마커부터 재면 어긋난다** — 고치기 전의 셈을 그대로 두고 견준다.
    /// 앞 빈칸이 있는 줄에서는 두 값이 **달라야** 한다. 같아지면 되돌아간 것이다.
    func testOldWayIsShorter() throws {
        var checked = 0
        for item in try Self.load().hangingCases {
            let leading = item.text.prefix { $0 == " " || $0 == "\t" }
            guard !leading.isEmpty else { continue }
            let style = LineStyler.style(paragraph: item.text)
            guard let marker = style.markers.first else {
                return XCTFail("마커가 없다 — [\(item.name)]")
            }
            XCTAssertLessThan(style.contentStart - marker.start, style.contentStart,
                              "마커부터 재면 짧아야 한다 — [\(item.name)]")
            checked += 1
        }
        XCTAssertGreaterThan(checked, 0, "앞 빈칸이 있는 사례가 하나도 없다 — 사례를 더해라")
    }

    /// 탭이 없으면 그대로 둔다 — 쓸데없이 새 글자를 만들지 않는다.
    func testExpandingTabsLeavesPlainTextAlone() {
        XCTAssertEqual(LineStyler.expandingTabs("  - 가"), "  - 가")
        XCTAssertEqual(LineStyler.expandingTabs("\t- 가"), "    - 가")
    }
}
