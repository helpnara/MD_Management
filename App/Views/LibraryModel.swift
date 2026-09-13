import Foundation
import Core

/// 화면이 보는 상태. 파일은 `FolderStore`(actor) 가 만지고, 여기로는
/// **`Sendable` 값만** 건너온다 (설계서 §8).
@MainActor
final class LibraryModel: ObservableObject {

    @Published private(set) var folders: [FolderSummary] = []
    @Published private(set) var notes: [NoteSummary] = []
    @Published private(set) var kind: FolderKind = .localDocuments
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
    }

    var isSample: Bool { kind == .sample }

    var selectedNote: NoteSummary? {
        notes.first { $0.id == selectedNoteID }
    }

    var folderName: String {
        // 화면 상단 제목은 **폴더 이름**이다. 앱 이름을 쓰지 않는다 (설계서 §0).
        guard let root = store?.root else { return "기록" }
        return Paths.baseName(root.lastPathComponent).isEmpty
            ? "기록"
            : Paths.normalized(root.lastPathComponent)
    }

    func start() async {
        guard store == nil else { return }
        let (url, kind) = FolderSource.current(launch: launch)
        store = FolderStore(root: url, kind: kind)
        self.kind = kind
        await reloadFolders()
        await reloadNotes()
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
