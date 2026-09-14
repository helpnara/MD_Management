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
    func notes(in relativeFolder: String = "", includingHidden: Bool = false) -> [NoteSummary] {
        openScopeIfNeeded()
        let folder = relativeFolder.isEmpty ? root : root.appendingPathComponent(relativeFolder)

        var result: [NoteSummary] = []
        coordinateRead(folder) { url in
            let keys: [URLResourceKey] = [
                .isDirectoryKey, .contentModificationDateKey, .fileSizeKey,
                .isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey
            ]
            guard let entries = try? FileManager.default.contentsOfDirectory(
                at: url, includingPropertiesForKeys: keys,
                options: includingHidden ? [] : [.skipsHiddenFiles]
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

    // MARK: - 만들기 · 이름 바꾸기 · 지우기

    /// 새 노트. 이름이 겹치면 실패하지 않고 `이름 2.md` 로 비켜 간다. 만든 경로를 준다.
    func createNote(named name: String, in folder: String, text: String) throws -> String {
        openScopeIfNeeded()
        try createFolder(folder)
        let path = uniqueRelativePath(name: name, in: folder)
        try writeText(text, to: path)
        return path
    }

    /// 파일 이름을 바꾼다. 확장자를 안 적으면 `.md` 를 붙인다. 새 경로를 준다.
    /// **덮어쓰지 않는다** — 같은 이름이 있으면 번호를 붙인다.
    func rename(_ relativePath: String, to newName: String) throws -> String {
        openScopeIfNeeded()
        let folder = Paths.directory(of: relativePath)
        let current = relativePath.split(separator: "/").last.map(String.init) ?? relativePath
        let safe = Paths.safeFileName(newName)
        // **점이 든 이름을 확장자로 오해하지 않는다.** `2026.09.13 회의` 를 그대로 두면
        // `.md` 가 안 붙어 목록에서 사라진다 — 노트 확장자가 아니면 `.md` 를 붙인다.
        let wanted = Paths.isNoteFile(safe) ? safe : safe + ".md"
        guard wanted != current else { return relativePath }

        // **자기 자신은 비켜 갈 상대가 아니다.** `여행 2.md` 의 제목이 `여행` 인데
        // `여행.md` 가 이미 있으면, 자기 자리인 `여행 2.md` 를 그대로 쓴다 — 아니면
        // 저장할 때마다 `여행 3` · `여행 4` 로 밀려난다 (54).
        let target = uniqueRelativePath(name: wanted, in: folder, keeping: relativePath)
        guard target != relativePath else { return relativePath }
        try move(from: root.appendingPathComponent(relativePath),
                 to: root.appendingPathComponent(target))
        return target
    }

    /// **지우지 않고 `.trash/` 로 옮긴다** (설계서 §7.1 · ADR-0001). 영구 삭제는
    /// 설정 → 휴지통에서 타이핑 확인으로만 한다.
    ///
    /// **원래 자리를 경로로 기억한다.** `여행/A.md` 는 `.trash/여행/A.md` 로 간다.
    /// 그래야 다른 폴더의 같은 이름 `A.md` 와 섞이지 않고, 되돌리면 원래 폴더로
    /// 돌아간다 (빌드 15 · 5번 — 예전에는 `A 2.md` 로 이름이 바뀌어 최상위로 갔다).
    /// DB 없이 파일 구조만으로 기억하므로 ADR-0001 을 지킨다.
    func trash(_ relativePath: String) throws -> String {
        openScopeIfNeeded()
        let name = relativePath.split(separator: "/").last.map(String.init) ?? relativePath
        let folder = Paths.directory(of: relativePath)
        let trashFolder = folder.isEmpty ? ".trash" : ".trash/" + folder
        try createFolder(trashFolder)
        let target = uniqueRelativePath(name: name, in: trashFolder)
        try move(from: root.appendingPathComponent(relativePath),
                 to: root.appendingPathComponent(target))
        return target
    }

    /// `.trash/` 안의 노트 — 하위 폴더까지. `notes(in:)` 는 숨김 폴더를 건너뛰므로 따로 있다.
    /// `파일` 앱은 숨김 폴더를 못 보여 주므로 **이 목록이 휴지통의 유일한 창**이다 (A14).
    func trashedNotes() -> [NoteSummary] {
        openScopeIfNeeded()
        var result: [NoteSummary] = []
        var pending = [".trash"]
        while let folder = pending.popLast() {
            result += notes(in: folder, includingHidden: true)
            let url = root.appendingPathComponent(folder)
            guard let entries = try? FileManager.default.contentsOfDirectory(
                at: url, includingPropertiesForKeys: [.isDirectoryKey], options: []
            ) else { continue }
            for entry in entries {
                guard (try? entry.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true else { continue }
                pending.append(folder + "/" + Paths.normalized(entry.lastPathComponent))
            }
        }
        return result.sorted { $0.modifiedAt > $1.modifiedAt }
    }

    /// 휴지통 안 경로의 **원래 자리**. `.trash/여행/A.md` → `여행/A.md`.
    static func originalPath(ofTrashed relativePath: String) -> String {
        relativePath.hasPrefix(".trash/") ? String(relativePath.dropFirst(".trash/".count)) : relativePath
    }

    /// 휴지통에서 **원래 폴더로** 되돌린다. 폴더가 없어졌으면 다시 만든다.
    /// 같은 이름이 있으면 번호를 붙인다. 되돌린 경로를 준다.
    func restore(_ relativePath: String) throws -> String {
        openScopeIfNeeded()
        let original = Self.originalPath(ofTrashed: relativePath)
        let name = original.split(separator: "/").last.map(String.init) ?? original
        let folder = Paths.directory(of: original)
        try createFolder(folder)
        let target = uniqueRelativePath(name: name, in: folder)
        try move(from: root.appendingPathComponent(relativePath),
                 to: root.appendingPathComponent(target))
        return target
    }

    /// 최상위에 하위 폴더를 만든다. 이름은 파일 이름과 같은 규칙으로 다듬고,
    /// 같은 이름이 있으면 `이름 2` 로 비켜 간다. 만든 폴더의 상대경로를 준다.
    func createSubfolder(named name: String) throws -> String {
        openScopeIfNeeded()
        let safe = Paths.safeFileName(name, fallback: "새 폴더")
        var chosen = safe
        for attempt in 2...999 {
            if !FileManager.default.fileExists(atPath: root.appendingPathComponent(chosen).path) { break }
            chosen = "\(safe) \(attempt)"
        }
        try createFolder(chosen)
        return chosen
    }

    /// 하위 폴더 이름을 바꾼다. 같은 이름이 있으면 `이름 2`. 새 상대경로를 준다.
    func renameFolder(_ relativePath: String, to newName: String) throws -> String {
        openScopeIfNeeded()
        let safe = Paths.safeFileName(newName, fallback: "새 폴더")
        guard safe != relativePath else { return relativePath }
        var chosen = safe
        for attempt in 2...999 {
            if chosen == relativePath { return relativePath }
            if !FileManager.default.fileExists(atPath: root.appendingPathComponent(chosen).path) { break }
            chosen = "\(safe) \(attempt)"
        }
        try move(from: root.appendingPathComponent(relativePath),
                 to: root.appendingPathComponent(chosen))
        return chosen
    }

    /// 하위 폴더를 **통째로 휴지통으로.** 안의 파일을 하나씩 `.trash/<원래 경로>` 로 옮기고
    /// 빈 폴더를 지운다. 그래서 휴지통에는 노트 하나하나가 폴더 이름과 함께 보이고,
    /// 되돌리면 폴더가 다시 생긴다. 숨김 파일은 옮기지 않는다 (폴더와 함께 사라진다).
    /// 옮긴 파일 수를 준다.
    func trashFolder(_ relativePath: String) throws -> Int {
        openScopeIfNeeded()
        guard !relativePath.isEmpty, !relativePath.hasPrefix(".") else { return 0 }
        let folderURL = root.appendingPathComponent(relativePath)
        var moved = 0
        var pending = [relativePath]
        while let folder = pending.popLast() {
            let url = root.appendingPathComponent(folder)
            guard let entries = try? FileManager.default.contentsOfDirectory(
                at: url, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]
            ) else { continue }
            for entry in entries {
                let name = Paths.normalized(entry.lastPathComponent)
                let path = folder + "/" + name
                if (try? entry.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true {
                    pending.append(path)
                    continue
                }
                let trashFolder = ".trash/" + folder
                try createFolder(trashFolder)
                let target = uniqueRelativePath(name: name, in: trashFolder)
                try move(from: entry, to: root.appendingPathComponent(target))
                moved += 1
            }
        }
        try remove(folderURL)
        return moved
    }

    /// 파일명이 바뀌었을 때 **첫 줄 `# 제목` 을 파일명으로 맞춘다** (54 의 반대 방향).
    /// 첫 줄이 제목이 아니면 아무것도 안 한다. 바꿨으면 `true`.
    func retitle(_ relativePath: String, to title: String) throws -> Bool {
        let text = try readText(at: relativePath)
        guard let updated = FrontMatterParser.replacingFirstHeading(in: text, with: title),
              updated != text else { return false }
        try writeText(updated, to: relativePath)
        return true
    }

    /// **되돌릴 수 없는 유일한 삭제.** `.trash/` 안의 것만 지운다 — 다른 경로가
    /// 오면 아무것도 안 한다. 확인(타이핑)은 화면이 받았다 (설계서 §7.1).
    func deleteTrashed(_ relativePath: String) throws {
        guard relativePath.hasPrefix(".trash/") else { return }
        openScopeIfNeeded()
        try remove(root.appendingPathComponent(relativePath))
    }

    /// `.trash/` 를 통째로 지운다. 다음 지우기가 다시 만든다.
    func emptyTrash() throws {
        openScopeIfNeeded()
        let trash = root.appendingPathComponent(".trash")
        guard FileManager.default.fileExists(atPath: trash.path) else { return }
        try remove(trash)
    }

    /// 노트 옆 `assets/` 에 첨부를 넣는다. 같은 이름이 있으면 번호를 올린다.
    /// 만든 파일의 **노트 기준 상대경로**(`assets/2026-09-13-1.jpg`)를 준다.
    ///
    /// **빈칸으로 비켜 가지 않는다.** `이름 2.jpg` 는 마크다운 링크에서 `<>` 없이는
    /// 깨진다 (빌드 11 · 9번). `stem` 과 `ext` 를 받아 `stem-1.jpg` · `stem-2.jpg` 로 센다.
    func writeAsset(_ data: Data, stem: String, ext: String, besideNoteIn folder: String) throws -> String {
        openScopeIfNeeded()
        let assets = folder.isEmpty ? "assets" : folder + "/assets"
        try createFolder(assets)

        var path = ""
        for sequence in 1...999 {
            let candidate = assets + "/" + stem + "-\(sequence)." + ext
            if !FileManager.default.fileExists(atPath: root.appendingPathComponent(candidate).path) {
                path = candidate
                break
            }
        }
        if path.isEmpty {
            path = assets + "/" + stem + "-\(Int(Date().timeIntervalSince1970))." + ext
        }
        try writeData(data, to: path)
        return String(path.dropFirst(folder.isEmpty ? 0 : folder.count + 1))
    }

    /// 같은 이름이 있으면 `이름 2.md` · `이름 3.md`. 파일 시스템을 직접 본다 —
    /// 목록은 늦을 수 있다.
    private func uniqueRelativePath(name: String, in folder: String, keeping own: String? = nil) -> String {
        let safe = Paths.safeFileName(name)
        let ext = Paths.fileExtension(safe)
        let base = Paths.baseName(safe)
        let suffix = ext.isEmpty ? ".md" : "." + ext
        func path(_ file: String) -> String { folder.isEmpty ? file : folder + "/" + file }

        for attempt in 1...999 {
            let candidate = attempt == 1 ? base + suffix : "\(base) \(attempt)" + suffix
            if path(candidate) == own { return path(candidate) }
            if !FileManager.default.fileExists(atPath: root.appendingPathComponent(path(candidate)).path) {
                return path(candidate)
            }
        }
        return path("\(base) \(Int(Date().timeIntervalSince1970))" + suffix)
    }

    /// 옮기기도 `NSFileCoordinator` 로. iCloud 가 옮긴 것을 알아야 다른 기기에 전해진다.
    private func move(from source: URL, to target: URL) throws {
        var thrown: Error?
        var coordinationError: NSError?
        let coordinator = NSFileCoordinator()
        coordinator.coordinate(writingItemAt: source, options: .forMoving,
                               writingItemAt: target, options: .forReplacing,
                               error: &coordinationError) { from, to in
            do {
                try FileManager.default.createDirectory(
                    at: to.deletingLastPathComponent(), withIntermediateDirectories: true)
                try FileManager.default.moveItem(at: from, to: to)
                coordinator.item(at: from, didMoveTo: to)
            } catch {
                thrown = error
            }
        }
        if let error = thrown ?? coordinationError { throw error }
    }

    /// 영구 삭제도 `NSFileCoordinator` 로 — iCloud 가 지운 것을 알아야 다른 기기에서도 사라진다.
    private func remove(_ url: URL) throws {
        var thrown: Error?
        var coordinationError: NSError?
        NSFileCoordinator().coordinate(writingItemAt: url, options: .forDeleting, error: &coordinationError) { target in
            do {
                try FileManager.default.removeItem(at: target)
            } catch {
                thrown = error
            }
        }
        if let error = thrown ?? coordinationError { throw error }
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
