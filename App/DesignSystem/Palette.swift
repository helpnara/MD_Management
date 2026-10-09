import SwiftUI
import UIKit

// 색은 여기서만 정한다. 화면에서 색을 직접 적지 않는다.
//
// 지난 앱에서 화면마다 다크 모드 톤이 제각각이었다. 뷰어(WKWebView)의 CSS 도 같은
// 토큰을 `--yb-*` 변수로 받아 앱과 웹뷰가 함께 간다 (ADR-0004 · 설계서 §8).

@MainActor
enum Palette {
    /// 종이 — 바탕
    static let paper = Color(uiColor: .systemBackground)
    /// 한 겹 올라온 종이 — 목록 행 · 카드
    static let paperRaised = Color(uiColor: .secondarySystemBackground)
    /// 먹 — 본문 글자
    static let ink = Color(uiColor: .label)
    /// 옅은 먹 — 보조 설명 · 날짜
    static let inkFaint = Color(uiColor: .secondaryLabel)
    /// 마크다운 마커(`#` `**` `-`)를 흐리게 보일 때 (라이브 편집기 L1)
    static let marker = Color(uiColor: .tertiaryLabel)
    /// 강조 — 링크 · 선택
    static let accent = Color(uiColor: .tintColor)
    /// 인용 세로선 · 구분선
    static let rule = Color(uiColor: .separator)
    /// `#태그` (T2). 편집기와 뷰어가 같은 색을 쓴다.
    static let tag = Color(uiColor: tagUIColor)

    /// **인용 글자** (191). 편집기와 뷰어가 **같은 색 하나**를 쓴다 — 예전에는 편집기가 60% 회색, 뷰어가 투명도를
    /// 버린 회색이라 한쪽은 너무 흐리고 한쪽은 본문과 같았다. 옅은 파랑 — 링크 파랑보다 옅은 톤이고 링크에는 밑줄이 있다.
    /// 대비는 `Tools/contrast.py` 가 이 파일을 읽어 센다 (손으로 세지 않는다).
    static let quote = Color(uiColor: quoteUIColor)

    static let quoteUIColor = UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.490, green: 0.722, blue: 1.000, alpha: 1)    // 어두운 바탕 — #7DB8FF
            : UIColor(red: 0.184, green: 0.373, blue: 0.620, alpha: 1)    // 밝은 바탕 — #2F5F9E
    }

    /// `#태그` 색. 대비는 `Tools/contrast.py` 가 센다 — 밝은 바탕은 예전 `#B88500` 이 3.3:1 이라 4.5 에 못 미쳐 짙게 했다 (232).
    static let tagUIColor = UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 1.00, green: 0.84, blue: 0.35, alpha: 1)       // 어두운 바탕 — #FFD659
            : UIColor(red: 0.56, green: 0.405, blue: 0.00, alpha: 1)      // 밝은 바탕 — #8F6700
    }

    // MARK: - 뷰어 CSS 로 넘기는 같은 토큰

    /// `WKWebView` 의 `<style>` 맨 위에 넣는다.
    ///
    /// **두 벌을 다 낸다.** 라이트와 다크를 한 번에 넣어 두면 웹뷰가 시스템 설정을
    /// 저절로 따라간다 — 모드가 바뀔 때마다 다시 렌더하지 않아도 된다.
    ///
    /// **`px` 를 적지 않는다** — 글꼴은 `font: -apple-system-body` 가 Dynamic Type 을
    /// 저절로 따라간다 (설계서 §8).
    static func cssTokens() -> String {
        """
        :root { color-scheme: light dark; }
        :root {
        \(variables(dark: false))
        }
        @media (prefers-color-scheme: dark) {
          :root {
        \(variables(dark: true))
          }
        }
        """
    }

    private static func variables(dark: Bool) -> String {
        let traits = UITraitCollection(userInterfaceStyle: dark ? .dark : .light)
        func hex(_ color: UIColor) -> String {
            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            color.resolvedColor(with: traits).getRed(&r, green: &g, blue: &b, alpha: &a)
            let clamp = { (v: CGFloat) in Int((max(0, min(1, v)) * 255).rounded()) }
            return String(format: "#%02X%02X%02X", clamp(r), clamp(g), clamp(b))
        }
        return """
          --yb-paper: \(hex(.systemBackground));
          --yb-paper-raised: \(hex(.secondarySystemBackground));
          --yb-ink: \(hex(.label));
          --yb-ink-faint: \(hex(.secondaryLabel));
          --yb-accent: \(hex(.tintColor));
          --yb-rule: \(hex(.separator));
          --yb-tag: \(hex(tagUIColor));
          --yb-quote: \(hex(quoteUIColor));
        """
    }
}
