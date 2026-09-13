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
    /// 편집기가 들고 있는 지금 글. 아직 파일에 안 들어갔을 수 있다.
    @Published private(set) var draft = ""
    /// 저장할 것이 남았나. **저장이 실패해도 내리지 않는다** — 다음 기회에 다시 쓴다.
    @Published private(set) var isDirty = false
    @Published private(set) var lastSaved: Date?
    /// 마지막 저장이 실패했나. 화면 위 표시가 이것만 본다 — 읽기 오류와 섞이면
    /// 사용자가 무엇이 위험한지 못 가린다.
    @Published private(set) var saveFailed = false
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

    /// **지금 글이 어느 파일의 것인가.** `selectedNote` 를 보지 않는 이유는,
    /// 사용자가 노트를 바꾸면 그 값이 먼저 바뀌어 **이전 글이 새 파일에 덮일** 수
    /// 있기 때문이다. 저장은 언제나 이 경로로 간다.
    private var draftPath: String?
    private var autosave: Task<Void, Never>?

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
        // 화면 상단 제목은 **폴더 이름**이다 (설계서 §0).
        // (a) iCloud 컨테이너의 실제 폴더명은 `Documents` 라 제목으로 쓸 수 없다.
        //     `Files` 앱에 보이는 이름과 같은 것을 쓴다 — Info.plist 에서 읽으므로
        //     이름이 사는 곳이 늘지 않는다.
        if kind == .iCloudContainer, let name = FolderSource.iCloudFolderName {
            return name
        }
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

    /// 첨부가 제대로 뜨는지 **한 번 눌러 보는** 시험 (가정 A3 · A13).
    ///
    /// 손으로 하려면 사진을 `assets/` 에 넣고 다른 앱으로 `.md` 를 고쳐야 하는데,
    /// 그 과정에서 실수가 나면 원인 찾기가 더 어려워진다. 앱이 직접 만든다.
    ///
    /// 세 가지를 **갈라서** 본다 — 어느 것만 안 보이는지가 곧 원인이다:
    /// 1. 영문 이름 (`test.png`) — 폴더의 파일을 읽는가 (**A3**)
    /// 2. 한글 · 공백 이름 — iCloud 를 거쳐도 이름이 안 깨지는가 (**A13**)
    /// 3. 같은 파일을 퍼센트 인코딩으로 — 옵시디언이 쓰는 꼴
    func makeAttachmentTest() async {
        guard let store else { return }
        guard let png = SampleFolder.testPNG() else {
            lastError = "시험 그림을 만들지 못했습니다"
            return
        }
        do {
            try await store.createFolder("assets")
            try await store.writeData(png, to: "assets/test.png")
            try await store.writeData(png, to: "assets/시험 사진.png")
            try await store.writeText(Self.attachmentTestNote, to: "첨부 시험.md")

            await reloadFolders()
            await reloadNotes()
            selectedNoteID = "첨부 시험.md"
            isReading = true
            showsDiagnostics = false
            lastError = nil
        } catch {
            lastError = "시험 파일을 만들지 못했습니다: \(error.localizedDescription)"
        }
    }

    /// 곧은 따옴표를 문구 안에 쓰지 않는다 (CLAUDE.md §5).
    private static let attachmentTestNote = """
    # 첨부 시험

    **셋 다 그림이 보이면** 통과입니다. 점선 상자에 경로가 뜬 것이 어긋난 자리입니다.
    확인이 끝나면 이 노트와 `assets` 의 사진을 지우셔도 됩니다.

    ## 1. 영문 이름

    ![](assets/test.png)

    ## 2. 한글 · 공백 이름

    ![](<assets/시험 사진.png>)

    ## 3. 같은 사진을 퍼센트 인코딩으로

    ![](assets/%EC%8B%9C%ED%97%98%20%EC%82%AC%EC%A7%84.png)
    """

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
        저장 안 된 글: \(isDirty ? "있음" : "없음")
        마지막 저장: \(lastSaved.map { $0.formatted(date: .omitted, time: .standard) } ?? "없음")
        마지막 오류: \(lastError ?? "없음")
        """
    }

    // MARK: - 편집 · 자동 저장

    /// 멈춘 뒤 얼마 만에 쓰나 (설계서 §7.3).
    private static let autosaveDelay = Duration.seconds(2)

    /// 편집기가 한 글자 바뀔 때마다 부른다.
    func noteEdited(_ text: String) {
        guard draftPath != nil, text != draft else { return }
        draft = text
        isDirty = true
        autosave?.cancel()
        autosave = Task { [weak self] in
            try? await Task.sleep(for: Self.autosaveDelay)
            guard !Task.isCancelled else { return }
            await self?.save()
        }
    }

    /// 지금 쓴다. 노트를 바꾸기 전 · 앱이 뒤로 갈 때 · 읽기로 넘길 때 부른다.
    ///
    /// **자료 유실이 가장 비싼 자리다.** 실패하면 오류를 올리고 `isDirty` 를
    /// 그대로 둔다 — 다음 기회(2초 뒤 · 화면 전환 · 앱 종료 직전)에 다시 쓴다.
    func save() async {
        autosave?.cancel()
        autosave = nil
        guard isDirty, let store, let path = draftPath else { return }
        do {
            try await store.writeText(draft, to: path)
            noteText = draft
            isDirty = false
            saveFailed = false
            lastSaved = Date()
            lastError = nil
            await renderReading(path: path, text: draft)
        } catch {
            saveFailed = true
            lastError = "저장하지 못했습니다: \(error.localizedDescription)"
        }
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
        // **읽기 전에 쓴다.** 노트를 바꾸는 길목이 여기다 — 남은 글을 먼저 파일에
        // 넣지 않으면 그대로 사라진다.
        await save()

        guard let store, let note = selectedNote else {
            clearNote()
            return
        }
        do {
            let text = try await store.readText(at: note.relativePath)
            noteText = text
            draft = text
            draftPath = note.relativePath
            isDirty = false
            await renderReading(path: note.relativePath, text: text)
            lastError = nil
        } catch {
            clearNote()
            lastError = error.localizedDescription
        }
    }

    /// 읽기 모드에 넘길 HTML 을 다시 만든다.
    ///
    /// 두 단계다 (`MarkdownHTML.referencedPaths` 주석 참고): 파일이 있는지 아는
    /// 것은 actor 뿐인데 렌더는 순수 함수라 기다릴 수 없다.
    private func renderReading(path: String, text: String) async {
        guard let store else { return }
        let referenced = MarkdownHTML.referencedPaths(markdown: text, notePath: path)
        let existing = await store.existingPaths(among: referenced)
        let rendered = MarkdownHTML.render(markdown: text, notePath: path, existing: existing)

        pageHTML = MarkdownHTML.page(bodyHTML: rendered.bodyHTML, css: Palette.cssTokens())
        attachmentCount = existing.count
        missingAttachments = rendered.missingAttachments
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
        draft = ""
        draftPath = nil
        isDirty = false
        pageHTML = ""
        attachmentCount = 0
        missingAttachments = []
    }
}
