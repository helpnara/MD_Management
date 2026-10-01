import Foundation

/// **강조를 여닫는 자리** (197) — 편집기가 굵게 · 기울임 · 취소선을 **읽기 화면과 같은 규칙(CommonMark)**으로 판정한다.
///
/// CommonMark 는 `**` 가 **문장부호 곁**에 붙으면 반대쪽이 빈칸이나 문장부호여야 열고 닫는다. 그래서
/// `**개인 기록(영어)**로` 의 닫는 `**` 는 앞이 `)` 뒤가 `로` 라 **닫히지 않는다** — 읽기 화면(cmark-gfm)은 `**` 를
/// 글자로 남겼는데, 편집기는 *빈칸만 아니면* 닫는 제 규칙으로 굵게 칠했다 (사용자 · 2026-10-01 캡처). **같은 것을 재는
/// 곳이 둘이었다.**
///
/// 한글 곁에서도 열고 닫게 규칙을 넓히는 길도 있었지만 **표준을 따른다** (2026-10-01 사용자 — *변형이 많으면 호환성이
/// 떨어지므로 기본에 충실*). 이 앱에서 굵게 보이면 다른 앱에서도 굵게 보인다. 조사를 붙이려면 문장부호를 강조 밖으로
/// 낸다 — `**개인 기록**(영어)로`.
///
/// 읽기 화면은 cmark-gfm 이 이 규칙 그대로 그린다. 기댓값은 `Tools/golden` 의 `emphasisCases`(두 파서) · `styleCases`.
public enum Emphasis {

    /// `*` · `~` · `_` 뭉치를 열 수 있나. `before` · `after` 는 뭉치 **바깥** 양옆 글자 (글 끝이면 `nil`).
    public static func canOpen(_ delimiter: Character, before: Unicode.Scalar?, after: Unicode.Scalar?) -> Bool {
        let left = leftFlanking(before, after)
        guard delimiter == "_" else { return left }
        return left && (!rightFlanking(before, after) || isPunctuation(before))
    }

    public static func canClose(_ delimiter: Character, before: Unicode.Scalar?, after: Unicode.Scalar?) -> Bool {
        let right = rightFlanking(before, after)
        guard delimiter == "_" else { return right }
        return right && (!leftFlanking(before, after) || isPunctuation(after))
    }

    // MARK: - CommonMark 의 왼쪽 · 오른쪽 기댐

    static func leftFlanking(_ before: Unicode.Scalar?, _ after: Unicode.Scalar?) -> Bool {
        if isSpace(after) { return false }
        if !isPunctuation(after) { return true }
        return isSpace(before) || isPunctuation(before)
    }

    static func rightFlanking(_ before: Unicode.Scalar?, _ after: Unicode.Scalar?) -> Bool {
        if isSpace(before) { return false }
        if !isPunctuation(before) { return true }
        return isSpace(after) || isPunctuation(after)
    }

    /// 글 끝 · 첫머리(`nil`)도 빈칸이다 (CommonMark).
    static func isSpace(_ scalar: Unicode.Scalar?) -> Bool {
        guard let scalar else { return true }
        switch scalar {
        case " ", "\t", "\n", "\r", "\u{0C}": return true
        default: return scalar.properties.generalCategory == .spaceSeparator
        }
    }

    private static let asciiPunctuation = Set("!\"#$%&'()*+,-./:;<=>?@[\\]^_`{|}~".unicodeScalars)

    /// 아스키 문장부호 + 유니코드 문장부호(`P*`) — cmark-gfm 과 같은 범위.
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
}
