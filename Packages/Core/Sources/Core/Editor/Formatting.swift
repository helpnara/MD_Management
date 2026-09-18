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
    /// 세 가지를 차례로 본다.
    /// 1. 고른 글이 **이미 표시를 물고 있나** (`**글**` 을 통째로 골랐다) → 벗긴다.
    /// 2. 고른 글 **바로 바깥**이 표시인가 (`**` `글` `**` 에서 가운데만 골랐다) → 벗긴다.
    /// 3. 아니면 감싼다. 고른 것이 없으면 표시만 넣고 **그 사이에 커서**를 둔다.
    ///
    /// **기울임과 굵게가 겹치는 자리**를 조심한다. `**글**` 에서 기울임을 누르면 별 하나를
    /// 벗기는 것이 아니라 `***글***` 이 되어야 한다 — 별이 **둘 이상 이어져 있으면**
    /// 기울임의 표시로 보지 않는다.
    public static func toggle(_ wrap: Wrap, in text: String, start: Int, length: Int) -> Edit {
        let units = Array(text.utf16)
        let marker = Array(wrap.rawValue.utf16)
        let width = marker.count
        let start = clamp(start, 0, units.count)
        let length = clamp(length, 0, units.count - start)
        let end = start + length

        // 1. 고른 글이 표시를 물고 있다.
        if length >= width * 2,
           matches(units, at: start, marker),
           matches(units, at: end - width, marker),
           !isRunOfMore(units, at: start, wrap),
           !isRunOfMoreBackwards(units, at: end - width, wrap) {
            let inner = string(units, start + width, end - width)
            return Edit(start: start, length: length, text: inner,
                        selectionStart: start, selectionLength: (inner as NSString).length)
        }
        // 2. 고른 글 바깥이 표시다.
        if start >= width, end + width <= units.count,
           matches(units, at: start - width, marker),
           matches(units, at: end, marker),
           !isRunOfMoreBackwards(units, at: start - width, wrap),
           !isRunOfMore(units, at: end, wrap) {
            let inner = string(units, start, end)
            return Edit(start: start - width, length: length + width * 2, text: inner,
                        selectionStart: start - width, selectionLength: length)
        }
        // 3. 감싼다. **가장자리의 빈칸은 물러난다** — `** 회**` 처럼 표시 안쪽이 빈칸으로
        // 시작하면 **마크다운이 아예 안 먹는다**(강조는 빈칸에 붙지 못한다). 워드에서 낱말을
        // 두 번 눌러 고르면 뒤 빈칸까지 딸려 오는 일이 흔하므로 이 자리는 자주 밟힌다.
        // (파이썬 대조가 잡아 줬다 — 우리 규칙이 만든 글을 파서에게 물어본 덕이다.)
        var from = start
        var to = end
        while from < to, isBlank(units[from]) { from += 1 }
        while to > from, isBlank(units[to - 1]) { to -= 1 }
        let inner = string(units, from, to)
        return Edit(start: from, length: to - from,
                    text: wrap.rawValue + inner + wrap.rawValue,
                    selectionStart: from + width, selectionLength: to - from)
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
            return line.trimmingCharacters(in: .whitespaces).isEmpty ? ">" : "> " + line
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

    private static func matches(_ units: [UInt16], at index: Int, _ marker: [UInt16]) -> Bool {
        guard index >= 0, index + marker.count <= units.count else { return false }
        for offset in 0..<marker.count where units[index + offset] != marker[offset] { return false }
        return true
    }

    /// 기울임(`*`)일 때만 뜻이 있다 — 그 자리에서 **별이 더 이어지나**.
    private static func isRunOfMore(_ units: [UInt16], at index: Int, _ wrap: Wrap) -> Bool {
        guard wrap == .italic else { return false }
        let star = Array("*".utf16)[0]
        guard index + 1 < units.count else { return false }
        return units[index + 1] == star
    }

    /// 앞쪽으로 별이 더 이어지나 (`index` 는 표시가 **끝나는** 자리).
    private static func isRunOfMoreBackwards(_ units: [UInt16], at index: Int, _ wrap: Wrap) -> Bool {
        guard wrap == .italic else { return false }
        let star = Array("*".utf16)[0]
        guard index - 1 >= 0 else { return false }
        return units[index - 1] == star
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
