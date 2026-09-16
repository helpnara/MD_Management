import Foundation

/// YAML 머리말에서 읽는 것. **앱은 머리말을 만들어 넣지 않는다** — 읽기만 한다.
public struct FrontMatter: Equatable, Sendable {
    public var title: String?
    public var tags: [String]
    public var created: String?

    public init(title: String? = nil, tags: [String] = [], created: String? = nil) {
        self.title = title
        self.tags = tags
        self.created = created
    }
}

/// 머리말과 본문을 나눈 결과.
///
/// **문자열 인덱스나 오프셋을 담지 않는다** (설계서 §3 부속 결정). 본문을 그대로
/// 들고 다니는 편이 안전하다.
public struct ParsedNote: Equatable, Sendable {
    public var frontMatter: FrontMatter?
    public var body: String

    public init(frontMatter: FrontMatter?, body: String) {
        self.frontMatter = frontMatter
        self.body = body
    }
}

public enum FrontMatterParser {

    /// 머리말이 있으면 떼어 내고 본문을 돌려준다.
    ///
    /// `\r\n` 줄바꿈은 **그대로 보존한다** — 줄을 `\n` 으로 나눈 뒤 다시 `\n` 으로
    /// 이으므로 각 줄 끝의 `\r` 이 살아남는다 (설계서 §3 부속 결정).
    public static func parse(_ text: String) -> ParsedNote {
        var source = text
        if source.hasPrefix("\u{FEFF}") { source.removeFirst() }

        let lines = source.components(separatedBy: "\n")
        guard let first = lines.first, fence(first) == "---" else {
            return ParsedNote(frontMatter: nil, body: text)
        }

        var closing: Int? = nil
        for index in 1..<lines.count {
            let mark = fence(lines[index])
            if mark == "---" || mark == "..." {
                closing = index
                break
            }
        }
        guard let end = closing else {
            // 여는 `---` 만 있고 닫는 줄이 없다 — 머리말이 아니라 수평선이다.
            return ParsedNote(frontMatter: nil, body: text)
        }

        let yaml = lines[1..<end].joined(separator: "\n")
        let body = end + 1 < lines.count
            ? lines[(end + 1)...].joined(separator: "\n")
            : ""
        return ParsedNote(frontMatter: parseYAML(yaml), body: body)
    }

    /// 머리말이 차지하는 앞부분의 길이 (**UTF-16**) — 여는 `---` 부터 닫는 줄 끝까지.
    /// 머리말이 없으면 0. 편집기가 이 구간을 통째로 흐리게 칠할 때 쓴다 (L1).
    ///
    /// 문단 하나만 보는 `LineStyler` 는 `title:` 줄이 머리말인지 모른다 — 문서 첫머리라는
    /// 문맥이 필요하다. 그래서 여기서 길이만 재어 주고, 칠하는 쪽이 그 안의 문단을 가린다.
    public static func headerLength(of text: String) -> Int {
        var source = text
        var bom = 0
        if source.hasPrefix("\u{FEFF}") {
            source.removeFirst()
            bom = 1
        }
        let lines = source.components(separatedBy: "\n")
        guard let first = lines.first, fence(first) == "---" else { return 0 }
        for index in 1..<lines.count {
            let mark = fence(lines[index])
            if mark == "---" || mark == "..." {
                return bom + lines[0...index].joined(separator: "\n").utf16.count
            }
        }
        return 0
    }

    /// **파일명이 따라갈 글** (54 · T6, 2026-09-16 사용자 결정).
    ///
    /// 머리말을 뗀 본문의 **첫 줄**(빈 줄은 건너뛴다) 그대로다. **`#` 을 치지 않아도 된다** —
    /// `팀 이슈회의` 라고만 써도 파일명이 된다. 첫 줄이 `# 팀 이슈회의` 면 마크다운 마커를
    /// 떼고 `팀 이슈회의` 를 준다 (예전에 쓰던 노트가 그대로 동작한다).
    ///
    /// **왜 `#` 을 요구하지 않게 했나.** 요구하던 시절에는 반대 방향(`aligned` — 파일명이
    /// 본문을 이긴다)이 필요했고, 자료 사고가 전부 거기서 나왔다 (빌드 20 · 1, 30 · 5,
    /// 32 · 103). 한 방향만 남기면 **앱이 본문을 고치는 코드가 하나도 없다** (ADR-0001).
    public static func firstLine(of text: String) -> String? {
        let body = parse(text).body
        for line in body.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { continue }
            guard let text = stripHeadingMarker(trimmed) else { continue }
            // **글자가 한 자도 없는 줄은 건너뛴다** — `---` 수평선이나 장식 줄이다.
            // 사람이 파일명으로 삼고 싶은 줄이 아니다 (골든 `no-frontmatter.md` 가 그것을 잡았다).
            guard text.contains(where: { $0.isLetter || $0.isNumber }) else { continue }
            return text
        }
        return nil
    }

    /// `# 제목` · `### 제목` 에서 마커를 뗀다. 마커가 없으면 그대로.
    /// 닫는 `#` 도 뗀다 — CommonMark 가 제목에서 빼는 것과 같다 (`# 제목 #`).
    static func stripHeadingMarker(_ line: String) -> String? {
        var rest = Substring(line)
        let hashes = rest.prefix { $0 == "#" }
        if !hashes.isEmpty, hashes.count <= 6 {
            let after = rest.dropFirst(hashes.count)
            // `#태그` 는 제목이 아니다 — 마커 뒤에 빈칸이 있어야 한다 (CommonMark).
            if after.isEmpty || after.first == " " {
                rest = after
                while rest.last == "#" { rest = rest.dropLast() }
            }
        }
        let text = rest.trimmingCharacters(in: .whitespaces)
        return text.isEmpty ? nil : text
    }

    /// **첫 줄의 글을 바꾼 것** (54 의 반대 방향 — 파일명을 바꾸면 첫 줄이 따라간다).
    /// 첫 줄이 `# ` 로 시작했으면 **그 마커를 그대로 두고** 글자만 바꾼다.
    /// 쓸 줄이 없으면(빈 노트) `nil` — 없는 줄을 만들지는 않는다.
    public static func replacingFirstLine(in text: String, with title: String) -> String? {
        let header = headerLength(of: text)
        let utf16 = Array(text.utf16)
        var head = String(decoding: utf16[0..<header], as: UTF16.self)
        var rest = String(decoding: utf16[header...], as: UTF16.self)
        // 머리말 뒤 첫 줄바꿈까지가 머리말이다 (headerLength 는 닫는 울타리까지만 센다).
        if !head.isEmpty, rest.hasPrefix("\n") { head += "\n"; rest.removeFirst() }
        var lines = rest.components(separatedBy: "\n")
        guard let index = lines.firstIndex(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty })
        else { return nil }

        let old = lines[index]
        let indent = old.prefix { $0 == " " || $0 == "\t" }
        let marker = old.dropFirst(indent.count).prefix { $0 == "#" }
        let keepsMarker = !marker.isEmpty && marker.count <= 6
            && (old.dropFirst(indent.count + marker.count).first.map { $0 == " " } ?? true)
        lines[index] = keepsMarker ? "\(indent)\(marker) \(title)" : "\(indent)\(title)"
        return head + lines.joined(separator: "\n")
    }

    /// 목록에 보여 줄 제목. 머리말 → 첫 `# 제목` → 파일명 순으로 고른다.
    public static func title(of text: String, fileName: String) -> String {
        let parsed = parse(text)
        if let fromMatter = parsed.frontMatter?.title, !fromMatter.isEmpty {
            return fromMatter
        }
        // **첫 줄이 곧 제목이다** (T6). `#` 이 있으면 떼고, 없으면 그대로.
        if let first = firstLine(of: text) { return first }
        // 확장자를 뗀 파일명.
        let name = Paths.normalized(fileName)
        if let dot = name.lastIndex(of: "."), dot != name.startIndex {
            return String(name[name.startIndex..<dot])
        }
        return name
    }

    // MARK: - 속

    /// 줄에서 `\r` 과 공백을 걷어낸 것. 울타리 판정에만 쓴다.
    private static func fence(_ line: String) -> String {
        line.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// **아주 작은 YAML 만 읽는다.** 설계서 §5.1 에 적힌 세 칸(`title` · `tags` ·
    /// `created`)이 전부다. 완전한 YAML 파서를 쓰지 않는 이유는 외부 의존 하나가
    /// 심사 · 빌드 · 리눅스 테스트를 다 끌고 오기 때문이다.
    ///
    /// 읽는 꼴:
    /// ```yaml
    /// title: 앱 구상
    /// tags: [앱, 기획]
    /// created: 2026-09-13
    /// ```
    /// 와 블록 목록:
    /// ```yaml
    /// tags:
    ///   - 앱
    ///   - 기획
    /// ```
    static func parseYAML(_ yaml: String) -> FrontMatter {
        var matter = FrontMatter()
        var collectingTags = false

        for rawLine in yaml.components(separatedBy: "\n") {
            let line = rawLine.replacingOccurrences(of: "\r", with: "")
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }

            // 블록 목록의 항목.
            if collectingTags, trimmed.hasPrefix("- ") || trimmed == "-" {
                let item = unquote(String(trimmed.dropFirst(1)).trimmingCharacters(in: .whitespaces))
                if !item.isEmpty { matter.tags.append(item) }
                continue
            }

            // 들여쓰기가 있는 줄은 우리가 읽는 세 칸이 아니다.
            if line.first == " " || line.first == "\t" { continue }
            collectingTags = false

            guard let colon = trimmed.firstIndex(of: ":") else { continue }
            let key = String(trimmed[trimmed.startIndex..<colon]).trimmingCharacters(in: .whitespaces).lowercased()
            let value = String(trimmed[trimmed.index(after: colon)...]).trimmingCharacters(in: .whitespaces)

            switch key {
            case "title":
                let t = unquote(value)
                if !t.isEmpty { matter.title = t }
            case "created", "date":
                let c = unquote(value)
                if !c.isEmpty { matter.created = c }
            case "tags":
                if value.isEmpty {
                    collectingTags = true
                } else if value.hasPrefix("["), value.hasSuffix("]") {
                    let inner = String(value.dropFirst().dropLast())
                    matter.tags = inner
                        .split(separator: ",")
                        .map { unquote(String($0).trimmingCharacters(in: .whitespaces)) }
                        .filter { !$0.isEmpty }
                } else {
                    // `tags: 앱 기획` — 공백으로 나눈다.
                    matter.tags = value.split(separator: " ").map { unquote(String($0)) }.filter { !$0.isEmpty }
                }
            default:
                continue
            }
        }
        return matter
    }

    private static func unquote(_ raw: String) -> String {
        var text = raw
        if text.count >= 2 {
            let first = text.first!
            let last = text.last!
            if (first == "\"" && last == "\"") || (first == "'" && last == "'") {
                text = String(text.dropFirst().dropLast())
            }
        }
        return Paths.normalized(text.trimmingCharacters(in: .whitespaces))
    }
}
