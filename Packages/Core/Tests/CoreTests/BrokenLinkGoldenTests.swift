import XCTest
@testable import Core

/// **안 열리는 링크 찾기** (146, 사용자 제안).
///
/// 읽기 모드는 이미 없는 첨부를 네모로 보여 준다. 그런데 그건 **그 자리까지 내려가야**
/// 보인다 — 긴 노트에서는 있는 줄도 모른다. 여기서는 한 번에 모아 준다.
///
/// **고치지 않는다. 보여 주기만 한다.** 앱이 본문을 고치는 자리는 둘뿐이다
/// (노트를 옮길 때 · 붙여넣을 때). 여기서 몰래 고치면 셋째 자리가 생긴다.
final class BrokenLinkGoldenTests: XCTestCase {

    struct Golden: Decodable {
        struct Broken: Decodable {
            let destination: String
            let resolved: String
            let line: Int
            let text: String
            let kind: String
        }
        struct Case: Decodable {
            let name: String
            let text: String
            let notePath: String
            let files: [String]
            let broken: [Broken]
        }
        let brokenCases: [Case]
    }

    static func load() throws -> Golden {
        let here = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let url = here.appendingPathComponent("Golden/expected.json")
        return try JSONDecoder().decode(Golden.self, from: try Data(contentsOf: url))
    }

    func testMatchesGolden() throws {
        for item in try Self.load().brokenCases {
            let made = BrokenLinks.find(in: item.text, notePath: item.notePath, files: item.files)
            let where_ = "[\(item.name)]"
            XCTAssertEqual(made.count, item.broken.count, "찾은 수 — \(where_)")
            for (mine, golden) in zip(made, item.broken) {
                XCTAssertEqual(mine.destination, golden.destination, "적힌 그대로 — \(where_)")
                XCTAssertEqual(mine.resolved, golden.resolved, "풀린 경로 — \(where_)")
                XCTAssertEqual(mine.line, golden.line, "몇째 줄 — \(where_)")
                XCTAssertEqual(mine.text, golden.text, "그 줄 — \(where_)")
                XCTAssertEqual(mine.kind.rawValue, golden.kind, "그림인가 — \(where_)")
            }
        }
    }

    /// **찾았다고 한 것은 정말 없는 파일이다.** 멀쩡한 링크를 깨졌다고 하면 사람이
    /// 앱을 못 믿는다.
    func testEveryFindingIsReallyMissing() throws {
        for item in try Self.load().brokenCases {
            for broken in BrokenLinks.find(in: item.text, notePath: item.notePath,
                                           files: item.files) {
                XCTAssertFalse(item.files.contains(broken.resolved),
                               "있는 파일을 깨졌다고 했다 — [\(item.name)] \(broken.resolved)")
            }
        }
    }

    /// **줄 번호가 진짜 그 줄을 가리킨다.** 사람이 찾아가야 하는 값이다.
    func testLineNumbersPointAtTheRightLine() throws {
        for item in try Self.load().brokenCases {
            let lines = item.text.components(separatedBy: "\n")
            for broken in BrokenLinks.find(in: item.text, notePath: item.notePath,
                                           files: item.files) {
                guard broken.line >= 1, broken.line <= lines.count else {
                    XCTFail("줄 번호가 글 밖이다 — [\(item.name)] \(broken.line)"); continue
                }
                XCTAssertEqual(lines[broken.line - 1].trimmingCharacters(in: .whitespaces),
                               broken.text, "줄 번호가 딴 줄을 가리킨다 — [\(item.name)]")
            }
        }
    }

    /// **금고를 모르면 아무것도 안 찾는다.** 아직 못 읽었을 때 *다 깨졌다* 고 말하는 것이
    /// 가장 나쁘다.
    func testNoFilesMeansNoFindings() {
        XCTAssertTrue(BrokenLinks.find(in: "[표](assets/없는표.pdf)",
                                       notePath: "노트.md", files: []).isEmpty)
    }

    /// **바깥 주소는 우리 몫이 아니다.** 인터넷이 끊겼는지까지 앱이 알 수는 없다.
    func testExternalLinksAreNotOurs() {
        let text = "[사이트](https://example.com) [메일](mailto:a@b.c) [절대](/etc/hosts)"
        XCTAssertTrue(BrokenLinks.find(in: text, notePath: "노트.md",
                                       files: ["노트.md"]).isEmpty)
    }
}
