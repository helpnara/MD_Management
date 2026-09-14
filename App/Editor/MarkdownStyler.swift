import UIKit
import Core

/// 마크다운 원문에 **속성만** 건다 (ADR-0005 L1).
///
/// 글자는 하나도 지우거나 바꿔 넣지 않는다. 보이는 모습의 차이는 전부 속성이다.
/// 그래서 저장은 `textStorage.string` 을 그대로 쓰면 끝이고, 매핑 버그가 생길
/// 자리가 없다.
///
/// **`NSTextStorage` 를 상속하지 않는다.** 빌드 7 에서 직접 조립한 TextKit 2
/// 더미(`NSTextContentStorage` + `NSTextLayoutManager` + 커스텀 저장소)가 빈
/// 화면을 냈다 — 오류 하나 없이. 여기서는 컴파일해 볼 수 없는 조립이라 위험이
/// 크다. `UITextView(usingTextLayoutManager:)` 가 만들어 준 저장소에
/// **대리자로 붙는 쪽**이 훨씬 단순하고, `didProcessEditing` 은 속성을 바꾸라고
/// 애플이 정해 둔 바로 그 자리다.
enum MarkdownStyler {

    /// 고친 문단만 다시 칠한다. 전체 재칠은 파일을 열 때 한 번뿐이다 (S11).
    ///
    /// `previousHeader` 는 지난번 머리말 길이. **머리말이 생기거나 없어지거나 길이가
    /// 바뀌면 그 구간을 통째로 다시 칠한다.** `---` → `title:` → `---` 순으로 치면
    /// 마지막 `---` 를 친 순간에야 머리말이 생기는데, 고친 문단만 칠하면 위의
    /// `title:` 은 머리말 없던 시절 모습으로 남는다 (빌드 10 · 4번 "될 때도 안 될 때도").
    /// 새 머리말 길이를 돌려준다 — 부른 쪽이 들고 있다가 다음에 넘긴다.
    ///
    /// `cursor` 는 커서 자리 (UTF-16). 그 문단은 마커를 흐리게(L1), 나머지는 숨긴다(L2).
    /// `nil` 이면 다 흐리게(L1) — 커서를 모를 때(전체 다시 칠하기)만.
    @discardableResult
    static func restyle(_ storage: NSTextStorage, touching range: NSRange,
                        with sheet: EditorStyleSheet, previousHeader: Int = 0,
                        cursor: Int? = nil) -> Int {
        let text = storage.string as NSString
        guard text.length > 0 else { return 0 }

        // 머리말은 문서 첫머리라는 문맥이 있어야 안다. 한 번 재어 두고 문단마다 가린다.
        let header = FrontMatterParser.headerLength(of: storage.string)
        var touched = text.paragraphRange(for: clamp(range, to: text.length))
        if header != previousHeader {
            let widest = min(max(header, previousHeader), text.length)
            let headerRange = text.paragraphRange(for: NSRange(location: 0, length: widest))
            touched = NSUnionRange(touched, headerRange)
        }
        var location = touched.location
        let limit = NSMaxRange(touched)

        repeat {
            let paragraph = text.paragraphRange(for: NSRange(location: min(location, text.length - 1), length: 0))
            if paragraph.location < header {
                storage.setAttributes(sheet.frontMatter(), range: paragraph)
            } else {
                // 커서가 이 문단에 있나. 문단 끝(줄바꿈 앞)까지, 마지막 문단은 글 끝까지.
                let hasCursor = cursor.map { at in
                    at >= paragraph.location
                        && (at < NSMaxRange(paragraph) || NSMaxRange(paragraph) == text.length)
                } ?? true
                style(paragraph: paragraph, in: text, storage: storage, sheet: sheet, hasCursor: hasCursor)
            }
            let next = NSMaxRange(paragraph)
            // 문단이 앞으로 안 가면 멈춘다 — 무한 반복 막이.
            if next <= location { break }
            location = next
        } while location < limit && location < text.length
        return header
    }

    @discardableResult
    static func restyleAll(_ storage: NSTextStorage, with sheet: EditorStyleSheet, cursor: Int? = nil) -> Int {
        restyle(storage, touching: NSRange(location: 0, length: storage.length), with: sheet, cursor: cursor)
    }

    private static func clamp(_ range: NSRange, to length: Int) -> NSRange {
        let location = max(0, min(range.location, max(0, length - 1)))
        return NSRange(location: location, length: min(range.length, length - location))
    }

    private static func style(paragraph: NSRange, in text: NSString,
                              storage: NSTextStorage, sheet: EditorStyleSheet, hasCursor: Bool) {
        // `paragraphRange` 는 끝의 줄바꿈까지 준다. `LineStyler` 는 줄 하나만 본다.
        var line = paragraph
        if line.length > 0, text.character(at: NSMaxRange(line) - 1) == 0x0A {
            line.length -= 1
        }
        let style = LineStyler.style(paragraph: text.substring(with: line))

        // 목록: 겹친 단계는 마커 앞의 빈칸 수로 (둘에 한 단계), 매달린 들여쓰기는
        // **실제 마커 폭**으로. `- ` · `1. ` · `- [ ] ` 가 다 달라서 고정값이면 어긋난다
        // (빌드 8 · 10번).
        var depth = 0
        var markerWidth: CGFloat = 0
        if style.block == .listItem || style.block == .orderedItem,
           let marker = style.markers.first {
            depth = marker.start / 2
            let prefix = text.substring(with: NSRange(location: line.location + marker.start,
                                                      length: style.contentStart - marker.start))
            markerWidth = (prefix as NSString).size(withAttributes: [.font: sheet.body]).width
        }
        storage.setAttributes(sheet.base(for: style.block, depth: depth, markerWidth: markerWidth),
                              range: paragraph)

        for span in style.inlineSpans {
            let range = NSRange(location: line.location + span.start, length: span.length)
            guard NSMaxRange(range) <= NSMaxRange(line) else { continue }
            sheet.apply(span.token, to: storage, range: range)
        }
        // L2 — 커서가 없는 문단은 마커를 숨긴다. 다만:
        //  · 목록 마커(`- ` `1. ` `[ ]`)와 수평선은 **안 숨긴다** — 번호가 사라지면 정보가
        //    사라진다. 그 자리는 L3 가 기호로 바꾼다.
        //  · 대체 글자 없는 그림(`![](…)`)이 있는 문단도 안 숨긴다 — 줄이 통째로 사라진다.
        let isList = style.block == .listItem || style.block == .orderedItem
        let keepsAll = hasCursor || style.block == .thematicBreak
            || style.inlineSpans.contains { $0.token == .image && $0.length == 0 }
        for mark in style.markers {
            let range = NSRange(location: line.location + mark.start, length: mark.length)
            guard NSMaxRange(range) <= NSMaxRange(line) else { continue }
            let isBlockMarker = mark.start < style.contentStart
            if keepsAll || (isList && isBlockMarker) {
                sheet.dimMarker(in: storage, range: range)
            } else {
                sheet.hideMarker(in: storage, range: range)
            }
        }
    }
}
