import Foundation
import Markdown

/// 렌더한 결과.
public struct RenderedNote: Equatable, Sendable {
    /// `<body>` 안에 들어갈 HTML.
    public let bodyHTML: String
    /// 참조했는데 폴더 안에 없는 것. **원문에 적힌 링크 그대로** — 사용자에게
    /// "어느 링크가 없는지" 를 보여 줘야 한다 (안정화 기준 S5).
    public let missingAttachments: [String]
    /// 읽기 화면의 코드 상자들 — **화면에 그린 차례대로** (237). `yb://copy/<번호>` · `yb://code/<번호>` 의 번호가 이 배열의 자리다.
    public let codeBlocks: [CodeBlockText]

    public init(bodyHTML: String, missingAttachments: [String], codeBlocks: [CodeBlockText] = []) {
        self.bodyHTML = bodyHTML
        self.missingAttachments = missingAttachments
        self.codeBlocks = codeBlocks
    }
}

/// 코드 상자 하나 (237). `language` 는 울타리 뒤에 적은 첫 낱말 (` ```swift ` → `swift`), 없으면 빈 문자열.
/// `text` 는 상자 안의 글 그대로 — 복사하기가 클립보드에 넣는 것이다.
public struct CodeBlockText: Equatable, Sendable {
    public let language: String
    public let text: String

    public init(language: String, text: String) {
        self.language = language
        self.text = text
    }
}

/// 코드 상자 머리의 글자 (237). Core 에는 번역 목록이 없어 App 이 번역해 넘긴다 — 기본값은 한국어.
public struct CodeBoxLabels: Sendable {
    public let code: String
    public let copy: String
    public let expand: String

    public init(code: String = "코드", copy: String = "복사", expand: String = "크게 보기") {
        self.code = code
        self.copy = copy
        self.expand = expand
    }
}

/// 마크다운을 뷰어용 HTML 로 바꾼다 (ADR-0004).
///
/// 파싱은 `swift-markdown`, HTML 생성은 그 안의 `HTMLFormatter` 가 한다.
/// 이 타입이 하는 일은 그 앞뒤다:
/// - 이미지 · 링크의 상대경로를 `yb://` 로 바꾼다 (WKURLSchemeHandler 가 받는다)
/// - 없는 첨부를 회색 상자로 바꾸고 목록으로 알린다
/// - **글자를 전부 이스케이프한다** (아래 "안전" 참고)
///
/// ## 안전 — 남의 노트를 열 수 있다
///
/// `HTMLFormatter` 는 글자 · 코드 · 원시 HTML 을 **이스케이프하지 않고 그대로**
/// 내보낸다. 사용자가 받은 zip 을 풀어 여는 일이 정상 경로이므로(설계서 §7.6.3),
/// 남이 쓴 `.md` 가 우리 웹뷰에서 임의의 HTML 이 될 수 있다. 웹뷰는 사용자 폴더의
/// 파일을 `yb://` 로 읽어 주므로 그건 곧 자료 유출 경로다.
///
/// 세 겹으로 막는다:
/// 1. **여기서** 글자 · 인라인 코드 · 코드 블록 · 원시 HTML 을 전부 이스케이프한다.
///    (이스케이프한 문자열을 `HTMLFormatter` 가 그대로 내보내므로 화면에는
///    사용자가 쓴 글자 그대로 보인다 — 코드 블록 안의 `<b>` 가 굵게 되지 않는다.)
/// 2. `page(bodyHTML:css:)` 가 **CSP** 를 박는다 — 스크립트 · 네트워크 전면 금지.
/// 3. App 의 웹뷰가 자바스크립트를 끈다 (`allowsContentJavaScript = false`).
public enum MarkdownHTML {

    /// 폴더 안 파일을 웹뷰에 건네주는 스킴. `WKURLSchemeHandler` 가 받는다.
    public static let scheme = "yb"

    // MARK: - 렌더

    /// 본문이 참조하는 폴더 안 경로들. **렌더하기 전에** 이것으로 어느 파일이
    /// 실제로 있는지 알아낸 뒤 `render(markdown:notePath:existing:)` 에 넘긴다.
    ///
    /// 왜 두 단계인가: 파일이 있는지 아는 것은 `actor FolderStore` 뿐인데,
    /// 렌더는 순수 함수라 actor 를 기다릴 수 없다.
    public static func referencedPaths(markdown: String, notePath: String) -> [String] {
        let note = Paths.normalized(notePath)
        var seen: Set<String> = []
        var paths: [String] = []
        for link in MarkdownLinks.extract(from: markdown) {
            if case .relative(let path) = Paths.resolve(link: link.destination, fromNoteAt: note),
               !seen.contains(path) {
                seen.insert(path)
                paths.append(path)
            }
        }
        return paths
    }

    /// - Parameters:
    ///   - markdown: 파일 전체 (머리말 포함)
    ///   - notePath: 폴더 기준 상대경로 — 상대 링크를 푸는 기준이다
    ///   - existing: 폴더 안에 실제로 있는 상대경로들 (`referencedPaths` → `FolderStore`)
    /// `tooDeepNotice` — 겹침이 너무 깊을 때 위에 다는 한 줄. App 이 앱 언어로 넘긴다 (222 — Core 에는 번역 목록이 없다).
    public static func render(
        markdown: String,
        notePath: String,
        existing: Set<String>,
        tooDeepNotice: String = "겹침이 너무 깊은 글이라 글자 그대로 보여 줍니다.",
        codeLabels: CodeBoxLabels = CodeBoxLabels()
    ) -> RenderedNote {
        let body = FrontMatterParser.parse(markdown).body

        // **겹침이 너무 깊으면 트리를 만들지 않는다** (182) — 라이브러리가 재귀로 걷다 스택이 넘친다.
        // 글은 그대로 보여 준다(이스케이프해서). 첨부는 안 그리므로 없는 첨부도 없다.
        guard !Nesting.isTooDeep(body) else {
            return RenderedNote(
                bodyHTML: "<p><em>\(escape(tooDeepNotice))</em></p>\n<pre>\(escape(body))</pre>\n",
                missingAttachments: []
            )
        }

        // **스마트 따옴표를 끈다.** 파일이 원본이다 (ADR-0001) — 화면에서 곧은
        // 따옴표가 둥근 것으로 바뀌면 사용자가 쓴 글과 다르게 보인다.
        let document = Document(parsing: body, options: [.disableSmartOpts])

        var rewriter = NoteRewriter(notePath: Paths.normalized(notePath), existing: existing)
        var rewritten = rewriter.visit(document) ?? document
        // 제목 안의 굵게 · 기울임 · 코드 · 링크를 살린다 (201) — 위에서 링크 · 이스케이프를 다 고친 **뒤에** 한다.
        var headings = HeadingRewriter()
        rewritten = headings.visit(rewritten) ?? rewritten

        // 블록마다 원문 줄 범위를 붙인다 — 읽기 ↔ 쓰기를 오가도 보던 자리를 잇는다 (176).
        // 짝이 안 맞으면 `LineMap` 이 손대지 않고 돌려준다.
        let tasked = linkTasks(LineMap.annotate(HTMLFormatter.format(rewritten), markdown: markdown),
                               markdown: markdown)
        // 코드 상자에 머리(언어 · 복사 · 크게 보기)를 단다 (237) — 단추의 번호와 복사할 글을 **같은 한 번의 훑기**에서 얻는다.
        let boxed = decorateCodeBlocks(tasked, labels: codeLabels)
        return RenderedNote(
            bodyHTML: boxed.html,
            missingAttachments: rewriter.missing,
            codeBlocks: boxed.blocks
        )
    }

    /// **코드 상자마다 머리를 단다** (237, 2026-10-11 사용자 — 상자 오른쪽 위에 *복사* · *크게 보기*).
    ///
    /// 읽기 화면은 자바스크립트를 끈 웹뷰라 화면 안에서 클립보드에 넣을 수 없다 — 체크상자(211)와 같은 길로 간다:
    /// 단추는 `yb://copy/<번호>` · `yb://code/<번호>` 링크이고, 누르면 앱이 받아 `codeBlocks[번호]` 를 쓴다.
    ///
    /// **번호와 글을 한 번에 얻는다** (CLAUDE.md §1 — 같은 것을 재는 곳이 둘이면 갈린다). 글은 **화면에 그린 HTML 에서**
    /// 되돌려 얻는다 — 원시 HTML 은 위에서 전부 이스케이프되므로 진짜 `<pre>` 는 코드 블록에서만 나온다.
    /// 짝이 안 맞는 꼴(정규식이 못 잡는 `<pre>`)은 손대지 않는다 — 단추가 없을 뿐 글은 그대로 보인다.
    static func decorateCodeBlocks(_ html: String, labels: CodeBoxLabels) -> (html: String, blocks: [CodeBlockText]) {
        guard html.contains("<pre"),
              let regex = try? NSRegularExpression(
                pattern: #"<pre(\b[^>]*)><code(?: class="language-([^"]*)")?>([\s\S]*?)</code></pre>"#)
        else { return (html, []) }
        let text = html as NSString
        var out = ""
        var blocks: [CodeBlockText] = []
        var cursor = 0
        for match in regex.matches(in: html, range: NSRange(location: 0, length: text.length)) {
            let attributes = text.substring(with: match.range(at: 1))
            let languageClass = match.range(at: 2).location == NSNotFound ? "" : text.substring(with: match.range(at: 2))
            let inner = text.substring(with: match.range(at: 3))
            // 언어는 울타리 뒤 첫 낱말 — ` ```js 제목 ` 이면 `js`.
            let language = unescape(languageClass).split(whereSeparator: { $0 == " " || $0 == "\t" }).first.map(String.init) ?? ""
            var code = unescape(inner)
            if code.hasSuffix("\n") { code.removeLast() }   // 파서가 상자 끝에 붙이는 줄바꿈 하나
            let index = blocks.count
            blocks.append(CodeBlockText(language: language, text: code))

            let classAttribute = languageClass.isEmpty ? "" : " class=\"language-\(languageClass)\""
            let head = "<div class=\"yb-code\"><div class=\"yb-code-bar\">"
                // 머리 글자는 **CSS 가 그린다** (`::before`) — 페이지의 글이 아니라서 글을 골라 복사할 때 실리지 않는다 (237 셋째,
                // 빌드 96 사용자 — 코드와 글을 함께 골라 복사해 붙이니 `코드` 만 든 상자가 하나 더 생겼다. 고정폭 글꼴이라
                // 붙여넣기가 코드로 읽었다). 단추는 그림뿐이라 글이 없다.
                + "<span class=\"yb-code-lang\" data-label=\"\(escape(language.isEmpty ? labels.code : language))\"></span>"
                + "<a class=\"yb-code-btn\" href=\"\(scheme)://copy/\(index)\" aria-label=\"\(escape(labels.copy))\">\(copyIcon)</a>"
                + "<a class=\"yb-code-btn\" href=\"\(scheme)://code/\(index)\" aria-label=\"\(escape(labels.expand))\">\(expandIcon)</a>"
                + "</div>"
            out += text.substring(with: NSRange(location: cursor, length: match.range.location - cursor))
            out += head + "<pre\(attributes)><code\(classAttribute)>\(inner)</code></pre></div>"
            cursor = match.range.location + match.range.length
        }
        out += text.substring(from: cursor)
        return (out, blocks)
    }

    /// `escape` 를 거꾸로 — 같은 다섯 글자만. `&amp;` 는 맨 나중에 (먼저 풀면 `&amp;lt;` 가 `<` 가 된다).
    static func unescape(_ text: String) -> String {
        guard text.contains("&") else { return text }
        return text
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&amp;", with: "&")
    }

    /// 겹친 네모 둘 — 복사 (237). 선만 그리고 색은 글자색을 따른다.
    private static let copyIcon = #"<svg viewBox="0 0 24 24" aria-hidden="true"><rect x="8" y="8" width="12" height="12" rx="2.5"/><path d="M16 8V6.5A2.5 2.5 0 0 0 13.5 4h-7A2.5 2.5 0 0 0 4 6.5v7A2.5 2.5 0 0 0 6.5 16H8"/></svg>"#
    /// 바깥으로 벌어지는 두 화살 — 크게 보기 (237).
    private static let expandIcon = #"<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M14 4h6v6M20 4l-7 7M10 20H4v-6M4 20l7-7"/></svg>"#

    /// **체크상자를 누를 수 있게** (211) — 목록 항목의 줄 번호(`data-line`, `LineMap` 이 붙였다)로 `yb://task/<줄>` 링크를 씌운다.
    /// 체크상자 자체는 그대로 두고(`disabled`), 링크가 누름을 받는다 — CSS 가 체크상자의 누름을 링크로 흘린다.
    /// 줄 번호가 없으면(줄 지도가 안 맞았다) 손대지 않는다 — 엉뚱한 줄을 바꾸느니 못 누르는 편이 낫다.
    ///
    /// **인용(`>`) 안의 체크상자** (빌드 78 · 4번 사용자 화면) — cmark-gfm 은 이것을 체크상자로 안 읽고 글자 `[ ]` 로 남긴다.
    /// GFM 규격은 인용 안의 목록 항목을 막지 않는다(렌더러의 한계 — markdown-it 의 확장은 체크상자로 읽는다). 그래서 목록 항목이
    /// 글자 `[ ]` · `[x]` 로 시작하고 **그 원문 줄이 체크상자 줄이면**(`TaskToggle.marker` — 뒤집을 때와 같은 잣대) 체크상자로 그린다.
    /// `\[ ]` 로 막은 줄은 원문 줄이 체크상자 줄이 아니라 글자 그대로 둔다. 느슨한 목록(`<li><p>[ ] …`)은 체크상자를 `<p>` 앞으로 —
    /// cmark-gfm 이 보통 체크상자를 두는 자리와 같게 해 CSS 가 같은 규칙으로 맞춘다.
    static func linkTasks(_ html: String, markdown: String) -> String {
        guard html.contains("data-line=\""),
              let regex = try? NSRegularExpression(
                pattern: #"(<li\b[^>]*\bdata-line="(\d+)"[^>]*>)(?:(<input\b[^>]*type="checkbox"[^>]*>)|(\s*<p\b[^>]*>)?\[([ xX])\](?=[ \t]))"#)
        else { return html }
        let lines = TaskToggle.split(markdown)
        let text = html as NSString
        var out = ""
        var cursor = 0
        for match in regex.matches(in: html, range: NSRange(location: 0, length: text.length)) {
            let open = text.substring(with: match.range(at: 1))
            let line = text.substring(with: match.range(at: 2))
            // **보이스오버에는 체크상자로 읽힌다** (232, 2026-10-09 전수 조사). 링크 안에 꺼 둔(`disabled`) 체크상자만 있으면
            // *링크* 로 읽히고 켜졌는지는 흐리게 묻혔다. 링크에 체크상자 역할과 켜짐을 달면 안의 상자는 겉모습만 남는다
            // (체크상자 역할의 자식은 따로 읽히지 않는다). 두 번 누르면 링크가 눌린 것과 같아 그대로 뒤집힌다.
            func link(_ checked: Bool) -> String {
                "<a class=\"yb-task\" role=\"checkbox\" aria-checked=\"\(checked)\" href=\"\(scheme)://task/\(line)\">"
            }
            var replaced: String
            if match.range(at: 3).location != NSNotFound {
                // cmark-gfm 이 그린 체크상자.
                let input = text.substring(with: match.range(at: 3))
                replaced = open + link(input.contains("checked=")) + input + "</a>"
            } else {
                // 글자로 남은 `[ ]` — 원문 줄이 정말 체크상자 줄일 때만.
                guard let row = Int(line), row < lines.count,
                      TaskToggle.marker(Array(lines[row].unicodeScalars)) != nil else { continue }
                let checked = text.substring(with: match.range(at: 5)) != " "
                let box = "<input type=\"checkbox\" disabled=\"\"" + (checked ? " checked=\"\"" : "") + " />"
                replaced = open + link(checked) + box + "</a>"
                if match.range(at: 4).location != NSNotFound {
                    replaced += " " + text.substring(with: match.range(at: 4)).trimmingCharacters(in: .whitespacesAndNewlines)
                }
            }
            out += text.substring(with: NSRange(location: cursor, length: match.range.location - cursor))
            out += replaced
            cursor = match.range.location + match.range.length
        }
        out += text.substring(from: cursor)
        return out
    }

    /// **이 노트를 가리키는 노트** 칸 (212) — 읽기 화면 맨 아래. 없으면 빈 글 (칸을 아예 안 그린다).
    /// 줄마다 노트 이름(노트 목록의 제목과 같은 `Paths.baseName`)과, 맨 위 폴더가 아니면 흐린 폴더 경로. 누르면 `yb://note/…` —
    /// 본문의 노트 링크와 같은 길로 그 노트가 열린다 (`NoteLinkAction.note`). 파일에는 아무것도 안 쓴다.
    /// 목록은 `AttachmentLedger.backlinks` 가 정한다 — 여기서는 그리기만.
    /// `title` 은 App 이 번역해 넘긴다 — Core 에는 번역 목록이 없다 (219 · 영어 스토어 스크린샷에서 한국어로 남은 것이 잡혔다).
    public static func backlinksHTML(_ paths: [String], title: String = "이 노트를 가리키는 노트") -> String {
        guard !paths.isEmpty else { return "" }
        var html = "<section class=\"yb-backlinks\">\n<p class=\"yb-backlinks-title\">\(escape(title)) · \(paths.count)</p>\n<ul>\n"
        for path in paths {
            let normalized = Paths.normalized(path)
            // 이름은 노트 목록과 같은 셈 (`Paths.baseName` — 목록의 제목이 이것이다).
            let name = normalized.split(separator: "/").last.map(String.init) ?? normalized
            let folder = Paths.directory(of: normalized)
            html += "<li><a href=\"\(assetURL(normalized))\">\(escape(Paths.baseName(name)))</a>"
            if !folder.isEmpty { html += " <span class=\"yb-backlinks-folder\">\(escape(folder))</span>" }
            html += "</li>\n"
        }
        return html + "</ul>\n</section>\n"
    }

    /// 완전한 HTML 문서. 색 토큰(`--yb-*`)은 App 이 만들어 넘긴다 — 앱과 웹뷰의
    /// 다크 모드가 같이 가야 하기 때문이다 (설계서 §8).
    /// `lang` — 이 글의 언어 (222). 보이스오버가 이것으로 읽을 목소리를 고르고, 줄바꿈 · 글꼴도 따른다.
    /// 예전에는 늘 `ko` 여서 영어 노트를 한국어 목소리로 읽었다. App 이 글을 보고 정해 넘긴다.
    public static func page(bodyHTML: String, css: String, lang: String = "ko") -> String {
        """
        <!doctype html>
        <html lang="\(escape(lang))">
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <meta http-equiv="Content-Security-Policy" content="\(contentSecurityPolicy)">
        <style>
        \(css)
        \(baseCSS)
        </style>
        </head>
        <body>
        \(bodyHTML)
        </body>
        </html>
        """
    }

    /// 스크립트도 네트워크도 없다. 이미지는 우리 스킴에서만 온다.
    public static let contentSecurityPolicy =
        "default-src 'none'; img-src yb:; style-src 'unsafe-inline'; base-uri 'none'; form-action 'none'"

    // MARK: - 주소 만들기

    /// 폴더 안 파일을 가리키는 주소.
    public static func assetURL(_ relativePath: String) -> String {
        "\(scheme)://note/" + encode(path: relativePath)
    }

    /// 참조했는데 없는 파일. 앱이 탭을 받아 "찾을 수 없습니다" 를 알린다.
    public static func missingURL(_ relativePath: String) -> String {
        "\(scheme)://missing/" + encode(path: relativePath)
    }

    /// 주소에서 폴더 기준 상대경로를 되꺼낸다 (`WKURLSchemeHandler` 가 쓴다).
    public static func relativePath(fromURLPath urlPath: String) -> String {
        let trimmed = urlPath.hasPrefix("/") ? String(urlPath.dropFirst()) : urlPath
        return Paths.normalized(trimmed.removingPercentEncoding ?? trimmed)
    }

    /// 퍼센트 인코딩은 **따옴표도 없앤다** — `HTMLFormatter` 가 `src` 를
    /// 이스케이프 없이 넣으므로, 이것이 속성을 깨뜨리지 않게 하는 유일한 장치다.
    static func encode(path: String) -> String {
        Paths.normalized(path).addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? ""
    }

    // MARK: - 이스케이프

    public static func escape(_ text: String) -> String {
        var out = ""
        out.reserveCapacity(text.count)
        for character in text {
            switch character {
            case "&": out += "&amp;"
            case "<": out += "&lt;"
            case ">": out += "&gt;"
            case "\"": out += "&quot;"
            case "'": out += "&#39;"
            default: out.append(character)
            }
        }
        return out
    }

    /// 글자를 이스케이프하면서 `#태그` 만 `<span class="yb-tag">` 으로 감싼다 (T2).
    ///
    /// **감싸는 껍데기는 우리가 쓴 것이고, 안의 글자는 이스케이프한 것이다.** 사용자 글이
    /// HTML 이 되는 길은 열리지 않는다 (§안전 1겹).
    public static func escapeMarkingTags(_ text: String) -> String {
        let spans = Tags.scan(text)
        guard !spans.isEmpty else { return escape(text) }
        let utf16 = Array(text.utf16)
        var out = ""
        var cursor = 0
        for span in spans {
            guard span.start >= cursor, span.start + span.length <= utf16.count else { continue }
            out += escape(String(decoding: utf16[cursor..<span.start], as: UTF16.self))
            let tag = String(decoding: utf16[span.start..<(span.start + span.length)], as: UTF16.self)
            out += "<span class=\"yb-tag\">" + escape(tag) + "</span>"
            cursor = span.start + span.length
        }
        out += escape(String(decoding: utf16[cursor...], as: UTF16.self))
        return out
    }

    static func missingBox(label: String) -> String {
        "<span class=\"yb-missing\">\(escape(label))</span>"
    }

    // MARK: - 기본 CSS

    /// **`px` 를 적지 않는다.** `font: -apple-system-body` 가 Dynamic Type 을
    /// 저절로 따라가고, 나머지 크기는 전부 그것에 상대적인 `em` 이다 (설계서 §8).
    static let baseCSS = """
    html { -webkit-text-size-adjust: 100%; }
    body {
      font: -apple-system-body;
      line-height: 1.65;
      color: var(--yb-ink);
      background: var(--yb-paper);
      margin: 0;
      padding: 0.8em 1.1em 4em;
      word-break: break-word;
      -webkit-font-smoothing: antialiased;
    }
    h1, h2, h3, h4, h5, h6 { line-height: 1.3; margin: 1.7em 0 0.6em; font-weight: 700; }
    h1 { font-size: 1.55em; }
    h2 { font-size: 1.3em; }
    h3 { font-size: 1.12em; }
    h4, h5, h6 { font-size: 1em; }
    p { margin: 0.9em 0; }
    /* **첫 줄은 `#` 이 없어도 제목이다** (133). 이 앱에서 첫 줄은 곧 파일명이므로(107)
       제목으로 보이는 편이 맞다. **파일은 한 글자도 안 바뀐다** — 보이는 모습만 그렇다.
       편집기도 같은 규칙으로 그린다 (`MarkdownStyler`) — 두 자리가 갈리면 93 이 된다. */
    body > p:first-child { font-size: 1.55em; line-height: 1.3; font-weight: 700; }
    /* **첫 덩이 위에는 빈 자리를 두지 않는다** (136, 사용자 — `# 제목` 을 쓰면 읽기 모드에서
       제목 위로 한 줄이 비었다). 제목의 위 여백은 **글 사이**에서나 뜻이 있지 맨 처음에는
       군더더기다. `#` 이 있든 없든 같은 자리에서 시작한다. */
    body > :first-child { margin-top: 0; }
    a { color: var(--yb-accent); text-decoration: underline; text-underline-offset: 0.15em; }
    ul, ol { margin: 0.9em 0; padding-left: 1.4em; }
    li { margin: 0.25em 0; }
    /* 빈 줄이 있는 목록은 항목마다 <p> 가 생긴다. 그대로 두면 항목 사이가
       문단만큼 벌어진다 (빌드 4 스크린샷). */
    li > p { margin: 0.3em 0; }
    li > p:last-child { margin-bottom: 0; }
    li input[type="checkbox"] { margin-right: 0.35em; vertical-align: baseline; }
    /* 작업 목록 — 점을 없애고 체크박스와 글을 **한 줄에** 둔다.
       빌드 4 에서 점 · 체크박스가 한 줄, 글이 다음 줄로 갈라졌다. */
    li:has(> input[type="checkbox"]) { list-style: none; margin-left: -1.15em; }
    li:has(> input[type="checkbox"]) > p { display: inline; }
    /* 211 — 누를 수 있는 체크상자. 체크상자는 누름을 받지 않고 감싼 링크가 받는다. */
    a.yb-task { text-decoration: none; -webkit-tap-highlight-color: transparent; }
    a.yb-task input[type="checkbox"] { pointer-events: none; }
    li:has(> a.yb-task) { list-style: none; margin-left: -1.15em; }
    li:has(> a.yb-task) > p { display: inline; }
    /* 겹친 체크상자 (빌드 78 사용자 화면) — 체크상자를 점 자리로 당기는 위의 -1.15em 이 단계마다 다시 걸려 안쪽 단계가 0.25em(4화소)만
       들어갔다. 체크상자 항목 아래 목록은 그만큼 더 들여 **점 목록과 같은 한 단계(1.4em)** 가 되게 한다. */
    li:has(> input[type="checkbox"]) > ul, li:has(> input[type="checkbox"]) > ol,
    li:has(> a.yb-task) > ul, li:has(> a.yb-task) > ol { padding-left: 2.55em; }
    /* 212 — 이 노트를 가리키는 노트. 본문과 가는 선으로 가르고, 제목은 작고 흐리게. */
    .yb-backlinks { margin-top: 3em; padding-top: 1em; border-top: 1px solid var(--yb-rule); }
    .yb-backlinks-title { font-size: 0.85em; font-weight: 600; color: var(--yb-ink-faint); margin: 0 0 0.5em; }
    .yb-backlinks ul { list-style: none; padding-left: 0; margin: 0; }
    .yb-backlinks li { margin: 0.45em 0; }
    .yb-backlinks-folder { font-size: 0.8em; color: var(--yb-ink-faint); margin-left: 0.35em; }
    .yb-tag {
      color: var(--yb-tag, #8F6700);  /* 232 — 대비 4.5 넘게. 앱은 늘 토큰을 넘긴다 */
      font-weight: 600;
    }
    blockquote {
      margin: 1em 0;
      padding: 0.1em 0 0.1em 0.9em;
      border-left: 0.2em solid var(--yb-quote, var(--yb-rule));
      color: var(--yb-quote, var(--yb-ink-faint));
    }
    code {
      font-family: ui-monospace, SFMono-Regular, Menlo, monospace;
      font-size: 0.88em;
      background: var(--yb-paper-raised);
      color: var(--yb-quote, inherit);
      padding: 0.12em 0.3em;
      border-radius: 0.3em;
    }
    pre {
      background: var(--yb-paper-raised);
      padding: 0.8em;
      border-radius: 0.5em;
      overflow-x: auto;
      /* 긴 줄은 화면 폭에서 접는다 — 좌우로 밀지 않고 위아래로만 읽는다 (170). 줄바꿈 · 들여쓰기는 그대로. */
      white-space: pre-wrap;
      overflow-wrap: anywhere;
    }
    /* 글자 인용만 파랑 (196) — 코드 덩이는 본문색 그대로. */
    pre code { background: none; color: inherit; padding: 0; font-size: 0.85em; white-space: inherit; }
    /* 237 — 코드 상자의 머리: 왼쪽 언어(없으면 코드) · 오른쪽 복사 · 크게 보기. 상자와 한 덩어리로 보이게 같은 바탕에 가는 선으로 가른다. */
    .yb-code { margin: 1em 0; border-radius: 0.5em; background: var(--yb-paper-raised); overflow: hidden; }
    .yb-code pre { margin: 0; border-radius: 0; }
    .yb-code-bar { display: flex; align-items: center; gap: 0.2em; padding: 0.15em 0.35em 0.15em 0.8em;
      border-bottom: 1px solid var(--yb-rule); font-size: 0.8em; color: var(--yb-ink-faint);
      -webkit-user-select: none; user-select: none; }
    .yb-code-lang { flex: 1; font-family: ui-monospace, SFMono-Regular, Menlo, monospace; }
    .yb-code-lang::before { content: attr(data-label); }
    .yb-code-btn { display: flex; align-items: center; justify-content: center; width: 2.6em; height: 2.4em;
      color: var(--yb-ink-faint); -webkit-tap-highlight-color: transparent; }
    .yb-code-btn:active { color: var(--yb-ink); }
    .yb-code-btn svg { width: 1.35em; height: 1.35em; fill: none; stroke: currentColor; stroke-width: 1.8;
      stroke-linecap: round; stroke-linejoin: round; }
    hr { border: none; border-top: 1px solid var(--yb-rule); margin: 2em 0; }
    img { max-width: 100%; height: auto; border-radius: 0.4em; display: block; margin: 1em auto; }
    table { display: block; max-width: 100%; overflow-x: auto; border-collapse: collapse; margin: 1em 0; }
    th, td { border: 1px solid var(--yb-rule); padding: 0.4em 0.6em; text-align: left; overflow-wrap: anywhere; }
    th { background: var(--yb-paper-raised); }
    /* 참조했는데 없는 첨부 — 회색 상자에 경로를 적는다 (안정화 기준 S5) */
    .yb-missing {
      display: inline-block;
      font-family: ui-monospace, SFMono-Regular, Menlo, monospace;
      font-size: 0.85em;
      color: var(--yb-ink-faint);
      background: var(--yb-paper-raised);
      border: 1px dashed var(--yb-rule);
      border-radius: 0.4em;
      padding: 0.6em 0.8em;
    }
    """
}

// MARK: - AST 고쳐 쓰기

/// 주소를 `yb://` 로 바꾸고 글자를 이스케이프한다.
///
/// **왜 AST 를 고치나.** `HTMLFormatter` 가 내보낸 HTML 을 나중에 문자열로
/// 손보면 따옴표 · 중첩 때문에 반드시 틀린다. 트리에서 고치면 형식 생성은
/// 라이브러리에 맡기고 우리는 뜻만 바꾼다.
/// **제목 안의 글 모양** (201, 2026-10-01 자동 검사가 찾았다). `HTMLFormatter` 는 제목을 글자만(`plainText`) 그린다 —
/// `## **설계**` 의 굵게, `## [회의록](회의.md)` 의 링크가 읽기 화면에서 사라졌다 (쓰기 화면 · 다른 앱은 그린다).
///
/// 제목의 글을 **본문 문단과 같은 길**(`HTMLFormatter`)로 그리고 `<hN>` 으로 감싼 날 HTML 덩이로 바꾼다. 날 HTML 덩이는
/// `HTMLFormatter` 가 글자 그대로 내보내므로 링크 고치기 · 이스케이프는 앞의 `NoteRewriter` 가 이미 한 그대로 남는다.
/// 블록 차례와 `<hN>` 여는 태그는 그대로라 줄 지도(`LineMap`)도 그대로 맞는다.
private struct HeadingRewriter: MarkupRewriter {
    mutating func visitHeading(_ heading: Heading) -> Markup? {
        let paragraph = Paragraph(heading.inlineChildren.map { $0 })
        var inner = HTMLFormatter.format(paragraph)
        if inner.hasPrefix("<p>") { inner.removeFirst(3) }
        while inner.hasSuffix("\n") { inner.removeLast() }
        if inner.hasSuffix("</p>") { inner.removeLast(4) }
        let level = min(max(heading.level, 1), 6)
        return HTMLBlock("<h\(level)>" + inner + "</h\(level)>\n")
    }
}

private struct NoteRewriter: MarkupRewriter {
    let notePath: String
    /// 폴더 안에 실제로 있는 상대경로들. 클로저가 아니라 값이라 저장해도 안전하다.
    let existing: Set<String>

    private(set) var missing: [String] = []
    private var missingSeen: Set<String> = []

    init(notePath: String, existing: Set<String>) {
        self.notePath = notePath
        self.existing = existing
    }

    private mutating func record(_ rawLink: String) {
        guard !missingSeen.contains(rawLink) else { return }
        missingSeen.insert(rawLink)
        missing.append(rawLink)
    }

    // MARK: 이스케이프 (안전 1겹)

    mutating func visitText(_ text: Text) -> Markup? {
        // **`#태그` 를 같은 색으로** (T2). 편집기와 읽기 모드가 다르게 그리면 그것이 곧
        // 버그 자리다 (93 에서 배웠다). 규칙은 한 군데 — `Tags.scan` 이다.
        Text(MarkdownHTML.escapeMarkingTags(text.string))
    }

    mutating func visitInlineCode(_ inlineCode: InlineCode) -> Markup? {
        InlineCode(MarkdownHTML.escape(inlineCode.code))
    }

    mutating func visitCodeBlock(_ codeBlock: CodeBlock) -> Markup? {
        var copy = codeBlock
        copy.code = MarkdownHTML.escape(codeBlock.code)
        // 울타리 뒤 글(언어)도 HTML 속성(`class="language-…"`)에 그대로 들어간다 — 따옴표가 있으면 속성을 깨고 나왔다 (237 에서 찾음).
        copy.language = codeBlock.language.map { MarkdownHTML.escape($0) }
        return copy
    }

    mutating func visitInlineHTML(_ inlineHTML: InlineHTML) -> Markup? {
        // 남이 쓴 노트의 원시 HTML 은 **글자로 보여 준다.** 실행하지 않는다.
        InlineHTML(MarkdownHTML.escape(inlineHTML.rawHTML))
    }

    mutating func visitHTMLBlock(_ html: HTMLBlock) -> Markup? {
        var copy = html
        copy.rawHTML = "<p>" + MarkdownHTML.escape(html.rawHTML) + "</p>\n"
        return copy
    }

    // MARK: 주소 바꾸기

    mutating func visitImage(_ image: Image) -> Markup? {
        guard let source = image.source, !source.isEmpty else { return image }

        switch Paths.resolve(link: source, fromNoteAt: notePath) {
        case .empty:
            return image

        case .external:
            // 외부 이미지는 CSP 가 막는다 — 네트워크를 안 쓰는 앱이다 (설계서 §1).
            record(source)
            return InlineHTML(MarkdownHTML.missingBox(label: source))

        case .relative(let path):
            guard existing.contains(path) else {
                record(source)
                return InlineHTML(MarkdownHTML.missingBox(label: path))
            }
            var copy = image
            copy.source = MarkdownHTML.assetURL(path)
            return copy

        case .absolute(let path), .outside(let path):
            record(source)
            return InlineHTML(MarkdownHTML.missingBox(label: path))
        }
    }

    mutating func visitLink(_ link: Link) -> Markup? {
        guard let destination = link.destination, !destination.isEmpty else {
            return defaultVisit(link)
        }

        var copy = link
        switch Paths.resolve(link: destination, fromNoteAt: notePath) {
        case .empty, .external, .absolute:
            break   // 그대로 둔다. 외부 URL 은 앱이 Safari 로 연다

        case .relative(let path):
            if existing.contains(path) {
                copy.destination = MarkdownHTML.assetURL(path)
            } else {
                record(destination)
                copy.destination = MarkdownHTML.missingURL(path)
            }

        case .outside(let path):
            record(destination)
            copy.destination = MarkdownHTML.missingURL(path)
        }
        // 링크 글자도 이스케이프해야 하므로 자식으로 내려간다.
        return defaultVisit(copy)
    }
}
