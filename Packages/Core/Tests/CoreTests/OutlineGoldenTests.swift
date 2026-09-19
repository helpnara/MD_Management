import XCTest
@testable import Core

/// **개요에서 항목을 한 칸 미는 일** (148 · 150).
///
/// 세 번을 같은 자리에서 걸렸다.
/// 1. 붙을 자리를 **바로 위 줄**로 봐서 두 단계가 들어갔다 (148).
/// 2. 딸린 줄을 두고 가서 **자식이 형제가 됐다** (148).
/// 3. 딸린 줄을 **한 줄 덜** 데려갔다 (150, 사용자 · 빌드 45 —
///    *모델링은 따라오는데 시스템화는 못 따라온다*).
///
/// 셋째는 **시험이 닿지 못하는 곳**에 있었다 — 줄 차례를 글자 자리로 바꾸는 셈이
/// 편집기 쪽에 흩어져 있었다. 이제 그 셈까지 Core 에 있고(`plan` · `offset`) 여기서 지킨다.
final class OutlineGoldenTests: XCTestCase {

    struct Golden: Decodable {
        struct Case: Decodable {
            let name: String
            let lines: [String]
            let at: Int
            let subtreeEnd: Int
            let parent: String?
            let offsets: [Int]
            let applied: String?
            let roundTrip: String?
        }
        let outlineCases: [Case]
    }

    static func load() throws -> Golden {
        let here = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let url = here.appendingPathComponent("Golden/expected.json")
        return try JSONDecoder().decode(Golden.self, from: try Data(contentsOf: url))
    }

    func testPlanMatchesGolden() throws {
        for item in try Self.load().outlineCases {
            let move = ListEditing.plan(movingFrom: item.at, count: 1, in: item.lines)
            let where_ = "[\(item.name)]"
            XCTAssertEqual(move.first, item.at, "움직일 첫 줄 — \(where_)")
            XCTAssertEqual(move.end, item.subtreeEnd, "딸린 줄의 끝 — \(where_)")
            XCTAssertEqual(move.parent, item.parent, "붙을 자리 — \(where_)")
        }
    }

    /// **줄 차례를 글자 자리로 바꾸는 셈.** 여기서 한 칸이 어긋나 딸린 줄을 덜 데려갔다 (150).
    func testOffsetsMatchGolden() throws {
        for item in try Self.load().outlineCases {
            for index in 0...item.lines.count {
                XCTAssertEqual(ListEditing.offset(ofLine: index, in: item.lines),
                               item.offsets[index],
                               "줄 \(index) 의 자리 — [\(item.name)]")
            }
        }
    }

    /// **옮길 구간이 딸린 줄을 빠짐없이 덮는다.** 끝 자리에서 마지막 줄바꿈만 뺀다.
    func testMovedRangeCoversEveryChild() throws {
        for item in try Self.load().outlineCases {
            let move = ListEditing.plan(movingFrom: item.at, count: 1, in: item.lines)
            let from = ListEditing.offset(ofLine: move.first, in: item.lines)
            let to = ListEditing.offset(ofLine: move.end, in: item.lines)
            let whole = item.lines.joined(separator: "\n") + "\n"
            let units = Array(whole.utf16)
            guard from <= to, to <= units.count else {
                XCTFail("구간이 글 밖으로 나갔다 — [\(item.name)]"); continue
            }
            var piece = String(decoding: units[from..<to], as: UTF16.self)
            if piece.hasSuffix("\n") { piece.removeLast() }
            XCTAssertEqual(piece, item.lines[move.first..<move.end].joined(separator: "\n"),
                           "옮길 글 — [\(item.name)]")
        }
    }

    /// **딱 한 단계만 깊어진다.**
    func testMovesExactlyOneLevel() throws {
        for item in try Self.load().outlineCases {
            guard let applied = item.applied else { continue }
            let before = ListEditing.depths(in: item.lines)
            let after = ListEditing.depths(in: applied.components(separatedBy: "\n"))
            guard before.indices.contains(item.at), after.indices.contains(item.at) else { continue }
            XCTAssertEqual(abs(after[item.at] - before[item.at]), 1,
                           "한 단계가 아니다 — [\(item.name)]")
        }
    }

    /// **딸린 줄은 함께 가고, 딸린 줄이 아닌 것은 그대로다.**
    func testChildrenComeAlongAndOthersStay() throws {
        for item in try Self.load().outlineCases {
            guard let applied = item.applied else { continue }
            let before = ListEditing.depths(in: item.lines)
            let after = ListEditing.depths(in: applied.components(separatedBy: "\n"))
            guard before.indices.contains(item.at), after.indices.contains(item.at) else { continue }
            let step = after[item.at] - before[item.at]
            for index in (item.at + 1)..<item.subtreeEnd where after.indices.contains(index) {
                XCTAssertEqual(after[index] - before[index], step,
                               "딸린 줄이 따라오지 않았다 — [\(item.name)] \(item.lines[index])")
            }
            for index in item.subtreeEnd..<item.lines.count where after.indices.contains(index) {
                XCTAssertEqual(after[index], before[index],
                               "남의 줄까지 움직였다 — [\(item.name)] \(item.lines[index])")
            }
        }
    }

    /// **밀었다 당기면 제자리다.** 사용자가 걸린 자리다 — 시스템화만 못 돌아왔다.
    func testRoundTripReturns() throws {
        for item in try Self.load().outlineCases {
            guard let back = item.roundTrip else { continue }
            XCTAssertEqual(ListEditing.depths(in: back.components(separatedBy: "\n")),
                           ListEditing.depths(in: item.lines),
                           "도로 당겼더니 제자리가 아니다 — [\(item.name)]")
        }
    }

    /// **위가 없으면 붙을 형제도 없다.**
    func testFirstItemHasNoSibling() {
        XCTAssertNil(ListEditing.parentForIndent(of: "- 첫째", above: []))
        XCTAssertNil(ListEditing.parentForIndent(of: "  - 안쪽", above: ["    - 더 깊은 줄"]),
                     "나보다 깊은 줄은 형제가 아니다")
    }
}
