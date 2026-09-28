import Foundation

/// **이 노트에서 안 열리는 링크 하나** (146).
public struct BrokenLink: Equatable, Sendable {
    /// 원문에 적힌 그대로 (`<>` 와 퍼센트 인코딩도 그대로).
    public let destination: String
    /// 풀어 본 금고 기준 경로. 폴더 밖을 가리키면 비어 있다.
    public let resolved: String
    /// 몇째 줄인가 (1부터). 사람이 찾아가야 하므로 줄이 필요하다.
    public let line: Int
    /// 그 줄의 글. 목록에서 어느 자리인지 알아보게 한다.
    public let text: String
    public let kind: ExtractedLink.Kind

    public init(destination: String, resolved: String, line: Int, text: String,
                kind: ExtractedLink.Kind) {
        self.destination = destination
        self.resolved = resolved
        self.line = line
        self.text = text
        self.kind = kind
    }
}

/// **안 열리는 링크를 찾는다** (146, 사용자 제안).
///
/// 읽기 모드는 이미 없는 첨부를 네모로 보여 준다. 그런데 그건 **그 자리까지 내려가야**
/// 보인다 — 긴 노트에서는 있는 줄도 모른다. 여기서는 **한 번에 모아** 보여 준다.
///
/// **고치지 않는다. 보여 주기만 한다.** 앱이 본문을 고치는 자리는 둘뿐이다 (노트를 옮길
/// 때 · 붙여넣을 때) — 둘 다 사람이 시킨 그 순간이고, 몇 개를 고칠지 먼저 알린다.
/// 여기서 몰래 고치기 시작하면 셋째 자리가 생긴다.
public enum BrokenLinks {

    /// `files` 는 금고 기준 경로들. **비어 있으면 아무것도 안 찾는다** — 목록을 아직
    /// 못 읽었을 때 *다 깨졌다* 고 말하는 것이 가장 나쁘다.
    public static func find(in markdown: String, notePath: String,
                            files: [String]) -> [BrokenLink] {
        guard !files.isEmpty, markdown.contains("](") else { return [] }
        let known = Set(files)
        var found: [BrokenLink] = []

        // 머리말은 본문이 아니다 — 거기 있는 `](` 는 링크가 아니다.
        let header = FrontMatterParser.headerLength(of: markdown)
        let start = markdown.index(markdown.startIndex,
                                   offsetBy: min(header, markdown.count))
        var cursor = start

        while let bracket = markdown.range(of: "](", range: cursor..<markdown.endIndex) {
            cursor = bracket.upperBound
            guard let piece = destination(in: markdown, from: cursor) else { continue }
            defer { cursor = markdown.index(after: piece.end) }

            let kind = isImage(markdown, before: bracket.lowerBound) ? ExtractedLink.Kind.image
                                                                    : ExtractedLink.Kind.link
            guard let broken = check(piece.raw, notePath: notePath, known: known) else { continue }
            let (line, text) = place(of: bracket.lowerBound, in: markdown)
            found.append(BrokenLink(destination: piece.raw, resolved: broken,
                                    line: line, text: text, kind: kind))
        }
        return found
    }

    /// 링크 하나 — 안 열리면 풀린 경로, 멀쩡하면 `nil`.
    private static func check(_ raw: String, notePath: String, known: Set<String>) -> String? {
        let wrapped = raw.hasPrefix("<") && raw.hasSuffix(">") && raw.count >= 2
        let inner = wrapped ? String(raw.dropFirst().dropLast()) : raw
        var target = inner
        if let hash = inner.firstIndex(of: "#"), hash != inner.startIndex {
            target = String(inner[inner.startIndex..<hash])
        }
        guard !target.isEmpty else { return nil }        // 앵커만 있는 것은 같은 노트다
        switch Paths.resolve(link: target, fromNoteAt: notePath) {
        case .relative(let path):
            return known.contains(path) ? nil : path
        case .outside(let path):
            // 폴더 밖은 이 앱에서 절대 못 연다 — 사람에게 알려야 한다.
            return path
        case .external, .absolute, .empty:
            return nil                                    // 바깥 주소 · 절대경로는 우리 몫이 아니다
        }
    }

    /// 이 자리가 몇째 줄이고 그 줄이 무엇인가 (1부터).
    private static func place(of index: String.Index,
                              in text: String) -> (line: Int, text: String) {
        var line = 1
        var lineStart = text.startIndex
        var cursor = text.startIndex
        while cursor < index {
            if text[cursor] == "\n" {
                line += 1
                lineStart = text.index(after: cursor)
            }
            cursor = text.index(after: cursor)
        }
        var lineEnd = lineStart
        while lineEnd < text.endIndex, text[lineEnd] != "\n" { lineEnd = text.index(after: lineEnd) }
        return (line, String(text[lineStart..<lineEnd]).trimmingCharacters(in: .whitespaces))
    }

    /// `](` 앞이 `![…]` 인가 — 그림이면 목록에 다르게 보여 준다.
    private static func isImage(_ text: String, before bracket: String.Index) -> Bool {
        var cursor = bracket
        var depth = 0
        while cursor > text.startIndex {
            cursor = text.index(before: cursor)
            let character = text[cursor]
            if character == "\n" { return false }
            if character == "]" { depth += 1 }
            if character == "[" {
                if depth == 0 {
                    guard cursor > text.startIndex else { return false }
                    return text[text.index(before: cursor)] == "!"
                }
                depth -= 1
            }
        }
        return false
    }

    /// `](` 바로 뒤에서 닫는 `)` 까지. `MarkdownLinks` 와 같은 규칙이다.
    private static func destination(in text: String,
                                    from start: String.Index) -> (raw: String, end: String.Index)? {
        guard start < text.endIndex else { return nil }
        if text[start] == "<" {
            var cursor = text.index(after: start)
            while cursor < text.endIndex, text[cursor] != ">" {
                if text[cursor] == "\n" { return nil }
                cursor = text.index(after: cursor)
            }
            guard cursor < text.endIndex else { return nil }
            let close = text.index(after: cursor)
            guard close < text.endIndex, text[close] == ")" else { return nil }
            return (String(text[start...cursor]), close)
        }
        var depth = 0
        var cursor = start
        while cursor < text.endIndex {
            let character = text[cursor]
            if character == "\n" { return nil }
            if character == "(" { depth += 1 }
            if character == ")" {
                if depth == 0 { return (String(text[start..<cursor]), cursor) }
                depth -= 1
            }
            cursor = text.index(after: cursor)
        }
        return nil
    }
}
