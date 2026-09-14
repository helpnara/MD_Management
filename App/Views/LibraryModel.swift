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
    /// 이름을 바꾸는 중인 노트 · 새 이름. 화면의 알림창이 이것을 본다.
    @Published var renaming: NoteSummary?
    @Published var renameText = ""
    /// 지울지 묻는 중인 노트. **모든 삭제에 확인** (CLAUDE.md §1).
    @Published var trashing: NoteSummary?

    /// 이름을 바꾸는 중인 하위 폴더 · 지울지 묻는 중인 하위 폴더 (사용자 요청, 빌드 17).
    @Published var renamingFolder: FolderSummary?
    @Published var folderRenameText = ""
    @Published var trashingFolder: FolderSummary?
    /// 새 폴더 이름을 묻는 중인가 · 그 이름. 폴더 화면의 알림창이 이것을 본다 (52).
    @Published var creatingFolder = false
    @Published var newFolderName = ""
    /// 영구 삭제를 묻는 중인 대상 · 사용자가 친 확인 문구. **되돌릴 수 없는 유일한
    /// 삭제**라 설계서 §7.1 대로 `지우기` 를 그대로 쳐야만 지운다 (51).
    @Published var purging: Purge?
    @Published var purgeText = ""

    enum Purge: Identifiable {
        case all
        case one(NoteSummary)

        var id: String {
            switch self {
            case .all: return "*"
            case .one(let note): return note.id
            }
        }
    }

    /// 영구 삭제 확인 문구. 화면과 검사가 같은 값을 본다.
    static let purgeConfirmation = "지우기"

    /// 편집기가 커서 자리에 넣어야 할 글. 사진을 고르면 여기 링크가 실린다.
    /// `Identifiable` 인 이유: 같은 글을 두 번 넣어도 새 요청으로 보이게.
    @Published var insertion: Insertion?

    struct Insertion: Identifiable, Equatable {
        let id = UUID()
        let text: String
    }

    /// 지금 떠 있는 시트. **하나로 모아 둔다** — `.sheet` 를 한 뷰에 여러 개
    /// 걸면 마지막 것만 뜬다 (SwiftUI 의 오랜 함정).
    @Published var sheet: Sheet?

    enum Sheet: Identifiable {
        case settings
        case diagnostics
        /// `파일` 앱이 건넨, 내 폴더 **밖**의 파일. 가져올지 물어야 한다.
        case incoming(IncomingFile)

        var id: String {
            switch self {
            case .settings: return "settings"
            case .diagnostics: return "diagnostics"
            case .incoming(let file): return "incoming-\(file.id)"
            }
        }
    }
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
    /// 글을 읽었을 때 · 마지막으로 썼을 때의 파일 도장. 저장 직전에 견준다 (A15).
    private var draftStamp: FileStamp?
    private var autosave: Task<Void, Never>?
    /// **편집기의 정체성.** 파일을 실제로 읽어 편집기에 새 글을 넣을 때만 바뀐다.
    /// 경로를 정체성으로 쓰면 제목 따라 이름이 바뀔 때(54) 편집기가 글을 갈아 끼우며
    /// 커서와 키보드를 잃는다. 이름이 바뀌어도 글은 같다 — 정체성도 같다.
    @Published private(set) var editorSession = UUID()

    /// 폴더를 잡기 전에 `파일` 앱이 먼저 건넨 파일. 폴더가 서면 그때 연다.
    private var pendingOpen: URL?

    /// 웹뷰가 `yb://` 로 파일을 읽어 갈 곳.
    var assetProvider: AssetProvider? { store }

    init(launch: LaunchOptions = .fromProcess()) {
        self.launch = launch
        self.isReading = launch.readingMode
        if launch.showDiagnostics {
            self.sheet = .diagnostics
        } else if launch.showSettings {
            self.sheet = .settings
        }
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

        // 폴더가 서기 전에 `파일` 앱이 건넨 것이 있으면 이제 연다.
        if let pending = pendingOpen {
            pendingOpen = nil
            await open(fileURL: pending)
        }
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
            sheet = nil
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

    // MARK: - `파일` 앱에서 건너온 파일

    /// 내 폴더 밖의 파일. 가져오기 전까지는 **읽기만** 한다.
    struct IncomingFile: Identifiable {
        let id = UUID()
        let url: URL
        let name: String
        let text: String
    }

    /// `파일` 앱에서 `.md` 를 눌렀을 때 (`CFBundleDocumentTypes`).
    ///
    /// 두 갈래다. **내 폴더 안의 파일이면 그냥 그 노트를 연다** — 가장 흔한 길이고,
    /// 사용자의 노트는 대개 이 폴더에 있다. 밖의 파일이면 가져올지 묻는다.
    ///
    /// **밖의 파일을 그 자리에서 고치게 하지 않는다.** 보안 범위 접근이 언제 끊길지
    /// 모르는 파일에 자동 저장을 걸면 저장이 조용히 실패한다 — 이 앱에서 가장
    /// 피하고 싶은 일이다 (ADR-0001).
    func open(fileURL url: URL) async {
        guard let store else {
            // 폴더가 아직 안 섰다. `use(_:)` 끝에서 이어 받는다.
            pendingOpen = url
            return
        }

        // 보안 범위 — 내 폴더 밖의 파일은 이 문을 열어야 읽힌다.
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }

        let path = url.standardizedFileURL.path
        let root = store.root.standardizedFileURL.path

        if let relative = Paths.relative(of: path, under: root) {
            guard !Paths.isHidden(relative) else { return }
            await save()
            selectedFolder = Paths.directory(of: relative)
            selectedNoteID = relative
            isReading = false
            lastError = nil
            return
        }

        do {
            // 파일 읽기는 주 액터 밖에서. 화면이 멈추지 않게 (설계서 §8).
            let text = try await Task.detached {
                try String(contentsOf: url, encoding: .utf8)
            }.value
            sheet = .incoming(IncomingFile(url: url,
                                           name: Paths.normalized(url.lastPathComponent),
                                           text: text))
        } catch {
            lastError = "파일을 읽지 못했습니다: \(error.localizedDescription)"
        }
    }

    /// 밖의 파일을 내 폴더로 **복사**해 열어 준다. 원본은 건드리지 않는다.
    /// 같은 이름이 있으면 저장소가 `이름 2.md` 로 비켜 간다 — 남의 노트를 덮지 않는다.
    func importIncoming(_ file: IncomingFile) async {
        guard let store else { return }
        await save()
        do {
            let path = try await store.createNote(named: file.name, in: selectedFolder, text: file.text)
            sheet = nil
            await reloadNotes()
            selectedNoteID = path
            isReading = false
            lastError = nil
        } catch {
            lastError = "가져오지 못했습니다: \(error.localizedDescription)"
        }
    }

    // MARK: - 새 노트 · 이름 바꾸기 · 지우기

    /// 지금 폴더에 새 노트를 만들고 연다.
    func createNote() async {
        guard let store else { return }
        await save()
        do {
            let path = try await store.createNote(named: "새 노트", in: selectedFolder,
                                                  text: "# 새 노트\n\n")
            await reloadNotes()
            selectedNoteID = path
            isReading = false
            lastError = nil
        } catch {
            lastError = "노트를 만들지 못했습니다: \(error.localizedDescription)"
        }
    }

    /// 최상위에 하위 폴더를 만들고 그 폴더로 간다 (52).
    func finishCreateFolder() async {
        guard let store else { return }
        creatingFolder = false
        let name = newFolderName.trimmingCharacters(in: .whitespacesAndNewlines)
        newFolderName = ""
        guard !name.isEmpty else { return }
        await save()
        do {
            let path = try await store.createSubfolder(named: name)
            await reloadFolders()
            selectedFolder = path
            lastError = nil
        } catch {
            lastError = "폴더를 만들지 못했습니다: \(error.localizedDescription)"
        }
    }

    func beginRenameFolder(_ folder: FolderSummary) {
        folderRenameText = folder.name
        renamingFolder = folder
    }

    /// 하위 폴더 이름 바꾸기. 그 폴더를 보고 있었으면 새 이름으로 따라간다.
    func finishRenameFolder(_ folder: FolderSummary) async {
        guard let store else { return }
        renamingFolder = nil
        let name = folderRenameText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name != folder.name else { return }
        await save()
        do {
            let moved = try await store.renameFolder(folder.relativePath, to: name)
            let wasViewing = selectedFolder == folder.relativePath
            if wasViewing { selectedNoteID = nil }
            await reloadFolders()
            if wasViewing { selectedFolder = moved }
            lastError = nil
        } catch {
            lastError = "폴더 이름을 바꾸지 못했습니다: \(error.localizedDescription)"
        }
    }

    /// 하위 폴더를 통째로 휴지통으로. 확인은 화면이 받았다. 보고 있던 폴더면 최상위로 돌아간다.
    func finishTrashFolder(_ folder: FolderSummary) async {
        guard let store else { return }
        trashingFolder = nil
        await save()
        do {
            let wasViewing = selectedFolder == folder.relativePath
            if wasViewing { selectedNoteID = nil }
            _ = try await store.trashFolder(folder.relativePath)
            await reloadFolders()
            if wasViewing { selectedFolder = "" }
            lastError = nil
        } catch {
            lastError = "폴더를 지우지 못했습니다: \(error.localizedDescription)"
        }
    }

    func beginRename(_ note: NoteSummary) {
        renameText = Paths.baseName(note.fileName)
        renaming = note
    }

    /// **대상을 인자로 받는다.** 확인 창의 버튼을 누르면 SwiftUI 가 창을 닫으며
    /// `renaming` 을 먼저 `nil` 로 지우고, 이 일은 그 뒤에 돈다. 빌드 8 에서 그래서
    /// 이름 바꾸기 · 지우기가 조용히 아무것도 안 했다 (4 · 6번).
    func finishRename(_ note: NoteSummary) async {
        guard let store else { return }
        renaming = nil
        let name = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        await save()
        do {
            let moved = try await store.rename(note.relativePath, to: name)
            // **파일명을 바꾸면 첫 줄 제목이 따라간다** (54 의 반대 방향, 빌드 16 · 2번).
            // 열려 있던 노트는 `save()` 로 먼저 비웠으므로 파일이 최신이다. 파일을 고치고
            // 다시 읽는다 — 편집기는 새 글을 받는다 (이름 바꾸기 창에서 왔으니 커서는 잃어도 된다).
            let newName = moved.split(separator: "/").last.map(String.init) ?? moved
            _ = try await store.retitle(moved, to: Paths.baseName(newName))
            let wasSelected = selectedNoteID == note.id
            if wasSelected { selectedNoteID = moved }
            await reloadNotes()
            lastError = nil
        } catch {
            lastError = "이름을 바꾸지 못했습니다: \(error.localizedDescription)"
        }
    }

    /// `.trash/` 로 옮긴다. 확인은 화면이 받았다.
    func finishTrash(_ note: NoteSummary) async {
        guard let store else { return }
        trashing = nil
        await save()
        do {
            _ = try await store.trash(note.relativePath)
            if selectedNoteID == note.id { selectedNoteID = nil }
            await reloadNotes()
            lastError = nil
        } catch {
            lastError = "지우지 못했습니다: \(error.localizedDescription)"
        }
    }

    // MARK: - 사진 넣기

    /// 사진첩에서 고른 사진을 노트 옆 `assets/` 에 JPEG 로 넣고, 커서 자리에 넣을
    /// `![](assets/….jpg)` 를 편집기에 건넨다 (설계서 §2-4).
    func insertPhoto(_ original: Data) async {
        guard let store, let note = selectedNote else { return }
        // 디코딩 · 크기 줄이기 · 인코딩은 주 액터 밖에서.
        // (`guard` 조건 안에는 트레일링 클로저를 못 쓴다 — 빌드 11 첫 컴파일이 잡았다.)
        let converted = await Task.detached(priority: .userInitiated) {
            ImageImport.jpeg(from: original)
        }.value
        guard let jpeg = converted else {
            lastError = "사진을 읽지 못했습니다"
            return
        }
        do {
            let relative = try await store.writeAsset(
                jpeg, stem: ImageImport.stem(), ext: "jpg",
                besideNoteIn: Paths.directory(of: note.relativePath))
            insertion = Insertion(text: ImageImport.markdownImage(path: relative))
            lastError = nil
        } catch {
            lastError = "사진을 넣지 못했습니다: \(error.localizedDescription)"
        }
    }

    // MARK: - 휴지통

    /// `.trash/` 안의 노트. 설정 → 휴지통이 보여 준다.
    @Published private(set) var trashed: [NoteSummary] = []

    func reloadTrash() async {
        guard let store else { return }
        trashed = await store.trashedNotes()
    }

    /// 원래 폴더로 되돌린다. 폴더 수와 목록을 함께 새로 읽는다 — 보고 있는 폴더가
    /// 아니면 목록에는 안 보이는 것이 맞다. 행이 폴더 이름을 보여 준다 (빌드 15 · 9번).
    func restore(_ note: NoteSummary) async {
        guard let store else { return }
        do {
            _ = try await store.restore(note.relativePath)
            await reloadTrash()
            await reloadFolders()
            await reloadNotes()
            lastError = nil
        } catch {
            lastError = "되돌리지 못했습니다: \(error.localizedDescription)"
        }
    }

    /// **되돌릴 수 없는 유일한 삭제.** 확인 문구가 다르면 아무것도 안 하고 그 사실을 띄운다.
    /// 대상을 인자로 받는 이유는 `finishRename` 과 같다 — 창이 닫히며 `purging` 이 먼저 비워진다.
    func finishPurge(_ target: Purge) async {
        guard let store else { return }
        purging = nil
        let typed = purgeText.trimmingCharacters(in: .whitespacesAndNewlines)
        purgeText = ""
        guard typed == Self.purgeConfirmation else {
            lastError = "확인 문구가 다릅니다. \(Self.purgeConfirmation) 라고 그대로 입력해야 지웁니다."
            return
        }
        do {
            switch target {
            case .all: try await store.emptyTrash()
            case .one(let note): try await store.deleteTrashed(note.relativePath)
            }
            await reloadTrash()
            lastError = nil
        } catch {
            lastError = "영구 삭제하지 못했습니다: \(error.localizedDescription)"
        }
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
        저장 안 된 글: \(isDirty ? "있음" : "없음")
        마지막 저장: \(lastSaved.map { $0.formatted(date: .omitted, time: .standard) } ?? "없음")
        마지막 오류: \(lastError ?? "없음")
        """
    }

    // MARK: - 편집 · 자동 저장

    /// 충돌 사본 이름의 시각. 파일 이름이라 `:` 를 못 쓴다 — `14.02`.
    private static let conflictClock: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH.mm"
        return formatter
    }()

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
        guard isDirty, let store, var path = draftPath else { return }
        let original = path
        var conflictPath: String?
        do {
            // **덮어쓰기 전에 파일이 그대로인지 본다** (설계서 §7.2 · A15). 도장(시각 · 크기)이
            // 다르면 내용을 읽어 견준다 — iCloud 가 시각만 건드린 경우를 걸러 헛돌지 않게.
            // 정말 다른 글이면 **덮어쓰지 않고** `이름 (충돌 …).md` 로 나란히 쓰고 그쪽을 연다.
            if let known = draftStamp, let now = await store.stamp(of: path), now != known,
               let onDisk = try? await store.readText(at: path), onDisk != noteText {
                let name = path.split(separator: "/").last.map(String.init) ?? path
                let conflict = try await store.createNote(
                    named: "\(Paths.baseName(name)) (충돌 \(Self.conflictClock.string(from: Date())))",
                    in: Paths.directory(of: path), text: draft)
                draftPath = conflict
                path = conflict
                conflictPath = conflict
                lastError = "다른 기기에서 고친 노트입니다. 내 글은 \(conflict.split(separator: "/").last.map(String.init) ?? conflict) 로 나란히 저장했습니다."
            } else {
                try await store.writeText(draft, to: path)
                lastError = nil
            }
            draftStamp = await store.stamp(of: path)
            noteText = draft
            isDirty = false
            saveFailed = false
            lastSaved = Date()
            if let conflictPath {
                // 더러움을 내린 **뒤에** 목록을 읽는다 — 안 그러면 다시 읽기가 저장을 또 부른다.
                if selectedNoteID == original { selectedNoteID = conflictPath }
                await reloadNotes()
            }
            // 목록은 최근 수정순인데 저장한다고 다시 읽지는 않는다 — 그러면 고친 노트가
            // 위로 안 올라온다 (48). 그 한 줄만 새 시각으로 바꿔 다시 정렬한다.
            if let index = notes.firstIndex(where: { $0.relativePath == path }) {
                let old = notes[index]
                notes[index] = NoteSummary(relativePath: old.relativePath, title: old.title,
                                           preview: old.preview, modifiedAt: Date(),
                                           size: (draft as NSString).length, isDownloaded: old.isDownloaded)
                notes.sort { $0.modifiedAt > $1.modifiedAt }
            }
            await renderReading(path: path, text: draft)
            await followTitle(of: draft, at: path)
        } catch {
            saveFailed = true
            lastError = "저장하지 못했습니다: \(error.localizedDescription)"
        }
    }

    /// **첫 줄 `# 제목` 을 파일명이 따라간다** (54, 사용자 요청). 저장이 성공한 뒤에만.
    /// 제목이 없거나 이미 같으면 아무것도 안 한다. 이름이 겹치면 `제목 2.md` 가 되고,
    /// 그 뒤로는 `제목 2` 자리를 지킨다 (`FolderStore.rename` 의 `keeping`).
    /// 편집기는 건드리지 않는다 — `editorSession` 이 그대로라 커서도 키보드도 그대로다.
    private func followTitle(of text: String, at path: String) async {
        guard let store, let heading = FrontMatterParser.firstHeading(of: text) else { return }
        let wanted = Paths.safeFileName(heading, fallback: "")
        let fileName = path.split(separator: "/").last.map(String.init) ?? path
        guard !wanted.isEmpty, wanted != Paths.baseName(fileName) else { return }
        do {
            let moved = try await store.rename(path, to: wanted)
            guard moved != path else { return }
            if draftPath == path {
                draftPath = moved
                draftStamp = await store.stamp(of: moved)
            }
            if let index = notes.firstIndex(where: { $0.relativePath == path }) {
                let old = notes[index]
                let newName = moved.split(separator: "/").last.map(String.init) ?? moved
                notes[index] = NoteSummary(relativePath: moved, title: Paths.baseName(newName),
                                           preview: old.preview, modifiedAt: old.modifiedAt,
                                           size: old.size, isDownloaded: old.isDownloaded)
            }
            if selectedNoteID == path { selectedNoteID = moved }
        } catch {
            lastError = "제목대로 이름을 바꾸지 못했습니다: \(error.localizedDescription)"
        }
    }

    func clearError() { lastError = nil }

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
        // **이미 들고 있는 그 파일이고 디스크도 그대로면 다시 읽지 않는다.** 제목을 따라
        // 이름만 바뀐 뒤(54) · 충돌 사본으로 옮겨 간 뒤 · 같은 노트를 다시 고른 뒤가 여기다.
        // 다시 읽으면 편집기가 글을 갈아 끼우며 커서를 잃는다. 디스크가 바뀌었으면
        // (다른 기기) 읽는다 — 당겨서 새로 고침이 그 길이다.
        if note.relativePath == draftPath, let stamp = draftStamp,
           await store.stamp(of: note.relativePath) == stamp {
            return
        }
        do {
            let text = try await store.readText(at: note.relativePath)
            noteText = text
            draft = text
            draftPath = note.relativePath
            draftStamp = await store.stamp(of: note.relativePath)
            isDirty = false
            editorSession = UUID()
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
        draftStamp = nil
        editorSession = UUID()
        isDirty = false
        pageHTML = ""
        attachmentCount = 0
        missingAttachments = []
    }
}
