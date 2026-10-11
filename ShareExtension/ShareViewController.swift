import SwiftUI
import UIKit
import UniformTypeIdentifiers
import LinkPresentation

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

/// 제목 창구(oEmbed)의 대답 — `title` 만 읽는다 (240).
private struct TitleAnswer: Decodable, Sendable {
    let title: String?
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
    /// **넣을 곳** (241) — 앱이 적어 둔 고정한 노트들. nil 이면 받은 글 폴더에 새 노트.
    @Published var targets: [ShareInbox.Target] = []
    @Published var target: String?
    /// 마지막에 고른 곳 — 같은 주제를 이어 모을 때 다시 고르지 않게. 확장 자기 설정에만 둔다.
    static let targetKey = "share.target"

    var onFinish: @MainActor (Bool) -> Void = { _ in }
    private var imageProviders: [NSItemProvider] = []
    /// **주소만 온 공유의 제목 가져오기** (240). 보내기가 이것을 기다린다 — 길어도 `titleTimeout` 까지.
    private var titleTask: Task<Void, Never>?
    /// 가져오는 동안 붙들어 둔다 — 놓으면 가져오기가 멈출 수 있다.
    private var metadataProvider: LPMetadataProvider?
    /// 오래 기다리게 하지 않는다 — 못 가져오면 예전처럼 주소만 넣는다.
    static let titleTimeout: TimeInterval = 5

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
        // 유튜브 같은 앱은 주소를 글로 준다 — 글이 주소 하나뿐이면 주소로 옮겨 사파리와 같은 길을 탄다 (240 · 빌드 99 사용자 화면).
        let separated = SharedAddress.separate(text: text, url: url)
        text = separated.text
        url = separated.url
        imageCount = imageProviders.count
        targets = await ShareInbox().targets()
        // 마지막에 고른 노트가 아직 고정돼 있으면 그대로 고른다.
        let remembered = UserDefaults.standard.string(forKey: Self.targetKey)
        target = targets.contains { $0.path == remembered } ? remembered : nil
        isLoading = false
        fetchTitleIfMissing()
    }

    /// **주소만 왔으면 그 쪽의 제목을 가져온다** (240, 2026-10-11 사용자 — *유튜브에서 공유하면 받은 글에 링크만 들어온다*).
    /// 사파리는 주소와 함께 제목을 주지만(`attributedContentText`) 유튜브 같은 앱은 주소만 준다. 애플의 링크 미리보기
    /// (`LinkPresentation` — 메시지 앱이 쓰는 것)로 그 주소에 **한 번** 접속해 제목만 읽는다. 다른 것은 보내지 않는다 (처리방침).
    /// **유튜브는 그 사이트가 여는 제목 창구(oEmbed)로** — 쪽을 읽으면 채널 이름이 잡혔다 (빌드 100 사용자 · `SharedAddress.titleService`).
    /// 못 가져오면 예전 그대로 — 제목 칸은 사이트 이름, 본문은 주소 링크.
    private func fetchTitleIfMissing() {
        guard pageTitle == nil, let address = url, let target = URL(string: address),
              let scheme = target.scheme?.lowercased(), scheme == "https" || scheme == "http" else { return }
        // 유튜브는 공식 창구(oEmbed)로만 — 쪽을 읽으면 제목 대신 채널 이름이 잡힌다 (빌드 100 사용자). 못 가져오면 제목 없이.
        let service = SharedAddress.titleService(for: address).flatMap { URL(string: $0) }
        titleTask = Task { [weak self] in
            guard let self else { return }
            let title: String?
            if let service {
                title = await Self.serviceTitle(service)
            } else {
                title = await self.previewTitle(target)
            }
            let trimmed = title?.trimmingCharacters(in: .whitespacesAndNewlines)
            // 제목이 주소 그대로면 쓸모가 없다.
            if self.pageTitle == nil, let trimmed, !trimmed.isEmpty, trimmed != address {
                self.pageTitle = trimmed
            }
        }
    }

    /// 애플 링크 미리보기 — 쪽의 제목.
    private func previewTitle(_ target: URL) async -> String? {
        let provider = LPMetadataProvider()
        provider.timeout = Self.titleTimeout
        metadataProvider = provider
        let title: String? = await withCheckedContinuation { continuation in
            provider.startFetchingMetadata(for: target) { @Sendable metadata, _ in
                continuation.resume(returning: metadata?.title)
            }
        }
        metadataProvider = nil
        return title
    }

    /// 사이트가 여는 제목 창구(oEmbed) — 받은 것의 `title` 만 읽는다. 쿠키 · 캐시를 남기지 않는다.
    private static func serviceTitle(_ service: URL) async -> String? {
        let request = URLRequest(url: service, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: titleTimeout)
        let session = URLSession(configuration: .ephemeral)
        defer { session.finishTasksAndInvalidate() }
        guard let answer = try? await session.data(for: request),
              (answer.1 as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return (try? JSONDecoder().decode(TitleAnswer.self, from: answer.0))?.title
    }

    func send() async {
        guard !isSending else { return }
        isSending = true
        failure = nil
        // 제목을 가져오는 중이면 기다린다 (240) — 길어도 `titleTimeout`. 보낸 뒤에 온 제목은 노트에 못 들어간다.
        await titleTask?.value
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
                                                   images: names, created: Date(), target: target), in: folder)
            UserDefaults.standard.set(target, forKey: Self.targetKey)
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
                    if !model.targets.isEmpty {
                        Section {
                            Picker("넣을 곳", selection: $model.target) {
                                Text("새 노트").tag(String?.none)
                                ForEach(model.targets) { item in
                                    Text(item.name).tag(String?.some(item.path))
                                }
                            }
                        }
                    }
                    Section {
                        Text(model.target == nil
                             ? String(localized: "앱을 열면 받은 글 폴더에 새 노트로 들어갑니다.")
                             : String(localized: "앱을 열면 고른 노트의 맨 끝에 한 줄로 덧붙입니다."))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        if model.targets.isEmpty {
                            Text("노트를 고정해 두면 여기서 그 노트에 덧붙일 수 있습니다.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
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
