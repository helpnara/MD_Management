import Foundation

/// **타이핑으로 다른 노트 연결하기** (147, 2026-09-18 사용자 — 아이폰 메모처럼).
///
/// `>>회의` 라고 치면 제목에 `회의` 가 든 노트를 찾아 목록으로 보여 주고, 고르면
/// 그 자리에 링크가 들어간다.
///
/// **파일에는 표준 마크다운 링크만 남는다.** `>>` 도 `[[회의록]]` 도 그대로 저장하지
/// 않는다 — 그런 글자는 옵시디언 말고는 아무 데서도 안 열린다. 방아쇠는 **목록을 부르는
/// 신호일 뿐**이고, 고르는 순간 `[제목](../폴더/노트.md)` 로 바뀐다 (ADR-0001).
///
/// 순수 함수다. 오프셋은 **UTF-16** (`NSTextStorage` 단위 — `Formatting` 과 같다).
public enum NoteLinking {

    /// 목록을 부르는 글자.
    ///
    /// `>>` 는 사용자가 쓰던 것(아이폰 메모)이고, `[[` 는 마크다운에서 아무 뜻이 없어
    /// **어디서든 안전**하다. 옵시디언을 쓰는 사람에게도 익숙하다.
    public enum Trigger: String, Sendable, Equatable, CaseIterable {
        case chevrons = ">>"
        case brackets = "[["
    }

    /// **찾는 말이 너무 길어지면 그만둔다.** 방아쇠를 친 걸 잊고 계속 쓰는 수가 있다.
    public static let maxQueryLength = 50

    /// 지금 커서 앞에 방아쇠가 있나, 있다면 무엇을 찾고 있나.
    public struct Query: Equatable, Sendable {
        /// 방아쇠가 시작하는 자리 (UTF-16).
        public let start: Int
        /// 방아쇠 + 그 뒤에 친 글자의 길이. 링크가 이만큼을 덮는다.
        public let length: Int
        /// 찾을 말. **빈칸도 그대로 넣는다** — 제목에 빈칸이 흔하다 (`9월 회의록`).
        public let text: String
        public let trigger: Trigger

        public init(start: Int, length: Int, text: String, trigger: Trigger) {
            self.start = start
            self.length = length
            self.text = text
            self.trigger = trigger
        }
    }

    /// **커서 앞을 훑어 방아쇠를 찾는다.** 없으면 `nil` — 목록을 닫으라는 뜻이다.
    ///
    /// 줄 하나 안에서만 본다. 그 줄에서 커서에 **가장 가까운** 방아쇠를 고른다.
    ///
    /// **`>>` 는 줄 맨 앞에서는 방아쇠가 아니다.** 마크다운에서 줄 앞의 `>` 는 인용이고
    /// `>>` 는 인용 속 인용이다 — 도구 띠의 인용 버튼이 만드는 바로 그 글자다. 줄 첫머리에서
    /// 링크를 걸고 싶으면 빈칸 하나를 치고 쓰면 된다. `[[` 는 그런 겹침이 없어 어디서든 된다.
    public static func query(in text: String, caret: Int) -> Query? {
        let units = Array(text.utf16)
        let caret = clamp(caret, 0, units.count)
        let newline = Array("\n".utf16)[0]

        var lineStart = caret
        while lineStart > 0, units[lineStart - 1] != newline { lineStart -= 1 }
        // 줄 앞 빈칸 뒤가 **줄의 첫머리**다 — 인용 마커가 서는 자리.
        var firstInk = lineStart
        while firstInk < caret, isBlank(units[firstInk]) { firstInk += 1 }

        var best: Query?
        for trigger in Trigger.allCases {
            let mark = Array(trigger.rawValue.utf16)
            var at = caret - mark.count
            while at >= lineStart {
                if matches(units, at: at, mark) {
                    let found = found(trigger, units, at: at, caret: caret, firstInk: firstInk)
                    if let found, best == nil || found.start > best!.start { best = found }
                    break                      // 커서에 가장 가까운 것 하나면 된다
                }
                at -= 1
            }
        }
        return best
    }

    /// 방아쇠 자리 하나를 살펴 `Query` 로 만든다. 쓸 수 없는 자리면 `nil`.
    private static func found(_ trigger: Trigger, _ units: [UInt16],
                              at start: Int, caret: Int, firstInk: Int) -> Query? {
        if trigger == .chevrons, start == firstInk { return nil }   // 줄 맨 앞은 인용이다
        let from = start + Array(trigger.rawValue.utf16).count
        guard from <= caret else { return nil }
        let text = String(decoding: units[from..<caret], as: UTF16.self)
        guard text.utf16.count <= maxQueryLength else { return nil }
        // 대괄호가 끼면 링크를 쓰다 만 것이다 — 방아쇠로 보지 않는다.
        guard !text.contains("[") , !text.contains("]") else { return nil }
        return Query(start: start, length: caret - start, text: text, trigger: trigger)
    }

    /// **고른 노트를 그 자리에 넣는다.** 방아쇠와 친 글자를 통째로 링크로 바꾼다.
    ///
    /// - `noteFolder`: 지금 노트가 든 폴더. 링크는 **여기서 보는 상대 경로**다.
    /// - `path`: 고른 노트의 금고 기준 경로.
    public static func link(to title: String, path: String, from noteFolder: String,
                            replacing query: Query) -> Formatting.Edit {
        link(to: title, path: path, from: noteFolder, start: query.start, length: query.length)
    }

    /// **방아쇠 없이 커서 자리에** (145 — 메뉴에서 고르는 길).
    ///
    /// 타이핑으로 부르면 `>>회의` 를 덮어쓰지만, 메뉴에서 고르면 **덮을 글자가 없다.**
    /// 145 가 먹통이던 까닭이 이것이었다 — 넣는 길이 방아쇠를 **요구**하고 있었다
    /// (사용자 · 빌드 46 — *파일을 선택해도 링크가 들어가지 않는다*).
    /// 고른 구간이 있으면 그 자리를 링크로 바꾼다.
    public static func link(to title: String, path: String, from noteFolder: String,
                            start: Int, length: Int, in text: String = "") -> Formatting.Edit {
        // **글 밖을 가리키면 끝으로 당긴다.** 시트를 닫고 오는 길이라 커서 값이 묵었을 수
        // 있다 — 묵은 값에 글자를 넣으려다 앱이 죽는 것이 가장 나쁘다.
        let units = (text as NSString).length
        let from = text.isEmpty ? max(start, 0) : clamp(start, 0, units)
        let span = text.isEmpty ? max(length, 0) : clamp(length, 0, units - from)
        let relative = Paths.relativeLink(from: noteFolder, to: path)
        let piece = markdownLink(label: title, path: relative)
        return Formatting.Edit(start: from, length: span, text: piece,
                               selectionStart: from + (piece as NSString).length,
                               selectionLength: 0)
    }

    /// **고른 글이 있으면 그것이 링크의 이름이 된다** (152, 빌드 47 · 4번에서 드러남).
    ///
    /// 워드 · 노션 · 옵시디언이 다 그렇다. 고른 글을 지우고 파일 이름을 넣으면
    /// **사람이 친 글자가 조용히 사라진다.**
    ///
    /// ```
    /// 이 문서는 [체크리스트] 입니다   ← `체크리스트` 를 골랐다
    /// 이 문서는 [체크리스트](<자료/목돈 배치.md>) 입니다
    /// ```
    ///
    /// 세 가지를 지킨다.
    /// - 고른 글의 **가장자리 빈칸은 링크 밖에** 둔다 — 안에 넣으면 보기 싫고 뜻도 없다.
    /// - **줄을 넘어 고른 것은 이름으로 쓰지 않는다.** 줄바꿈이 든 이름은 링크를 깨뜨린다.
    ///   그때는 **한 글자도 지우지 않고** 고른 자리 앞에 끼워 넣는다.
    /// - 고른 것이 빈칸뿐이면 파일 이름을 쓴다.
    public static func link(to title: String, path: String, from noteFolder: String,
                            wrapping start: Int, length: Int, in text: String) -> Formatting.Edit {
        let units = Array(text.utf16)
        var from = clamp(start, 0, units.count)
        var to = clamp(start + max(length, 0), from, units.count)

        // 줄을 넘어 골랐다 — 지우지 않고 그 앞에 넣는다.
        let newline = Array("\n".utf16)[0]
        if units[from..<to].contains(newline) {
            return link(to: title, path: path, from: noteFolder, start: from, length: 0, in: text)
        }
        // 가장자리 빈칸은 링크 밖에 둔다.
        while from < to, isBlank(units[from]) { from += 1 }
        while to > from, isBlank(units[to - 1]) { to -= 1 }

        let picked = String(decoding: units[from..<to], as: UTF16.self)
        let label = picked.isEmpty ? title : picked
        return link(to: label, path: path, from: noteFolder,
                    start: from, length: to - from, in: text)
    }

    /// `[이름](경로)` — **빈칸이 있으면 꺾쇠로 감싼다.** CommonMark 는 빈칸 있는 주소를
    /// 링크로 안 읽는다. 첨부를 넣을 때와 **같은 규칙**을 쓴다 (`ImageImport` 가 이것을 부른다).
    public static func markdownLink(label: String, path: String) -> String {
        // **대괄호는 역슬래시로 피한다** (152). 예전에는 `]` 를 빈칸으로 바꿨는데, 그러면
        // 사람이 고른 글자가 **망가진다** — `[것]` 이 `[것 ` 이 됐다. 파이썬 대조가 잡았다.
        // 역슬래시로 피하면 두 파서 모두 `[것]` 을 그대로 보여 준다.
        var safeLabel = ""
        for character in label {
            if character == "[" || character == "]" || character == "\\" { safeLabel.append("\\") }
            safeLabel.append(character)
        }
        let needsBrackets = path.contains(" ")
        return "[" + safeLabel + "](" + (needsBrackets ? "<" + path + ">" : path) + ")"
    }

    // MARK: - 자잘한 것

    private static func matches(_ units: [UInt16], at index: Int, _ mark: [UInt16]) -> Bool {
        guard index >= 0, index + mark.count <= units.count else { return false }
        for offset in 0..<mark.count where units[index + offset] != mark[offset] { return false }
        return true
    }

    private static func isBlank(_ unit: UInt16) -> Bool { unit == 0x20 || unit == 0x09 }

    private static func clamp(_ value: Int, _ low: Int, _ high: Int) -> Int {
        min(max(value, low), max(low, high))
    }
}
