import Foundation
import UniformTypeIdentifiers
import WebKit
import Core

/// 웹뷰에 폴더 안 파일을 건네주는 것.
///
/// `loadFileURL` 이 아니라 커스텀 스킴을 쓰는 이유 (ADR-0004):
/// 보안 범위 북마크로 연 폴더((b))에서는 `loadFileURL` 의 `readAccessURL` 제약이
/// 걸린다. 스킴 핸들러는 우리가 직접 `Data` 를 만들어 주므로 그 제약이 없다.
/// 실기기에서 확인해야 하는 **가정 A3** 다.
protocol AssetProvider: Sendable {
    /// 폴더 기준 상대경로의 내용. 없으면 `nil`.
    func data(forRelativePath path: String) async -> Data?
}

/// WebKit 은 이 메서드들을 **메인 스레드에서만** 부른다. 그런데 SDK 가
/// `WKURLSchemeHandler` 를 `@MainActor` 로 표시하는지는 판본마다 다르므로,
/// 클래스를 `@MainActor` 로 못 박으면 적합성이 깨질 수 있다. 그래서 격리를
/// 걸지 않고 `@unchecked Sendable` 로 두되, **상태는 메인에서만 만진다**는
/// 규약을 이 주석과 `Task { @MainActor in }` 로 지킨다.
final class NoteSchemeHandler: NSObject, WKURLSchemeHandler, @unchecked Sendable {

    var assets: AssetProvider?

    private var running: Set<ObjectIdentifier> = []

    func webView(_ webView: WKWebView, start task: any WKURLSchemeTask) {
        let identifier = ObjectIdentifier(task)
        running.insert(identifier)

        guard let url = task.request.url, url.host == "note", let assets else {
            finish(task, identifier: identifier, with: Self.placeholderPNG, mimeType: "image/png")
            return
        }

        let path = MarkdownHTML.relativePath(fromURLPath: url.path)
        let mimeType = Self.mimeType(for: path)

        Task { @MainActor [weak self] in
            let data = await assets.data(forRelativePath: path)
            self?.finish(task,
                         identifier: identifier,
                         with: data ?? Self.placeholderPNG,
                         mimeType: data == nil ? "image/png" : mimeType)
        }
    }

    func webView(_ webView: WKWebView, stop task: any WKURLSchemeTask) {
        // 끝난 작업에 응답하면 크래시한다. 멈춘 것을 지워 둔다.
        running.remove(ObjectIdentifier(task))
    }

    private func finish(_ task: any WKURLSchemeTask, identifier: ObjectIdentifier, with data: Data, mimeType: String) {
        guard running.contains(identifier), let url = task.request.url else { return }
        running.remove(identifier)

        let response = URLResponse(url: url,
                                   mimeType: mimeType,
                                   expectedContentLength: data.count,
                                   textEncodingName: nil)
        task.didReceive(response)
        task.didReceive(data)
        task.didFinish()
    }

    private static func mimeType(for path: String) -> String {
        let ext = Paths.fileExtension(path)
        if let type = UTType(filenameExtension: ext)?.preferredMIMEType {
            return type
        }
        return "application/octet-stream"
    }

    /// 1×1 투명 PNG. 파일이 없을 때 웹뷰가 기다리지 않게 한다 —
    /// 사용자에게 보이는 회색 상자는 `MarkdownHTML` 이 HTML 로 만든다.
    private static let placeholderPNG: Data = Data([
        0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A,
        0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52,
        0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
        0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4,
        0x89, 0x00, 0x00, 0x00, 0x0A, 0x49, 0x44, 0x41,
        0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
        0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00,
        0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE,
        0x42, 0x60, 0x82
    ])
}
