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
    /// 파일마다 마지막으로 읽은 인코딩. **UTF-8 이 아닌 파일을 조용히 고쳐 쓰지 않으려고** 둔다.
    private var encodings: [String: String.Encoding] = [:]
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

    /// **UTF-8 이 먼저다.** UTF-8 로 안 읽히면 UTF-16(BOM 있을 때) · CP949(예전 한글 윈도)
    /// 차례로 본다 — 예전 한글 파일을 열었다고 오류만 띄우고 마는 것보다 낫다.
    /// 무엇으로 읽었는지 기억해 둔다 (`encoding(of:)`) — 부른 쪽이 그 사실을 알아야
    /// **여는 것만으로 남의 파일을 UTF-8 로 바꿔 쓰는 일**(62)을 안 한다.
    func readText(at relativePath: String) throws -> String {
        openScopeIfNeeded()
        let url = root.appendingPathComponent(relativePath)
        var result: Result<Data, Error> = .failure(CocoaError(.fileNoSuchFile))
        coordinateRead(url) { readURL in
            result = Result { try Data(contentsOf: readURL) }
        }
        let data = try result.get()
        guard let decoded = Self.decode(data) else {
            encodings[relativePath] = nil
            throw CocoaError(.fileReadInapplicableStringEncoding)
        }
        encodings[relativePath] = decoded.encoding
        return decoded.text
    }

    /// 마지막으로 읽었을 때 어떤 글자 인코딩이었나. UTF-8 이 아니면 예전 파일이다.
    func encoding(of relativePath: String) -> String.Encoding? {
        encodings[relativePath]
    }

    /// 한글 윈도의 확장 완성형. `Foundation` 에 이름이 없어 이렇게 만든다.
    static let cp949 = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(
        CFStringEncoding(CFStringEncodings.dosKorean.rawValue)))

    /// 바이트를 글자로. **UTF-8 은 엄격하게** 본다 — 틀리면 다음 후보로 넘어간다.
    /// UTF-16 은 BOM 이 있을 때만 — 없으면 아무 바이트나 받아들여 쓰레기가 나온다.
    static func decode(_ data: Data) -> (text: String, encoding: String.Encoding)? {
        if let text = String(data: data, encoding: .utf8) { return (text, .utf8) }
        let bom = Array(data.prefix(2))
        if bom == [0xFF, 0xFE] || bom == [0xFE, 0xFF],
           let text = String(data: data, encoding: .utf16) { return (text, .utf16) }
        if let text = String(data: data, encoding: cp949) { return (text, cp949) }
        return nil
    }

    /// 사람에게 보여 줄 인코딩 이름.
    static func encodingName(_ encoding: String.Encoding) -> String {
        switch encoding {
        case .utf8: return "UTF-8"
        case .utf16: return "UTF-16"
        case cp949: return "CP949 (예전 한글 윈도)"
        default: return "알 수 없음"
        }
    }

    /// 파일의 **수정 시각과 크기** — 충돌 감지의 도장이다 (설계서 §7.2 · A15).
    /// 없는 파일이면 `nil`.
    func stamp(of relativePath: String) -> FileStamp? {
        openScopeIfNeeded()
        // 빈 경로는 최상위 폴더 자체 — 폴더의 시각은 안에 무엇이 생기거나 없어질 때 바뀐다.
        let url = relativePath.isEmpty ? root : root.appendingPathComponent(relativePath)
        var stamp: FileStamp?
        coordinateRead(url) { readURL in
            guard let values = try? readURL.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey]),
                  let date = values.contentModificationDate else { return }
            stamp = FileStamp(modifiedAt: date, size: values.fileSize ?? 0)
        }
        return stamp
    }

    /// 충돌 사본의 이름. 파일 이름이라 `:` 를 못 쓴다 — `이름 (충돌 2026-09-14 14.02)`.
    static func conflictName(for fileName: String, at date: Date = Date()) -> String {
        let clock = DateFormatter()
        clock.locale = Locale(identifier: "en_US_POSIX")
        clock.dateFormat = "yyyy-MM-dd HH.mm"
        return "\(Paths.baseName(fileName)) (충돌 \(clock.string(from: date)))"
    }

    /// **iCloud 가 스스로 만든 충돌 판본**을 끌어낸다 (설계서 §7.2). 두 기기가 같은 파일을
    /// 따로 고치면 iCloud 는 하나를 남기고 다른 하나를 `NSFileVersion` 으로 숨겨 둔다 —
    /// 사용자는 그것을 볼 길이 없다. 숨은 판본마다 `이름 (충돌 …).md` 로 나란히 꺼내 놓고
    /// 판본을 정리한다. 만든 사본의 경로들을 준다. 없으면 빈 배열.
    func surfaceConflictVersions(of relativePath: String) throws -> [String] {
        openScopeIfNeeded()
        let url = root.appendingPathComponent(relativePath)
        guard let versions = NSFileVersion.unresolvedConflictVersionsOfItem(at: url), !versions.isEmpty else {
            return []
        }
        let current = try? readText(at: relativePath)
        let name = relativePath.split(separator: "/").last.map(String.init) ?? relativePath
        var made: [String] = []
        for (index, version) in versions.enumerated() {
            if let data = try? Data(contentsOf: version.url), let text = Self.decode(data)?.text,
               text != current {
                let stamp = version.modificationDate ?? Date()
                let title = Self.conflictName(for: name, at: stamp) + (index == 0 ? "" : " \(index + 1)")
                made.append(try createNote(named: title, in: Paths.directory(of: relativePath), text: text))
            }
            version.isResolved = true
        }
        try? NSFileVersion.removeOtherVersionsOfItem(at: url)
        return made
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
        // 우리는 언제나 UTF-8 로 쓴다. 예전 인코딩이었더라도 이 순간 UTF-8 이 된다.
        encodings[relativePath] = .utf8
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
        let safe = Paths.safeFileName(name)
        let path = uniqueRelativePath(name: Paths.isNoteFile(safe) ? safe : safe + ".md", in: folder)
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
        // 옮기기 전에 읽어야 한다 — 이 노트만 쓰는 첨부를 같이 보낸다 (60).
        let attachments = exclusiveAttachments(of: relativePath)
        try createFolder(trashFolder)
        let target = uniqueRelativePath(name: name, in: trashFolder)
        try move(from: root.appendingPathComponent(relativePath),
                 to: root.appendingPathComponent(target))
        for attachment in attachments {
            let home = ".trash/" + Paths.directory(of: attachment)
            let file = attachment.split(separator: "/").last.map(String.init) ?? attachment
            try? createFolder(home)
            try? move(from: root.appendingPathComponent(attachment),
                      to: root.appendingPathComponent(uniqueRelativePath(name: file, in: home)))
        }
        return target
    }

    /// 이 노트가 가리키는 첨부 가운데 **같은 폴더의 다른 노트는 안 쓰는 것** (60).
    /// 노트로 가는 링크(`docs/a.md`)는 첨부가 아니다 — 지우면 남의 노트가 사라진다.
    /// 다른 폴더의 노트가 쓰는지는 보지 않는다 — `assets/` 는 폴더마다 따로 두는 약속이다.
    private func exclusiveAttachments(of notePath: String) -> [String] {
        guard let text = try? readText(at: notePath) else { return [] }
        let mine = MarkdownHTML.referencedPaths(markdown: text, notePath: notePath).filter {
            !Paths.isNoteFile($0) && FileManager.default.fileExists(atPath: root.appendingPathComponent($0).path)
        }
        guard !mine.isEmpty else { return [] }
        var used: Set<String> = []
        for other in notes(in: Paths.directory(of: notePath)) where other.relativePath != notePath {
            guard let otherText = try? readText(at: other.relativePath) else { continue }
            used.formUnion(MarkdownHTML.referencedPaths(markdown: otherText, notePath: other.relativePath))
        }
        return mine.filter { !used.contains($0) }
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
        restoreAttachments(of: target)
        return target
    }

    /// 되돌린 노트가 가리키는 첨부가 휴지통에 같은 자리로 있으면 **같이 되돌린다** (56).
    /// 폴더째 지웠다가 노트만 되돌릴 때 사진이 휴지통에 남던 것. 원래 자리에 이미
    /// 파일이 있으면 건드리지 않는다. 실패해도 노트 되돌리기는 이미 끝났으므로 조용히 넘어간다.
    private func restoreAttachments(of notePath: String) {
        guard let text = try? readText(at: notePath) else { return }
        for path in MarkdownHTML.referencedPaths(markdown: text, notePath: notePath) {
            let trashed = root.appendingPathComponent(".trash/" + path)
            let home = root.appendingPathComponent(path)
            guard FileManager.default.fileExists(atPath: trashed.path),
                  !FileManager.default.fileExists(atPath: home.path) else { continue }
            try? move(from: trashed, to: home)
        }
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
    ///
    /// **확장자를 지어내지 않는다.** 예전에는 확장자가 없으면 `.md` 를 붙였는데, `이름 (충돌
    /// 2026-09-14 14.02)` 의 `.02)` 를 확장자로 보고 `.md` 를 안 붙여 **충돌 사본이 목록에서
    /// 안 보였다** (빌드 18 · 10번). 노트 확장자는 노트를 만드는 쪽(`createNote` · `rename`)이
    /// 책임진다. 여기는 이름 그대로 번호만 붙인다 — 그래야 `사진.jpg` 도 `사진 2.jpg` 가 된다.
    private func uniqueRelativePath(name: String, in folder: String, keeping own: String? = nil) -> String {
        let safe = Paths.safeFileName(name)
        // 번호는 마지막 점 앞에 — 단, 노트 확장자나 짧은 확장자일 때만. `14.02)` 는 확장자가 아니다.
        let ext = Paths.fileExtension(safe)
        let splits = !ext.isEmpty && ext.count <= 5 && ext.allSatisfy { $0.isLetter || $0.isNumber }
        let base = splits ? Paths.baseName(safe) : safe
        let suffix = splits ? "." + ext : ""
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
