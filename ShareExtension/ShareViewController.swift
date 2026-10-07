import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// **다른 앱의 공유 메뉴 → 느린 여백** (213).
///
/// 받은 것(글 · 주소 · 사진)을 보여 주고, **보내기**를 누르면 받은 글 상자(`ShareInbox`)에 둔다. 앱이 앞으로 나오면
/// 그것이 `받은 글` 폴더의 새 노트가 된다. 확장은 사용자 폴더를 직접 열지 않는다 — 폴더 권한은 앱의 것이다.
///
/// 이름을 못 박아 둔다(`@objc`) — `Info.plist` 의 `NSExtensionPrincipalClass` 가 모듈 이름 없이 찾는다.
@objc(ShareViewController)
final class ShareViewController: UIViewController {

    private let model = ShareModel()

    override func viewDidLoad() {
        super.viewDidLoad()
        model.onFinish = { [weak self] sent in self?.finish(sent: sent) }
        let host = UIHostingController(rootView: ShareView(model: model))
        addChild(host)
        host.view.frame = view.bounds
        host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(host.view)
        host.didMove(toParent: self)

        let items = (extensionContext?.inputItems as? [NSExtensionItem]) ?? []
        Task { await model.load(items) }
    }

    private func finish(sent: Bool) {
        if sent {
            extensionContext?.completeRequest(returningItems: nil)
        } else {
            extensionContext?.cancelRequest(withError: NSError(domain: NSCocoaErrorDomain,
                                                               code: NSUserCancelledError))
        }
    }
}

/// 받은 것 · 보내기. 모두 주 액터에서 돈다 — `NSItemProvider` 를 다른 곳으로 넘기지 않는다.
/// 읽기 완료 처리는 **다른 큐에서** 불린다 — 클로저에 `@Sendable` 을 붙여 주 액터로 추정되지 않게 한다
/// (Swift 6 은 주 액터로 추정된 클로저가 다른 큐에서 불리면 앱을 멈춘다). 안에서는 값만 만들어 넘긴다.
@MainActor
final class ShareModel: ObservableObject {
    @Published var text = ""
    @Published var url: String?
    @Published var pageTitle: String?
    @Published var imageCount = 0
    @Published var isLoading = true
    @Published var isSending = false
    @Published var failure: String?

    var onFinish: @MainActor (Bool) -> Void = { _ in }
    private var imageProviders: [NSItemProvider] = []

    var isEmpty: Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && url == nil && imageCount == 0
    }

    func load(_ items: [NSExtensionItem]) async {
        for item in items {
            // 사파리는 주소와 함께 쪽 제목을 준다.
            let caption = (item.attributedContentText?.string ?? item.attributedTitle?.string)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            for provider in item.attachments ?? [] {
                if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
                    imageProviders.append(provider)
                } else if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
                    guard url == nil, let found = await loadURL(provider), !found.isFileURL else { continue }
                    url = found.absoluteString
                    if let caption, !caption.isEmpty, caption != url { pageTitle = caption }
                } else if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
                    guard let found = await loadText(provider), !found.isEmpty else { continue }
                    text += (text.isEmpty ? "" : "\n\n") + found
                }
            }
        }
        imageCount = imageProviders.count
        isLoading = false
    }

    func send() async {
        guard !isSending else { return }
        isSending = true
        failure = nil
        let inbox = ShareInbox()
        var opened: URL?
        do {
            let folder = try await inbox.begin()
            opened = folder
            var names: [String] = []
            for (index, provider) in imageProviders.enumerated() {
                guard let image = await loadImage(provider) else { continue }
                names.append(try await inbox.writeImage(image.data, ext: image.ext, index: index + 1, in: folder))
            }
            try await inbox.finish(ShareInbox.Item(text: text, url: url, pageTitle: pageTitle,
                                                   images: names, created: Date()), in: folder)
            onFinish(true)
        } catch {
            if let opened { await inbox.discard(opened) }
            failure = String(localized: "보내지 못했습니다. 잠시 뒤 다시 해 주세요.")
            isSending = false
        }
    }

    // MARK: - 받은 것 읽기

    private func loadURL(_ provider: NSItemProvider) async -> URL? {
        await withCheckedContinuation { continuation in
            provider.loadItem(forTypeIdentifier: UTType.url.identifier, options: nil) { @Sendable item, _ in
                let found: URL?
                if let value = item as? URL {
                    found = value
                } else if let value = item as? String {
                    found = URL(string: value)
                } else if let value = item as? Data {
                    found = URL(dataRepresentation: value, relativeTo: nil)
                } else {
                    found = nil
                }
                continuation.resume(returning: found)
            }
        }
    }

    private func loadText(_ provider: NSItemProvider) async -> String? {
        await withCheckedContinuation { continuation in
            provider.loadItem(forTypeIdentifier: UTType.plainText.identifier, options: nil) { @Sendable item, _ in
                let found: String?
                if let value = item as? String {
                    found = value
                } else if let value = item as? Data {
                    found = String(data: value, encoding: .utf8)
                } else if let value = item as? URL, value.isFileURL {
                    found = try? String(contentsOf: value, encoding: .utf8)
                } else {
                    found = nil
                }
                continuation.resume(returning: found)
            }
        }
    }

    /// 사진의 원래 데이터 — 앱이 가져갈 때 사진 넣기와 같은 길로 다시 읽고 줄인다 (`ImageImport`).
    private func loadImage(_ provider: NSItemProvider) async -> (data: Data, ext: String)? {
        let type = provider.registeredTypeIdentifiers
            .compactMap { UTType($0) }
            .first { $0.conforms(to: .image) } ?? .image
        let ext = type.preferredFilenameExtension ?? "img"
        let data: Data? = await withCheckedContinuation { continuation in
            provider.loadDataRepresentation(forTypeIdentifier: type.identifier) { @Sendable data, _ in
                continuation.resume(returning: data)
            }
        }
        guard let data else { return nil }
        return (data, ext)
    }
}

struct ShareView: View {
    @ObservedObject var model: ShareModel
    @ScaledMetric(relativeTo: .body) private var editorHeight: CGFloat = 140

    var body: some View {
        NavigationStack {
            Form {
                if model.isLoading {
                    ProgressView()
                } else {
                    Section {
                        TextEditor(text: $model.text)
                            .frame(minHeight: editorHeight)
                    } header: {
                        Text("글")
                    }
                    if let url = model.url {
                        Section {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(model.pageTitle ?? url)
                                    .font(.body)
                                Text(url)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                        } header: {
                            Text("주소")
                        }
                    }
                    if model.imageCount > 0 {
                        Section {
                            Label("사진 \(model.imageCount)장", systemImage: "photo.on.rectangle")
                        }
                    }
                    Section {
                        Text("앱을 열면 받은 글 폴더에 새 노트로 들어갑니다.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        if let failure = model.failure {
                            Text(failure)
                                .font(.footnote)
                                .foregroundStyle(.red)
                        }
                    }
                }
            }
            .navigationTitle("느린 여백에 보내기")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("취소") { model.onFinish(false) }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("보내기") {
                        Task { await model.send() }
                    }
                    .disabled(model.isLoading || model.isSending || model.isEmpty)
                }
            }
        }
    }
}
