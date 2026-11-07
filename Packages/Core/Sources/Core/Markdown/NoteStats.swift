import Foundation

/// **노트의 기초 통계** (315, 2026-11-07 사용자 — *노트에 대한 기초 통계량을 편집모드와 읽기모드에서 볼 수 있도록*).
///
/// 셈은 **읽는 사람이 보는 글**로 한다 — 마크다운 표시(`**` · `[](주소)` · `#`)는 세지 않는다. 줄마다 목록 미리보기와 같은
/// `PreviewLine.plain` 을 부른다 (같은 것을 재는 곳이 둘이면 갈린다 — CLAUDE §1). 빼는 줄:
/// - 머리말 — 첫 줄이 `---` 이고 뒤에 `---` 나 `...` 줄이 있으면 그 사이 전부
/// - 코드 울타리 줄(```` ``` ```` · `~~~` — 앞 빈칸 셋까지). 울타리 **안의 줄은 그대로** 센다
/// - 가로줄 · 제목 밑줄 — 빈칸을 빼면 `-` `*` `_` `=` 한 가지로만 셋 이상 (문단을 끊는다)
/// - 표의 구분 줄 (`|---|:--:|`) — 문단은 안 끊는다. 표의 줄(`|` 로 시작)은 칸마다 보이는 글로 바꿔 빈칸 하나로 잇는다
///
/// 글자는 **NFC 로 맞춘 뒤 유니코드 스칼라** 단위다 (한글 음절 하나 = 1). 할 일 상자는 미리보기가 바꾼 `☐ ` · `☑ ` 로 세고
/// 글자 셈에서는 뺀다. 링크 · 사진은 원문에서 `[…](…)` · `![…](…)` 를 센다 (머리말 · 코드 밖). 읽는 시간은 공백 뺀 글자 500자에 1분.
///
/// **파이썬 `Tools/golden/note_stats.py` 와 같은 셈이다** (`noteStatsCases`). 고칠 때는 두 쪽을 같이 고친다. 순수 함수 — UIKit 을 모른다.
public struct NoteStats: Equatable, Sendable {
    public var characters = 0
    public var charactersNoSpaces = 0
    public var words = 0
    public var lines = 0
    public var paragraphs = 0
    public var tasks = 0
    public var tasksDone = 0
    public var links = 0
    public var images = 0
    public var readingMinutes = 0

    public init() {}

    /// 한글 기준 1분에 읽는 글자 (공백 뺀).
    public static let charactersPerMinute = 500

    static let spaces: Set<UInt32> = {
        var set: Set<UInt32> = [0x09, 0x0B, 0x0C, 0x20, 0xA0, 0x1680, 0x2028, 0x2029, 0x202F, 0x205F, 0x3000]
        for v in UInt32(0x2000)..<UInt32(0x200B) { set.insert(v) }
        return set
    }()

    static func isSpace(_ s: Unicode.Scalar) -> Bool { spaces.contains(s.value) }

    static func stripSpaces(_ s: [Unicode.Scalar]) -> [Unicode.Scalar] {
        var start = 0, end = s.count
        while start < end, isSpace(s[start]) { start += 1 }
        while end > start, isSpace(s[end - 1]) { end -= 1 }
        return Array(s[start..<end])
    }

    private static let delimiter = try! NSRegularExpression(
        pattern: "^[ \\t]*\\|?[ \\t]*:?-+:?[ \\t]*(\\|[ \\t]*:?-+:?[ \\t]*)*\\|?[ \\t]*\\z")
    private static let link = try! NSRegularExpression(pattern: "(!?)\\[[^\\]\\n]*\\]\\([^)\\n]*\\)")

    private static func string(_ s: [Unicode.Scalar]) -> String {
        var out = String.UnicodeScalarView()
        out.append(contentsOf: s)
        return String(out)
    }

    /// 앞 빈칸(` ` 만) 셋까지 뒤의 ```` ``` ```` · `~~~` 줄 — (글자, 길이, 그 뒤 자리).
    static func fence(_ s: [Unicode.Scalar]) -> (Unicode.Scalar, Int, Int)? {
        var k = 0
        while k < s.count, k < 4, s[k] == " " { k += 1 }
        guard k <= 3, k < s.count, s[k] == "`" || s[k] == "~" else { return nil }
        let mark = s[k]
        var n = 0
        while k + n < s.count, s[k + n] == mark { n += 1 }
        guard n >= 3 else { return nil }
        return (mark, n, k + n)
    }

    static func isRule(_ s: [Unicode.Scalar]) -> Bool {
        let body = s.filter { !isSpace($0) }
        guard body.count >= 3, let first = body.first, "-*_=".unicodeScalars.contains(first) else { return false }
        return body.allSatisfy { $0 == first }
    }

    /// 머리말이 끝난 다음 줄 번호. 없으면 0.
    static func frontMatterEnd(_ lines: [[Unicode.Scalar]]) -> Int {
        func trimmedRight(_ s: [Unicode.Scalar]) -> String {
            var end = s.count
            while end > 0, s[end - 1] == " " || s[end - 1] == "\t" { end -= 1 }
            return string(Array(s[..<end]))
        }
        guard let first = lines.first, trimmedRight(first) == "---" else { return 0 }
        for i in 1..<max(1, lines.count) where i < lines.count {
            let t = trimmedRight(lines[i])
            if t == "---" || t == "..." { return i + 1 }
        }
        return 0
    }

    static func tableText(_ line: String) -> String {
        var cells = line.components(separatedBy: "|")
        if let first = cells.first, stripSpaces(Array(first.unicodeScalars)).isEmpty { cells.removeFirst() }
        if let last = cells.last, stripSpaces(Array(last.unicodeScalars)).isEmpty { cells.removeLast() }
        return cells.map { PreviewLine.plain($0) }.filter { !$0.isEmpty }.joined(separator: " ")
    }

    private static func matches(_ regex: NSRegularExpression, _ s: String) -> [NSTextCheckingResult] {
        regex.matches(in: s, range: NSRange(s.startIndex..., in: s))
    }

    public static func of(_ text: String) -> NoteStats {
        let scalars = Array(text.precomposedStringWithCanonicalMapping.unicodeScalars)
        // 줄은 `\n` 으로만 가른다 (Swift 글자는 `\r\n` 을 한 글자로 보므로 스칼라로 자른다). 줄 끝 `\r` 하나는 뗀다.
        var lines: [[Unicode.Scalar]] = [[]]
        for s in scalars {
            if s == "\n" { lines.append([]) } else { lines[lines.count - 1].append(s) }
        }
        lines = lines.map { $0.last == "\r" ? Array($0.dropLast()) : $0 }

        var stats = NoteStats()
        var open: (Unicode.Scalar, Int)?
        var inParagraph = false
        for line in lines[frontMatterEnd(lines)...] {
            var visible: [Unicode.Scalar]?
            let opener = fence(line)
            let text = string(line)
            if let current = open {
                if let o = opener, o.0 == current.0, o.1 >= current.1, stripSpaces(Array(line[o.2...])).isEmpty {
                    open = nil
                } else {
                    visible = stripSpaces(line)
                }
            } else if let o = opener {
                open = (o.0, o.1)
            } else if line.contains("|"), !matches(delimiter, text).isEmpty {
                continue    // 표의 구분 줄 — 세지 않고 문단도 안 끊는다
            } else if isRule(line) {
                // 가로줄 — 문단을 끊는다
            } else {
                for m in matches(link, text) {
                    if m.range(at: 1).length > 0 { stats.images += 1 } else { stats.links += 1 }
                }
                if stripSpaces(line).first == "|" {
                    visible = Array(tableText(text).unicodeScalars)
                } else {
                    var shown = Array(PreviewLine.plain(text).unicodeScalars)
                    if shown.count >= 2, shown[1] == " ", shown[0] == "☐" || shown[0] == "☑" {
                        stats.tasks += 1
                        if shown[0] == "☑" { stats.tasksDone += 1 }
                        shown = Array(shown.dropFirst(2))
                    }
                    visible = shown
                }
            }
            if let shown = visible, !shown.isEmpty {
                stats.characters += shown.count
                var token = false
                for s in shown {
                    if isSpace(s) {
                        token = false
                    } else {
                        stats.charactersNoSpaces += 1
                        if !token { token = true; stats.words += 1 }
                    }
                }
                stats.lines += 1
                if !inParagraph { stats.paragraphs += 1; inParagraph = true }
            } else {
                inParagraph = false
            }
        }
        stats.readingMinutes = stats.charactersNoSpaces > 0
            ? (stats.charactersNoSpaces + charactersPerMinute - 1) / charactersPerMinute : 0
        return stats
    }
}
