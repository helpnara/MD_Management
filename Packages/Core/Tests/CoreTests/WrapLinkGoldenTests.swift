import XCTest
@testable import Core

/// **고른 글이 링크의 이름이 된다** (152, 빌드 47 · 4번에서 드러남).
///
/// 워드 · 노션 · 옵시디언이 다 그렇다. 고른 글을 지우고 파일 이름을 넣으면
/// **사람이 친 글자가 조용히 사라진다.**
final class WrapLinkGoldenTests: XCTestCase {

    struct Golden: Decodable {
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
            let start: Int
            let length: Int
            let noteFolder: String
            let pick: Pick
            let edit: Edit
            let applied: String
        }
        let wrapCases: [Case]
    }

    static func load() throws -> Golden {
        let here = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let url = here.appendingPathComponent("Golden/expected.json")
        return try JSONDecoder().decode(Golden.self, from: try Data(contentsOf: url))
    }

    func testMatchesGolden() throws {
        for item in try Self.load().wrapCases {
            let made = NoteLinking.link(to: item.pick.title, path: item.pick.path,
                                        from: item.noteFolder, wrapping: item.start,
                                        length: item.length, in: item.text)
            let where_ = "[\(item.name)]"
            XCTAssertEqual(made.start, item.edit.start, "바꿀 자리 — \(where_)")
            XCTAssertEqual(made.length, item.edit.length, "바꿀 길이 — \(where_)")
            XCTAssertEqual(made.text, item.edit.text, "넣을 링크 — \(where_)")
            XCTAssertEqual(apply(made, to: item.text), item.applied, "바꾼 뒤 글 — \(where_)")
        }
    }

    /// **고른 글자가 사라지지 않는다.** 152 가 고치려는 바로 그 일이다.
    func testTheChosenWordsSurvive() throws {
        for item in try Self.load().wrapCases {
            let units = Array(item.text.utf16)
            let to = min(item.start + item.length, units.count)
            guard item.start < to else { continue }
            let picked = String(decoding: units[item.start..<to], as: UTF16.self)
                .trimmingCharacters(in: .whitespaces)
            guard !picked.isEmpty, !picked.contains("\n") else { continue }
            let escaped = picked.reduce(into: "") { out, character in
                if character == "[" || character == "]" || character == "\\" { out.append("\\") }
                out.append(character)
            }
            XCTAssertTrue(item.applied.contains(picked) || item.applied.contains(escaped),
                          "고른 글이 사라졌다 — [\(item.name)] \(picked)")
        }
    }

    /// **줄을 넘어 고르면 한 글자도 안 지운다.** 줄바꿈이 든 이름은 링크를 깨뜨린다.
    func testMultilineSelectionDeletesNothing() {
        let text = "첫 줄\n둘째 줄"
        let made = NoteLinking.link(to: "회의록", path: "회의록.md", from: "",
                                    wrapping: 1, length: 6, in: text)
        XCTAssertEqual(made.length, 0, "지우면 안 된다")
        XCTAssertTrue(apply(made, to: text).contains("첫"), "앞 글자가 남아야 한다")
        XCTAssertTrue(apply(made, to: text).contains("둘째 줄"), "뒷줄이 남아야 한다")
    }

    /// **고른 것이 빈칸뿐이면 파일 이름을 쓴다.**
    func testBlankSelectionFallsBackToTheTitle() {
        let made = NoteLinking.link(to: "목돈 배치", path: "자료/목돈 배치.md", from: "",
                                    wrapping: 4, length: 1, in: "이 문서는 체크리스트 입니다")
        XCTAssertTrue(made.text.hasPrefix("[목돈 배치]"), "파일 이름이 아니다 — \(made.text)")
    }

    private func apply(_ edit: Formatting.Edit, to text: String) -> String {
        let units = Array(text.utf16)
        let head = String(decoding: units[0..<edit.start], as: UTF16.self)
        let tail = String(decoding: units[(edit.start + edit.length)...], as: UTF16.self)
        return head + edit.text + tail
    }
}
