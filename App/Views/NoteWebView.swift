import SwiftUI
import WebKit
import Core

/// 읽기 모드 — 렌더된 마크다운 (ADR-0004).
///
/// 표 · 코드 블록 · 핀치 줌 · 글자 선택 · 찾기가 전부 `WKWebView` 에서 공짜다.
/// SwiftUI 로 다시 만들지 않는다 — 지난 앱에서 핀치 줌 하나로 세 바퀴 돌았다.
struct NoteWebView: UIViewRepresentable {

    /// 완전한 HTML 문서 (`MarkdownHTML.page`).
    let html: String
    /// 폴더 안 파일을 읽어 주는 것. 웹뷰의 `yb://` 요청이 여기로 온다.
    let assets: AssetProvider
    /// 뷰어 안에서 무언가를 탭했을 때.
    var onOpen: (NoteLinkAction) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onOpen: onOpen)
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()

        // **자바스크립트를 끈다.** 남이 쓴 노트를 여는 것이 정상 경로이고,
        // 이 웹뷰는 `yb://` 로 사용자 폴더를 읽어 준다 (설계서 ADR-0004 안전).
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false
        configuration.setURLSchemeHandler(context.coordinator.schemeHandler,
                                          forURLScheme: MarkdownHTML.scheme)

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.isOpaque = false
        webView.backgroundColor = .systemBackground
        webView.scrollView.backgroundColor = .systemBackground
        // 핀치 줌은 웹뷰가 한다.
        webView.scrollView.minimumZoomScale = 1
        webView.scrollView.maximumZoomScale = 4
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        context.coordinator.onOpen = onOpen
        context.coordinator.schemeHandler.assets = assets
        guard context.coordinator.loadedHTML != html else { return }
        context.coordinator.loadedHTML = html
        // `yb://` 를 기준 주소로 삼아야 상대 주소가 우리 스킴으로 풀린다.
        webView.loadHTMLString(html, baseURL: URL(string: "\(MarkdownHTML.scheme)://note/"))
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        let schemeHandler = NoteSchemeHandler()
        var onOpen: (NoteLinkAction) -> Void
        var loadedHTML: String?

        init(onOpen: @escaping (NoteLinkAction) -> Void) {
            self.onOpen = onOpen
        }

        /// **`async` 판으로 쓴다.** 클로저를 받는 판은 Xcode 26.6 의 WebKit 에서 클로저 타입이
        /// `@MainActor @Sendable` 로 바뀌어, 우리 메서드가 "거의 맞지만 다른" 것으로 취급돼
        /// **호출되지 않았다** (컴파일 경고 하나뿐이었다). 그러면 링크를 가로채지 못해 웹뷰가
        /// `.md` 원문을 문자 집합 없이 열어 한글이 깨지고, 없는 파일은 빈 화면이 됐다
        /// (빌드 24 · 11 · 12번, 빌드 20 · 10 · 11번도 같은 원인). `async` 판은 서명이 하나뿐이다.
        func webView(_ webView: WKWebView,
                     decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
            // 첫 로드(loadHTMLString)는 그대로 통과시킨다.
            guard navigationAction.navigationType == .linkActivated,
                  let url = navigationAction.request.url else {
                return .allow
            }
            onOpen(NoteLinkAction(url: url))
            return .cancel
        }
    }
}

/// 뷰어에서 탭한 것이 무엇인가.
enum NoteLinkAction {
    /// 폴더 안의 다른 노트 — 앱 안에서 연다.
    case note(String)
    /// 폴더 안의 다른 첨부 — QuickLook.
    case attachment(String)
    /// 바깥 주소 — Safari.
    case external(URL)
    /// 참조했는데 없는 것 — 알린다.
    case missing(String)

    init(url: URL) {
        guard url.scheme == MarkdownHTML.scheme else {
            self = .external(url)
            return
        }
        let path = MarkdownHTML.relativePath(fromURLPath: url.path)
        switch url.host {
        case "missing":
            self = .missing(path)
        case "note":
            // `assets/` 안의 `.md` 는 **첨부**다 — 문서 첨부로 넣은 것. 노트로 열면 `assets` 폴더로
            // 옮겨 가 버린다 (빌드 24 · 17번). 미리보기로 연다.
            let inAssets = path.split(separator: "/").dropLast().contains("assets")
            self = (Paths.isNoteFile(path) && !inAssets) ? .note(path) : .attachment(path)
        default:
            self = .missing(path)
        }
    }
}
