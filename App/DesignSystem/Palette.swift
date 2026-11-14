import SwiftUI
import UIKit

// 색은 여기서만 정한다. 화면에서 색을 직접 적지 않는다.
//
// 지난 앱에서 화면마다 다크 모드 톤이 제각각이었다. 뷰어(WKWebView)의 CSS 도 같은
// 토큰을 `--yb-*` 변수로 받아 앱과 웹뷰가 함께 간다 (ADR-0004 · 설계서 §8).

@MainActor
enum Palette {
    // **종이와 먹** (316, 2026-11-12 사용자 — *앱 디자인에 조금 더 신경써서 항상 고급스럽게*). 예전에는 iOS 기본(흰 바탕 · 새까만 바탕 ·
    // 시스템 파랑)을 그대로 썼다 — 아이콘 · 홍보 영상의 따뜻한 종이 · 먹 · 잎과 앱이 따로 놀았다. 색은 **모두 이 파일에서** 두 벌(어두움 · 밝음)로
    // 정하고, 대비는 `Tools/contrast.py` 가 이 파일을 읽어 센다 (손으로 세지 않는다 · 바탕도 이 파일에서 읽는다). ADR-0010.

    /// 종이 — 바탕
    static let paper = Color(uiColor: paperUIColor)
    /// 한 겹 올라온 종이 — 코드 · 찾기 칸 · 띠 · 묶음 목록의 칸
    static let paperRaised = Color(uiColor: paperRaisedUIColor)
    /// 먹 — 본문 글자
    static let ink = Color(uiColor: inkUIColor)
    /// 옅은 먹 — 보조 설명 · 날짜
    static let inkFaint = Color(uiColor: inkFaintUIColor)
    /// 마크다운 마커(`#` `**` `-`)를 흐리게 보일 때 (라이브 편집기 L1)
    static let marker = Color(uiColor: markerUIColor)
    /// 강조 — 링크 · 선택 · 스위치 · 할 일 상자. **잎 초록** (316 · 사용자 *잎 초록*) — 아이콘의 새싹 색
    static let accent = Color(uiColor: accentUIColor)
    /// 인용 세로선 · 구분선
    static let rule = Color(uiColor: ruleUIColor)
    /// 입력 칸 바탕 — 찾기 칸 (265 · 266). 종이 위에서 한 단 짙게.
    static let fill = Color(uiColor: fillUIColor)
    /// 묶음 목록의 바탕 — 폴더 화면 · 설정. 칸(`paperRaised` 가 아니라 `paper`)이 이 위에 선다.
    static let paperGrouped = Color(uiColor: paperGroupedUIColor)
    /// `#태그` (T2). 편집기와 뷰어가 같은 색을 쓴다.
    static let tag = Color(uiColor: tagUIColor)

    /// **인용 글자** (191). 편집기와 뷰어가 **같은 색 하나**를 쓴다. 316 — 파랑이던 것을 잎 초록과 어울리는 **옅은 먹**으로 (세로선은 잎 초록).
    static let quote = Color(uiColor: quoteUIColor)

    static let paperUIColor = UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.106, green: 0.102, blue: 0.094, alpha: 1)    // 어두운 바탕 — #1B1A18
            : UIColor(red: 0.980, green: 0.969, blue: 0.945, alpha: 1)    // 밝은 바탕 — #FAF7F1
    }

    static let paperRaisedUIColor = UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.149, green: 0.141, blue: 0.125, alpha: 1)    // 어두운 바탕 — #262420
            : UIColor(red: 0.945, green: 0.925, blue: 0.890, alpha: 1)    // 밝은 바탕 — #F1ECE3
    }

    static let paperGroupedUIColor = UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.071, green: 0.067, blue: 0.063, alpha: 1)    // 어두운 바탕 — #121110
            : UIColor(red: 0.953, green: 0.937, blue: 0.910, alpha: 1)    // 밝은 바탕 — #F3EFE8
    }

    static let inkUIColor = UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.925, green: 0.906, blue: 0.875, alpha: 1)    // 어두운 바탕 — #ECE7DF
            : UIColor(red: 0.141, green: 0.129, blue: 0.118, alpha: 1)    // 밝은 바탕 — #24211E
    }

    static let inkFaintUIColor = UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.647, green: 0.620, blue: 0.576, alpha: 1)    // 어두운 바탕 — #A59E93
            : UIColor(red: 0.420, green: 0.396, blue: 0.361, alpha: 1)    // 밝은 바탕 — #6B655C
    }

    /// 마커는 글자가 아니라 표시라 대비 4.5 를 묻지 않는다 — 흐리게 보이는 것이 일이다.
    static let markerUIColor = UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.420, green: 0.396, blue: 0.361, alpha: 1)    // #6B655C
            : UIColor(red: 0.690, green: 0.663, blue: 0.616, alpha: 1)    // #B0A99D
    }

    static let accentUIColor = UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.612, green: 0.796, blue: 0.431, alpha: 1)    // 어두운 바탕 — #9CCB6E
            : UIColor(red: 0.290, green: 0.455, blue: 0.161, alpha: 1)    // 밝은 바탕 — #4A7429
    }

    static let ruleUIColor = UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.925, green: 0.906, blue: 0.875, alpha: 0.12)
            : UIColor(red: 0.141, green: 0.129, blue: 0.118, alpha: 0.12)
    }

    static let fillUIColor = UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.925, green: 0.906, blue: 0.875, alpha: 0.10)
            : UIColor(red: 0.141, green: 0.129, blue: 0.118, alpha: 0.07)
    }

    static let quoteUIColor = UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.761, green: 0.729, blue: 0.682, alpha: 1)    // 어두운 바탕 — #C2BAAE
            : UIColor(red: 0.361, green: 0.337, blue: 0.302, alpha: 1)    // 밝은 바탕 — #5C564D
    }

    /// `#태그` 색. 대비는 `Tools/contrast.py` 가 센다 — 밝은 바탕은 예전 `#B88500` 이 3.3:1 이라 4.5 에 못 미쳐 짙게 했다 (232).
    /// 316 — 종이가 흰색보다 어두워져 한 단 더 짙게.
    static let tagUIColor = UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 1.00, green: 0.84, blue: 0.35, alpha: 1)       // 어두운 바탕 — #FFD659
            : UIColor(red: 0.50, green: 0.36, blue: 0.00, alpha: 1)       // 밝은 바탕 — #805C00
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
        /// 투명도까지 넘긴다 (238). 가름선(`separator`)은 앱에서 반투명인데 `hex` 가 투명도를 버려 읽기 화면의 선이 짙었다.
        /// 글자 색(`secondaryLabel` 도 반투명)은 그대로 `hex` — 읽기 글이 옅어지면 대비가 4.5:1 아래로 내려간다.
        func rgba(_ color: UIColor) -> String {
            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            color.resolvedColor(with: traits).getRed(&r, green: &g, blue: &b, alpha: &a)
            let clamp = { (v: CGFloat) in Int((max(0, min(1, v)) * 255).rounded()) }
            return String(format: "rgba(%d, %d, %d, %.3f)", clamp(r), clamp(g), clamp(b), Double(max(0, min(1, a))))
        }
        return """
          --yb-paper: \(hex(paperUIColor));
          --yb-paper-raised: \(hex(paperRaisedUIColor));
          --yb-ink: \(hex(inkUIColor));
          --yb-ink-faint: \(hex(inkFaintUIColor));
          --yb-accent: \(hex(accentUIColor));
          --yb-rule: \(rgba(ruleUIColor));
          --yb-tag: \(hex(tagUIColor));
          --yb-quote: \(hex(quoteUIColor));
        """
    }
}
