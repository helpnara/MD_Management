import Foundation

/// **마크다운이 줄바꿈 · 빈칸으로 안 보는 글자를 고친다** (287, 2026-11-01 사용자 — *앱에서 표시가 잘못되는 이유를 모르겠어*).
///
/// 웹 · 다른 노트 앱에서 옮겨 온 글은 줄바꿈이 `U+2028`(줄 구분 글자)로, 들여쓰기가 `U+00A0`(붙는 빈칸)과 빈칸을
/// 번갈아 쓴 꼴로 오는 일이 있다. 화면에서는 줄이 바뀌고 들여 쓴 것처럼 보이지만 **마크다운은 둘 다 글자로 본다** —
/// 사용자의 노트는 줄바꿈 1,056곳이 `U+2028` 이라 `## 제목` 48곳 · `- 목록` 122곳이 줄 가운데에 놓였고,
/// 읽기 화면에는 목록이 하나도 서지 않았다. iOS 문자열도 `U+2028` 에서 **문단**을 끊지 않아, 편집기는 수천 자를 한 문단으로 칠했다.
///
/// 고치는 것은 둘뿐이다 — 글자 수는 그대로다(UTF-16 으로 한 글자 → 한 글자). 그래서 커서 자리를 옮길 필요가 없다.
/// - 줄바꿈으로 보는 글자(`foreign`) → `\n`
/// - **줄 앞** 빈칸 덩어리 안의 `U+00A0` → 빈칸. 줄 가운데의 것은 그대로 둔다 — 글 속 붙는 빈칸은 일부러 쓴 것일 수 있다.
///
/// 붙여넣기(`LibraryModel.repairPastedLinks`)와 *줄바꿈 고치기* 메뉴가 **이 하나**를 쓴다. 지도 장소(`MapPlaces.breaks`)도
/// 같은 목록으로 줄을 나눈다 — 줄바꿈으로 보는 글자를 적어 두는 자리는 여기 하나다 (CLAUDE.md §1).
public enum LineBreaks {

    /// 마크다운이 줄바꿈으로 안 보는데 화면 · 다른 앱은 줄바꿈으로 쓰는 글자 — 세로 탭 · 폼 피드 · 다음 줄 · 줄 구분 · 문단 구분.
    /// `\r` 은 넣지 않는다 — `\r\n` · `\r` 은 마크다운이 이미 줄바꿈으로 본다.
    public static let foreign: Set<Unicode.Scalar> = ["\u{0B}", "\u{0C}", "\u{85}", "\u{2028}", "\u{2029}"]

    /// 붙는 빈칸 (`&nbsp;`).
    public static let noBreakSpace: Unicode.Scalar = "\u{00A0}"

    /// 고칠 곳이 몇 개인가 — 줄바꿈 글자 · 줄 앞의 붙는 빈칸. 둘 다 0 이면 고칠 것이 없다.
    public struct Count: Equatable, Sendable {
        public let breaks: Int
        public let spaces: Int

        public init(breaks: Int, spaces: Int) {
            self.breaks = breaks
            self.spaces = spaces
        }

        public var isEmpty: Bool { breaks == 0 && spaces == 0 }
    }

    /// 고칠 곳을 센다. `repaired` 와 **같은 걸음**으로 센다 — 둘이 갈리면 메뉴는 뜨는데 고칠 것이 없다.
    public static func count(_ text: String) -> Count {
        var breaks = 0
        var spaces = 0
        walk(text) { _, change in
            switch change {
            case .lineBreak: breaks += 1
            case .space: spaces += 1
            case .keep: break
            }
        }
        return Count(breaks: breaks, spaces: spaces)
    }

    /// 고친 글. 고칠 것이 없으면 같은 글을 돌려준다.
    public static func repaired(_ text: String) -> String {
        guard !count(text).isEmpty else { return text }
        var out = String.UnicodeScalarView()
        out.reserveCapacity(text.unicodeScalars.count)
        walk(text) { scalar, change in
            switch change {
            case .lineBreak: out.append("\n")
            case .space: out.append(" ")
            case .keep: out.append(scalar)
            }
        }
        return String(out)
    }

    private enum Change { case keep, lineBreak, space }

    /// 한 글자씩 걸으며 무엇으로 바꿀지 정한다. **줄 앞**은 줄 첫머리부터 빈칸 · 탭 · 붙는 빈칸만 이어진 동안이다.
    private static func walk(_ text: String, _ visit: (Unicode.Scalar, Change) -> Void) {
        var atLineStart = true
        for scalar in text.unicodeScalars {
            if foreign.contains(scalar) {
                visit(scalar, .lineBreak)
                atLineStart = true
            } else if scalar == "\n" || scalar == "\r" {
                visit(scalar, .keep)
                atLineStart = true
            } else if atLineStart && scalar == noBreakSpace {
                visit(scalar, .space)
            } else if atLineStart && (scalar == " " || scalar == "\t") {
                visit(scalar, .keep)
            } else {
                visit(scalar, .keep)
                atLineStart = false
            }
        }
    }
}
