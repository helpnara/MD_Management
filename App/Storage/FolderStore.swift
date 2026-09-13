import Foundation
import Core

/// 사용자 폴더를 읽고 쓰는 **유일한** 자리.
///
/// ADR-0007 을 지키는 방법이 이것이다. `App/Storage/` 밖에서 `FileManager` 로 사용자
/// 폴더를 만지는 코드가 보이면 그 결정이 안 지켜지고 있다는 뜻이다.
///
/// 모든 읽기 · 쓰기는 `NSFileCoordinator` 로 감싼다. 쓰기는 임시 파일 →
/// `replaceItemAt` (원자적).
actor FolderStore {

    let root: URL
    let kind: FolderKind

    /// 보안 범위 폴더((b))는 쓰는 동안 접근을 열어 두어야 한다.
    private let needsSecurityScope: Bool
    private var hasScope = false

    init(root: URL, kind: FolderKind) {
        self.root = root
        self.kind = kind
        self.needsSecurityScope = (kind == .userChosen)
    }

    /// 보안 범위 접근을 닫는다. 폴더를 바꿀 때 부른다.
    /// (`deinit` 에서 부르지 않는다 — actor 의 `deinit` 은 격리된 상태를 못 만진다.)
    func close() {
        if hasScope {
            root.stopAccessingSecurityScopedResource()
            hasScope = false
        }
    }

    private func openScopeIfNeeded() {
        guard needsSecurityScope, !hasScope else { return }
        hasScope = root.startAccessingSecurityScopedResource()
    }

    // MARK: - 목록

    /// 한 폴더 안의 노트를 읽는다. 하위 폴더로 내려가지 않는다.
    ///
    /// **첫 줄 미리보기를 여기서 만들지 않는다.** 파일을 다 열면 300개에 3초를
    /// 못 맞추고, iCloud 미다운로드 파일은 아예 못 읽는다 (설계서 §7.5 · S1).
    func notes(in relativeFolder: String = "") -> [NoteSummary] {
        openScopeIfNeeded()
        let folder = relativeFolder.isEmpty ? root : root.appendingPathComponent(relativeFolder)

        var result: [NoteSummary] = []
        coordinateRead(folder) { url in
            let keys: [URLResourceKey] = [
                .isDirectoryKey, .contentModificationDateKey, .fileSizeKey,
                .isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey
            ]
            guard let entries = try? FileManager.default.contentsOfDirectory(
                at: url, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles]
            ) else { return }

            for entry in entries {
                let name = Paths.normalized(entry.lastPathComponent)
                guard !name.hasPrefix("."), Paths.isNoteFile(name) else { continue }
                let values = try? entry.resourceValues(forKeys: Set(keys))
                if values?.isDirectory == true { continue }

                let relative = relativeFolder.isEmpty ? name : "\(relativeFolder)/\(name)"
                result.append(NoteSummary(
                    relativePath: relative,
                    title: Paths.baseName(name),
                    preview: "",
                    modifiedAt: values?.contentModificationDate ?? .distantPast,
                    size: values?.fileSize ?? 0,
                    isDownloaded: Self.isDownloaded(values)
                ))
            }
        }
        return result.sorted { $0.modifiedAt > $1.modifiedAt }
    }

    /// 하위 폴더 목록 (사이드바용). 숨김 폴더는 뺀다 — 옵시디언 볼트의 `.obsidian/` (A6).
    func folders() -> [FolderSummary] {
        openScopeIfNeeded()
        var result: [FolderSummary] = []
        coordinateRead(root) { url in
            guard let entries = try? FileManager.default.contentsOfDirectory(
                at: url, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]
            ) else { return }
            for entry in entries {
                let name = Paths.normalized(entry.lastPathComponent)
                guard !name.hasPrefix("."), name != "assets" else { continue }
                guard (try? entry.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true else { continue }
                let count = (try? FileManager.default.contentsOfDirectory(atPath: entry.path))?
                    .filter { Paths.isNoteFile($0) }.count ?? 0
                result.append(FolderSummary(relativePath: name, name: name, noteCount: count))
            }
        }
        return result.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    // MARK: - 읽기 · 쓰기

    func readText(at relativePath: String) throws -> String {
        openScopeIfNeeded()
        let url = root.appendingPathComponent(relativePath)
        var result: Result<String, Error> = .failure(CocoaError(.fileNoSuchFile))
        coordinateRead(url) { readURL in
            result = Result { try String(contentsOf: readURL, encoding: .utf8) }
        }
        return try result.get()
    }

    /// **원자적으로** 쓴다. 원본을 열어 놓고 덮어쓰지 않는다 (설계서 §7.1).
    func writeText(_ text: String, to relativePath: String) throws {
        openScopeIfNeeded()
        let target = root.appendingPathComponent(relativePath)
        var thrown: Error?

        var coordinationError: NSError?
        NSFileCoordinator().coordinate(writingItemAt: target, options: .forReplacing, error: &coordinationError) { url in
            do {
                let temporary = FileManager.default.temporaryDirectory
                    .appendingPathComponent(UUID().uuidString)
                    .appendingPathExtension("md")
                try text.write(to: temporary, atomically: true, encoding: .utf8)
                if FileManager.default.fileExists(atPath: url.path) {
                    _ = try FileManager.default.replaceItemAt(url, withItemAt: temporary)
                } else {
                    try FileManager.default.moveItem(at: temporary, to: url)
                }
            } catch {
                thrown = error
            }
        }
        if let error = thrown ?? coordinationError { throw error }
    }

    /// 이미지 같은 이진 파일을 원자적으로 쓴다.
    func writeData(_ data: Data, to relativePath: String) throws {
        openScopeIfNeeded()
        let target = root.appendingPathComponent(relativePath)
        try createFolder(Paths.directory(of: relativePath))

        var thrown: Error?
        var coordinationError: NSError?
        NSFileCoordinator().coordinate(writingItemAt: target, options: .forReplacing, error: &coordinationError) { url in
            do {
                let temporary = FileManager.default.temporaryDirectory
                    .appendingPathComponent(UUID().uuidString)
                try data.write(to: temporary, options: .atomic)
                if FileManager.default.fileExists(atPath: url.path) {
                    _ = try FileManager.default.replaceItemAt(url, withItemAt: temporary)
                } else {
                    try FileManager.default.moveItem(at: temporary, to: url)
                }
            } catch {
                thrown = error
            }
        }
        if let error = thrown ?? coordinationError { throw error }
    }

    /// 하위 폴더를 만든다. 빈 문자열이면 아무것도 안 한다.
    func createFolder(_ relativePath: String) throws {
        guard !relativePath.isEmpty else { return }
        openScopeIfNeeded()
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent(relativePath),
            withIntermediateDirectories: true)
    }

    // MARK: - 속

    private func coordinateRead(_ url: URL, _ body: (URL) -> Void) {
        var error: NSError?
        NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &error) { readURL in
            body(readURL)
        }
    }

    private static func isDownloaded(_ values: URLResourceValues?) -> Bool {
        guard values?.isUbiquitousItem == true else { return true }
        return values?.ubiquitousItemDownloadingStatus == .current
    }
}

// MARK: - 뷰어에 파일 건네주기 (ADR-0004)

extension FolderStore: AssetProvider {

    /// 웹뷰의 `yb://note/<상대경로>` 요청을 받는다.
    ///
    /// **폴더 밖으로 나가는 경로는 거부한다.** 요청은 노트 본문에서 오고,
    /// 노트는 남이 보낸 것일 수 있다 (설계서 §7.6.3).
    func data(forRelativePath path: String) -> Data? {
        guard Paths.join(base: "", relative: path) == Paths.normalized(path) else { return nil }
        openScopeIfNeeded()

        let url = root.appendingPathComponent(path)
        var result: Data?
        coordinateRead(url) { readURL in
            result = try? Data(contentsOf: readURL)
        }
        return result
    }

    /// 후보 경로 가운데 실제로 있는 것만. 렌더러에 넘길 `exists` 를 만든다.
    func existingPaths(among candidates: [String]) -> Set<String> {
        openScopeIfNeeded()
        var found: Set<String> = []
        for candidate in candidates {
            let url = root.appendingPathComponent(candidate)
            if FileManager.default.fileExists(atPath: url.path) {
                found.insert(candidate)
            }
        }
        return found
    }
}
