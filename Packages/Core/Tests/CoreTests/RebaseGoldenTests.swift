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
                // **폴더 밖을 가리키던 링크는 견줄 수 없다.** 그런 링크는 그대로 두는데,
                // 노트가 옮겨지면 같은 글자가 다른 자리를 가리키게 된다 (`../바깥.png` 이
                // 최상위에서는 폴더 밖이지만 `회의/` 에서는 폴더 안이다). 우리가 풀 수 없는
                // 링크라 고치지도 않는다 — 그것이 맞다. 견주는 것은 **풀 수 있던 링크**뿐이다.
                guard case .relative = was else { continue }
                XCTAssertEqual(was, now, "가리키는 자리가 달라졌다 — [\(item.name)]")
            }
        }
    }

    /// 옮겼다가 도로 옮기면 처음 글로 돌아온다.
    func testMoveBackRoundTrips() throws {
        for item in try Self.load().rebaseCases {
            let moved = MarkdownLinks.rebased(item.text, from: item.from, to: item.to)
            let back = MarkdownLinks.rebased(moved, from: item.to, to: item.from)
            // 두 가지는 되돌아오지 않는 것이 맞다:
            // · 빈칸 이름은 `<>` 가 붙어 돌아온다 (링크는 살아 있다)
            // · 폴더 밖을 가리키던 링크는 옮긴 자리에서 폴더 안이 되어 한 번 고쳐진다
            let escapes = MarkdownLinks.extract(from: item.text).contains { $0.destination.contains("..") }
            if !escapes, item.text.contains("<") || !item.text.contains(" ") || item.from == item.to {
                XCTAssertEqual(back, item.text, "되돌아오지 않는다 — [\(item.name)]")
            }
        }
    }
}
