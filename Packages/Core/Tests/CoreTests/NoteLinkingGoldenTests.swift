import XCTest
@testable import Core

/// **타이핑으로 노트 연결하기** (147, 2026-09-18 사용자 — 아이폰 메모처럼).
///
/// 기댓값은 `Tools/golden/generate.py` 가 같은 규칙을 파이썬으로 다시 구현해 계산하고,
/// **넣은 글이 정말 링크로 읽히는지**를 심판 둘(markdown-it · cmark-gfm)에게 물어 본 것이다.
final class NoteLinkingGoldenTests: XCTestCase {

    struct Golden: Decodable {
        struct Query: Decodable {
            let start: Int
            let length: Int
            let text: String
            let trigger: String
        }
        struct Edit: Decodable {
            let start: Int
            let length: Int
            let text: String
            let selectionStart: Int
            let selectionLength: Int
        }
        struct Pick: Decodable {
            let title: String
            let path: String
        }
        struct Case: Decodable {
            let name: String
            let text: String
            let caret: Int
            let noteFolder: String
            let pick: Pick?
            let query: Query?
            let edit: Edit?
            let applied: String?
            /// 방아쇠 없이 **커서 자리에** 넣었을 때 (145 — 메뉴에서 고르는 길).
            let menuEdit: Edit?
            let menuApplied: String?
        }
        let linkTriggerCases: [Case]
    }

    static func load() throws -> Golden {
        let here = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let url = here.appendingPathComponent("Golden/expected.json")
        return try JSONDecoder().decode(Golden.self, from: try Data(contentsOf: url))
    }

    func testMatchesGolden() throws {
        for item in try Self.load().linkTriggerCases {
            let made = NoteLinking.query(in: item.text, caret: item.caret)
            let where_ = "[\(item.name)] \(item.text)"
            guard let golden = item.query else {
                XCTAssertNil(made, "방아쇠가 아닌데 잡았다 — \(where_)")
                continue
            }
            let found = try XCTUnwrap(made, "방아쇠를 놓쳤다 — \(where_)")
            XCTAssertEqual(found.start, golden.start, "방아쇠 자리 — \(where_)")
            XCTAssertEqual(found.length, golden.length, "덮을 길이 — \(where_)")
            XCTAssertEqual(found.text, golden.text, "찾을 말 — \(where_)")
            XCTAssertEqual(found.trigger.rawValue, golden.trigger, "방아쇠 글자 — \(where_)")
        }
    }

    func testInsertedLinkMatchesGolden() throws {
        for item in try Self.load().linkTriggerCases {
            guard let pick = item.pick, let golden = item.edit,
                  let found = NoteLinking.query(in: item.text, caret: item.caret) else { continue }
            let made = NoteLinking.link(to: pick.title, path: pick.path,
                                        from: item.noteFolder, replacing: found)
            let where_ = "[\(item.name)]"
            XCTAssertEqual(made.start, golden.start, "바꿀 자리 — \(where_)")
            XCTAssertEqual(made.length, golden.length, "바꿀 길이 — \(where_)")
            XCTAssertEqual(made.text, golden.text, "넣을 링크 — \(where_)")
            XCTAssertEqual(made.selectionStart, golden.selectionStart, "커서 자리 — \(where_)")
            XCTAssertEqual(apply(made, to: item.text), item.applied, "바꾼 뒤 글 — \(where_)")
        }
    }

    /// **방아쇠 글자는 파일에 남지 않는다** (ADR-0001). `>>` 나 `[[` 가 그대로 저장되면
    /// 옵시디언 말고는 아무 데서도 안 열린다.
    func testTriggerNeverReachesTheFile() throws {
        for item in try Self.load().linkTriggerCases {
            guard let applied = item.applied else { continue }
            XCTAssertFalse(applied.contains(">>"), "`>>` 가 파일에 남았다 — [\(item.name)]")
            XCTAssertFalse(applied.contains("[["), "`[[` 가 파일에 남았다 — [\(item.name)]")
        }
    }

    /// **줄 맨 앞의 `>>` 는 인용이다.** 도구 띠의 인용 버튼이 만드는 글자와 겹치므로
    /// 방아쇠로 쓰지 않는다. `[[` 는 그런 겹침이 없어 어디서든 된다.
    func testChevronsAtLineStartStayAQuote() {
        XCTAssertNil(NoteLinking.query(in: ">>인용", caret: 4))
        XCTAssertNil(NoteLinking.query(in: "  >>인용", caret: 6))
        XCTAssertNil(NoteLinking.query(in: "첫 줄\n>>인용", caret: 8))
        XCTAssertNotNil(NoteLinking.query(in: "[[회의", caret: 4), "대괄호는 줄 맨 앞에서도 된다")
    }

    /// **빈칸은 찾는 말에 그대로 넣는다.** 제목에 빈칸이 흔하다 (`9월 회의록`) —
    /// 빈칸에서 멈추면 그런 제목을 영영 못 찾는다.
    func testSpacesStayInTheQuery() throws {
        let found = try XCTUnwrap(NoteLinking.query(in: "메모 >>9월 회의", caret: 11))
        XCTAssertEqual(found.text, "9월 회의")
    }

    /// **방아쇠가 없어도 넣을 수 있다** (145, 사용자 · 빌드 46 —
    /// *파일을 선택해도 링크가 들어가지 않는다*).
    ///
    /// 넣는 길이 `>>` · `[[` 를 **요구**하고 있어서, 메뉴에서 고르는 길이 통째로 먹통이었다.
    /// 타이핑으로 부르면 친 글자를 덮고, 메뉴에서 고르면 **덮을 것이 없다** — 그때는 커서
    /// 자리에 그냥 넣는다.
    func testInsertsWithoutATrigger() throws {
        for item in try Self.load().linkTriggerCases {
            guard let pick = item.pick, let golden = item.menuEdit else { continue }
            let made = NoteLinking.link(to: pick.title, path: pick.path,
                                        from: item.noteFolder, start: item.caret, length: 0)
            let where_ = "[\(item.name)]"
            XCTAssertEqual(made.start, golden.start, "넣을 자리 — \(where_)")
            XCTAssertEqual(made.length, golden.length, "덮을 길이 — \(where_)")
            XCTAssertEqual(made.text, golden.text, "넣을 링크 — \(where_)")
            XCTAssertEqual(apply(made, to: item.text), item.menuApplied, "넣은 뒤 글 — \(where_)")
        }
    }

    /// **덮을 것이 없으면 아무 글자도 지우지 않는다.** 길이 0 이면 순수하게 끼워 넣는다.
    func testInsertingKeepsEveryLetter() throws {
        for item in try Self.load().linkTriggerCases {
            guard let pick = item.pick, let menu = item.menuApplied else { continue }
            let made = NoteLinking.link(to: pick.title, path: pick.path,
                                        from: item.noteFolder, start: item.caret, length: 0)
            XCTAssertEqual(menu.utf16.count, item.text.utf16.count + made.text.utf16.count,
                           "글자가 사라지거나 늘었다 — [\(item.name)]")
        }
    }

    private func apply(_ edit: Formatting.Edit, to text: String) -> String {
        let units = Array(text.utf16)
        let head = String(decoding: units[0..<edit.start], as: UTF16.self)
        let tail = String(decoding: units[(edit.start + edit.length)...], as: UTF16.self)
        return head + edit.text + tail
    }
}
