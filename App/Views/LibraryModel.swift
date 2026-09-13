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
    @Published private(set) var attachmentCount = 0
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

    init(launch: LaunchOptions = .fromProcess()) {
        self.launch = launch
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
            noteText = ""
            attachmentCount = 0
            return
        }
        do {
            let text = try await store.readText(at: note.relativePath)
            noteText = text
            // Core 가 세어 준다. 공유(§7.6)와 첨부 표시(§7.3)가 같은 추출기를 쓴다.
            attachmentCount = MarkdownLinks.extract(from: text)
                .filter { link in
                    if case .relative = Paths.resolve(link: link.destination, fromNoteAt: note.relativePath) {
                        return true
                    }
                    return false
                }
                .count
            lastError = nil
        } catch {
            noteText = ""
            attachmentCount = 0
            lastError = error.localizedDescription
        }
    }
}
