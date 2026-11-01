import XCTest
@testable import Core

/// **노트를 옮길 때 같이 옮길 첨부** (291) · **휴지통의 폴더** (292). 기댓값은 `Tools/golden/generate.py` —
/// 옮긴 뒤 cmark 가 읽은 링크마다 같은 파일(옮겼으면 새 자리)을 가리키는지 · 휴지통 것이 한 번씩만 나오는지도 거기서 본다.
final class MoveAttachmentGoldenTests: XCTestCase {

    struct Golden: Decodable {
        struct Move: Decodable {
            let name: String
            let notes: [String: String?]
            let trashed: [String: String?]
            let files: [String]
            let note: String
            let folder: String
            let moves: [String: String]
            let text: String
            let rebased: String
        }
        struct Group: Decodable {
            struct Folder: Decodable {
                let folder: String
                let paths: [String]
            }
            let name: String
            let trashed: [String]
            let existing: [String]
            let candidates: [String]
            let folders: [Folder]
            let loose: [String]
        }
        struct Purge: Decodable {
            let name: String
            let folder: String
            let notes: [String: String?]
            let trashed: [String: String?]
            let files: [String]
            let purging: [String]
        }
        struct Trash: Decodable {
            let groups: [Group]
            let purges: [Purge]
        }
        let moveAttachmentCases: [Move]
        let trashGroupCases: Trash
    }

    /// `load` 라고 하지 않는다 — 맥에서 `NSObject.load()` 와 겹친다 (빌드 136).
    static func golden() throws -> Golden {
        let here = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let url = here.appendingPathComponent("Golden/expected.json")
        return try JSONDecoder().decode(Golden.self, from: try Data(contentsOf: url))
    }

    func testMoving() throws {
        let cases = try Self.golden().moveAttachmentCases
        XCTAssertFalse(cases.isEmpty)
        for item in cases {
            let moves = AttachmentLedger.moving(item.note, to: item.folder, notes: item.notes,
                                                trashed: item.trashed, files: Set(item.files))
            XCTAssertEqual(moves, item.moves, "[\(item.name)] 옮길 표")
            let from = Paths.directory(of: item.note)
            let text = from == item.folder ? item.text
                : MarkdownLinks.rebased(item.text, from: from, to: item.folder, moving: moves)
            XCTAssertEqual(text, item.rebased, "[\(item.name)] 고친 글")
        }
    }

    func testTrashGroups() throws {
        let trash = try Self.golden().trashGroupCases
        XCTAssertFalse(trash.groups.isEmpty)
        for item in trash.groups {
            XCTAssertEqual(TrashGroups.candidates(item.trashed), item.candidates, "[\(item.name)] 볼 폴더")
            let existing = Set(item.existing).intersection(item.candidates)
            let got = TrashGroups.group(item.trashed, existing: existing)
            XCTAssertEqual(got.folders.map(\.folder), item.folders.map(\.folder), "[\(item.name)] 폴더 줄")
            XCTAssertEqual(got.folders.map(\.paths), item.folders.map(\.paths), "[\(item.name)] 폴더 안")
            XCTAssertEqual(got.loose, item.loose, "[\(item.name)] 낱개")
        }
    }

    func testPurgingFolder() throws {
        let trash = try Self.golden().trashGroupCases
        XCTAssertFalse(trash.purges.isEmpty)
        for item in trash.purges {
            XCTAssertEqual(AttachmentLedger.purgingFolder(item.folder, notes: item.notes, trashed: item.trashed,
                                                          files: Set(item.files)),
                           item.purging, "[\(item.name)] 폴더째 영구 삭제")
        }
    }
}
