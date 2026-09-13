import Foundation
import Markdown

/// 렌더한 결과.
public struct RenderedNote: Equatable, Sendable {
    /// `<body>` 안에 들어갈 HTML.
    public let bodyHTML: String
    /// 참조했는데 폴더 안에 없는 것. **원문에 적힌 링크 그대로** — 사용자에게
    /// "어느 링크가 없는지" 를 보여 줘야 한다 (안정화 기준 S5).
    public let missingAttachments: [String]

    public init(bodyHTML: String, missingAttachments: [String]) {
        self.bodyHTML = bodyHTML
        self.missingAttachments = missingAttachments
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

    /// - Parameters:
    ///   - markdown: 파일 전체 (머리말 포함)
    ///   - notePath: 폴더 기준 상대경로 — 상대 링크를 푸는 기준이다
    ///   - exists: 폴더 기준 상대경로가 실제로 있는지
    public static func render(
        markdown: String,
        notePath: String,
        exists: (String) -> Bool
    ) -> RenderedNote {
        let body = FrontMatterParser.parse(markdown).body

        // **스마트 따옴표를 끈다.** 파일이 원본이다 (ADR-0001) — 화면에서 곧은
        // 따옴표가 둥근 것으로 바뀌면 사용자가 쓴 글과 다르게 보인다.
        let document = Document(parsing: body, options: [.disableSmartOpts])

        var rewriter = NoteRewriter(notePath: Paths.normalized(notePath), exists: exists)
        let rewritten = rewriter.visit(document) ?? document

        return RenderedNote(
            bodyHTML: HTMLFormatter.format(rewritten),
            missingAttachments: rewriter.missing
        )
    }

    /// 완전한 HTML 문서. 색 토큰(`--yb-*`)은 App 이 만들어 넘긴다 — 앱과 웹뷰의
    /// 다크 모드가 같이 가야 하기 때문이다 (설계서 §8).
    public static func page(bodyHTML: String, css: String) -> String {
        """
        <!doctype html>
        <html lang="ko">
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
    a { color: var(--yb-accent); text-decoration: underline; text-underline-offset: 0.15em; }
    ul, ol { margin: 0.9em 0; padding-left: 1.4em; }
    li { margin: 0.25em 0; }
    li input[type="checkbox"] { margin-right: 0.35em; }
    blockquote {
      margin: 1em 0;
      padding: 0.1em 0 0.1em 0.9em;
      border-left: 0.2em solid var(--yb-rule);
      color: var(--yb-ink-faint);
    }
    code {
      font-family: ui-monospace, SFMono-Regular, Menlo, monospace;
      font-size: 0.88em;
      background: var(--yb-paper-raised);
      padding: 0.12em 0.3em;
      border-radius: 0.3em;
    }
    pre {
      background: var(--yb-paper-raised);
      padding: 0.8em;
      border-radius: 0.5em;
      overflow-x: auto;
    }
    pre code { background: none; padding: 0; font-size: 0.85em; }
    hr { border: none; border-top: 1px solid var(--yb-rule); margin: 2em 0; }
    img { max-width: 100%; height: auto; border-radius: 0.4em; display: block; margin: 1em auto; }
    table { display: block; max-width: 100%; overflow-x: auto; border-collapse: collapse; margin: 1em 0; }
    th, td { border: 1px solid var(--yb-rule); padding: 0.4em 0.6em; text-align: left; }
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
private struct NoteRewriter: MarkupRewriter {
    let notePath: String
    let exists: (String) -> Bool

    private(set) var missing: [String] = []
    private var missingSeen: Set<String> = []

    init(notePath: String, exists: @escaping (String) -> Bool) {
        self.notePath = notePath
        self.exists = exists
    }

    private mutating func record(_ rawLink: String) {
        guard !missingSeen.contains(rawLink) else { return }
        missingSeen.insert(rawLink)
        missing.append(rawLink)
    }

    // MARK: 이스케이프 (안전 1겹)

    mutating func visitText(_ text: Text) -> Markup? {
        Text(MarkdownHTML.escape(text.string))
    }

    mutating func visitInlineCode(_ inlineCode: InlineCode) -> Markup? {
        InlineCode(MarkdownHTML.escape(inlineCode.code))
    }

    mutating func visitCodeBlock(_ codeBlock: CodeBlock) -> Markup? {
        var copy = codeBlock
        copy.code = MarkdownHTML.escape(codeBlock.code)
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
            guard exists(path) else {
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
            if exists(path) {
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
