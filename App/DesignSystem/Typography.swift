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
