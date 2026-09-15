import Foundation

/// 라이브 편집기가 한 문단에 거는 모습 (ADR-0005 L1).
public enum StyleToken: String, Equatable, Sendable, CaseIterable {
    // ── 문단 전체 ──
    case heading1, heading2, heading3, heading4, heading5, heading6
    case quote
    case listItem
    case orderedItem
    case codeBlock
    case thematicBreak
    case tableRow

    // ── 문단 안쪽 ──
    case strong
    case emphasis
    case strikethrough
    case inlineCode
    case link
    case image

    /// 마크다운 마커(`#` `**` `-` `> ` …).
    /// **L1 은 흐리게, L2 는 숨긴다.** 문자열에서 지우지 않는다 (ADR-0005).
    case marker

    public static func heading(level: Int) -> StyleToken {
        switch max(1, min(6, level)) {
        case 1: return .heading1
        case 2: return .heading2
        case 3: return .heading3
        case 4: return .heading4
        case 5: return .heading5
        default: return .heading6
        }
    }
}

/// 문단 안의 한 구간. **UTF-16 오프셋**이다 — `NSTextStorage` 가 그 단위로 센다.
public struct StyleSpan: Equatable, Sendable {
    public let start: Int
    public let length: Int
    public let token: StyleToken

    public init(start: Int, length: Int, token: StyleToken) {
        self.start = start
        self.length = length
        self.token = token
    }

    public var end: Int { start + length }
}

/// 문단 하나를 어떻게 그릴지.
public struct ParagraphStyle: Equatable, Sendable {
    /// 문단 전체에 거는 것. `nil` 이면 보통 문단.
    public let block: StyleToken?
    /// 블록 마커가 끝나는 자리 (UTF-16). 제목이면 `## ` 다음.
    public let contentStart: Int
    /// 강조 · 코드 · 링크. **마커를 뺀 내용만** 덮는다.
    public let inlineSpans: [StyleSpan]
    /// 마크다운 마커들. 블록 마커와 인라인 마커가 다 들어 있다.
    public let markers: [StyleSpan]

    public init(block: StyleToken?, contentStart: Int, inlineSpans: [StyleSpan], markers: [StyleSpan]) {
        self.block = block
        self.contentStart = contentStart
        self.inlineSpans = inlineSpans
        self.markers = markers
    }

    public static let plain = ParagraphStyle(block: nil, contentStart: 0, inlineSpans: [], markers: [])
}

/// **문단 하나를 보고 어떻게 그릴지 정하는 순수 함수.**
///
/// 라이브 편집기(ADR-0005)의 심장이다. 리눅스 `swift test` 에서 검증되고,
/// 기댓값은 `Tools/golden` 이 `markdown-it-py` 로 따로 계산한다.
///
/// **문단 단위인 이유:** 재스타일은 편집된 문단 + 커서가 떠난 문단 + 커서가 온
/// 문단만 한다. 전체 재스타일은 파일을 열 때 한 번뿐이다 (안정화 기준 S11).
///
/// 여기서 하지 않는 것: 표 렌더 · 코드 블록 문법 강조 · 여러 문단에 걸친 구조.
/// 1.0 라이브에서 표와 코드는 고정폭 원문 그대로 둔다 (ADR-0005).
public enum LineStyler {

    public static func style(paragraph: String) -> ParagraphStyle {
        guard !paragraph.isEmpty else { return .plain }

        var markers: [StyleSpan] = []
        // **오프셋이 아니라 `String.Index` 를 받는다.** UTF-16 오프셋으로 되돌리면
        // 글자 가운데를 가리킬 수 있고, 되돌리는 코드가 곧 버그 자리가 된다.
        let (block, contentIndex) = blockPrefix(paragraph, markers: &markers)
        let inlineSpans = inlineScan(paragraph, from: contentIndex, to: paragraph.endIndex, markers: &markers)

        return ParagraphStyle(
            block: block,
            contentStart: utf16Offset(paragraph, contentIndex),
            inlineSpans: inlineSpans,
            markers: markers.sorted { $0.start < $1.start })
    }

    // MARK: - 블록 앞머리

    private static func blockPrefix(_ text: String, markers: inout [StyleSpan]) -> (StyleToken?, String.Index) {
        let trimmed = text.trimmingCharacters(in: .whitespaces)

        // 수평선 — 앞머리를 떼지 않고 문단 전체가 마커다.
        if isThematicBreak(trimmed) {
            markers.append(span(text, text.startIndex, text.endIndex, .marker))
            return (.thematicBreak, text.endIndex)
        }
        // 코드 울타리 · 표 줄 — 원문 그대로 둔다.
        if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
            return (.codeBlock, text.endIndex)
        }
        if trimmed.hasPrefix("|") {
            return (.tableRow, text.endIndex)
        }

        var cursor = text.startIndex
        var leading = 0
        while cursor < text.endIndex, text[cursor] == " " || text[cursor] == "\t" {
            leading += text[cursor] == "\t" ? 4 : 1
            cursor = text.index(after: cursor)
        }
        // 네 칸 이상 들여쓴 줄은 코드다.
        if leading >= 4 { return (.codeBlock, text.endIndex) }
        guard cursor < text.endIndex else { return (nil, cursor) }

        // 제목
        if text[cursor] == "#" {
            var hashes = cursor
            var level = 0
            while hashes < text.endIndex, text[hashes] == "#", level < 7 {
                level += 1
                hashes = text.index(after: hashes)
            }
            let followedBySpace = hashes == text.endIndex || text[hashes] == " "
            if level >= 1 && level <= 6 && followedBySpace {
                var after = hashes
                while after < text.endIndex, text[after] == " " { after = text.index(after: after) }
                markers.append(span(text, cursor, after, .marker))
                return (.heading(level: level), after)
            }
        }

        // 인용 — `> > ` 처럼 겹친 것도 한 번에 먹는다.
        if text[cursor] == ">" {
            var after = cursor
            while after < text.endIndex, text[after] == ">" {
                after = text.index(after: after)
                if after < text.endIndex, text[after] == " " { after = text.index(after: after) }
            }
            markers.append(span(text, cursor, after, .marker))
            return (.quote, after)
        }

        // 번호 목록
        if text[cursor].isNumber {
            var digits = cursor
            var count = 0
            while digits < text.endIndex, text[digits].isNumber, count < 9 {
                count += 1
                digits = text.index(after: digits)
            }
            if digits < text.endIndex, text[digits] == "." || text[digits] == ")" {
                let afterPunctuation = text.index(after: digits)
                if afterPunctuation < text.endIndex, text[afterPunctuation] == " " {
                    var after = afterPunctuation
                    while after < text.endIndex, text[after] == " " { after = text.index(after: after) }
                    markers.append(span(text, cursor, after, .marker))
                    let content = consumeCheckbox(text, from: after, markers: &markers)
                    return (.orderedItem, content)
                }
            }
        }

        // 글머리 목록
        if text[cursor] == "-" || text[cursor] == "*" || text[cursor] == "+" {
            let next = text.index(after: cursor)
            if next < text.endIndex, text[next] == " " {
                var after = next
                while after < text.endIndex, text[after] == " " { after = text.index(after: after) }
                markers.append(span(text, cursor, after, .marker))
                let content = consumeCheckbox(text, from: after, markers: &markers)
                return (.listItem, content)
            }
        }

        return (nil, cursor)
    }

    /// `[ ]` · `[x]` 를 마커로 먹는다. 작업 목록 항목의 체크박스다.
    private static func consumeCheckbox(_ text: String, from start: String.Index,
                                        markers: inout [StyleSpan]) -> String.Index {
        guard start < text.endIndex, text[start] == "[" else { return start }
        let mark = text.index(after: start)
        guard mark < text.endIndex else { return start }
        let inner = text[mark]
        guard inner == " " || inner == "x" || inner == "X" else { return start }
        let close = text.index(after: mark)
        guard close < text.endIndex, text[close] == "]" else { return start }

        var after = text.index(after: close)
        while after < text.endIndex, text[after] == " " { after = text.index(after: after) }
        markers.append(span(text, start, after, .marker))
        return after
    }

    private static func isThematicBreak(_ trimmed: String) -> Bool {
        guard let first = trimmed.first, first == "-" || first == "*" || first == "_" else { return false }
        var count = 0
        for character in trimmed {
            if character == first { count += 1 }
            else if character != " " { return false }
        }
        return count >= 3
    }

    // MARK: - 문단 안쪽

    /// `start ..< end` 를 훑어 강조 · 코드 · 링크를 찾는다.
    ///
    /// **겹친 것도 다 낸다.** `**굵고 *기운* 글**` 은 strong 과 emphasis 를 둘 다 낸다 —
    /// 편집기는 속성을 겹쳐 걸기 때문이다. 바깥 구간을 먼저, 안쪽 구간을 뒤에 낸다.
    /// (`Tools/golden` 의 markdown-it 도 여는 태그 순서로 준다.)
    private static func inlineScan(_ text: String, from start: String.Index, to end: String.Index,
                                   markers: inout [StyleSpan]) -> [StyleSpan] {
        var spans: [StyleSpan] = []
        var cursor = start

        while cursor < end {
            let character = text[cursor]

            // 이스케이프 — 다음 글자는 글자 그대로다.
            if character == "\\" {
                let next = text.index(after: cursor)
                cursor = next < end ? text.index(after: next) : end
                continue
            }

            if character == "`",
               let found = scanCode(text, at: cursor, to: end, markers: &markers) {
                spans.append(contentsOf: found.spans)
                cursor = found.next
                continue
            }
            if character == "!",
               let found = scanBracket(text, at: cursor, to: end, isImage: true, markers: &markers) {
                spans.append(contentsOf: found.spans)
                cursor = found.next
                continue
            }
            if character == "[",
               let found = scanBracket(text, at: cursor, to: end, isImage: false, markers: &markers) {
                spans.append(contentsOf: found.spans)
                cursor = found.next
                continue
            }
            if let found = scanEmphasis(text, at: cursor, to: end, markers: &markers) {
                spans.append(contentsOf: found.spans)
                cursor = found.next
                continue
            }

            cursor = text.index(after: cursor)
        }
        return spans
    }

    /// `` `코드` `` — 여는 백틱 개수와 같은 수로 닫힌다. 안쪽은 더 보지 않는다.
    private static func scanCode(_ text: String, at start: String.Index, to end: String.Index,
                                 markers: inout [StyleSpan]) -> (spans: [StyleSpan], next: String.Index)? {
        var open = start
        var fence = 0
        while open < end, text[open] == "`" {
            fence += 1
            open = text.index(after: open)
        }
        guard open < end else { return nil }

        var search = open
        while search < end {
            guard text[search] == "`" else {
                search = text.index(after: search)
                continue
            }
            var close = search
            var run = 0
            while close < end, text[close] == "`" {
                run += 1
                close = text.index(after: close)
            }
            if run == fence {
                markers.append(span(text, start, open, .marker))
                markers.append(span(text, search, close, .marker))
                return ([span(text, open, search, .inlineCode)], close)
            }
            search = close
        }
        return nil
    }

    /// `[글](주소)` 와 `![대체](주소)`.
    ///
    /// 링크 글자 안의 강조는 살린다. 그림의 대체 글자는 화면에 글로 안 보이므로 두지 않는다
    /// — markdown-it 도 `image` 토큰 하나로 준다.
    private static func scanBracket(_ text: String, at start: String.Index, to end: String.Index, isImage: Bool,
                                    markers: inout [StyleSpan]) -> (spans: [StyleSpan], next: String.Index)? {
        var open = start
        if isImage {
            open = text.index(after: start)
            guard open < end, text[open] == "[" else { return nil }
        }
        let inner = text.index(after: open)
        guard let close = findUnescaped("]", in: text, from: inner, to: end) else { return nil }

        let afterClose = text.index(after: close)
        guard afterClose < end, text[afterClose] == "(" else { return nil }
        let destination = text.index(after: afterClose)
        let paren: String.Index
        if destination < end, text[destination] == "<" {
            // **`<…>` 주소.** `>` 까지는 괄호가 들어 있어도 전부 주소다 — 빈칸 · 괄호가 든 파일명을
            // 이렇게 감싼다 (빌드 24 · 18번: 첫 `)` 에서 끊어 링크가 반 토막 났다). `>` 바로 뒤가 `)`.
            guard let gt = findUnescaped(">", in: text, from: text.index(after: destination), to: end),
                  text.index(after: gt) < end, text[text.index(after: gt)] == ")" else { return nil }
            paren = text.index(after: gt)
        } else {
            // 맨 주소: 짝을 이룬 괄호는 주소의 일부다 (CommonMark) — `[a](b(c).md)`.
            guard let balanced = findClosingParen(text, from: destination, to: end) else { return nil }
            paren = balanced
        }

        let finish = text.index(after: paren)
        markers.append(span(text, start, inner, .marker))   // `[` 또는 `![`
        markers.append(span(text, close, finish, .marker))  // `](주소)`

        var spans = [span(text, inner, close, isImage ? .image : .link)]
        if !isImage {
            spans.append(contentsOf: inlineScan(text, from: inner, to: close, markers: &markers))
        }
        return (spans, finish)
    }

    /// `**굵게**` · `*기울임*` · `~~취소~~` · `***굵고 기울임***`.
    private static func scanEmphasis(_ text: String, at start: String.Index, to end: String.Index,
                                     markers: inout [StyleSpan]) -> (spans: [StyleSpan], next: String.Index)? {
        let character = text[start]
        guard character == "*" || character == "_" || character == "~" else { return nil }

        // `_` 는 낱말 안에서 강조가 아니다 — `snake_case_name` 은 그냥 글자다 (CommonMark).
        if character == "_", start > text.startIndex, isWord(text[text.index(before: start)]) {
            return nil
        }

        var open = start
        var run = 0
        while open < end, text[open] == character {
            run += 1
            open = text.index(after: open)
        }
        // 여는 마커 뒤가 공백이면 강조가 아니다. `2 * 3 * 4` 가 기울지 않는 이유다.
        guard open < end, !text[open].isWhitespace else { return nil }

        // 한 번에 먹는 마커 수. `***글***` 은 기울임 하나만 먹고, 남은 `**글**` 은
        // 안쪽에서 굵게가 된다 — CommonMark 가 겹치는 방식 그대로다.
        let width: Int
        let token: StyleToken
        switch (character, run) {
        case ("~", 2): width = 2; token = .strikethrough
        case ("~", _): return nil
        case (_, 1): width = 1; token = .emphasis
        case (_, 2): width = 2; token = .strong
        default: width = 1; token = .emphasis
        }

        var search = open
        while search < end {
            guard text[search] == character else {
                if text[search] == "\\" {
                    let next = text.index(after: search)
                    search = next < end ? text.index(after: next) : end
                } else {
                    search = text.index(after: search)
                }
                continue
            }
            var close = search
            var closing = 0
            while close < end, text[close] == character {
                closing += 1
                close = text.index(after: close)
            }
            // 닫는 마커 앞이 공백이면 닫지 않는다.
            if closing >= width, !text[text.index(before: search)].isWhitespace {
                // 여닫는 마커 수가 같고 남는 게 있으면(`***글***`) 안쪽 겹을 먼저 짝지어야
                // 하므로 바깥은 **뒤쪽 끝**을 가져간다. 그 밖에는 앞쪽부터다 (`*글***`).
                let markerStart = (closing == run && run > width)
                    ? text.index(close, offsetBy: -width) : search
                let markerEnd = text.index(markerStart, offsetBy: width)
                // `_` 는 낱말 안에서 닫지도 않는다 — `_foo_bar` 는 그냥 글자다.
                let intraword = character == "_" && markerEnd < end && isWord(text[markerEnd])
                if !intraword {
                    let openEnd = text.index(start, offsetBy: width)
                    markers.append(span(text, start, openEnd, .marker))
                    markers.append(span(text, markerStart, markerEnd, .marker))
                    var spans = [span(text, openEnd, markerStart, token)]
                    spans.append(contentsOf: inlineScan(text, from: openEnd, to: markerStart, markers: &markers))
                    return (spans, markerEnd)
                }
            }
            search = close
        }
        return nil
    }

    private static func isWord(_ character: Character) -> Bool {
        character.isLetter || character.isNumber
    }

    /// 링크 주소의 닫는 `)` — 안의 `(` `)` 가 짝을 이루면 넘어간다. 이스케이프는 건너뛴다.
    private static func findClosingParen(_ text: String, from start: String.Index, to end: String.Index) -> String.Index? {
        var cursor = start
        var depth = 0
        while cursor < end {
            let ch = text[cursor]
            if ch == "\\" {
                let next = text.index(after: cursor)
                cursor = next < end ? text.index(after: next) : end
                continue
            }
            if ch == "(" { depth += 1 }
            else if ch == ")" {
                if depth == 0 { return cursor }
                depth -= 1
            }
            cursor = text.index(after: cursor)
        }
        return nil
    }

    private static func findUnescaped(_ target: Character, in text: String,
                                      from start: String.Index, to end: String.Index) -> String.Index? {
        var cursor = start
        while cursor < end {
            if text[cursor] == "\\" {
                let next = text.index(after: cursor)
                cursor = next < end ? text.index(after: next) : end
                continue
            }
            if text[cursor] == target { return cursor }
            cursor = text.index(after: cursor)
        }
        return nil
    }

    // MARK: - UTF-16 자

    private static func span(_ text: String, _ from: String.Index, _ to: String.Index,
                             _ token: StyleToken) -> StyleSpan {
        let start = utf16Offset(text, from)
        return StyleSpan(start: start, length: utf16Offset(text, to) - start, token: token)
    }

    static func utf16Offset(_ text: String, _ index: String.Index) -> Int {
        index.utf16Offset(in: text)
    }
}
