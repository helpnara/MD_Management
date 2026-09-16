import XCTest
@testable import Core

/// 고정된 노트 (빌드 35 · T10).
///
/// 기댓값은 `Tools/golden/generate.py` 가 같은 규칙을 파이썬으로 다시 구현해 계산한다.
final class PinGoldenTests: XCTestCase {

    struct Golden: Decodable {
        struct Case: Decodable {
            let name: String
            let pins: [String]
            let tidied: [String]
            let merge: [String]?
            let merged: [String]?
            let from: String?
            let to: String?
            let followed: [String]?
            let gone: String?
            let removed: [String]?
        }
        let pinCases: [Case]
    }

    static func load() throws -> Golden {
        let here = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let url = here.appendingPathComponent("Golden/expected.json")
        return try JSONDecoder().decode(Golden.self, from: try Data(contentsOf: url))
    }

    func testMatchesGolden() throws {
        for item in try Self.load().pinCases {
            let where_ = "[\(item.name)]"
            XCTAssertEqual(Pins.tidy(item.pins), item.tidied, "고르기 — \(where_)")
            if let merge = item.merge, let merged = item.merged {
                XCTAssertEqual(Pins.merged(item.pins, merge), merged, "합치기 — \(where_)")
            }
            if let from = item.from, let to = item.to, let followed = item.followed {
                XCTAssertEqual(Pins.following(item.pins, from: from, to: to), followed,
                               "따라가기 — \(where_)")
            }
            if let gone = item.gone, let removed = item.removed {
                XCTAssertEqual(Pins.removing(item.pins, at: gone), removed, "빼기 — \(where_)")
            }
        }
    }

    /// **적었다가 읽으면 그대로다.** 고정은 자료가 아니지만, 잃으면 사용자가 다시 해야 한다.
    func testRoundTripsThroughFile() throws {
        for item in try Self.load().pinCases {
            let tidied = Pins.tidy(item.pins)
            XCTAssertEqual(Pins.decode(Pins.encode(tidied)), tidied, "[\(item.name)]")
        }
    }

    /// **깨진 파일은 빈 목록이다 — 죽지 않는다.** 고정을 잃어도 노트는 그대로다.
    func testBrokenFileIsEmptyNotACrash() {
        XCTAssertEqual(Pins.decode(Data()), [])
        XCTAssertEqual(Pins.decode(Data("{ 망가진".utf8)), [])
        XCTAssertEqual(Pins.decode(Data("{\"a\":1}".utf8)), [])
    }

    /// **합치기는 어느 쪽을 먼저 놓아도 같은 것을 담는다** (두 기기가 부딪힐 때).
    func testMergeIsTheSameSetEitherWay() throws {
        for item in try Self.load().pinCases {
            guard let merge = item.merge else { continue }
            XCTAssertEqual(Set(Pins.merged(item.pins, merge)),
                           Set(Pins.merged(merge, item.pins)), "[\(item.name)]")
        }
    }

    /// 숨김 자리에 둔다 — 노트 목록에 안 보여야 한다.
    func testLivesInAHiddenFolder() {
        XCTAssertTrue(Pins.folder.hasPrefix("."), "숨김 폴더여야 목록에서 빠진다")
        XCTAssertTrue(Pins.fileName.hasPrefix(Pins.folder + "/"))
    }
}
