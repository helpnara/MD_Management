import Foundation

/// **읽기 화면에서 체크상자 누르기** (211, 2026-10-03 사용자 — 좋은 아이디어야 · 하나씩 구현해 보자).
///
/// 사용자는 평소 **읽기 모드**로 본다(A11 을 뺀 까닭). 체크상자를 켜고 끄려고 쓰기로 넘어가는 것이 이 앱에서 가장 잦은 오감이었다.
/// 읽기 화면의 체크상자는 `yb://task/<줄>` 링크가 되고, 누르면 앱이 **그 줄의 `[ ]` · `[x]` 한 글자만** 바꾼다.
/// 고친 글은 편집기와 **같은 문**(`LibraryModel.noteEdited` → 저장)으로 들어간다 — 본문을 고치는 길은 하나다 (CLAUDE.md §1).
///
/// 줄 번호는 `LineMap` 과 같다 — **0 부터, 머리말 줄도 센다.** 파이썬 쌍둥이 `task_toggled` · `task_lines` (`htmlMarkdownCases`).
public enum TaskToggle {

    /// `line` 의 체크상자를 뒤집은 글. 체크상자 줄이 아니거나 줄이 없으면 `nil` — 아무것도 안 바꾼다.
    public static func toggled(_ markdown: String, line: Int) -> String? {
        var lines = split(markdown)
        guard line >= 0, line < lines.count else { return nil }
        var scalars = Array(lines[line].unicodeScalars)
        guard let at = marker(scalars) else { return nil }
        scalars[at] = (scalars[at] == "x" || scalars[at] == "X") ? " " : "x"
        lines[line] = string(scalars)
        return lines.joined(separator: "\n")
    }

    /// 체크상자가 든 목록 줄이면 `[` 다음 글자의 자리. 앞 빈칸 · 인용(`>`) 몇 겹 · 목록 기호 · 빈칸 · `[ ]`/`[x]` · 빈칸.
    /// `- [ ]` 혼자(뒤에 빈칸이 없음)는 체크상자가 아니다 (cmark-gfm).
    static func marker(_ s: [Unicode.Scalar]) -> Int? {
        let n = s.count
        func spaces(_ k: Int) -> Int {
            var k = k
            while k < n, s[k] == " " || s[k] == "\t" { k += 1 }
            return k
        }
        var i = spaces(0)
        while i < n, s[i] == ">" { i = spaces(i + 1) }
        if i < n, s[i] == "-" || s[i] == "*" || s[i] == "+" {
            i += 1
        } else {
            var j = i
            while j < n, j - i < 9, s[j] >= "0" && s[j] <= "9" { j += 1 }
            guard j > i, j < n, s[j] == "." || s[j] == ")" else { return nil }
            i = j + 1
        }
        guard i < n, s[i] == " " || s[i] == "\t" else { return nil }
        i = spaces(i)
        guard i + 3 < n, s[i] == "[", s[i + 2] == "]",
              s[i + 1] == " " || s[i + 1] == "x" || s[i + 1] == "X",
              s[i + 3] == " " || s[i + 3] == "\t" else { return nil }
        return i + 1
    }

    /// `\n` 으로만 가른다 (스칼라로 — `Character` 는 `\r\n` 을 한 자로 본다).
    static func split(_ text: String) -> [String] {
        var out: [String] = []
        var current = String.UnicodeScalarView()
        for c in text.unicodeScalars {
            if c == "\n" {
                out.append(String(current))
                current = String.UnicodeScalarView()
            } else {
                current.append(c)
            }
        }
        out.append(String(current))
        return out
    }

    static func string(_ scalars: [Unicode.Scalar]) -> String {
        var view = String.UnicodeScalarView()
        view.append(contentsOf: scalars)
        return String(view)
    }
}
