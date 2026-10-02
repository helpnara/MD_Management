import UIKit
import Core

/// 마크다운 원문에 **속성만** 건다 (ADR-0005 L1).
///
/// 글자는 하나도 지우거나 바꿔 넣지 않는다. 보이는 모습의 차이는 전부 속성이다.
/// 그래서 저장은 `textStorage.string` 을 그대로 쓰면 끝이고, 매핑 버그가 생길
/// 자리가 없다.
///
/// **`NSTextStorage` 를 상속하지 않는다.** 빌드 7 에서 직접 조립한 TextKit 2
/// 더미(`NSTextContentStorage` + `NSTextLayoutManager` + 커스텀 저장소)가 빈
/// 화면을 냈다 — 오류 하나 없이. 여기서는 컴파일해 볼 수 없는 조립이라 위험이
/// 크다. `UITextView(usingTextLayoutManager:)` 가 만들어 준 저장소에
/// **대리자로 붙는 쪽**이 훨씬 단순하고, `didProcessEditing` 은 속성을 바꾸라고
/// 애플이 정해 둔 바로 그 자리다.
enum MarkdownStyler {

    /// 고친 문단만 다시 칠한다. 전체 재칠은 파일을 열 때 한 번뿐이다 (S11).
    ///
    /// `previousHeader` 는 지난번 머리말 길이. **머리말이 생기거나 없어지거나 길이가
    /// 바뀌면 그 구간을 통째로 다시 칠한다.** `---` → `title:` → `---` 순으로 치면
    /// 마지막 `---` 를 친 순간에야 머리말이 생기는데, 고친 문단만 칠하면 위의
    /// `title:` 은 머리말 없던 시절 모습으로 남는다 (빌드 10 · 4번 "될 때도 안 될 때도").
    /// 새 머리말 길이를 돌려준다 — 부른 쪽이 들고 있다가 다음에 넘긴다.
    ///
    /// `cursor` 는 커서 자리 (UTF-16). 그 문단은 마커를 흐리게(L1), 나머지는 숨긴다(L2).
    /// `nil` 이면 다 흐리게(L1) — 커서를 모를 때(전체 다시 칠하기)만.
    /// 커서가 **어디에도 없다** 는 뜻의 자리 (편집이 끝났을 때 · 빌드 29 · 2번).
    /// 어떤 문단의 시작보다도 앞이라 모든 문단이 마커를 숨긴다 (L2).
    /// `cursor: nil` 과는 다르다 — 그쪽은 **커서를 모른다**는 뜻이라 다 드러낸다.
    static let noCursor = -1

    @discardableResult
    static func restyle(_ storage: NSTextStorage, touching range: NSRange,
                        with sheet: EditorStyleSheet, previousHeader: Int = 0,
                        cursor: Int? = nil) -> Int {
        let text = storage.string as NSString
        guard text.length > 0 else { return 0 }

        // 머리말은 문서 첫머리라는 문맥이 있어야 안다. 한 번 재어 두고 문단마다 가린다.
        let header = FrontMatterParser.headerLength(of: storage.string)
        var touched = text.paragraphRange(for: clamp(range, to: text.length))
        if header != previousHeader {
            let widest = min(max(header, previousHeader), text.length)
            let headerRange = text.paragraphRange(for: NSRange(location: 0, length: widest))
            touched = NSUnionRange(touched, headerRange)
        }
        // **첫 줄은 `#` 이 없어도 제목이다** (133, 사용자 — *그냥 써 놓으니 글자가 너무 작다*).
        // 이 앱에서 첫 줄은 **곧 파일명**이므로(107 · T6) 제목으로 보이는 편이 맞다.
        // 문단 하나만 보는 `LineStyler` 로는 알 수 없는 문맥이라 여기서 잰다.
        let titleStart = firstMeaningfulParagraph(in: text, after: header)
        // **목록은 덩이 전체를 다시 칠한다** (149, 사용자 · 빌드 44 — *엔터를 치며 내려가면
        // 아래 항목이 틀어진다*).
        //
        // 141 에서 단계를 **앞 줄들에 기대어** 세도록 바꿨다. 그러면 한 줄을 밀거나 당길 때
        // **그 아래 줄들의 단계가 다 바뀐다.** 그런데 다시 칠하는 범위는 고친 문단 언저리
        // 그대로였다 — 파일은 맞는데 화면만 옛 모습으로 남았다. 141 이전에는 단계가 줄
        // 하나로 정해져서(빈칸 ÷ 2) 그 자리만 칠하면 됐다. **잣대를 바꿨으면 칠하는 범위도
        // 바꿔야 했다.**
        if let run = listRun(in: text, covering: touched) {
            touched = NSUnionRange(touched, run)
        }
        // **줄 문맥** (198) — 밑줄(`---` · `===`)이 받친 글은 제목이고, 글 바로 밑의 `2. ` 는 목록이 아니다. 줄 하나로는
        // 모르는 일이라 **글 덩이**(빈 줄 사이)를 함께 본다. 다만 덩이 전체를 칠하지는 않는다 — 한 번 엔터로만 줄을 나눈
        // 노트는 덩이가 노트 전체라 글자마다 다 칠하게 된다 (S11). 칠하는 것은 **고친 줄 ± 한 줄**과 **역할이 있는 줄**이다.
        // `---` 를 치면 바로 윗줄이 제목이 되고, 지우면 윗줄이 돌아온다. (여러 줄짜리 밑줄 제목에서 `---` 를 지우면
        // 두 줄 위부터는 그 줄을 고칠 때 돌아온다 — 드문 모양이라 값을 아꼈다.)
        touched = NSUnionRange(touched, neighbors(in: text, around: touched))
        let roles = contextRoles(in: text, covering: textBlock(in: text, around: touched), header: header)
        // 문단마다 위로 훑으면 큰 노트에서 느려지므로 한 번에 재어 둔다.
        let depths = listDepths(in: text, covering: touched)
        let limit = NSMaxRange(touched)

        func paint(_ paragraph: NSRange) {
            if paragraph.location < header {
                storage.setAttributes(sheet.frontMatter(), range: paragraph)
                return
            }
            // 커서가 이 문단에 있나. 문단 끝(줄바꿈 앞)까지, 마지막 문단은 글 끝까지.
            let hasCursor = cursor.map { at in
                at >= paragraph.location
                    && (at < NSMaxRange(paragraph) || NSMaxRange(paragraph) == text.length)
            } ?? true
            style(paragraph: paragraph, in: text, storage: storage, sheet: sheet,
                  hasCursor: hasCursor, isTitle: paragraph.location == titleStart,
                  depth: depths[paragraph.location] ?? 0,
                  role: roles[paragraph.location] ?? .normal)
        }

        var location = touched.location
        repeat {
            let paragraph = text.paragraphRange(for: NSRange(location: min(location, text.length - 1), length: 0))
            paint(paragraph)
            let next = NSMaxRange(paragraph)
            // 문단이 앞으로 안 가면 멈춘다 — 무한 반복 막이.
            if next <= location { break }
            location = next
        } while location < limit && location < text.length
        // 고친 자리에서 먼 **역할 있는 줄** — 여러 줄짜리 밑줄 제목의 윗줄들 · 글에 이어지는 줄.
        for start in roles.keys.sorted() where start < touched.location || start >= limit {
            paint(text.paragraphRange(for: NSRange(location: start, length: 0)))
        }
        return header
    }

    @discardableResult
    static func restyleAll(_ storage: NSTextStorage, with sheet: EditorStyleSheet, cursor: Int? = nil) -> Int {
        restyle(storage, touching: NSRange(location: 0, length: storage.length), with: sheet, cursor: cursor)
    }

    private static func clamp(_ range: NSRange, to length: Int) -> NSRange {
        let location = max(0, min(range.location, max(0, length - 1)))
        return NSRange(location: location, length: min(range.length, length - location))
    }

    /// 머리말 뒤 **첫 글줄**의 자리. 빈 줄은 건너뛴다. 없으면 `nil`.
    private static func firstMeaningfulParagraph(in text: NSString, after header: Int) -> Int? {
        var location = min(header, max(0, text.length - 1))
        while location < text.length {
            let paragraph = text.paragraphRange(for: NSRange(location: location, length: 0))
            var line = paragraph
            if line.length > 0, text.character(at: NSMaxRange(line) - 1) == 0x0A { line.length -= 1 }
            if !text.substring(with: line).trimmingCharacters(in: .whitespaces).isEmpty {
                return paragraph.location
            }
            let next = NSMaxRange(paragraph)
            if next <= location { return nil }
            location = next
        }
        return nil
    }

    /// **목록 덩이의 단계를 미리 재어 둔다** (141).
    ///
    /// 마크다운은 자식이 **부모의 글칸**부터 시작해야 겹친 것으로 읽는다. 그 셈은 줄
    /// 하나만 봐서는 할 수 없고 덩이의 머리부터 쌓아 올라가야 한다. 규칙은 Core 의
    /// `ListEditing.depths` 가 정하고 여기서는 줄을 모아 건네기만 한다.
    ///
    /// 덩이의 머리는 위로 올라가다 **목록도 빈 줄도 아닌 줄**을 만나는 자리다 —
    /// 빈 줄은 목록을 끊지 않으므로 건너뛴다.
    /// **이 범위가 걸친 목록 덩이** (149). 목록이 아니면 `nil`.
    ///
    /// 위아래로 목록도 빈 줄도 아닌 줄을 만날 때까지 넓힌다 — 빈 줄은 목록을 끊지 않는다.
    static func listRun(in text: NSString, covering range: NSRange) -> NSRange? {
        guard text.length > 0 else { return nil }
        let head = min(max(range.location, 0), text.length - 1)
        var start = text.paragraphRange(for: NSRange(location: head, length: 0)).location
        var sawItem = false

        var at = start
        while at > 0 {
            let above = text.paragraphRange(for: NSRange(location: at - 1, length: 0))
            let line = lineText(text, above)
            if !line.trimmingCharacters(in: .whitespaces).isEmpty, !ListEditing.isItem(line) { break }
            if above.location == at { break }
            at = above.location
            start = at
        }

        var end = max(NSMaxRange(range), start + 1)
        end = min(end, text.length)
        while end < text.length {
            let next = text.paragraphRange(for: NSRange(location: end, length: 0))
            let line = lineText(text, next)
            if !line.trimmingCharacters(in: .whitespaces).isEmpty, !ListEditing.isItem(line) { break }
            if NSMaxRange(next) <= end { break }
            end = NSMaxRange(next)
        }

        // 덩이 안에 항목이 하나라도 있어야 목록이다.
        var scan = start
        while scan < end {
            let paragraph = text.paragraphRange(for: NSRange(location: scan, length: 0))
            if ListEditing.isItem(lineText(text, paragraph)) { sawItem = true; break }
            if NSMaxRange(paragraph) <= scan { break }
            scan = NSMaxRange(paragraph)
        }
        guard sawItem else { return nil }
        return NSRange(location: start, length: end - start)
    }

    /// **목록 덩이의 단계를 미리 재어 둔다** (141).
    ///
    /// 마크다운은 자식이 **부모의 글칸**부터 시작해야 겹친 것으로 읽는다. 그 셈은 줄
    /// 하나만 봐서는 할 수 없고 덩이의 머리부터 쌓아 올라가야 한다. 규칙은 Core 의
    /// `ListEditing.depths` 가 정하고 여기서는 줄을 모아 건네기만 한다.
    private static func listDepths(in text: NSString, covering range: NSRange) -> [Int: Int] {
        guard text.length > 0, let run = listRun(in: text, covering: range) else { return [:] }

        var starts: [Int] = []
        var lines: [String] = []
        var at = run.location
        let limit = NSMaxRange(run)
        while at < limit {
            let paragraph = text.paragraphRange(for: NSRange(location: at, length: 0))
            starts.append(paragraph.location)
            lines.append(lineText(text, paragraph))
            let next = NSMaxRange(paragraph)
            if next <= at { break }
            at = next
        }

        let counted = ListEditing.depths(in: lines)
        var map: [Int: Int] = [:]
        for (index, location) in starts.enumerated() where index < counted.count {
            map[location] = counted[index]
        }
        return map
    }

    /// 범위의 **한 줄 위 · 한 줄 아래**까지 (198). `---` 를 치거나 지우면 바로 윗줄의 모습이 바뀐다.
    private static func neighbors(in text: NSString, around range: NSRange) -> NSRange {
        guard text.length > 0 else { return range }
        var start = min(range.location, text.length - 1)
        if start > 0 { start = text.paragraphRange(for: NSRange(location: start - 1, length: 0)).location }
        var end = min(NSMaxRange(range), text.length)
        if end < text.length { end = NSMaxRange(text.paragraphRange(for: NSRange(location: end, length: 0))) }
        return NSRange(location: start, length: max(0, end - start))
    }

    /// **글 덩이** (198) — 범위의 한 줄 위 · 한 줄 아래부터 빈 줄을 만날 때까지 넓힌다. 한 줄씩 더 보는 까닭: 빈 줄을
    /// 끼우거나 지운 자리에서도 위아래 글이 다시 칠해져야 한다.
    private static func textBlock(in text: NSString, around range: NSRange) -> NSRange {
        guard text.length > 0 else { return range }
        var start = min(range.location, text.length - 1)
        if start > 0 { start = text.paragraphRange(for: NSRange(location: start - 1, length: 0)).location }
        while start > 0 {
            let above = text.paragraphRange(for: NSRange(location: start - 1, length: 0))
            if lineText(text, above).trimmingCharacters(in: .whitespaces).isEmpty || above.location >= start { break }
            start = above.location
        }
        var end = min(NSMaxRange(range), text.length)
        if end < text.length { end = NSMaxRange(text.paragraphRange(for: NSRange(location: end, length: 0))) }
        while end < text.length {
            let next = text.paragraphRange(for: NSRange(location: end, length: 0))
            if lineText(text, next).trimmingCharacters(in: .whitespaces).isEmpty || NSMaxRange(next) <= end { break }
            end = NSMaxRange(next)
        }
        return NSRange(location: start, length: max(0, end - start))
    }

    /// 범위 안 줄들의 역할 (198). 규칙은 Core 의 `BlockContext.roles` 가 정한다 — 여기서는 줄을 모아 건넨다.
    /// 머리말은 빼고, 위쪽에서 코드 울타리가 열려 있으면 그 안으로 본다.
    private static func contextRoles(in text: NSString, covering range: NSRange,
                                     header: Int) -> [Int: BlockContext.Role] {
        let begin = max(range.location, header)
        let limit = min(NSMaxRange(range), text.length)
        guard begin < limit else { return [:] }
        var starts: [Int] = []
        var lines: [String] = []
        var at = begin
        while at < limit {
            let paragraph = text.paragraphRange(for: NSRange(location: at, length: 0))
            starts.append(paragraph.location)
            lines.append(lineText(text, paragraph))
            let next = NSMaxRange(paragraph)
            if next <= at { break }
            at = next
        }
        let roles = BlockContext.roles(of: lines, insideFence: fenceIsOpen(in: text, from: header, to: begin))
        var map: [Int: BlockContext.Role] = [:]
        for (index, location) in starts.enumerated() where index < roles.count && roles[index] != .normal {
            map[location] = roles[index]
        }
        return map
    }

    /// `start ..< end` 사이에 코드 울타리 줄이 홀수 개면 `end` 는 울타리 안이다.
    private static func fenceIsOpen(in text: NSString, from start: Int, to end: Int) -> Bool {
        guard end > start,
              text.range(of: "```").location != NSNotFound || text.range(of: "~~~").location != NSNotFound else {
            return false
        }
        var open = false
        var at = start
        while at < end {
            let paragraph = text.paragraphRange(for: NSRange(location: at, length: 0))
            if BlockContext.isFence(lineText(text, paragraph)) { open.toggle() }
            let next = NSMaxRange(paragraph)
            if next <= at { break }
            at = next
        }
        return open
    }

    /// 문단 범위에서 **줄바꿈을 뺀** 글.
    private static func lineText(_ text: NSString, _ paragraph: NSRange) -> String {
        var line = paragraph
        if line.length > 0, text.character(at: NSMaxRange(line) - 1) == 0x0A { line.length -= 1 }
        return text.substring(with: line)
    }

    private static func style(paragraph: NSRange, in text: NSString,
                              storage: NSTextStorage, sheet: EditorStyleSheet,
                              hasCursor: Bool, isTitle: Bool = false, depth: Int = 0,
                              role: BlockContext.Role = .normal) {
        // `paragraphRange` 는 끝의 줄바꿈까지 준다. `LineStyler` 는 줄 하나만 본다.
        var line = paragraph
        if line.length > 0, text.character(at: NSMaxRange(line) - 1) == 0x0A {
            line.length -= 1
        }
        let lineString = text.substring(with: line)
        // 제목 글줄 · 이어지는 줄은 **보통 글로** 읽는다 (198) — `2. 나` 가 목록 마커를 갖지 않게.
        var style = LineStyler.style(paragraph: lineString, asText: role != .normal && role != .underline)
        if role == .underline {
            // 밑줄 줄은 **줄 전체가 마커**이고 **늘 흐리게** 보인다 — 수평선 줄과 같다. 커서가 없을 때 숨기면 커서가 그 줄에
            // 와도 다시 안 드러나 빈 줄 위에서 치게 됐다 (빌드 69 · 9번 녹화). 커서 따라 드러내는 장치(`MarkerFocus`)는
            // 줄 하나만 보고 마커가 있는 줄만 챙긴다 — `===` 는 줄 혼자로는 마커가 없다.
            let length = (lineString as NSString).length
            style = ParagraphStyle(block: .thematicBreak, contentStart: length, inlineSpans: [],
                                   markers: [StyleSpan(start: 0, length: length, token: .marker)])
        }

        // 목록: 겹친 단계는 **부른 쪽이 재어 준다** (141 — 마크다운과 같은 셈이라야
        // 화면과 파일이 안 갈린다). 매달린 들여쓰기는 **실제 폭**으로 — `- ` · `1. ` ·
        // `- [ ] ` 가 다 달라서 고정값이면 어긋난다 (빌드 8 · 10번).
        //
        // **줄 맨 앞부터 잰다** (155). 예전에는 마커(`2. `)부터 쟀는데, `LineStyler` 는
        // 줄 앞 빈칸을 **다 지나온 뒤에** 마커를 적는다. 그 빈칸은 화면에 글자로 그려지므로
        // 첫 줄은 그만큼 밀리고 접힌 줄은 안 밀려 **겹칠수록 벌어졌다** (사용자 · 2026-09-20).
        // `contentStart` 가 이미 맞는 자리를 들고 있었다 — 따로 더해 올라갈 까닭이 없었다.
        var contentInset: CGFloat = 0
        if style.block == .listItem || style.block == .orderedItem, style.contentStart > 0 {
            let prefix = text.substring(with: NSRange(location: line.location,
                                                      length: min(style.contentStart, line.length)))
            // 탭은 탭 자리로 그려져 글자처럼 못 잰다 — 빈칸 넷으로 펴서 잰다.
            let measured = LineStyler.expandingTabs(prefix)
            contentInset = (measured as NSString).size(withAttributes: [.font: sheet.body]).width
        }
        // 목록이 아닌 줄은 단계가 없다.
        let depth = (style.block == .listItem || style.block == .orderedItem) ? max(0, depth - 1) : 0
        // 첫 글줄이고 **아직 아무 블록도 아니면** 제목처럼 그린다 (133). 이미 `#` 이
        // 붙었거나 목록 · 인용이면 그 모습을 그대로 둔다 — 글은 한 글자도 안 바뀐다.
        let block: StyleToken?
        switch role {
        case .heading1: block = .heading(level: 1)
        case .heading2: block = .heading(level: 2)
        default: block = (isTitle && style.block == nil) ? StyleToken.heading(level: 1) : style.block
        }
        storage.setAttributes(sheet.base(for: block, depth: depth, contentInset: contentInset),
                              range: paragraph)

        for span in style.inlineSpans {
            let range = NSRange(location: line.location + span.start, length: span.length)
            guard NSMaxRange(range) <= NSMaxRange(line) else { continue }
            sheet.apply(span.token, to: storage, range: range)
        }
        // L2 — 커서가 없는 문단은 **읽기 모드에 가깝게** (163, 2026-09-25 사용자).
        // 규칙 하나: **숨길 수 있는 마커는 숨긴다. 숨길 수 없는 마커는 본문 색으로 둔다.
        // 회색은 커서 줄에서만.** 예전에는 *안 숨긴다* 와 *회색으로 칠한다* 가 한 갈래라
        // 커서 없는 줄의 번호까지 원문 줄처럼 회색이었다 — 읽기 모드와 어긋났다.
        //
        // 숨길 수 없는 것과 그 까닭:
        //  · 목록 마커(`- ` `1. ` `[ ]`) — 번호가 사라지면 정보가 사라진다 → **본문 색**,
        //    `[x]` 만 강조색 (읽기 모드의 켜진 체크상자처럼)
        //  · 표의 세로줄 `|` — 숨기면 칸이 어디서 나뉘는지 모른다 → **회색** (164)
        //  · 코드 울타리 · 수평선 — 줄 전체가 마커라 숨기면 줄이 사라진다 → **회색** (165)
        //  · 대체 글자 없는 그림(`![](…)`)이 있는 문단 — 줄이 통째로 사라진다 → 회색
        let isList = style.block == .listItem || style.block == .orderedItem
        let isTable = style.block == .tableRow
        let keepsAll = hasCursor || style.block == .thematicBreak || style.block == .codeBlock
            || style.inlineSpans.contains { $0.token == .image && $0.length == 0 }
        for mark in style.markers {
            let range = NSRange(location: line.location + mark.start, length: mark.length)
            guard NSMaxRange(range) <= NSMaxRange(line) else { continue }
            let isBlockMarker = mark.start < style.contentStart
            if keepsAll || isTable {
                sheet.dimMarker(in: storage, range: range)
            } else if isList && isBlockMarker {
                // 본문 색은 이미 문단 바탕에 깔려 있다 — 켜진 체크상자만 따로 칠한다.
                if text.substring(with: range).hasPrefix("[x") || text.substring(with: range).hasPrefix("[X") {
                    sheet.checkedMarker(in: storage, range: range)
                }
            } else {
                sheet.hideMarker(in: storage, range: range)
            }
        }
    }
}
