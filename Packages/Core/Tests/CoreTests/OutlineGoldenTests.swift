import XCTest
@testable import Core

/// **개요에서 항목을 한 칸 미는 일** (148, 사용자 · 빌드 44 —
/// *2. 데이터 검증 밑에 3. EDA 가 되어야 하는데 두 단계가 들어가 버린다*).
///
/// 두 가지가 얽혀 있었다.
/// 1. 붙을 자리를 **바로 위 줄**로 봤다. 그 줄이 나보다 깊으면 두 단계가 들어간다 —
///    개요에서는 **앞 형제**의 자식이 되는 것이 맞다.
/// 2. 딸린 줄을 두고 갔다. 부모만 움직이면 **자식이 형제가 된다.**
///
/// 기댓값은 파이썬이 다시 계산하고, 심판 둘이 **딱 한 단계만** 움직였는지와
/// **딸린 줄이 함께 갔는지**를 본다.
final class OutlineGoldenTests: XCTestCase {

    struct Golden: Decodable {
        struct Shift: Decodable {
            let text: String
            let firstLineDelta: Int
        }
        struct Case: Decodable {
            let name: String
            let lines: [String]
            let at: Int
            let subtreeEnd: Int
            let parent: String?
            let shifted: Shift?
            let applied: String?
        }
        let outlineCases: [Case]
    }

    static func load() throws -> Golden {
        let here = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let url = here.appendingPathComponent("Golden/expected.json")
        return try JSONDecoder().decode(Golden.self, from: try Data(contentsOf: url))
    }

    func testSubtreeEndMatchesGolden() throws {
        for item in try Self.load().outlineCases {
            XCTAssertEqual(ListEditing.subtreeEnd(from: item.at, in: item.lines), item.subtreeEnd,
                           "딸린 줄의 끝 — [\(item.name)]")
        }
    }

    func testParentMatchesGolden() throws {
        for item in try Self.load().outlineCases {
            let end = ListEditing.subtreeEnd(from: item.at, in: item.lines)
            let block = item.lines[item.at..<end].joined(separator: "\n")
            let above = Array(item.lines.prefix(item.at))
            XCTAssertEqual(ListEditing.parentForIndent(of: block, above: above), item.parent,
                           "붙을 자리 — [\(item.name)]")
        }
    }

    /// **딱 한 단계만 깊어진다.** 두 단계가 들어가면 개요가 무너진다.
    func testMovesExactlyOneLevel() throws {
        for item in try Self.load().outlineCases {
            guard let applied = item.applied else { continue }
            let before = ListEditing.depths(in: item.lines)
            let after = ListEditing.depths(in: applied.components(separatedBy: "\n"))
            guard before.indices.contains(item.at), after.indices.contains(item.at) else { continue }
            let step = after[item.at] - before[item.at]
            XCTAssertEqual(abs(step), 1, "한 단계가 아니다 — [\(item.name)] \(step)")
        }
    }

    /// **딸린 줄이 같이 간다.** 부모만 움직이면 자식이 형제가 된다.
    func testChildrenComeAlong() throws {
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
        }
    }

    /// **위가 없으면 붙을 형제도 없다.** 목록의 첫 항목은 밀 데가 없다.
    func testFirstItemHasNoSibling() {
        XCTAssertNil(ListEditing.parentForIndent(of: "- 첫째", above: []))
        XCTAssertNil(ListEditing.parentForIndent(of: "  - 안쪽", above: ["    - 더 깊은 줄"]),
                     "나보다 깊은 줄은 형제가 아니다")
    }
}
