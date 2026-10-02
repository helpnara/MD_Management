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
    /// **보던 자리를 묻는다** (176). 새 값이 오면 맨 위 블록을 재서 `onSpot` 으로 답한다.
    var spotRequest: UUID? = nil
    var onSpot: @MainActor (LibraryModel.Spot?) -> Void = { _ in }
    /// 쓰기에서 넘어왔을 때 **가야 할 자리.** 페이지가 다 뜬 뒤에 간다.
    var restore: LibraryModel.SpotRestore? = nil
    var onRestored: @MainActor () -> Void = {}

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
        // 늘 보이는 스크롤 막대 (202) — 쓰기 화면과 같은 것.
        ScrollGaugeView.attach(to: webView.scrollView)
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        let coordinator = context.coordinator
        coordinator.onOpen = onOpen
        coordinator.onSpot = onSpot
        coordinator.onRestored = onRestored
        coordinator.schemeHandler.assets = assets
        if let restore, coordinator.restoredID != restore.id {
            coordinator.restoredID = restore.id
            coordinator.restoring = restore
            coordinator.restoreIfReady(webView)
        }
        if let spotRequest, coordinator.answered != spotRequest {
            coordinator.answered = spotRequest
            coordinator.reportSpot(webView)
        }
        guard coordinator.loadedHTML != html else { return }
        coordinator.loadedHTML = html
        coordinator.isLoaded = false
        // `yb://` 를 기준 주소로 삼아야 상대 주소가 우리 스킴으로 풀린다.
        webView.loadHTMLString(html, baseURL: URL(string: "\(MarkdownHTML.scheme)://note/"))
    }

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate {
        let schemeHandler = NoteSchemeHandler()
        var onOpen: (NoteLinkAction) -> Void
        var loadedHTML: String?
        var onSpot: @MainActor (LibraryModel.Spot?) -> Void = { _ in }
        var onRestored: @MainActor () -> Void = {}
        /// 이미 답한 물음 · 가는 중인 자리 · 페이지가 다 떴나.
        var answered: UUID?
        var restoring: LibraryModel.SpotRestore?
        var restoredID: UUID?
        var isLoaded = false

        init(onOpen: @escaping (NoteLinkAction) -> Void) {
            self.onOpen = onOpen
        }

        // MARK: 보던 자리 (176)
        //
        // 블록마다 `data-line` 이 붙어 있다 (`LineMap.annotate`). 순번은 Core 의 블록 표와 같은
        // 문서 순서다. **노트 안의 스크립트는 여전히 끈다** — 이것은 앱이 넣는 짧은 물음이다(A17).
        // 물음이 실패하면(스크립트가 안 돌면) 스크롤 비율로 물러선다.

        /// 맨 위 블록 · 그 안의 비율 · 전체 비율. 품은 블록이 여럿이면 **가장 안쪽**(문서 순서로 마지막).
        static let measureScript = """
        (function(){var y=window.scrollY;var h=Math.max(1,document.documentElement.scrollHeight-window.innerHeight);\
        var els=document.querySelectorAll('[data-line]');var pick=-1,f=0;\
        for(var i=0;i<els.length;i++){var r=els[i].getBoundingClientRect();var top=r.top+y;\
        if(top>y+1){if(pick<0){pick=i;f=0;}break;}\
        if(r.bottom+y>y){pick=i;f=(y-top)/Math.max(1,r.height);}}\
        return pick+','+f+','+Math.min(1,Math.max(0,y/h));})()
        """

        func reportSpot(_ webView: WKWebView) {
            let fallback = ratio(of: webView.scrollView)
            guard isLoaded else {
                onSpot(LibraryModel.Spot(ratio: fallback))
                return
            }
            webView.evaluateJavaScript(Self.measureScript) { [weak self] value, _ in
                // 완료 처리는 주 스레드에서 온다 — 아니면 가정하지 않고 물러선다(400ms 뒤 비율로) (184).
                guard Thread.isMainThread else { return }
                MainActor.assumeIsolated {
                    guard let self else { return }
                    let parts = (value as? String)?.split(separator: ",").compactMap { Double($0) } ?? []
                    // `NaN` 이 오면 `Int(_:)` 가 앱을 끈다 (184).
                    guard parts.count == 3, parts.allSatisfy(\.isFinite) else {
                        self.onSpot(LibraryModel.Spot(ratio: fallback))
                        return
                    }
                    let block = Int(parts[0])
                    self.onSpot(LibraryModel.Spot(block: block >= 0 ? block : nil,
                                                  fraction: parts[1], ratio: parts[2]))
                }
            }
        }

        func restoreIfReady(_ webView: WKWebView) {
            guard isLoaded, let restoring else { return }
            let spot = restoring.spot
            self.restoring = nil
            let block = spot.block ?? -1
            let script = """
            (function(i,f,ratio){var els=document.querySelectorAll('[data-line]');var y;\
            if(i>=0&&i<els.length){var r=els[i].getBoundingClientRect();y=r.top+window.scrollY+f*r.height;}\
            else{y=ratio*Math.max(0,document.documentElement.scrollHeight-window.innerHeight);}\
            window.scrollTo(0,y);return y;})(\(block),\(spot.fraction),\(spot.ratio))
            """
            webView.evaluateJavaScript(script) { [weak self, weak webView] _, error in
                guard Thread.isMainThread else { return }
                MainActor.assumeIsolated {
                    if error != nil, let scrollView = webView?.scrollView {
                        // 스크립트가 안 돌면 비율로 (A17 이 틀린 경우).
                        let range = max(0, scrollView.contentSize.height - scrollView.bounds.height
                                        + scrollView.adjustedContentInset.bottom)
                        scrollView.setContentOffset(
                            CGPoint(x: 0, y: spot.ratio * range - scrollView.adjustedContentInset.top),
                            animated: false)
                    }
                    self?.onRestored()
                }
            }
        }

        private func ratio(of scrollView: UIScrollView) -> Double {
            let top = scrollView.contentOffset.y + scrollView.adjustedContentInset.top
            let range = scrollView.contentSize.height - scrollView.bounds.height
                + scrollView.adjustedContentInset.top + scrollView.adjustedContentInset.bottom
            guard range > 0 else { return 0 }
            return min(1, max(0, Double(top / range)))
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            isLoaded = true
            restoreIfReady(webView)
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
            // **`.md` 는 어디에 있든 노트로 연다** (T7, 사용자 요청 — 메모 앱의 메모 간 링크처럼).
            // 빌드 26 까지는 `assets/` 안의 것만 미리보기로 물러섰다. 노트로 열면 보고 있는
            // 폴더가 `assets` 로 끌려갔기 때문이다 (빌드 24 · 17번). 이제 **링크로 여는 길은
            // 폴더를 안 건드린다** — 그 제약이 없어졌다.
            self = Paths.isNoteFile(path) ? .note(path) : .attachment(path)
        default:
            self = .missing(path)
        }
    }
}
