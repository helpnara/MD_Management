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
    /// **파일 하나의 요약** — 목록에 없는 노트를 상세 칸에 띄울 때 쓴다 (T7).
    /// 링크를 따라 `assets/` 안의 `.md` 로 갈 때가 그 자리다.
    func summary(of relativePath: String) -> NoteSummary? {
        openScopeIfNeeded()
        let url = root.appendingPathComponent(relativePath)
        let keys: [URLResourceKey] = [
            .isDirectoryKey, .contentModificationDateKey, .fileSizeKey,
            .isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey
        ]
        guard let values = try? url.resourceValues(forKeys: Set(keys)), values.isDirectory != true else {
            return nil
        }
        let name = relativePath.split(separator: "/").last.map(String.init) ?? relativePath
        return NoteSummary(
            relativePath: relativePath,
            title: Paths.baseName(name),
            preview: "",
            modifiedAt: values.contentModificationDate ?? .distantPast,
            size: values.fileSize ?? 0,
            isDownloaded: Self.isDownloaded(values))
    }

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
                let values = try? entry.resourceValues(forKeys: Set(keys))
                // **세는 쪽과 같은 거름망을 쓴다** (153). 예전에는 이 조건을 여기서 손으로
                // 풀고, 폴더 화면의 숫자는 따로 셌다 — 둘이 갈라져 개수가 안 맞았다.
                guard Paths.countsAsNote(name: name, isDirectory: values?.isDirectory == true)
                else { continue }

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

    /// 폴더 **전체**의 노트 — 하위 폴더까지, 숨김은 빼고. 색인이 쓴다 (ADR-0003).
    func allNotes() -> [NoteSummary] {
        openScopeIfNeeded()
        var result: [NoteSummary] = []
        var pending = [""]
        while let folder = pending.popLast() {
            result += notes(in: folder)
            let url = folder.isEmpty ? root : root.appendingPathComponent(folder)
            guard let entries = try? FileManager.default.contentsOfDirectory(
                at: url, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]
            ) else { continue }
            for entry in entries {
                let name = Paths.normalized(entry.lastPathComponent)
                guard !name.hasPrefix("."), name != "assets",
                      (try? entry.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true else { continue }
                pending.append(folder.isEmpty ? name : folder + "/" + name)
            }
        }
        return result
    }

    /// **폴더에 바로 든 노트가 몇 개인가** (153).
    ///
    /// 하위 폴더 **안**은 세지 않는다 — 폴더 화면의 숫자는 그 폴더를 열었을 때 보이는
    /// 목록의 길이와 **같아야** 하고, 그 목록도 하위 폴더 안은 안 보여 준다.
    ///
    /// **`notes(in:)` 과 같은 거름망 · 같은 조정 읽기를 쓴다.** 예전에는 여기서 확장자만
    /// 보고 따로 셌다 — 숨김 파일과 `자료.md` 라는 폴더를 세어 **목록에 없는 것이
    /// 숫자에는 있었다** (사용자 · 2026-09-19).
    func noteCount(in relativeFolder: String) -> Int {
        openScopeIfNeeded()
        let folder = relativeFolder.isEmpty ? root : root.appendingPathComponent(relativeFolder)
        var count = 0
        coordinateRead(folder) { url in
            guard let entries = try? FileManager.default.contentsOfDirectory(
                at: url, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]
            ) else { return }
            for entry in entries {
                let isDirectory = (try? entry.resourceValues(forKeys: [.isDirectoryKey]))?
                    .isDirectory == true
                if Paths.countsAsNote(name: Paths.normalized(entry.lastPathComponent),
                                      isDirectory: isDirectory) { count += 1 }
            }
        }
        return count
    }

    /// 하위 폴더 목록 — **모든 깊이** (203). 숨김 폴더는 뺀다 — 옵시디언 볼트의 `.obsidian/` (A6).
    ///
    /// 폴더 화면은 이 가운데 두 단계까지 펼치고(`FolderTree.sidebar`), 더 깊은 폴더는 두 번째 단계 폴더를 열면 나온다.
    /// 노트 수는 폴더마다 **바로 든** 노트다 (153). 차례는 이름 차례 — 부모 아래 자식이 같은 셈으로 놓인다.
    func folders() -> [FolderSummary] {
        openScopeIfNeeded()
        // **이름만 먼저 모으고 조정 밖에서 센다** (153). 조정 읽기 **안에서** 또 조정
        // 읽기를 부르면 겹친다 — 읽기끼리는 막지 않지만 겹쳐 부를 까닭이 없다.
        var paths: [String] = []
        var pending: [(path: String, depth: Int)] = [("", 0)]
        while let next = pending.popLast() {
            let folder = next.path
            let depth = next.depth
            // 아주 깊은 폴더는 끝까지 안 내려간다 — 고리(별칭)나 남의 앱 자료가 끝없이 깊을 때.
            guard depth < 12 else { continue }
            let url = folder.isEmpty ? root : root.appendingPathComponent(folder)
            coordinateRead(url) { readURL in
                guard let entries = try? FileManager.default.contentsOfDirectory(
                    at: readURL, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]
                ) else { return }
                for entry in entries {
                    let name = Paths.normalized(entry.lastPathComponent)
                    guard !name.hasPrefix("."), name != "assets" else { continue }
                    guard (try? entry.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true else { continue }
                    let path = folder.isEmpty ? name : folder + "/" + name
                    paths.append(path)
                    pending.append((path, depth + 1))
                }
            }
        }
        return paths
            .map { path in
                FolderSummary(relativePath: path,
                              name: path.split(separator: "/").last.map(String.init) ?? path,
                              noteCount: noteCount(in: path))
            }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    // MARK: - 읽기 · 쓰기

    /// **UTF-8 이 먼저다.** UTF-8 로 안 읽히면 UTF-16(BOM 있을 때) · CP949(예전 한글 윈도)
    /// 차례로 본다 — 예전 한글 파일을 열었다고 오류만 띄우고 마는 것보다 낫다.
    /// 무엇으로 읽었는지 기억해 둔다 (`encoding(of:)`) — 부른 쪽이 그 사실을 알아야
    /// **여는 것만으로 남의 파일을 UTF-8 로 바꿔 쓰는 일**(62)을 안 한다.
    func readText(at relativePath: String) throws -> String {
        openScopeIfNeeded()
        let url = root.appendingPathComponent(relativePath)
        // **다 안 내려온 파일은 읽지 않는다.** iCloud 는 이름을 먼저 주고 내용을 나중에 준다.
        // 그때 읽으면 **잘린 글**이 오고, 제목 맞추기(62)가 그것을 도로 써서 원본을 잘라 버렸다 —
        // iCloud 는 온전한 판과 갈라졌다고 보아 충돌을 냈다 (사용자: 원본이 잘리고 사본에 원래 글).
        // 내려받기를 시켜 두고 물러난다. 다 오면 지켜보기가 다시 부른다.
        guard isCurrent(url) else {
            try? FileManager.default.startDownloadingUbiquitousItem(at: url)
            throw ReadError.notDownloaded
        }
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

    /// 이 파일이 **지금 내려와 있고 최신인가.** 기기 안 파일은 늘 참이다.
    /// URL 은 자원 값을 캐시하므로 **새로 만들어** 본다 (85 와 같은 까닭).
    func isCurrent(_ url: URL) -> Bool {
        var fresh = URL(fileURLWithPath: url.path)
        fresh.removeAllCachedResourceValues()
        let values = try? fresh.resourceValues(forKeys: [.isUbiquitousItemKey,
                                                         .ubiquitousItemDownloadingStatusKey])
        guard values?.isUbiquitousItem == true else { return true }
        return values?.ubiquitousItemDownloadingStatus == .current
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
        case cp949: return String(localized: "CP949 (예전 한글 윈도)")
        default: return String(localized: "알 수 없음")
        }
    }

    /// 파일의 **수정 시각과 크기** — 충돌 감지의 도장이다 (설계서 §7.2 · A15).
    /// 없는 파일이면 `nil`.
    func stamp(of relativePath: String) -> FileStamp? {
        openScopeIfNeeded()
        // 빈 경로는 최상위 폴더 자체 — 폴더의 시각은 안에 무엇이 생기거나 없어질 때 바뀐다.
        //
        // **URL 을 매번 새로 만든다.** `URL` 은 자원 값을 **그 객체에 캐시한다.** 예전에는 최상위일 때
        // 저장해 둔 `root` 를 그대로 넘겨, 폴더가 바뀌어도 늘 옛 시각이 돌아왔다 — 아이패드를 켜 둔 채
        // 두면 다른 기기의 삭제가 반영되지 않았다 (빌드 25 · 사용자). 당겨서 새로 고침과 재시작만
        // 되던 까닭이다. 경로 문자열로 새 URL 을 만들면 캐시가 따라오지 않는다.
        let path = relativePath.isEmpty ? root.path : root.appendingPathComponent(relativePath).path
        var stamp: FileStamp?
        coordinateRead(URL(fileURLWithPath: path)) { readURL in
            var fresh = URL(fileURLWithPath: readURL.path)
            fresh.removeAllCachedResourceValues()
            guard let values = try? fresh.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey]),
                  let date = values.contentModificationDate else { return }
            stamp = FileStamp(modifiedAt: date, size: values.fileSize ?? 0)
        }
        return stamp
    }

    /// **이름이 비었을 때 쓰는 파일 이름** (222 · ADR-0009) — 앱 언어로. 한국어 `제목 없음` · 영어 `Untitled`.
    /// Core 의 기본값은 한국어라 앱이 늘 이것을 넘긴다 (`createNote` · `rename` · 겹침 피하기).
    static var untitled: String { String(localized: "fallback.untitled", defaultValue: "제목 없음") }

    /// 충돌 사본의 이름. 파일 이름이라 `:` 를 못 쓴다 — `이름 (충돌 2026-09-14 14.02)` · 영어 `이름 (Conflict 2026-09-14 14.02)`.
    /// 기기 언어를 따른다 (219 · ADR-0009) — 이 이름을 알아보는 코드는 없다. 사람이 읽고 합치는 이름이다.
    static func conflictName(for fileName: String, at date: Date = Date()) -> String {
        let clock = DateFormatter()
        clock.locale = Locale(identifier: "en_US_POSIX")
        clock.dateFormat = "yyyy-MM-dd HH.mm"
        return String(localized: "\(Paths.baseName(fileName)) (충돌 \(clock.string(from: date)))")
    }

    /// **iCloud 가 스스로 만든 충돌 판본**을 끌어낸다 (설계서 §7.2). 두 기기가 같은 파일을
    /// 따로 고치면 iCloud 는 하나를 남기고 다른 하나를 `NSFileVersion` 으로 숨겨 둔다 —
    /// 사용자는 그것을 볼 길이 없다. 숨은 판본마다 `이름 (충돌 …).md` 로 나란히 꺼내 놓고
    /// 판본을 정리한다. 만든 사본의 경로들을 준다. 없으면 빈 배열.
    func surfaceConflictVersions(of relativePath: String) throws -> ConflictSweep {
        openScopeIfNeeded()
        let url = root.appendingPathComponent(relativePath)
        guard let versions = NSFileVersion.unresolvedConflictVersionsOfItem(at: url), !versions.isEmpty else {
            return ConflictSweep(made: [], pending: 0)
        }
        let current = try? readText(at: relativePath)
        let name = relativePath.split(separator: "/").last.map(String.init) ?? relativePath
        var made: [String] = []
        var pending = 0

        for (index, version) in versions.enumerated() {
            // **읽지 못한 판본은 절대 해결로 표시하지 않는다.** 여기가 빌드 20 의 유실 자리였다
            // (빌드 20 · 4번): 비행기 모드를 풀면 다른 기기의 판본은 아직 **안 내려와 있다.**
            // 그때 `Data(contentsOf:)` 가 실패했는데도 `isResolved = true` 를 찍어 **그 글을
            // 버렸고**, 남은 내 판본이 이겨 다른 기기까지 덮었다. 이제 못 읽으면 그대로 두고
            // 다음 기회에 다시 본다 — 판본은 iCloud 가 들고 있다.
            guard let text = versionText(version) else {
                pending += 1
                continue
            }
            if text != current {
                let stamp = version.modificationDate ?? Date()
                let title = Self.conflictName(for: name, at: stamp) + (index == 0 ? "" : " \(index + 1)")
                // 사본을 못 쓰면 역시 판본을 남긴다 — 글을 먼저 안전한 곳에 둔 뒤에만 지운다.
                guard let path = try? createNote(named: title, in: Paths.directory(of: relativePath), text: text) else {
                    pending += 1
                    continue
                }
                made.append(path)
            }
            version.isResolved = true
        }
        // 모두 갈무리했을 때만 묵은 판본을 정리한다.
        if pending == 0 { try? NSFileVersion.removeOtherVersionsOfItem(at: url) }
        return ConflictSweep(made: made, pending: pending)
    }

    /// 충돌 판본의 글. **먼저 내려받고 조정해서 읽는다** — iCloud 의 판본은 파일이
    /// 아직 기기에 없을 수 있다. 못 읽으면 `nil` 이고, 부른 쪽은 그 판본을 건드리지 않는다.
    private func versionText(_ version: NSFileVersion) -> String? {
        try? FileManager.default.startDownloadingUbiquitousItem(at: version.url)
        var text: String?
        coordinateRead(version.url) { url in
            if let data = try? Data(contentsOf: url) { text = Self.decode(data)?.text }
        }
        return text
    }

    /// **원자적으로** 쓴다. 원본을 열어 놓고 덮어쓰지 않는다 (설계서 §7.1).
    ///
    /// `expecting` 은 **우리가 마지막으로 읽었거나 쓴 글**이다. 조정 안에서 디스크의 글이 그것과
    /// 다르면(다른 기기가 고쳤다) **쓰지 않고** `WriteConflict.changedOnDisk` 를 던진다 — 부른 쪽이
    /// 충돌 사본을 만든다 (A15). 검사와 쓰기가 한 덩어리여야 그 사이에 들어온 글을 덮지 않는다.
    ///
    /// **조정 옵션은 UIDocument 와 같다.** 파일을 처음 만들 때만 `.forReplacing`, 있는 파일에
    /// 덮어쓸 때는 `.forMerging`. `.forReplacing` 은 "이 자리를 새 항목으로 바꾼다" 는 뜻이라
    /// iCloud 가 저장을 **새 파일**로 봤고, 두 기기가 같은 노트를 고치면 판본 대신 `A 2` 가
    /// 생겼다 (빌드 20 · 21 의 1번 — 임시 파일 자리를 옮겨도 그대로였다).
    func writeText(_ text: String, to relativePath: String, expecting previous: String? = nil) throws {
        openScopeIfNeeded()
        let target = root.appendingPathComponent(relativePath)
        let exists = FileManager.default.fileExists(atPath: target.path)
        var thrown: Error?

        var coordinationError: NSError?
        NSFileCoordinator().coordinate(writingItemAt: target, options: exists ? .forMerging : .forReplacing,
                                       error: &coordinationError) { url in
            do {
                if let previous {
                    // **확인할 수 없으면 덮지 않는다.** 다 안 내려온 파일을 덮으면 남의 글이 사라진다.
                    guard self.isCurrent(url) else {
                        thrown = ReadError.notDownloaded
                        return
                    }
                    if let data = try? Data(contentsOf: url), let onDisk = Self.decode(data)?.text,
                       onDisk != previous, onDisk != text {
                        thrown = WriteConflict.changedOnDisk(onDisk)
                        return
                    }
                }
                let temporary = try Self.replacementScratch(for: url).appendingPathExtension("md")
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

    /// **이 URL 이 우리 폴더 안의 파일인가.** 안이면 폴더 기준 상대경로, 밖이면 `nil`.
    ///
    /// 문서 피커가 건네는 URL 은 심볼릭 링크를 지나올 수 있어(`/private/var…`)
    /// 양쪽을 다 풀어서 견준다.
    func relativePath(of url: URL) -> String? {
        openScopeIfNeeded()
        let base = root.standardizedFileURL.resolvingSymlinksInPath().path
        let target = url.standardizedFileURL.resolvingSymlinksInPath().path
        guard target.hasPrefix(base + "/") else { return nil }
        return Paths.normalized(String(target.dropFirst(base.count + 1)))
    }

    /// **노트를 노트로 들여온다** (111). `assets/` 가 아니라 **그 노트 옆**에 둔다 —
    /// `.md` 는 첨부가 아니라 폴더의 시민이다. 이름이 겹치면 `이름 2.md` 로 비켜 간다.
    func importNote(_ data: Data, named name: String, in folder: String) throws -> String {
        guard let text = Self.decode(data)?.text else { throw ReadError.notDownloaded }
        return try createNote(named: Paths.baseName(name), in: folder, text: text)
    }

    /// **노트를 다른 폴더로 옮긴다** (T1, 사용자 요청).
    ///
    /// `rebasesLinks` 가 참이면 옮기기 **전에** 본문의 상대 링크를 새 자리에 맞춰 고친다
    /// (`MarkdownLinks.rebased`). 앱이 본문을 고치는 유일한 자리이므로, 부르는 쪽이
    /// **사용자에게 몇 개를 고칠지 먼저 알린 뒤에** 참으로 부른다 (107 에서 62 를 지운 까닭).
    ///
    /// 이름이 겹치면 `이름 2.md` 로 비켜 간다. 옮겨진 자리의 상대경로를 준다.
    func moveNote(_ relativePath: String, to folder: String, rebasesLinks: Bool) throws -> String {
        openScopeIfNeeded()
        let from = Paths.directory(of: relativePath)
        guard from != folder else { return relativePath }
        let name = relativePath.split(separator: "/").last.map(String.init) ?? relativePath

        if rebasesLinks {
            let text = try readText(at: relativePath)
            let fixed = MarkdownLinks.rebased(text, from: from, to: folder)
            if fixed != text { try writeText(fixed, to: relativePath, expecting: text) }
        }

        try createFolder(folder)
        let target = uniqueRelativePath(name: name, in: folder)
        try move(from: root.appendingPathComponent(relativePath),
                 to: root.appendingPathComponent(target))
        encodings[target] = encodings[relativePath]
        encodings[relativePath] = nil
        return target
    }

    /// 이 노트가 **폴더 안을 가리키는 링크**를 몇 개 갖고 있나 (T1).
    /// 옮기기 전에 사용자에게 "링크 N개를 고칩니다" 라고 알리려고 센다.
    func folderLinkCount(of relativePath: String) -> Int {
        openScopeIfNeeded()
        guard let text = try? readText(at: relativePath) else { return 0 }
        let note = Paths.normalized(relativePath)
        var count = 0
        for link in MarkdownLinks.extract(from: text) {
            if case .relative = Paths.resolve(link: link.destination, fromNoteAt: note) { count += 1 }
        }
        return count
    }

    // MARK: - 고정된 노트 (T10)

    /// 적어 둔 고정 목록. 없거나 깨졌으면 빈 목록 — 고정은 잃어도 자료가 아니다.
    func readPins() -> [String] {
        openScopeIfNeeded()
        let url = root.appendingPathComponent(Pins.fileName)
        var data: Data?
        coordinateRead(url) { readURL in data = try? Data(contentsOf: readURL) }
        guard let data else { return [] }
        return Pins.decode(data)
    }

    /// **이름이 바뀌거나 옮겨졌을 때 고정도 따라간다** (T10). 부르는 쪽이 옛 자리와 새
    /// 자리를 다 아는 자리에서 부른다 — `rename` · `moveNote` · `followTitle` · `renameFolder`.
    @discardableResult
    func followPins(from old: String, to new: String) -> [String] {
        let moved = Pins.following(readPins(), from: old, to: new)
        return writePins(moved, mergingDisk: false)
    }

    /// 휴지통으로 갔거나 영영 지워졌다 — 고정에서 뺀다.
    @discardableResult
    func unpin(_ gone: String) -> [String] {
        let left = Pins.removing(readPins(), at: gone)
        return writePins(left, mergingDisk: false)
    }

    /// **디스크에 있는 것과 합쳐서** 적는다 (T10). 두 기기가 각각 고정하면 파일이
    /// 부딪히는데, 고정 목록은 집합이라 **합치면 된다** — 노트 본문처럼 판본을 꺼낼 일이 없다.
    /// 그래서 쓰기 전에 한 번 더 읽는다.
    @discardableResult
    func writePins(_ paths: [String], mergingDisk: Bool = true) -> [String] {
        openScopeIfNeeded()
        let settled = mergingDisk ? Pins.merged(paths, readPins()) : Pins.tidy(paths)
        do {
            try createFolder(Pins.folder)
            try writeData(Pins.encode(settled), to: Pins.fileName)
        } catch {
            // 고정을 못 적어도 노트는 멀쩡하다. 조용히 물러난다.
        }
        return settled
    }

    /// 안전 저장용 임시 파일 자리. **원본과 같은 볼륨의 교체 전용 폴더**여야 한다.
    ///
    /// 빌드 20 까지는 앱의 `tmp` 에 썼다. 그러면 `replaceItemAt` 이 자리를 맞바꾸지 못하고
    /// **새 파일을 만들어 옛 파일을 지우는** 쪽으로 물러나, iCloud 가 그 저장을 같은 파일의
    /// 수정이 아니라 **새 파일**로 봤다. 그래서 두 기기가 같은 노트를 고치면 판본(`NSFileVersion`)
    /// 이 아니라 `A 2` 가 생기고 한쪽이 다른 쪽을 덮었다 (빌드 20 · 1번, 두 기기 확인).
    /// 애플이 `replaceItemAt` 과 짝지어 둔 자리가 `itemReplacementDirectory` 다.
    private static func replacementScratch(for target: URL) throws -> URL {
        let directory = try FileManager.default.url(for: .itemReplacementDirectory, in: .userDomainMask,
                                                    appropriateFor: target, create: true)
        return directory.appendingPathComponent(UUID().uuidString)
    }

    /// 이미지 같은 이진 파일을 원자적으로 쓴다.
    func writeData(_ data: Data, to relativePath: String) throws {
        openScopeIfNeeded()
        let target = root.appendingPathComponent(relativePath)
        try createFolder(Paths.directory(of: relativePath))

        var thrown: Error?
        var coordinationError: NSError?
        let exists = FileManager.default.fileExists(atPath: target.path)
        NSFileCoordinator().coordinate(writingItemAt: target, options: exists ? .forMerging : .forReplacing,
                                       error: &coordinationError) { url in
            do {
                // 글과 같은 까닭으로 같은 볼륨의 교체 전용 폴더에 · 같은 조정 옵션으로 (위 `writeText`).
                let temporary = try Self.replacementScratch(for: url)
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
        let safe = Paths.safeFileName(name, fallback: Self.untitled)
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
        let safe = Paths.safeFileName(newName, fallback: Self.untitled)
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

    /// 이 노트가 가리키는 첨부 가운데 **폴더 안의 다른 노트가 안 쓰는 것** (60 · 172).
    /// 노트로 가는 링크(`docs/a.md`)는 첨부가 아니다 — 지우면 남의 노트가 사라진다.
    ///
    /// **폴더 전체를 본다** (172). 빌드 56 까지는 같은 폴더의 노트만 봤다 — `assets/` 는 폴더마다
    /// 따로 두는 약속이었는데, 옮기기(T1)와 붙여넣기(144)가 `../회의/assets/a.png` 같은 **폴더 밖
    /// 링크**를 만들면서 그 약속이 깨졌다. 다른 폴더 노트의 사진이 휴지통으로 가던 자리다.
    /// 셈은 `AttachmentLedger` 하나다 — 정리 화면(174) · 영구 삭제(173)와 같은 셈.
    private func exclusiveAttachments(of notePath: String) -> [String] {
        let census = attachmentCensus()
        return AttachmentLedger.trashing(notePath, notes: census.notes,
                                         trashed: census.trashed, files: census.files)
    }

    /// **첨부 셈에 넘길 것** (172 · 173 · 174). 폴더 전체를 한 번 훑는다 — 휴지통은 넣고,
    /// 다른 숨김 폴더(다른 앱의 설정 폴더 등)는 뺀다.
    ///
    /// 노트는 본문을 읽는다. **아직 안 내려온 노트는 `nil`** — 셈이 판정을 멈춘다(못 읽은 노트가
    /// 그 사진을 쓸 수 있다). 옛 iCloud 자리표시자(`.이름.icloud`)도 안 내려온 노트로 센다.
    /// 노트가 아닌 파일은 경로와 크기만.
    func attachmentCensus() -> AttachmentCensus {
        openScopeIfNeeded()
        var census = AttachmentCensus()
        let keys: Set<URLResourceKey> = [
            .isDirectoryKey, .fileSizeKey, .isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey
        ]
        var pending = [""]
        while let folder = pending.popLast() {
            let url = folder.isEmpty ? root : root.appendingPathComponent(folder)
            guard let entries = try? FileManager.default.contentsOfDirectory(
                at: url, includingPropertiesForKeys: Array(keys), options: []
            ) else { continue }
            for entry in entries {
                var name = Paths.normalized(entry.lastPathComponent)
                let values = try? entry.resourceValues(forKeys: keys)
                if values?.isDirectory == true {
                    let isTrash = folder.isEmpty && name == ".trash"
                    if name.hasPrefix(".") && !isTrash { continue }
                    pending.append(folder.isEmpty ? name : folder + "/" + name)
                    continue
                }
                var placeholder = false
                if name.hasPrefix(".") {
                    guard name.hasSuffix(".icloud"), name.count > ".icloud".count + 1 else { continue }
                    name = String(name.dropFirst().dropLast(".icloud".count))
                    placeholder = true
                }
                let path = folder.isEmpty ? name : folder + "/" + name
                if Paths.isNoteFile(path) {
                    var text: String?
                    if !placeholder, Self.isDownloaded(values) { text = try? readText(at: path) }
                    // `사전[키] = nil` 은 키를 지운다 — 못 읽은 노트를 **nil 로 남기려고** updateValue.
                    if path.hasPrefix(".trash/") {
                        census.trashed.updateValue(text, forKey: path)
                    } else {
                        census.notes.updateValue(text, forKey: path)
                    }
                } else if !placeholder {
                    census.files.insert(path)
                    census.sizes[path] = values?.fileSize ?? 0
                }
            }
        }
        return census
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

    /// `parent` 안에 폴더를 만든다 (최상위면 빈 문자열). 이름은 파일 이름과 같은 규칙으로 다듬고,
    /// 같은 이름이 있으면 `이름 2` 로 비켜 간다. 만든 폴더의 상대경로를 준다.
    /// **두 단계까지만** 만든다 (203, `FolderTree.creatableDepth`) — 부르는 쪽이 지키지만 여기서도 막는다.
    func createSubfolder(named name: String, in parent: String = "") throws -> String {
        openScopeIfNeeded()
        guard FolderTree.depth(of: parent) < FolderTree.creatableDepth else {
            throw CocoaError(.fileWriteNoPermission)
        }
        let safe = Paths.safeFileName(name, fallback: String(localized: "새 폴더"))
        let base = parent.isEmpty ? safe : parent + "/" + safe
        var chosen = base
        for attempt in 2...999 {
            if !FileManager.default.fileExists(atPath: root.appendingPathComponent(chosen).path) { break }
            chosen = "\(base) \(attempt)"
        }
        try createFolder(chosen)
        return chosen
    }

    /// 폴더 이름을 바꾼다 — **같은 부모 안에서** (203). 같은 이름이 있으면 `이름 2`. 새 상대경로를 준다.
    /// 예전에는 새 이름을 최상위에 만들었다 — 하위 폴더에 쓰면 최상위로 빠져나갔을 것이다.
    func renameFolder(_ relativePath: String, to newName: String) throws -> String {
        let safe = Paths.safeFileName(newName, fallback: String(localized: "새 폴더"))
        return try relocateFolder(relativePath, to: FolderTree.renamed(relativePath, to: safe))
    }

    /// 폴더를 **다른 폴더 안으로** 옮긴다 (204) — 이름은 그대로, `parent` 가 빈 문자열이면 맨 위로.
    /// 제 안으로는 못 간다. 이름 바꾸기와 같은 길(`relocateFolder`)로 옮긴다.
    func moveFolder(_ relativePath: String, into parent: String) throws -> String {
        guard !FolderTree.isInside(parent, relativePath) else { throw CocoaError(.fileWriteInvalidFileName) }
        return try relocateFolder(relativePath, to: FolderTree.moved(relativePath, into: parent))
    }

    /// 폴더를 `base` 로 옮긴다 — 이름 바꾸기 · 다른 폴더로 옮기기가 함께 쓴다. 같은 이름이 있으면 `이름 2`.
    private func relocateFolder(_ relativePath: String, to base: String) throws -> String {
        openScopeIfNeeded()
        guard !relativePath.isEmpty, base != relativePath else { return relativePath }
        var chosen = base
        for attempt in 2...999 {
            if chosen == relativePath { return relativePath }
            if !FileManager.default.fileExists(atPath: root.appendingPathComponent(chosen).path) { break }
            chosen = "\(base) \(attempt)"
        }
        try createFolder(FolderTree.parent(of: chosen))
        try move(from: root.appendingPathComponent(relativePath),
                 to: root.appendingPathComponent(chosen))
        return chosen
    }

    /// 폴더 이름을 바꾸고 **그 폴더 안을 가리키던 링크를 따라 고친다** (179, 사용자 — 남은 할 일을
    /// 반영해 제출하자). 168 은 알리기만 해서, 이름을 바꾸면 다른 폴더 노트의 사진이 깨졌다.
    func renameFolderFixingLinks(_ relativePath: String, to newName: String) throws -> FolderRename {
        try relocateFixingLinks(relativePath) { try renameFolder(relativePath, to: newName) }
    }

    /// 폴더를 다른 폴더 안으로 옮기고 링크를 고친다 (204). 안의 노트가 한 단계 깊어지거나 얕아지므로
    /// 바깥을 가리키던 링크도 새 자리에 맞춘다 — 셈은 이름 바꾸기와 같은 `MarkdownLinks.retargeted`.
    func moveFolderFixingLinks(_ relativePath: String, into parent: String) throws -> FolderRename {
        try relocateFixingLinks(relativePath) { try moveFolder(relativePath, into: parent) }
    }

    /// 옮기기 **전에** 폴더 전체를 읽는다 — 옛 자리로 링크를 풀어야 하기 때문이다. 고치는 셈은
    /// `MarkdownLinks.retargeted` 하나다. 안의 노트는 새 자리에 쓴다. 쓸 때 **읽은 글과 같을 때만**
    /// 쓴다(`expecting`) — 그 사이 다른 기기에서 고쳤으면 건드리지 않고 못 고친 수로 센다.
    /// 아직 안 내려온 노트는 읽을 수 없어 못 본 수로 센다.
    private func relocateFixingLinks(_ relativePath: String, _ relocate: () throws -> String) throws -> FolderRename {
        let census = attachmentCensus()
        let moved = try relocate()
        guard moved != relativePath else { return FolderRename(path: moved) }
        var result = FolderRename(path: moved)
        for (path, text) in census.notes {
            guard let text else {
                result.unread += 1
                continue
            }
            let repair = MarkdownLinks.retargeted(text, notePath: path,
                                                  fromFolder: relativePath, toFolder: moved)
            guard repair.fixed > 0 else { continue }
            let now = FolderTree.rebased(path, from: relativePath, to: moved) ?? path
            do {
                try writeText(repair.text, to: now, expecting: text)
                result.fixed += repair.fixed
                result.notes += 1
            } catch {
                result.failed += 1
            }
        }
        return result
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
        guard let updated = FrontMatterParser.replacingFirstLine(in: text, with: title),
              updated != text else { return false }
        try writeText(updated, to: relativePath)
        return true
    }

    /// **되돌릴 수 없는 유일한 삭제.** `.trash/` 안의 것만 지운다 — 다른 경로가
    /// 오면 아무것도 안 한다. 확인(타이핑)은 화면이 받았다 (설계서 §7.1).
    ///
    /// **이 노트만 쓰던 첨부도 같이 지운다** (173). 예전에는 노트만 지워 첨부가 `.trash/` 에
    /// 안 보이게 영원히 남았다. 휴지통의 다른 노트가 쓰거나, 살아 있는 노트가 원래 자리를
    /// 가리키는데 거기 파일이 없으면(그 휴지통 파일이 유일한 사본) 남긴다 — `AttachmentLedger.purging`.
    func deleteTrashed(_ relativePath: String) throws {
        guard relativePath.hasPrefix(".trash/") else { return }
        openScopeIfNeeded()
        let census = attachmentCensus()
        let attachments = AttachmentLedger.purging(relativePath, notes: census.notes,
                                                   trashed: census.trashed, files: census.files)
        try remove(root.appendingPathComponent(relativePath))
        for path in attachments where path.hasPrefix(".trash/") {
            try? remove(root.appendingPathComponent(path))
        }
    }

    /// 휴지통 안의 **첨부**(노트가 아닌 파일) — 휴지통 화면이 개수 · 용량을 보여 준다 (173).
    /// 노트 본문은 안 읽는다 — 휴지통을 열 때마다 불리므로 가볍게.
    func trashedAttachments() -> [TrashedFile] {
        openScopeIfNeeded()
        var sizes: [String: Int] = [:]
        var pending = [".trash"]
        while let folder = pending.popLast() {
            guard let entries = try? FileManager.default.contentsOfDirectory(
                at: root.appendingPathComponent(folder),
                includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey], options: []
            ) else { continue }
            for entry in entries {
                let name = Paths.normalized(entry.lastPathComponent)
                let values = try? entry.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey])
                let path = folder + "/" + name
                if values?.isDirectory == true {
                    pending.append(path)
                    continue
                }
                guard !name.hasPrefix("."), !Paths.isNoteFile(path) else { continue }
                sizes[path] = values?.fileSize ?? 0
            }
        }
        return AttachmentLedger.ordered(sizes.keys).map { TrashedFile(relativePath: $0, size: sizes[$0] ?? 0) }
    }

    /// 휴지통의 첨부 하나를 **원래 자리로.** 원래 자리에 이미 파일이 있으면 번호를 붙인다
    /// — 링크는 원래 이름을 가리키므로, 그런 일은 드물다.
    func restoreAttachment(_ relativePath: String) throws -> String {
        openScopeIfNeeded()
        guard relativePath.hasPrefix(".trash/") else { return relativePath }
        let original = Self.originalPath(ofTrashed: relativePath)
        let name = original.split(separator: "/").last.map(String.init) ?? original
        let folder = Paths.directory(of: original)
        try createFolder(folder)
        let target = uniqueRelativePath(name: name, in: folder)
        try move(from: root.appendingPathComponent(relativePath),
                 to: root.appendingPathComponent(target))
        return target
    }

    /// **안 쓰는 첨부를 휴지통으로** (174). `.trash/<원래 경로>` 로 — 휴지통 화면에서 되돌릴 수 있다.
    /// 옮긴 개수를 준다. 하나가 실패해도 나머지는 옮긴다.
    func trashAttachments(_ paths: [String]) -> Int {
        openScopeIfNeeded()
        var moved = 0
        for path in paths where AttachmentLedger.isAttachmentPath(path) {
            let home = ".trash/" + Paths.directory(of: path)
            let name = path.split(separator: "/").last.map(String.init) ?? path
            do {
                try createFolder(home)
                try move(from: root.appendingPathComponent(path),
                         to: root.appendingPathComponent(uniqueRelativePath(name: name, in: home)))
                moved += 1
            } catch {
                continue
            }
        }
        return moved
    }

    /// **폴더 밖 노트가 이 폴더 안을 가리키는 링크 수** (168). 폴더 이름을 바꾸거나 지우면
    /// 그 링크가 깨진다 — 확인창이 먼저 알린다. 못 읽은 노트는 세지 못한다(`nil` 이 아니라 뺀 값).
    func incomingLinkCount(toFolder folder: String) -> Int {
        let census = attachmentCensus()
        return AttachmentLedger.incomingLinks(to: folder, notes: census.notes)
    }

    /// **이 노트를 가리키는 노트** (212). 폴더 링크 셈(168)과 같은 훑기 · 같은 셈이다. 못 읽은 노트는 세지 못한다.
    func backlinks(to path: String) -> [String] {
        AttachmentLedger.backlinks(to: path, notes: attachmentCensus().notes)
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
    ///
    /// **이름을 금고 전체에서 겹치지 않게 짓는다** (178). 예전에는 폴더마다 `2026-09-28-1.jpg` 부터 다시
    /// 세서, 같은 날 두 폴더에 사진을 넣으면 이름이 겹쳤다 — 붙여넣기의 링크 고치기(144)가 이름으로
    /// 찾다가 어느 것인지 몰라 못 고치거나 **다른 폴더의 사진**을 가리켰다(177). 이미 있는 파일의 이름은
    /// 바꾸지 않는다 — 파일이 원본이다. 새로 넣는 것부터 겹치지 않는다. 휴지통 안의 이름도 피한다
    /// (되돌리면 다시 나란히 선다).
    func writeAsset(_ data: Data, stem: String, ext: String, besideNoteIn folder: String) throws -> String {
        let path = try newAssetPath(stem: stem, ext: ext, besideNoteIn: folder)
        try writeData(data, to: path)
        return String(path.dropFirst(folder.isEmpty ? 0 : folder.count + 1))
    }

    /// 문서 첨부를 **메모리에 올리지 않고 복사해** 넣는다 (181). 예전에는 파일을 통째로 `Data` 로
    /// 읽었다 — 수 GB 영상이면 iOS 가 앱을 끈다. 이름 짓기는 `writeAsset` 과 같은 길이다.
    /// 큰 파일이면 복사하는 동안 이 actor 의 다른 일(자동 저장)이 기다린다 — 글은 편집기에 있다.
    func copyAsset(from source: URL, stem: String, ext: String, besideNoteIn folder: String) throws -> String {
        let path = try newAssetPath(stem: stem, ext: ext, besideNoteIn: folder)
        let target = root.appendingPathComponent(path)
        let scoped = source.startAccessingSecurityScopedResource()
        defer { if scoped { source.stopAccessingSecurityScopedResource() } }
        try? FileManager.default.startDownloadingUbiquitousItem(at: source)

        var thrown: Error?
        var coordinationError: NSError?
        NSFileCoordinator().coordinate(readingItemAt: source, options: [],
                                       writingItemAt: target, options: .forReplacing,
                                       error: &coordinationError) { readURL, writeURL in
            do {
                try FileManager.default.copyItem(at: readURL, to: writeURL)
            } catch {
                thrown = error
            }
        }
        if let error = thrown ?? coordinationError { throw error }
        return String(path.dropFirst(folder.isEmpty ? 0 : folder.count + 1))
    }

    /// 새 첨부의 금고 기준 경로 — `assets/` 를 만들고, 금고 전체에서 겹치지 않는 이름을 고른다 (178).
    private func newAssetPath(stem: String, ext: String, besideNoteIn folder: String) throws -> String {
        openScopeIfNeeded()
        let assets = folder.isEmpty ? "assets" : folder + "/assets"
        try createFolder(assets)
        let taken = assetNamesInVault()

        var path = ""
        for sequence in 1...9999 {
            let name = stem + "-\(sequence)." + ext
            let candidate = assets + "/" + name
            if !taken.contains(Paths.normalized(name).lowercased()),
               !FileManager.default.fileExists(atPath: root.appendingPathComponent(candidate).path) {
                path = candidate
                break
            }
        }
        if path.isEmpty {
            path = assets + "/" + stem + "-\(Int(Date().timeIntervalSince1970))." + ext
        }
        return path
    }

    /// 금고 안 **모든 `assets/` 폴더의 파일 이름** (휴지통 포함 · 소문자 · NFC). 사진 이름을 겹치지 않게
    /// 짓는 데만 쓴다 (178). 다른 숨김 폴더는 들어가지 않는다.
    private func assetNamesInVault() -> Set<String> {
        var names: Set<String> = []
        var pending = [""]
        while let folder = pending.popLast() {
            let url = folder.isEmpty ? root : root.appendingPathComponent(folder)
            guard let entries = try? FileManager.default.contentsOfDirectory(
                at: url, includingPropertiesForKeys: [.isDirectoryKey], options: []
            ) else { continue }
            let inAssets = folder.split(separator: "/").last == "assets"
            for entry in entries {
                let name = Paths.normalized(entry.lastPathComponent)
                if (try? entry.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true {
                    if name.hasPrefix(".") && !(folder.isEmpty && name == ".trash") { continue }
                    pending.append(folder.isEmpty ? name : folder + "/" + name)
                } else if inAssets {
                    names.insert(name.lowercased())
                }
            }
        }
        return names
    }

    /// 같은 이름이 있으면 `이름 2.md` · `이름 3.md`. 파일 시스템을 직접 본다 —
    /// 목록은 늦을 수 있다.
    ///
    /// **확장자를 지어내지 않는다.** 예전에는 확장자가 없으면 `.md` 를 붙였는데, `이름 (충돌
    /// 2026-09-14 14.02)` 의 `.02)` 를 확장자로 보고 `.md` 를 안 붙여 **충돌 사본이 목록에서
    /// 안 보였다** (빌드 18 · 10번). 노트 확장자는 노트를 만드는 쪽(`createNote` · `rename`)이
    /// 책임진다. 여기는 이름 그대로 번호만 붙인다 — 그래야 `사진.jpg` 도 `사진 2.jpg` 가 된다.
    private func uniqueRelativePath(name: String, in folder: String, keeping own: String? = nil) -> String {
        let safe = Paths.safeFileName(name, fallback: Self.untitled)
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

    // MARK: - 공유 (설계서 §7.6)

    /// 공유할 파일 하나를 임시 폴더에 만든다. 첨부가 없으면 `.md`, 있으면 `.zip`.
    ///
    /// **원본을 그대로 넘기지 않고 임시 폴더로 복사한다.** 고른 폴더(b)의 파일은 보안 범위
    /// 안에 있어 받는 앱이 못 열 수 있고, 공유 도중 원본이 바뀌면 곤란하다.
    /// zip 은 `NSFileCoordinator … .forUploading` 이 만든다 — 그 URL 은 **블록 안에서만**
    /// 유효하므로 안에서 옮긴다. zip 최상위에 폴더 이름이 들어가므로 그 이름을 노트 제목으로 둔다.
    func prepareShare(of notePath: String, followLinkedNotes: Bool) throws -> SharePackage {
        openScopeIfNeeded()
        let text = try readText(at: notePath)
        let plan = ShareBundle.plan(notePath: notePath, noteText: text,
                                    followLinkedNotes: followLinkedNotes) { candidate in
            FileManager.default.fileExists(atPath: root.appendingPathComponent(candidate).path)
        }

        let fileName = notePath.split(separator: "/").last.map(String.init) ?? notePath
        let title = Paths.safeFileName(Paths.baseName(fileName), fallback: String(localized: "노트"))
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("share-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        var bytes = 0
        func copy(_ relative: String, to target: URL) throws {
            let source = root.appendingPathComponent(relative)
            // 다 안 내려온 파일을 복사하면 **잘린 것을 보낸다** (86 과 같은 뿌리).
            guard isCurrent(source) else {
                try? FileManager.default.startDownloadingUbiquitousItem(at: source)
                throw ReadError.notDownloaded
            }
            try FileManager.default.createDirectory(at: target.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: source, to: target)
            bytes += (try? FileManager.default.attributesOfItem(atPath: target.path)[.size] as? Int) ?? 0
        }

        if plan.mode == .mdOnly {
            let file = directory.appendingPathComponent(title + ".md")
            try copy(notePath, to: file)
            return SharePackage(url: file, directory: directory, isZip: false,
                                missing: plan.missing, bytes: bytes)
        }

        // 노트와 첨부를 **원래 상대경로 그대로** 담는다 — 받는 쪽에서 풀면 링크가 산다.
        let stage = directory.appendingPathComponent(title, isDirectory: true)
        try FileManager.default.createDirectory(at: stage, withIntermediateDirectories: true)
        for relative in plan.includes {
            try copy(relative, to: stage.appendingPathComponent(relative))
        }

        let zip = directory.appendingPathComponent(title + ".zip")
        var thrown: Error?
        var coordinationError: NSError?
        NSFileCoordinator().coordinate(readingItemAt: stage, options: [.forUploading],
                                       error: &coordinationError) { packed in
            do {
                try FileManager.default.copyItem(at: packed, to: zip)
            } catch {
                thrown = error
            }
        }
        if let error = thrown ?? coordinationError { throw error }
        try? FileManager.default.removeItem(at: stage)
        let zipBytes = (try? FileManager.default.attributesOfItem(atPath: zip.path)[.size] as? Int) ?? bytes
        return SharePackage(url: zip, directory: directory, isZip: true,
                            missing: plan.missing, bytes: zipBytes)
    }

    /// 공유가 끝나면 임시 폴더를 지운다.
    nonisolated static func cleanUpShare(_ directory: URL) {
        try? FileManager.default.removeItem(at: directory)
    }

    /// **공유 임시 폴더에 아직 남은 것** — 꾸러미 몇 개 · 몇 바이트 (97, 사용자 제안).
    /// 기기 저장 공간이 쌓이는지는 눈으로 보기 어렵다. 공유가 끝날 때마다 이것을 최근 일에
    /// 적어 두면, 늘 `0개 · 0B` 인지 사람이 훑어보고 알 수 있다.
    nonisolated static func shareScratch() -> (count: Int, bytes: Int) {
        let temporary = FileManager.default.temporaryDirectory
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: temporary, includingPropertiesForKeys: [.isDirectoryKey]) else { return (0, 0) }
        var count = 0
        var bytes = 0
        for entry in entries where entry.lastPathComponent.hasPrefix("share-") {
            count += 1
            bytes += folderBytes(entry)
        }
        return (count, bytes)
    }

    /// **금고 안에서 이어 붙일 만한 파일들** (145, 사용자 제안 — *이미 있는 파일 연결하기*).
    ///
    /// 노트와 첨부를 함께 준다 — 첨부도 여러 노트에서 나눠 쓰고 싶어 나온 이야기다.
    /// 숨김 폴더와 휴지통은 뺀다. 목록이 아주 커지지 않게 `limit` 에서 멈춘다.
    ///
    /// **사본을 만들지 않는다** (2026-09-18 사용자). 파일은 제자리에 두고 **링크만** 넣는다.
    func linkableFiles(limit: Int = 2000) -> [LinkableFile] {
        openScopeIfNeeded()
        guard let walker = FileManager.default.enumerator(
            at: root, includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]) else { return [] }

        var found: [LinkableFile] = []
        for case let url as URL in walker {
            if found.count >= limit { break }
            let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            guard let relative = Paths.relative(of: url.path, under: root.path) else { continue }
            let path = Paths.normalized(relative)
            if isDirectory {
                // 휴지통과 숨김 폴더 속은 아예 들어가지 않는다.
                if url.lastPathComponent == ".trash" || url.lastPathComponent.hasPrefix(".") {
                    walker.skipDescendants()
                }
                continue
            }
            guard !Paths.isHidden(path) else { continue }
            found.append(LinkableFile(relativePath: path, name: url.lastPathComponent))
        }
        return found.sorted { $0.relativePath.localizedStandardCompare($1.relativePath) == .orderedAscending }
    }

    /// 폴더 아래 모든 파일의 크기 합.
    nonisolated static func folderBytes(_ directory: URL) -> Int {
        guard let walker = FileManager.default.enumerator(
            at: directory, includingPropertiesForKeys: [.fileSizeKey]) else { return 0 }
        var bytes = 0
        for case let url as URL in walker {
            bytes += (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        }
        return bytes
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
        // **너무 큰 파일은 건네지 않는다** (181) — 통째로 메모리에 올리므로 수 GB 면 iOS 가 앱을 끈다.
        // 웹뷰는 빈 그림을 받는다. 파일은 목록에서 눌러 따로 연다.
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
        guard size <= Self.largestHandedToViewer else { return nil }
        var result: Data?
        coordinateRead(url) { readURL in
            result = try? Data(contentsOf: readURL)
        }
        return result
    }

    /// 읽기 화면에 건네는 파일의 상한 — 사진 한 장으로는 넉넉하다 (181).
    static let largestHandedToViewer = 64 * 1024 * 1024

    /// 폴더 안 사진의 **작은 그림** — 커서 줄 사진 띠 (181). 파일에서 바로 줄여 읽는다.
    func thumbnail(forRelativePath path: String, maxPixel: CGFloat) -> Data? {
        guard Paths.join(base: "", relative: path) == Paths.normalized(path) else { return nil }
        openScopeIfNeeded()
        var result: Data?
        coordinateRead(root.appendingPathComponent(path)) { readURL in
            result = ImageImport.thumbnailPNG(at: readURL, maxPixel: maxPixel)
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
