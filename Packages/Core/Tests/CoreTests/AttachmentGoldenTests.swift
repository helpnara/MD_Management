import XCTest
@testable import Core

/// 172 · 173 · 174 — **누가 어떤 첨부를 쓰나.**
///
/// 기댓값은 `Tools/golden/generate.py` 의 `attachmentCases` — 같은 규칙을 파이썬으로 따로 적어
/// 계산했다. 거기서 **빌드 56 의 규칙(같은 폴더만)이 21건 중 8건에서 걸리는 것**을 보고 왔다.
final class AttachmentGoldenTests: XCTestCase {

    struct Golden: Decodable {
        struct Case: Decodable {
            let name: String
            let notes: [String: String?]
            let trashed: [String: String?]
            let files: [String]
            let unused: [String]?
            let delete: String?
            let trashing: [String]?
            let purge: String?
            let purging: [String]?
            let folder: String?
            let incoming: Int?
            let backlinksOf: String?
            let backlinks: [String]?
        }
        let attachmentCases: [Case]
    }

    static func load() throws -> Golden {
        let here = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let url = here.appendingPathComponent("Golden/expected.json")
        return try JSONDecoder().decode(Golden.self, from: try Data(contentsOf: url))
    }

    func testMatchesGolden() throws {
        let cases = try Self.load().attachmentCases
        XCTAssertFalse(cases.isEmpty, "정답표가 비었다")
        for item in cases {
            let files = Set(item.files)
            XCTAssertEqual(AttachmentLedger.unused(notes: item.notes, trashed: item.trashed, files: files),
                           item.unused, "안 쓰는 첨부 — [\(item.name)]")
            if let note = item.delete {
                XCTAssertEqual(AttachmentLedger.trashing(note, notes: item.notes, trashed: item.trashed, files: files),
                               item.trashing, "지울 때 같이 — [\(item.name)]")
            }
            if let note = item.purge {
                XCTAssertEqual(AttachmentLedger.purging(note, notes: item.notes, trashed: item.trashed, files: files),
                               item.purging, "영구 삭제 때 같이 — [\(item.name)]")
            }
            if let folder = item.folder {
                XCTAssertEqual(AttachmentLedger.incomingLinks(to: folder, notes: item.notes),
                               item.incoming, "폴더를 가리키는 링크 — [\(item.name)]")
            }
            if let note = item.backlinksOf {
                XCTAssertEqual(AttachmentLedger.backlinks(to: note, notes: item.notes),
                               item.backlinks, "이 노트를 가리키는 노트 — [\(item.name)]")
            }
        }
    }

    /// 212 — 읽기 화면 아래 칸은 **셈이 낸 목록 그대로** 그린다: 노트마다 줄 하나, 주소는 본문의 노트 링크와 같은 꼴.
    /// 없으면 칸을 아예 안 그린다.
    func testBacklinksSectionDrawsEveryNote() throws {
        for item in try Self.load().attachmentCases {
            guard let note = item.backlinksOf else { continue }
            let found = AttachmentLedger.backlinks(to: note, notes: item.notes)
            let html = MarkdownHTML.backlinksHTML(found)
            if found.isEmpty {
                XCTAssertEqual(html, "", "[\(item.name)]")
                continue
            }
            XCTAssertEqual(html.components(separatedBy: "<li>").count - 1, found.count, "[\(item.name)]")
            for path in found {
                XCTAssertTrue(html.contains("href=\"\(MarkdownHTML.assetURL(path))\""), "[\(item.name)] \(path)")
            }
        }
    }

    /// **같이 보내는 것은 언제나 안 쓰는 것의 일부다.** 지울 노트를 빼고 셌을 때 안 쓰는 첨부가
    /// 아니면 보내면 안 된다 — 두 셈이 갈리지 않는지 본다 (CLAUDE.md §1).
    func testTrashingIsAlwaysUnusedWithoutTheNote() throws {
        for item in try Self.load().attachmentCases {
            guard let note = item.delete else { continue }
            let files = Set(item.files)
            let sent = AttachmentLedger.trashing(note, notes: item.notes, trashed: item.trashed, files: files)
            guard !sent.isEmpty else { continue }
            var rest = item.notes
            rest[note] = nil
            let unused = AttachmentLedger.unused(notes: rest, trashed: item.trashed, files: files) ?? []
            // `assets/` 밖의 파일도 가리키면 같이 보낸다(60 그대로) — 정리 화면의 후보는 아니다.
            for path in sent where AttachmentLedger.isAttachmentPath(path) {
                XCTAssertTrue(unused.contains(path), "[\(item.name)] \(path) 를 보냈는데 남은 노트 중 누가 쓴다")
            }
        }
    }

    /// **한글 이름이 NFD 로 와도 같은 답이다.** iCloud · 다른 앱을 거치면 본문 속 이름이 풀려서 온다.
    func testDecomposedMentionStillCounts() {
        let composed = "회의/assets/내 사진.jpg"
        let mention = "표지는 내 사진.jpg".decomposedStringWithCanonicalMapping
        let notes: [String: String?] = ["회의/B.md": "![](assets/내%20사진.jpg)", "기록.md": mention]
        XCTAssertEqual(AttachmentLedger.trashing("회의/B.md", notes: notes, trashed: [:], files: [composed]), [])
    }
}
