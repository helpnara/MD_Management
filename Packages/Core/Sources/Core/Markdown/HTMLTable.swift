import Foundation

/// **HTML 표 하나를 마크다운 표로** (159, 2026-09-22 사용자 — *생성형 AI 가 답변한
/// 내용의 표를 복사해서 붙여넣기*).
///
/// 클로드 · 쳇GPT 의 답에서 표를 복사하면 클립보드에 `<table>` 이 같이 실린다.
/// 평문 갈래에는 **칸 구분이 뭉개진 글자**만 와서 지금은 그것이 붙고 있다.
///
/// **표만 본다.** HTML 전체를 이해하지 않는다 — 목록 · 제목 · 코드까지 손대면
/// 붙여넣기가 **무엇을 할지 모르는 자리**가 된다. 표가 아니면 `nil` 을 내고
/// 부르는 쪽이 원문 그대로 붙인다.
///
/// 순수 함수다. 기댓값은 `Tools/golden/` 이 파이썬으로 따로 계산한다.
public enum HTMLTable {

    /// 칸 안에서 **마크다운 표를 깨뜨리는 글자**를 피한다.
    ///
    /// - `|` 는 칸을 가르는 글자다. 안 피하면 **칸이 쪼개진다.**
    /// - 줄바꿈은 마크다운 표의 칸에 못 들어간다. `<br>` 로 바꾼다.
    public static func escapeCell(_ text: String) -> String {
        var out = ""
        for character in text {
            if character == "|" { out.append("\\") }
            out.append(character)
        }
        return out
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\n", with: "<br>")
    }

    /// HTML 에서 **첫 번째 표**를 찾아 마크다운 표로 만든다. 표가 없으면 `nil`.
    ///
    /// **머리줄이 없으면 빈 머리줄을 세운다** — 마크다운 표는 머리줄 없이 못 선다.
    /// 병합된 칸(`colspan` · `rowspan`)은 **펴지 않는다**: 마크다운 표에 없는 개념이라
    /// 펴면 없던 자료를 지어내는 것이 된다. 글자만 그 칸에 두고 넘어간다.
    public static func markdown(from html: String) -> String? {
        guard let table = firstElement(named: "table", in: html) else { return nil }
        let rows = rows(in: table)
        guard !rows.isEmpty else { return nil }

        let width = rows.map(\.cells.count).max() ?? 0
        guard width > 0 else { return nil }

        var head = rows[0]
        var body = Array(rows.dropFirst())
        // 첫 줄이 머리줄이 아니면 **빈 머리줄**을 세운다 — 자료를 머리줄로 올리지 않는다.
        if !head.isHeader {
            body.insert(head, at: 0)
            head = Row(cells: Array(repeating: "", count: width), isHeader: true)
        }

        var lines = [line(head.cells, width: width),
                     "|" + String(repeating: " --- |", count: width)]
        for row in body { lines.append(line(row.cells, width: width)) }
        return lines.joined(separator: "\n")
    }

    // MARK: - 안쪽
    //
    // **글자 배열과 숫자 자리로만 훑는다.** 처음에는 `lowercased()` 를 만들어 그 인덱스를
    // **원본 문자열에 쓰고** 있었다. 소문자로 바꾸면 길이가 달라지는 글자가 있어
    // (`İ` 는 한 자가 두 자가 된다) 그 인덱스는 원본에서 **범위를 벗어날 수 있다** —
    // 앱이 죽는다. 여기서는 컴파일해 볼 수 없으니 (`CLAUDE.md` §2) 그런 길을 아예 만들지
    // 않는다. 대소문자는 **견줄 때만** 무시한다.

    struct Row {
        var cells: [String]
        var isHeader: Bool
    }

    private static func line(_ cells: [String], width: Int) -> String {
        var padded = cells
        while padded.count < width { padded.append("") }
        return "| " + padded.map { $0.isEmpty ? " " : $0 }.joined(separator: " | ") + " |"
    }

    /// `<table>` 안의 줄들. `<th>` 만으로 된 줄은 머리줄로 본다.
    static func rows(in table: String) -> [Row] {
        var out: [Row] = []
        var rest = table
        while let row = element(named: "tr", in: rest) {
            rest = row.after
            var cells: [String] = []
            var headers = 0
            var inner = row.body
            while let cell = nextCell(in: inner) {
                cells.append(escapeCell(text(of: cell.body)))
                if cell.isHeader { headers += 1 }
                inner = cell.after
            }
            guard !cells.isEmpty else { continue }
            out.append(Row(cells: cells, isHeader: headers == cells.count))
        }
        return out
    }

    /// 태그를 걷어내고 글자만 남긴다. **굵게와 링크는 마크다운으로 살린다.**
    static func text(of html: String) -> String {
        let units = Array(html)
        var out = ""
        var at = 0
        while at < units.count {
            guard units[at] == "<" else {
                out.append(units[at])
                at += 1
                continue
            }
            guard let close = index(of: ">", in: units, from: at) else { break }
            let name = tagName(units, from: at + 1, to: close)
            switch name {
            case "b", "strong", "/b", "/strong": out += "**"
            case "i", "em", "/i", "/em": out += "*"
            case "br", "br/": out += "\n"
            case "code", "/code": out += "`"
            default: break
            }
            at = close + 1
        }
        return unescape(out).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// `&amp;` 같은 것을 글자로. **흔한 다섯만** 푼다 — 모르는 것은 그대로 둔다.
    static func unescape(_ text: String) -> String {
        guard text.contains("&") else { return text }
        return text
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\u{22}")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
    }

    /// `<이름 …> … </이름>` 의 **안쪽**과 **닫는 태그 뒤**를 돌려준다.
    static func element(named name: String, in html: String) -> (body: String, after: String)? {
        let units = Array(html)
        guard let open = tagStart(named: name, in: units, from: 0),
              let openEnd = index(of: ">", in: units, from: open) else { return nil }
        let bodyStart = openEnd + 1
        guard let close = closingTag(named: name, in: units, from: bodyStart),
              let closeEnd = index(of: ">", in: units, from: close) else { return nil }
        return (String(units[bodyStart..<close]),
                String(units[min(closeEnd + 1, units.count)...]))
    }

    private static func firstElement(named name: String, in html: String) -> String? {
        element(named: name, in: html)?.body
    }

    /// `<td>` 든 `<th>` 든 **먼저 오는 것** 하나.
    private static func nextCell(in html: String) -> (body: String, after: String, isHeader: Bool)? {
        let units = Array(html)
        let data = tagStart(named: "td", in: units, from: 0)
        let head = tagStart(named: "th", in: units, from: 0)
        let useHead: Bool
        switch (data, head) {
        case (nil, nil): return nil
        case (_?, nil): useHead = false
        case (nil, _?): useHead = true
        case (let d?, let h?): useHead = h < d
        }
        guard let found = element(named: useHead ? "th" : "td", in: html) else { return nil }
        return (found.body, found.after, useHead)
    }

    // MARK: - 글자 훑기

    private static func index(of character: Character, in units: [Character], from: Int) -> Int? {
        var at = max(from, 0)
        while at < units.count {
            if units[at] == character { return at }
            at += 1
        }
        return nil
    }

    /// `<` 부터 `>` 앞까지에서 **태그 이름**만 (소문자로).
    private static func tagName(_ units: [Character], from: Int, to end: Int) -> String {
        var name = ""
        var at = from
        while at < end, units[at] != " ", units[at] != "\n", units[at] != "\t" {
            name.append(units[at])
            at += 1
        }
        return name.lowercased()
    }

    /// `<td` 처럼 **이름이 정확히 맞는** 여는 태그의 자리. `<table>` 을 `<ta` 로 안 잡는다.
    private static func tagStart(named name: String, in units: [Character], from: Int) -> Int? {
        var at = max(from, 0)
        while let open = index(of: "<", in: units, from: at) {
            if let close = index(of: ">", in: units, from: open),
               tagName(units, from: open + 1, to: close) == name.lowercased() {
                return open
            }
            at = open + 1
        }
        return nil
    }

    /// 짝이 맞는 `</이름>` 의 자리. **같은 이름이 겹쳐 들어가도 짝을 센다.**
    private static func closingTag(named name: String, in units: [Character], from: Int) -> Int? {
        let wanted = name.lowercased()
        var depth = 0
        var at = from
        while let open = index(of: "<", in: units, from: at) {
            guard let close = index(of: ">", in: units, from: open) else { return nil }
            let found = tagName(units, from: open + 1, to: close)
            if found == wanted {
                depth += 1
            } else if found == "/" + wanted {
                if depth == 0 { return open }
                depth -= 1
            }
            at = close + 1
        }
        return nil
    }
}
