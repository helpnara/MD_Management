import XCTest
@testable import Core

/// 번호 목록을 다시 매길 때 **무엇을 고치나** (빌드 32 · 104).
///
/// 기댓값은 `Tools/golden/generate.py` 가 같은 규칙을 파이썬으로 다시 구현해 계산한다
/// (`Paths` · `ShareBundle` · 들여쓰기와 같은 방식). 손으로 적으면 옮겨 적은 실수를
/// 테스트가 그대로 승인한다.
final class RenumberGoldenTests: XCTestCase {

    struct Golden: Decodable {
        struct Fix: Decodable {
            let start: Int
            let length: Int
            let number: String
        }
        struct Case: Decodable {
            let name: String
            let text: String
            let start: Int?
            let fixes: [Fix]
        }
        struct NumberCase: Decodable {
            let line: String
            let number: Int?
        }
        let renumberCases: [Case]
        let orderedNumberCases: [NumberCase]
    }

    static func load() throws -> Golden {
        let here = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let url = here.appendingPathComponent("Golden/expected.json")
        return try JSONDecoder().decode(Golden.self, from: try Data(contentsOf: url))
    }

    func testMatchesGolden() throws {
        for item in try Self.load().renumberCases {
            let fixes = ListEditing.renumber(item.text, start: item.start)
            let where_ = "[\(item.name)]"
            XCTAssertEqual(fixes.count, item.fixes.count, "고칠 자리 수가 다르다 — \(where_)")
            for (made, want) in zip(fixes, item.fixes) {
                XCTAssertEqual(made.start, want.start, "자리 — \(where_)")
                XCTAssertEqual(made.length, want.length, "옛 숫자 길이 — \(where_)")
                XCTAssertEqual(made.number, want.number, "넣을 숫자 — \(where_)")
            }
        }
    }

    /// **고친 글에는 더 고칠 것이 없다.** 한 번에 끝나야 커서가 덜 흔들린다.
    func testSettlesInOnePass() throws {
        for item in try Self.load().renumberCases {
            var utf16 = Array(item.text.utf16)
            for fix in ListEditing.renumber(item.text, start: item.start).reversed() {
                utf16.replaceSubrange(fix.start..<(fix.start + fix.length), with: Array(fix.number.utf16))
            }
            let fixed = String(decoding: utf16, as: UTF16.self)
            XCTAssertTrue(ListEditing.renumber(fixed).isEmpty, "두 번 돌아야 맞는다 — [\(item.name)] \(fixed)")
        }
    }

    /// 번호 읽기 (192) — 편집기가 지우기 전의 첫 번호를 이것으로 적는다.
    func testOrderedNumberMatchesGolden() throws {
        let cases = try Self.load().orderedNumberCases
        XCTAssertFalse(cases.isEmpty)
        for item in cases {
            XCTAssertEqual(ListEditing.orderedNumber(item.line), item.number, "[\(item.line)]")
        }
    }
}
