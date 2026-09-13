import Foundation
import Core

/// 화면이 보는 상태. 파일은 `FolderStore`(actor) 가 만지고, 여기로는
/// **`Sendable` 값만** 건너온다 (설계서 §8).
@MainActor
final class LibraryModel: ObservableObject {

    @Published private(set) var folders: [FolderSummary] = []
    @Published private(set) var notes: [NoteSummary] = []
    @Published private(set) var kind: FolderKind = .localDocuments
    /// iCloud 컨테이너를 잡을 수 있었나. `false` 인데 `kind == .localDocuments` 면
    /// **조용히 물러난 것**이다 — 진단 화면이 이것을 크게 보여 준다 (A2).
    @Published private(set) var iCloudAvailable = false
    @Published private(set) var isLoading = false
    @Published private(set) var noteText = ""
    /// 읽기 모드에 넘길 완전한 HTML 문서 (ADR-0004).
    @Published private(set) var pageHTML = ""
    @Published private(set) var attachmentCount = 0
    /// 본문이 참조하는데 폴더에 없는 것 — 뷰어가 회색 상자로 보여 주고,
    /// 공유 전에도 알린다 (설계서 §7.6-4).
    @Published private(set) var missingAttachments: [String] = []
    @Published private(set) var lastError: String?

    /// 최상위는 빈 문자열.
    @Published var selectedFolder = ""
    @Published var selectedNoteID: String?
    /// 위 토글. **쓰기가 기본**이다 (설계서 §14-6).
    @Published var isReading = false
    /// 진단 화면이 떠 있나.
    @Published var showsDiagnostics = false
    /// 지금 쓰는 폴더의 실제 경로. 진단에만 쓴다.
    @Published private(set) var rootPath = ""

    /// 아이패드(regular 폭)는 상세 칸이 비어 있으면 어색하므로 첫 노트를 미리 고른다.
    /// **아이폰(compact)은 고르지 않는다** — 고르면 앱이 목록이 아니라 노트로 열린다
    /// (빌드 2 스크린샷에서 잡혔다). ADR-0006 의 "같은 자료를 넓은 화면으로".
    var autoSelectsFirstNote = false

    let launch: LaunchOptions
    private var store: FolderStore?

    /// 웹뷰가 `yb://` 로 파일을 읽어 갈 곳.
    var assetProvider: AssetProvider? { store }

    init(launch: LaunchOptions = .fromProcess()) {
        self.launch = launch
        self.isReading = launch.readingMode
        self.showsDiagnostics = launch.showDiagnostics
    }

    var isSample: Bool { kind == .sample }

    var selectedNote: NoteSummary? {
        notes.first { $0.id == selectedNoteID }
    }

    var folderName: String {
        // 화면 상단 제목은 **폴더 이름**이다. 앱 이름을 쓰지 않는다 (설계서 §0).
        guard let root = store?.root else { return "기록" }
        let name = Paths.normalized(root.lastPathComponent)
        return name.isEmpty ? "기록" : name
    }

    func start() async {
        guard store == nil else { return }
        await use(await FolderSource.current(launch: launch))
    }

    /// 기기 안 폴더로 물러나 있는가. 이 상태에서는 `Files` 앱에 폴더가 안 생기고
    /// 다른 기기와도 안 맞춰진다.
    var isFallenBackFromICloud: Bool {
        kind == .localDocuments && !iCloudAvailable && !launch.localFolderOnly
    }

    /// 앱이 다시 앞으로 나올 때 · 진단 화면의 버튼에서 부른다.
    ///
    /// 설치 직후 첫 실행은 컨테이너가 아직 준비되지 않아 못 잡는 일이 있다.
    /// 그때 잡히면 조용히 옮겨 탄다.
    func retryICloud() async {
        guard isFallenBackFromICloud else { return }
        guard let cloud = await FolderSource.iCloudDocuments(attempts: 2) else { return }
        await use(FolderChoice(url: cloud, kind: .iCloudContainer,
                               iCloudAvailable: true, attempts: 2))
    }

    private func use(_ choice: FolderChoice) async {
        await store?.close()
        store = FolderStore(root: choice.url, kind: choice.kind)
        kind = choice.kind
        iCloudAvailable = choice.iCloudAvailable
        rootPath = choice.url.path
        selectedFolder = ""
        selectedNoteID = nil
        await reloadFolders()
        await reloadNotes()
    }

    /// 사용자가 복사해 붙일 수 있는 것. **글과 사진은 담지 않는다.**
    var diagnosticsText: String {
        """
        느린 여백 진단
        판: \(Bundle.appVersion) (\(Bundle.appBuild))
        번들: \(Bundle.main.bundleIdentifier ?? "-")
        폴더 종류: \(kind.rawValue) (\(kind.label))
        iCloud 잡음: \(iCloudAvailable ? "예" : "아니오")
        물러남: \(isFallenBackFromICloud ? "예" : "아니오")
        경로: \(rootPath)
        노트: \(notes.count)개 · 하위 폴더: \(folders.count)개
        마지막 오류: \(lastError ?? "없음")
        """
    }

    func reloadFolders() async {
        guard let store else { return }
        folders = await store.folders()
    }

    func reloadNotes() async {
        guard let store else { return }
        isLoading = true
        let loaded = await store.notes(in: selectedFolder)
        notes = loaded
        if let current = selectedNoteID, !loaded.contains(where: { $0.id == current }) {
            selectedNoteID = nil
        }
        if selectedNoteID == nil, autoSelectsFirstNote {
            selectedNoteID = loaded.first?.id
        }
        isLoading = false
        await loadSelectedText()
    }

    func loadSelectedText() async {
        guard let store, let note = selectedNote else {
            clearNote()
            return
        }
        do {
            let text = try await store.readText(at: note.relativePath)
            noteText = text

            // 두 단계다 (MarkdownHTML.referencedPaths 주석 참고): 파일이 있는지
            // 아는 것은 actor 뿐인데 렌더는 순수 함수라 기다릴 수 없다.
            let referenced = MarkdownHTML.referencedPaths(markdown: text, notePath: note.relativePath)
            let existing = await store.existingPaths(among: referenced)

            let rendered = MarkdownHTML.render(
                markdown: text,
                notePath: note.relativePath,
                existing: existing)

            pageHTML = MarkdownHTML.page(bodyHTML: rendered.bodyHTML, css: Palette.cssTokens())
            attachmentCount = existing.count
            missingAttachments = rendered.missingAttachments
            lastError = nil
        } catch {
            clearNote()
            lastError = error.localizedDescription
        }
    }

    /// 폴더 안의 다른 노트를 뷰어에서 탭했을 때.
    func open(relativePath: String) {
        if let match = notes.first(where: { $0.relativePath == relativePath }) {
            selectedNoteID = match.id
            return
        }
        // 다른 폴더의 노트다 — 그 폴더로 옮겨 가서 고른다.
        selectedFolder = Paths.directory(of: relativePath)
        selectedNoteID = relativePath
    }

    private func clearNote() {
        noteText = ""
        pageHTML = ""
        attachmentCount = 0
        missingAttachments = []
    }
}
