import SwiftUI
import UIKit

// 글꼴과 **글자를 담는 길이**를 한 곳에서 만든다.
//
// 지난 앱에서 `.system(size:)` 275곳을 나중에 고쳤다. 고치고 나니 이번엔 글자를 담는
// 칸(폭 · 높이 · 여백)이 고정이라 캡션이 겹쳤다. 그래서 **화면을 하나 만들기 전에**
// 이 파일이 먼저 있다 (설계서 §8).
//
// 규칙: 이 파일 밖에서 `.system(size:)` 와 고정 `padding` 숫자를 쓰지 않는다.

extension Font {
    /// Dynamic Type 을 따라 커지는 글꼴.
    static func scaled(_ style: Font.TextStyle, weight: Font.Weight = .regular) -> Font {
        .system(style, design: .default, weight: weight)
    }

    /// 코드 · 마크다운 원문에 쓰는 고정폭. 라이브 편집기의 표 · 코드 블록이 이것을 쓴다.
    static func scaledMono(_ style: Font.TextStyle, weight: Font.Weight = .regular) -> Font {
        .system(style, design: .monospaced, weight: weight)
    }

    /// **명조 제목** (317, 2026-11-12 사용자 — *명조 넣기*). 노트 제목 · 읽기 화면의 제목 · 막대 제목에만 쓴다 — 본문은 시스템 글꼴 그대로(가독성).
    /// 앱에 넣은 노토 명조 굵은 한 벌(`AppFont.serifName`). **글자 크기 설정을 따른다** — `relativeTo:` 가 Dynamic Type 으로 키운다.
    /// 글꼴이 안 실렸으면 시스템의 명조 디자인(라틴은 명조 · 한글은 고딕)으로 물러선다.
    static func scaledSerif(_ style: Font.TextStyle) -> Font {
        guard AppFont.serifAvailable else { return .system(style, design: .serif, weight: .bold) }
        return .custom(AppFont.serifName, size: AppFont.baseSize(style), relativeTo: style)
    }
}

/// 앱에 넣은 글꼴 (317 · ADR-0010). `Info.plist` 의 `UIAppFonts` 가 싣는다 — 파일은 `App/Resources/Fonts/` (사용 허락서 `OFL.txt` 함께).
enum AppFont {
    /// PostScript 이름 — 글꼴 파일 안의 이름표(6번)와 같다.
    static let serifName = "NotoSerifKR-Bold"
    static let serifFile = "NotoSerifKR-Bold-Subset"

    static var serifAvailable: Bool { UIFont(name: serifName, size: 12) != nil }

    /// 글자 크기 설정이 *보통* 일 때의 크기 — `relativeTo:` · `UIFontMetrics` 가 여기서부터 키운다.
    static func baseSize(_ style: Font.TextStyle) -> CGFloat {
        switch style {
        case .largeTitle: return 34
        case .title: return 28
        case .title2: return 22
        case .title3: return 20
        case .headline, .body: return 17
        case .callout: return 16
        case .subheadline: return 15
        case .footnote: return 13
        case .caption: return 12
        case .caption2: return 11
        @unknown default: return 17
        }
    }

    /// UIKit 쪽(편집기 제목 · 막대 제목) — 같은 글꼴을 글자 크기 설정만큼 키워 준다. 없으면 시스템 굵은 글꼴.
    @MainActor
    static func serif(_ style: UIFont.TextStyle, size: CGFloat) -> UIFont {
        guard let base = UIFont(name: serifName, size: size) else { return .systemFont(ofSize: size, weight: .bold) }
        return UIFontMetrics(forTextStyle: style).scaledFont(for: base)
    }
}

@MainActor
enum Metrics {
    /// 글자를 담는 길이는 글자와 같은 비율로 커져야 한다.
    static func scaledLength(_ points: CGFloat, relativeTo style: UIFont.TextStyle = .body) -> CGFloat {
        UIFontMetrics(forTextStyle: style).scaledValue(for: points)
    }

    static var gutter: CGFloat { scaledLength(16) }
    static var rowSpacing: CGFloat { scaledLength(6) }
    static var blockSpacing: CGFloat { scaledLength(14) }
    static var iconSide: CGFloat { scaledLength(22) }
}
