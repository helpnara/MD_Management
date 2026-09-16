import Foundation
import Markdown

/// 본문에서 뽑은 링크 하나.
public struct ExtractedLink: Equatable, Sendable {
    public enum Kind: String, Equatable, Sendable {
        case image
        case link
    }

    /// 원문에 적힌 그대로 (퍼센트 인코딩도 그대로). 푸는 것은 `Paths.resolve` 가 한다.
    public let destination: String
    public let kind: Kind

    public init(destination: String, kind: Kind) {
        self.destination = destination
        self.kind = kind
    }
}

/// 본문의 링크를 뽑는다. 공유 묶음(§7.6)과 첨부 표시(§7.3)가 이것을 쓴다.
public enum MarkdownLinks {

    /// 머리말을 뗀 본문에서 이미지와 링크를 **나온 순서대로** 뽑는다.
    public static func extract(from markdown: String) -> [ExtractedLink] {
        let body = FrontMatterParser.parse(markdown).body
        let document = Document(parsing: body)
        var walker = LinkWalker()
        walker.visit(document)
        return walker.found
    }

    /// **노트를 다른 폴더로 옮길 때 링크를 새 자리에 맞춰 고친 글** (T1).
    ///
    /// 폴더 안을 가리키는 상대 링크만 고친다 — 바깥 주소 · 앵커 · 절대경로는 그대로다.
    /// `회의/노트.md` 의 `assets/a.png` 는 `아이디어/` 로 옮기면 `../회의/assets/a.png` 가 된다.
    ///
    /// **앱이 본문을 고치는 유일한 자리다.** 그래서 사용자가 옮기라고 한 그 순간에만,
    /// **몇 개를 고칠지 먼저 알린 뒤에** 부른다 (107 에서 62 를 지운 까닭과 같다).
    /// 고칠 것이 없으면 원문을 그대로 돌려준다.
    public static func rebased(_ text: String, from oldFolder: String, to newFolder: String) -> String {
        guard oldFolder != newFolder else { return text }
        let oldNote = oldFolder.isEmpty ? "노트.md" : oldFolder + "/노트.md"
        var out = ""
        var cursor = text.startIndex

        while let bracket = text.range(of: "](", range: cursor..<text.endIndex) {
            out += text[cursor..<bracket.upperBound]
            cursor = bracket.upperBound
            guard let piece = destination(in: text, from: cursor) else { continue }
            let rewritten = rebase(piece.raw, note: oldNote, to: newFolder)
            out += rewritten
            out += text[piece.end..<text.index(after: piece.end)]   // 닫는 `)`
            cursor = text.index(after: piece.end)
        }
        out += text[cursor...]
        return out
    }

    /// 링크 하나를 새 폴더 기준으로. 폴더 안을 가리키지 않으면 그대로 둔다.
    private static func rebase(_ raw: String, note: String, to newFolder: String) -> String {
        let wrapped = raw.hasPrefix("<") && raw.hasSuffix(">") && raw.count >= 2
        let inner = wrapped ? String(raw.dropFirst().dropLast()) : raw
        // 앵커(`노트.md#절`)는 떼어 두었다가 도로 붙인다.
        var anchor = ""
        var target = inner
        if let hash = inner.firstIndex(of: "#"), hash != inner.startIndex {
            anchor = String(inner[hash...])
            target = String(inner[inner.startIndex..<hash])
        }
        guard case .relative(let resolved) = Paths.resolve(link: target, fromNoteAt: note) else {
            return raw
        }
        let link = Paths.relativeLink(from: newFolder, to: resolved) + anchor
        // 빈칸이 있으면 `<>` 로 감싼다 — 안 그러면 링크가 끊긴다.
        return (wrapped || link.contains(" ")) ? "<" + link + ">" : link
    }

    /// `](` 바로 뒤에서 닫는 `)` 까지. `<…>` 와 겹친 괄호를 다룬다.
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

private struct LinkWalker: MarkupWalker {
    var found: [ExtractedLink] = []

    mutating func visitLink(_ link: Markdown.Link) {
        if let destination = link.destination, !destination.isEmpty {
            found.append(ExtractedLink(destination: destination, kind: .link))
        }
        descendInto(link)
    }

    mutating func visitImage(_ image: Markdown.Image) {
        if let source = image.source, !source.isEmpty {
            found.append(ExtractedLink(destination: source, kind: .image))
        }
        descendInto(image)
    }
}
