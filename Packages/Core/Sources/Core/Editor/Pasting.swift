import Foundation

/// **밖에서 복사해 온 것을 붙일 때 그 자리에 맞게 고친다** (157 · 158 · 159).
///
/// 붙여넣기는 **앱이 본문을 고쳐도 되는 두 자리 중 하나**다 (ADR-0001 — 나머지는 노트
/// 옮기기). 그래서 세 가지를 지킨다.
///
/// - **되돌리기는 한 번에.** 부르는 쪽이 `replace(_:withText:)` 하나로 넣는다.
/// - **바꿨으면 알린다.** 사람이 모르게 본문이 달라지지 않는다.
/// - **모르면 안 건드린다.** 확실할 때만 고치고, 아니면 원문 그대로 붙인다.
///
/// 순수 함수다. 클립보드를 읽는 일은 앱이 하고, **무엇으로 바꿀지는 여기서** 정한다 —
/// 그래야 `Tools/golden/` 의 파이썬 대조가 심판이 된다 (`CLAUDE.md` §2).
public enum Pasting {

    // MARK: - 158 · 번호가 겹쳐 둘이 되는 것

    /// 마커의 갈래. **같은 갈래일 때만** 겹친 것으로 본다.
    public enum MarkerKind: String, Sendable, Equatable {
        case ordered   // `1. ` · `1) `
        case bullet    // `- ` · `* ` · `+ `
    }

    public struct Numbering: Equatable, Sendable {
        /// 고친 글.
        public let text: String
        /// 지운 마커 — 사람에게 알릴 말에 쓴다.
        public let removed: String

        public init(text: String, removed: String) {
            self.text = text
            self.removed = removed
        }
    }

    /// **이미 마커를 쳐 둔 줄에 목록을 붙이면 마커가 둘이 된다** (158, 2026-09-22 사용자
    /// — *앞에 번호가 이미 있다면 중복으로 2번 붙어서 매번 지워야 하는 불편함이 있음*).
    ///
    /// ```
    /// 1.          ← 여기에 커서
    /// 1. 첫째     ← 이것을 붙이면
    /// 1. 1. 첫째  ← 이렇게 된다
    /// ```
    ///
    /// - `lineBefore`: 커서가 선 줄에서 **커서 앞까지**의 글자.
    /// - **줄이 마커 하나로만 이루어져 있을 때만** 고친다. `1. 이미 쓴 글` 처럼 글이 있으면
    ///   붙는 자리가 글 뒤라서 겹치는 것이 아니다 — 손대지 않는다.
    /// - **같은 갈래일 때만** 고친다. `- ` 에 번호 목록을 붙이면 **둘 다 둔다** — 어느
    ///   쪽을 살릴지는 사람만 안다. *모르면 안 건드린다.*
    /// - 뒤따르는 줄에는 **커서 줄의 앞칸을 붙여** 준다. 안 그러면 둘째 줄부터 단계가
    ///   풀린다.
    public static func numbering(pasted: String, onLine lineBefore: String) -> Numbering? {
        guard let here = onlyMarker(lineBefore) else { return nil }
        var lines = pasted.components(separatedBy: "\n")
        guard let first = lines.first, let there = leadingMarker(first),
              there.kind == here.kind else { return nil }

        lines[0] = String(first.dropFirst(there.marker.count))
        // 뒤따르는 줄도 같은 단계에 서야 한다 — 커서 줄의 앞칸을 그대로 붙인다.
        if !here.leading.isEmpty {
            for index in 1..<max(lines.count, 1) where !lines[index].isEmpty {
                lines[index] = here.leading + lines[index]
            }
        }
        let text = lines.joined(separator: "\n")
        guard text != pasted else { return nil }
        return Numbering(text: text, removed: there.marker)
    }

    // MARK: - 157 · 웹 링크

    /// **주소를 붙이면 바로 링크가 되게** (157, 2026-09-22 사용자).
    ///
    /// - `name`: 클립보드가 같이 준 페이지 이름. **없으면 없는 대로 쓴다** —
    ///   이름을 받아오려고 통신을 넣지 않는다. 이 앱은 네트워크를 아예 쓰지 않는다고
    ///   애플에 신고했고(`project.yml`), 처리방침에도 **서버가 없습니다** 라고 적었다.
    /// - `selection`: 고른 글이 있으면 **그것이 링크 이름**이 된다 (152 와 같은 규칙).
    ///
    /// 이름이 없으면 `<주소>` 로 둔다 — CommonMark 의 자동 링크라 두 파서 모두
    /// 누를 수 있는 링크로 읽는다. 주소를 이름으로 **베껴 적지 않는다**: 같은 글이
    /// 두 번 보이면 읽기 싫고, 주소가 길면 줄이 무너진다.
    public static func webLink(url raw: String, name: String? = nil,
                               selection: String = "") -> String? {
        let address = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isWebAddress(address) else { return nil }

        let picked = selection.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = picked.isEmpty
            ? (name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            : picked
        guard !title.isEmpty, !title.contains("\n") else { return "<" + address + ">" }
        return NoteLinking.markdownLink(label: title, path: address)
    }

    /// 링크로 만들 만한 주소인가. **`http` · `https` 만** 본다 — `javascript:` 같은 것을
    /// 링크로 만들면 누르는 사람이 위험하다.
    public static func isWebAddress(_ text: String) -> Bool {
        guard !text.isEmpty, !text.contains(" "), !text.contains("\n") else { return false }
        let lower = text.lowercased()
        guard lower.hasPrefix("http://") || lower.hasPrefix("https://") else { return false }
        // `https://` 뒤에 뭐라도 있어야 한다.
        return text.count > (lower.hasPrefix("https://") ? 8 : 7)
    }

    // MARK: - 자잘한 것

    /// 줄이 **마커 하나로만** 이루어져 있나. 그렇다면 앞칸과 갈래를 돌려준다.
    private static func onlyMarker(_ line: String) -> (leading: String, kind: MarkerKind)? {
        guard let found = leadingMarker(line) else { return nil }
        guard found.marker.count == line.count else { return nil }   // 뒤에 글이 있으면 아니다
        let leading = String(line.prefix { $0 == " " || $0 == "\t" })
        return (leading, found.kind)
    }

    /// 줄 앞머리의 목록 마커 — 앞칸까지 **통째로** 돌려준다 (`  1. `).
    static func leadingMarker(_ line: String) -> (marker: String, kind: MarkerKind)? {
        var cursor = line.startIndex
        while cursor < line.endIndex, line[cursor] == " " || line[cursor] == "\t" {
            cursor = line.index(after: cursor)
        }
        guard cursor < line.endIndex else { return nil }

        // 수평선(`---`)은 목록이 아니다.
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if let first = trimmed.first, first == "-" || first == "*" || first == "_",
           trimmed.count >= 3,
           trimmed.allSatisfy({ $0 == first || $0 == " " }) {
            return nil
        }

        var after: String.Index?
        var kind: MarkerKind = .bullet
        if line[cursor].isASCII, line[cursor].isNumber {
            var digits = cursor
            var count = 0
            while digits < line.endIndex, line[digits].isASCII, line[digits].isNumber, count < 9 {
                count += 1
                digits = line.index(after: digits)
            }
            if digits < line.endIndex, line[digits] == "." || line[digits] == ")" {
                let next = line.index(after: digits)
                if next < line.endIndex, line[next] == " " {
                    after = next
                    kind = .ordered
                }
            }
        }
        if after == nil, line[cursor] == "-" || line[cursor] == "*" || line[cursor] == "+" {
            let next = line.index(after: cursor)
            if next < line.endIndex, line[next] == " " {
                after = next
                kind = .bullet
            }
        }
        guard var end = after else { return nil }
        while end < line.endIndex, line[end] == " " { end = line.index(after: end) }
        return (String(line[line.startIndex..<end]), kind)
    }
}
