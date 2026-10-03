import Foundation

/// **붙여넣은 HTML 전체를 마크다운으로** (206 · 207, 2026-10-02 사용자 — *아이폰 메모에서 표가 포함된 긴 글을 복사해서
/// 붙여 넣으면 표만 변환되고 나머지 글을 모두 날라가는데 이 부분은 반드시 수정이 되어야 해. 메모에서 사용한 양식을 최대한 MD
/// 문법으로 잘 변환될 수 있게*).
///
/// 159 의 `HTMLTable` 은 HTML 에서 **표 하나만** 꺼내 그것만 붙였다 — 표가 든 긴 글을 붙이면 나머지가 사라졌다. 이제 글 전체를
/// **차례대로** 읽는다: 제목(h1~h6 · 글자가 본문보다 큰 문단) · 문단 · 목록(겹침 · 번호 · 체크) · 표 · 인용 · 코드 · 가로줄,
/// 글 속의 굵게 · 기울임 · 취소선 · 고정폭 · 링크. 아이폰 메모는 굵게 · 글자 크기를 `<style>` 의 갈래 규칙으로 싣는다 — 그것도 읽는다.
///
/// 사진(`<img>` · 글 속 U+FFFC)은 **U+FFFC 한 자**로 자리만 남긴다. 앱이 파일로 저장한 뒤 `fillImages` 로 링크를 넣는다 (207).
///
/// **파이썬 `Tools/golden/html_markdown.py` 와 같은 셈이다** (`htmlMarkdownCases`). 파이썬 쪽은 그 답을 cmark-gfm 으로 그려
/// 글자가 하나도 안 빠졌는지까지 보고 온다. 둘이 같은 답을 내도록 **정규식 · 파서 라이브러리 없이 유니코드 스칼라 하나씩** 훑는다.
/// 순수 함수다 — UIKit 을 모른다.
public enum HTMLMarkdown {

    /// 사진 자리 하나 — 문서 차례. `src` 가 `data:` 면 그 안에 사진이 들었다.
    public struct ImageSlot: Equatable, Sendable {
        public let src: String
        public let alt: String
        public init(src: String, alt: String) {
            self.src = src
            self.alt = alt
        }
    }

    /// 사진 자리 글자. 바꾼 글에 이것이 사진 수만큼 들어 있다.
    public static let objectMark: Unicode.Scalar = "\u{FFFC}"

    /// HTML 을 마크다운으로. 글이 없으면 `nil`.
    public static func convert(_ html: String) -> String? {
        let doc = Doc(root: buildTree(Array(html.unicodeScalars)))
        doc.body = bodySize(doc)
        let text = joinBlocks(containerBlocks(doc, doc.root, Style()))
        var lines = splitLines(text)
        while let first = lines.first, trimSpaces(first).isEmpty { lines.removeFirst() }
        while let last = lines.last, trimSpaces(last).isEmpty { lines.removeLast() }
        let out = lines.joined(separator: "\n")
        return out.isEmpty ? nil : out
    }

    /// 사진 자리 — 문서 차례대로 `<img>` 와 글 속 U+FFFC. `convert` 가 남긴 U+FFFC 와 수 · 차례가 같다.
    public static func imageSlots(_ html: String) -> [ImageSlot] {
        let root = buildTree(Array(html.unicodeScalars))
        var out: [ImageSlot] = []
        func walk(_ node: El) {
            for child in node.children {
                switch child {
                case .text(let text):
                    for scalar in text.unicodeScalars where scalar == objectMark {
                        out.append(ImageSlot(src: "", alt: ""))
                    }
                case .element(let el):
                    guard !skip.contains(el.name) else { continue }
                    if el.name == "img" {
                        out.append(ImageSlot(src: trim(el.attrs["src"] ?? ""), alt: trim(el.attrs["alt"] ?? "")))
                    }
                    walk(el)
                }
            }
        }
        walk(root)
        return out
    }

    /// U+FFFC 를 차례로 링크로 바꾼다 (`nil` 이면 지운다). **수가 안 맞으면 모두 지운다** — 엉뚱한 사진을 엉뚱한 자리에
    /// 넣지 않는다. 빈 줄은 하나까지만, 앞뒤 빈 줄은 뗀다.
    public static func fillImages(_ markdown: String, links: [String?]) -> String {
        let count = markdown.unicodeScalars.filter { $0 == objectMark }.count
        var out = String.UnicodeScalarView()
        var index = 0
        for scalar in markdown.unicodeScalars {
            if scalar == objectMark {
                let link = count == links.count ? links[index] : nil
                index += 1
                if let link, !link.isEmpty { out.append(contentsOf: link.unicodeScalars) }
                continue
            }
            out.append(scalar)
        }
        var result: [String] = []
        for line in splitLines(String(out)).map(rstripSpace) {
            if line.isEmpty, let last = result.last, last.isEmpty { continue }
            result.append(line)
        }
        while let first = result.first, first.isEmpty { result.removeFirst() }
        while let last = result.last, last.isEmpty { result.removeLast() }
        return result.joined(separator: "\n")
    }

    /// **평문의 글자 · 숫자가 차례대로 모두 바꾼 글에 있나** — 바꾼 글에 더 있는 것(링크 주소)은 된다.
    /// 앱은 이것이 거짓이면 바꾸지 않고 **평문 그대로** 붙인다. 붙여넣기에서 글이 사라지는 일은 다시 없어야 한다 (206).
    public static func keepsLetters(plain: String, converted: String) -> Bool {
        let want = letters(plain)
        var at = 0
        for scalar in letters(converted) where at < want.count && want[at] == scalar {
            at += 1
        }
        return at == want.count
    }

    /// 줄 첫머리의 번호(`2.` · `3)`)를 뗀다 — 안전장치가 견주지 않는 글자다.
    ///
    /// 메모는 표에 끊긴 번호 목록을 평문에서 **이어 센다**(`2.`) — HTML 은 `<ol>` 마다 1 부터다. 그 차이를 *글자가 빠졌다*
    /// 로 읽어 변환을 버리고 평문을 붙였다 (빌드 74 · 사용자 진단). 번호는 목록이 다시 매기는 것이라 글이 아니다.
    static func dropListNumbers(_ text: String) -> String {
        splitLines(text).map { line -> String in
            let s = Array(line.unicodeScalars)
            var i = 0
            while i < s.count, s[i] == " " || s[i] == "\t" { i += 1 }
            var j = i
            while j < s.count, j - i < 9, isDigit(s[j]) { j += 1 }
            if j > i, j < s.count, s[j] == "." || s[j] == ")", j + 1 == s.count || s[j + 1] == " " || s[j + 1] == "\t" {
                return string(s[0..<i]) + string(s[(j + 1)...])
            }
            return line
        }.joined(separator: "\n")
    }

    static func letters(_ text: String) -> [Unicode.Scalar] {
        dropListNumbers(text).precomposedStringWithCanonicalMapping.unicodeScalars.filter { scalar in
            switch scalar.properties.generalCategory {
            case .uppercaseLetter, .lowercaseLetter, .titlecaseLetter, .modifierLetter, .otherLetter, .decimalNumber:
                return true
            default:
                return false
            }
        }
    }

    // MARK: - 글자 갈래

    static let void: Set<String> = ["area", "base", "br", "col", "embed", "hr", "img", "input", "link", "meta",
                                    "param", "source", "track", "wbr"]
    static let raw: Set<String> = ["script", "style", "textarea", "title", "xmp"]
    static let skip: Set<String> = ["head", "script", "style", "title", "meta", "link", "noscript", "template", "svg",
                                    "math", "iframe", "button", "select", "option", "textarea", "xmp"]
    static let block: Set<String> = ["address", "article", "aside", "blockquote", "body", "center", "dd", "details",
                                     "dialog", "div", "dl", "dt", "fieldset", "figcaption", "figure", "footer", "form",
                                     "h1", "h2", "h3", "h4", "h5", "h6", "header", "hr", "html", "li", "main", "nav",
                                     "ol", "p", "pre", "section", "summary", "table", "tbody", "td", "tfoot", "th",
                                     "thead", "tr", "ul"]
    static let headings: [String: Int] = ["h1": 1, "h2": 2, "h3": 3, "h4": 4, "h5": 5, "h6": 6]
    static let nbsp: Unicode.Scalar = "\u{00A0}"

    static func isSpace(_ c: Unicode.Scalar) -> Bool {
        c == " " || c == "\t" || c == "\n" || c == "\r" || c == "\u{0C}"
    }
    static func isLetter(_ c: Unicode.Scalar) -> Bool { (c >= "a" && c <= "z") || (c >= "A" && c <= "Z") }
    static func isDigit(_ c: Unicode.Scalar) -> Bool { c >= "0" && c <= "9" }
    static func isHex(_ c: Unicode.Scalar) -> Bool { isDigit(c) || (c >= "a" && c <= "f") || (c >= "A" && c <= "F") }
    static func isNameChar(_ c: Unicode.Scalar) -> Bool { isLetter(c) || isDigit(c) || c == "-" || c == ":" }

    static func string<S: Sequence>(_ scalars: S) -> String where S.Element == Unicode.Scalar {
        var view = String.UnicodeScalarView()
        view.append(contentsOf: scalars)
        return String(view)
    }

    static func asciiLower(_ text: String) -> String {
        string(text.unicodeScalars.map { c in
            (c >= "A" && c <= "Z") ? Unicode.Scalar(c.value + 32)! : c
        })
    }

    static func trim(_ text: String) -> String {
        let s = Array(text.unicodeScalars)
        var a = 0, b = s.count
        while a < b, isSpace(s[a]) { a += 1 }
        while b > a, isSpace(s[b - 1]) { b -= 1 }
        return string(s[a..<b])
    }

    /// 앞뒤의 빈칸(` `)만 뗀다.
    static func trimSpaces(_ text: String) -> String {
        let s = Array(text.unicodeScalars)
        var a = 0, b = s.count
        while a < b, s[a] == " " { a += 1 }
        while b > a, s[b - 1] == " " { b -= 1 }
        return string(s[a..<b])
    }

    static func rstripSpace(_ text: String) -> String {
        let s = Array(text.unicodeScalars)
        var b = s.count
        while b > 0, s[b - 1] == " " || s[b - 1] == "\t" { b -= 1 }
        return string(s[0..<b])
    }

    /// `\n` 으로만 가른다 — 빈 줄도 남긴다 (스칼라로 본다. `Character` 는 `\r\n` 을 한 자로 본다).
    static func splitLines(_ text: String) -> [String] {
        var out: [String] = []
        var current = String.UnicodeScalarView()
        for c in text.unicodeScalars {
            if c == "\n" {
                out.append(String(current))
                current = String.UnicodeScalarView()
            } else {
                current.append(c)
            }
        }
        out.append(String(current))
        return out
    }

    static func split(_ text: String, on separator: Unicode.Scalar) -> [String] {
        var out: [String] = []
        var current = String.UnicodeScalarView()
        for c in text.unicodeScalars {
            if c == separator {
                out.append(String(current))
                current = String.UnicodeScalarView()
            } else {
                current.append(c)
            }
        }
        out.append(String(current))
        return out
    }

    static func replacing(_ text: String, _ target: String, with replacement: String) -> String {
        let s = Array(text.unicodeScalars), t = Array(target.unicodeScalars)
        guard !t.isEmpty, s.count >= t.count else { return text }
        var out = String.UnicodeScalarView()
        var i = 0
        while i < s.count {
            if i + t.count <= s.count, Array(s[i..<(i + t.count)]) == t {
                out.append(contentsOf: replacement.unicodeScalars)
                i += t.count
            } else {
                out.append(s[i])
                i += 1
            }
        }
        return String(out)
    }

    static func contains(_ text: String, _ needle: String) -> Bool {
        find(Array(text.unicodeScalars), Array(needle.unicodeScalars), from: 0) >= 0
    }

    static func find(_ s: [Unicode.Scalar], _ needle: [Unicode.Scalar], from start: Int) -> Int {
        let n = s.count, m = needle.count
        var i = start
        while i + m <= n {
            if Array(s[i..<(i + m)]) == needle { return i }
            i += 1
        }
        return -1
    }

    // MARK: - 엔터티

    static let named: [String: String] = ["amp": "&", "lt": "<", "gt": ">", "quot": "\u{22}", "apos": "'",
                                          "nbsp": "\u{00A0}"]

    static func decodeEntities(_ text: String) -> String {
        let s = Array(text.unicodeScalars)
        guard s.contains("&") else { return text }
        var out = String.UnicodeScalarView()
        var i = 0
        let n = s.count
        while i < n {
            let c = s[i]
            if c != "&" {
                out.append(c)
                i += 1
                continue
            }
            var j = i + 1
            while j < n, j - i <= 32, s[j] != ";", s[j] != "&" { j += 1 }
            if j < n, s[j] == ";", j > i + 1, let got = entity(Array(s[(i + 1)..<j])) {
                out.append(contentsOf: got.unicodeScalars)
                i = j + 1
                continue
            }
            out.append("&")
            i += 1
        }
        return String(out)
    }

    static func entity(_ body: [Unicode.Scalar]) -> String? {
        var value: UInt32
        if body.count >= 2, body[0] == "#", body[1] == "x" || body[1] == "X" {
            let digits = body.dropFirst(2)
            guard !digits.isEmpty, digits.count <= 8, digits.allSatisfy(isHex),
                  let parsed = UInt32(string(digits), radix: 16) else { return nil }
            value = parsed
        } else if body.first == "#" {
            let digits = body.dropFirst()
            guard !digits.isEmpty, digits.count <= 8, digits.allSatisfy(isDigit),
                  let parsed = UInt32(string(digits)) else { return nil }
            value = parsed
        } else {
            return named[string(body)]
        }
        guard value > 0, value <= 0x10FFFF, !(value >= 0xD800 && value <= 0xDFFF),
              let scalar = Unicode.Scalar(value) else { return nil }
        return string([scalar])
    }

    // MARK: - 글자를 태그로

    enum Token {
        case text(String)
        case start(String, [String: String], Bool)
        case end(String)
        case raw(String)
    }

    static func findRawEnd(_ s: [Unicode.Scalar], name: String, from start: Int) -> Int {
        let target = Array(name.unicodeScalars)
        let n = s.count, m = target.count
        var i = start
        while i + 2 + m <= n {
            if s[i] == "<", s[i + 1] == "/", asciiLower(string(s[(i + 2)..<(i + 2 + m)])) == name { return i }
            i += 1
        }
        return -1
    }

    static func tokenize(_ s: [Unicode.Scalar]) -> [Token] {
        var tokens: [Token] = []
        var text = String.UnicodeScalarView()
        var i = 0
        let n = s.count
        func flushText() {
            if !text.isEmpty {
                tokens.append(.text(String(text)))
                text = String.UnicodeScalarView()
            }
        }
        let commentOpen: [Unicode.Scalar] = ["<", "!", "-", "-"]
        while i < n {
            let c = s[i]
            if c != "<" {
                text.append(c)
                i += 1
                continue
            }
            if i + 4 <= n, Array(s[i..<(i + 4)]) == commentOpen {
                let j = find(s, ["-", "-", ">"], from: i + 4)
                i = j < 0 ? n : j + 3
                continue
            }
            if i + 1 < n, s[i + 1] == "!" || s[i + 1] == "?" {
                let j = find(s, [">"], from: i + 2)
                i = j < 0 ? n : j + 1
                continue
            }
            var k = i + 1
            var closing = false
            if k < n, s[k] == "/" {
                closing = true
                k += 1
            }
            guard k < n, isLetter(s[k]) else {
                text.append("<")
                i += 1
                continue
            }
            let start = k
            while k < n, isNameChar(s[k]) { k += 1 }
            let name = asciiLower(string(s[start..<k]))
            var attrs: [String: String] = [:]
            var selfClose = false
            var done = false
            while k < n {
                while k < n, isSpace(s[k]) { k += 1 }
                if k >= n { break }
                if s[k] == ">" {
                    k += 1
                    done = true
                    break
                }
                if s[k] == "/" {
                    selfClose = true
                    k += 1
                    continue
                }
                let a = k
                while k < n, !isSpace(s[k]), s[k] != "=", s[k] != ">", s[k] != "/" { k += 1 }
                if k == a {
                    k += 1
                    continue
                }
                let attr = asciiLower(string(s[a..<k]))
                while k < n, isSpace(s[k]) { k += 1 }
                var value = ""
                if k < n, s[k] == "=" {
                    k += 1
                    while k < n, isSpace(s[k]) { k += 1 }
                    if k < n, s[k] == "\u{22}" || s[k] == "'" {
                        let quote = s[k]
                        k += 1
                        let v = k
                        while k < n, s[k] != quote { k += 1 }
                        value = string(s[v..<k])
                        if k < n { k += 1 }
                    } else {
                        let v = k
                        while k < n, !isSpace(s[k]), s[k] != ">" { k += 1 }
                        value = string(s[v..<k])
                    }
                }
                if attrs[attr] == nil { attrs[attr] = decodeEntities(value) }
            }
            guard done else {
                text.append("<")
                i += 1
                continue
            }
            flushText()
            if closing {
                tokens.append(.end(name))
                i = k
                continue
            }
            tokens.append(.start(name, attrs, selfClose))
            i = k
            if raw.contains(name), !selfClose {
                let j = findRawEnd(s, name: name, from: i)
                let end = j < 0 ? n : j
                tokens.append(.raw(string(s[i..<end])))
                i = end
            }
        }
        flushText()
        return tokens
    }

    enum Node {
        case text(String)
        case element(El)
    }

    final class El {
        let name: String
        let attrs: [String: String]
        var children: [Node]
        var blockMemo: Bool?
        init(name: String, attrs: [String: String], children: [Node]) {
            self.name = name
            self.attrs = attrs
            self.children = children
        }
    }

    static func buildTree(_ s: [Unicode.Scalar]) -> El {
        let root = El(name: "#root", attrs: [:], children: [])
        var stack = [root]
        for token in tokenize(s) {
            switch token {
            case .start(let name, let attrs, let selfClose):
                let top = stack[stack.count - 1].name
                if (name == "li" && top == "li") || (name == "p" && top == "p")
                    || ((name == "td" || name == "th") && (top == "td" || top == "th"))
                    || (name == "tr" && top == "tr") {
                    stack.removeLast()
                }
                let el = El(name: name, attrs: attrs, children: [])
                stack[stack.count - 1].children.append(.element(el))
                if !void.contains(name), !selfClose { stack.append(el) }
            case .end(let name):
                var index = stack.count - 1
                while index > 0 {
                    if stack[index].name == name {
                        stack.removeSubrange(index...)
                        break
                    }
                    index -= 1
                }
            case .text(let text):
                stack[stack.count - 1].children.append(.text(decodeEntities(text)))
            case .raw(let text):
                stack[stack.count - 1].children.append(.text(text))
            }
        }
        return root
    }

    // MARK: - CSS

    static func stripComments(_ css: String) -> String {
        let s = Array(css.unicodeScalars)
        var out = String.UnicodeScalarView()
        var i = 0
        while i < s.count {
            if i + 1 < s.count, s[i] == "/", s[i + 1] == "*" {
                let j = find(s, ["*", "/"], from: i + 2)
                i = j < 0 ? s.count : j + 2
                continue
            }
            out.append(s[i])
            i += 1
        }
        return String(out)
    }

    static func parseDeclarations(_ text: String) -> [(String, String)] {
        var out: [(String, String)] = []
        for part in split(text, on: ";") {
            let s = Array(part.unicodeScalars)
            guard let colon = s.firstIndex(of: ":") else { continue }
            let prop = asciiLower(trim(string(s[0..<colon])))
            let value = asciiLower(trim(string(s[(colon + 1)...])))
            if !prop.isEmpty { out.append((prop, value)) }
        }
        return out
    }

    static func classOfSelector(_ selector: String) -> String? {
        let s = Array(selector.unicodeScalars)
        guard let dot = s.firstIndex(of: ".") else { return nil }
        let tag = s[0..<dot], cls = s[(dot + 1)...]
        guard tag.allSatisfy({ isLetter($0) || isDigit($0) }) else { return nil }
        guard !cls.isEmpty, cls.allSatisfy({ isLetter($0) || isDigit($0) || $0 == "_" || $0 == "-" }) else {
            return nil
        }
        return string(cls)
    }

    static func parseCSS(_ css: String) -> [String: [(String, String)]] {
        var rules: [String: [(String, String)]] = [:]
        for chunk in split(stripComments(css), on: "}") {
            let s = Array(chunk.unicodeScalars)
            guard let brace = s.firstIndex(of: "{") else { continue }
            let declarations = parseDeclarations(string(s[(brace + 1)...]))
            for selector in split(string(s[0..<brace]), on: ",") {
                if let cls = classOfSelector(trim(selector)) {
                    rules[cls, default: []].append(contentsOf: declarations)
                }
            }
        }
        return rules
    }

    static func collectCSS(_ node: El, into out: inout [String]) {
        for child in node.children {
            guard case .element(let el) = child else { continue }
            if el.name == "style" {
                for inner in el.children {
                    if case .text(let text) = inner { out.append(text) }
                }
            } else {
                collectCSS(el, into: &out)
            }
        }
    }

    static func splitWhitespace(_ text: String) -> [String] {
        var out: [String] = []
        var current = String.UnicodeScalarView()
        for c in text.unicodeScalars {
            if isSpace(c) {
                if !current.isEmpty {
                    out.append(String(current))
                    current = String.UnicodeScalarView()
                }
            } else {
                current.append(c)
            }
        }
        if !current.isEmpty { out.append(String(current)) }
        return out
    }

    final class Doc {
        let root: El
        let rules: [String: [(String, String)]]
        var body: Double?
        var listCounter = 0
        /// 표 칸 안인가 — 칸 안의 표는 글자만 (159 와 같다).
        var cellDepth = 0
        /// 목록 항목 안인가.
        var itemDepth = 0

        init(root: El) {
            self.root = root
            var css: [String] = []
            HTMLMarkdown.collectCSS(root, into: &css)
            rules = HTMLMarkdown.parseCSS(css.joined(separator: "\n"))
        }

        func decls(_ el: El) -> [String: String] {
            var d: [String: String] = [:]
            for cls in HTMLMarkdown.splitWhitespace(el.attrs["class"] ?? "") {
                for (prop, value) in rules[cls] ?? [] { d[prop] = value }
            }
            for (prop, value) in HTMLMarkdown.parseDeclarations(el.attrs["style"] ?? "") { d[prop] = value }
            return d
        }

        func hasBlock(_ el: El) -> Bool {
            if let memo = el.blockMemo { return memo }
            var found = false
            for child in el.children {
                if case .element(let inner) = child, !HTMLMarkdown.skip.contains(inner.name),
                   HTMLMarkdown.block.contains(inner.name) || hasBlock(inner) {
                    found = true
                    break
                }
            }
            el.blockMemo = found
            return found
        }

        func isBlock(_ el: El) -> Bool { HTMLMarkdown.block.contains(el.name) || hasBlock(el) }
    }

    // MARK: - 스타일

    /// 처음 나오는 `숫자px` · `숫자pt` 의 숫자.
    static func numberWithUnit(_ text: String) -> Double? {
        let v = Array(text.unicodeScalars)
        let n = v.count
        var i = 0
        while i < n {
            if isDigit(v[i]), i == 0 || !(isDigit(v[i - 1]) || v[i - 1] == ".") {
                var j = i
                while j < n, isDigit(v[j]) { j += 1 }
                if j + 1 < n, v[j] == ".", isDigit(v[j + 1]) {
                    j += 1
                    while j < n, isDigit(v[j]) { j += 1 }
                }
                let number = string(v[i..<j])
                var k = j
                while k < n, isSpace(v[k]) { k += 1 }
                if k + 2 <= n, v[k] == "p", v[k + 1] == "x" || v[k + 1] == "t" {
                    return Double(number)
                }
                i = j
                continue
            }
            i += 1
        }
        return nil
    }

    static func fontSize(_ d: [String: String]) -> Double? {
        if let size = d["font-size"] { return numberWithUnit(size) }
        if let font = d["font"] { return numberWithUnit(font) }
        return nil
    }

    static func cssBold(_ d: [String: String]) -> Bool? {
        if let w = d["font-weight"] {
            if ["bold", "bolder", "600", "700", "800", "900"].contains(w) { return true }
            if ["normal", "lighter", "100", "200", "300", "400", "500"].contains(w) { return false }
        }
        let family = (d["font-family"] ?? "") + " " + (d["font"] ?? "")
        return contains(family, "bold") ? true : nil
    }

    static func cssItalic(_ d: [String: String]) -> Bool? {
        if let style = d["font-style"] {
            if style == "italic" || style == "oblique" { return true }
            if style == "normal" { return false }
        }
        return contains(d["font"] ?? "", "italic") ? true : nil
    }

    static func cssStrike(_ d: [String: String]) -> Bool? {
        let t = (d["text-decoration"] ?? "") + " " + (d["text-decoration-line"] ?? "")
        if contains(t, "line-through") { return true }
        if trim(t) == "none" { return false }
        return nil
    }

    static let monoFamilies = ["menlo", "courier", "monaco", "consolas", "monospace", "sfmono", "sf mono"]

    static func cssMono(_ d: [String: String]) -> Bool {
        let family = (d["font-family"] ?? "") + " " + (d["font"] ?? "")
        return monoFamilies.contains { contains(family, $0) }
    }

    /// `code` — 고정폭으로 그린다 (`<code>` 든 고정폭 글꼴이든). `mono` — **글꼴**이 고정폭이다 (메모의 고정폭 문단).
    struct Style {
        var bold = false
        var italic = false
        var strike = false
        var code = false
        var mono = false
        var href: String?
    }

    static func style(of el: El, in doc: Doc, parent: Style) -> Style {
        var s = parent
        switch el.name {
        case "b", "strong": s.bold = true
        case "i", "em", "cite", "dfn": s.italic = true
        case "s", "strike", "del": s.strike = true
        case "code", "tt", "kbd", "samp": s.code = true
        case "a":
            let href = trim(el.attrs["href"] ?? "")
            if !href.isEmpty, !asciiLower(href).hasPrefix("javascript:") { s.href = href }
        default: break
        }
        let d = doc.decls(el)
        if let bold = cssBold(d) { s.bold = bold }
        if let italic = cssItalic(d) { s.italic = italic }
        if let strike = cssStrike(d) { s.strike = strike }
        if cssMono(d) {
            s.code = true
            s.mono = true
        }
        return s
    }

    // MARK: - 글자 줄기

    struct Run {
        var text: String
        var style: Style
        var isBreak = false
    }

    static func collapse(_ text: String) -> String {
        var out = String.UnicodeScalarView()
        var space = false
        for c in text.unicodeScalars {
            if isSpace(c) {
                if !space { out.append(" ") }
                space = true
            } else {
                out.append(c)
                space = false
            }
        }
        return String(out)
    }

    final class RunState {
        var lastSpace = true
    }

    static func inlineRuns(_ doc: Doc, _ nodes: [Node], _ style: Style, _ state: RunState, _ out: inout [Run]) {
        for node in nodes {
            switch node {
            case .text(let raw):
                var text = Array(collapse(raw).unicodeScalars)
                if text.first == " ", state.lastSpace { text.removeFirst() }
                guard !text.isEmpty else { continue }
                var piece = String.UnicodeScalarView()
                for c in text {
                    if c == objectMark {
                        if !piece.isEmpty {
                            out.append(Run(text: String(piece), style: style))
                            piece = String.UnicodeScalarView()
                        }
                        out.append(Run(text: string([objectMark]), style: style))
                    } else {
                        piece.append(c)
                    }
                }
                if !piece.isEmpty { out.append(Run(text: String(piece), style: style)) }
                state.lastSpace = text.last == " "
            case .element(let el):
                if skip.contains(el.name) || el.name == "input" { continue }
                if el.name == "br" {
                    out.append(Run(text: "\n", style: Style(), isBreak: true))
                    state.lastSpace = true
                    continue
                }
                if el.name == "img" {
                    out.append(Run(text: string([objectMark]), style: style))
                    state.lastSpace = false
                    continue
                }
                inlineRuns(doc, el.children, self.style(of: el, in: doc, parent: style), state, &out)
            }
        }
    }

    static func isGap(_ c: Unicode.Scalar) -> Bool { c == " " || c == nbsp }

    enum Mark: Equatable {
        case link(String), bold, italic, strike, code
    }

    static func marks(_ style: Style, dropBold: Bool) -> [Mark] {
        var out: [Mark] = []
        if let href = style.href { out.append(.link(href)) }
        if style.bold, !dropBold { out.append(.bold) }
        if style.italic { out.append(.italic) }
        if style.strike { out.append(.strike) }
        if style.code { out.append(.code) }
        return out
    }

    static func linkTarget(_ href: String) -> String {
        guard href.unicodeScalars.contains(where: { $0 == " " || $0 == "(" || $0 == ")" || $0 == "<" || $0 == ">" })
        else { return href }
        return "<" + replacing(replacing(href, "<", with: "%3C"), ">", with: "%3E") + ">"
    }

    /// 줄기들을 마크다운 줄들로. 강조 기호는 **글자에 붙인다** — 빈칸은 기호 밖으로 낸다.
    static func emit(_ runs: [Run], dropBold: Bool = false) -> [String] {
        var out = ""
        var stack: [(mark: Mark, opener: String)] = []
        var pending = ""

        func close(to k: Int) {
            while stack.count > k {
                let (mark, opener) = stack.removeLast()
                switch mark {
                case .link(let href): out += "](" + linkTarget(href) + ")"
                case .bold: out += "**"
                case .italic: out += "*"
                case .strike: out += "~~"
                case .code: out += opener == "`` " ? " ``" : "`"
                }
            }
        }

        for run in runs {
            if run.isBreak {
                close(to: 0)
                out += pending
                pending = ""
                out += "\n"
                continue
            }
            let text = Array(run.text.unicodeScalars)
            var a = 0, b = text.count
            while a < b, isGap(text[a]) { a += 1 }
            while b > a, isGap(text[b - 1]) { b -= 1 }
            guard a < b else {
                pending += run.text
                continue
            }
            let core = string(text[a..<b])
            let want = marks(run.style, dropBold: dropBold)
            var k = 0
            while k < stack.count, k < want.count, stack[k].mark == want[k] { k += 1 }
            close(to: k)
            out += pending + string(text[0..<a])
            pending = ""
            for mark in want[k...] {
                let opener: String
                switch mark {
                case .link: opener = "["
                case .bold: opener = "**"
                case .italic: opener = "*"
                case .strike: opener = "~~"
                case .code: opener = core.unicodeScalars.contains("`") ? "`` " : "`"
                }
                out += opener
                stack.append((mark, opener))
            }
            out += core
            pending = string(text[b...])
        }
        close(to: 0)
        out += pending
        return splitLines(out).map { trimSpaces(replacing($0, string([nbsp]), with: " ")) }
    }

    // MARK: - 블록

    struct Block {
        var kind: String
        var lines: [String]
        var group: String
        var runs: [Run] = []
        var fromPara = false
    }

    /// 빈칸 아닌 글자가 든 줄기인가 (사진 자리도 글자다).
    static func isContent(_ run: Run) -> Bool {
        !run.isBreak && run.text.unicodeScalars.contains { scalar in !isGap(scalar) }
    }

    static func hasContent(_ runs: [Run]) -> Bool {
        runs.contains(where: isContent)
    }

    static func flush(_ doc: Doc, _ nodes: [Node], _ style: Style) -> [Block] {
        guard !nodes.isEmpty else { return [] }
        var runs: [Run] = []
        inlineRuns(doc, nodes, style, RunState(), &runs)
        guard hasContent(runs) else {
            return runs.contains { $0.isBreak } ? [Block(kind: "blank", lines: [], group: "blank")] : []
        }
        let content = runs.filter(isContent)
        if doc.cellDepth == 0, doc.itemDepth == 0,
           content.allSatisfy({ $0.style.mono && $0.text != string([objectMark]) }) {
            // 고정폭 **글꼴**만 든 문단 (메모의 고정폭) — 코드 줄로. 여러 문단이 이어지면 한 덩어리로 모은다.
            // 표 칸 · 목록 항목 안에서는 하지 않는다 — 거기서는 글 속 코드로 둔다.
            let raw = runs.map { $0.isBreak ? "\n" : $0.text }.joined()
            var lines = splitLines(raw).map { rstripSpace(replacing($0, string([nbsp]), with: " ")) }
            while let first = lines.first, first.isEmpty { lines.removeFirst() }
            while let last = lines.last, last.isEmpty { lines.removeLast() }
            return [Block(kind: "code", lines: lines, group: "code", fromPara: true)]
        }
        return [Block(kind: "para", lines: emit(runs), group: "text", runs: runs)]
    }

    static func containerBlocks(_ doc: Doc, _ el: El, _ style: Style) -> [Block] {
        var out: [Block] = []
        var buffer: [Node] = []
        for child in el.children {
            switch child {
            case .text:
                buffer.append(child)
            case .element(let inner):
                if skip.contains(inner.name) { continue }
                if doc.isBlock(inner) {
                    out += flush(doc, buffer, style)
                    buffer = []
                    out += blockOf(doc, inner, style)
                } else {
                    buffer.append(child)
                }
            }
        }
        out += flush(doc, buffer, style)
        return out
    }

    static func textContent(_ el: El) -> String {
        var parts = ""
        func walk(_ node: El) {
            for child in node.children {
                switch child {
                case .text(let text): parts += text
                case .element(let inner): if !skip.contains(inner.name) { walk(inner) }
                }
            }
        }
        walk(el)
        return trim(collapse(parts))
    }

    static func blockSize(_ doc: Doc, _ el: El) -> Double? {
        var best = fontSize(doc.decls(el))
        let whole = textContent(el)
        func walk(_ node: El) {
            for child in node.children {
                guard case .element(let inner) = child, !skip.contains(inner.name) else { continue }
                if let size = fontSize(doc.decls(inner)), textContent(inner) == whole {
                    if best == nil || size > best! { best = size }
                }
                walk(inner)
            }
        }
        walk(el)
        return best
    }

    static func bodySize(_ doc: Doc) -> Double? {
        var counts: [Double: Int] = [:]
        func walk(_ node: El) {
            for child in node.children {
                guard case .element(let inner) = child, !skip.contains(inner.name) else { continue }
                if ["p", "div", "li"].contains(inner.name), !doc.hasBlock(inner), !textContent(inner).isEmpty,
                   let size = blockSize(doc, inner) {
                    counts[size, default: 0] += 1
                }
                walk(inner)
            }
        }
        walk(doc.root)
        guard let best = counts.values.max() else { return nil }
        return counts.filter { $0.value == best }.keys.min()
    }

    static func headingLevel(_ doc: Doc, _ el: El, _ runs: [Run]) -> Int? {
        guard let body = doc.body, let size = blockSize(doc, el) else { return nil }
        let ratio = size / body
        if ratio >= 1.45 { return 1 }
        if ratio >= 1.18 { return 2 }
        let content = runs.filter(isContent)
        if ratio >= 1.05, !content.isEmpty, content.allSatisfy({ $0.style.bold }) { return 3 }
        return nil
    }

    static func headingBlock(_ level: Int, _ runs: [Run]) -> [Block] {
        let text = emit(runs, dropBold: true).filter { !$0.isEmpty }.joined(separator: " ")
        guard !text.isEmpty else { return [] }
        return [Block(kind: "heading", lines: [String(repeating: "#", count: level) + " " + text], group: "heading")]
    }

    static func blockOf(_ doc: Doc, _ el: El, _ parent: Style) -> [Block] {
        let s = style(of: el, in: doc, parent: parent)
        let n = el.name
        if let level = headings[n] {
            var runs: [Run] = []
            inlineRuns(doc, el.children, s, RunState(), &runs)
            runs = runs.map { $0.isBreak ? Run(text: " ", style: s) : $0 }
            return headingBlock(level, runs)
        }
        if n == "ul" || n == "ol" {
            doc.listCounter += 1
            return listBlocks(doc, el, s, indent: "", group: "list\(doc.listCounter)")
        }
        if n == "table" {
            if doc.cellDepth > 0 {
                let text = textContent(el)
                return text.isEmpty ? [] : [Block(kind: "para", lines: [text], group: "text")]
            }
            return tableBlocks(doc, el, s)
        }
        if n == "pre" { return preBlock(el) }
        if n == "blockquote" {
            let text = joinBlocks(containerBlocks(doc, el, s))
            guard !text.isEmpty else { return [] }
            return [Block(kind: "quote", lines: splitLines(text).map { $0.isEmpty ? ">" : "> " + $0 }, group: "quote")]
        }
        if n == "hr" { return [Block(kind: "hr", lines: ["---"], group: "hr")] }
        let blocks = containerBlocks(doc, el, s)
        if n == "p" || n == "div", blocks.count == 1, blocks[0].kind == "para", blocks[0].lines.count == 1,
           let level = headingLevel(doc, el, blocks[0].runs) {
            return headingBlock(level, blocks[0].runs)
        }
        return blocks
    }

    static func preBlock(_ el: El) -> [Block] {
        var parts = ""
        func walk(_ node: El) {
            for child in node.children {
                switch child {
                case .text(let text): parts += text
                case .element(let inner):
                    if inner.name == "br" { parts += "\n" }
                    else if inner.name == "img" { parts += string([objectMark]) }
                    else if !skip.contains(inner.name) { walk(inner) }
                }
            }
        }
        walk(el)
        let raw = replacing(replacing(replacing(parts, "\r\n", with: "\n"), "\r", with: "\n"),
                            string([nbsp]), with: " ")
        var lines = splitLines(raw).map(rstripSpace)
        while let first = lines.first, first.isEmpty { lines.removeFirst() }
        while let last = lines.last, last.isEmpty { lines.removeLast() }
        guard !lines.isEmpty else { return [] }
        let fence = lines.contains { contains($0, "```") } ? "~~~" : "```"
        return [Block(kind: "code", lines: [fence] + lines + [fence], group: "code")]
    }

    static let checked: Set<Unicode.Scalar> = ["\u{2611}", "\u{2612}", "\u{2705}", "\u{2713}", "\u{2714}"]
    static let unchecked: Set<Unicode.Scalar> = ["\u{2610}", "\u{25A1}", "\u{25FB}"]
    static let bullets: Set<Unicode.Scalar> = ["\u{2022}", "\u{25E6}", "\u{25AA}", "\u{25AB}", "\u{25CF}", "\u{25CB}",
                                               "\u{25A0}", "\u{2013}", "\u{2014}", "\u{00B7}"]

    static func lstrip(_ s: ArraySlice<Unicode.Scalar>, _ set: Set<Unicode.Scalar>) -> String {
        var a = s.startIndex
        while a < s.endIndex, set.contains(s[a]) { a += 1 }
        return string(s[a...])
    }

    /// 항목 글 앞의 글머리 · 체크 글자를 뗀다. (남은 글, 체크 — 없으면 `nil`).
    static func stripGlyphs(_ text: String, ordered: Bool) -> (String, Bool?) {
        var t = Array(text.unicodeScalars)[...]
        if let first = t.first, checked.contains(first) || unchecked.contains(first) {
            let check = checked.contains(first)
            t = t.dropFirst()
            if t.first == "\u{FE0F}" { t = t.dropFirst() }
            return (lstrip(t, [" "]), check)
        }
        if t.count >= 2, bullets.contains(t[t.startIndex]),
           t[t.startIndex + 1] == " " || t[t.startIndex + 1] == "\t" {
            return (lstrip(t.dropFirst(2), [" ", "\t"]), nil)
        }
        if ordered {
            var j = t.startIndex
            while j < t.endIndex, isDigit(t[j]) { j += 1 }
            let digits = j - t.startIndex
            if digits > 0, j + 1 < t.endIndex, t[j] == "." || t[j] == ")", t[j + 1] == " " || t[j + 1] == "\t" {
                return (lstrip(t[(j + 2)...], [" ", "\t"]), nil)
            }
        }
        return (string(t), nil)
    }

    static func checkbox(_ li: El) -> Bool? {
        for child in li.children {
            guard case .element(let el) = child else { continue }
            if el.name == "ul" || el.name == "ol" { continue }
            if el.name == "input", asciiLower(el.attrs["type"] ?? "") == "checkbox" {
                return el.attrs["checked"] != nil
            }
            if let got = checkbox(el) { return got }
        }
        return nil
    }

    static func startNumber(_ el: El) -> Int {
        let v = Array(trim(el.attrs["start"] ?? "").unicodeScalars)
        var j = 0
        while j < v.count, j < 9, isDigit(v[j]) { j += 1 }
        return j > 0 ? (Int(string(v[0..<j])) ?? 1) : 1
    }

    static func listBlocks(_ doc: Doc, _ el: El, _ style: Style, indent: String, group: String) -> [Block] {
        let ordered = el.name == "ol"
        var number = startNumber(el)
        var out: [Block] = []
        var stray: [Node] = []
        var lastWidth = 2

        func item(_ content: El?, _ nodes: [Node]) {
            let holder = content ?? El(name: "li", attrs: [:], children: nodes)
            let s = self.style(of: holder, in: doc, parent: style)
            let body = El(name: holder.name, attrs: holder.attrs, children: holder.children.filter { node in
                if case .element(let inner) = node, inner.name == "ul" || inner.name == "ol" { return false }
                return true
            })
            let nested: [El] = holder.children.compactMap { node in
                if case .element(let inner) = node, inner.name == "ul" || inner.name == "ol" { return inner }
                return nil
            }
            doc.itemDepth += 1
            let blocks = containerBlocks(doc, body, s).filter { $0.kind != "blank" }
            doc.itemDepth -= 1
            let lines = blocks.flatMap(\.lines)
            let first = lines.first ?? ""
            let rest = lines.dropFirst()
            let stripped = stripGlyphs(first, ordered: ordered)
            let text = stripped.0
            var check = stripped.1
            if let box = checkbox(holder) { check = box }
            var marker = ordered ? "\(number). " : "- "
            let width = marker.unicodeScalars.count
            lastWidth = width
            number += 1
            if let check { marker += check ? "[x] " : "[ ] " }
            var itemLines = [rstripSpace(indent + marker + text)]
            let pad = indent + String(repeating: " ", count: width)
            itemLines += rest.map { $0.isEmpty ? "" : pad + $0 }
            out.append(Block(kind: "item", lines: itemLines, group: group))
            for sub in nested {
                out += listBlocks(doc, sub, s, indent: pad, group: group)
            }
        }

        func flushStray() {
            let meaningful = stray.contains { node in
                switch node {
                case .text(let text): return !trim(collapse(text)).isEmpty
                case .element: return true
                }
            }
            if meaningful { item(nil, stray) }
            stray = []
        }

        for child in el.children {
            if case .element(let inner) = child {
                if inner.name == "li" {
                    flushStray()
                    item(inner, [])
                    continue
                }
                if inner.name == "ul" || inner.name == "ol" {
                    flushStray()
                    out += listBlocks(doc, inner, style, indent: indent + String(repeating: " ", count: lastWidth),
                                      group: group)
                    continue
                }
                if skip.contains(inner.name) { continue }
            }
            stray.append(child)
        }
        flushStray()
        return out
    }

    /// 칸 안에서 **마크다운 표를 깨뜨리는 글자**를 피한다 — `|` 는 `\|`, 줄바꿈은 `<br>` (159 와 같다).
    public static func escapeCell(_ text: String) -> String {
        var out = String.UnicodeScalarView()
        for c in text.unicodeScalars {
            if c == "|" { out.append("\\") }
            out.append(c)
        }
        return replacing(replacing(String(out), "\r\n", with: "\n"), "\n", with: "<br>")
    }

    static func tableBlocks(_ doc: Doc, _ el: El, _ style: Style) -> [Block] {
        var rows: [(cells: [String], isHeader: Bool)] = []
        func findRows(_ node: El) {
            for child in node.children {
                guard case .element(let inner) = child, !skip.contains(inner.name), inner.name != "table" else {
                    continue
                }
                if inner.name == "tr" {
                    var cells: [String] = []
                    var headers = 0
                    for cellNode in inner.children {
                        guard case .element(let cell) = cellNode, cell.name == "td" || cell.name == "th" else {
                            continue
                        }
                        let s = self.style(of: cell, in: doc, parent: style)
                        doc.cellDepth += 1
                        let blocks = containerBlocks(doc, cell, s)
                        doc.cellDepth -= 1
                        let lines = blocks.filter { $0.kind != "blank" }.flatMap(\.lines)
                        cells.append(escapeCell(trim(lines.joined(separator: "\n"))))
                        if cell.name == "th" { headers += 1 }
                    }
                    if !cells.isEmpty { rows.append((cells, headers == cells.count)) }
                } else {
                    findRows(inner)
                }
            }
        }
        findRows(el)
        guard let width = rows.map({ $0.cells.count }).max(), width > 0 else { return [] }
        var head = rows[0]
        var body = Array(rows.dropFirst())
        if !head.isHeader {
            body.insert(head, at: 0)
            head = (Array(repeating: "", count: width), true)
        }
        func line(_ cells: [String]) -> String {
            var padded = cells
            while padded.count < width { padded.append("") }
            return "| " + padded.map { $0.isEmpty ? " " : $0 }.joined(separator: " | ") + " |"
        }
        let lines = [line(head.cells), "|" + String(repeating: " --- |", count: width)] + body.map { line($0.cells) }
        return [Block(kind: "table", lines: lines, group: "table")]
    }

    static func joinBlocks(_ blocks: [Block]) -> String {
        var merged: [Block] = []
        for block in blocks {
            if block.kind == "code", block.fromPara, let last = merged.last, last.kind == "code", last.fromPara {
                merged[merged.count - 1] = Block(kind: "code", lines: last.lines + block.lines, group: "code",
                                                 fromPara: true)
                continue
            }
            merged.append(block)
        }
        var out: [String] = []
        var previous: Block?
        var blank = false
        for block in merged {
            if block.kind == "blank" {
                if previous != nil { blank = true }
                continue
            }
            var lines = block.lines
            if block.kind == "code", block.fromPara {
                let fence = lines.contains { contains($0, "```") } ? "~~~" : "```"
                lines = [fence] + lines + [fence]
            }
            if lines.isEmpty { continue }
            // 같은 목록의 항목끼리만 붙인다. 문단과 문단 사이도 빈 줄 하나 — 메모는 줄마다 `<p>` 이고, 한 줄 띄움으로
            // 이으면 읽기 화면에서 한 문단으로 붙는다 (표준 · 199). 빌드 74 사용자 진단에서 본 실제 메모 모양이다.
            if let previous {
                let together = block.group == previous.group && block.kind == "item"
                if blank || !together { out.append("") }
            }
            blank = false
            out += lines
            previous = block
        }
        return out.joined(separator: "\n")
    }
}
