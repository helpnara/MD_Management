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

    /// 목록에 보여 줄 제목. 머리말 → 첫 `# 제목` → 파일명 순으로 고른다.
    public static func title(of text: String, fileName: String) -> String {
        let parsed = parse(text)
        if let fromMatter = parsed.frontMatter?.title, !fromMatter.isEmpty {
            return fromMatter
        }
        for line in parsed.body.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("#") else { continue }
            let heading = trimmed.drop { $0 == "#" }.trimmingCharacters(in: .whitespaces)
            if !heading.isEmpty { return heading }
        }
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
