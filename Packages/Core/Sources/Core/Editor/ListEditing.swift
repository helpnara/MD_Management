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

    /// **탭** — 고른 줄들을 한 단계 들여쓴다. 목록 줄이 하나도 없으면 `nil` 이다
    /// (그때 편집기는 커서 자리에 빈칸 둘을 넣는다 — 글 한복판에서 탭이 먹통이 되지 않도록).
    /// 빈 줄은 그대로 둔다 — 빈칸만 남은 줄이 생기면 문단이 끊긴다.
    public static func indent(_ block: String) -> Shifted? {
        let lines = block.components(separatedBy: "\n")
        guard lines.contains(where: { isItem($0) }) else { return nil }
        var firstDelta = 0
        var shifted: [String] = []
        shifted.reserveCapacity(lines.count)
        for (index, line) in lines.enumerated() {
            if line.trimmingCharacters(in: .whitespaces).isEmpty {
                shifted.append(line)
                continue
            }
            if index == 0 { firstDelta = step.utf16.count }
            shifted.append(step + line)
        }
        return Shifted(text: shifted.joined(separator: "\n"), firstLineDelta: firstDelta)
    }

    /// **시프트 탭** — 한 단계 내어쓴다. 줄마다 앞의 탭 하나 또는 빈칸 둘까지를 뗀다.
    /// 뗄 것이 하나도 없으면 `nil` — 아무 일도 일어나지 않는다.
    public static func outdent(_ block: String) -> Shifted? {
        var changed = false
        var firstDelta = 0
        var shifted: [String] = []
        for (index, line) in block.components(separatedBy: "\n").enumerated() {
            var rest = line[...]
            var removed = 0
            if rest.hasPrefix("\t") {
                rest = rest.dropFirst()
                removed = 1
            } else {
                while removed < step.count, rest.hasPrefix(" ") {
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

    /// 목록 줄인가 — 앞 빈칸을 뺀 뒤 `- ` · `* ` · `+ ` · `1. ` · `1) ` 로 시작하나.
    ///
    /// **`LineStyler` 를 쓰지 않는다.** 그쪽은 문단 하나만 보므로 네 칸 이상 들여쓴 줄을
    /// 코드로 읽는데, 겹친 목록은 두 단계만 내려가도 그보다 깊어진다.
    static func isItem(_ line: String) -> Bool {
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
