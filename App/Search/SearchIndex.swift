import Foundation
import SQLite3
import Core

/// 찾기 결과 — 한도(200)를 넘었는지도 함께 (272).
struct SearchResults: Sendable {
    var hits: [SearchHit]
    var truncated: Bool
}

/// 색인에 든 노트의 도장 — 파일의 고친 시각(초) · 크기. 같으면 색인이 본 본문이 지금 파일과 같다 (268 · 269).
struct IndexStamp: Sendable, Equatable {
    let mtime: Int
    let size: Int
}

/// **첨부 셈의 힌트** (268 · 269) — 파일 담당이 읽지 않아도 되는 노트를 가린다 (`FolderStore.attachmentCensus(hint:)`).
struct CensusHint: Sendable {
    /// 색인에 본문까지 든 노트의 도장.
    let indexed: [String: IndexStamp]
    /// 판정에 들 수 있는 노트 — 늘 읽는다.
    let candidates: Set<String>
    /// 이 폴더 안의 노트도 늘 읽는다 (폴더 옮기기 — 안의 노트는 바깥으로 가는 링크가 바뀐다).
    let inside: String?

    /// 이 노트를 읽지 않아도 되나 — 후보가 아니고 · 폴더 안이 아니고 · 색인의 도장이 파일과 같을 때만.
    func canSkip(_ path: String, mtime: Int?, size: Int?) -> Bool {
        guard !candidates.contains(path) else { return false }
        if let inside, !inside.isEmpty, path.hasPrefix(inside + "/") { return false }
        guard let stamp = indexed[path], let mtime, let size else { return false }
        return stamp.mtime == mtime && stamp.size == size
    }
}

/// 검색 결과 하나. 화면에는 `Sendable` 값만 건넨다.
struct SearchHit: Identifiable, Hashable, Sendable {
    let relativePath: String
    let title: String
    /// 일치한 **줄** — 한글이 잘리지 않게 줄 단위로 자른다 (설계서 §7.5).
    let line: String
    /// 파일명이 맞은 것인가 (본문보다 앞에 세운다).
    let byTitle: Bool
    var id: String { relativePath }
}

/// 색인의 형편. 진단 화면이 보여 준다 (A4 · A5).
struct IndexStatus: Sendable {
    var noteCount = 0
    var trigramAvailable = false
    var lastRefresh: Date?
    var lastRefreshSeconds: Double = 0
    var fileBytes: Int = 0
    /// **제목만 넣은 노트** (245) — 아직 이 기기로 안 내려와 본문을 못 읽은 것. 검색 결과 아래 · 진단에 보인다.
    var titleOnlyCount = 0
    /// 안 받은 노트가 `SearchIndex.downloadLimit` 를 넘어 **내려받기를 시키지 않은** 때 (245).
    var downloadsWithheld = false
}

/// **SQLite FTS5 색인 — 캐시다** (ADR-0003). 언제 지워도 되고, 판이 다르면 통째로 다시 만든다.
/// 마이그레이션은 없다. SQLite 호출은 **이 파일에만** 있다 (CLAUDE.md §4).
///
/// 스키마는 ADR-0003 그대로: `note`(경로 · 제목 · 도장) + `note_fts`(trigram, 본문 사본).
/// 3글자 이상은 `MATCH`, 2글자 이하는 `LIKE` 폴백. 두 결과를 AND 로 교차한다.
actor SearchIndex {

    /// 스키마가 바뀌면 올린다 — 파일이 이 판이 아니면 지우고 새로 만든다.
    /// 색인 판. **규칙이 바뀌면 올린다** — 그러면 옛 파일은 버려지고 처음부터 다시 만든다
    /// (CLAUDE.md §1: 색인은 캐시다, 마이그레이션을 쓰지 않는다).
    ///
    /// - v2 (빌드 35 · 115): 미리보기 규칙이 바뀌었다(110 — 첫 줄은 제목이므로 건너뛴다).
    ///   판을 안 올렸더니 **고치지 않은 노트는 옛 미리보기를 그대로 들고 있었다** —
    ///   목록에 제목과 같은 글이 두 번 나왔다 (빌드 34 · 1번, 사용자).
    /// - v3 (빌드 103 · 242): 미리보기 줄을 보이는 글로(`PreviewLine`) — 링크는 제목만, `**` 등은 뗀다.
    /// - v4 (빌드 112 · 253 · 255): `note.links`(이 노트가 가리키는 폴더 안 경로 — 역링크를 여기서 찾는다) ·
    ///   `note_fts` 의 rowid 를 `note.id` 로 맞춤(지우기가 표 전체를 훑지 않게) · 트랜잭션.
    private static let version = 4

    /// **안 받은 노트가 이보다 많으면 내려받기를 시키지 않는다** (245, 2026-10-13 사용자 — *만약 수천개라면 유사한 상황이
    /// 발생할 가능성 · a 방식이 나을 것*). 그 아래면 예전처럼 받아서 본문까지 — 노트 150개쯤인 폴더는 본문 검색이 그대로다.
    /// 넘으면 안 받은 노트는 **제목만** 색인한다 (데이터 · 배터리). 사용자가 열면 그 노트는 내려오고, 다음 새로 고침에 본문까지 들어간다.
    static let downloadLimit = 500

    /// 제목만 넣은 줄의 `mtime` — 파일의 고친 시각과 늘 달라서, 다 내려오면 도장이 어긋나 본문까지 다시 읽는다.
    /// 표가 그대로라 색인 판은 올리지 않았다 (옛 색인에는 이 줄이 없을 뿐 — 다음 새로 고침이 채운다).
    private static let titleOnlyStamp = -1

    private var db: OpaquePointer?
    private let fileURL: URL
    private(set) var status = IndexStatus()

    /// 폴더마다 색인 하나. `Application Support/Index/<폴더 이름>-v<판>.sqlite`. **iCloud 로 안 간다.**
    init(for root: URL) {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        var folder = support.appendingPathComponent("Index", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        // **기기 백업에 넣지 않는다** (273) — 본문의 4배쯤 되는 캐시다 (노트 1만 개면 150MB). 백업에서 돌아오면 다시 만들면 된다.
        var backup = URLResourceValues()
        backup.isExcludedFromBackup = true
        try? folder.setResourceValues(backup)
        let stem = Paths.safeFileName(root.path.replacingOccurrences(of: "/", with: "_"), fallback: "root")
        let name = String(stem.suffix(120))
        fileURL = folder.appendingPathComponent("\(name)-v\(Self.version).sqlite")
        // 옛 판 색인은 지운다 — 판을 올릴 때마다 옛 파일이 그대로 남아 있었다 (242 에서 봄). 캐시라 지워도 된다.
        for old in 1..<Self.version {
            try? FileManager.default.removeItem(at: folder.appendingPathComponent("\(name)-v\(old).sqlite"))
        }
    }

    /// 손을 뗀다. 폴더를 바꿀 때 모델이 부른다 — 액터의 `deinit` 은 `OpaquePointer` 를
    /// 못 만지므로(Sendable 이 아니다) 닫기는 **명시적으로** 한다.
    func close() {
        if let db { sqlite3_close(db) }
        db = nil
    }

    // MARK: - 열기

    private func open() throws {
        if db != nil { return }
        var handle: OpaquePointer?
        guard sqlite3_open(fileURL.path, &handle) == SQLITE_OK, let handle else {
            throw IndexError.cannotOpen(fileURL.lastPathComponent)
        }
        db = handle
        status.trigramAvailable = probeTrigram()
        do {
            try prepareSchema()
        } catch {
            // 어긋난 파일이다 — 캐시니까 지우고 다시.
            sqlite3_close(handle)
            db = nil
            try? FileManager.default.removeItem(at: fileURL)
            var reopened: OpaquePointer?
            guard sqlite3_open(fileURL.path, &reopened) == SQLITE_OK, let reopened else {
                throw IndexError.cannotOpen(fileURL.lastPathComponent)
            }
            db = reopened
            try prepareSchema()
        }
    }

    /// **A4** — trigram 토크나이저가 이 기기의 SQLite 에 있는가. 없으면 전부 LIKE 로 간다.
    private func probeTrigram() -> Bool {
        guard let db else { return false }
        let sql = "CREATE VIRTUAL TABLE IF NOT EXISTS probe_trigram USING fts5(x, tokenize='trigram')"
        let ok = sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK
        sqlite3_exec(db, "DROP TABLE IF EXISTS probe_trigram", nil, nil, nil)
        return ok
    }

    private func prepareSchema() throws {
        let tokenize = status.trigramAvailable ? "trigram" : "unicode61"
        try exec("""
        CREATE TABLE IF NOT EXISTS note(
          id INTEGER PRIMARY KEY,
          rel_path TEXT UNIQUE NOT NULL,
          title TEXT NOT NULL,
          mtime INTEGER NOT NULL,
          size INTEGER NOT NULL,
          tags TEXT NOT NULL DEFAULT '',
          first_line TEXT NOT NULL DEFAULT '',
          links TEXT NOT NULL DEFAULT ''
        );
        CREATE VIRTUAL TABLE IF NOT EXISTS note_fts USING fts5(
          rel_path UNINDEXED, title, body, tags, tokenize='\(tokenize)'
        );
        """)
    }

    /// **한 묶음으로 쓴다** (255). 문장마다 자동 커밋(디스크 동기화)하던 것을 하나로 — 처음 색인이 노트 수 × 3번 커밋이었다.
    /// 안에서 던지면 되돌리고 다시 던진다.
    private func transaction<T>(_ body: () throws -> T) rethrows -> T {
        try? exec("BEGIN IMMEDIATE")
        do {
            let result = try body()
            try? exec("COMMIT")
            return result
        } catch {
            try? exec("ROLLBACK")
            throw error
        }
    }

    // MARK: - 새로 고침

    /// **받기를 시킨 노트** (254) — 제목만 넣은 줄은 도장이 늘 어긋나(`titleOnlyStamp`), 예전에는 새로 고침마다 그 노트들에
    /// 다시 받기를 시키고 자원값을 물었다. 한 번 시킨 것은 다 내려올 때까지 건너뛴다 (`isDownloaded` 가 참이 되면 본문을 읽는다).
    private var downloadRequested: Set<String> = []

    /// 목록의 도장과 색인의 도장을 견줘 **바뀐 것만** 다시 읽는다 (설계서 §7.5).
    /// 목록에 없는 것은 지운다. 읽기는 `reader` 가 한다 — 파일은 `FolderStore` 의 것이다.
    ///
    /// **취소를 본다** (254) — 부른 쪽이 접으면(`Task.isCancelled`) 그때까지 쓴 것을 남기고 물러난다. 다음 바퀴가 나머지를 한다.
    func refresh(_ notes: [NoteSummary], meter: WorkMeter = .none,
                 reader: @Sendable (String) async throws -> String) async -> Int {
        let started = Date()
        do { try open() } catch { return 0 }
        guard db != nil else { return 0 }

        var known: [String: (mtime: Int, size: Int)] = [:]
        for row in query("SELECT rel_path, mtime, size FROM note") {
            known[row[0]] = (Int(row[1]) ?? 0, Int(row[2]) ?? 0)
        }
        let wanted = Set(notes.map(\.relativePath))
        var changed = 0
        // 245 — 안 받은 노트가 많으면 내려받기를 시키지 않는다. `reader` 가 읽으려다 iCloud 에 받기를 시킨다.
        let pending = notes.reduce(0) { $0 + ($1.isDownloaded ? 0 : 1) }
        let fetchBodies = pending <= Self.downloadLimit
        status.downloadsWithheld = !fetchBodies

        // 본문은 묶음 밖에서 읽는다 (`await` — actor 가 다른 일을 받을 수 있다). 쓰기만 묶는다.
        var batch: [(NoteSummary, String)] = []
        var titleOnly: [NoteSummary] = []
        func flush() {
            guard !batch.isEmpty || !titleOnly.isEmpty else { return }
            transaction {
                for note in titleOnly { writeTitleOnly(note) }
                for (note, text) in batch { write(note, text: text) }
            }
            changed += batch.count + titleOnly.count
            batch = []
            titleOnly = []
        }
        // 다시 읽을 것만 먼저 고른다 — 몇 개 중 몇 개인지 띠에 보인다 (259).
        let stale = notes.filter { note in
            guard let old = known[note.relativePath] else { return true }
            return old.mtime != Int(note.modifiedAt.timeIntervalSince1970) || old.size != note.size
        }
        var seen = 0
        for note in stale {
            if Task.isCancelled { break }
            seen += 1
            meter.tick(seen, of: stale.count)
            let old = known[note.relativePath]
            // **본문을 못 읽는 노트도 제목으로는 찾히게** (245) — 예전에는 다 내려올 때까지 색인에 아예 없었다
            // (검색 · `[[` 목록 모두에서 빠졌다). 이미 줄이 있으면(옛 본문 · 제목만) 그대로 둔다 — 다 내려오면 바뀐다.
            if !note.isDownloaded {
                if old == nil { titleOnly.append(note) }
                // 받기는 한 번만 시킨다 (254). 시키는 길이 `reader` 라 한 번 불러 본다.
                if fetchBodies, !downloadRequested.contains(note.relativePath) {
                    downloadRequested.insert(note.relativePath)
                    _ = try? await reader(note.relativePath)
                }
                continue
            }
            downloadRequested.remove(note.relativePath)
            let text: String
            do {
                text = try await reader(note.relativePath)
            } catch {
                if old == nil { titleOnly.append(note) }
                continue
            }
            batch.append((note, text))
            if batch.count >= 50 { flush() }   // 50개마다 한 번 디스크에 — 접혀도 그만큼은 남는다
        }
        flush()
        if !Task.isCancelled {
            let gone = known.keys.filter { !wanted.contains($0) }
            if !gone.isEmpty {
                transaction { for path in gone { remove(path) } }
                changed += gone.count
            }
        }
        if changed > 0 || status.lastRefresh == nil { countRows() }
        status.lastRefresh = Date()
        status.lastRefreshSeconds = Date().timeIntervalSince(started)
        status.fileBytes = (try? FileManager.default.attributesOfItem(atPath: fileURL.path)[.size] as? Int) ?? 0
        return changed
    }

    /// **방금 저장한 노트 하나만** (254). 저장마다 폴더 전체를 훑지 않는다 — 글은 저장한 쪽이 이미 들고 있어 파일을 다시 읽지 않는다.
    /// 돌려주는 것은 목록에 보일 첫 줄 미리보기.
    func update(_ note: NoteSummary, text: String) -> String {
        do { try open() } catch { return "" }
        downloadRequested.remove(note.relativePath)
        return transaction { write(note, text: text) }
    }

    /// 제목을 따라 이름이 바뀌었다 (254) — 줄을 새 경로로. 본문은 그대로라 다시 읽지 않는다.
    func rename(from old: String, to new: String) {
        do { try open() } catch { return }
        transaction {
            // **찾기 표는 rowid 로** (276) — `rel_path` 는 색인 없는 열이라 표 전체를 훑었다 (255 의 지우기와 같은 모양이 여기 남았다).
            if let id = rowID(of: old) {
                run("UPDATE note_fts SET rel_path = ? WHERE rowid = ?", [.text(new), .int(id)])
            }
            run("UPDATE note SET rel_path = ? WHERE rel_path = ?", [new, old])
            // 다른 노트가 가리키던 이 노트의 경로도 (역링크가 따라오게). 그 노트들의 파일은 고치지 않는다 — 제목을 따라 이름을 바꿀 때
            // 링크를 고치지 않는 것과 같다. 경로 하나에 꼭 맞게 앞뒤 구분자까지.
            let from = Self.linksSeparator + old + Self.linksSeparator
            let to = Self.linksSeparator + new + Self.linksSeparator
            run("UPDATE note SET links = replace(links, ?, ?) WHERE instr(links, ?) > 0", [from, to, from])
        }
    }

    /// **폴더 이름이 바뀌거나 옮겨졌다** (276) — 그 안 노트들의 줄을 새 경로로 옮긴다. 파일의 시각 · 크기는 그대로라 다음 새로 고침이
    /// 본문을 **다시 읽지 않는다** (예전에는 폴더 안 노트를 모두 새 노트로 보고 다시 읽었다 — 3,000개면 10초 넘게).
    /// 다른 노트의 `links` 에 적힌 이 폴더 경로도 바꾼다 — 폴더 안 노트끼리의 링크는 글이 그대로라 다시 읽지 않는다.
    func renameFolder(from old: String, to new: String) {
        guard !old.isEmpty, old != new else { return }
        do { try open() } catch { return }
        let oldPrefix = old + "/", newPrefix = new + "/"
        // SQLite `substr` 는 **코드 포인트**로 센다 — Swift 의 `count`(글자 묶음)가 아니라 `unicodeScalars.count` 와 같다.
        let length = Int64(oldPrefix.unicodeScalars.count)
        transaction {
            run("UPDATE note_fts SET rel_path = ? || substr(rel_path, ?) WHERE rowid IN (SELECT id FROM note WHERE substr(rel_path, 1, ?) = ?)",
                [.text(newPrefix), .int(length + 1), .int(length), .text(oldPrefix)])
            run("UPDATE note SET rel_path = ? || substr(rel_path, ?) WHERE substr(rel_path, 1, ?) = ?",
                [.text(newPrefix), .int(length + 1), .int(length), .text(oldPrefix)])
            let from = Self.linksSeparator + oldPrefix, to = Self.linksSeparator + newPrefix
            run("UPDATE note SET links = replace(links, ?, ?) WHERE instr(links, ?) > 0", [from, to, from])
        }
    }

    // MARK: - 첨부 셈의 힌트 (268 · 269)

    /// **모든 노트 본문을 읽지 않아도 되게** (268 · 269, 2026-10-24 규모 점검 — 폴더 확인창 · 사진 든 노트 지우기가 금고의 모든 노트를 읽었다).
    /// 색인에 본문까지 든 노트의 도장과, 판정에 **들 수 있는** 노트를 준다. 파일 담당은 도장이 같고 후보가 아닌 노트를 읽지 않는다 —
    /// 그 노트의 본문은 색인이 이미 보았고 그 안에 찾는 이름 · 링크가 없다. 도장이 다르면(그 사이 고쳐짐 · 아직 색인 안 됨) 예전처럼 읽는다.
    /// 후보: 이름(`names` — 첨부 파일 이름)이 본문에 든 노트 · `paths` 를 링크로 가리키는 노트 · `folder` 안을 가리키는 노트.
    /// 이름은 첨부 셈(`AttachmentLedger.Usage`)과 같은 꼴로 견준다 — 작은 글자 · NFC · NFD · 퍼센트 꼴.
    /// `readingInside` — 폴더를 옮길 때만: 그 안의 노트도 늘 읽는다 (바깥으로 가는 링크가 바뀐다). 세기만 할 때는 안 읽는다.
    func censusHint(names: [String] = [], paths: [String] = [], linkingInto folder: String? = nil,
                    readingInside: Bool = false) -> CensusHint? {
        do { try open() } catch { return nil }
        var indexed: [String: IndexStamp] = [:]
        for row in query("SELECT rel_path, mtime, size FROM note WHERE mtime <> ?", [String(Self.titleOnlyStamp)]) {
            guard let mtime = Int(row[1]), let size = Int(row[2]) else { continue }
            indexed[row[0]] = IndexStamp(mtime: mtime, size: size)
        }
        var candidates: Set<String> = []
        var needles: Set<String> = []
        for name in names where !name.isEmpty {
            let lowered = Paths.normalized(name).lowercased()
            needles.insert(lowered)
            needles.insert(lowered.decomposedStringWithCanonicalMapping)
            let encoded = lowered.addingPercentEncoding(withAllowedCharacters: AttachmentLedger.quoteSafeCharacters) ?? lowered
            needles.insert(encoded.lowercased())
        }
        for needle in needles where !needle.isEmpty {
            for row in query("SELECT rel_path FROM note_fts WHERE instr(lower(body), ?) > 0", [needle]) { candidates.insert(row[0]) }
        }
        for path in paths where !path.isEmpty {
            let needle = Self.linksSeparator + Paths.normalized(path) + Self.linksSeparator
            for row in query("SELECT rel_path FROM note WHERE instr(links, ?) > 0", [needle]) { candidates.insert(row[0]) }
        }
        if let folder, !folder.isEmpty {
            let needle = Self.linksSeparator + Paths.normalized(folder) + "/"
            for row in query("SELECT rel_path FROM note WHERE instr(links, ?) > 0", [needle]) { candidates.insert(row[0]) }
        }
        return CensusHint(indexed: indexed, candidates: candidates, inside: readingInside ? folder : nil)
    }

    /// **이 노트를 가리키는 노트** (212 · 253). 색인할 때 적어 둔 `links` 에서 찾는다 — 예전에는 폴더의 모든 본문을 읽었다.
    /// 아직 안 내려와 제목만 넣은 노트는 못 센다 (예전과 같은 한계). 차례는 `AttachmentLedger.ordered` 와 같게.
    func backlinks(to path: String) -> [String] {
        do { try open() } catch { return [] }
        let needle = Self.linksSeparator + Paths.normalized(path) + Self.linksSeparator
        let rows = query("SELECT rel_path FROM note WHERE rel_path <> ? AND instr(links, ?) > 0", [path, needle])
        return AttachmentLedger.ordered(rows.map { $0[0] })
    }

    /// `links` 열의 구분자 — 경로에는 줄바꿈이 없다. 앞뒤에도 두어 `instr` 가 경로 하나에 꼭 맞게.
    private static let linksSeparator = "\n"

    /// 노트 한 줄을 쓴다 — `note` 표 · `note_fts` (rowid = note.id). 돌려주는 것은 첫 줄 미리보기.
    @discardableResult
    private func write(_ note: NoteSummary, text: String) -> String {
        let mtime = Int(note.modifiedAt.timeIntervalSince1970)
        let parsed = FrontMatterParser.parse(text)
        let tags = " " + (parsed.frontMatter?.tags ?? []).map { Paths.normalized($0) }.joined(separator: " ") + " "
        let firstLine = Self.firstBodyLine(of: parsed.body)
        // 253 — 이 노트가 가리키는 폴더 안 경로 (역링크 · 폴더 링크 셈과 같은 `linkTargets`).
        let targets = AttachmentLedger.linkTargets(of: note.relativePath, text: text)
        let links = targets.isEmpty ? "" : Self.linksSeparator + targets.joined(separator: Self.linksSeparator) + Self.linksSeparator
        run("""
        INSERT INTO note(rel_path, title, mtime, size, tags, first_line, links) VALUES(?,?,?,?,?,?,?)
        ON CONFLICT(rel_path) DO UPDATE SET title=excluded.title, mtime=excluded.mtime,
          size=excluded.size, tags=excluded.tags, first_line=excluded.first_line, links=excluded.links
        """, [note.relativePath, note.title, String(mtime), String(note.size), tags, firstLine, links])
        guard let id = rowID(of: note.relativePath) else { return firstLine }
        run("DELETE FROM note_fts WHERE rowid = ?", [.int(id)])
        run("INSERT INTO note_fts(rowid, rel_path, title, body, tags) VALUES(?,?,?,?,?)",
            [.int(id), .text(note.relativePath), .text(note.title), .text(text), .text(tags)])
        return firstLine
    }

    /// **제목만** 넣는다 (245) — 본문 · 태그 · 미리보기 · 링크는 비운다. `mtime` 은 `titleOnlyStamp`.
    private func writeTitleOnly(_ note: NoteSummary) {
        run("""
        INSERT INTO note(rel_path, title, mtime, size, tags, first_line, links) VALUES(?,?,?,?,?,?,?)
        ON CONFLICT(rel_path) DO UPDATE SET title=excluded.title, mtime=excluded.mtime,
          size=excluded.size, tags=excluded.tags, first_line=excluded.first_line, links=excluded.links
        """, [note.relativePath, note.title, String(Self.titleOnlyStamp), String(note.size), "", "", ""])
        guard let id = rowID(of: note.relativePath) else { return }
        run("DELETE FROM note_fts WHERE rowid = ?", [.int(id)])
        run("INSERT INTO note_fts(rowid, rel_path, title, body, tags) VALUES(?,?,?,?,?)",
            [.int(id), .text(note.relativePath), .text(note.title), .text(""), .text("")])
    }

    /// `note` 표의 번호 — `note_fts` 의 rowid 와 같다.
    private func rowID(of path: String) -> Int64? {
        query("SELECT id FROM note WHERE rel_path = ?", [path]).first?.first.flatMap { Int64($0) }
    }

    private func remove(_ path: String) {
        if let id = rowID(of: path) { run("DELETE FROM note_fts WHERE rowid = ?", [.int(id)]) }
        run("DELETE FROM note WHERE rel_path = ?", [path])
    }

    private func countRows() {
        status.noteCount = Int(query("SELECT COUNT(*) FROM note").first?.first ?? "0") ?? 0
        status.titleOnlyCount = Int(query("SELECT COUNT(*) FROM note WHERE mtime = ?",
                                          [String(Self.titleOnlyStamp)]).first?.first ?? "0") ?? 0
    }

    /// 목록의 **첫 줄 미리보기** — 색인에서만 가져온다 (설계서 §7.5). 색인 전이면 빈칸.
    func firstLines() -> [String: String] {
        do { try open() } catch { return [:] }
        var result: [String: String] = [:]
        for row in query("SELECT rel_path, first_line FROM note") { result[row[0]] = row[1] }
        return result
    }

    /// 통째로 지우고 처음부터. 설정 · 진단의 **색인 다시 만들기**.
    func reset() {
        if let db { sqlite3_close(db) }
        db = nil
        try? FileManager.default.removeItem(at: fileURL)
        status = IndexStatus()
        downloadRequested = []
    }

    // MARK: - 검색

    /// 파일명 일치를 앞에, 본문 일치를 뒤에 (설계서 §6-E). 최대 200개.
    /// **제목에 이 말이 든 노트** (147 — 타이핑으로 노트 연결하기).
    ///
    /// 본문은 안 본다. 고르려고 보는 목록이라 짧아야 쓸 만하다 — 본문까지 훑으면 엉뚱한
    /// 것이 잔뜩 섞인다. 자기 자신은 뺀다.
    ///
    /// `LIKE` 하나다. FTS 를 안 쓰는 까닭은 **두 글자짜리 제목**도 찾아야 하기 때문이다
    /// (`SearchQuery` 가 짧은 말을 `LIKE` 로 돌리는 것과 같은 이유).
    func titles(matching raw: String, excluding own: String?, limit: Int = 8) -> [SearchHit] {
        let term = Paths.normalized(raw).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else { return [] }

        var binds = [SearchQueryParser.likePattern(for: term)]
        var sql = "SELECT rel_path, title FROM note WHERE title LIKE ? ESCAPE '\\'"
        if let own, !own.isEmpty {
            sql += " AND rel_path <> ?"
            binds.append(own)
        }
        sql += " ORDER BY length(title), title LIMIT \(max(1, limit))"

        return query(sql, binds).map { row in
            SearchHit(relativePath: row[0], title: row[1], line: "", byTitle: true)
        }
    }

    /// 찾기 결과의 한도 (272). 넘으면 화면이 *여기까지만* 이라고 알린다 — 말없이 자르지 않는다.
    static let resultLimit = 200

    func search(_ raw: String) -> SearchResults {
        do { try open() } catch { return SearchResults(hits: [], truncated: false) }
        var (hits, truncated) = textHits(raw)
        // **제목 초성** (246) — 말이 한글 자음만이면 제목의 첫소리와도 견준다. 보통 검색에 **더한다**
        // (본문에 `ㅎㅎ` 를 쓴 노트도 그대로 찾힌다). 제목 수천 개도 한순간이라 표를 따로 두지 않는다.
        if let initials = HangulInitials.query(raw) {
            var seen = Set(hits.map(\.relativePath))
            for row in query("SELECT rel_path, title, first_line FROM note")
            where HangulInitials.matches(title: row[1], query: initials) {
                guard seen.insert(row[0]).inserted else { continue }
                hits.append(SearchHit(relativePath: row[0], title: row[1], line: row[2], byTitle: true))
            }
        }
        let sorted = hits.sorted { a, b in
            if a.byTitle != b.byTitle { return a.byTitle }
            return a.title.localizedStandardCompare(b.title) == .orderedAscending
        }
        // 초성으로 더한 것까지 한도 안에서 — 제목이 맞은 것이 앞이라 잘려도 제목은 남는다.
        if sorted.count > Self.resultLimit { truncated = true }
        return SearchResults(hits: Array(sorted.prefix(Self.resultLimit)), truncated: truncated)
    }

    /// 보통 검색 — 3글자 이상은 `MATCH`, 짧은 말은 `LIKE`. 차례는 `search` 가 세운다.
    /// **제목이 맞는 노트를 먼저 뽑는다** (272) — 예전에는 아무 차례로 200개를 받은 뒤에 제목을 앞에 세워, 흔한 말이면 제목이 맞는
    /// 노트가 200개 밖으로 밀릴 수 있었다. 이제 제목에서 맞은 것을 먼저 받고, 남은 자리를 본문에서 맞은 것으로 채운다.
    private func textHits(_ raw: String) -> (hits: [SearchHit], truncated: Bool) {
        let queryText = SearchQueryParser.parse(raw)
        guard !queryText.isEmpty else { return ([], false) }

        // trigram 이 없으면 전부 LIKE 로 (A4 후퇴).
        var q = queryText
        if !status.trigramAvailable {
            q.likeTerms += q.ftsTerms
            q.ftsTerms = []
        }

        var conditions: [String] = []
        var binds: [String] = []
        if let match = SearchQueryParser.ftsExpression(for: q) {
            conditions.append("note_fts MATCH ?")
            binds.append(match)
        }
        for pattern in SearchQueryParser.likePatterns(for: q) {
            conditions.append("(body LIKE ? ESCAPE '\\' OR title LIKE ? ESCAPE '\\')")
            binds.append(pattern); binds.append(pattern)
        }
        for pattern in SearchQueryParser.tagLikePatterns(for: q) {
            conditions.append("tags LIKE ? ESCAPE '\\'")
            binds.append(pattern)
        }
        if let prefix = q.pathPrefix {
            conditions.append("rel_path LIKE ? ESCAPE '\\'")
            // `%prefix%` 에서 앞 `%` 만 뗀다 — 경로는 **앞부터** 맞아야 한다.
            binds.append(String(SearchQueryParser.likePattern(for: prefix).dropFirst()))
        }
        guard !conditions.isEmpty else { return ([], false) }

        let terms = (q.ftsTerms + q.likeTerms).map { $0.lowercased() }
        let base = "SELECT rel_path, title, body FROM note_fts WHERE " + conditions.joined(separator: " AND ")
        // 제목에 낱말이 다 든 것 먼저 — 같은 조건에 제목 조건을 더한다.
        var rows: [[String]] = []
        if !terms.isEmpty {
            let titleConditions = terms.map { _ in "title LIKE ? ESCAPE '\\'" }.joined(separator: " AND ")
            rows = query(base + " AND " + titleConditions + " LIMIT \(Self.resultLimit)",
                         binds + terms.map { SearchQueryParser.likePattern(for: $0) })
        }
        // 나머지 — 한 줄 더 받아 넘치는지 안다.
        let rest = query(base + " LIMIT \(Self.resultLimit + rows.count + 1)", binds)
        var hits: [SearchHit] = []
        var seen: Set<String> = []
        var truncated = false
        for row in rows + rest {
            let path = row[0], title = row[1], body = row[2]
            // 같은 경로가 두 번 오면 목록의 이름표(`id`)가 겹친다 — 화면이 어긋나거나 꺼진다 (184). 제목에서 받은 것이 뒤에서 또 온다.
            guard !seen.contains(path) else { continue }
            // 한도가 찬 뒤에 **새** 노트가 또 오면 넘친 것이다.
            guard hits.count < Self.resultLimit else { truncated = true; break }
            seen.insert(path)
            let byTitle = terms.contains { title.lowercased().contains($0) }
            let line = Self.matchingLine(in: body, terms: terms, skipping: title)
                ?? Self.firstBodyLine(of: FrontMatterParser.parse(body).body)
            hits.append(SearchHit(relativePath: path, title: title, line: line, byTitle: byTitle))
        }
        return (hits, truncated)
    }

    // MARK: - 줄 고르기 (순수)

    /// 낱말 하나라도 든 **첫 줄**. 머리말 · 빈 줄 · 제목 표시는 건너뛴다.
    /// `skipping` 은 제목 — 제목이 맞은 노트에서 제목 줄을 되풀이하지 않는다 (80).
    /// 맞는지는 **원문 줄**로 보고(주소 속 낱말도 찾는다), 보여 주는 것은 **보이는 글**이다 (242 — `shown`).
    static func matchingLine(in text: String, terms: [String], skipping title: String = "") -> String? {
        let body = FrontMatterParser.parse(text).body
        for line in body.components(separatedBy: "\n") {
            let lowered = line.lowercased()
            guard terms.contains(where: { lowered.contains($0) }) else { continue }
            let cleaned = shown(line)
            if cleaned.isEmpty || cleaned == title { continue }
            return cleaned
        }
        return nil
    }

    /// 본문의 첫 글줄 — 제목 줄(`# `)은 목록에 이미 있으니 건너뛴다.
    static func firstBodyLine(of body: String) -> String {
        var passedTitle = false
        for line in body.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { continue }
            // 글자가 한 자도 없는 줄(`---` 수평선 · 장식)은 제목도 미리보기도 아니다 (107 과 같은 규칙).
            guard trimmed.contains(where: { $0.isLetter || $0.isNumber }) else { continue }
            // **첫 줄은 제목이다** (107). 목록에 이미 그것이 보이므로 건너뛴다 —
            // 안 건너뛰면 제목과 미리보기에 **같은 글이 두 번** 나온다 (빌드 33 · 5번, 사용자).
            // 예전에는 `#` 로 시작하는 줄만 건너뛰었다. 이제 제목에 `#` 이 없을 수 있다.
            if !passedTitle {
                passedTitle = true
                continue
            }
            // 보이는 글이 없는 줄(대체 글 없는 사진 `![](…)` 하나 등)은 건너뛴다.
            let cleaned = shown(trimmed)
            if cleaned.isEmpty { continue }
            return cleaned
        }
        return ""
    }

    /// **화면에 보이는 한 줄** (242 — 2026-10-12 사용자 미리보기 영상 검토: 검색 결과에 `[시니어 명소](<>)` 가,
    /// 목록에 `**…**` 가 원문째 보였다). 블록 표시 · 링크 · 굵게 등은 `Core.PreviewLine` 이 읽는다 — markdown-it 이
    /// 심판한 정답표로 시험한다. 예전 `tidy` 는 앞의 `#` `>` `-` `*` 만 떼서 `**굵게**` 로 시작하는 줄의 별까지 떼었다.
    static func shown(_ line: String) -> String {
        String(PreviewLine.plain(line).prefix(120))
    }

    // MARK: - SQLite 속

    enum IndexError: Error { case cannotOpen(String), sql(String) }

    private static let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    private func exec(_ sql: String) throws {
        guard let db else { return }
        var message: UnsafeMutablePointer<CChar>?
        guard sqlite3_exec(db, sql, nil, nil, &message) == SQLITE_OK else {
            let text = message.map { String(cString: $0) } ?? "?"
            sqlite3_free(message)
            throw IndexError.sql(text)
        }
    }

    @discardableResult
    private func run(_ sql: String, _ binds: [String]) -> Bool {
        run(sql, binds.map(Bind.text))
    }

    /// 문장에 넣을 값 — 글자 또는 정수. rowid 는 **정수로** 넣어야 한다 (255) — 글자 `'12'` 를 넣으면 FTS5 가 자료형이 다르다고 거절한다.
    private enum Bind {
        case text(String)
        case int(Int64)
    }

    @discardableResult
    private func run(_ sql: String, _ binds: [Bind]) -> Bool {
        guard let db else { return false }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else { return false }
        defer { sqlite3_finalize(statement) }
        bindAll(binds, to: statement)
        return sqlite3_step(statement) == SQLITE_DONE
    }

    private func bindAll(_ binds: [Bind], to statement: OpaquePointer) {
        for (index, value) in binds.enumerated() {
            switch value {
            case .text(let text): sqlite3_bind_text(statement, Int32(index + 1), text, -1, Self.transient)
            case .int(let number): sqlite3_bind_int64(statement, Int32(index + 1), number)
            }
        }
    }

    private func query(_ sql: String, _ binds: [String] = []) -> [[String]] {
        guard let db else { return [] }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else { return [] }
        defer { sqlite3_finalize(statement) }
        for (index, value) in binds.enumerated() {
            sqlite3_bind_text(statement, Int32(index + 1), value, -1, Self.transient)
        }
        var rows: [[String]] = []
        let columns = Int(sqlite3_column_count(statement))
        while sqlite3_step(statement) == SQLITE_ROW {
            var row: [String] = []
            for column in 0..<columns {
                if let text = sqlite3_column_text(statement, Int32(column)) {
                    row.append(String(cString: text))
                } else {
                    row.append("")
                }
            }
            rows.append(row)
        }
        return rows
    }
}
