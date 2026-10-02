import UIKit
import Core

/// **늘 보이는 스크롤 막대** (202) — 오른쪽 가장자리에 가는 막대. 길이는 노트가 얼마나 긴지, 자리는 지금 어디쯤인지.
///
/// 쓰기 화면(`UITextView`)과 읽기 화면(`WKWebView` 의 `scrollView`)에 **같은 것**을 붙인다. 막대의 길이 · 자리 셈은 Core 의
/// `ScrollGauge.thumb` 하나다. 스크롤 뷰의 **자식**으로 붙어 화면과 함께 움직이므로, 자리를 매번 지금 보이는 칸에 맞춰 놓는다
/// (iOS 의 스크롤 표시가 하는 방식).
///
/// **막대는 하나다** (빌드 72 · 10번, 2026-10-02 사용자 — *iOS 기본 스크롤과 앱 자체 스크롤이 꼭 2개여야 해? 상식과 벗어난다*).
/// iOS 의 스크롤 표시는 멈추면 사라지고 늘 켜 두는 설정이 없어 이 막대를 그렸다. 빌드 72 는 iOS 표시를 살려 두고 미는 동안
/// 이 막대가 비켜 주게 했는데, 한 가지를 두 모양이 번갈아 보여 주었다. 이제 **iOS 표시를 끄고** 이 막대가 밀 때도 손을 따라
/// 움직인다. 잃는 것은 iOS 표시를 길게 눌러 끄는 빠른 넘기기 하나. 누름은 받지 않는다 — 글 고르기 · 링크 누르기를 가로채지 않게.
@MainActor
final class ScrollGaugeView: UIView {

    private weak var scrollView: UIScrollView?
    private var observations: [NSKeyValueObservation] = []
    private let thumb = UIView()

    /// 스크롤 뷰에 막대를 붙인다. 막대는 스크롤 뷰의 자식이라 따로 붙들어 둘 필요가 없다.
    @discardableResult
    static func attach(to scrollView: UIScrollView) -> ScrollGaugeView {
        let gauge = ScrollGaugeView(frame: .zero)
        gauge.isUserInteractionEnabled = false
        gauge.isAccessibilityElement = false
        gauge.backgroundColor = UIColor.label.withAlphaComponent(0.08)
        gauge.thumb.backgroundColor = .secondaryLabel
        gauge.addSubview(gauge.thumb)
        gauge.isHidden = true
        scrollView.showsVerticalScrollIndicator = false
        scrollView.addSubview(gauge)
        gauge.scrollView = scrollView
        gauge.observations = [
            scrollView.observe(\.contentOffset, options: []) { [weak gauge] _, _ in
                MainActor.assumeIsolated { gauge?.update() }
            },
            scrollView.observe(\.contentSize, options: []) { [weak gauge] _, _ in
                MainActor.assumeIsolated { gauge?.update() }
            },
            scrollView.observe(\.bounds, options: []) { [weak gauge] _, _ in
                MainActor.assumeIsolated { gauge?.update() }
            },
        ]
        gauge.update()
        return gauge
    }

    private func update() {
        guard let scrollView else { return }
        let inset = scrollView.adjustedContentInset
        let width = Metrics.scaledLength(3)
        let margin = Metrics.scaledLength(4)
        let viewport = scrollView.bounds.height - inset.top - inset.bottom
        let track = viewport - margin * 2
        guard let shape = ScrollGauge.thumb(content: Double(scrollView.contentSize.height),
                                            viewport: Double(viewport),
                                            offset: Double(scrollView.contentOffset.y + inset.top),
                                            track: Double(track),
                                            minimum: Double(Metrics.scaledLength(28))) else {
            isHidden = true
            return
        }
        isHidden = false
        frame = CGRect(x: scrollView.bounds.maxX - width - Metrics.scaledLength(2) - inset.right,
                       y: scrollView.bounds.minY + inset.top + margin,
                       width: width, height: track)
        layer.cornerRadius = width / 2
        thumb.frame = CGRect(x: 0, y: CGFloat(shape.start), width: width, height: CGFloat(shape.length))
        thumb.layer.cornerRadius = width / 2
        // 글 조각들이 새로 붙어도 막대가 그 위에 오게.
        scrollView.bringSubviewToFront(self)
    }
}
