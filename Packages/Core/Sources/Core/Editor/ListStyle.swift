import Foundation

/// 목록 줄의 모양 (193).
public enum ListMarker: String, Equatable, Sendable {
    case bullet
    case number
    case checkbox
    /// 목록 아님. **`none` 이라 부르지 않는다** (194) — 화면 쪽은 `ListMarker?` 로 받는데, 거기서 `.none` 은
    /// `Optional.none`(= 단추 한 번 누르기)으로 읽혀 *목록 해제* 가 번호로 바뀌었다 (빌드 67 · 8번).
    case plain

    /// 새로 쓸 마커. 번호는 모두 `1.` 로 두고 다시 매기기(104)가 맞춘다.
    public var text: String {
        switch self {
        case .bullet: return "- "
        case .number: return "1. "
        case .checkbox: return "- [ ] "
        case .plain: return ""
        }
    }
}

/// **목록 모양 바꾸기** — 도구 띠의 목록 단추 (193, 사용자 — *1. 가나다 입력 후 들여쓰기해서 하위 항목을
/// 불렛으로 입력하려면 지우고 맞추고 하는 작업들이 생기는데 … 버튼이 하나 있으면 좋겠다*).
///
/// 줄의 **마커만** 갈아 끼운다 — 앞 빈칸과 글은 그대로다. `1. ` 은 세 칸, `- ` 는 두 칸이라 **글이 시작하는
/// 칸**(자식이 들어가야 할 칸)이 바뀐다. 그대로 두면 딸린 줄이 겹침에서 빠진다(141 과 같은 뿌리). 그래서 바꾼
/// 줄에 딸린 줄들을 그 차이만큼 함께 민다. 정답표(`restyleCases`)가 **파서가 세는 단계가 한 줄도 안 바뀌는지**
/// 파이썬 쪽에서 본다.
///
/// 문자 개요(`가.` · `a.`)는 넣지 않는다 — 마크다운 목록이 아니라 다른 앱과 읽기 화면에서 글자로 보인다.
/// **파이썬 `restyle_lines` 와 같은 셈이다.**
extension ListEditing {

    /// 단추를 **눌렀을 때** 갈 모양 — 번호 ↔ 글머리표. 체크상자는 번호로, 목록이 아니면 글머리표로.
    public static func toggleTarget(_ line: String) -> ListMarker {
        switch splitMarker(line).kind {
        case .number: return .bullet
        case .bullet, .checkbox: return .number
        case .plain: return .bullet
        }
    }

    /// `lines` 가운데 `first` 부터 `count` 줄의 모양을 `marker` 로. 빈 줄은 건너뛴다.
    public static func restyle(lines: [String], first: Int, count: Int, to marker: ListMarker) -> [String] {
        var out = lines
        guard first >= 0, first < out.count else { return out }
        let last = min(out.count, first + max(count, 1))
        for index in first..<last {
            let line = out[index]
            if line.trimmingCharacters(in: .whitespaces).isEmpty { continue }
            let parts = splitMarker(line)
            if parts.kind == marker { continue }
            let newLine = String(parts.indent) + marker.text + String(parts.body)
            let oldColumn = (parts.kind == .plain ? nil : contentColumn(line)) ?? width(line)
            let newColumn = (marker == .plain ? nil : contentColumn(newLine)) ?? width(newLine)
            let delta = newColumn - oldColumn
            let end = parts.kind == .plain ? index + 1 : subtreeEnd(from: index, in: out)
            out[index] = newLine
            guard delta != 0, index + 1 < end else { continue }
            for child in (index + 1)..<end {
                let text = out[child]
                if text.trimmingCharacters(in: .whitespaces).isEmpty { continue }
                if delta > 0 {
                    out[child] = String(repeating: " ", count: delta) + text
                } else {
                    let spaces = text.prefix { $0 == " " }.count
                    out[child] = String(text.dropFirst(min(-delta, spaces)))
                }
            }
        }
        return out
    }

    /// (앞 빈칸, 모양, 글). 파이썬 `split_marker` 와 같다.
    public static func splitMarker(_ line: String) -> (indent: Substring, kind: ListMarker, body: Substring) {
        let indent = line.prefix { $0 == " " || $0 == "\t" }
        let rest = line.dropFirst(indent.count)
        if let mark = rest.first, mark == "-" || mark == "*" || mark == "+",
           rest.dropFirst().first == " " {
            let after = rest.dropFirst(2)
            let box = Array(after.prefix(4))
            if box.count == 4, box[0] == "[", box[1] == " " || box[1] == "x" || box[1] == "X",
               box[2] == "]", box[3] == " " {
                return (indent, .checkbox, after.dropFirst(4))
            }
            return (indent, .bullet, after)
        }
        let digits = rest.prefix { $0.isASCII && $0.isNumber }
        let after = rest.dropFirst(digits.count)
        if !digits.isEmpty, digits.count <= 9, after.hasPrefix(". ") || after.hasPrefix(") ") {
            return (indent, .number, after.dropFirst(2))
        }
        return (indent, .plain, rest)
    }

    /// 줄 앞의 빈칸 너비 (탭은 네 칸) — `leadingWidth` 와 같다.
    private static func width(_ line: String) -> Int {
        line.prefix { $0 == " " || $0 == "\t" }.reduce(0) { $0 + ($1 == "\t" ? 4 : 1) }
    }
}
