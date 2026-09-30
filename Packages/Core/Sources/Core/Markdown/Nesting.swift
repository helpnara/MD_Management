import Foundation

/// **겹침이 너무 깊은 글** (182).
///
/// 마크다운 라이브러리(swift-markdown)는 cmark 가 읽은 트리를 **재귀로** 옮기고 · 걷고 · 지운다.
/// `> > > …` 가 수천 겹인 파일이면 스택이 넘쳐 앱이 꺼진다 — 읽기로 열어도, 커서를 옮겨도(사진 줄
/// 찾기), 링크를 세어도. 그래서 파서에 넘기기 **전에** 한 번 훑어 겹침 깊이의 **위쪽 한계**를 잰다.
/// 한계를 넘으면 트리를 만들지 않는다 — 부르는 쪽이 글 그대로 다룬다.
///
/// **작게 말하면 안 된다** — 그러면 막지 못한다. 정답표(`nestingCases`)가 cmark 가 실제로 만든
/// 깊이와 견주어 이 값이 늘 크거나 같은지 본다. 크게 말하는 것은 괜찮다 — 보통 노트는 50 도 안 된다.
///
/// 한 줄의 값 = 앞머리(`>` 1 · 목록 표시 2 · 빈칸 1 · 탭 4) + 잎 블록 4 + 줄 안 표시 + 여유 2.
/// 줄 안 표시(`*` `~` `[` · 낱말 가운데가 아닌 `_`)는 **문단이 이어지는 동안 더해 간다** — 기울임은
/// 줄을 넘어 이어질 수 있다. 빈 줄 · 제목 · 새 목록 항목 · 코드 울타리에서 새로 센다. `|` 가 든 줄
/// (표의 한 줄)은 저 혼자 센다. 울타리 안은 줄 안 표시를 안 센다. **파이썬 `nesting_depth` 와 같은 셈이다.**
public enum Nesting {

    /// 이보다 깊으면 트리를 만들지 않는다. 인용으로 치면 125 겹까지 연다.
    public static let limit = 256
    static let leaf = 4
    static let slack = 2

    public static func isTooDeep(_ text: String) -> Bool {
        depth(of: text) > limit
    }

    public static func depth(of text: String) -> Int {
        var deepest = 0
        var carried = 0
        var fence: (mark: Unicode.Scalar, length: Int)?

        for raw in text.unicodeScalars.split(separator: "\n", omittingEmptySubsequences: false) {
            let line: [Unicode.Scalar] = Array(raw).filter { $0 != "\r" }
            let n = line.count
            var i = 0
            var container = 0
            var item = false
            while i < n {
                let c = line[i]
                if c == " " || c == ">" {
                    container += 1
                    i += 1
                } else if c == "\t" {
                    container += 4
                    i += 1
                } else if c == "-" || c == "+" || c == "*", i + 1 == n || isBlank(line[i + 1]) {
                    container += 2
                    item = true
                    i += 1
                } else if isDigit(c) {
                    var j = i
                    while j < n, isDigit(line[j]), j - i < 9 { j += 1 }
                    guard j < n, line[j] == "." || line[j] == ")",
                          j + 1 == n || isBlank(line[j + 1]) else { break }
                    container += 2
                    item = true
                    i = j + 1
                } else {
                    break
                }
            }
            let rest = Array(line[i...])
            let stripped = trimmed(rest)

            if let open = fence {
                let run = stripped.prefix { $0 == open.mark }.count
                if run >= open.length, trimmed(Array(stripped.dropFirst(run))).isEmpty { fence = nil }
                deepest = max(deepest, container + leaf)
                carried = 0
                continue
            }
            guard let first = stripped.first else {
                carried = 0
                continue
            }
            if first == "`" || first == "~" {
                let run = stripped.prefix { $0 == first }.count
                if run >= 3, !(first == "`" && stripped.dropFirst(run).contains("`")) {
                    fence = (first, run)
                    deepest = max(deepest, container + leaf)
                    carried = 0
                    continue
                }
            }
            let hashes = stripped.prefix { $0 == "#" }.count
            if item || ((1...6).contains(hashes) && (hashes == stripped.count || isBlank(stripped[hashes]))) {
                carried = 0
            }
            var marks = 0
            for (k, ch) in rest.enumerated() {
                if ch == "*" || ch == "~" || ch == "[" {
                    marks += 1
                } else if ch == "_" {
                    let inside = k > 0 && k < rest.count - 1 && isWordish(rest[k - 1]) && isWordish(rest[k + 1])
                    if !inside { marks += 1 }
                }
            }
            let unit: Int
            if stripped.contains("|") {
                unit = marks
                carried = 0
            } else {
                carried += marks
                unit = carried
            }
            deepest = max(deepest, container + leaf + unit + slack)
        }
        return deepest
    }

    private static func isDigit(_ c: Unicode.Scalar) -> Bool {
        (48...57).contains(c.value)
    }

    private static func isBlank(_ c: Unicode.Scalar) -> Bool {
        c == " " || c == "\t"
    }

    private static func trimmed(_ scalars: [Unicode.Scalar]) -> [Unicode.Scalar] {
        guard let start = scalars.firstIndex(where: { !isBlank($0) }),
              let end = scalars.lastIndex(where: { !isBlank($0) }) else { return [] }
        return Array(scalars[start...end])
    }

    /// 파이썬 `_wordish` 와 같다 — 영문 · 숫자 · 한글 음절. 그 사이의 `_` 는 기울임을 못 연다.
    private static func isWordish(_ c: Unicode.Scalar) -> Bool {
        switch c.value {
        case 48...57, 65...90, 97...122, 0xAC00...0xD7A3: return true
        default: return false
        }
    }
}
