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
        struct Active: Decodable {
            let bold: Bool
            let italic: Bool
            let strikethrough: Bool
            let quote: Bool
            let code: Bool
        }
        struct Case: Decodable {
            let name: String
            let op: String
            let text: String
            let start: Int
            let length: Int
            let edit: Edit
            let applied: String
            let activeBefore: Active
            let activeAfter: Active
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

    /// **눌린 모습과 실제 동작이 갈리지 않는다** (128).
    ///
    /// 띠가 `굵게` 를 눌린 채로 그리는데 눌러도 안 풀리면, 사람은 앱을 못 믿게 된다.
    /// 그래서 판정(`active`)과 동작(`toggle`)이 **같은 훑기**를 쓰는지를 여기서 지킨다.
    func testActiveMatchesGolden() throws {
        for item in try Self.load().formatCases {
            let before = Formatting.active(in: item.text, start: item.start, length: item.length)
            assertSame(before, item.activeBefore, "누르기 전 — [\(item.name)]")

            let after = Formatting.active(in: item.applied,
                                          start: item.edit.selectionStart,
                                          length: item.edit.selectionLength)
            assertSame(after, item.activeAfter, "누른 뒤 — [\(item.name)]")
        }
    }

    /// **누르면 상태가 뒤집힌다.** 감싸기 세 가지에만 해당한다.
    func testPressingFlipsTheState() throws {
        for item in try Self.load().formatCases {
            guard ["bold", "italic", "strikethrough"].contains(item.op),
                  item.edit.selectionLength > 0 else { continue }
            let before = value(item.activeBefore, item.op)
            let after = value(item.activeAfter, item.op)
            XCTAssertNotEqual(before, after, "누른 뒤에도 그대로다 — [\(item.name)]")
        }
    }

    /// **걸었다 풀면 처음으로 돌아온다.** 감싸기 세 가지에만 해당한다 —
    /// 빈칸이 딸려 온 선택은 물러나서 감싸므로 고른 자리가 달라진다.
    func testToggleRoundTrips() throws {
        for item in try Self.load().formatCases {
            guard let wrap = Formatting.Wrap(rawValue: marker(item.op)) else { continue }
            let first = try edit(for: item)
            guard first.selectionLength > 0 else { continue }
            // 코드 단추가 약속하는 되돌아오기는 **감싼 것을 풀면 제자리** 다. 푼 쪽에서 다시
            // 누르면 한 줄짜리 안쪽은 울타리가 아니라 역따옴표로 감싸인다 — 그것이 맞는
            // 동작이므로, 첫 누르기가 **글자를 뺀** 코드 사례는 여기서 안 본다.
            if item.op == "code", (first.text as NSString).length < first.length { continue }
            let applied = apply(first, to: item.text)
            // 코드는 **같은 단추**로 다시 누른다 — 울타리는 `toggle` 이 아니라 `toggleCode` 가 푼다.
            let second = item.op == "code"
                ? Formatting.toggleCode(in: applied, start: first.selectionStart,
                                        length: first.selectionLength)
                : Formatting.toggle(wrap, in: applied,
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
        case "code":
            return Formatting.toggleCode(in: item.text, start: item.start, length: item.length)
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
        case "code": return "`"
        default: return ""
        }
    }

    private func assertSame(_ made: Formatting.Active, _ golden: Golden.Active, _ where_: String) {
        XCTAssertEqual(made.bold, golden.bold, "굵게 — \(where_)")
        XCTAssertEqual(made.italic, golden.italic, "기울임 — \(where_)")
        XCTAssertEqual(made.code, golden.code, "코드 — \(where_)")
        XCTAssertEqual(made.strikethrough, golden.strikethrough, "취소선 — \(where_)")
        XCTAssertEqual(made.quote, golden.quote, "인용 — \(where_)")
    }

    private func value(_ active: Golden.Active, _ op: String) -> Bool {
        switch op {
        case "bold": return active.bold
        case "italic": return active.italic
        case "strikethrough": return active.strikethrough
        default: return active.quote
        }
    }

    private func apply(_ edit: Formatting.Edit, to text: String) -> String {
        let units = Array(text.utf16)
        let head = String(decoding: units[0..<edit.start], as: UTF16.self)
        let tail = String(decoding: units[(edit.start + edit.length)...], as: UTF16.self)
        return head + edit.text + tail
    }
}
