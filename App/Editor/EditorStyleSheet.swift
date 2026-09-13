import UIKit
import Core

/// `LineStyler` 가 낸 구간을 **속성**으로 바꾼다 (ADR-0005 L1).
///
/// 글자는 하나도 지우거나 바꿔 넣지 않는다. 보이는 모습의 차이는 전부 여기서 나온다.
/// 그래서 저장은 `textStorage.string` 을 그대로 쓰면 끝이다.
///
/// **값을 미리 뽑아 둔다.** 만드는 것은 주 액터에서 한 번뿐이고, 다시 칠할 때는
/// UIKit 에 되묻지 않는다 — `NSTextStorage` 는 주 액터가 아니기 때문이다.
/// Dynamic Type 이 바뀌면 새로 만들어 갈아 끼운다.
struct EditorStyleSheet {

    let body: UIFont
    let mono: UIFont
    /// 1~6단계 제목.
    let headings: [UIFont]

    let ink: UIColor
    /// 마크다운 마커. **L1 은 흐리게만 한다** — 지우지도 숨기지도 않는다.
    let markerInk: UIColor
    let quoteInk: UIColor
    let linkInk: UIColor
    let codeBackground: UIColor

    let plainParagraph: NSParagraphStyle
    let headingParagraph: NSParagraphStyle
    let quoteParagraph: NSParagraphStyle
    let monoParagraph: NSParagraphStyle

    /// 목록은 겹친 단계마다 새로 만든다. 값만 미리 재어 둔다 (주 액터 밖에서 쓰므로).
    let lineSpacing: CGFloat
    let paragraphSpacing: CGFloat
    /// 목록 줄이 시작하는 자리. **보통 문단보다 안쪽**이라야 목록으로 보인다 (빌드 7 · 4번).
    let listIndent: CGFloat
    /// 접힌 둘째 줄이 마커가 아니라 **글**에 맞춰지도록 더 들어가는 폭.
    let listHanging: CGFloat
    /// `  - 안쪽` 처럼 겹칠 때 한 단계마다.
    let nestStep: CGFloat

    /// 숫자는 `Metrics.scaledLength` 하나로 통한다 (CLAUDE.md §1).
    @MainActor
    init() {
        body = .preferredFont(forTextStyle: .body)
        mono = UIFontMetrics(forTextStyle: .body)
            .scaledFont(for: .monospacedSystemFont(ofSize: 16, weight: .regular))

        func sized(_ style: UIFont.TextStyle, _ weight: UIFont.Weight) -> UIFont {
            .systemFont(ofSize: UIFont.preferredFont(forTextStyle: style).pointSize, weight: weight)
        }
        let small = sized(.headline, .semibold)
        headings = [sized(.title1, .bold), sized(.title2, .bold), sized(.title3, .semibold),
                    small, small, small]

        ink = .label
        markerInk = .tertiaryLabel
        quoteInk = .secondaryLabel
        linkInk = .tintColor
        codeBackground = .secondarySystemBackground

        let spacing = Metrics.scaledLength(2)
        let after = Metrics.scaledLength(6)
        lineSpacing = spacing
        paragraphSpacing = after
        listIndent = Metrics.scaledLength(10)
        listHanging = Metrics.scaledLength(20)
        nestStep = Metrics.scaledLength(16)

        func paragraph(_ build: (NSMutableParagraphStyle) -> Void) -> NSParagraphStyle {
            let style = NSMutableParagraphStyle()
            style.lineSpacing = spacing
            style.paragraphSpacing = after
            build(style)
            return style
        }

        plainParagraph = paragraph { _ in }
        headingParagraph = paragraph { $0.paragraphSpacingBefore = Metrics.scaledLength(10) }
        quoteParagraph = paragraph {
            $0.firstLineHeadIndent = Metrics.scaledLength(12)
            $0.headIndent = Metrics.scaledLength(12)
        }
        // 코드와 표는 접히면 읽을 수 없다. 글자 단위로 접어 표 칸이 어긋나지 않게 한다.
        monoParagraph = paragraph { $0.lineBreakMode = .byCharWrapping }
    }

    // MARK: - 문단 전체

    func font(for block: StyleToken?) -> UIFont {
        switch block {
        case .heading1: return headings[0]
        case .heading2: return headings[1]
        case .heading3: return headings[2]
        case .heading4: return headings[3]
        case .heading5: return headings[4]
        case .heading6: return headings[5]
        case .codeBlock, .tableRow: return mono
        default: return body
        }
    }

    /// `depth` 는 목록이 겹친 단계 (`  - 안쪽` 이면 1).
    func paragraphStyle(for block: StyleToken?, depth: Int = 0) -> NSParagraphStyle {
        switch block {
        case .heading1, .heading2, .heading3, .heading4, .heading5, .heading6: return headingParagraph
        case .listItem, .orderedItem:
            let style = NSMutableParagraphStyle()
            style.lineSpacing = lineSpacing
            style.paragraphSpacing = paragraphSpacing
            let start = listIndent + nestStep * CGFloat(max(0, depth))
            style.firstLineHeadIndent = start
            style.headIndent = start + listHanging
            return style
        case .quote: return quoteParagraph
        case .codeBlock, .tableRow: return monoParagraph
        default: return plainParagraph
        }
    }

    /// 문단 전체에 먼저 까는 것. 그 위에 강조 구간과 마커가 덮인다.
    func base(for block: StyleToken?, depth: Int = 0) -> [NSAttributedString.Key: Any] {
        [
            .font: font(for: block),
            .foregroundColor: block == .quote ? quoteInk : ink,
            .paragraphStyle: paragraphStyle(for: block, depth: depth),
        ]
    }

    /// 머리말(`---` … `---`). 통째로 흐린 고정폭 — 본문이 아니라는 것이 한눈에 보이게.
    func frontMatter() -> [NSAttributedString.Key: Any] {
        [.font: mono, .foregroundColor: markerInk, .paragraphStyle: monoParagraph]
    }

    // MARK: - 문단 안쪽

    /// 한 구간에 거는 것. **글꼴을 갈아 끼우지 않고 굵기 · 기울기만 더한다** —
    /// `**굵고 *기운* 글**` 이 굵고 기운 글이 되려면 겹쳐 쌓여야 한다.
    func apply(_ token: StyleToken, to text: NSMutableAttributedString, range: NSRange) {
        switch token {
        case .strong:
            addTraits(.traitBold, to: text, range: range)
        case .emphasis:
            addTraits(.traitItalic, to: text, range: range)
        case .strikethrough:
            text.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: range)
        case .inlineCode:
            text.addAttribute(.font, value: mono, range: range)
            text.addAttribute(.backgroundColor, value: codeBackground, range: range)
        case .link, .image:
            text.addAttribute(.foregroundColor, value: linkInk, range: range)
        default:
            break
        }
    }

    /// 마커를 흐리게. L2 는 여기만 바꾸면 숨겨진다.
    func dimMarker(in text: NSMutableAttributedString, range: NSRange) {
        text.addAttribute(.foregroundColor, value: markerInk, range: range)
    }

    private func addTraits(_ traits: UIFontDescriptor.SymbolicTraits,
                           to text: NSMutableAttributedString, range: NSRange) {
        text.enumerateAttribute(.font, in: range, options: []) { value, subrange, _ in
            let current = (value as? UIFont) ?? body
            let merged = current.fontDescriptor.symbolicTraits.union(traits)
            guard let descriptor = current.fontDescriptor.withSymbolicTraits(merged) else { return }
            text.addAttribute(.font, value: UIFont(descriptor: descriptor, size: current.pointSize),
                              range: subrange)
        }
    }
}
