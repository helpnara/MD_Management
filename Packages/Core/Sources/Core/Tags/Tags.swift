import Foundation

/// **`#태그`** — 아이폰 메모 앱의 태그처럼 (T2, 사용자 요청).
///
/// 마크다운과 부딪히지 않는다. CommonMark 는 `#` 뒤에 **빈칸이 있어야** 제목으로 보므로
/// `#ABC` 는 제목이 아니라 그냥 글자다. 그러니 줄 첫머리든 문장 가운데든 태그로 칠해도
/// 제목과 헷갈릴 일이 없다.
///
/// **파일에 아무것도 더하지 않는다.** 앱은 `#ABC` 를 **보이는 모습**으로만 다룬다 —
/// 글자는 그대로고, 다른 앱에서 열어도 그냥 `#ABC` 다 (ADR-0001 · ADR-0005).
public enum Tags {

    /// 태그 한 자리. **UTF-16 오프셋** (`NSTextStorage` 단위).
    public struct Span: Equatable, Sendable {
        public let start: Int
        public let length: Int

        public init(start: Int, length: Int) {
            self.start = start
            self.length = length
        }
    }

    /// 태그에 쓸 수 있는 글자 — 글자 · 숫자 · `_` · `-` · `/`.
    /// `/` 는 겹친 태그(`#일/회의`)를 위한 것이다.
    static func isTagCharacter(_ character: Character) -> Bool {
        character.isLetter || character.isNumber
            || character == "_" || character == "-" || character == "/"
    }

    /// **글에서 `#태그` 를 다 찾는다.**
    ///
    /// 규칙 셋:
    /// 1. `#` 이 **줄 첫머리이거나 앞이 빈칸**이다 — `a#b` 는 태그가 아니다.
    /// 2. 바로 뒤에 태그 글자가 온다 — `# 제목`(빈칸) · `## 제목`(`#`) 은 태그가 아니다.
    /// 3. **숫자만인 것은 태그가 아니다** — `#1` 은 번호나 이슈 표기다.
    public static func scan(_ text: String) -> [Span] {
        var found: [Span] = []
        var index = text.startIndex
        var offset = 0

        while index < text.endIndex {
            let character = text[index]
            let width = String(character).utf16.count
            guard character == "#" else {
                offset += width
                index = text.index(after: index)
                continue
            }
            let atStart = index == text.startIndex
            let afterSpace = atStart || text[text.index(before: index)].isWhitespace
            guard afterSpace else {
                offset += width
                index = text.index(after: index)
                continue
            }

            var end = text.index(after: index)
            var length = 1
            var hasLetter = false
            while end < text.endIndex, isTagCharacter(text[end]) {
                if !text[end].isNumber { hasLetter = true }
                length += String(text[end]).utf16.count
                end = text.index(after: end)
            }
            if length > 1, hasLetter {
                found.append(Span(start: offset, length: length))
                offset += length
                index = end
                continue
            }
            offset += width
            index = text.index(after: index)
        }
        return found
    }
}
