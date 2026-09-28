import Foundation
import Markdown

/// 읽기 화면의 블록 하나가 **원문 몇째 줄부터 몇째 줄까지**인가 (176).
public struct LineBlock: Equatable, Sendable {
    /// `p` · `h1`~`h6` · `li` · `blockquote` · `pre` · `table` · `tr` · `hr`
    public let tag: String
    /// 원문 기준 줄 번호, 0 부터. **머리말 줄도 센다** — 편집기의 글과 같은 번호다.
    public let line: Int
    /// 비지 않은 마지막 줄.
    public let lineEnd: Int

    public init(tag: String, line: Int, lineEnd: Int) {
        self.tag = tag
        self.line = line
        self.lineEnd = lineEnd
    }
}

/// **읽기 ↔ 쓰기를 오가도 보던 자리를 잇는다** (176, 2026-09-28 사용자 — *편집 모드를 누르면
/// 다시 처음부터 가서 고칠 곳을 찾아야 한다*).
///
/// 두 화면을 잇는 값은 **원문 줄 번호 하나**다. 편집기의 글은 원문 그대로라(ADR-0005) 줄 번호가
/// 곧 편집기 자리다 — 두 문자열을 잇는 매핑이 따로 없다.
///
/// 읽기 HTML 의 블록마다 `data-line` · `data-line-end` 를 붙이고, 웹뷰는 맨 위 블록의 **순번과
/// 그 안에서 내려온 비율**을 말한다. 순번은 이 표(`blocks`)의 순번과 같다 — 둘 다 문서 순서다.
///
/// 기댓값은 `Tools/golden/generate.py` 의 `lineMapCases` (markdown-it 의 `token.map` 으로 따로 계산).
public enum LineMap {

    /// 원문(머리말 포함) → 블록 표. 문서 순서.
    public static func blocks(markdown: String) -> [LineBlock] {
        let parsed = parse(markdown)
        return parsed.entries.compactMap(\.block)
    }

    /// 편집기 맨 위 줄 → (블록 순번 · 그 안의 비율). 품은 블록이 여럿이면 **가장 안쪽**
    /// (문서 순서로 마지막). 블록 사이의 빈 줄은 다음 블록의 머리, 끝의 빈 줄은 마지막 블록의 끝.
    public static func anchor(forLine line: Int, in blocks: [LineBlock]) -> (index: Int, fraction: Double)? {
        if let index = blocks.indices.last(where: { blocks[$0].line <= line && line <= blocks[$0].lineEnd }) {
            let block = blocks[index]
            return (index, Double(line - block.line) / Double(block.lineEnd - block.line + 1))
        }
        if let index = blocks.indices.first(where: { blocks[$0].line > line }) {
            return (index, 0)
        }
        guard !blocks.isEmpty else { return nil }
        return (blocks.count - 1, 1)
    }

    /// 읽기 화면 맨 위 블록 · 비율 → 편집기 맨 위에 둘 줄.
    public static func line(forBlock index: Int, fraction: Double, in blocks: [LineBlock]) -> Int? {
        guard blocks.indices.contains(index) else { return nil }
        let block = blocks[index]
        let span = block.lineEnd - block.line + 1
        let step = Int((fraction * Double(span) + 1e-9).rounded(.down))
        return block.line + min(max(step, 0), span - 1)
    }

    /// 렌더한 HTML 의 블록 여는 태그에 줄 범위를 붙인다. **짝이 하나라도 안 맞으면 손대지
    /// 않고 그대로 돌려준다** — 그러면 앱은 비율로 물러선다. 틀린 줄로 데려가는 것보다 낫다.
    static func annotate(_ html: String, markdown: String) -> String {
        let expected = parse(markdown).entries
        guard !expected.isEmpty else { return html }
        let pattern = #"<(p|h[1-6]|li|blockquote|pre|table|tr|hr)(?=[\s>/])"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return html }
        let text = html as NSString
        let found = regex.matches(in: html, range: NSRange(location: 0, length: text.length))
        guard found.count == expected.count else { return html }

        var out = ""
        var cursor = 0
        for (match, entry) in zip(found, expected) {
            let tag = text.substring(with: match.range(at: 1))
            guard tag == entry.tag else { return html }
            let end = match.range.location + match.range.length
            out += text.substring(with: NSRange(location: cursor, length: end - cursor))
            if let block = entry.block {
                out += " data-line=\"\(block.line)\" data-line-end=\"\(block.lineEnd)\""
            }
            cursor = end
        }
        out += text.substring(from: cursor)
        return out
    }

    // MARK: - 속

    /// `HTMLFormatter` 가 내는 **블록 여는 태그의 순서** 그대로. 날 HTML 블록은 `NoteRewriter` 가
    /// 글자로 바꿔 `<p>` 하나로 내므로 자리만 차지하고(줄 범위 없음) 표에는 안 들어간다.
    struct Entry {
        let tag: String
        let block: LineBlock?
    }

    struct Parsed {
        let entries: [Entry]
    }

    static func parse(_ markdown: String) -> Parsed {
        let body = FrontMatterParser.parse(markdown).body
        let offset = markdown.components(separatedBy: "\n").count - body.components(separatedBy: "\n").count
        let lines = body.components(separatedBy: "\n")
        let document = Document(parsing: body, options: [.disableSmartOpts])
        var walker = Walker(offset: offset, lines: lines)
        walker.visit(document)
        return Parsed(entries: walker.entries)
    }

    private struct Walker: MarkupWalker {
        let offset: Int
        let lines: [String]
        var entries: [Entry] = []

        init(offset: Int, lines: [String]) {
            self.offset = offset
            self.lines = lines
        }

        private mutating func record(_ tag: String, _ markup: Markup) {
            guard let range = markup.range else {
                entries.append(Entry(tag: tag, block: nil))
                return
            }
            // swift-markdown 의 줄은 1 부터다.
            let start = range.lowerBound.line - 1
            var last = max(start, min(range.upperBound.line - 1, lines.count - 1))
            while last > start,
                  lines[last].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                last -= 1
            }
            entries.append(Entry(tag: tag, block: LineBlock(tag: tag, line: start + offset,
                                                            lineEnd: last + offset)))
        }

        mutating func visitParagraph(_ paragraph: Paragraph) {
            record("p", paragraph)
            descendInto(paragraph)
        }

        mutating func visitHeading(_ heading: Heading) {
            record("h\(heading.level)", heading)
            descendInto(heading)
        }

        mutating func visitListItem(_ listItem: ListItem) {
            record("li", listItem)
            descendInto(listItem)
        }

        mutating func visitBlockQuote(_ blockQuote: BlockQuote) {
            record("blockquote", blockQuote)
            descendInto(blockQuote)
        }

        mutating func visitCodeBlock(_ codeBlock: CodeBlock) {
            record("pre", codeBlock)
        }

        mutating func visitThematicBreak(_ thematicBreak: ThematicBreak) {
            record("hr", thematicBreak)
        }

        mutating func visitTable(_ table: Table) {
            record("table", table)
            descendInto(table)
        }

        mutating func visitTableHead(_ tableHead: Table.Head) {
            record("tr", tableHead)
        }

        mutating func visitTableRow(_ tableRow: Table.Row) {
            record("tr", tableRow)
        }

        mutating func visitHTMLBlock(_ html: HTMLBlock) {
            entries.append(Entry(tag: "p", block: nil))
        }
    }
}
