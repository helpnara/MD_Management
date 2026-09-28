import Foundation

/// **누가 어떤 첨부를 쓰나** — 172 · 173 · 174 가 모두 이 셈 하나를 부른다.
///
/// - 노트를 지울 때 같이 휴지통으로 보낼 첨부 (`trashing` · 172)
/// - 휴지통에서 노트 하나를 영구 삭제할 때 같이 지울 첨부 (`purging` · 173)
/// - 설정의 **안 쓰는 첨부** (`unused` · 174)
///
/// 셋이 따로 세면 언젠가 갈린다 (CLAUDE.md §1). 172 가 바로 그 모양이었다 — 지우는 쪽은
/// **같은 폴더의 노트만** 봤는데, 옮기기(T1) · 붙여넣기(144)가 이미 `../회의/assets/a.png`
/// 같은 폴더 밖 링크를 만들고 있었다.
///
/// **의심스러우면 쓰는 것이다.** 잘못 남기면 용량이지만, 잘못 치우면 사진이 깨진다.
/// - 폴더 **전체**의 노트를 본다.
/// - 표준 링크가 아니어도 **파일 이름이 본문 어디에든 있으면** 쓰는 것이다 — `![[a.png]]` ·
///   `<img src>` · 머리말의 표지. 대소문자를 가리지 않는다(기기의 파일 시스템이 안 가린다).
/// - **못 읽은 노트**(아직 안 내려받음)가 하나라도 있으면 판정하지 않는다.
/// - 휴지통의 노트가 쓰는 것도 쓰는 것이다 — 되돌리면 같이 돌아와야 한다 (56).
///
/// 파일을 읽지 않는다. `(경로 → 본문, 못 읽었으면 nil)` 과 파일 목록을 받는다 — 그래서
/// 리눅스 `swift test` 가 심판이 된다. 기댓값은 `Tools/golden/generate.py` 의
/// `attachmentCases` (파이썬으로 따로 계산).
public enum AttachmentLedger {

    /// 휴지통 경로의 원래 자리. `.trash/회의/a.png` → `회의/a.png`.
    public static func originalPath(of path: String) -> String {
        path.hasPrefix(".trash/") ? String(path.dropFirst(".trash/".count)) : path
    }

    /// 정리 후보인가 — **살아 있는** `assets/` 안의 파일(깊이 무관). 사용자가 둔 다른
    /// 파일은 앱의 것이 아니다.
    public static func isAttachmentPath(_ path: String) -> Bool {
        guard !path.hasPrefix(".trash/") else { return false }
        return path.split(separator: "/").dropLast().contains("assets")
    }

    /// 설정의 **안 쓰는 첨부.** 못 읽은 노트가 있으면 `nil` — 판정하지 않는다.
    public static func unused(notes: [String: String?],
                              trashed: [String: String?],
                              files: Set<String>) -> [String]? {
        guard notes.values.allSatisfy({ $0 != nil }) else { return nil }
        let live = notes.compactMapValues { $0 }
        let bin = trashed.compactMapValues { $0 }
        let everyone = Usage(live.merging(bin) { first, _ in first })
        let restored = Usage(Dictionary(bin.map { (originalPath(of: $0.key), $0.value) }) { first, _ in first },
                             mentions: false)
        return ordered(files).filter { path in
            isAttachmentPath(path) && !everyone.uses(path) && !restored.uses(path)
        }
    }

    /// 노트를 지울 때 **같이 휴지통으로 보낼 첨부** (172). 이 노트가 가리키고, 폴더 안의
    /// 어느 노트(휴지통 노트 포함)도 안 쓰는 것만. 판정할 수 없으면 빈 목록 — 아무것도 안 보낸다.
    public static func trashing(_ note: String,
                                notes: [String: String?],
                                trashed: [String: String?],
                                files: Set<String>) -> [String] {
        guard let text = notes[note] ?? nil else { return [] }
        let others = notes.filter { $0.key != note }
        guard others.values.allSatisfy({ $0 != nil }) else { return [] }
        let bin = trashed.compactMapValues { $0 }
        let everyone = Usage(others.compactMapValues { $0 }.merging(bin) { first, _ in first })
        let restored = Usage(Dictionary(bin.map { (originalPath(of: $0.key), $0.value) }) { first, _ in first },
                             mentions: false)
        return ordered(preciseReferences(of: note, text: text)).filter { path in
            files.contains(path) && !path.hasPrefix(".trash/")
                && !everyone.uses(path) && !restored.uses(path)
        }
    }

    /// 휴지통에서 노트 하나를 **영구 삭제할 때 같이 지울 첨부** (173).
    /// 휴지통의 다른 노트가 쓰거나, 살아 있는 노트가 **원래 자리**를 가리키는데 거기 파일이
    /// 없으면(이것이 유일한 사본) 남긴다.
    public static func purging(_ note: String,
                               notes: [String: String?],
                               trashed: [String: String?],
                               files: Set<String>) -> [String] {
        guard let text = trashed[note] ?? nil,
              notes.values.allSatisfy({ $0 != nil }) else { return [] }
        let others = trashed.filter { $0.key != note }.compactMapValues { $0 }
        let inBin = Usage(others)
        let restored = Usage(Dictionary(others.map { (originalPath(of: $0.key), $0.value) }) { first, _ in first })
        let live = Usage(notes.compactMapValues { $0 })
        return ordered(preciseReferences(of: note, text: text)).filter { path in
            guard files.contains(path), path.hasPrefix(".trash/") else { return false }
            let home = originalPath(of: path)
            if inBin.uses(path) || restored.uses(home) { return false }
            if !files.contains(home) && live.uses(home) { return false }
            return true
        }
    }

    /// **폴더 밖 노트가 이 폴더 안을 가리키는 링크 수** (168). 폴더 이름을 바꾸거나 지우면
    /// 그 링크가 깨진다. 노트로 가는 링크도 센다. 못 읽은 노트는 셀 수 없어 뺀다.
    public static func incomingLinks(to folder: String, notes: [String: String?]) -> Int {
        let folder = Paths.normalized(folder)
        guard !folder.isEmpty else { return 0 }
        let inside = folder + "/"
        var count = 0
        for (path, text) in notes {
            guard let text, !path.hasPrefix(inside) else { continue }
            for link in MarkdownLinks.extract(from: text) {
                if case .relative(let target) = Paths.resolve(link: link.destination, fromNoteAt: path),
                   target.hasPrefix(inside) {
                    count += 1
                }
            }
        }
        return count
    }

    // MARK: - 셈의 속

    /// 노트가 **링크로** 가리키는 파일 (노트로 가는 링크는 빼고). 금고 기준 경로.
    static func preciseReferences(of notePath: String, text: String) -> Set<String> {
        Set(MarkdownHTML.referencedPaths(markdown: text, notePath: notePath)
            .filter { !Paths.isNoteFile($0) })
    }

    /// 노트 여럿이 **한 파일을 쓰나.** 링크를 미리 모아 두고, 이름은 본문을 한 줄로 이어 찾는다 —
    /// 파일 수 × 노트 수만큼 본문을 훑지 않으려고. 이어 붙인 자리에 `\0` 을 끼워 두 노트에
    /// 걸친 가짜 이름이 안 생기게 한다 (파일 이름에는 `\0` 이 없다).
    struct Usage {
        let links: Set<String>
        let text: String?

        init(_ notes: [String: String], mentions: Bool = true) {
            var links: Set<String> = []
            for (path, body) in notes {
                links.formUnion(AttachmentLedger.preciseReferences(of: path, text: body))
            }
            self.links = links
            self.text = mentions
                ? notes.values.map { Paths.normalized($0).lowercased() }.joined(separator: "\n\u{0}\n")
                : nil
        }

        func uses(_ path: String) -> Bool {
            if links.contains(path) { return true }
            guard let text, !text.isEmpty else { return false }
            let name = Paths.normalized(String(path.split(separator: "/").last ?? Substring(path))).lowercased()
            if text.contains(name) { return true }
            let encoded = name.addingPercentEncoding(withAllowedCharacters: AttachmentLedger.quoteSafe) ?? name
            return text.contains(encoded.lowercased())
        }
    }

    /// 파이썬 `urllib.parse.quote` 가 그대로 두는 글자 — 영문 · 숫자 · `_.-~/`.
    /// `CharacterSet.alphanumerics` 는 한글도 글자로 쳐서 쓰지 않는다.
    static let quoteSafe = CharacterSet(
        charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_.-~/")

    /// 코드 포인트 순 — 파이썬 `sorted` 와 같은 순서 (화면 목록 · 정답표 대조).
    public static func ordered<S: Sequence>(_ paths: S) -> [String] where S.Element == String {
        paths.sorted { $0.unicodeScalars.lexicographicallyPrecedes($1.unicodeScalars) }
    }
}
