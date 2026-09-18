import Foundation

/// 목록 안에서 **줄바꿈을 눌렀을 때** 무엇을 할지 (아이폰 메모의 개요 입력처럼).
///
/// - 항목에 글이 있으면 → 다음 항목을 이어 준다 (번호는 +1, 체크박스는 빈 칸)
/// - 빈 항목이면 → 한 단계 위로 (겹친 것이면 들여쓰기 하나를 뺀다)
/// - 최상위 빈 항목이면 → 마커를 지워 보통 글이 된다
///
/// 순수 함수다. 오프셋은 **UTF-16** (`NSTextStorage` 단위).
public enum ListEditing {

    public enum Action: Equatable, Sendable {
        /// 커서 자리에 이 문자열을 넣는다 (`"\n- "` 같은 것).
        case insert(String)
        /// 문단 앞머리 `length` 만큼을 `with` 로 바꾼다. 커서는 그 끝으로.
        case replacePrefix(length: Int, with: String)
    }

    /// `paragraph` 는 줄바꿈을 뺀 한 문단. 목록이 아니면 `nil` — 보통 줄바꿈이다.
    public static func returnPressed(in paragraph: String) -> Action? {
        let style = LineStyler.style(paragraph: paragraph)
        guard style.block == .listItem || style.block == .orderedItem else { return nil }

        let utf16 = Array(paragraph.utf16)
        let prefix = String(decoding: utf16[0..<style.contentStart], as: UTF16.self)
        let isEmpty = style.contentStart >= utf16.count

        if isEmpty {
            // 겹친 항목이면 한 단계 위로, 아니면 마커를 지운다.
            let leading = prefix.prefix { $0 == " " || $0 == "\t" }
            if leading.count >= 2 {
                let outdented = String(prefix.dropFirst(min(2, leading.count)))
                return .replacePrefix(length: style.contentStart, with: outdented)
            }
            return .replacePrefix(length: style.contentStart, with: "")
        }
        return .insert("\n" + nextMarker(from: prefix))
    }

    // MARK: - 탭 · 시프트 탭 (빌드 29 · 1번)

    /// 들여쓰기 한 단계 = **빈칸 둘**. `returnPressed` 가 빈 항목에서 내어쓸 때 빼는 양과 같다.
    public static let step = "  "

    /// 바꾼 줄들과, **첫 줄 앞**이 얼마나 늘거나 줄었나 (UTF-16). 커서를 그만큼 옮긴다.
    public struct Shifted: Equatable, Sendable {
        public let text: String
        public let firstLineDelta: Int

        public init(text: String, firstLineDelta: Int) {
            self.text = text
            self.firstLineDelta = firstLineDelta
        }
    }

    /// **목록이 시작될 수 있는 가장 깊은 칸.** 넷이면 마크다운은 코드로 읽는다.
    public static let maxListStart = 3

    /// **탭** — 고른 줄들을 **부모의 글칸까지** 들여쓴다. 목록 줄이 하나도 없거나
    /// **이미 그만큼 들어가 있으면** `nil` 이다 (그때 편집기는 글 한복판이면 빈칸 둘을
    /// 넣고, 목록이면 아무 일도 하지 않는다).
    /// 빈 줄은 그대로 둔다 — 빈칸만 남은 줄이 생기면 문단이 끊긴다.
    ///
    /// **부모의 글칸에서 멈춘다 — 거기가 천장이다** (141, 사용자 · 빌드 42 —
    /// *여전히 올바르게 동작하지 않는다*). 139 에서는 `max(부모까지, 제 마커폭)` 이라
    /// **누를 때마다 마커폭만큼 더 깊어졌다.** 부모의 글칸보다 **네 칸**을 넘기는 순간
    /// 마크다운은 그 줄을 목록이 아니라 **앞 문단에 딸린 글**로 읽는다 — 화면에서는
    /// 멀쩡한데 파일이 무너지고, 읽기 모드에서 `공유 1. 테스트 2. 테스트` 한 줄이 된다.
    ///
    /// - `under`: 위로 올라가며 만난 **빈 줄이 아닌 첫 줄**. 그 줄이 목록이면 그 줄의
    ///   글이 시작하는 칸까지 들어간다 (`- ` 는 둘, `1. ` 은 셋, `10. ` 은 넷).
    ///   목록이 아니거나 없으면 겹칠 자리가 없으므로 **목록으로 남을 만큼만** 간다.
    public static func indent(_ block: String, under previous: String? = nil) -> Shifted? {
        let lines = block.components(separatedBy: "\n")
        guard let firstItem = lines.first(where: { isItem($0) }) else { return nil }

        let here = leadingWidth(firstItem)
        let target: Int
        if let previous, let column = contentColumn(previous) {
            target = column
        } else {
            target = min(here + step.count, maxListStart)
        }
        guard here < target else { return nil }   // **더 들어갈 자리가 없다**
        let pad = String(repeating: " ", count: target - here)

        var firstDelta = 0
        var shifted: [String] = []
        shifted.reserveCapacity(lines.count)
        for (index, line) in lines.enumerated() {
            if line.trimmingCharacters(in: .whitespaces).isEmpty {
                shifted.append(line)
                continue
            }
            if index == 0 { firstDelta = pad.utf16.count }
            shifted.append(pad + line)
        }
        return Shifted(text: shifted.joined(separator: "\n"), firstLineDelta: firstDelta)
    }

    /// **줄마다 몇 단계인가** — 마크다운이 세는 대로 (141).
    ///
    /// 편집기는 오래도록 **앞 빈칸 ÷ 2** 로 단계를 그렸다. 마크다운은 그렇게 세지 않는다 —
    /// 자식은 **부모의 글이 시작하는 칸**부터라야 겹친다. 잣대가 둘이라 화면과 파일이
    /// 갈렸고, 사용자는 *편집 모드는 맞는데 읽기 모드가 다르다* 를 두 번 겪었다.
    /// 이제 그리는 쪽도 읽는 쪽과 **같은 셈**을 쓴다.
    ///
    /// 목록이 아닌 줄은 0. 빈 줄은 목록을 끊지 않으므로 앞 단계를 이어 준다.
    public static func depths(in lines: [String]) -> [Int] {
        var columns: [Int] = []     // 지금 품고 있는 조상들의 **글칸**
        var out: [Int] = []
        out.reserveCapacity(lines.count)
        for line in lines {
            if line.trimmingCharacters(in: .whitespaces).isEmpty {
                out.append(columns.count)
                continue
            }
            guard isItem(line) else {
                columns.removeAll()
                out.append(0)
                continue
            }
            let width = leadingWidth(line)
            while let last = columns.last, last > width { columns.removeLast() }
            out.append(columns.count + 1)
            columns.append(contentColumn(line) ?? (width + step.count))
        }
        return out
    }

    /// **시프트 탭** — 한 단계 내어쓴다.
    ///
    /// - `to`: 블록보다 **얕은** 바로 위 목록 줄. 그 줄의 들여쓰기까지 나온다.
    ///   없으면 맨 앞까지(또는 뗄 수 있는 만큼).
    ///
    /// 뗄 것이 하나도 없으면 `nil` — 아무 일도 일어나지 않는다.
    public static func outdent(_ block: String, to shallower: String? = nil) -> Shifted? {
        let lines = block.components(separatedBy: "\n")
        let firstItem = lines.first(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty })
        let here = firstItem.map(leadingWidth) ?? 0
        let target = shallower.map(leadingWidth) ?? 0
        // 몇 칸을 뗄까 — 얕은 줄이 있으면 그 줄까지, 없으면 한 단계(빈칸 둘)만.
        let amount = here > target ? here - target : step.count

        var changed = false
        var firstDelta = 0
        var shifted: [String] = []
        for (index, line) in lines.enumerated() {
            var rest = line[...]
            var removed = 0
            if rest.hasPrefix("\t") {
                rest = rest.dropFirst()
                removed = 1
            } else {
                while removed < amount, rest.hasPrefix(" ") {
                    rest = rest.dropFirst()
                    removed += 1
                }
            }
            if removed > 0 {
                changed = true
                if index == 0 { firstDelta = -removed }
            }
            shifted.append(String(rest))
        }
        guard changed else { return nil }
        return Shifted(text: shifted.joined(separator: "\n"), firstLineDelta: firstDelta)
    }

    /// 줄 앞의 빈칸 너비 (탭은 네 칸).
    private static func leadingWidth(_ line: String) -> Int {
        line.prefix { $0 == " " || $0 == "\t" }.reduce(0) { $0 + ($1 == "\t" ? 4 : 1) }
    }

    /// 마커 너비 — `- ` 는 둘, `1. ` 은 셋, `10. ` 은 넷. 목록이 아니면 `nil`.
    ///
    /// **`LineStyler` 의 `contentStart` 를 쓰지 않는다.** 그쪽은 `- [ ] ` 의 체크박스까지
    /// 마커로 세는데(화면에 그리려고), 마크다운이 보는 **글이 시작하는 칸**은 `- ` 뒤다.
    /// 여섯 칸을 들여쓰면 부모의 글칸(둘)보다 네 칸이 더 들어가 **코드로 읽힌다** —
    /// 겹친 목록이 아니라.
    private static func markerWidth(_ line: String) -> Int? {
        let rest = line.drop { $0 == " " || $0 == "\t" }
        if rest.hasPrefix("- ") || rest.hasPrefix("* ") || rest.hasPrefix("+ ") { return 2 }
        let digits = rest.prefix { $0.isASCII && $0.isNumber }
        guard !digits.isEmpty else { return nil }
        let after = rest.dropFirst(digits.count)
        guard after.hasPrefix(". ") || after.hasPrefix(") ") else { return nil }
        return digits.count + 2
    }

    /// **글이 시작하는 칸** — 자식 항목은 여기까지 들어가야 겹친 것으로 읽힌다.
    private static func contentColumn(_ line: String) -> Int? {
        guard let width = markerWidth(line) else { return nil }
        return leadingWidth(line) + width
    }

    // MARK: - 번호 다시 매기기 (빌드 32 · 104)

    /// 고칠 자리 하나 — **블록 안에서의 UTF-16 오프셋**과 그 자리에 넣을 숫자.
    /// 줄 전체를 갈아 끼우지 않고 **숫자만** 바꾼다. 커서와 되돌리기가 덜 흔들린다.
    public struct Renumber: Equatable, Sendable {
        public let start: Int
        public let length: Int
        public let number: String

        public init(start: Int, length: Int, number: String) {
            self.start = start
            self.length = length
            self.number = number
        }
    }

    /// **번호 목록을 1 · 2 · 3 으로 다시 맞춘다** (사용자 요청 — 중간에 넣거나 지우면 어긋난다).
    ///
    /// - 첫 항목의 번호는 **그대로 둔다.** `5.` 로 시작하는 목록은 5 · 6 · 7 이다 (CommonMark).
    /// - 겹친 단계는 따로 센다. 앞 빈칸 수가 곧 단계다.
    /// - 빈 줄은 목록을 끊지 않는다 — 항목 사이에 빈 줄을 두는 사람이 많다.
    /// - 글줄(목록이 아닌 줄)이 나오면 그 단계부터 아래는 새 목록이다.
    /// - 같은 단계에 글머리표(`- `)가 끼면 번호 목록이 거기서 끊긴다.
    ///
    /// 고칠 것이 없으면 빈 배열. 돌려주는 자리는 **앞에서 뒤 순서**다 — 넣을 때는 **뒤에서부터**.
    public static func renumber(_ block: String) -> [Renumber] {
        var fixes: [Renumber] = []
        /// 단계(앞 빈칸 수)마다 다음에 올 번호.
        var next: [Int: Int] = [:]
        var offset = 0

        for line in block.components(separatedBy: "\n") {
            let length = line.utf16.count
            defer { offset += length + 1 }   // 줄바꿈 한 칸

            if line.trimmingCharacters(in: .whitespaces).isEmpty { continue }

            let indent = line.prefix { $0 == " " || $0 == "\t" }
            let depth = indent.reduce(0) { $0 + ($1 == "\t" ? 4 : 1) }
            let rest = line.dropFirst(indent.count)

            // 글머리표 — 이 단계의 번호 목록을 끊는다.
            if rest.hasPrefix("- ") || rest.hasPrefix("* ") || rest.hasPrefix("+ ") {
                next = next.filter { $0.key < depth }
                continue
            }

            // **아스키 숫자만** 센다 — 파이썬 심판과 한 글자도 어긋나지 않게.
            let digits = rest.prefix { $0.isASCII && $0.isNumber }
            let after = rest.dropFirst(digits.count)
            guard !digits.isEmpty, digits.count <= 9,
                  after.hasPrefix(". ") || after.hasPrefix(") "), let read = Int(digits) else {
                // 목록이 아닌 글줄 — 이 단계와 그 아래를 끊는다.
                next = next.filter { $0.key < depth }
                continue
            }

            // 더 깊은 단계는 여기서 끊긴다.
            next = next.filter { $0.key <= depth }
            // **겹친 단계의 첫 항목은 1 부터** (134, 사용자 — 둘째 줄을 들여썼더니 `2.` 로
            // 남았다). 맨 바깥 목록은 `5.` 로 시작할 수 있으므로(CommonMark) 그 번호를
            // 그대로 두지만, **들여써서 새로 생긴 단계**가 2 로 시작하는 것은 뜻이 없다.
            let wanted = next[depth] ?? (depth > 0 ? 1 : read)
            if wanted != read {
                fixes.append(Renumber(start: offset + indent.utf16.count,
                                      length: digits.utf16.count, number: String(wanted)))
            }
            next[depth] = wanted + 1
        }
        return fixes
    }

    /// 목록 줄인가 — 앞 빈칸을 뺀 뒤 `- ` · `* ` · `+ ` · `1. ` · `1) ` 로 시작하나.
    ///
    /// **`LineStyler` 를 쓰지 않는다.** 그쪽은 문단 하나만 보므로 네 칸 이상 들여쓴 줄을
    /// 코드로 읽는데, 겹친 목록은 두 단계만 내려가도 그보다 깊어진다.
    public static func isItem(_ line: String) -> Bool {
        var rest = line[...].drop { $0 == " " || $0 == "\t" }
        if rest.hasPrefix("- ") || rest.hasPrefix("* ") || rest.hasPrefix("+ ") { return true }
        let digits = rest.prefix { $0.isNumber }
        guard !digits.isEmpty, digits.count <= 9 else { return false }
        rest = rest.dropFirst(digits.count)
        return rest.hasPrefix(". ") || rest.hasPrefix(") ")
    }

    /// `1. ` → `2. ` · `- [x] ` → `- [ ] ` · 그 밖은 그대로.
    static func nextMarker(from prefix: String) -> String {
        var result = ""
        var index = prefix.startIndex

        // 앞 빈칸은 그대로
        while index < prefix.endIndex, prefix[index] == " " || prefix[index] == "\t" {
            result.append(prefix[index])
            index = prefix.index(after: index)
        }
        // 번호
        var digits = ""
        while index < prefix.endIndex, prefix[index].isNumber {
            digits.append(prefix[index])
            index = prefix.index(after: index)
        }
        if !digits.isEmpty, let number = Int(digits) {
            result += String(number + 1)
        }
        // 나머지 (`. ` · `) ` · `- ` · 체크박스)
        let rest = String(prefix[index...])
        result += rest
            .replacingOccurrences(of: "[x]", with: "[ ]")
            .replacingOccurrences(of: "[X]", with: "[ ]")
        return result
    }
}
