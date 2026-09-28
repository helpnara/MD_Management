import XCTest
@testable import Core

/// **붙여넣은 글의 상대 링크를 이 노트 기준으로** (144, 사용자 제안 —
/// *A 폴더 노트의 링크를 B 폴더 노트에 붙이면 동작하지 않는다*).
///
/// **앱이 본문을 고치는 두 번째 자리다** (첫째는 노트를 옮길 때 · T1). 그래서 규칙을 좁게
/// 둔다 — **여기서 안 맞으면서 금고 어딘가에 딱 하나만 있는** 링크만 고친다.
/// 짐작해서 고치면 엉뚱한 파일을 가리키게 되고, 그것이 가장 나쁘다.
final class PasteGoldenTests: XCTestCase {

    struct Golden: Decodable {
        struct Case: Decodable {
            let name: String
            let text: String
            let noteFolder: String
            let files: [String]
            let repaired: String
            let fixed: Int
        }
        let pasteCases: [Case]
    }

    static func load() throws -> Golden {
        let here = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let url = here.appendingPathComponent("Golden/expected.json")
        return try JSONDecoder().decode(Golden.self, from: try Data(contentsOf: url))
    }

    func testMatchesGolden() throws {
        for item in try Self.load().pasteCases {
            let made = MarkdownLinks.repaired(pasted: item.text, noteFolder: item.noteFolder,
                                              files: item.files)
            XCTAssertEqual(made.text, item.repaired, "고친 글 — [\(item.name)]")
            XCTAssertEqual(made.fixed, item.fixed, "고친 수 — [\(item.name)]")
        }
    }

    /// **고친 링크는 정말 그 파일에 닿는다.** 경로만 그럴듯하면 아무 소용이 없다.
    func testRepairedLinksReachTheFile() throws {
        for item in try Self.load().pasteCases where item.fixed > 0 {
            for link in MarkdownLinks.extract(from: item.repaired) {
                let note = item.noteFolder.isEmpty ? "노트.md" : item.noteFolder + "/노트.md"
                guard case .relative(let path) = Paths.resolve(link: link.destination,
                                                               fromNoteAt: note) else { continue }
                XCTAssertTrue(item.files.contains(path),
                              "고쳤는데 없는 파일을 가리킨다 — [\(item.name)] \(path)")
            }
        }
    }

    /// **고칠 것이 없으면 글자 하나 안 건드린다.** 앱이 본문을 함부로 고치지 않는다.
    func testUntouchedWhenNothingToFix() throws {
        for item in try Self.load().pasteCases where item.fixed == 0 {
            XCTAssertEqual(item.repaired, item.text, "안 고쳐야 하는데 바뀌었다 — [\(item.name)]")
        }
    }

    /// **금고를 모르면 아무것도 안 고친다.** 목록이 아직 안 읽혔을 때의 안전한 쪽이다.
    func testNoFilesMeansNoChange() {
        let made = MarkdownLinks.repaired(pasted: "[표](assets/표.pdf)", noteFolder: "B", files: [])
        XCTAssertEqual(made.text, "[표](assets/표.pdf)")
        XCTAssertEqual(made.fixed, 0)
    }

    /// **여럿이면 손대지 않는다.** 어느 것인지 우리가 알 수 없다.
    func testAmbiguousIsLeftAlone() {
        let made = MarkdownLinks.repaired(pasted: "[표](assets/표.pdf)", noteFolder: "B",
                                          files: ["A/assets/표.pdf", "C/assets/표.pdf"])
        XCTAssertEqual(made.fixed, 0)
    }
}
