import Foundation

/// **줄 하나만 봐서는 모르는 것** (198) — 위아래 줄을 함께 봐야 정해지는 모습.
///
/// 편집기는 줄마다 칠한다(`LineStyler`, ADR-0005). 그런데 마크다운에는 **앞 줄이 무엇이냐**에 따라 뜻이 바뀌는
/// 줄이 있다. 읽기 화면(cmark-gfm)은 문서 전체를 보므로 둘이 갈렸다 (사용자 · 2026-10-01 캡처 — 읽기에서는 제목,
/// 쓰기에서는 보통 글):
///
/// | 글 | 줄마다 보면 | 실제 (CommonMark) |
/// |---|---|---|
/// | `가나다` 바로 밑 `---` | 보통 글 + 수평선 | **`가나다` 가 제목 2**, `---` 는 밑줄 |
/// | `가나다` 바로 밑 `===` | 보통 글 둘 | **제목 1** |
/// | `가나다` 바로 밑 `2. 나` | 번호 목록 | **같은 문단** — 1 이 아닌 번호는 글을 끊고 목록을 못 연다 |
/// | `가나다` 바로 밑 `    나` (네 칸) | 코드 | **같은 문단** — 코드는 글을 못 끊는다 |
///
/// 여기서는 **줄마다 역할만** 정한다. 칠하기는 편집기가 이 역할을 보고 한다. 울타리(```) 안의 줄은 **코드** 역할이다 —
/// 줄 하나만 보면 `# 주석` 이 제목, `- 항목` 이 목록처럼 칠해졌다 (200). 읽기 화면은 코드로 그린다.
/// 목록 · 인용 바로 밑의 글줄은 그 항목에 딸린 줄(게으른 이음)이라 문단을 새로 열지 않는다.
///
/// **파이썬 `context_roles` 와 같은 셈이다** (`Tools/golden`, `contextCases`) — 파이썬은 그 답을 cmark-gfm 이 그린
/// HTML 에 대어 보고 온다.
public enum BlockContext {

    public enum Role: String, Equatable, Sendable {
        /// 줄 혼자 본 모습 그대로.
        case normal
        /// 밑줄(`===` · `---`)이 받친 글줄 — 제목.
        case heading1, heading2
        /// 제목을 받치는 밑줄 줄. 읽기 화면에는 안 보인다.
        case underline
        /// 앞 문단에 이어지는 줄 — 목록 · 코드처럼 보여도 **보통 글**이다.
        case continuation
        /// 코드 울타리(```` ``` ````) **안**의 줄 (200) — `# 주석` · `- 항목` 도 글자 그대로. 울타리 줄 자신은 아니다.
        case code
        /// **네 칸 들여쓴 코드** (빌드 78 사용자 화면) — 빈 줄 · 제목 · 울타리 뒤의 네 칸 줄이 **열린 목록 항목 안이 아니면** 코드다
        /// (읽기 화면은 회색 덩어리로 그렸는데 쓰기 화면은 상자가 없었다). 목록 항목 안이면 그 항목의 글이고, 항목 글 칸에서
        /// 네 칸 더 들어가야 항목 안의 코드다. `code` 와 따로 둔다 — 엔터가 목록을 잇는 판정(`continuesText`)은 울타리 안만 본다.
        case indentedCode
    }

    /// `lines` 는 **머리말 뒤** 의 줄들 (줄바꿈 없이). 첫 줄 위는 빈 줄로 본다.
    /// `insideFence` — 첫 줄이 이미 코드 울타리 안인가 (위쪽 울타리 줄 수가 홀수).
    public static func roles(of lines: [String], insideFence: Bool = false) -> [Role] {
        var roles = Array(repeating: Role.normal, count: lines.count)
        var paragraph: Int? = nil       // 열린 문단의 첫 줄
        var inFence = insideFence
        var container = false           // 바로 위가 목록 · 인용 — 글줄은 거기 딸린다
        var list: Int? = nil            // 열린 목록 항목의 글이 시작하는 칸 — 빈 줄을 건너서도 산다
        var afterBlank = true           // 첫 줄 위는 빈 줄로 본다

        for (index, line) in lines.enumerated() {
            let kind = kind(of: line)
            if inFence {
                if kind == .fence { inFence = false } else { roles[index] = .code }
                continue
            }
            if kind == .blank {
                paragraph = nil
                container = false
                afterBlank = true
                continue
            }
            let width = leadingWidth(line)
            // 목록 글에 빈칸 없이 붙어 오는 글줄(게으른 이음)은 덜 들여써도 그 항목에 남는다.
            let lazy = !afterBlank && kind == .plain && (paragraph != nil || container)
            defer {
                // 열린 목록 — 항목 줄이면 그 글 칸으로, 항목 글 칸보다 덜 들여쓴 줄이 오면 목록 밖이다.
                let itemKind = kind == .container || kind == .weakItem || kind == .indented
                if itemKind, roles[index] != .indentedCode, roles[index] != .continuation, let content = itemContent(line) {
                    list = content
                } else if roles[index] != .indentedCode, let open = list, width < open, !lazy {
                    list = nil
                }
                afterBlank = false
            }
            // **치는 중일 수 있는 줄은 목록을 시작하는 줄로 본다** (빌드 69 · 9번). 표준은 글 바로 밑의 `-` · 빈 `- ` 를
            // 제목 밑줄로 읽지만, 그렇게 칠하면 글 밑에서 목록을 시작하는 순간 윗글이 제목으로 커진다.
            if isTentative(line) {
                paragraph = nil
                container = true
                continue
            }
            if let start = paragraph {
                if let level = underlineLevel(line) {
                    for row in start..<index { roles[row] = level == 1 ? .heading1 : .heading2 }
                    roles[index] = .underline
                    paragraph = nil
                    continue
                }
                switch kind {
                case .plain:
                    continue
                case .weakItem, .indented:
                    roles[index] = .continuation
                    continue
                default:
                    paragraph = nil     // 글을 끊는 줄 — 아래에서 새로 본다
                }
            }
            switch kind {
            case .fence:
                inFence = true
                container = false
            case .plain:
                if !container { paragraph = index }
            case .container, .weakItem:
                container = true
            case .indented:
                // 목록 · 인용 바로 밑이면 그 항목의 줄이다 — 어느 쪽도 문단이 아니다.
                // 빈 줄 · 제목 · 울타리 뒤라면 열린 목록 항목 안인지 본다 (`indentedCode`).
                if !container {
                    if let open = list, width >= open {
                        if width >= open + 4 { roles[index] = .indentedCode }
                    } else {
                        roles[index] = .indentedCode
                    }
                }
            case .other:
                container = false
            case .blank:
                break
            }
        }
        return roles
    }

    /// 줄 앞 빈칸의 폭 (탭은 넷).
    static func leadingWidth(_ line: String) -> Int {
        var width = 0
        for scalar in line.unicodeScalars {
            if scalar == " " { width += 1 } else if scalar == "\t" { width += 4 } else { break }
        }
        return width
    }

    /// 목록 항목 줄이면 **글이 시작하는 칸** (앞 빈칸 · 기호 · 뒤 빈칸 한~넷). 기호 뒤 빈칸이 다섯 이상이면 하나로 본다 (표준).
    /// 인용(`>`)은 목록이 아니다 — 빈 줄에서 끝난다.
    static func itemContent(_ line: String) -> Int? {
        let scalars = Array(line.unicodeScalars)
        var index = 0
        var width = 0
        while index < scalars.count, scalars[index] == " " || scalars[index] == "\t" {
            width += scalars[index] == "\t" ? 4 : 1
            index += 1
        }
        var marker = 0
        if index < scalars.count, scalars[index] == "-" || scalars[index] == "*" || scalars[index] == "+" {
            marker = 1
        } else {
            while index + marker < scalars.count, marker < 9,
                  (48...57).contains(scalars[index + marker].value) { marker += 1 }
            guard marker > 0, index + marker < scalars.count,
                  scalars[index + marker] == "." || scalars[index + marker] == ")" else { return nil }
            marker += 1
        }
        var after = index + marker
        guard after == scalars.count || scalars[after] == " " || scalars[after] == "\t" else { return nil }
        var spaces = 0
        while after < scalars.count, scalars[after] == " " { spaces += 1; after += 1 }
        if after == scalars.count || spaces > 4 { spaces = 1 }
        return width + marker + spaces
    }

    /// **치는 중일 수 있는 줄** — 빈 항목(`- ` · `1. `) · 짧은 밑줄(`-` · `--`).
    ///
    /// 표준대로면 글 바로 밑의 `-` 하나 · 빈 `- ` 도 제목 밑줄이라, 글 밑에서 목록을 시작하면 `-` 를 치는 순간 윗줄이 제목으로
    /// 커진다 — 목록 단추가 넣는 `- ` 도 같다. 빌드 69 에서는 *커서가 그 줄에 있는 동안만* 미뤘는데, 그러면 커서를 옮길 때마다
    /// 윗줄이 커졌다 작아졌고 숨은 `-` 위에서 치게 됐다 (사용자 · 화면 녹화). 이제 **커서와 상관없이** 이런 줄은 목록을 시작하는
    /// 줄로 본다(`roles`). **표준과 갈리는 자리는 이것 하나다** — 빈 `- ` 를 글 밑에 남겨 두면 읽기 화면에서는 윗글이 제목이다.
    public static func isTentative(_ line: String) -> Bool {
        if kind(of: line) == .weakItem {
            let rest = line.drop { $0 == " " || $0 == "\t" }
            let marker = rest.prefix { $0 != " " && $0 != "\t" }
            if rest.dropFirst(marker.count).allSatisfy({ $0 == " " || $0 == "\t" }) { return true }
        }
        guard underlineLevel(line) == 2 else { return false }
        return line.filter { $0 == "-" }.count < 3
    }

    /// 코드 울타리 줄인가 (```` ``` ```` · `~~~`, 앞 빈칸 셋까지). 편집기가 위쪽 울타리를 셀 때 쓴다.
    public static func isFence(_ line: String) -> Bool {
        kind(of: line) == .fence
    }

    enum Kind: Equatable {
        case blank
        case fence
        /// 보통 글줄 — 문단을 열거나 잇는다.
        case plain
        /// 글을 끊는 목록 · 인용 (`- 가` · `1. 가` · `> 가`).
        case container
        /// 목록처럼 보이지만 글을 못 끊는 것 — 1 이 아닌 번호 · 빈 항목.
        case weakItem
        /// 네 칸 이상 들여쓴 줄.
        case indented
        /// 제목 · 수평선 · 표 줄 — 글을 끊고, 아래 글줄을 거느리지 않는다.
        case other
    }

    static func kind(of line: String) -> Kind {
        let scalars = Array(line.unicodeScalars)
        var index = 0
        var width = 0
        while index < scalars.count, scalars[index] == " " || scalars[index] == "\t" {
            width += scalars[index] == "\t" ? 4 : 1
            index += 1
        }
        if index == scalars.count { return .blank }
        if width >= 4 { return .indented }
        let rest = String(String.UnicodeScalarView(scalars[index...]))

        if rest.hasPrefix("```") || rest.hasPrefix("~~~") { return .fence }
        if isThematicBreak(rest) { return .other }
        if rest.hasPrefix("|") { return .other }
        if rest.hasPrefix(">") { return .container }

        // 제목 — `#` 한~여섯 개 뒤에 빈칸이나 줄 끝.
        let hashes = rest.prefix { $0 == "#" }.count
        if (1...6).contains(hashes) {
            let after = rest.dropFirst(hashes)
            if after.isEmpty || after.first == " " || after.first == "\t" { return .other }
        }

        // 글머리표
        if let first = rest.first, first == "-" || first == "*" || first == "+" {
            let after = rest.dropFirst()
            if after.first == " " || after.first == "\t" {
                return after.trimmingCharacters(in: .whitespaces).isEmpty ? .weakItem : .container
            }
        }
        // 번호 — 아스키 숫자 아홉 자리까지.
        let digits = rest.prefix { $0.isASCII && $0.isNumber }
        if !digits.isEmpty, digits.count <= 9 {
            let after = rest.dropFirst(digits.count)
            if let mark = after.first, mark == "." || mark == ")" {
                let body = after.dropFirst()
                if body.first == " " || body.first == "\t" {
                    let empty = body.trimmingCharacters(in: .whitespaces).isEmpty
                    return Int(digits) == 1 && !empty ? .container : .weakItem
                }
            }
        }
        return .plain
    }

    /// 밑줄 줄인가 — 앞 빈칸 셋까지, `=` 만 또는 `-` 만, 뒤 빈칸은 된다. `=` 이면 1, `-` 이면 2.
    static func underlineLevel(_ line: String) -> Int? {
        var rest = Substring(line)
        var leading = 0
        while let first = rest.first, first == " ", leading < 4 {
            leading += 1
            rest = rest.dropFirst()
        }
        guard leading <= 3, let mark = rest.first, mark == "=" || mark == "-" else { return nil }
        let body = rest.prefix { $0 == mark }
        guard rest.dropFirst(body.count).allSatisfy({ $0 == " " || $0 == "\t" }) else { return nil }
        return mark == "=" ? 1 : 2
    }

    /// `---` · `***` · `___` · `- - -` — `LineStyler` 와 같은 판정.
    static func isThematicBreak(_ rest: String) -> Bool {
        let trimmed = rest.trimmingCharacters(in: .whitespaces)
        guard let first = trimmed.first, first == "-" || first == "*" || first == "_" else { return false }
        var count = 0
        for character in trimmed {
            if character == first { count += 1 }
            else if character != " " && character != "\t" { return false }
        }
        return count >= 3
    }
}
