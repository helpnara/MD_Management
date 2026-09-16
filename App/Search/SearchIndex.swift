import Foundation
import SQLite3
import Core

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
    private static let version = 2

    private var db: OpaquePointer?
    private let fileURL: URL
    private(set) var status = IndexStatus()

    /// 폴더마다 색인 하나. `Application Support/Index/<폴더 이름>-v1.sqlite`. **iCloud 로 안 간다.**
    init(for root: URL) {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let folder = support.appendingPathComponent("Index", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let stem = Paths.safeFileName(root.path.replacingOccurrences(of: "/", with: "_"), fallback: "root")
        fileURL = folder.appendingPathComponent("\(String(stem.suffix(120)))-v\(Self.version).sqlite")
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
          first_line TEXT NOT NULL DEFAULT ''
        );
        CREATE VIRTUAL TABLE IF NOT EXISTS note_fts USING fts5(
          rel_path UNINDEXED, title, body, tags, tokenize='\(tokenize)'
        );
        """)
    }

    // MARK: - 새로 고침

    /// 목록의 도장과 색인의 도장을 견줘 **바뀐 것만** 다시 읽는다 (설계서 §7.5).
    /// 목록에 없는 것은 지운다. 읽기는 `reader` 가 한다 — 파일은 `FolderStore` 의 것이다.
    func refresh(_ notes: [NoteSummary], reader: @Sendable (String) async throws -> String) async -> Int {
        let started = Date()
        do { try open() } catch { return 0 }
        guard let db else { return 0 }

        var known: [String: (mtime: Int, size: Int)] = [:]
        for row in query("SELECT rel_path, mtime, size FROM note") {
            known[row[0]] = (Int(row[1]) ?? 0, Int(row[2]) ?? 0)
        }
        let wanted = Set(notes.map(\.relativePath))
        var changed = 0

        for note in notes {
            let mtime = Int(note.modifiedAt.timeIntervalSince1970)
            if let old = known[note.relativePath], old.mtime == mtime, old.size == note.size { continue }
            guard let text = try? await reader(note.relativePath) else { continue }
            let parsed = FrontMatterParser.parse(text)
            let tags = " " + (parsed.frontMatter?.tags ?? []).map { Paths.normalized($0) }.joined(separator: " ") + " "
            let firstLine = Self.firstBodyLine(of: parsed.body)
            run("DELETE FROM note_fts WHERE rel_path = ?", [note.relativePath])
            run("INSERT INTO note_fts(rel_path, title, body, tags) VALUES(?,?,?,?)",
                [note.relativePath, note.title, text, tags])
            run("""
            INSERT INTO note(rel_path, title, mtime, size, tags, first_line) VALUES(?,?,?,?,?,?)
            ON CONFLICT(rel_path) DO UPDATE SET title=excluded.title, mtime=excluded.mtime,
              size=excluded.size, tags=excluded.tags, first_line=excluded.first_line
            """, [note.relativePath, note.title, String(mtime), String(note.size), tags, firstLine])
            changed += 1
        }
        for path in known.keys where !wanted.contains(path) {
            run("DELETE FROM note WHERE rel_path = ?", [path])
            run("DELETE FROM note_fts WHERE rel_path = ?", [path])
            changed += 1
        }
        _ = db
        status.noteCount = Int(query("SELECT COUNT(*) FROM note").first?.first ?? "0") ?? 0
        status.lastRefresh = Date()
        status.lastRefreshSeconds = Date().timeIntervalSince(started)
        status.fileBytes = (try? FileManager.default.attributesOfItem(atPath: fileURL.path)[.size] as? Int) ?? 0
        return changed
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
    }

    // MARK: - 검색

    /// 파일명 일치를 앞에, 본문 일치를 뒤에 (설계서 §6-E). 최대 200개.
    func search(_ raw: String) -> [SearchHit] {
        let queryText = SearchQueryParser.parse(raw)
        guard !queryText.isEmpty else { return [] }
        do { try open() } catch { return [] }

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
        guard !conditions.isEmpty else { return [] }

        let sql = "SELECT rel_path, title, body FROM note_fts WHERE " + conditions.joined(separator: " AND ") + " LIMIT 200"
        let terms = (q.ftsTerms + q.likeTerms).map { $0.lowercased() }
        var hits: [SearchHit] = []
        for row in query(sql, binds) {
            let path = row[0], title = row[1], body = row[2]
            let byTitle = terms.contains { title.lowercased().contains($0) }
            let line = Self.matchingLine(in: body, terms: terms, skipping: title)
                ?? Self.firstBodyLine(of: FrontMatterParser.parse(body).body)
            hits.append(SearchHit(relativePath: path, title: title, line: line, byTitle: byTitle))
        }
        return hits.sorted { a, b in
            if a.byTitle != b.byTitle { return a.byTitle }
            return a.title.localizedStandardCompare(b.title) == .orderedAscending
        }
    }

    // MARK: - 줄 고르기 (순수)

    /// 낱말 하나라도 든 **첫 줄**. 머리말 · 빈 줄 · 제목 표시는 건너뛴다.
    /// `skipping` 은 제목 — 제목이 맞은 노트에서 제목 줄을 되풀이하지 않는다 (80).
    static func matchingLine(in text: String, terms: [String], skipping title: String = "") -> String? {
        let body = FrontMatterParser.parse(text).body
        for line in body.components(separatedBy: "\n") {
            let cleaned = tidy(line)
            if cleaned.isEmpty || cleaned == title { continue }
            let lowered = line.lowercased()
            if terms.contains(where: { lowered.contains($0) }) {
                return cleaned
            }
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
            return tidy(trimmed)
        }
        return ""
    }

    private static func tidy(_ line: String) -> String {
        var s = line.trimmingCharacters(in: .whitespaces)
        while s.hasPrefix("#") || s.hasPrefix(">") || s.hasPrefix("-") || s.hasPrefix("*") {
            s = String(s.dropFirst()).trimmingCharacters(in: .whitespaces)
        }
        return String(s.prefix(120))
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
        guard let db else { return false }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else { return false }
        defer { sqlite3_finalize(statement) }
        for (index, value) in binds.enumerated() {
            sqlite3_bind_text(statement, Int32(index + 1), value, -1, Self.transient)
        }
        return sqlite3_step(statement) == SQLITE_DONE
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
