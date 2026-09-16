import XCTest
@testable import Core

/// 노트를 다른 폴더로 옮길 때 **링크를 새 자리에 맞춰 고친다** (빌드 34 · T1).
///
/// 기댓값은 `Tools/golden/generate.py` 가 같은 규칙을 파이썬으로 다시 구현해 계산한다.
final class RebaseGoldenTests: XCTestCase {

    struct Golden: Decodable {
        struct Case: Decodable {
            let name: String
            let text: String
            let from: String
            let to: String
            let rebased: String
        }
        let rebaseCases: [Case]
    }

    static func load() throws -> Golden {
        let here = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let url = here.appendingPathComponent("Golden/expected.json")
        return try JSONDecoder().decode(Golden.self, from: try Data(contentsOf: url))
    }

    func testMatchesGolden() throws {
        for item in try Self.load().rebaseCases {
            XCTAssertEqual(MarkdownLinks.rebased(item.text, from: item.from, to: item.to),
                           item.rebased, "[\(item.name)]")
        }
    }

    /// **고친 링크가 같은 파일에 닿는다.** 옮기기의 전부가 이 한 줄이다 —
    /// 자리는 달라져도 가리키는 파일은 같아야 한다.
    func testLinksStillReachTheSameFiles() throws {
        for item in try Self.load().rebaseCases {
            let oldNote = item.from.isEmpty ? "노트.md" : item.from + "/노트.md"
            let newNote = item.to.isEmpty ? "노트.md" : item.to + "/노트.md"
            let moved = MarkdownLinks.rebased(item.text, from: item.from, to: item.to)

            let before = MarkdownLinks.extract(from: item.text)
                .map { Paths.resolve(link: $0.destination, fromNoteAt: oldNote) }
            let after = MarkdownLinks.extract(from: moved)
                .map { Paths.resolve(link: $0.destination, fromNoteAt: newNote) }

            XCTAssertEqual(before.count, after.count, "링크 수가 달라졌다 — [\(item.name)]")
            for (was, now) in zip(before, after) {
                XCTAssertEqual(was, now, "가리키는 자리가 달라졌다 — [\(item.name)]")
            }
        }
    }

    /// 옮겼다가 도로 옮기면 처음 글로 돌아온다.
    func testMoveBackRoundTrips() throws {
        for item in try Self.load().rebaseCases {
            let moved = MarkdownLinks.rebased(item.text, from: item.from, to: item.to)
            let back = MarkdownLinks.rebased(moved, from: item.to, to: item.from)
            // 빈칸 이름은 `<>` 가 붙어 돌아오므로 그 경우만 빼고 견준다.
            if item.text.contains("<") || !item.text.contains(" ") || item.from == item.to {
                XCTAssertEqual(back, item.text, "되돌아오지 않는다 — [\(item.name)]")
            }
        }
    }
}
