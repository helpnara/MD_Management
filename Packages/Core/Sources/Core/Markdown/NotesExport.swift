import Foundation

/// **메모의 *마크다운으로 보내기* 를 앱의 꼴로** (289, 2026-11-01 사용자 — *이런 파일이 많다고 생각할때*).
///
/// 메모는 노트마다 폴더 하나로 내보낸다 — `노트/노트.md` + `노트/Attachments/UUID.jpeg`. 그대로 넣어도 사진 · 링크는 보이지만
/// 노트마다 폴더가 생기고 `Attachments` 가 폴더 목록에 서며 *안 쓰는 첨부* 가 그 사진들을 못 본다(`assets` 만 본다).
/// 그래서 앱이 원래 만드는 꼴로 옮겨 적는다 — **한 폴더에 노트를 나란히, 첨부는 그 폴더의 `assets/` 로, 링크는 새 자리에 맞춰.**
///
/// 여기는 **무엇을 어디로** 만 정한다(순수 함수). 읽고 쓰는 것은 앱(`LibraryModel.importNotesExport`)이 한다.
/// - 고른 폴더 안의 모든 노트(`.md` · `.markdown` · `.txt`)를 깊이와 상관없이 모은다 — 한 노트를 내보낸 폴더를 골라도, 여럿을 모은 폴더를 골라도 된다.
/// - 노트가 아닌 파일은 모두 첨부로 `assets/` 에. 메모의 첨부 이름은 UUID 라 겹치지 않지만, 겹치면 `이름 2.png` 처럼 번호를 붙이고 링크도 그 이름으로.
/// - 맥이 압축할 때 끼워 넣는 꼬리 파일(`__MACOSX/` · `._…` · `.DS_Store`)과 숨김 파일은 건너뛴다.
/// - 이름은 NFC 로 (CLAUDE.md §4 — 맥 압축은 NFD 로 온다).
public enum NotesExport {

    /// 하나를 어디서 어디로. `source` 는 고른 폴더 기준, `destination` 은 금고 기준.
    public struct Move: Equatable, Sendable {
        public let source: String
        public let destination: String

        public init(source: String, destination: String) {
            self.source = source
            self.destination = destination
        }
    }

    public struct Plan: Equatable, Sendable {
        public let notes: [Move]
        public let files: [Move]
        /// 건너뛴 꼬리 · 숨김 파일 (고른 폴더 기준).
        public let skipped: [String]

        public init(notes: [Move], files: [Move], skipped: [String]) {
            self.notes = notes
            self.files = files
            self.skipped = skipped
        }

        /// 옛 자리(고른 폴더 기준) → 새 자리(금고 기준). 링크를 고칠 때 쓴다.
        public var moves: [String: String] {
            var out: [String: String] = [:]
            for move in notes + files { out[move.source] = move.destination }
            return out
        }
    }

    /// 맥 압축의 꼬리 · 숨김 파일인가 — 경로의 어느 조각이 `__MACOSX` 이거나 `.` 으로 시작하면.
    public static func isJunk(_ path: String) -> Bool {
        path.split(separator: "/").contains { $0 == "__MACOSX" || $0.hasPrefix(".") }
    }

    /// 무엇을 어디로. `files` 는 고른 폴더 안의 **파일** 경로들(폴더 빼고), `folder` 는 넣을 금고 안 폴더.
    /// `taken` 은 그 폴더에 이미 있는 이름들(노트 · `assets/` 안) — 덮어쓰지 않는다.
    public static func plan(files: [String], into folder: String, taken: Set<String> = []) -> Plan {
        let base = Paths.normalized(folder)
        let all = files.map(Paths.normalized).sorted()
        var used = Set(taken.map { Paths.normalized($0).lowercased() })
        var notes: [Move] = []
        var attachments: [Move] = []
        var skipped: [String] = []
        for path in all {
            if isJunk(path) {
                skipped.append(path)
                continue
            }
            let name = String(path.split(separator: "/").last ?? Substring(path))
            if Paths.isNoteFile(path) {
                let unique = uniqueName(name, in: base, used: &used)
                notes.append(Move(source: path, destination: join(base, unique)))
            } else {
                let assets = join(base, "assets")
                let unique = uniqueName(name, in: assets, used: &used)
                attachments.append(Move(source: path, destination: join(assets, unique)))
            }
        }
        return Plan(notes: notes, files: attachments, skipped: skipped)
    }

    /// **노트 한 편을 새 자리의 글로** — 줄바꿈 · 빈칸 글자를 고치고(287), 고른 폴더 안을 가리키던 링크를 새 자리로 고쳐 적는다.
    /// `source` 는 이 노트의 옛 자리(고른 폴더 기준), `destination` 은 새 자리(금고 기준). 바깥 주소 · 앵커 · 없는 파일은 그대로다.
    /// 줄바꿈을 **먼저** 고친다 — 링크 주소를 읽는 걸음(`MarkdownLinks.destination`)은 `\n` 에서만 멈춘다.
    public static func converted(_ text: String, source: String, destination: String,
                                 moves: [String: String]) -> String {
        relinked(LineBreaks.repaired(text), source: source, destination: destination, moves: moves)
    }

    /// 링크만 고친다. `MarkdownLinks.rebased` 와 같은 걸음 — `](` 뒤의 주소 하나씩.
    public static func relinked(_ text: String, source: String, destination: String,
                                moves: [String: String]) -> String {
        guard text.contains("](") else { return text }
        let note = Paths.normalized(source)
        let newFolder = Paths.directory(of: Paths.normalized(destination))
        var out = ""
        var cursor = text.startIndex
        while let bracket = text.range(of: "](", range: cursor..<text.endIndex) {
            out += text[cursor..<bracket.upperBound]
            cursor = bracket.upperBound
            guard let piece = MarkdownLinks.destination(in: text, from: cursor) else { continue }
            out += relink(piece.raw, note: note, newFolder: newFolder, moves: moves)
            out += text[piece.end..<text.index(after: piece.end)]   // 닫는 `)`
            cursor = text.index(after: piece.end)
        }
        out += text[cursor...]
        return out
    }

    private static func relink(_ raw: String, note: String, newFolder: String, moves: [String: String]) -> String {
        let wrapped = raw.hasPrefix("<") && raw.hasSuffix(">") && raw.count >= 2
        let inner = wrapped ? String(raw.dropFirst().dropLast()) : raw
        var anchor = ""
        var target = inner
        if let hash = inner.firstIndex(of: "#"), hash != inner.startIndex {
            anchor = String(inner[hash...])
            target = String(inner[inner.startIndex..<hash])
        }
        guard case .relative(let resolved) = Paths.resolve(link: target, fromNoteAt: note),
              let moved = moves[resolved] else { return raw }
        let link = Paths.relativeLink(from: newFolder, to: moved) + anchor
        return (wrapped || link.contains(" ")) ? "<" + link + ">" : link
    }

    /// 겹치지 않는 이름 — `이름.png` · `이름 2.png` · `이름 3.png`. 대소문자 · 정규화를 가리지 않고 견준다.
    private static func uniqueName(_ name: String, in folder: String, used: inout Set<String>) -> String {
        let dot = name.lastIndex(of: ".").flatMap { $0 == name.startIndex ? nil : $0 }
        let stem = dot.map { String(name[name.startIndex..<$0]) } ?? name
        let ext = dot.map { String(name[$0...]) } ?? ""
        var candidate = name
        var number = 2
        while used.contains(join(folder, candidate).lowercased()) {
            candidate = stem + " \(number)" + ext
            number += 1
        }
        used.insert(join(folder, candidate).lowercased())
        return candidate
    }

    private static func join(_ folder: String, _ name: String) -> String {
        folder.isEmpty ? name : folder + "/" + name
    }
}
