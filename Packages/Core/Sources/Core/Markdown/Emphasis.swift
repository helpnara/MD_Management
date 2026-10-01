import Foundation

/// **한글 곁의 강조** (197) — 편집기와 읽기 화면이 굵게 · 기울임 · 취소선을 **같은 규칙 하나**로 판정한다.
///
/// CommonMark 는 `**` 가 **문장부호 곁**에 붙으면 반대쪽이 빈칸이나 문장부호여야 강조를 열고 닫는다. 영어는 낱말 사이에
/// 빈칸이 있어 괜찮은데 한글은 조사가 붙는다 — `**개인 기록(영어)**로` 의 닫는 `**` 는 앞이 `)` 뒤가 `로` 라 **닫히지
/// 않는다.** 편집기는 *빈칸만 아니면* 닫는 제 규칙으로 굵게 칠했고, 읽기 화면(cmark-gfm)은 `**` 를 글자로 남겼다
/// (사용자 · 2026-10-01 캡처). **같은 것을 재는 곳이 둘이었다.**
///
/// 규칙 하나를 더한다 — **반대쪽이 한중일 글자여도 된다.** 편집기는 이 판정(`canOpen` · `canClose`)으로 칠하고,
/// 읽기 화면은 같은 자리에 **안 보이는 문장부호** `⸱`(U+2E31)를 끼워(`cjkFriendly`) cmark-gfm 이 스스로 열고 닫게
/// 한 뒤 HTML 에서 뺀다(`stripSentinel`). **파일은 한 글자도 안 바뀐다.** `_` 는 넣지 않는다 — 낱말 안의 밑줄
/// (`snake_case`) 규칙이 더 중하다.
///
/// **파이썬 `cjk_friendly` · `left_flanking` · `right_flanking` 과 같은 셈이다** (`Tools/golden`, `emphasisCases`).
public enum Emphasis {

    /// 읽기 화면에만 끼우는 글자 — WORD SEPARATOR MIDDLE DOT (문장부호 `Po`). 글에서 쓸 일이 거의 없다.
    /// 글에 이미 있으면 끼우지 않는다 — 뺄 때 사용자의 글자까지 빠지지 않게.
    public static let sentinel: Unicode.Scalar = "\u{2E31}"

    /// `*` · `~` 뭉치를 열 수 있나. `before` · `after` 는 뭉치 **바깥** 양옆 글자 (줄 끝이면 `nil`).
    public static func canOpen(_ delimiter: Character, before: Unicode.Scalar?, after: Unicode.Scalar?) -> Bool {
        if delimiter == "_" {
            return leftFlanking(before, after, cjk: false)
                && (!rightFlanking(before, after, cjk: false) || isPunctuation(before))
        }
        return leftFlanking(before, after, cjk: true)
    }

    public static func canClose(_ delimiter: Character, before: Unicode.Scalar?, after: Unicode.Scalar?) -> Bool {
        if delimiter == "_" {
            return rightFlanking(before, after, cjk: false)
                && (!leftFlanking(before, after, cjk: false) || isPunctuation(after))
        }
        return rightFlanking(before, after, cjk: true)
    }

    /// 읽기 화면에 넘기기 전 — **한글 덕에만** 열리고 닫히는 `*` · `~` 뭉치 곁에 `⸱` 를 끼운다.
    public static func cjkFriendly(_ text: String) -> String {
        let scalars = Array(text.unicodeScalars)
        guard !scalars.contains(sentinel), scalars.contains(where: { $0 == "*" || $0 == "~" }) else { return text }
        var out = String.UnicodeScalarView()
        var i = 0
        while i < scalars.count {
            let scalar = scalars[i]
            if scalar == "\\", i + 1 < scalars.count {
                out.append(scalar)
                out.append(scalars[i + 1])
                i += 2
                continue
            }
            guard scalar == "*" || scalar == "~" else {
                out.append(scalar)
                i += 1
                continue
            }
            var j = i
            while j < scalars.count, scalars[j] == scalar { j += 1 }
            let before = i > 0 ? scalars[i - 1] : nil
            let after = j < scalars.count ? scalars[j] : nil
            let run = scalars[i..<j]
            if !leftFlanking(before, after, cjk: false), leftFlanking(before, after, cjk: true) {
                out.append(sentinel)
                out.append(contentsOf: run)
            } else if !rightFlanking(before, after, cjk: false), rightFlanking(before, after, cjk: true) {
                out.append(contentsOf: run)
                out.append(sentinel)
            } else {
                out.append(contentsOf: run)
            }
            i = j
        }
        return String(out)
    }

    /// 끼운 `⸱` 를 뺀다 — 글자 그대로든, 주소 안에서 퍼센트로 바뀌었든.
    public static func stripSentinel(_ text: String) -> String {
        guard text.contains("\u{2E31}") || text.contains("%E2%B8%B1") || text.contains("%e2%b8%b1") else { return text }
        return text.replacingOccurrences(of: "\u{2E31}", with: "")
            .replacingOccurrences(of: "%E2%B8%B1", with: "")
            .replacingOccurrences(of: "%e2%b8%b1", with: "")
    }

    // MARK: - CommonMark 의 왼쪽 · 오른쪽 기댐 (+ 한중일)

    static func leftFlanking(_ before: Unicode.Scalar?, _ after: Unicode.Scalar?, cjk: Bool) -> Bool {
        if isSpace(after) { return false }
        if !isPunctuation(after) { return true }
        return isSpace(before) || isPunctuation(before) || (cjk && isCJK(before))
    }

    static func rightFlanking(_ before: Unicode.Scalar?, _ after: Unicode.Scalar?, cjk: Bool) -> Bool {
        if isSpace(before) { return false }
        if !isPunctuation(before) { return true }
        return isSpace(after) || isPunctuation(after) || (cjk && isCJK(after))
    }

    /// 줄 끝 · 첫머리(`nil`)도 빈칸이다 (CommonMark).
    static func isSpace(_ scalar: Unicode.Scalar?) -> Bool {
        guard let scalar else { return true }
        switch scalar {
        case " ", "\t", "\n", "\r", "\u{0C}": return true
        default: return scalar.properties.generalCategory == .spaceSeparator
        }
    }

    private static let asciiPunctuation = Set("!\"#$%&'()*+,-./:;<=>?@[\\]^_`{|}~".unicodeScalars)

    static func isPunctuation(_ scalar: Unicode.Scalar?) -> Bool {
        guard let scalar else { return false }
        if scalar.isASCII { return asciiPunctuation.contains(scalar) }
        switch scalar.properties.generalCategory {
        case .connectorPunctuation, .dashPunctuation, .openPunctuation, .closePunctuation,
             .initialPunctuation, .finalPunctuation, .otherPunctuation:
            return true
        default:
            return false
        }
    }

    /// 한글(음절 · 자모) · 가나 · 한자 · 반각 가나 · 한글.
    static func isCJK(_ scalar: Unicode.Scalar?) -> Bool {
        guard let value = scalar?.value else { return false }
        switch value {
        case 0x1100...0x11FF, 0x3040...0x30FF, 0x3130...0x318F, 0x3400...0x4DBF, 0x4E00...0x9FFF,
             0xA960...0xA97F, 0xAC00...0xD7A3, 0xD7B0...0xD7FF, 0xF900...0xFAFF, 0xFF66...0xFFDC:
            return true
        default:
            return false
        }
    }
}
