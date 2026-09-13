import UIKit
import Core

/// 마크다운 원문 **하나**를 들고, 보이는 모습은 속성으로만 낸다 (ADR-0005).
///
/// **이 앱에서 가장 조심할 자리다.** 원문과 보이는 것 두 문자열을 매핑하지 않는
/// 이유가 여기 있다 — 매핑 버그는 곧 자료 손상이다. `string` 은 언제나 사용자가
/// 친 그대로이고, 저장은 그것을 그대로 쓴다.
///
/// **직접 만드는 생성자를 두지 않는다.** `NSTextStorage` 는 `NSCoding` 과
/// `NSItemProviderReading` 을 타고 required 생성자가 여럿 딸려 온다. 하나라도
/// 직접 만들면 그것을 다 적어야 한다. 그래서 `sheet` 는 만든 뒤에 끼운다.
final class MarkdownTextStorage: NSTextStorage {

    private let backing = NSMutableAttributedString()

    /// 주 액터에서 만들어 끼운다. 없으면 칠하지 않는다 (글자는 그대로 보인다).
    var sheet: EditorStyleSheet?

    /// 한글 조합 중에는 속성을 건드리지 않는다. 조합 중 속성 갱신은 조합을 끊는다
    /// — 자음과 모음이 따로 찍힌다 (안정화 기준 S10).
    var isComposing = false

    // MARK: - NSTextStorage 가 요구하는 네 가지

    override var string: String { backing.string }

    override func attributes(at location: Int,
                             effectiveRange range: NSRangePointer?) -> [NSAttributedString.Key: Any] {
        backing.attributes(at: location, effectiveRange: range)
    }

    override func replaceCharacters(in range: NSRange, with str: String) {
        beginEditing()
        backing.replaceCharacters(in: range, with: str)
        edited(.editedCharacters, range: range,
               changeInLength: (str as NSString).length - range.length)
        endEditing()
    }

    override func setAttributes(_ attrs: [NSAttributedString.Key: Any]?, range: NSRange) {
        beginEditing()
        backing.setAttributes(attrs, range: range)
        edited(.editedAttributes, range: range, changeInLength: 0)
        endEditing()
    }

    // MARK: - 다시 칠하기

    /// **고친 문단만** 다시 칠한다. 전체 재칠은 파일을 열 때 한 번뿐이다 (S11).
    ///
    /// 속성은 `processEditing` 안에서만 바꾼다. 밖에서 바꾸면 되돌리기 스택이
    /// 속성 변경까지 기록해 `⌘Z` 가 이상해진다.
    override func processEditing() {
        if editedMask.contains(.editedCharacters), !isComposing {
            restyle(paragraphsTouching: editedRange)
        }
        super.processEditing()
    }

    /// 원문을 통째로 갈아 끼운다 (다른 노트를 열 때). 재칠은 `processEditing` 이 한다.
    func load(_ text: String) {
        replaceCharacters(in: NSRange(location: 0, length: backing.length), with: text)
    }

    /// 파일을 열 때 · Dynamic Type 이 바뀔 때 · 조합이 끝났을 때.
    func restyleAll(sheet: EditorStyleSheet? = nil) {
        if let sheet { self.sheet = sheet }
        beginEditing()
        restyle(in: NSRange(location: 0, length: backing.length))
        endEditing()
    }

    /// 한글 조합이 끝난 뒤 그 문단만. 조합 중에 건너뛴 재칠을 여기서 갚는다.
    func restyleParagraph(containing location: Int) {
        beginEditing()
        restyle(paragraphsTouching: NSRange(location: min(location, backing.length), length: 0))
        endEditing()
    }

    private func restyle(paragraphsTouching range: NSRange) {
        let touched = (backing.string as NSString).paragraphRange(for: range)
        restyle(in: touched)
    }

    // MARK: - 문단 단위

    private func restyle(in range: NSRange) {
        guard sheet != nil else { return }
        let text = backing.string as NSString
        guard text.length > 0 else { return }

        var location = min(max(0, range.location), text.length - 1)
        let limit = min(NSMaxRange(range), text.length)

        repeat {
            let paragraph = text.paragraphRange(for: NSRange(location: location, length: 0))
            style(paragraph: paragraph, in: text)
            let next = NSMaxRange(paragraph)
            // 문단이 앞으로 안 가면 멈춘다 — 무한 반복 막이.
            if next <= location { break }
            location = next
        } while location < limit && location < text.length

        edited(.editedAttributes, range: range, changeInLength: 0)
    }

    private func style(paragraph: NSRange, in text: NSString) {
        guard let sheet else { return }

        // `paragraphRange` 는 끝의 줄바꿈까지 준다. `LineStyler` 는 줄 하나만 본다.
        var line = paragraph
        if line.length > 0, text.character(at: NSMaxRange(line) - 1) == 0x0A {
            line.length -= 1
        }
        let style = LineStyler.style(paragraph: text.substring(with: line))

        backing.setAttributes(sheet.base(for: style.block), range: paragraph)

        for span in style.inlineSpans {
            let range = NSRange(location: line.location + span.start, length: span.length)
            guard NSMaxRange(range) <= NSMaxRange(line) else { continue }
            sheet.apply(span.token, to: backing, range: range)
        }
        for mark in style.markers {
            let range = NSRange(location: line.location + mark.start, length: mark.length)
            guard NSMaxRange(range) <= NSMaxRange(line) else { continue }
            sheet.dimMarker(in: backing, range: range)
        }
    }
}
