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
