import XCTest
@testable import Core

/// 203 — **폴더 안의 폴더.** 폴더 화면은 두 단계까지, 더 깊은 폴더는 열어서 들어간다.
///
/// 기댓값은 `Tools/golden/generate.py` 의 `folderTreeCases` — 같은 셈을 파이썬으로 적었다.
final class FolderTreeGoldenTests: XCTestCase {

    struct Golden: Decodable {
        struct Entry: Decodable {
            let path: String
            let depth: Int
            let subfolders: Int
        }
        struct Rename: Decodable {
            let path: String
            let to: String
            let result: String
        }
        struct Rebase: Decodable {
            let path: String
            let old: String
            let new: String
            let result: String?
        }
        struct Move: Decodable {
            let path: String
            let into: String
            let result: String
        }
        struct Case: Decodable {
            let name: String
            let paths: [String]
            let sidebar: [Entry]
            let depths: [Int]
            let children: [String: [String]]
            let rename: Rename?
            let rebase: [Rebase]?
            let move: [Move]?
            let targets: [String: [String]]?
            let create: [String: String]?
        }
        let folderTreeCases: [Case]
    }

    func testMatchesGolden() throws {
        let here = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let url = here.appendingPathComponent("Golden/expected.json")
        let cases = try JSONDecoder().decode(Golden.self, from: try Data(contentsOf: url)).folderTreeCases
        XCTAssertFalse(cases.isEmpty, "정답표가 비었다")
        for item in cases {
            let sidebar = FolderTree.sidebar(item.paths)
            XCTAssertEqual(sidebar.map(\.path), item.sidebar.map(\.path), "줄 — [\(item.name)]")
            XCTAssertEqual(sidebar.map(\.depth), item.sidebar.map(\.depth), "단계 — [\(item.name)]")
            XCTAssertEqual(sidebar.map(\.subfolders), item.sidebar.map(\.subfolders), "안의 폴더 — [\(item.name)]")
            XCTAssertEqual(item.paths.map(FolderTree.depth(of:)), item.depths, "깊이 — [\(item.name)]")
            for (folder, children) in item.children {
                XCTAssertEqual(FolderTree.children(of: folder, in: item.paths), children, "열기 \(folder) — [\(item.name)]")
            }
            if let rename = item.rename {
                XCTAssertEqual(FolderTree.renamed(rename.path, to: rename.to), rename.result, "이름 — [\(item.name)]")
            }
            for rebase in item.rebase ?? [] {
                XCTAssertEqual(FolderTree.rebased(rebase.path, from: rebase.old, to: rebase.new), rebase.result,
                               "따라가기 \(rebase.path) — [\(item.name)]")
            }
            // 204 — 다른 폴더 안으로 옮기기.
            for move in item.move ?? [] {
                XCTAssertEqual(FolderTree.moved(move.path, into: move.into), move.result,
                               "옮기기 \(move.path) → \(move.into) — [\(item.name)]")
            }
            // 218 — 고른 폴더 기준 새 폴더 자리.
            for (selected, parent) in item.create ?? [:] {
                XCTAssertEqual(FolderTree.creationParent(for: selected), parent, "새 폴더 자리 \(selected) — [\(item.name)]")
            }
            for (folder, targets) in item.targets ?? [:] {
                XCTAssertEqual(FolderTree.moveTargets(for: folder, in: item.paths), targets,
                               "옮길 자리 \(folder) — [\(item.name)]")
            }
        }
    }
}
