import XCTest
@testable import Core

/// **메모의 *마크다운으로 보내기* 를 앱의 꼴로** (289). 기댓값은 `Tools/golden/generate.py` 가 계산한다 —
/// 모든 파일이 한 번씩 옮겨지는지, 새 자리가 겹치지 않는지, cmark 가 읽은 링크마다 옮긴 곳을 가리키는지도 거기서 본다.
final class NotesExportGoldenTests: XCTestCase {

    struct Golden: Decodable {
        struct Move: Decodable {
            let source: String
            let destination: String
        }
        struct Plan: Decodable {
            let notes: [Move]
            let files: [Move]
            let skipped: [String]
        }
        struct Note: Decodable {
            let source: String
            let text: String
            let converted: String
        }
        struct Case: Decodable {
            let name: String
            let folder: String
            let files: [String]
            let taken: [String]
            let plan: Plan
            let notes: [Note]
        }
        let notesExportCases: [Case]
    }

    static func load() throws -> [Golden.Case] {
        let here = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let url = here.appendingPathComponent("Golden/expected.json")
        return try JSONDecoder().decode(Golden.self, from: try Data(contentsOf: url)).notesExportCases
    }

    func testMatchesGolden() throws {
        let cases = try Self.load()
        XCTAssertFalse(cases.isEmpty)
        for item in cases {
            let plan = NotesExport.plan(files: item.files, into: item.folder, taken: Set(item.taken))
            XCTAssertEqual(plan.notes.map(\.source), item.plan.notes.map(\.source), "[\(item.name)] 노트 옛 자리")
            XCTAssertEqual(plan.notes.map(\.destination), item.plan.notes.map(\.destination), "[\(item.name)] 노트 새 자리")
            XCTAssertEqual(plan.files.map(\.source), item.plan.files.map(\.source), "[\(item.name)] 첨부 옛 자리")
            XCTAssertEqual(plan.files.map(\.destination), item.plan.files.map(\.destination), "[\(item.name)] 첨부 새 자리")
            XCTAssertEqual(plan.skipped, item.plan.skipped, "[\(item.name)] 건너뛴 것")
            let moves = plan.moves
            for (move, note) in zip(plan.notes, item.notes) {
                XCTAssertEqual(move.source, note.source)
                XCTAssertEqual(NotesExport.converted(note.text, source: move.source, destination: move.destination,
                                                     moves: moves),
                               note.converted, "[\(item.name)] \(note.source)")
            }
        }
    }

    /// 꼬리 · 숨김은 경로의 **어느 조각**이든 — 맥 압축은 `__MACOSX/` 아래에 같은 나무를 한 벌 더 만든다.
    func testJunk() {
        XCTAssertTrue(NotesExport.isJunk("__MACOSX/메모/._노트.md"))
        XCTAssertTrue(NotesExport.isJunk("메모/.DS_Store"))
        XCTAssertTrue(NotesExport.isJunk("메모/.숨김/노트.md"))
        XCTAssertFalse(NotesExport.isJunk("메모/노트.md"))
        XCTAssertFalse(NotesExport.isJunk("메모/Attachments/A.jpeg"))
    }
}
