import XCTest
@testable import Core

/// 노트 위치에서 목표 파일로 가는 **상대 링크** (빌드 34 · 108).
///
/// 기댓값은 `Tools/golden/generate.py` 가 같은 규칙을 파이썬으로 다시 구현해 계산한다.
/// **되돌아오는지까지 견준다** — `join(노트 폴더, 링크)` 가 목표와 같아야 링크가 산다.
final class RelativeLinkGoldenTests: XCTestCase {

    struct Golden: Decodable {
        struct Case: Decodable {
            let name: String
            let folder: String
            let target: String
            let link: String
            let resolved: String?
        }
        let linkCases: [Case]
    }

    static func load() throws -> Golden {
        let here = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let url = here.appendingPathComponent("Golden/expected.json")
        return try JSONDecoder().decode(Golden.self, from: try Data(contentsOf: url))
    }

    func testMatchesGolden() throws {
        for item in try Self.load().linkCases {
            XCTAssertEqual(Paths.relativeLink(from: item.folder, to: item.target), item.link,
                           "[\(item.name)] \(item.folder) → \(item.target)")
        }
    }

    /// **링크는 되돌아와야 산다.** 파이썬이 `join` 으로 되돌린 값과, 우리 `join` 의 값과,
    /// 애초의 목표가 셋 다 같아야 한다.
    func testRoundTripsThroughJoin() throws {
        for item in try Self.load().linkCases {
            let link = Paths.relativeLink(from: item.folder, to: item.target)
            XCTAssertEqual(Paths.join(base: item.folder, relative: link), item.target,
                           "되돌아오지 않는다 — [\(item.name)]")
            XCTAssertEqual(item.resolved, item.target, "파이썬 쪽도 되돌아와야 한다 — [\(item.name)]")
        }
    }

    /// 링크를 실제로 푸는 길(`resolve`)로도 같은 자리에 닿는다.
    func testResolveReachesTheSameFile() throws {
        for item in try Self.load().linkCases {
            let notePath = item.folder.isEmpty ? "노트.md" : item.folder + "/노트.md"
            let link = Paths.relativeLink(from: item.folder, to: item.target)
            XCTAssertEqual(Paths.resolve(link: link, fromNoteAt: notePath), .relative(item.target),
                           "[\(item.name)] \(link)")
        }
    }
}
