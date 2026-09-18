import XCTest
@testable import Core

/// 편집 도구 띠가 고른 글에 하는 일 (T13 1차 · 127).
///
/// 기댓값은 `Tools/golden/generate.py` 가 **같은 규칙을 파이썬으로 다시 구현해** 계산한다.
/// 게다가 그 파이썬은 **결과를 markdown-it 에게 한 번 더 물어본다** — 우리가 만든 글이
/// 정말 굵게 · 인용 · 표로 읽히는지. 그 심판이 `** 회**`(빈칸이 딸려 온 선택)를 잡았다.
final class FormatGoldenTests: XCTestCase {

    struct Golden: Decodable {
        struct Edit: Decodable {
            let start: Int
            let length: Int
            let text: String
            let selectionStart: Int
            let selectionLength: Int
        }
        struct Case: Decodable {
            let name: String
            let op: String
            let text: String
            let start: Int
            let length: Int
            let edit: Edit
            let applied: String
        }
        let formatCases: [Case]
    }

    static func load() throws -> Golden {
        let here = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let url = here.appendingPathComponent("Golden/expected.json")
        return try JSONDecoder().decode(Golden.self, from: try Data(contentsOf: url))
    }

    func testMatchesGolden() throws {
        for item in try Self.load().formatCases {
            let made = try edit(for: item)
            let where_ = "[\(item.name)]"
            XCTAssertEqual(made.start, item.edit.start, "바꿀 자리 — \(where_)")
            XCTAssertEqual(made.length, item.edit.length, "바꿀 길이 — \(where_)")
            XCTAssertEqual(made.text, item.edit.text, "넣을 글 — \(where_)")
            XCTAssertEqual(made.selectionStart, item.edit.selectionStart, "선택 시작 — \(where_)")
            XCTAssertEqual(made.selectionLength, item.edit.selectionLength, "선택 길이 — \(where_)")
            XCTAssertEqual(apply(made, to: item.text), item.applied, "바꾼 뒤 글 — \(where_)")
        }
    }

    /// **걸었다 풀면 처음으로 돌아온다.** 감싸기 세 가지에만 해당한다 —
    /// 빈칸이 딸려 온 선택은 물러나서 감싸므로 고른 자리가 달라진다.
    func testToggleRoundTrips() throws {
        for item in try Self.load().formatCases {
            guard let wrap = Formatting.Wrap(rawValue: marker(item.op)) else { continue }
            let first = try edit(for: item)
            guard first.selectionLength > 0 else { continue }
            let applied = apply(first, to: item.text)
            let second = Formatting.toggle(wrap, in: applied,
                                           start: first.selectionStart,
                                           length: first.selectionLength)
            XCTAssertEqual(apply(second, to: applied), item.text,
                           "되돌아오지 않는다 — [\(item.name)]")
        }
    }

    // MARK: - 자잘한 것

    private func edit(for item: Golden.Case) throws -> Formatting.Edit {
        switch item.op {
        case "bold", "italic", "strikethrough":
            let wrap = try XCTUnwrap(Formatting.Wrap(rawValue: marker(item.op)))
            return Formatting.toggle(wrap, in: item.text, start: item.start, length: item.length)
        case "quote":
            return Formatting.toggleQuote(in: item.text, start: item.start, length: item.length)
        case "table":
            return Formatting.table(in: item.text, start: item.start)
        default:
            XCTFail("모르는 도구 \(item.op)")
            return Formatting.Edit(start: 0, length: 0, text: "",
                                   selectionStart: 0, selectionLength: 0)
        }
    }

    private func marker(_ op: String) -> String {
        switch op {
        case "bold": return "**"
        case "italic": return "*"
        case "strikethrough": return "~~"
        default: return ""
        }
    }

    private func apply(_ edit: Formatting.Edit, to text: String) -> String {
        let units = Array(text.utf16)
        let head = String(decoding: units[0..<edit.start], as: UTF16.self)
        let tail = String(decoding: units[(edit.start + edit.length)...], as: UTF16.self)
        return head + edit.text + tail
    }
}
