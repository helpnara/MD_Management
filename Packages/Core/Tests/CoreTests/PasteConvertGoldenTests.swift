import XCTest
@testable import Core

/// **밖에서 복사해 온 것을 붙일 때 바꿔 주기** (157 · 158 · 159, 2026-09-22 사용자).
///
/// 기댓값은 `Tools/golden/generate.py` 가 파이썬으로 따로 계산한다. 표는 거기서
/// **두 파서에 먹여** 칸의 글자가 살아남는지까지 본 것이다 (`CLAUDE.md` §2).
final class PasteConvertGoldenTests: XCTestCase {

    struct Golden: Decodable {
        struct Numbering: Decodable {
            struct Result: Decodable { let text: String; let removed: String }
            let name: String
            let line: String
            let pasted: String
            let result: Result?
        }
        struct WebLink: Decodable {
            let name: String
            let url: String
            let pageName: String?
            let selection: String
            let result: String?
        }
        struct Table: Decodable {
            let name: String
            let html: String
            let result: String?
        }
        struct Convert: Decodable {
            let numbering: [Numbering]
            let webLink: [WebLink]
            let htmlTable: [Table]
        }
        let pasteConvertCases: Convert
    }

    static func load() throws -> Golden.Convert {
        let here = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let url = here.appendingPathComponent("Golden/expected.json")
        return try JSONDecoder().decode(Golden.self, from: try Data(contentsOf: url))
            .pasteConvertCases
    }

    // MARK: - 158 · 번호 겹침

    func testNumberingMatchesGolden() throws {
        for item in try Self.load().numbering {
            let got = Pasting.numbering(pasted: item.pasted, onLine: item.line)
            let where_ = "[\(item.name)]"
            guard let want = item.result else {
                XCTAssertNil(got, "안 건드려야 한다 — \(where_)")
                continue
            }
            XCTAssertEqual(got?.text, want.text, "고친 글 — \(where_)")
            XCTAssertEqual(got?.removed, want.removed, "지운 마커 — \(where_)")
        }
    }

    /// **마커 말고는 한 글자도 안 없앤다.** 붙여넣기는 앱이 본문을 고치는 자리라
    /// 글자가 사라지면 사람이 친 것을 잃는다 (152 에서 겪은 그 일이다).
    func testNumberingRemovesOnlyTheMarker() throws {
        var touched = 0
        for item in try Self.load().numbering {
            guard let got = Pasting.numbering(pasted: item.pasted, onLine: item.line) else { continue }
            let shrunk = item.pasted.replacingOccurrences(of: got.removed, with: "",
                                                          options: [], range: item.pasted.range(of: got.removed))
            XCTAssertEqual(bare(got.text), bare(shrunk), "마커 말고 다른 글자가 달라졌다 — [\(item.name)]")
            touched += 1
        }
        XCTAssertGreaterThan(touched, 0, "고치는 사례가 하나도 없다 — 사례를 더해라")
    }

    /// **갈래가 다르면 안 건드린다.** 어느 마커를 살릴지는 사람만 안다.
    func testDifferentKindsAreLeftAlone() {
        XCTAssertNil(Pasting.numbering(pasted: "1. 첫째", onLine: "- "))
        XCTAssertNil(Pasting.numbering(pasted: "- 첫째", onLine: "1. "))
    }

    // MARK: - 157 · 웹 링크

    func testWebLinkMatchesGolden() throws {
        for item in try Self.load().webLink {
            let got = Pasting.webLink(url: item.url, name: item.pageName, selection: item.selection)
            XCTAssertEqual(got, item.result, "[\(item.name)] \(item.url)")
        }
    }

    /// **`http` · `https` 만 링크로 만든다.** 다른 스킴을 링크로 만들면 누르는 사람이 위험하다.
    func testOnlyWebSchemes() {
        for address in ["javascript:alert(1)", "file:///etc/passwd", "data:text/html,x",
                        "mailto:a@b.c", "ftp://example.com", "그냥 글자", "", "https://"] {
            XCTAssertFalse(Pasting.isWebAddress(address), address)
        }
        XCTAssertTrue(Pasting.isWebAddress("https://example.com"))
        XCTAssertTrue(Pasting.isWebAddress("http://example.com"))
    }

    // MARK: - 159 · HTML 표

    func testHTMLTableMatchesGolden() throws {
        for item in try Self.load().htmlTable {
            XCTAssertEqual(HTMLTable.markdown(from: item.html), item.result, "[\(item.name)]")
        }
    }

    /// **표가 아니면 손대지 않는다.** 붙여넣기가 무엇을 할지 모르는 자리가 되면 안 된다.
    func testNonTableHTMLIsLeftAlone() {
        for html in ["<p>글</p>", "<ul><li>하나</li></ul>", "<h1>제목</h1>", "", "표"] {
            XCTAssertNil(HTMLTable.markdown(from: html), html)
        }
    }

    /// **세로줄을 피해야 칸이 안 쪼개진다.** 파이썬 대조가 두 파서로 확인한 성질이다.
    func testCellPipeIsEscaped() {
        XCTAssertEqual(HTMLTable.escapeCell("가 | 나"), "가 \\| 나")
        XCTAssertEqual(HTMLTable.escapeCell("첫 줄\n둘째 줄"), "첫 줄<br>둘째 줄")
    }

    private func bare(_ text: String) -> String {
        text.replacingOccurrences(of: " ", with: "").replacingOccurrences(of: "\t", with: "")
    }
}
