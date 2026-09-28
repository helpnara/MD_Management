import XCTest
@testable import Core

/// **폴더 화면의 노트 개수** (153, 사용자 · 2026-09-19 — *개수가 안 맞을 때가 있어*).
///
/// 세는 길이 **둘**이었다. 목록을 만드는 쪽은 숨김 파일과 폴더를 걸렀는데, 숫자를
/// 만드는 쪽은 확장자만 보고 셌다 — **목록에 없는 것이 숫자에는 있었다.**
/// 이제 둘이 `Paths.countsAsNote` 하나를 쓴다. 그 규칙을 여기서 못 박는다.
final class CountGoldenTests: XCTestCase {

    struct Golden: Decodable {
        struct Case: Decodable {
            let name: String
            let entry: String
            let isDirectory: Bool
            let countsAsNote: Bool
        }
        let countCases: [Case]
    }

    static func load() throws -> Golden {
        let here = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let url = here.appendingPathComponent("Golden/expected.json")
        return try JSONDecoder().decode(Golden.self, from: try Data(contentsOf: url))
    }

    func testMatchesGolden() throws {
        for item in try Self.load().countCases {
            XCTAssertEqual(Paths.countsAsNote(name: item.entry, isDirectory: item.isDirectory),
                           item.countsAsNote,
                           "[\(item.name)] \(item.entry)")
        }
    }

    /// **폴더는 이름이 무엇이든 노트가 아니다.** `자료.md` 라는 폴더가 세어지던 자리다.
    func testDirectoryNeverCounts() throws {
        for item in try Self.load().countCases {
            XCTAssertFalse(Paths.countsAsNote(name: item.entry, isDirectory: true),
                           "폴더를 셌다 — [\(item.name)]")
        }
    }

    /// **점으로 시작하면 세지 않는다** — 목록에도 안 나오기 때문이다.
    func testHiddenNeverCounts() {
        for name in [".초안.md", ".DS_Store", ".회의록.md.icloud", ".trash"] {
            XCTAssertFalse(Paths.countsAsNote(name: name, isDirectory: false), name)
        }
    }

    /// **NFC 든 NFD 든 같은 값이 나온다.** 한글 파일명은 iCloud · 옵시디언 사이에서
    /// 두 모습으로 오간다 — 세는 값이 갈리면 개수가 기기마다 달라진다.
    func testNormalizationDoesNotChangeTheAnswer() {
        let composed = "회의록.md"
        let decomposed = composed.decomposedStringWithCanonicalMapping
        XCTAssertNotEqual(composed.unicodeScalars.count, decomposed.unicodeScalars.count,
                          "시험이 두 모습을 쓰고 있지 않다")
        XCTAssertTrue(Paths.countsAsNote(name: composed, isDirectory: false))
        XCTAssertTrue(Paths.countsAsNote(name: decomposed, isDirectory: false))
    }
}
