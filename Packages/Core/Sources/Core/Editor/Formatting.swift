import Foundation

/// **고른 글에 표시를 걸고 푼다** (T13 1차, 2026-09-18 사용자 — 워드의 도구 띠처럼).
///
/// 여기 있는 것은 **마크다운 표준 안쪽**뿐이다 — 굵게 · 기울임 · 취소선 · 인용 · 표.
/// 글자색 · 밑줄 · 형광펜은 마크다운에 없어서 넣지 않았다 (로드맵 T13 검토). 그것들을
/// 넣으면 **파일에 이 앱만 아는 글자를 심게 되고**, 그러면 ADR-0001(파일이 원본이다)을
/// 어긴다 — 옵시디언 · 깃허브로 옮겼을 때 그대로 드러난다.
///
/// 순수 함수다. 오프셋은 **UTF-16** (`NSTextStorage` 단위 — `ListEditing` 과 같다).
public enum Formatting {

    /// 고른 글을 **양옆에서 감싸는** 표시.
    public enum Wrap: String, Sendable, Equatable, CaseIterable {
        case bold = "**"
        case italic = "*"
        case strikethrough = "~~"
        /// 줄 안의 코드 (166). 역따옴표 하나씩 — 아이폰 자판에서 세 번 파고 들어가야
        /// 나오는 글자라 단추를 두었다 (2026-09-25 사용자 — *입력하는게 너무 불편해*).
        case code = "`"

        /// 한쪽에 몇 개를 두나.
        var width: Int { (self == .italic || self == .code) ? 1 : 2 }
    }

    /// 무엇을 어디로 바꾸고, 바꾼 뒤 어디를 고르고 있을 것인가.
    ///
    /// 편집기는 이 하나만 보고 `UITextView.replace(_:withText:)` 를 부른다 —
    /// **되돌리기(`⌘Z`)가 한 번에 되도록** 한 번의 바꾸기로 끝낸다.
    public struct Edit: Equatable, Sendable {
        /// 바꿀 구간 (UTF-16).
        public let start: Int
        public let length: Int
        /// 그 자리에 넣을 글.
        public let text: String
        /// 바꾼 뒤 선택 시작 · 길이. 길이가 0 이면 커서만 놓는다.
        public let selectionStart: Int
        public let selectionLength: Int

        public init(start: Int, length: Int, text: String,
                    selectionStart: Int, selectionLength: Int) {
            self.start = start
            self.length = length
            self.text = text
            self.selectionStart = selectionStart
            self.selectionLength = selectionLength
        }
    }

    // MARK: - 굵게 · 기울임 · 취소선

    /// **걸려 있으면 풀고, 없으면 건다.**
    ///
    /// **표시의 개수를 센다.** 고른 글 양옆에 같은 글자가 몇 개 이어져 있는지 보고 정한다 —
    /// 별 하나는 기울임, 둘은 굵게, 셋은 둘 다다(`***글***`). 그래서
    ///
    /// - 굵게는 **둘 이상**이면 걸려 있는 것 → 양쪽에서 **둘씩** 뺀다.
    /// - 기울임은 개수가 **홀수**면 걸려 있는 것 → 양쪽에서 **하나씩** 뺀다.
    /// - 없으면 그만큼 **더한다.**
    ///
    /// 이렇게 세면 `***글***` 에서 기울임만 풀어 `**글**` 이 되고, 다시 걸면 제자리로
    /// 돌아온다. **처음에는 껍질을 벗기는 식으로 짰다가 여기서 되돌아오지 않았다** —
    /// 파이썬 대조의 되돌아오기 시험이 잡았다.
    ///
    /// 고른 글이 **표시를 물고 있어도** 된다 (`**글**` 을 통째로 골랐을 때). 그 표시는
    /// 바깥 개수에 함께 센다.
    public static func toggle(_ wrap: Wrap, in text: String, start: Int, length: Int) -> Edit {
        let units = Array(text.utf16)
        let need = wrap.width
        let scan = scan(wrap, units, start: start, length: length)
        let (from, to, left, right, isOn) = (scan.from, scan.to, scan.left, scan.right, scan.isOn)

        let newLeft = max(0, isOn ? left - need : left + need)
        let newRight = max(0, isOn ? right - need : right + need)

        let inner = string(units, from, to)
        let one = String(wrap.rawValue.prefix(1))
        let piece = String(repeating: one, count: newLeft) + inner
            + String(repeating: one, count: newRight)
        let editStart = from - left
        let editLength = (to + right) - editStart
        return Edit(start: editStart, length: editLength, text: piece,
                    selectionStart: editStart + newLeft,
                    selectionLength: (inner as NSString).length)
    }

    /// **지금 무엇이 걸려 있나** (128, 사용자 — *선택이 되었는지 안 되었는지가 안 보인다*).
    ///
    /// 워드의 도구 띠처럼 **누르면 눌린 채로 보이게** 하려면 화면이 이것을 알아야 한다.
    /// 판정은 `toggle` 과 **같은 훑기**를 쓴다 — 두 길이 갈리면 *눌린 것처럼 보이는데
    /// 눌러도 안 풀리는* 자리가 생긴다.
    public struct Active: Equatable, Sendable {
        public var bold = false
        public var italic = false
        public var strikethrough = false
        public var quote = false
        /// 줄 안의 코드만 본다 — 울타리 안인지는 문단 하나로는 모른다 (166).
        public var code = false

        public init(bold: Bool = false, italic: Bool = false,
                    strikethrough: Bool = false, quote: Bool = false, code: Bool = false) {
            self.bold = bold
            self.italic = italic
            self.strikethrough = strikethrough
            self.quote = quote
            self.code = code
        }
    }

    public static func active(in text: String, start: Int, length: Int) -> Active {
        let units = Array(text.utf16)
        var active = Active()
        for wrap in Wrap.allCases {
            let isOn = scan(wrap, units, start: start, length: length).isOn
            switch wrap {
            case .bold: active.bold = isOn
            case .italic: active.italic = isOn
            case .strikethrough: active.strikethrough = isOn
            case .code: active.code = isOn
            }
        }
        // 인용은 줄 이야기다 — **커서가 선 줄**이 `>` 로 시작하나.
        let block = lineRange(units, start: start, length: length)
        let first = string(units, block.start, block.end).components(separatedBy: "\n").first ?? ""
        active.quote = first.drop(while: { $0 == " " || $0 == "\t" }).hasPrefix(">")
        return active
    }

    /// 고른 글의 양옆을 훑어 **표시가 몇 개나 이어져 있나**를 센다. `toggle` 과 `active` 가
    /// 이 하나를 같이 쓴다.
    private static func scan(_ wrap: Wrap, _ units: [UInt16],
                             start: Int,
                             length: Int) -> (from: Int, to: Int, left: Int, right: Int, isOn: Bool) {
        let mark = Array(wrap.rawValue.utf16)[0]
        let need = wrap.width
        var from = clamp(start, 0, units.count)
        var to = clamp(start + length, from, units.count)

        // 고른 글이 표시를 물고 있으면 안쪽으로 물러난다 — 바깥 개수에 함께 센다.
        while from < to, units[from] == mark { from += 1 }
        while to > from, units[to - 1] == mark { to -= 1 }
        // 걸 때는 가장자리 빈칸에서도 물러난다. `** 글**` 은 **마크다운이 아예 안 먹는다**
        // (강조는 빈칸에 붙지 못한다). 낱말을 두 번 눌러 고르면 뒤 빈칸이 흔히 딸려 온다.
        while from < to, isBlank(units[from]) { from += 1 }
        while to > from, isBlank(units[to - 1]) { to -= 1 }

        var left = 0
        while from - left - 1 >= 0, units[from - left - 1] == mark { left += 1 }
        var right = 0
        while to + right < units.count, units[to + right] == mark { right += 1 }

        let both = min(left, right)
        let isOn = wrap == .italic ? (both % 2 == 1) : (both >= need)
        return (from, to, left, right, isOn)
    }

    // MARK: - 코드 (166)

    /// **코드 단추 하나로 셋을 한다.** 고른 것이 한 줄 안이면 역따옴표로 감싸고, 여러 줄이면
    /// 울타리(```` ``` ````)로 감싸고, **빈 줄에 커서만 있으면** 울타리를 만들어 그 안에 커서를
    /// 둔다 — 아이폰에서 역따옴표 셋을 연달아 치는 것이 이 단추를 만든 까닭이다.
    ///
    /// 감싸는 쪽은 `toggle(.code…)` 과 같은 훑기라 걸었다 풀면 제자리로 돌아온다.
    /// 울타리도 **첫 줄과 끝 줄이 울타리면 푼다.**
    public static func toggleCode(in text: String, start: Int, length: Int) -> Edit {
        let units = Array(text.utf16)
        let newline = Array("\n".utf16)[0]
        let from = clamp(start, 0, units.count)
        let to = clamp(start + length, from, units.count)
        let spansLines = units[from..<to].contains(newline)
        let line = lineRange(units, start: start, length: 0)
        let lineIsBlank = string(units, line.start, line.end)
            .trimmingCharacters(in: .whitespaces).isEmpty

        // 빈 줄에 커서만 — 울타리를 세우고 가운데 줄에 커서를 둔다.
        if length == 0, lineIsBlank {
            let fence = "```\n\n```"
            return Edit(start: line.start, length: line.end - line.start, text: fence,
                        selectionStart: line.start + 4, selectionLength: 0)
        }
        guard spansLines else {
            return toggle(.code, in: text, start: start, length: length)
        }

        // 여러 줄 — 울타리로 감싸거나 푼다.
        let block = lineRange(units, start: start, length: length)
        var lines = string(units, block.start, block.end).components(separatedBy: "\n")
        let opens = lines.first.map { $0.trimmingCharacters(in: .whitespaces).hasPrefix("```") } ?? false
        let closes = lines.count >= 2
            && (lines.last.map { $0.trimmingCharacters(in: .whitespaces) == "```" } ?? false)
        if opens, closes {
            lines.removeFirst()
            lines.removeLast()
            let inner = lines.joined(separator: "\n")
            return Edit(start: block.start, length: block.end - block.start, text: inner,
                        selectionStart: block.start, selectionLength: (inner as NSString).length)
        }
        let body = string(units, block.start, block.end)
        let piece = "```\n" + body + "\n```"
        return Edit(start: block.start, length: block.end - block.start, text: piece,
                    selectionStart: block.start + 4, selectionLength: (body as NSString).length)
    }

    // MARK: - 인용

    /// **고른 줄들을 인용으로** (`> `). 이미 다 인용이면 푼다.
    ///
    /// 줄 단위 일이라 고른 구간을 **줄 끝까지 넓혀** 바꾼다. 빈 줄에는 `>` 만 붙인다 —
    /// `> ` 로 두면 눈에 안 보이는 빈칸이 파일에 남는다.
    public static func toggleQuote(in text: String, start: Int, length: Int) -> Edit {
        let units = Array(text.utf16)
        let block = lineRange(units, start: start, length: length)
        let lines = string(units, block.start, block.end).components(separatedBy: "\n")

        let meaningful = lines.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        let allQuoted = !meaningful.isEmpty && meaningful.allSatisfy { line in
            line.trimmingCharacters(in: .whitespaces).hasPrefix(">")
        }

        let changed: [String] = lines.map { line in
            if allQuoted { return unquote(line) }
            if line.trimmingCharacters(in: .whitespaces).isEmpty { return ">" }
            // **이미 인용인 줄에 또 걸지 않는다** — `> > 첫 줄` 은 인용 속 인용이다.
            return line.drop(while: { $0 == " " || $0 == "\t" }).hasPrefix(">") ? line : "> " + line
        }
        let joined = changed.joined(separator: "\n")
        return Edit(start: block.start, length: block.end - block.start, text: joined,
                    selectionStart: block.start, selectionLength: (joined as NSString).length)
    }

    // MARK: - 표

    /// **표를 넣는다** (GFM). 기본은 3×3 — 머리글 한 줄과 내용 두 줄이라 **보이는 줄이 셋**이다.
    ///
    /// 커서가 선 줄이 비어 있으면 그 자리에, 아니면 **그 줄 다음에** 넣는다. 표는 앞뒤로
    /// 빈 줄이 있어야 표로 읽히므로(GFM) 필요한 만큼 빈 줄을 함께 넣는다.
    /// 넣고 나서 **첫 칸의 글자를 골라 둔다** — 바로 쳐서 덮어쓸 수 있다.
    public static func table(in text: String, start: Int, rows: Int = 3, columns: Int = 3) -> Edit {
        let units = Array(text.utf16)
        let columns = max(1, columns)
        let bodyRows = max(1, rows - 1)
        let line = lineRange(units, start: start, length: 0)
        let current = string(units, line.start, line.end)
        let isEmptyLine = current.trimmingCharacters(in: .whitespaces).isEmpty

        let header = "| " + (1...columns).map { "제목 \($0)" }.joined(separator: " | ") + " |"
        let rule = "| " + Array(repeating: "---", count: columns).joined(separator: " | ") + " |"
        let body = Array(repeating: "|" + String(repeating: "  |", count: columns), count: bodyRows)
        let table = ([header, rule] + body).joined(separator: "\n")

        // 넣을 자리와 앞뒤 빈 줄.
        let insertAt = isEmptyLine ? line.start : line.end
        let before = isEmptyLine ? "" : "\n\n"
        let hasRoomAfter = insertAt >= units.count
        let after = hasRoomAfter ? "\n" : "\n\n"
        let piece = before + table + after

        // 첫 칸의 `제목 1` 을 골라 둔다.
        let lead = ((before + "| ") as NSString).length
        let first = ("제목 1" as NSString).length
        return Edit(start: insertAt, length: 0, text: piece,
                    selectionStart: insertAt + lead, selectionLength: first)
    }

    // MARK: - 자잘한 것

    private static func unquote(_ line: String) -> String {
        var rest = Substring(line)
        let leading = rest.prefix { $0 == " " || $0 == "\t" }
        rest = rest.dropFirst(leading.count)
        guard rest.hasPrefix(">") else { return line }
        rest = rest.dropFirst()
        if rest.hasPrefix(" ") { rest = rest.dropFirst() }
        return String(leading) + String(rest)
    }

    private static func isBlank(_ unit: UInt16) -> Bool {
        unit == 0x20 || unit == 0x09 || unit == 0x0A
    }




    private static func lineRange(_ units: [UInt16], start: Int, length: Int) -> (start: Int, end: Int) {
        let newline = Array("\n".utf16)[0]
        var from = clamp(start, 0, units.count)
        var to = clamp(start + length, from, units.count)
        while from > 0, units[from - 1] != newline { from -= 1 }
        while to < units.count, units[to] != newline { to += 1 }
        // 고른 것이 줄바꿈에서 끝났으면 그 줄까지만 본다.
        if to > from, length > 0, units[to - 1] == newline { to -= 1 }
        return (from, to)
    }

    private static func string(_ units: [UInt16], _ from: Int, _ to: Int) -> String {
        guard from < to, from >= 0, to <= units.count else { return "" }
        return String(decoding: units[from..<to], as: UTF16.self)
    }

    private static func clamp(_ value: Int, _ low: Int, _ high: Int) -> Int {
        min(max(value, low), max(low, high))
    }
}
