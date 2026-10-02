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
        // 겹침이 너무 깊으면 트리를 만들지 않고 글자로 훑는다 (182). 공유 묶음 · 링크 셈이 첨부를
        // 놓치지 않게 — 코드 안의 `](` 까지 줍겠지만 이런 글에서는 빠뜨리는 것보다 낫다.
        guard !Nesting.isTooDeep(body) else { return scanned(body) }
        let document = Document(parsing: body)
        var walker = LinkWalker()
        walker.visit(document)
        return walker.found
    }

    /// `](` 를 글자로 훑어 뽑는다 — 트리를 못 만드는 글에서만 (182).
    static func scanned(_ text: String) -> [ExtractedLink] {
        var found: [ExtractedLink] = []
        var cursor = text.startIndex
        while let bracket = text.range(of: "](", range: cursor..<text.endIndex) {
            cursor = bracket.upperBound
            guard let piece = destination(in: text, from: cursor) else { continue }
            cursor = text.index(after: piece.end)
            var target = piece.raw
            if target.hasPrefix("<"), target.hasSuffix(">"), target.count >= 2 {
                target = String(target.dropFirst().dropLast())
            } else if let space = target.firstIndex(of: " ") {
                target = String(target[..<space])          // 뒤에 붙은 제목(`"…"`)을 뗀다
            }
            guard !target.isEmpty else { continue }
            let kind: ExtractedLink.Kind = BrokenLinks.isImage(text, before: bracket.lowerBound) ? .image : .link
            found.append(ExtractedLink(destination: target, kind: kind))
        }
        return found
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

    /// **붙여넣은 글의 상대 링크를 이 노트 기준으로 고친다** (144, 사용자 제안).
    ///
    /// `A` 폴더 노트의 `[이름](assets/파일.pdf)` 를 `B` 폴더 노트에 그대로 붙이면 링크가
    /// 안 맞는다 — 같은 글자가 자리마다 다른 곳을 가리키기 때문이다. 여기서는 그 글자를
    /// **이 노트에서 보는 경로**로 바꿔 준다: `[이름](../A/assets/파일.pdf)`.
    ///
    /// **사본을 만들지 않는다** (2026-09-18 사용자 — *사본이 늘면 내용이 갈라진다*).
    /// 파일은 제자리에 그대로 두고 **링크만** 고친다.
    ///
    /// 손대는 것은 **여기서 안 맞으면서 금고 어딘가에 딱 하나만 있는** 링크뿐이다.
    /// - 여기서도 맞으면 그대로 둔다.
    /// - 바깥 주소 · 절대경로 · 앵커만 있는 것은 그대로 둔다.
    /// - 같은 이름이 **여럿이면 손대지 않는다** — 어느 것인지 우리가 알 수 없다.
    ///   짐작해서 고치면 엉뚱한 파일을 가리키게 되고, 그것이 가장 나쁘다.
    ///
    /// `files` 는 금고 기준 경로들이다. 비어 있으면 아무것도 안 고친다.
    public struct Repair: Equatable, Sendable {
        public let text: String
        /// 몇 개를 고쳤나. 0 이면 글이 그대로다 — 사람에게 알릴 필요도 없다.
        public let fixed: Int

        public init(text: String, fixed: Int) {
            self.text = text
            self.fixed = fixed
        }
    }

    /// **어디서 복사했는지 알 때** — 원래 노트의 폴더에서 이 폴더로 링크를 옮겨 적는다 (177 둘째).
    ///
    /// 앱 안에서 복사하면 편집기가 클립보드에 **원래 노트의 경로**를 함께 싣는다. 그러면 이름으로
    /// 찾을 필요가 없다 — 노트를 옮길 때(T1)와 **같은 셈**(`rebased`)으로 정확히 옮긴다.
    ///
    /// 이름으로 찾기(`repaired`)는 이 앱의 사진 이름에서 무너진다: 사진은 폴더마다
    /// `2026-09-28-1.jpg` 부터 다시 센다. 같은 날 두 폴더에 사진을 넣으면 **이름이 겹쳐**
    /// 어느 것인지 몰라 안 고쳤고(깨진 링크), 붙이는 폴더에 같은 이름이 있으면 **그 폴더의
    /// 다른 사진**을 가리킨 채로 두었다. 빌드 58 에서 사용자가 두 번째로 걸린 자리다.
    public static func moved(pasted text: String, fromNote source: String, toFolder folder: String) -> Repair {
        let from = Paths.directory(of: source)
        guard from != folder, text.contains("](") else { return Repair(text: text, fixed: 0) }
        let out = rebased(text, from: from, to: folder)
        guard out != text else { return Repair(text: text, fixed: 0) }
        let before = extract(from: text).map(\.destination)
        let after = extract(from: out).map(\.destination)
        let fixed = zip(before, after).filter { $0 != $1 }.count
        return Repair(text: out, fixed: fixed)
    }

    public static func repaired(pasted text: String, noteFolder: String,
                                files: [String]) -> Repair {
        guard !files.isEmpty, text.contains("](") else { return Repair(text: text, fixed: 0) }
        let note = noteFolder.isEmpty ? "노트.md" : noteFolder + "/노트.md"
        var out = ""
        var cursor = text.startIndex
        var fixed = 0

        while let bracket = text.range(of: "](", range: cursor..<text.endIndex) {
            out += text[cursor..<bracket.upperBound]
            cursor = bracket.upperBound
            guard let piece = destination(in: text, from: cursor) else { continue }
            if let rewritten = repair(piece.raw, note: note, noteFolder: noteFolder, files: files) {
                out += rewritten
                fixed += 1
            } else {
                out += piece.raw
            }
            out += text[piece.end..<text.index(after: piece.end)]   // 닫는 `)`
            cursor = text.index(after: piece.end)
        }
        out += text[cursor...]
        return Repair(text: out, fixed: fixed)
    }

    /// 링크 하나 — 고칠 것이 있으면 새 글자, 없으면 `nil`.
    private static func repair(_ raw: String, note: String, noteFolder: String,
                               files: [String]) -> String? {
        let wrapped = raw.hasPrefix("<") && raw.hasSuffix(">") && raw.count >= 2
        let inner = wrapped ? String(raw.dropFirst().dropLast()) : raw
        var anchor = ""
        var target = inner
        if let hash = inner.firstIndex(of: "#"), hash != inner.startIndex {
            anchor = String(inner[hash...])
            target = String(inner[inner.startIndex..<hash])
        }
        guard !target.isEmpty else { return nil }
        // 바깥 주소 · 절대경로 · 폴더 밖은 손대지 않는다.
        guard case .relative(let here) = Paths.resolve(link: target, fromNoteAt: note) else {
            return nil
        }
        guard !files.contains(here) else { return nil }     // 여기서도 맞는다
        // 이 글자가 **금고의 맨 위에서** 가리키는 곳 — 꼬리를 얻는다.
        guard case .relative(let tail) = Paths.resolve(link: target, fromNoteAt: "노트.md") else {
            return nil
        }
        let matches = files.filter { $0 == tail || $0.hasSuffix("/" + tail) }
        guard matches.count == 1, let found = matches.first else { return nil }

        let link = Paths.relativeLink(from: noteFolder, to: found) + anchor
        guard link != inner else { return nil }
        return (wrapped || link.contains(" ")) ? "<" + link + ">" : link
    }

    /// **폴더 이름을 바꿀 때 그 폴더 안을 가리키던 링크를 새 이름으로** (179, 사용자 — 남은 할 일을
    /// 반영해 제출하자). 168 은 알리기만 했다 — 이름을 바꾸면 링크가 열리지 않았다.
    ///
    /// 노트 하나의 링크 가운데 `old` 안을 가리키던 것만 `new` 안으로 옮겨 적는다. 노트 자신이 `old`
    /// 안에 있었으면 **노트의 자리도 옮긴 뒤** 상대 링크를 다시 계산한다 — 안에서 안을 가리키는 보통
    /// 링크는 그대로 남는다. 바깥 주소 · 앵커 · 다른 폴더는 손대지 않는다. 옮기기(T1)와 같은 글쓰기다.
    ///
    /// **폴더를 다른 폴더 안으로 옮길 때도 이것 하나다** (204). 그때는 안의 노트가 한 단계 깊어지거나 얕아져서
    /// 바깥을 가리키던 `../메모.md` 가 엉뚱한 곳을 가리킨다 — 안의 노트의 링크는 **새 자리에서 같은 파일에 닿지
    /// 않으면** 다시 계산한다. 이름만 바꿀 때는 깊이가 같아 늘 닿으므로 손대지 않는다.
    public static func retargeted(_ text: String, notePath: String,
                                  fromFolder oldFolder: String, toFolder newFolder: String) -> Repair {
        let old = Paths.normalized(oldFolder), new = Paths.normalized(newFolder)
        let noteOld = Paths.normalized(notePath)
        guard !old.isEmpty, old != new, text.contains("](") else { return Repair(text: text, fixed: 0) }
        let noteNew = noteOld.hasPrefix(old + "/") ? new + String(noteOld.dropFirst(old.count)) : noteOld
        var out = ""
        var cursor = text.startIndex
        var fixed = 0
        while let bracket = text.range(of: "](", range: cursor..<text.endIndex) {
            out += text[cursor..<bracket.upperBound]
            cursor = bracket.upperBound
            guard let piece = destination(in: text, from: cursor) else { continue }
            let rewritten = retarget(piece.raw, noteOld: noteOld, noteNew: noteNew, old: old, new: new)
            if rewritten != piece.raw { fixed += 1 }
            out += rewritten
            out += text[piece.end..<text.index(after: piece.end)]   // 닫는 `)`
            cursor = text.index(after: piece.end)
        }
        out += text[cursor...]
        return Repair(text: out, fixed: fixed)
    }

    private static func retarget(_ raw: String, noteOld: String, noteNew: String,
                                 old: String, new: String) -> String {
        let wrapped = raw.hasPrefix("<") && raw.hasSuffix(">") && raw.count >= 2
        let inner = wrapped ? String(raw.dropFirst().dropLast()) : raw
        var anchor = ""
        var target = inner
        if let hash = inner.firstIndex(of: "#"), hash != inner.startIndex {
            anchor = String(inner[hash...])
            target = String(inner[inner.startIndex..<hash])
        }
        guard case .relative(let resolved) = Paths.resolve(link: target, fromNoteAt: noteOld) else { return raw }
        let moved: String
        if resolved.hasPrefix(old + "/") {
            moved = new + String(resolved.dropFirst(old.count))
        } else if noteOld != noteNew {
            // 안의 노트가 바깥을 가리킨다 (204) — 새 자리에서도 같은 파일에 닿으면 그대로.
            if case .relative(let again) = Paths.resolve(link: target, fromNoteAt: noteNew), again == resolved {
                return raw
            }
            moved = resolved
        } else {
            return raw
        }
        let link = Paths.relativeLink(from: Paths.directory(of: noteNew), to: moved) + anchor
        guard link != inner else { return raw }
        return (wrapped || link.contains(" ")) ? "<" + link + ">" : link
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

    /// **줄이 끝나는 글자인가** (183). Swift 는 `\r\n` 을 글자 **하나**로 본다 — `== "\n"` 만 보면 윈도
    /// 줄 끝 파일에서 줄을 못 보고 **다음 줄의 `)` 까지** 링크로 읽어 고쳐 버린다. 파이썬 정답표는
    /// 코드 포인트로 `\n` 을 보므로 이 둘이 같은 셈이다 (홀로 선 `\r` 은 둘 다 줄로 안 본다).
    static func endsLine(_ character: Character) -> Bool {
        character == "\n" || character == "\r\n"
    }

    /// `](` 바로 뒤에서 닫는 `)` 까지. `<…>` 와 겹친 괄호를 다룬다.
    /// `BrokenLinks` 도 이것을 부른다 — 링크를 **읽는 길은 하나**다 (183 전에는 둘이었다).
    static func destination(in text: String,
                            from start: String.Index) -> (raw: String, end: String.Index)? {
        guard start < text.endIndex else { return nil }
        if text[start] == "<" {
            var cursor = text.index(after: start)
            while cursor < text.endIndex, text[cursor] != ">" {
                if endsLine(text[cursor]) { return nil }
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
            if endsLine(character) { return nil }
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
