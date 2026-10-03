import Foundation

/// **공유 확장과 앱이 함께 쓰는 받은 글 상자** (213).
///
/// 공유 확장은 사용자 폴더를 열 수 없다 — 폴더 북마크 · iCloud 권한은 앱의 것이다. 그래서 확장은 받은 것을
/// **앱 그룹 컨테이너**의 `Inbox/<칸>/` 에 두기만 하고, 앱이 앞으로 나오면 그것을 `받은 글` 폴더의 새 노트로
/// 옮긴 뒤 칸을 지운다. 상자는 **잠깐 맡아 두는 곳**이다 — 노트가 된 칸은 남지 않는다 (ADR-0001, 파일이 원본).
///
/// 칸 하나 = 공유 한 번: 사진 파일들 + 마지막에 쓰는 `item.json`. **`item.json` 이 있는 칸만** 앱이 가져간다 —
/// 확장이 사진을 쓰다 끊겨도 반쯤 쓴 칸은 노트가 되지 않는다.
///
/// 이 파일은 앱과 확장 **둘 다** 빌드한다 (`project.yml` — `Shared/`).
actor ShareInbox {

    /// 앱과 확장의 자격 파일 · 애플 개발자 콘솔의 App Groups 와 같은 이름이어야 한다.
    static let groupID = "group.com.helpnara.markdown"

    struct Item: Codable, Sendable {
        var text: String
        var url: String?
        var pageTitle: String?
        /// 같은 칸 안의 사진 파일 이름 — 받은 순서.
        var images: [String]
        var created: Date
    }

    struct Entry: Sendable {
        let folder: URL
        let item: Item
    }

    enum InboxError: Error {
        case unavailable
    }

    private let root: URL?

    init() {
        root = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: Self.groupID)?
            .appendingPathComponent("Inbox", isDirectory: true)
    }

    // MARK: - 확장이 쓴다

    /// 새 칸. 이름은 만든 때 + 겹치지 않는 꼬리 — 앱이 이름 순으로 가져가면 받은 순서다.
    func begin(at date: Date = Date()) throws -> URL {
        guard let root else { throw InboxError.unavailable }
        let stamp = String(Int(date.timeIntervalSince1970 * 1000))
        let folder = root.appendingPathComponent(stamp + "-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    /// 사진 하나를 칸에 쓴다. 칸 안의 파일 이름을 준다.
    func writeImage(_ data: Data, ext: String, index: Int, in folder: URL) throws -> String {
        let name = "\(index).\(ext)"
        try data.write(to: folder.appendingPathComponent(name), options: .atomic)
        return name
    }

    /// 칸을 닫는다 — **이것을 써야** 앱이 가져간다.
    func finish(_ item: Item, in folder: URL) throws {
        let data = try JSONEncoder().encode(item)
        try data.write(to: folder.appendingPathComponent("item.json"), options: .atomic)
    }

    /// 보내기를 그만뒀거나 쓰다 실패한 칸을 치운다.
    func discard(_ folder: URL) {
        try? FileManager.default.removeItem(at: folder)
    }

    // MARK: - 앱이 쓴다

    /// 다 쓴 칸들 — 받은 순서로. 상자가 없으면(자격이 없는 빌드) 빈 목록.
    func pending() -> [Entry] {
        guard let root,
              let folders = try? FileManager.default.contentsOfDirectory(
                at: root, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
        else { return [] }
        return folders
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .compactMap { folder in
                guard let data = try? Data(contentsOf: folder.appendingPathComponent("item.json")),
                      let item = try? JSONDecoder().decode(Item.self, from: data) else { return nil }
                return Entry(folder: folder, item: item)
            }
    }

    func imageData(_ name: String, in entry: Entry) -> Data? {
        try? Data(contentsOf: entry.folder.appendingPathComponent(name))
    }

    /// 노트가 된 칸을 지운다.
    func remove(_ entry: Entry) {
        try? FileManager.default.removeItem(at: entry.folder)
    }
}
