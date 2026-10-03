import UIKit

/// **쓰기 화면의 코드 덩어리에 회색 바탕을 깐다** (210, 2026-10-03 사용자 — 읽기 화면처럼).
///
/// 글자 바탕색(`.backgroundColor`)으로 칠하면 **글자가 있는 만큼만** 칠해져 줄마다 길이가 들쭉날쭉하고,
/// 빈 줄 · 줄 사이는 비어 줄무늬가 된다. 읽기 화면의 덩어리는 화면 폭 전체의 상자다.
/// 그래서 칠하는 줄(`MarkdownStyler` 가 `.ybCodeBox` 를 단 줄)은 **줄 조각을 우리 것으로** 만들고,
/// 그 조각이 제 자리의 **글 상자 폭 전체**를 먼저 칠한 뒤 글자를 그린다. 조각은 위아래로 빈틈없이 쌓이므로
/// 이어진 코드 줄들은 상자 하나로 보인다. 글자는 하나도 안 바뀐다 — 속성만이다 (ADR-0005).
///
/// UIKit 이 이미 대리자를 달아 두었으면 **코드가 아닌 줄은 그쪽에 그대로 넘긴다.**
final class CodeBoxLayout: NSObject, NSTextLayoutManagerDelegate {

    /// 우리보다 먼저 달려 있던 대리자.
    weak var forwarded: (any NSTextLayoutManagerDelegate)?

    func textLayoutManager(_ textLayoutManager: NSTextLayoutManager,
                           textLayoutFragmentFor location: NSTextLocation,
                           in textElement: NSTextElement) -> NSTextLayoutFragment {
        if let paragraph = textElement as? NSTextParagraph,
           paragraph.attributedString.length > 0,
           let fill = paragraph.attributedString.attribute(.ybCodeBox, at: 0, effectiveRange: nil) as? UIColor {
            return CodeBoxFragment(textElement: textElement, range: textElement.elementRange, fill: fill)
        }
        if let forwarded,
           let fragment = forwarded.textLayoutManager?(textLayoutManager, textLayoutFragmentFor: location,
                                                       in: textElement) {
            return fragment
        }
        return NSTextLayoutFragment(textElement: textElement, range: textElement.elementRange)
    }
}

/// 글 상자 폭 전체를 칠하고 글자를 그리는 줄 조각.
final class CodeBoxFragment: NSTextLayoutFragment {

    private let fill: UIColor

    init(textElement: NSTextElement, range: NSTextRange?, fill: UIColor) {
        self.fill = fill
        super.init(textElement: textElement, range: range)
    }

    required init?(coder: NSCoder) {
        return nil
    }

    /// 조각 자리(왼쪽 위)에서 잰 상자 — 글 상자 왼쪽 끝부터 폭 전체, 조각 높이 전체.
    private var box: CGRect {
        let frame = layoutFragmentFrame
        var width = textLayoutManager?.textContainer?.size.width ?? frame.width
        // 글 상자가 폭을 안 따라가는 경우(아주 큰 값)에는 조각 폭으로 물러선다.
        if !width.isFinite || width > 100_000 { width = frame.width }
        return CGRect(x: -frame.minX, y: 0, width: width, height: frame.height)
    }

    override var renderingSurfaceBounds: CGRect {
        super.renderingSurfaceBounds.union(box)
    }

    override func draw(at point: CGPoint, in context: CGContext) {
        context.saveGState()
        // 색은 다크 모드를 따라간다 — 그리는 순간의 화면 모드로 푼다.
        context.setFillColor(fill.resolvedColor(with: UITraitCollection.current).cgColor)
        context.fill(box.offsetBy(dx: point.x, dy: point.y))
        context.restoreGState()
        super.draw(at: point, in: context)
    }
}

extension NSAttributedString.Key {
    /// 이 줄은 코드 덩어리다 — 값은 바탕색 (`UIColor`). `CodeBoxLayout` 이 본다 (210).
    static let ybCodeBox = NSAttributedString.Key("yb.codeBox")
}
