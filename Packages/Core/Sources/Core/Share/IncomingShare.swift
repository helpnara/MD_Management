import Foundation

/// **다른 앱의 공유 메뉴로 받은 것을 노트 글로** (213, 2026-10-03 사용자 — *하나씩 구현해 보자* · 1.0.6 에 넣어 낸다).
///
/// 공유 확장은 받은 것(글 · 주소 · 주소의 제목 · 사진)을 앱 그룹 상자에 두기만 한다. 앱이 앞으로 나오면 사진을
/// `받은 글/assets/` 에 쓰고, 이 셈으로 노트 글을 짠 뒤 `받은 글` 폴더에 새 노트로 넣는다.
///
/// - **제목은 첫 줄이다** — 제목을 따라 파일 이름을 바꿀 때(`followTitle`)와 같은 `FrontMatterParser.firstLine`.
///   받은 글에 첫 줄이 있으면 그것이 제목이고 글은 그대로 둔다. 글이 없으면(주소 · 사진만) 주소의 제목 →
///   주소의 사이트 이름 → `fallback` 순으로 고르고, **글 맨 위에 `# 제목` 줄을 넣는다** — 파일 이름과 첫 줄이 같아야 나중에
///   고쳐도 이름이 엉뚱하게 바뀌지 않는다.
/// - 주소는 `[주소의 제목](주소)` — 노트 연결과 같은 `NoteLinking.markdownLink` (대괄호는 역슬래시로 피한다).
///   받은 글에 주소가 이미 들어 있으면 또 붙이지 않는다 (사파리는 글과 주소를 함께 줄 때가 있다).
/// - 사진은 줄마다 `![](assets/…)` — 사진 넣기와 같은 꼴.
///
/// 파이썬 쌍둥이: `Tools/golden/generate.py` 의 `incoming_share` (`shareCases`).
public enum IncomingShare {

    /// 받은 글이 들어갈 폴더의 한국어 이름 (금고 맨 위). 영어 기기는 `Inbox` — 실제로 쓸 폴더는 `inboxFolder` 가 고른다.
    public static let folder = "받은 글"

    /// 받은 글 폴더가 될 수 있는 이름 — 앱이 아는 언어마다 하나 (219 · ADR-0009).
    public static let folderNames = ["받은 글", "Inbox"]

    /// **받은 글을 넣을 폴더** (219 · ADR-0009). `existing` 은 맨 위 폴더 이름 → 그 안 노트 수.
    /// 받은 글 폴더가 될 수 있는 이름 가운데 **이미 있는 것**을 쓴다 — 한국어 아이폰과 영어 아이패드가 한 iCloud 를 쓸 때
    /// `받은 글` 과 `Inbox` 로 갈리지 않게. 둘 다 있으면 노트가 많은 쪽, 같으면 기기 언어 쪽(`preferred`). 없으면 `preferred` 로 새로 만든다.
    /// 한 번 고른 것을 기억하지 않는다 — 기억은 앱 DB 가 된다 (ADR-0001). 폴더 목록이 곧 기억이다.
    /// 파이썬 쌍둥이: `inbox_folder` (`inboxCases`).
    public static func inboxFolder(existing: [String: Int], preferred: String) -> String {
        let present = folderNames.filter { existing[$0] != nil }
        guard let most = present.map({ existing[$0] ?? 0 }).max() else { return preferred }
        let top = present.filter { (existing[$0] ?? 0) == most }
        return top.contains(preferred) ? preferred : top[0]
    }

    public struct Note: Equatable, Sendable {
        /// 파일 이름이 될 제목 (`FolderStore.createNote` 가 파일 이름으로 다듬는다).
        public let title: String
        public let markdown: String
    }

    /// - Parameters:
    ///   - text: 받은 글. 없으면 빈 글.
    ///   - url: 받은 주소.
    ///   - pageTitle: 주소의 제목 (사파리가 함께 준다).
    ///   - images: 노트 기준 사진 경로 (`assets/2026-10-04-1.jpg`) — 앱이 쓴 뒤에 넘긴다.
    ///   - fallback: 제목으로 쓸 것이 하나도 없을 때 (`받은 글 2026-10-04 07-30`).
    public static func note(text: String, url: String?, pageTitle: String?,
                            images: [String], fallback: String) -> Note {
        let body = trimmedLines(text.replacingOccurrences(of: "\r\n", with: "\n")
                                    .replacingOccurrences(of: "\r", with: "\n"))
        let address = url.map { oneLine($0) }.flatMap { $0.isEmpty ? nil : $0 }
        let label = pageTitle.map { oneLine($0) }.flatMap { $0.isEmpty ? nil : $0 }

        var parts: [String] = []
        if !body.isEmpty { parts.append(body) }
        if let address, !body.contains(address) {
            parts.append(NoteLinking.markdownLink(label: label ?? address, path: address))
        }
        for path in images {
            parts.append("!" + NoteLinking.markdownLink(label: "", path: path))
        }

        if let first = FrontMatterParser.firstLine(of: body) {
            return Note(title: first, markdown: parts.joined(separator: "\n\n") + "\n")
        }
        // 주소를 그대로 제목으로 쓰면 제목이 링크가 되고(GFM 자동 링크) 파일 이름이 `https---…` 가 된다 — 사이트 이름만.
        let title = label ?? address.flatMap(siteName) ?? fallback
        return Note(title: title, markdown: (["# " + title] + parts).joined(separator: "\n\n") + "\n")
    }

    // MARK: - 이미 있는 노트에 덧붙이기 (241)

    /// **노트 끝에 덧붙일 한 항목** (241, 2026-10-11 사용자 — *같은 주제의 내용은 하나의 노트에 계속 제목과 링크만 누적*).
    ///
    /// - 주소가 있으면 `- [주소의 제목](주소)` — 새 노트(`note`)와 같은 `markdownLink`. 제목이 없으면 주소가 이름이다.
    /// - 받은 글은 **한 줄로** 뒤에 붙인다 (` — 글`). 줄바꿈은 빈칸으로 — 목록 한 줄이 한 공유다.
    ///   받은 글에 주소가 이미 들어 있으면 링크를 또 붙이지 않는다 (`note` 와 같은 규칙).
    /// - 사진은 항목 아래에 두 칸 들여 `![](…)` — 그 항목에 딸린다. 글 · 주소가 없으면 첫 사진이 항목이다.
    /// - 아무것도 없으면 nil.
    ///
    /// 파이썬 쌍둥이: `share_entry` (`shareEntryCases`).
    public static func entry(text: String, url: String?, pageTitle: String?, images: [String]) -> String? {
        let memo = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n").map { trimmed($0) }.filter { !$0.isEmpty }.joined(separator: " ")
        let address = url.map { oneLine($0) }.flatMap { $0.isEmpty ? nil : $0 }
        let label = pageTitle.map { oneLine($0) }.flatMap { $0.isEmpty ? nil : $0 }
        var head = memo
        if let address, !memo.contains(address) {
            let link = NoteLinking.markdownLink(label: label ?? address, path: address)
            head = memo.isEmpty ? link : link + " — " + memo
        }
        var pictures = images.map { "!" + NoteLinking.markdownLink(label: "", path: $0) }
        if head.isEmpty {
            guard !pictures.isEmpty else { return nil }
            head = pictures.removeFirst()
        }
        return (["- " + head] + pictures.map { "  " + $0 }).joined(separator: "\n")
    }

    /// **노트 글 끝에 항목을 붙인 글.** 끝의 빈 줄은 걷고, 마지막 줄이 목록 항목(`- ` · `* ` · `+ `)이거나 두 칸 넘게
    /// 들여 쓴 줄(앞 항목에 딸린 줄)이면 **한 줄바꿈**으로 이어 같은 목록이 되게, 아니면 빈 줄 하나를 두고 새 목록을 연다.
    /// 앞의 글은 한 글자도 바꾸지 않는다 (마지막 줄 끝의 빈칸까지). 끝은 줄바꿈 하나.
    /// 파이썬 쌍둥이: `share_append` (`shareAppendCases`).
    public static func appending(_ entry: String, to text: String) -> String {
        // 줄은 글자 단위로 직접 나눈다 — `\r\n` 은 스위프트에서 한 글자라 `components` 가 플랫폼마다 다르게 나눌 수 있다.
        var lines: [String] = []
        var current = String.UnicodeScalarView()
        for scalar in text.unicodeScalars {
            if scalar == "\n" {
                lines.append(String(current))
                current = String.UnicodeScalarView()
            } else {
                current.append(scalar)
            }
        }
        lines.append(String(current))
        while let last = lines.last, last.unicodeScalars.allSatisfy({ $0 == " " || $0 == "\t" || $0 == "\r" }) {
            lines.removeLast()
        }
        guard let last = lines.last else { return entry + "\n" }
        var scalars = Array(last.unicodeScalars)
        if scalars.last == "\r" { scalars.removeLast() }
        let marks: Set<Unicode.Scalar> = ["-", "*", "+"]
        let listItem = scalars.count >= 2 && marks.contains(scalars[0]) && scalars[1] == " "
        let indented = scalars.count >= 3 && scalars[0] == " " && scalars[1] == " "
            && scalars.contains(where: { $0 != " " && $0 != "\t" })
        let separator = listItem || indented ? "\n" : "\n\n"
        return lines.joined(separator: "\n") + separator + entry + "\n"
    }

    /// 주소의 사이트 이름 (`https://www.example.org/a` → `example.org`). 소문자로 — 파이썬 `urlsplit` 과 같게.
    static func siteName(_ address: String) -> String? {
        guard var host = URLComponents(string: address)?.host?.lowercased(), !host.isEmpty else { return nil }
        // `www.` 로 시작하면 제목 줄에서 다시 자동 링크가 된다 — 뗀다.
        if host.hasPrefix("www."), host.count > 4 { host.removeFirst(4) }
        return host
    }

    /// 앞뒤의 빈 줄과 줄 끝 빈칸(빈칸 · 탭)을 걷어 낸다 — 글 가운데는 그대로.
    static func trimmedLines(_ text: String) -> String {
        var lines = text.components(separatedBy: "\n").map { trimmed($0, leading: false) }
        while let first = lines.first, trimmed(first).isEmpty { lines.removeFirst() }
        while let last = lines.last, last.isEmpty { lines.removeLast() }
        return lines.joined(separator: "\n")
    }

    /// 제목 한 줄 — 줄바꿈은 빈칸으로, 앞뒤 빈칸 · 탭은 뗀다.
    static func oneLine(_ text: String) -> String {
        trimmed(text.replacingOccurrences(of: "\r\n", with: " ")
                    .replacingOccurrences(of: "\r", with: " ")
                    .replacingOccurrences(of: "\n", with: " "))
    }

    /// 빈칸 · 탭만 뗀다 (유니코드 빈칸 묶음이 아니라 — 파이썬 쌍둥이와 글자 하나까지 같게).
    static func trimmed(_ text: String, leading: Bool = true) -> String {
        var out = Substring(text)
        while let last = out.last, last == " " || last == "\t" { out.removeLast() }
        if leading { while let first = out.first, first == " " || first == "\t" { out.removeFirst() } }
        return String(out)
    }
}
