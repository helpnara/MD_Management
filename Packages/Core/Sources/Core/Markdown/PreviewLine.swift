import Foundation

/// **목록 · 검색 결과에 보이는 한 줄을 글로** (242, 2026-10-12 사용자 미리보기 영상 검토에서 찾음 — 검색 결과 줄에
/// `[시니어 명소](<>)` 가, 목록 미리보기에 `**clearing what's piled up**` 이 마크다운 원문째 보였다).
///
/// 앞의 블록 표시(제목 `#` · 인용 `>` · 목록 `-` `1.` — 겹쳐도)를 떼고, 목록 바로 뒤의 할 일 상자는 ☐ · ☑ 로 바꾼 뒤,
/// **줄 안 표시는 markdown-it 이 읽는 그대로** 보이는 글만 남긴다 — 링크 · 이미지는 제목(대체 글)만, 굵게 · 기울임 ·
/// 취소선(`~` · `~~`) 표시는 짝이 맞을 때만 떼고, 코드는 안의 글, `\` 빗금 풀기, 자동 링크 `<주소>` 는 주소, 문자 참조는 글자.
/// HTML 태그는 그대로 둔다. 파일 · 색인의 본문은 그대로다 — 보여 주는 줄만 바뀐다.
///
/// **파이썬 `Tools/golden/preview_line.py` 와 같은 셈이다** (`previewCases`). 그 쌍둥이는 markdown-it 의 줄 안 규칙
/// (escape · backticks · strikethrough · emphasis · link · image · autolink · html_inline · entity · `balance_pairs`)을
/// 그대로 옮겼고, 정답표는 markdown-it 이 심판한다. 여기도 같은 순서 · 같은 이름으로 옮겼다 — 고칠 때는 두 쪽을 같이 고친다.
/// 글자는 유니코드 스칼라 단위로 본다 (파이썬의 코드 포인트와 같게). 순수 함수다 — UIKit 을 모른다.
public enum PreviewLine {

    /// 보이는 한 줄.
    public static func plain(_ line: String) -> String {
        let (box, rest) = stripBlock(line)
        let text = Inline(rest).text(0, rest.count)
        return makeString(trimSpaceTab(Array((box + text).unicodeScalars)))
    }

    // MARK: - 블록 표시

    /// 앞의 블록 표시를 뗀 (상자, 나머지). 제목 끝의 `#` 줄은 앞에 빈칸이 있을 때만 뗀다 (`C#` 은 둔다).
    static func stripBlock(_ line: String) -> (String, [Unicode.Scalar]) {
        var s = trimSpaceTab(Array(line.unicodeScalars))
        var box = ""
        while true {
            if let after = headingEnd(s) {
                s = Array(s[after...])
                s = removeClosingHashes(s)
                continue
            }
            if !s.isEmpty, s[0] == ">" {
                var k = 1
                if k < s.count, isSpaceTab(s[k]) { k += 1 }
                s = Array(s[k...])
                continue
            }
            if let after = listMarkerEnd(s) {
                s = Array(s[after...])
                if let task = taskBox(s) {
                    box = task.0 ? "☑ " : "☐ "
                    s = task.1
                    break
                }
                continue
            }
            break
        }
        return (box, trimSpaceTab(s))
    }

    /// `#{1,6}` 뒤에 빈칸(들)이나 줄 끝 — 그 뒤 자리.
    private static func headingEnd(_ s: [Unicode.Scalar]) -> Int? {
        var n = 0
        while n < s.count, s[n] == "#" { n += 1 }
        guard n >= 1, n <= 6 else { return nil }
        if n == s.count { return n }
        guard isSpaceTab(s[n]) else { return nil }
        var k = n
        while k < s.count, isSpaceTab(s[k]) { k += 1 }
        return k
    }

    /// `(?:^|[ \t]+)#+[ \t]*$` 를 뗀다.
    private static func removeClosingHashes(_ s: [Unicode.Scalar]) -> [Unicode.Scalar] {
        var end = s.count
        while end > 0, isSpaceTab(s[end - 1]) { end -= 1 }
        var start = end
        while start > 0, s[start - 1] == "#" { start -= 1 }
        guard start < end else { return s }
        if start == 0 { return [] }
        guard isSpaceTab(s[start - 1]) else { return s }
        var cut = start
        while cut > 0, isSpaceTab(s[cut - 1]) { cut -= 1 }
        return Array(s[..<cut])
    }

    /// `[-*+]` 또는 `[0-9]{1,9}[.)]` 뒤에 빈칸(들) — 그 뒤 자리.
    private static func listMarkerEnd(_ s: [Unicode.Scalar]) -> Int? {
        guard !s.isEmpty else { return nil }
        let first = s[0]
        var k: Int
        if first == "-" || first == "*" || first == "+" {
            k = 1
        } else {
            var n = 0
            while n < s.count, isDigit(s[n]) { n += 1 }
            guard n >= 1, n <= 9, n < s.count, s[n] == "." || s[n] == ")" else { return nil }
            k = n + 1
        }
        guard k < s.count, isSpaceTab(s[k]) else { return nil }
        while k < s.count, isSpaceTab(s[k]) { k += 1 }
        return k
    }

    /// `[ ]` · `[x]` · `[X]` 뒤에 빈칸(들) — (했나, 나머지).
    private static func taskBox(_ s: [Unicode.Scalar]) -> (Bool, [Unicode.Scalar])? {
        guard s.count >= 4, s[0] == "[", s[2] == "]", isSpaceTab(s[3]) else { return nil }
        let mark = s[1]
        guard mark == " " || mark == "x" || mark == "X" else { return nil }
        var k = 3
        while k < s.count, isSpaceTab(s[k]) { k += 1 }
        return (mark != " ", Array(s[k...]))
    }

    // MARK: - 줄 안 표시 (markdown-it 을 그대로)

    final class Delim {
        let marker: Unicode.Scalar
        let length: Int
        let token: Int
        var end = -1
        var open: Bool
        var close: Bool
        init(_ marker: Unicode.Scalar, _ length: Int, _ token: Int, _ open: Bool, _ close: Bool) {
            self.marker = marker
            self.length = length
            self.token = token
            self.open = open
            self.close = close
        }
    }

    final class Inline {
        let src: [Unicode.Scalar]
        /// markdown-it 의 `` ` `` 기억 (`backticks` · `backticksScanned`) — 링크 표를 찾다 끝까지 훑은 뒤로는 그 뒤에
        /// 같은 길이의 닫는 줄이 없으면 여는 줄도 글자다. 결과가 이 기억에 따라 달라져 그대로 옮긴다.
        var backticks: [Int: Int] = [:]
        var scanned = false

        init(_ src: [Unicode.Scalar]) { self.src = src }

        // ── 판정 ──

        func scanDelims(_ start: Int, _ end: Int, _ canSplit: Bool) -> (Bool, Bool, Int) {
            let marker = src[start]
            let last: Unicode.Scalar = start > 0 ? src[start - 1] : " "
            var pos = start
            while pos < end, src[pos] == marker { pos += 1 }
            let next: Unicode.Scalar = pos < end ? src[pos] : " "
            let lastP = PreviewLine.isPunct(last), nextP = PreviewLine.isPunct(next)
            let lastW = PreviewLine.isWhite(last), nextW = PreviewLine.isWhite(next)
            let left = !(nextW || (nextP && !(lastW || lastP)))
            let right = !(lastW || (lastP && !(nextW || nextP)))
            let canOpen = left && (canSplit || !right || lastP)
            let canClose = right && (canSplit || !left || nextP)
            return (canOpen, canClose, pos - start)
        }

        /// `` ` `` 줄 — (끝 자리, 내용 또는 nil). 닫는 줄이 없으면 내용 nil 로 그 줄만 넘긴다.
        func codeSpan(_ at: Int, _ end: Int) -> (Int, [Unicode.Scalar]?) {
            let start = at
            var pos = at + 1
            while pos < end, src[pos] == "`" { pos += 1 }
            let opener = pos - start
            if scanned, (backticks[opener] ?? 0) <= start { return (start + opener, nil) }
            var matchEnd = pos
            while true {
                // markdown-it 처럼 줄 끝까지 찾는다 (`end` 너머도).
                guard let k = src[matchEnd...].firstIndex(of: "`") else { break }
                matchEnd = k + 1
                while matchEnd < end, src[matchEnd] == "`" { matchEnd += 1 }
                if matchEnd - k == opener {
                    var content = Array(src[pos..<k])
                    if !content.isEmpty, content[0] == " ", content[content.count - 1] == " ",
                       content.contains(where: { !$0.properties.isWhitespace }) {
                        content = Array(content.dropFirst().dropLast())
                    }
                    return (matchEnd, content)
                }
                backticks[matchEnd - k] = k
            }
            scanned = true
            return (start + opener, nil)
        }

        func autolink(_ pos: Int, _ end: Int) -> (Int, String)? {
            var k = pos
            while true {
                k += 1
                if k >= end { return nil }
                if src[k] == "<" { return nil }
                if src[k] == ">" { break }
            }
            let url = makeString(src[(pos + 1)..<k])
            if PreviewLine.matches(PreviewLine.autolinkRE, url) != nil {
                return PreviewLine.validLink(url) ? (k + 1, url) : nil
            }
            if PreviewLine.matches(PreviewLine.emailRE, url) != nil { return (k + 1, url) }
            return nil
        }

        func html(_ pos: Int, _ end: Int) -> Int? {
            guard pos + 2 < end else { return nil }
            let ch = src[pos + 1]
            guard ch == "!" || ch == "?" || ch == "/" || isASCIILetter(ch) else { return nil }
            guard let m = PreviewLine.matches(PreviewLine.htmlTagRE, makeString(src[pos...])) else { return nil }
            return pos + m.length
        }

        func entity(_ pos: Int, _ end: Int) -> (Int, String)? {
            guard pos + 1 < end else { return nil }
            let rest = makeString(src[pos...])
            if src[pos + 1] == "#" {
                guard let m = PreviewLine.matches(PreviewLine.digitalRE, rest), let g = m.group1 else { return nil }
                let code: Int
                if g.first == "x" || g.first == "X" {
                    code = Int(g.dropFirst(), radix: 16) ?? 0
                } else {
                    code = Int(g, radix: 10) ?? 0
                }
                return (pos + m.length, PreviewLine.entityChar(code))
            }
            guard let m = PreviewLine.matches(PreviewLine.namedRE, rest), let g = m.group1,
                  let value = PreviewLine.entities[g] else { return nil }
            return (pos + m.length, value)
        }

        func destination(_ at: Int, _ end: Int) -> (Int, String)? {
            let start = at
            var pos = at
            if pos < src.count, src[pos] == "<" {
                pos += 1
                while pos < end {
                    let c = src[pos]
                    if c == "\n" || c == "<" { return nil }
                    if c == ">" { return (pos + 1, PreviewLine.unescape(makeString(src[(start + 1)..<pos]))) }
                    if c == "\\", pos + 1 < end {
                        pos += 2
                        continue
                    }
                    pos += 1
                }
                return nil
            }
            var level = 0
            while pos < end {
                let c = src[pos]
                if c == " " || c.value < 0x20 || c.value == 0x7F { break }
                if c == "\\", pos + 1 < end {
                    if src[pos + 1] == " " { break }
                    pos += 2
                    continue
                }
                if c == "(" {
                    level += 1
                    if level > 32 { return nil }
                }
                if c == ")" {
                    if level == 0 { break }
                    level -= 1
                }
                pos += 1
            }
            if start == pos || level != 0 { return nil }
            return (pos, PreviewLine.unescape(makeString(src[start..<pos])))
        }

        func title(_ at: Int, _ end: Int) -> Int? {
            guard at < end else { return nil }
            var marker = src[at]
            guard marker == "\"" || marker == "'" || marker == "(" else { return nil }
            if marker == "(" { marker = ")" }
            var pos = at + 1
            while pos < end {
                let c = src[pos]
                if c == marker { return pos + 1 }
                if c == "(", marker == ")" { return nil }
                if c == "\\", pos + 1 < end { pos += 1 }
                pos += 1
            }
            return nil
        }

        /// `[` 자리 start 에서 짝 `]` 자리 (없으면 -1).
        func labelEnd(_ start: Int, _ end: Int, _ disableNested: Bool) -> Int {
            var pos = start + 1
            var level = 1
            while pos < end {
                let marker = src[pos]
                if marker == "]" {
                    level -= 1
                    if level == 0 { return pos }
                }
                let prev = pos
                pos = skip(pos, end)
                if marker == "[" {
                    if prev == pos - 1 {
                        level += 1
                    } else if disableNested {
                        return -1
                    }
                }
            }
            return -1
        }

        /// `](…)` 뒤 — 링크가 되면 끝 자리, 아니면 nil.
        func linkTail(_ labelEnd: Int, _ end: Int) -> Int? {
            var pos = labelEnd + 1
            guard pos < end, src[pos] == "(" else { return nil }
            pos += 1
            while pos < end, isSpaceTabNewline(src[pos]) { pos += 1 }
            if pos >= end { return nil }
            if let dest = destination(pos, end) {
                if PreviewLine.validLink(dest.1) { pos = dest.0 }
                let start = pos
                while pos < end, isSpaceTabNewline(src[pos]) { pos += 1 }
                if pos < end, start != pos, let t = title(pos, end) {
                    pos = t
                    while pos < end, isSpaceTabNewline(src[pos]) { pos += 1 }
                }
            }
            if pos >= end || src[pos] != ")" { return nil }
            return pos + 1
        }

        /// […](…) — (끝 자리, 라벨 시작, 라벨 끝).
        func tryLink(_ pos: Int, _ end: Int) -> (Int, Int, Int)? {
            let le = labelEnd(pos, end, true)
            if le < 0 { return nil }
            guard let tail = linkTail(le, end) else { return nil }
            return (tail, pos + 1, le)
        }

        func tryImage(_ pos: Int, _ end: Int) -> (Int, Int, Int)? {
            if pos + 1 < end, src[pos + 1] != "[" { return nil }
            let le = labelEnd(pos + 1, end, false)
            if le < 0 { return nil }
            guard let tail = linkTail(le, end) else { return nil }
            return (tail, pos + 2, le)
        }

        /// 한 토큰 건너뛰기 (조용히) — markdown-it `skipToken`.
        func skip(_ pos: Int, _ end: Int) -> Int {
            let c = src[pos]
            if c == "\\" {
                if pos + 1 < end { return pos + 2 }
            } else if c == "`" {
                return codeSpan(pos, end).0
            } else if c == "[" {
                if let r = tryLink(pos, end) { return r.0 }
            } else if c == "!" {
                if let r = tryImage(pos, end) { return r.0 }
            } else if c == "<" {
                if let r = autolink(pos, end) { return r.0 }
                if let r = html(pos, end) { return r }
            } else if c == "&" {
                if let r = entity(pos, end) { return r.0 }
            }
            return pos + 1
        }

        // ── 글로 ──

        func text(_ start: Int, _ end: Int) -> String {
            var contents: [String] = []
            var keep: [Bool] = []
            var delims: [Delim] = []
            func push(_ s: String) {
                contents.append(s)
                keep.append(true)
            }
            var pos = start
            while pos < end {
                let c = src[pos]
                if c == "\\", pos + 1 < end {
                    let next = src[pos + 1]
                    push(PreviewLine.escapable.contains(next) ? String(next) : "\\" + String(next))
                    pos += 2
                    continue
                }
                if c == "`" {
                    let (after, content) = codeSpan(pos, end)
                    if let content {
                        push(makeString(content))
                    } else {
                        push(makeString(src[pos..<after]))
                    }
                    pos = after
                    continue
                }
                if c == "~" {
                    let (canOpen, canClose, n) = scanDelims(pos, end, true)
                    push(String(repeating: "~", count: n))
                    if n <= 2 { delims.append(Delim("~", 0, contents.count - 1, canOpen, canClose)) }
                    pos += n
                    continue
                }
                if c == "*" || c == "_" {
                    let (canOpen, canClose, n) = scanDelims(pos, end, c == "*")
                    for _ in 0..<n {
                        push(String(c))
                        delims.append(Delim(c, n, contents.count - 1, canOpen, canClose))
                    }
                    pos += n
                    continue
                }
                if c == "[", let r = tryLink(pos, end) {
                    push(text(r.1, r.2))
                    pos = r.0
                    continue
                }
                if c == "!", let r = tryImage(pos, end) {
                    let alt = Array(src[r.1..<r.2])
                    push(Inline(alt).text(0, alt.count))
                    pos = r.0
                    continue
                }
                if c == "<" {
                    if let r = autolink(pos, end) {
                        push(r.1)
                        pos = r.0
                        continue
                    }
                    if let r = html(pos, end) {
                        push(makeString(src[pos..<r]))
                        pos = r
                        continue
                    }
                }
                if c == "&", let r = entity(pos, end) {
                    push(r.1)
                    pos = r.0
                    continue
                }
                push(String(c))
                pos += 1
            }
            PreviewLine.balance(delims)
            for d in delims where d.end >= 0 {
                let closer = delims[d.end]
                if d.marker == "~", contents[d.token] != contents[closer.token] { continue }
                keep[d.token] = false
                keep[closer.token] = false
            }
            var out = ""
            for (k, s) in contents.enumerated() where keep[k] { out += s }
            return out
        }
    }

    /// markdown-it `processDelimiters` — 여는 표시마다 닫는 짝을 찾는다.
    static func balance(_ delims: [Delim]) {
        guard !delims.isEmpty else { return }
        var bottoms: [Unicode.Scalar: [Int]] = [:]
        var header = 0
        var lastToken = -2
        var jumps: [Int] = []
        for ci in delims.indices {
            let closer = delims[ci]
            jumps.append(0)
            if delims[header].marker != closer.marker || lastToken != closer.token - 1 {
                header = ci
            }
            lastToken = closer.token
            if !closer.close { continue }
            if bottoms[closer.marker] == nil { bottoms[closer.marker] = Array(repeating: -1, count: 6) }
            let slot = (closer.open ? 3 : 0) + (closer.length % 3)
            let minimum = bottoms[closer.marker]![slot]
            var oi = header - jumps[header] - 1
            var newMin = oi
            while oi > minimum {
                let opener = delims[oi]
                if opener.marker != closer.marker {
                    oi -= jumps[oi] + 1
                    continue
                }
                if opener.open, opener.end < 0 {
                    let odd = (opener.close || closer.open) && (opener.length + closer.length) % 3 == 0
                        && (opener.length % 3 != 0 || closer.length % 3 != 0)
                    if !odd {
                        let lastJump = (oi > 0 && !delims[oi - 1].open) ? jumps[oi - 1] + 1 : 0
                        jumps[ci] = ci - oi + lastJump
                        jumps[oi] = lastJump
                        closer.open = false
                        opener.end = ci
                        opener.close = false
                        newMin = -1
                        lastToken = -2
                        break
                    }
                }
                oi -= jumps[oi] + 1
            }
            if newMin != -1 { bottoms[closer.marker]![slot] = newMin }
        }
    }

    // MARK: - 글자 갈래 · 표

    static let escapable: Set<Unicode.Scalar> = Set("\\!\"#$%&'()*+,./:;<=>?@[]^_`{|}~-".unicodeScalars)
    static let asciiPunct: Set<Unicode.Scalar> = Set("!\"#$%&'()*+,-./:;<=>?@[\\]^_`{|}~".unicodeScalars)
    static let mdWhitespace: Set<UInt32> = [0x09, 0x0A, 0x0B, 0x0C, 0x0D, 0x20, 0xA0, 0x1680, 0x202F, 0x205F, 0x3000]

    /// 자주 쓰는 이름만 안다 — 모르는 이름은 글자 그대로 (파이썬 쌍둥이와 같은 표).
    static let entities: [String: String] = [
        "amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'", "nbsp": "\u{00A0}",
        "copy": "©", "reg": "®", "trade": "™", "hellip": "…", "mdash": "—", "ndash": "–",
        "middot": "·", "laquo": "«", "raquo": "»", "lsquo": "‘", "rsquo": "’", "ldquo": "“", "rdquo": "”",
        "deg": "°", "times": "×", "bull": "•",
    ]

    static func isPunct(_ s: Unicode.Scalar) -> Bool {
        if asciiPunct.contains(s) { return true }
        switch s.properties.generalCategory {
        case .connectorPunctuation, .dashPunctuation, .openPunctuation, .closePunctuation,
             .initialPunctuation, .finalPunctuation, .otherPunctuation,
             .mathSymbol, .currencySymbol, .modifierSymbol, .otherSymbol:
            return true
        default:
            return false
        }
    }

    static func isWhite(_ s: Unicode.Scalar) -> Bool {
        (0x2000...0x200A).contains(s.value) || mdWhitespace.contains(s.value)
    }

    static func entityChar(_ code: Int) -> String {
        let valid: Bool = {
            if (0xD800...0xDFFF).contains(code) || (0xFDD0...0xFDEF).contains(code) { return false }
            if (code & 0xFFFF) == 0xFFFF || (code & 0xFFFF) == 0xFFFE { return false }
            if (0x00...0x08).contains(code) || code == 0x0B || (0x0E...0x1F).contains(code) || (0x7F...0x9F).contains(code) {
                return false
            }
            return code <= 0x10FFFF
        }()
        guard valid, let scalar = Unicode.Scalar(UInt32(code)) else { return "\u{FFFD}" }
        return String(scalar)
    }

    /// `\` 빗금 풀기와 문자 참조 풀기 (링크 주소 안) — 나쁜 주소 거르기에만 쓰인다.
    static func unescape(_ text: String) -> String {
        let s = Array(text.unicodeScalars)
        var out = ""
        var i = 0
        while i < s.count {
            if s[i] == "\\", i + 1 < s.count, escapable.contains(s[i + 1]) {
                out.unicodeScalars.append(s[i + 1])
                i += 2
                continue
            }
            if s[i] == "&" {
                let rest = makeString(s[i...])
                if i + 1 < s.count, s[i + 1] == "#" {
                    if let m = matches(digitalRE, rest), let g = m.group1 {
                        let code = (g.first == "x" || g.first == "X") ? (Int(g.dropFirst(), radix: 16) ?? 0) : (Int(g) ?? 0)
                        out += entityChar(code)
                        i += m.length
                        continue
                    }
                } else if let m = matches(namedRE, rest), let g = m.group1, let value = entities[g] {
                    out += value
                    i += m.length
                    continue
                }
            }
            out.unicodeScalars.append(s[i])
            i += 1
        }
        return out
    }

    static func validLink(_ url: String) -> Bool {
        let u = url.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let bad = ["vbscript:", "javascript:", "file:", "data:"].contains { u.hasPrefix($0) }
        guard bad else { return true }
        return ["data:image/gif;", "data:image/png;", "data:image/jpeg;", "data:image/webp;"].contains { u.hasPrefix($0) }
    }

    // MARK: - 정규식 (파이썬 쌍둥이의 것을 글자 그대로) — 저장해 두지 않는다 (Swift 6 동시성 검사 · `<` · `&` 를 만날 때만 쓴다)

    static var htmlTagRE: NSRegularExpression? { try? NSRegularExpression(pattern: ##"^(?:<[A-Za-z][A-Za-z0-9\-]*(?:\s+[a-zA-Z_:][a-zA-Z0-9:._-]*(?:\s*=\s*(?:[^"'=<>`\x00-\x20]+|'[^']*'|"[^"]*"))?)*\s*\/?>|<\/[A-Za-z][A-Za-z0-9\-]*\s*>|<!---?>|<!--(?:[^-]|-[^-]|--[^>])*-->|<[?][\s\S]*?[?]>|<![A-Za-z][^>]*>|<!\[CDATA\[[\s\S]*?\]\]>)"##) }
    static var autolinkRE: NSRegularExpression? { try? NSRegularExpression(pattern: ##"^([a-zA-Z][a-zA-Z0-9+.\-]{1,31}):([^<>\x00-\x20]*)$"##) }
    static var emailRE: NSRegularExpression? { try? NSRegularExpression(pattern: ##"^([a-zA-Z0-9.!#$%&'*+/=?^_`{|}~-]+@[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(?:\.[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)*)$"##) }
    static var digitalRE: NSRegularExpression? { try? NSRegularExpression(pattern: ##"^&#((?:x[a-f0-9]{1,6}|[0-9]{1,7}));"##, options: [.caseInsensitive]) }
    static var namedRE: NSRegularExpression? { try? NSRegularExpression(pattern: ##"^&([a-z][a-z0-9]{1,31});"##, options: [.caseInsensitive]) }

    /// 글 머리에서 맞으면 (맞은 길이 — 스칼라 수, 첫 묶음).
    static func matches(_ regex: NSRegularExpression?, _ text: String) -> (length: Int, group1: String?)? {
        guard let regex else { return nil }
        let whole = NSRange(text.startIndex..., in: text)
        guard let m = regex.firstMatch(in: text, options: [.anchored], range: whole),
              let range = Range(m.range, in: text) else { return nil }
        var group: String?
        if m.numberOfRanges > 1, let g = Range(m.range(at: 1), in: text) { group = String(text[g]) }
        return (text[range].unicodeScalars.count, group)
    }
}

// MARK: - 작은 도우미

private func makeString<C: Collection>(_ scalars: C) -> String where C.Element == Unicode.Scalar {
    var view = String.UnicodeScalarView()
    view.append(contentsOf: scalars)
    return String(view)
}

private func isSpaceTab(_ s: Unicode.Scalar) -> Bool { s == " " || s == "\t" }
private func isSpaceTabNewline(_ s: Unicode.Scalar) -> Bool { s == " " || s == "\t" || s == "\n" }
private func isDigit(_ s: Unicode.Scalar) -> Bool { s.value >= 0x30 && s.value <= 0x39 }
private func isASCIILetter(_ s: Unicode.Scalar) -> Bool {
    (s.value >= 0x41 && s.value <= 0x5A) || (s.value >= 0x61 && s.value <= 0x7A)
}

private func trimSpaceTab(_ s: [Unicode.Scalar]) -> [Unicode.Scalar] {
    var a = 0, b = s.count
    while a < b, isSpaceTab(s[a]) { a += 1 }
    while b > a, isSpaceTab(s[b - 1]) { b -= 1 }
    return Array(s[a..<b])
}
