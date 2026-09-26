import Foundation
import Core

/// 화면이 보는 상태. 파일은 `FolderStore`(actor) 가 만지고, 여기로는
/// **`Sendable` 값만** 건너온다 (설계서 §8).
@MainActor
final class LibraryModel: ObservableObject {

    @Published private(set) var folders: [FolderSummary] = []
    /// **최상위 폴더에 바로 든 노트 수** (153).
    ///
    /// 예전에는 폴더 화면의 맨 윗줄이 `notes.count` 를 썼다. 그것은 **지금 고른 폴더**의
    /// 노트라서, 하위 폴더를 열었다 뒤로 나오면 그 폴더의 개수가 맨 윗줄에 떴다
    /// (사용자 · 2026-09-19 — *느린 여백 폴더에 노트 개수가 안 맞을 때가 있어*).
    /// 이제 아래 폴더들과 **같은 셈법**으로 따로 센다.
    @Published private(set) var rootNoteCount = 0
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
    /// 이 노트를 **iCloud 에서 받는 중인가.** 화면이 가만히 있으면 이상하므로 내용 자리에
    /// 도는 표시를 띄운다 (86 · 사용자). 다 오면 지켜보기가 다시 열어 준다.
    @Published private(set) var noteIsDownloading = false
    /// **앱이 받기를 시킨 노트들** (156).
    ///
    /// 목록의 딱지가 `받는 중` 인지 `안 받음` 인지를 가른다. 아이클라우드의 상태만으로는
    /// **안 받았다**는 것밖에 모른다 — *받고 있다* 는 뜻이 아니다. 목록을 그리면서
    /// 내려받기를 시키지는 않으므로, 아무도 받고 있지 않은 파일에 *받는 중* 이라고
    /// 적혀 있었다 (사용자 · 2026-09-21).
    ///
    /// 다 받아지면 `reloadNotes()` 가 여기서 뺀다.
    @Published private(set) var downloading: Set<String> = []

    /// 이 노트를 앱이 받으라고 시켰나 — 목록의 딱지가 이것을 본다.
    func isDownloading(_ relativePath: String) -> Bool { downloading.contains(relativePath) }
    /// 읽기 모드에 넘길 완전한 HTML 문서 (ADR-0004).
    @Published private(set) var pageHTML = ""
    @Published private(set) var attachmentCount = 0
    /// 본문이 참조하는데 폴더에 없는 것 — 뷰어가 회색 상자로 보여 주고,
    /// 공유 전에도 알린다 (설계서 §7.6-4).
    @Published private(set) var missingAttachments: [String] = []
    @Published private(set) var lastError: String?

    /// 최상위는 빈 문자열.
    @Published var selectedFolder = ""
    @Published var selectedNoteID: String? {
        didSet {
            // 목록에서 다른 노트를 고르면 링크 자취를 접는다 (T7). 링크로 가는 길은
            // `openLinked` 가 **먼저** `linkedNote` 를 세우므로 여기서 안 접힌다.
            guard selectedNoteID != linkedNote?.relativePath else { return }
            linkedNote = nil
            linkTrail = []
        }
    }

    /// **고정된 노트** (T10). 목록 맨 위에 따로 선다. 폴더 안 숨김 파일에 적어 두므로
    /// iCloud 로 따라가고 본문은 한 글자도 안 건드린다.
    @Published private(set) var pinned: [String] = []

    /// 고정된 것 · 아닌 것으로 가른 목록. 화면은 이 둘만 그린다.
    var pinnedNotes: [NoteSummary] {
        pinned.compactMap { path in notes.first { $0.relativePath == path } }
    }
    var looseNotes: [NoteSummary] {
        let set = Set(pinned)
        return notes.filter { !set.contains($0.relativePath) }
    }

    // MARK: - 노트 수 (169)
    //
    // **새로 세지 않는다.** 폴더 화면의 숫자(`rootNoteCount` · `folders[].noteCount`)가
    // 이미 있고, 그것은 목록을 읽을 때마다 `syncCount` 가 맞춘다 (153). 여기서 따로 세면
    // 세는 길이 둘이 되어 언젠가 갈린다 — 153 이 바로 그것이었다 (CLAUDE.md §1).

    /// 폴더 하나의 노트 수 — 폴더 화면 그 줄의 숫자와 **같은 값**.
    func noteCount(of folder: String) -> Int {
        folder.isEmpty ? rootNoteCount
            : (folders.first { $0.relativePath == folder }?.noteCount ?? 0)
    }

    /// 전체 노트 수 — 폴더 화면에 보이는 숫자들의 **합**이다. 합과 다르면 사람이 더해 보고
    /// 어긋난 것을 찾는다. 앱이 보여 주는 폴더는 최상위와 그 바로 아래 한 단계뿐이다 (52).
    var totalNoteCount: Int {
        folders.reduce(rootNoteCount) { $0 + $1.noteCount }
    }

    /// **목록에 없는데 상세 칸에 떠 있는 노트** (T7). 링크를 따라온 것 — `assets/` 안의
    /// `.md` 처럼 폴더 목록에 안 보이는 자리에 있을 수 있다.
    @Published private(set) var linkedNote: NoteSummary?

    /// 링크를 따라오기 **전에 어디에 있었나.** 뒤로 갈 때 폴더 · 노트 · 모드를 되살린다.
    struct LinkStep: Equatable, Sendable {
        let folder: String
        let notePath: String?
        let linked: Bool
        let wasReading: Bool
    }
    @Published private(set) var linkTrail: [LinkStep] = []
    /// 커서가 **제목 줄**에 있나 (89). 그 줄에 있는 동안에는 파일명을 바꾸지 않는다 —
    /// 치는 중간마다 바꾸면 `제` · `제주` · `제주 일` 로 파일이 계속 옮겨지고,
    /// iCloud 가 그 하나하나를 퍼뜨려 충돌을 부른다. **떠날 때 한 번** 바꾼다.
    @Published var cursorOnTitleLine = false {
        didSet {
            guard oldValue, !cursorOnTitleLine else { return }
            Task { [weak self] in await self?.save(settlingTitle: true) }
        }
    }

    /// **편집기에 커서가 있나** (98). 아이폰에는 키보드를 내릴 길이 없어 `키보드 내리기`
    /// 단추를 띄운다 — 그 단추가 보일 때를 이것으로 정한다.
    @Published var editorHasFocus = false

    /// 공유할 때 **링크된 노트도 한 단계 넣을까** (설계서 §7.6-5). 켜짐이 기본.
    @Published var sharesLinkedNotes: Bool = UserDefaults.standard.object(forKey: "share.linked") as? Bool ?? true {
        didSet { UserDefaults.standard.set(sharesLinkedNotes, forKey: "share.linked") }
    }
    /// 없는 첨부가 있어 **물어보는 중**인 공유. 확인하면 그대로 보낸다.
    @Published var sharePrompt: SharePrompt?

    struct SharePrompt: Identifiable {
        let id = UUID()
        let package: SharePackage
    }

    /// 공유가 끝나면 지울 임시 폴더.
    private var shareDirectory: URL?

    /// 열 때 첫 줄 제목을 파일명에 맞출까 (62). **켜짐이 기본.** 다른 앱과 같이 쓰는 폴더라면
    /// 끈다 — 여는 것만으로 파일이 고쳐지기 때문이다. `UserDefaults` 에 둔다.
    /// **첫 줄을 파일명으로 따라가게 할까** (T6). 켜짐이 기본.
    /// 예전 이름은 `alignsTitles` 였다 — 그때는 파일명이 본문을 이기는 반대 방향까지
    /// 함께 켰다. 이제 방향은 하나뿐이라 이름도 그렇게 바꿨다.
    @Published var syncsFileName: Bool = UserDefaults.standard.object(forKey: "title.align") as? Bool ?? true {
        didSet { UserDefaults.standard.set(syncsFileName, forKey: "title.align") }
    }
    /// **편집 도구 띠가 편집기에 보내는 한 번짜리 부탁** (127 · T13 1차).
    ///
    /// 값을 고치는 길은 **편집기 하나뿐이다** (CLAUDE.md §1 — 값의 출입구는 하나다).
    /// 그래서 띠는 본문을 건드리지 않고 **무엇을 해 달라**만 남긴다. 사진 넣기(`insertion`)와
    /// 같은 꼴이다 — 편집기가 받아 `UITextView` 에서 한 번의 바꾸기로 끝낸다(되돌리기 한 번).
    struct FormatRequest: Identifiable, Equatable {
        let id = UUID()
        let kind: Kind

        enum Kind: Equatable {
            case wrap(Formatting.Wrap)
            case quote
            /// 코드 단추 (166) — 한 줄이면 역따옴표, 여러 줄이면 울타리. `Formatting.toggleCode`.
            case code
            case table
            /// 들여쓰기 · 내어쓰기는 탭 · 시프트 탭과 **같은 길**을 쓴다 (112).
            case shift(deeper: Bool)
            /// 고른 노트를 링크로 넣는다 (147). 방아쇠 자리는 편집기가 **다시 찾는다**.
            ///
            /// 폴더를 함께 싣는다 — 편집기는 노트가 어디 있는지 모르고, 링크는 **그 자리에서
            /// 보는 상대 경로**라야 한다. 뷰에 값을 하나 더 다는 것보다 이쪽이 안전하다
            /// (값을 다는 차례가 바뀌면 컴파일이 깨진다 · 빌드 40).
            case link(title: String, path: String, noteFolder: String)
        }
    }

    @Published var formatRequest: FormatRequest?

    // MARK: - 타이핑으로 노트 연결하기 (147)

    /// 지금 커서 앞에 `>>` · `[[` 가 있나. `nil` 이면 목록을 닫는다.
    @Published var linkQuery: NoteLinking.Query?
    /// 보여 줄 후보 (제목만 본다 · 최대 여덟).
    @Published var linkCandidates: [SearchHit] = []
    private var linkTask: Task<Void, Never>?

    /// 편집기가 방아쇠를 알려 왔다. 찾는 말이 바뀌었을 때만 색인을 두드린다.
    func linkQueryChanged(_ query: NoteLinking.Query?) {
        guard linkQuery?.text != query?.text || (query == nil) != (linkQuery == nil) else {
            linkQuery = query
            return
        }
        linkQuery = query
        linkTask?.cancel()
        guard let query, !query.text.trimmingCharacters(in: .whitespaces).isEmpty else {
            linkCandidates = []
            return
        }
        linkTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(120))
            guard !Task.isCancelled, let self, let index = self.index else { return }
            let hits = await index.titles(matching: query.text,
                                          excluding: self.selectedNote?.relativePath)
            guard !Task.isCancelled, self.linkQuery?.text == query.text else { return }
            self.linkCandidates = hits
        }
    }

    /// 고른 노트를 넣는다. 목록은 편집기가 실제로 넣은 뒤 닫는다.
    func pickLink(_ hit: SearchHit) {
        format(.link(title: hit.title, path: hit.relativePath, noteFolder: noteFolderForLink))
        linkCandidates = []
    }

    // MARK: - 이미 있는 파일 연결하기 (145)

    /// 금고 안의 파일들 — 시트를 열 때 한 번 읽는다.
    @Published var linkableFiles: [LinkableFile] = []
    @Published var isLoadingLinkableFiles = false

    /// 시트를 열고 목록을 읽는다.
    func startLinkingExistingFile() {
        sheet = .linkFile
        linkableFiles = []
        isLoadingLinkableFiles = true
        Task { [weak self] in
            guard let self, let store = self.store else { return }
            let own = self.selectedNote?.relativePath
            let files = await store.linkableFiles().filter { $0.relativePath != own }
            self.linkableFiles = files
            self.isLoadingLinkableFiles = false
        }
    }

    /// 고른 파일을 **지금 노트 기준 상대 경로**로 넣는다. 파일은 제자리에 그대로 둔다.
    func linkExistingFile(_ file: LinkableFile) {
        sheet = nil
        // 노트는 제목을, 첨부는 파일 이름을 보여 준다 — `[9월 회의록](…)` · `[표.pdf](…)`.
        let label = Paths.isMarkdownFile(file.relativePath)
            ? Paths.baseName(file.name) : file.name
        format(.link(title: label, path: file.relativePath, noteFolder: noteFolderForLink))
    }

    // MARK: - 안 열리는 링크 찾기 (146)

    /// 지금 노트에서 안 열리는 링크들. 시트를 열 때 센다.
    @Published var brokenLinks: [BrokenLink] = []

    /// **찾아 주기만 한다 — 고치지 않는다.** 앱이 본문을 고치는 자리는 둘뿐이다
    /// (노트를 옮길 때 · 붙여넣을 때). 여기서 몰래 고치면 셋째 자리가 생긴다.
    func showBrokenLinks() {
        let path = selectedNote?.relativePath ?? ""
        brokenLinks = BrokenLinks.find(in: noteText, notePath: path, files: vaultPaths)
        sheet = .brokenLinks
    }

    // MARK: - 붙여넣은 링크를 이 노트 기준으로 (144)

    /// 금고 안 파일들의 경로 — 붙여넣을 때 쓴다. 노트를 열 때 뒤에서 읽어 둔다.
    ///
    /// **비어 있으면 아무것도 안 고친다.** 아직 못 읽었을 때 안전한 쪽이다.
    private(set) var vaultPaths: [String] = []
    private var vaultPathsReadAt: Date?

    /// 노트를 열 때 한 번 (너무 자주는 안 읽는다).
    func refreshVaultPathsIfNeeded() {
        if let at = vaultPathsReadAt, Date().timeIntervalSince(at) < 60 { return }
        vaultPathsReadAt = Date()
        Task { [weak self] in
            guard let self, let store = self.store else { return }
            let files = await store.linkableFiles()
            self.vaultPaths = files.map(\.relativePath)
        }
    }

    /// **붙여넣을 글의 링크를 이 노트 기준으로** (144). 고칠 것이 없으면 `nil`.
    ///
    /// 앱이 본문을 고치는 자리이므로 **고쳤다고 알리고**, 되돌리기 한 번으로 무를 수 있다
    /// (편집기가 한 번의 바꾸기로 넣는다).
    /// **붙여넣을 것을 이 자리에 맞게 바꾼다** (144 · 157 · 158 · 159).
    ///
    /// 순서가 뜻을 정한다.
    ///
    /// 1. **표** (159) — HTML 에 표가 있으면 그것이 붙을 것이다. 평문 갈래에는 칸 구분이
    ///    뭉개진 글자만 오므로, 표가 있으면 평문을 볼 까닭이 없다.
    /// 2. **주소** (157) — 붙일 것이 주소 하나면 링크로 만든다. 글이 섞여 있으면 아니다 —
    ///    글 속의 주소까지 건드리면 **무엇을 할지 모르는 자리**가 된다.
    /// 3. **번호 겹침** (158) 과 **링크 고치기** (144) — 둘 다 평문에 건다. 서로 다른
    ///    자리를 만지므로 겹치지 않는다.
    ///
    /// **바꿨으면 알린다.** 사람이 모르게 본문이 달라지지 않는다. 되돌리기는 한 번이다.
    func repairPastedLinks(_ pasted: MarkdownTextView.PastedItem) -> String? {
        // 1. 표
        if let html = pasted.html, let table = HTMLTable.markdown(from: html) {
            report("표를 마크다운 표로 바꿨습니다. 되돌리기로 무를 수 있습니다.")
            return table
        }
        // 2. 주소 하나
        let address = pasted.url ?? pasted.plain
        if Pasting.isWebAddress(pasted.plain.trimmingCharacters(in: .whitespacesAndNewlines))
            || (pasted.url != nil && pasted.plain.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty),
           let link = Pasting.webLink(url: address, name: pasted.urlName,
                                      selection: pasted.selection) {
            report("주소를 링크로 만들었습니다. 되돌리기로 무를 수 있습니다.")
            return link
        }
        // 3. 평문 — 번호 겹침과 링크 고치기
        var text = pasted.plain
        var notes: [String] = []
        if let fixed = Pasting.numbering(pasted: text, onLine: pasted.lineBefore) {
            text = fixed.text
            notes.append("겹친 번호를 지웠습니다")
        }
        let repair = MarkdownLinks.repaired(pasted: text, noteFolder: noteFolderForLink,
                                            files: vaultPaths)
        if repair.fixed > 0 {
            text = repair.text
            notes.append("링크 \(repair.fixed)개를 이 노트에서 열리도록 고쳤습니다")
        }
        guard !notes.isEmpty, text != pasted.plain else { return nil }
        report(notes.joined(separator: ". ") + ". 되돌리기로 무를 수 있습니다.")
        return text
    }

    /// 지금 노트가 든 폴더 — 링크는 여기서 보는 상대 경로다.
    private var noteFolderForLink: String {
        Paths.directory(of: selectedNote?.relativePath ?? "")
    }

    /// **없는 제목이면 새 노트를 만들어 연결한다** (147, 사용자 — 애플 메모처럼).
    /// 지금 노트와 **같은 폴더**에 만든다.
    func createNoteAndLink(named raw: String) {
        let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, let store else { return }
        let folder = selectedFolder
        Task { [weak self] in
            do {
                // **첫 줄이 곧 제목이다** (107 · T6) — 만들 때 그 줄을 넣어 둔다.
                let path = try await store.createNote(named: name, in: folder,
                                                      text: "# " + name + "\n\n")
                guard let self else { return }
                self.format(.link(title: name, path: path, noteFolder: self.noteFolderForLink))
                self.linkCandidates = []
                await self.reloadNotes()
            } catch {
                self?.report("새 노트를 만들지 못했습니다. " + error.localizedDescription)
            }
        }
    }

    /// **커서 자리에 지금 걸려 있는 표시** (128, 사용자 — *선택이 되었는지 안 보인다*).
    /// 도구 띠가 이것을 보고 눌린 모습으로 그린다.
    @Published var activeFormats = Formatting.Active()

    func format(_ kind: FormatRequest.Kind) {
        formatRequest = FormatRequest(kind: kind)
    }

    /// **시험 도구를 보여 줄까** (122 · T11). **꺼짐이 기본.**
    ///
    /// 진단 화면에는 두 종류가 섞여 있었다 — 무엇이 어긋났나(쓰는 사람)와 시험 도구
    /// (만드는 사람). 뒤엣것은 **누르면 자료를 만든다** — 노트 300개는 iCloud 에 20MB 를
    /// 올린다. 그래서 기본으로 감추고 설정에서 켜야 보이게 한다.
    @Published var showsTestTools: Bool = UserDefaults.standard.object(forKey: "tools.visible") as? Bool ?? false {
        didSet { UserDefaults.standard.set(showsTestTools, forKey: "tools.visible") }
    }
    /// **노트를 열 때 읽기 모드로 시작할까** (124, 사용자 — *평소에는 읽기 모드로 보고
    /// 편집은 회의 뒤나 자료를 쓸 때만 쓴다*). **꺼짐이 기본** — 지금까지의 동작 그대로다.
    @Published var opensInReadingMode: Bool = UserDefaults.standard.object(forKey: "mode.reading") as? Bool ?? false {
        didSet { UserDefaults.standard.set(opensInReadingMode, forKey: "mode.reading") }
    }
    /// 이번에 여는 노트의 모드는 **부른 쪽이 이미 정했다** (124). 새 노트는 쓰려고 만든
    /// 것이고 `왔던 노트` 는 떠날 때의 모드를 되살린다 — 위 스위치가 그것을 덮으면 안 된다.
    /// 한 번 쓰이고 저절로 풀린다.
    private var modeAlreadyChosen = false

    /// 위 토글. **쓰기가 기본**이다 (설계서 §14-6).
    @Published var isReading = false
    /// 이름을 바꾸는 중인 노트 · 새 이름. 화면의 알림창이 이것을 본다.
    @Published var renaming: NoteSummary?
    /// **어느 노트를 어느 폴더로 옮길까** (T1). 링크를 고칠지 물어보는 창이 이것으로 뜬다.
    struct Move: Identifiable, Equatable {
        let note: NoteSummary
        let folder: String
        let links: Int
        var id: String { note.relativePath + "→" + folder }
    }
    /// 폴더를 고르는 창 (아이폰 — 줄을 밀어 `이동`).
    @Published var movingNote: NoteSummary?
    /// 고칠 링크가 있어 물어보는 창.
    @Published var moveConfirm: Move?
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
        /// 첨부 미리보기 (QuickLook). 폴더 안 파일의 절대 URL.
        case preview(URL)
        /// 공유 시트 — 임시 폴더에 만든 `.md` 하나 또는 `.zip` 하나 (설계서 §7.6).
        case share(URL)
        /// **이미 있는 파일 고르기** (145). 고르면 링크만 넣는다 — 사본은 안 만든다.
        case linkFile
        /// **안 열리는 링크 보기** (146). 찾아 주기만 한다 — 고치지 않는다.
        case brokenLinks

        var id: String {
            switch self {
            case .settings: return "settings"
            case .diagnostics: return "diagnostics"
            case .incoming(let file): return "incoming-\(file.id)"
            case .preview(let url): return "preview-\(url.path)"
            case .share(let url): return "share-\(url.path)"
            case .linkFile: return "linkFile"
            case .brokenLinks: return "brokenLinks"
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
    /// 검색 색인 — 폴더마다 하나. 캐시다 (ADR-0003).
    private var index: SearchIndex?

    /// **지금 글이 어느 파일의 것인가.** `selectedNote` 를 보지 않는 이유는,
    /// 사용자가 노트를 바꾸면 그 값이 먼저 바뀌어 **이전 글이 새 파일에 덮일** 수
    /// 있기 때문이다. 저장은 언제나 이 경로로 간다.
    private var draftPath: String?
    /// 글을 읽었을 때 · 마지막으로 썼을 때의 파일 도장. 저장 직전에 견준다 (A15).
    private var draftStamp: FileStamp?
    private var autosave: Task<Void, Never>?
    /// 앞에 선 저장. 새 저장은 이것이 끝난 뒤에 쓴다 (빌드 29 · 4번).
    private var saveChain: Task<Void, Never>?
    /// 지금 쓰고 있나. 쓰는 도중에 다시 불린 저장은 제 차례를 기다리지 않는다.
    private var isWriting = false
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
        // 링크를 따라온 노트가 먼저다 — 목록(`notes`)에는 없을 수 있다 (T7).
        if let linked = linkedNote, linked.id == selectedNoteID { return linked }
        return notes.first { $0.id == selectedNoteID }
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
        let choice = await FolderSource.current(launch: launch)
        if choice.staleBookmark {
            // **조용히 넘어가지 않는다.** 폴더가 옮겨졌거나 지워졌거나 권한이 끊긴 것이다.
            log("고른 폴더를 더는 열 수 없어 \(choice.kind.label) 폴더로 돌아옴")
            lastError = "고른 폴더를 더는 열 수 없어 \(choice.kind.label) 폴더로 돌아왔습니다. 설정 → 폴더에서 다시 고를 수 있습니다."
        }
        await use(choice)
    }

    // MARK: - (b) 폴더 고르기 (ADR-0002)

    /// 문서 선택 창에서 고른 폴더로 **옮겨 탄다.** 지금 글을 먼저 저장하고, 북마크를 기억한 뒤
    /// 그 폴더를 연다. 옵시디언 볼트처럼 이미 있는 폴더가 여기로 들어온다.
    func chooseFolder(_ picked: URL) async {
        await save()
        do {
            let url = try FolderSource.adopt(picked)
            log("폴더를 고름: \(url.lastPathComponent)")
            await use(FolderChoice(url: url, kind: .userChosen, iCloudAvailable: iCloudAvailable, attempts: 0))
            lastError = nil
            sheet = nil
        } catch {
            lastError = "그 폴더를 열지 못했습니다: \(error.localizedDescription)"
        }
    }

    /// 고른 폴더를 잊고 (a) iCloud 폴더로 **돌아간다.** 고른 폴더의 파일은 그대로 남는다.
    func returnToDefaultFolder() async {
        await save()
        FolderSource.forget()
        log("고른 폴더를 잊고 기본 폴더로 돌아감")
        await use(await FolderSource.current(launch: launch))
        lastError = nil
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
        await index?.close()
        store = FolderStore(root: choice.url, kind: choice.kind)
        chosenFolderPath = choice.kind == .userChosen ? FolderSource.livePath(of: choice.url) : ""
        lastChosenFolderCheck = Date()
        index = SearchIndex(for: choice.url)
        searchText = ""
        searchResults = []
        indexStatus = IndexStatus()
        kind = choice.kind
        iCloudAvailable = choice.iCloudAvailable
        rootPath = choice.url.path
        selectedFolder = ""
        selectedNoteID = nil
        await reloadPins()
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
            modeAlreadyChosen = true      // 사진이 다 보이는지 보는 시험이다 (124)
            selectedNoteID = "첨부 시험.md"
            isReading = true
            sheet = nil
            lastError = nil
        } catch {
            lastError = "시험 파일을 만들지 못했습니다: \(error.localizedDescription)"
        }
    }

    /// **큰 노트를 만든다** — 300줄 · 20KB (안정화 기준 S11).
    ///
    /// S11 은 큰 파일에서 커서를 옮길 때 지연 · 튐이 없는가를 묻는다. 그 자료를 손으로
    /// 만들려면 다른 앱에서 300줄을 붙여 넣어야 하는데, 아이폰에서는 그것부터 일이다.
    /// 앱이 만든다 — 첨부 시험(A3 · A13)과 같은 뜻이다.
    ///
    /// **한 줄이 다 같은 줄이면 안 된다.** 제목 · 목록 · 인용 · 코드 · 강조가 섞여야
    /// 문단마다 다시 칠하는 길(`MarkdownStyler.restyle`)이 실제로 밟힌다.
    func makeBigNote() async {
        guard let store else { return }
        // 보고 있는 폴더에 만든다 — 최상위에 만들면 하위 폴더를 보던 사람에게는 안 보인다.
        // 이름이 겹치면 `큰 노트 시험 2` 로 비켜 간다 (`createNote`).
        let text = Self.bigNote()
        do {
            let path = try await store.createNote(named: "큰 노트 시험", in: selectedFolder, text: text)
            await reloadNotes()
            modeAlreadyChosen = true      // 커서를 훑어 보는 시험이다 (124)
            selectedNoteID = path
            isReading = false
            sheet = nil
            lastError = nil
            log("큰 노트 시험 만듦 — \(text.components(separatedBy: "\n").count)줄 · "
                + "\(Self.readableBytes(text.utf8.count)) · \(path)")
        } catch {
            lastError = "큰 노트를 만들지 못했습니다: \(error.localizedDescription)"
        }
    }

    /// 300줄 · 20KB 안팎. 곧은 따옴표를 문구 안에 쓰지 않는다 (CLAUDE.md §5).
    static func bigNote() -> String {
        var lines = ["# 큰 노트 시험", "",
                     "**300줄 · 20KB 안팎입니다.** 커서를 위아래로 훑어 지연이나 튐이 있는지 봅니다 (S11).",
                     "확인이 끝나면 지우셔도 됩니다.", ""]
        // 한 덩이가 12줄. 서른 덩이면 395줄 · 20.2KB 다 (파이썬으로 미리 재 뒀다).
        for block in 1...30 {
            lines.append("## \(block)번째 마디")
            lines.append("")
            lines.append("이 문단은 길이를 채우려고 있습니다. **굵게** 와 *기울임* 과 `코드` 가 한 줄에 섞여 있어, "
                         + "커서가 이 줄에 오고 갈 때마다 마커를 숨기고 드러내는 길이 실제로 밟힙니다.")
            lines.append("")
            lines.append("긴 글에서 커서를 옮길 때 앱이 다시 칠하는 것은 **문단 셋뿐**입니다 — 고친 문단 · "
                         + "커서가 떠난 문단 · 커서가 온 문단. 이 노트가 그것을 실제로 재는 자리입니다.")
            lines.append("")
            lines.append("- 첫째 항목 \(block)")
            lines.append("  - 겹친 항목 \(block)")
            lines.append("1. 번호 항목 \(block)")
            lines.append("> 인용 줄 \(block) — 세로선이 붙는 자리입니다.")
            lines.append("")
            lines.append("[제 자신으로 가는 링크](<큰 노트 시험.md>) 와 ~취소선~ 도 한 줄에 둡니다.")
            lines.append("")
        }
        return lines.joined(separator: "\n") + "\n"
    }

    // MARK: - 규모 시험 (S1 · A5 · A5b · A5c)

    /// 규모 시험 자료가 들어가는 폴더. 한 곳에 모아 두면 지울 때도 한 번이다.
    static let scaleFolder = "규모 시험"
    /// 만들 노트 수 · 노트 하나의 목표 크기. 300개 · 20MB 가 가정 표의 값이다.
    static let scaleCount = 300

    /// 만드는 중인가 · 몇 개까지 갔나. 화면이 멈춘 것처럼 보이면 안 된다.
    @Published private(set) var scaleProgress: Int?

    /// **300개 · 20MB 를 만든다** (S1 · A5 · A5b · A5c).
    ///
    /// 이 넷은 자료가 없어 못 재던 칸이다. 손으로 300개를 만들 수는 없으니 앱이 만든다.
    /// 만드는 동안 **iCloud 가 20MB 를 올린다** — 그것까지가 이 시험의 값이다.
    /// 끝나면 `규모 시험 지우기` 한 번으로 휴지통에 간다.
    func makeScaleTest() async {
        guard let store else { return }
        guard scaleProgress == nil else { return }
        scaleProgress = 0
        let started = Date()
        var bytes = 0
        do {
            let folder = try await store.createSubfolder(named: Self.scaleFolder)
            for number in 1...Self.scaleCount {
                let text = Self.scaleNote(number)
                bytes += text.utf8.count
                _ = try await store.createNote(named: "시험 \(number)", in: folder, text: text)
                // 열 개마다 화면에 알린다 — 300번 다 알리면 그리는 데 더 든다.
                if number % 10 == 0 { scaleProgress = number }
            }
            let seconds = Date().timeIntervalSince(started)
            log("규모 시험 \(Self.scaleCount)개 만듦 — \(Self.readableBytes(bytes)) · "
                + "\(String(format: "%.1f", seconds))초")
            scaleProgress = nil
            selectedFolder = folder
            await reloadFolders()
            await reloadNotes()
            sheet = nil
            lastError = nil
        } catch {
            scaleProgress = nil
            lastError = "규모 시험 자료를 만들지 못했습니다: \(error.localizedDescription)"
        }
    }

    /// 규모 시험 폴더를 **휴지통으로.** 영구 삭제는 설정 → 휴지통에서 (CLAUDE.md §1).
    func removeScaleTest() async {
        guard let store else { return }
        do {
            let moved = try await store.trashFolder(Self.scaleFolder)
            log("규모 시험 폴더를 휴지통으로 — 노트 \(moved)개")
            if selectedFolder == Self.scaleFolder { selectedFolder = "" }
            await reloadFolders()
            await reloadNotes()
            await reloadTrash()
            lastError = "규모 시험 폴더를 휴지통으로 옮겼습니다. 설정 → 휴지통에서 영구히 지울 수 있습니다."
        } catch {
            lastError = "규모 시험 폴더를 지우지 못했습니다: \(error.localizedDescription)"
        }
    }

    /// 노트 하나 — 평균 **68KB** 라야 300개가 20MB 가 된다. 번호에 따라 크기를 달리해
    /// 작은 노트와 큰 노트가 섞이게 한다 (실제 폴더가 그렇다).
    ///
    /// **검색이 실제로 걸릴 말을 심는다** — `회의`(두 글자, LIKE 폴백) · `노후자금`(세 글자,
    /// trigram) · `노후 자금`(구절). S6 가 재는 세 길이 그대로 여기 있다.
    static func scaleNote(_ number: Int) -> String {
        var lines = ["# 시험 \(number)", "",
                     "규모 시험용 노트입니다. **지워도 됩니다.**", ""]
        if number % 7 == 0 { lines.append("오늘 회의에서 정한 것을 적어 둡니다.") }
        if number % 11 == 0 { lines.append("노후자금 계획을 다시 봅니다.") }
        if number % 13 == 0 { lines.append("노후 자금 과 생활비를 갈라 적습니다.") }
        lines.append("")
        // 번호에 따라 두께를 달리한다 — 140 ~ 400 마디. 300개 합이 19.7MB · 평균 67KB 다
        // (파이썬으로 미리 재 뒀다). 작은 노트와 큰 노트가 섞여야 실제 폴더를 닮는다.
        let blocks = 140 + (number % 261)
        for block in 1...blocks {
            lines.append("## \(number)-\(block)")
            lines.append("")
            lines.append("이 문단은 크기를 채우려고 있습니다. **굵게** 와 *기울임* 과 `코드` 가 "
                         + "섞여 있어 색인과 그리기가 실제 노트와 비슷하게 돕니다. "
                         + "여백은 느리게 쓰는 사람을 위한 것입니다.")
            lines.append("")
            lines.append("- 항목 \(block)")
            lines.append("> 인용 \(block)")
            lines.append("")
        }
        return lines.joined(separator: "\n") + "\n"
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
            modeAlreadyChosen = true      // 쓰려고 만든 노트다 (124)
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
            pinned = await store.followPins(from: folder.relativePath, to: moved)
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
            pinned = await store.unpin(folder.relativePath)
            await reloadFolders()
            if wasViewing { selectedFolder = "" }
            lastError = nil
        } catch {
            lastError = "폴더를 지우지 못했습니다: \(error.localizedDescription)"
        }
    }

    // MARK: - 커서 줄의 사진 (ADR-0005 L3 후퇴판)

    /// **커서가 사진 줄에 있을 때 그 사진** (L3 후퇴판). 편집기 안에 그리는 대신
    /// 아래 띠에 작게 띄우고, 누르면 전체화면으로 본다. ADR-0005 에 적어 둔 물러설 길이다 —
    /// TextKit 2 프래그먼트(L3 본판)는 여기서 컴파일해 볼 수 없는 자리라 이쪽을 먼저 놓는다.
    @Published private(set) var cursorImage: CursorImage?

    struct CursorImage: Equatable, Identifiable {
        let path: String
        let image: Data
        var id: String { path }
    }

    private var imageLineTask: Task<Void, Never>?

    /// 편집기가 커서 줄의 그림 주소를 알려 준다. 폴더 안의 것만 띄운다 —
    /// 바깥 주소는 우리가 읽을 수 없고, 없는 파일은 읽기 모드가 이미 알린다.
    func cursorImageLineChanged(_ destination: String?) {
        imageLineTask?.cancel()
        guard let destination, let store, let note = draftPath else {
            cursorImage = nil
            return
        }
        guard case .relative(let path) = Paths.resolve(link: destination, fromNoteAt: note) else {
            cursorImage = nil
            return
        }
        if cursorImage?.path == path { return }
        imageLineTask = Task { [weak self] in
            let data = await store.data(forRelativePath: path)
            guard !Task.isCancelled, let self else { return }
            self.cursorImage = data.map { CursorImage(path: path, image: $0) }
        }
    }

    /// 고정하거나 푼다 (T10). 고정한 차례가 곧 위에서 아래 차례다.
    func togglePin(_ note: NoteSummary) async {
        guard let store else { return }
        let path = note.relativePath
        if pinned.contains(path) {
            pinned = await store.writePins(pinned.filter { $0 != path }, mergingDisk: false)
            log("고정 품: \(path)")
        } else {
            // 새로 고정한 것을 **맨 앞**에 — 방금 고정한 것이 먼저 보인다.
            pinned = await store.writePins([path] + pinned, mergingDisk: false)
            log("고정함: \(path)")
        }
    }

    /// 폴더를 열 때 · 다른 기기의 변경을 따라갈 때 다시 읽는다.
    func reloadPins() async {
        guard let store else { return }
        pinned = await store.readPins()
    }

    /// **노트를 폴더로 옮긴다** (T1, 사용자 요청 — 아이패드는 끌어다 놓기, 아이폰은 줄 밀기).
    ///
    /// 폴더 안을 가리키는 링크가 있으면 **먼저 물어본다.** 링크를 고치는 것은 앱이 본문에
    /// 손대는 일이라, 사용자가 그러라고 한 순간에만 한다 (107 에서 62 를 지운 까닭과 같다).
    func beginMove(_ note: NoteSummary, to folder: String) async {
        guard let store, Paths.directory(of: note.relativePath) != folder else { return }
        let links = await store.folderLinkCount(of: note.relativePath)
        if links == 0 {
            await finishMove(Move(note: note, folder: folder, links: 0), rebasesLinks: false)
        } else {
            moveConfirm = Move(note: note, folder: folder, links: links)
        }
    }

    /// 물어본 뒤 실제로 옮긴다. `rebasesLinks` 가 거짓이면 본문을 그대로 둔다 —
    /// 그러면 사진과 첨부가 안 보이게 되지만, 그것도 사용자의 선택이다.
    func finishMove(_ move: Move, rebasesLinks: Bool) async {
        guard let store else { return }
        moveConfirm = nil
        movingNote = nil
        await save()
        do {
            let moved = try await store.moveNote(move.note.relativePath, to: move.folder,
                                                 rebasesLinks: rebasesLinks)
            pinned = await store.followPins(from: move.note.relativePath, to: moved)
            log("옮김: \(move.note.relativePath) → \(moved)"
                + (rebasesLinks && move.links > 0 ? " (링크 \(move.links)개 고침)" : ""))
            if draftPath == move.note.relativePath { clearNote() }
            if selectedNoteID == move.note.relativePath { selectedNoteID = nil }
            await reloadFolders()
            await reloadNotes()
            scheduleIndexRefresh()
            lastError = nil
        } catch {
            lastError = "옮기지 못했습니다: \(error.localizedDescription)"
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
            pinned = await store.followPins(from: note.relativePath, to: moved)
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
            pinned = await store.unpin(note.relativePath)
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
        await insertPhotos([original])
    }

    /// 사진 여러 장을 **한 번에** — 각각 `assets/` 에 넣고 링크를 한 줄씩 모아 한 번의 넣기로 (77).
    /// 하나라도 실패하면 나머지는 넣고 실패한 수를 알린다.
    func insertPhotos(_ originals: [Data]) async {
        guard let store, let note = selectedNote, !originals.isEmpty else { return }
        let folder = Paths.directory(of: note.relativePath)
        var lines: [String] = []
        var failed = 0
        for original in originals {
            // 디코딩 · 크기 줄이기 · 인코딩은 주 액터 밖에서.
            // (`guard` 조건 안에는 트레일링 클로저를 못 쓴다 — 빌드 11 첫 컴파일이 잡았다.)
            let converted = await Task.detached(priority: .userInitiated) {
                ImageImport.jpeg(from: original)
            }.value
            guard let jpeg = converted else { failed += 1; continue }
            do {
                let relative = try await store.writeAsset(jpeg, stem: ImageImport.stem(), ext: "jpg",
                                                          besideNoteIn: folder)
                lines.append(ImageImport.markdownImage(path: relative))
            } catch {
                failed += 1
            }
        }
        if !lines.isEmpty { insertion = Insertion(text: lines.joined(separator: "\n")) }
        lastError = failed == 0 ? nil : "사진 \(failed)장을 넣지 못했습니다"
    }

    /// 문서 첨부 — 사진과 같은 길로 (78). 고른 파일을 `assets/` 에 **복사**하고 커서 자리에
    /// `[이름.pdf](<assets/이름-1.pdf>)` 를 넣는다. 원본은 건드리지 않는다. 여러 개면 한 줄씩.
    ///
    /// **`.md` 는 다르다** (111, 사용자 — 빌드 33 · 10번). 노트는 첨부가 아니라 폴더의
    /// 시민이다. `assets/` 에 복사하면 **원본과 딴 살림을 차린 사본**이 생기고, 그 사본을
    /// 고치게 된다. 그래서:
    /// - **폴더 안에 이미 있는 노트**면 복사하지 않고 **그 자리로 링크한다** (`../` 까지 붙여).
    /// - **밖에서 온 노트**면 `assets/` 가 아니라 **그 노트 옆**에 들여온다.
    func attachDocuments(_ urls: [URL]) async {
        guard let store, let note = selectedNote, !urls.isEmpty else { return }
        let folder = Paths.directory(of: note.relativePath)
        var lines: [String] = []
        var failed: [String] = []
        for url in urls {
            let name = Paths.normalized(url.lastPathComponent)
            // 파일 읽기는 주 액터 밖에서. 보안 범위는 그 안에서 연다.
            let loaded = await Task.detached(priority: .userInitiated) { () -> Data? in
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                try? FileManager.default.startDownloadingUbiquitousItem(at: url)
                var data: Data?
                var error: NSError?
                NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &error) { readURL in
                    data = try? Data(contentsOf: readURL)
                }
                return data
            }.value
            // **노트는 노트로** (111). 폴더 안의 것이면 그 자리로 링크하고, 밖의 것이면
            // 그 노트 옆에 들여온다. 어느 쪽이든 `assets/` 에는 안 들어간다.
            if Paths.isNoteFile(name) {
                do {
                    let inFolder = await store.relativePath(of: url)
                    let target: String
                    if let inFolder {
                        target = inFolder
                    } else {
                        guard let data = loaded else { failed.append(name); continue }
                        target = try await store.importNote(data, named: name, in: folder)
                    }
                    guard target != note.relativePath else { continue }   // 제 자신으로 가는 링크는 넣지 않는다
                    let link = Paths.relativeLink(from: folder, to: target)
                    lines.append(ImageImport.markdownLink(label: Paths.baseName(name), path: link))
                } catch {
                    failed.append(name)
                }
                continue
            }
            guard let data = loaded else { failed.append(name); continue }
            let ext = Paths.fileExtension(name).lowercased()
            let stem = Paths.safeFileName(Paths.baseName(name), fallback: "문서")
            do {
                let relative = try await store.writeAsset(data, stem: stem, ext: ext.isEmpty ? "bin" : ext,
                                                          besideNoteIn: folder)
                lines.append(ImageImport.markdownLink(label: name, path: relative))
            } catch {
                failed.append(name)
            }
        }
        if !lines.isEmpty {
            insertion = Insertion(text: lines.joined(separator: "\n"))
            await reloadNotes()   // 밖에서 들여온 노트가 목록에 서야 한다 (111)
            log("문서 첨부 \(lines.count)개: \(note.relativePath)")
        }
        lastError = failed.isEmpty ? nil : "첨부하지 못했습니다: \(failed.joined(separator: ", "))"
    }

    // MARK: - 공유 (설계서 §7.6)

    /// 노트 하나를 공유한다. 첨부가 없으면 `.md` 하나, 있으면 `.zip` 하나.
    /// **없는 첨부가 있으면 먼저 알린다** — 조용히 빠뜨리지 않는다.
    func share(_ note: NoteSummary) async {
        guard let store else { return }
        await save()
        do {
            let package = try await store.prepareShare(of: note.relativePath,
                                                       followLinkedNotes: sharesLinkedNotes)
            if package.missing.isEmpty {
                present(package)
            } else {
                sharePrompt = SharePrompt(package: package)
            }
        } catch ReadError.notDownloaded {
            lastError = "iCloud 에서 받는 중입니다. 다 받은 뒤에 공유할 수 있습니다."
        } catch {
            lastError = "공유할 파일을 만들지 못했습니다: \(error.localizedDescription)"
        }
    }

    /// 없는 첨부를 알린 뒤 그래도 보낸다.
    func shareAnyway(_ package: SharePackage) {
        sharePrompt = nil
        present(package)
    }

    /// 물어본 공유를 접는다 — 임시 폴더도 지운다.
    func cancelShare(_ package: SharePackage) {
        sharePrompt = nil
        FolderStore.cleanUpShare(package.directory)
        logShareScratch()
    }

    /// **치운 뒤에 무엇이 남았나** (97, 사용자 제안). 저장 공간이 쌓이는지는 눈으로 보기
    /// 어렵다 — 공유가 끝날 때마다 남은 임시 꾸러미 수와 크기를 최근 일에 적는다.
    /// 늘 `0개 · 0B` 이면 안 쌓이는 것이다.
    private func logShareScratch() {
        let left = FolderStore.shareScratch()
        log("공유 임시 폴더 치움 — 남은 것 \(left.count)개 · \(Self.readableBytes(left.bytes))")
    }

    /// 사람이 읽을 크기. `1.2MB` 처럼.
    static func readableBytes(_ bytes: Int) -> String {
        if bytes < 1024 { return "\(bytes)B" }
        if bytes < 1024 * 1024 { return String(format: "%.1fKB", Double(bytes) / 1024) }
        return String(format: "%.1fMB", Double(bytes) / (1024 * 1024))
    }

    private func present(_ package: SharePackage) {
        shareDirectory = package.directory
        log("공유 꾸러미 \(package.url.lastPathComponent) — \(Self.readableBytes(package.bytes))\(package.isZip ? " · zip" : "")")
        sheet = .share(package.url)
    }

    /// 공유 시트가 닫혔다 — 임시 폴더를 지운다.
    func shareSheetClosed() {
        if let directory = shareDirectory { FolderStore.cleanUpShare(directory) }
        shareDirectory = nil
        logShareScratch()
    }

    /// 읽기 모드에서 첨부를 눌렀다 — QuickLook 으로 연다 (78). 파일이 없으면 말한다.
    func previewAttachment(_ relativePath: String) async {
        guard let store else { return }
        guard await store.existingPaths(among: [relativePath]).contains(relativePath) else {
            lastError = "첨부가 폴더에 없습니다: \(relativePath)"
            return
        }
        sheet = .preview(store.root.appendingPathComponent(relativePath))
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
            let restored = try await store.restore(note.relativePath)
            log("되돌림: \(restored)")
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

    // MARK: - 검색 (ADR-0003 · 설계서 §7.5)

    /// 검색 칸의 글. 150ms 디바운스로 `searchResults` 가 따라온다.
    @Published var searchText = "" {
        didSet { scheduleSearch() }
    }
    @Published private(set) var searchResults: [SearchHit] = []
    @Published private(set) var isSearching = false
    @Published private(set) var indexStatus = IndexStatus()
    /// **색인이 도는 중인가** (T8). 표시가 없으면 사용자가 또 누르고, 누를 때마다
    /// 앞 작업을 접고 처음부터 다시 만든다. 도는 동안 단추를 막는다.
    @Published private(set) var isIndexing = false
    /// 마지막으로 목록을 읽는 데 걸린 시간 (S1) · 검색에 걸린 시간 (A5c). 진단에 보인다.
    @Published private(set) var listSeconds: Double = 0
    @Published private(set) var searchSeconds: Double = 0
    /// 목록의 첫 줄 미리보기 — **색인에서만** (설계서 §7.5). 색인 전이면 빈칸.
    private var previews: [String: String] = [:]
    private var searchTask: Task<Void, Never>?
    private var indexTask: Task<Void, Never>?

    /// 목록이 같은가 — 경로 · 시각 · 크기로 본다. 같은 값이면 화면을 안 건드린다.
    /// **줄 자체를 견딘다** (156). 값을 골라 이어 붙인 지문을 쓰지 않는다 —
    /// 고르는 순간 빠뜨릴 수 있고, 실제로 `isDownloaded` 를 빠뜨려
    /// **`받는 중` 딱지가 안 사라졌다.** 규칙은 `NoteSummary.forComparing` 에 있다.
    private static func fingerprint(_ notes: [NoteSummary]) -> [NoteSummary] {
        notes.map(\.forComparing).sorted { $0.relativePath < $1.relativePath }
    }

    private static func withPreviews(_ notes: [NoteSummary], from previews: [String: String]) -> [NoteSummary] {
        notes.map { note in
            let line = previews[note.relativePath] ?? ""
            guard line != note.preview else { return note }
            return NoteSummary(relativePath: note.relativePath, title: note.title, preview: line,
                               modifiedAt: note.modifiedAt, size: note.size, isDownloaded: note.isDownloaded)
        }
    }

    private func scheduleSearch() {
        searchTask?.cancel()
        let text = searchText.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { searchResults = []; isSearching = false; return }
        isSearching = true
        searchTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled, let self, let index = self.index else { return }
            // **검색에 걸린 시간도 앱이 잰다** (A5c · S6 — 0.5초 안).
            let started = Date()
            let hits = await index.search(text)
            guard !Task.isCancelled else { return }
            self.searchSeconds = Date().timeIntervalSince(started)
            if self.searchSeconds > 0.2 || self.indexStatus.noteCount >= 100 {
                self.log("검색 \(text) — \(String(format: "%.2f", self.searchSeconds))초 · \(hits.count)건")
            }
            self.searchResults = hits
            self.isSearching = false
        }
    }

    /// 목록이 바뀔 때마다 **바뀐 파일만** 다시 색인한다. 겹치면 앞 것을 접는다.
    /// 첫 색인은 뒤에서 돈다 — 목록은 기다리지 않는다 (S1).
    private func scheduleIndexRefresh() {
        indexTask?.cancel()
        isIndexing = true
        indexTask = Task { [weak self] in
            guard let self else { return }
            // 접힌 것이면 끄지 않는다 — 뒤이어 선 작업이 그 깃발의 임자다.
            defer { if !Task.isCancelled { self.isIndexing = false } }
            guard let index = self.index, let store = self.store else { return }
            // 색인은 폴더 **전체**를 안다 — 하위 폴더까지. 목록은 보고 있는 폴더뿐이다.
            let all = await store.allNotes()
            guard !Task.isCancelled else { return }
            let changed = await index.refresh(all) { path in try await store.readText(at: path) }
            guard !Task.isCancelled else { return }
            self.indexStatus = await index.status
            if changed > 0 || self.previews.isEmpty {
                self.previews = await index.firstLines()
                self.notes = Self.withPreviews(self.notes, from: self.previews)
                if changed > 0 { self.log("색인 갱신: \(changed)개 (\(self.indexStatus.noteCount)개 · \(String(format: "%.2f", self.indexStatus.lastRefreshSeconds))초)") }
            }
            if !self.searchText.isEmpty { self.scheduleSearch() }
        }
    }

    /// 설정 · 진단의 **색인 다시 만들기** — 통째로 지우고 처음부터 (ADR-0003).
    func rebuildIndex() async {
        guard let index else { return }
        await index.reset()
        previews = [:]
        log("색인을 지우고 다시 만듦")
        scheduleIndexRefresh()
    }

    // MARK: - 최근 일 (진단)

    /// 무슨 일이 있었는지 — 충돌 · 저장 실패 · 다른 기기 변경. 진단 화면이 보여 준다.
    /// 빨간 띠가 떴는데 원인을 모를 때 이것을 본다 (빌드 18 · 10번). 글은 담지 않는다.
    @Published private(set) var events: [String] = []

    private static let eventClock: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()

    /// 최근 일을 비운다 (T9). 새 시험을 시작할 때 묵은 줄을 치우면 방금 한 일만 남는다.
    func clearEvents() { events.removeAll() }

    func log(_ message: String) {
        events.insert("\(Self.eventClock.string(from: Date())) \(message)", at: 0)
        if events.count > 40 { events.removeLast(events.count - 40) }
    }

    // MARK: - 다른 기기의 변경 지켜보기

    private var watcher: Task<Void, Never>?
    private var folderStamp: FileStamp?
    /// 마지막으로 충돌 판본을 훑은 때. 너무 자주 훑지 않는다.
    private var lastConflictSweep = Date.distantPast
    /// 고른 폴더(b)의 **지금 실제 경로** — 열 때 적어 두고 6초마다 북마크를 다시 풀어 견준다.
    private var chosenFolderPath = ""
    private var lastChosenFolderCheck = Date.distantPast
    /// **최상위 폴더의 도장은 따로 본다.** 보고 있는 폴더만 보면, 다른 기기가 최상위에
    /// 만든 폴더를 놓친다 — 폴더 화면이 안 바뀌던 까닭이다 (빌드 21 · 사용자).
    private var rootStamp: FileStamp?
    /// 마지막으로 폴더 목록을 통째로 다시 읽은 때. 하위 폴더 **안에** 노트가 생기면
    /// 최상위 시각은 안 바뀌므로, 노트 수를 맞추려면 이따금 통째로 읽어야 한다.
    private var lastFolderSweep = Date.distantPast

    /// 앱이 앞에 있는 동안 **몇 초마다 파일 도장을 본다.** iCloud 가 다른 기기의 변경을
    /// 내려놓으면 열린 노트는 (내가 치는 중이 아닐 때) 그 자리에서 새 글로 바뀌고, 폴더에
    /// 무엇이 생기거나 없어지면 목록이 새로 읽힌다 (빌드 18 · 10번 — 당겨야만 보였다).
    /// 내가 치는 중이면 손대지 않는다 — 그때는 저장이 충돌을 가린다 (A15).
    /// iCloud 가 스스로 만든 충돌 판본도 여기서 끌어낸다.
    func startWatching() {
        watcher?.cancel()
        watcher = Task { [weak self] in
            while !Task.isCancelled {
                await self?.checkForExternalChanges()
                try? await Task.sleep(for: .seconds(3))
            }
        }
    }

    func stopWatching() {
        watcher?.cancel()
        watcher = nil
    }

    func checkForExternalChanges() async {
        guard let store else { return }
        // 받는 중이던 노트는 다 왔는지 다시 본다 (86). 3초마다라 곧 열린다.
        if noteIsDownloading, selectedNoteID != nil {
            await loadSelectedText()
            if noteIsDownloading { return }
        }
        // 고른 폴더(b)가 **옮겨졌거나 휴지통에 갔거나 사라졌나.** 앱이 든 URL 은 처음 열 때의
        // 것이라 그것만 봐서는 모른다 (빌드 25 · 7 · 8번 — 다시 켜야만 알아챘다). 6초마다 북마크를
        // **다시 풀어 지금 실제 경로**를 본다: 휴지통 · 없음이면 기본 폴더로 돌아오며 알리고,
        // 경로가 달라졌으면 옮겨진 것이니 따라가며 최근 일에 적는다.
        if kind == .userChosen, Date().timeIntervalSince(lastChosenFolderCheck) > 6 {
            lastChosenFolderCheck = Date()
            let known = chosenFolderPath
            switch FolderSource.bookmarkedFolder() {
            case .stale, .none:
                log("고른 폴더가 휴지통에 가거나 사라져 기본 폴더로 돌아옴")
                lastError = "고른 폴더가 휴지통에 가거나 사라져 기본 iCloud 폴더로 돌아왔습니다. 설정 → 폴더에서 다시 고를 수 있습니다."
                await save()
                FolderSource.forget()
                await use(await FolderSource.current(launch: launch))
                return
            case .folder(let resolved):
                let now = FolderSource.livePath(of: resolved)
                if now != known {
                    log("고른 폴더가 옮겨져 따라감: \(resolved.lastPathComponent)")
                    await save()
                    await use(FolderChoice(url: resolved, kind: .userChosen, iCloudAvailable: iCloudAvailable, attempts: 0))
                    return
                }
            }
        }
        // 열린 노트
        // 치는 중(`isDirty`)이면 손대지 않는다 — 저장이 견주고 필요하면 충돌 사본을 만든다.
        if !isDirty, let path = draftPath, let known = draftStamp,
           let now = await store.stamp(of: path), now != known,
           let text = try? await store.readText(at: path) {
            draftStamp = now
            if text != noteText {
                noteText = text
                draft = text
                log("다른 기기의 변경을 불러옴: \(path)")
                await renderReading(path: path, text: text)
            }
        }
        // **충돌 판본 훑기는 자주 하지 않는다.** 아직 안 내려온 판본을 읽으려면 iCloud 를
        // 기다려야 해서 파일 담당이 그동안 묶인다. 파일이 바뀌었을 때와 30초마다만 본다.
        if let path = draftPath, Date().timeIntervalSince(lastConflictSweep) > 30 {
            lastConflictSweep = Date()
            if let sweep = try? await store.surfaceConflictVersions(of: path) {
                if !sweep.made.isEmpty {
                    log("iCloud 충돌 판본 \(sweep.made.count)개를 사본으로 꺼냄: \(path)")
                    lastError = "iCloud 가 다른 기기의 글을 따로 두었습니다. \(sweep.made.count)개를 (충돌 …) 사본으로 꺼냈습니다."
                    await reloadNotes()
                }
                if sweep.pending > 0 {
                    // 아직 안 내려온 판본이다. **버리지 않았다** — 곧 다시 본다.
                    log("아직 안 내려온 충돌 판본 \(sweep.pending)개 — 그대로 두고 다시 봅니다: \(path)")
                    lastConflictSweep = Date().addingTimeInterval(-25)
                }
            }
        }
        // 보고 있는 폴더 — 노트가 생기거나 없어졌나
        let folderNow = await store.stamp(of: selectedFolder)
        if let known = folderStamp, let folderNow, folderNow != known {
            folderStamp = folderNow
            // **무엇이 왔고 갔는지 적는다.** iCloud 는 같은 이름이 만나면 판본 대신 `A 2` 로
            // 이름을 바꾸기도 한다 — 그때 최근 일에 이 줄이 없으면 무슨 일인지 알 길이 없다 (빌드 20 · 1번).
            let before = Set(notes.map(\.relativePath))
            await reloadFolders()
            await reloadNotes()
            let after = Set(notes.map(\.relativePath))
            for path in after.subtracting(before).sorted() { log("다른 기기에서 온 새 노트: \(path)") }
            for path in before.subtracting(after).sorted() { log("다른 기기에서 사라진 노트: \(path)") }
            if after == before { log("폴더가 바뀌어 목록을 다시 읽음: \(selectedFolder.isEmpty ? "최상위" : selectedFolder)") }
        } else if folderStamp == nil {
            folderStamp = folderNow
        }

        // 최상위 — 폴더가 생기거나 없어졌나. 보고 있는 폴더가 하위여도 이것은 본다.
        if !selectedFolder.isEmpty {
            let rootNow = await store.stamp(of: "")
            if let known = rootStamp, let rootNow, rootNow != known {
                rootStamp = rootNow
                log("최상위가 바뀌어 폴더 목록을 다시 읽음")
                await reloadFolders()
            } else if rootStamp == nil {
                rootStamp = rootNow
            }
        }

        // 하위 폴더 **안**의 변화는 최상위 시각에 안 잡힌다 — 노트 수를 맞추려고
        // 15초마다 폴더 목록을 통째로 읽는다. 값이 같으면 화면은 안 흔들린다.
        //
        // **목록도 같이 견준다.** 폴더 시각에만 기대면, 그 시각이 어떤 이유로든 안 바뀔 때
        // 다른 기기의 삭제 · 추가를 놓친다 (빌드 25 · 사용자 — 아이패드를 켜 둔 채 두면
        // 아이폰에서 지운 것이 안 사라졌다). 목록을 실제로 읽어 다르면 그때만 반영한다.
        if Date().timeIntervalSince(lastFolderSweep) > 15 {
            lastFolderSweep = Date()
            // 다른 기기에서 고정한 것도 여기서 따라온다 (T10).
            await reloadPins()
            await reloadFolders()
            if !isDirty {
                let fresh = await store.notes(in: selectedFolder)
                if Self.fingerprint(fresh) != Self.fingerprint(notes) {
                    log("목록이 달라져 다시 읽음: \(selectedFolder.isEmpty ? "최상위" : selectedFolder)")
                    folderStamp = await store.stamp(of: selectedFolder)
                    await reloadNotes()
                }
            }
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
        색인: \(indexStatus.noteCount)개 · trigram \(indexStatus.trigramAvailable ? "있음" : "없음(LIKE 만)") · \(indexStatus.fileBytes / 1024)KB · 마지막 갱신 \(String(format: "%.2f", indexStatus.lastRefreshSeconds))초
        저장 안 된 글: \(isDirty ? "있음" : "없음")
        마지막 저장: \(lastSaved.map { $0.formatted(date: .omitted, time: .standard) } ?? "없음")
        마지막 오류: \(lastError ?? "없음")
        최근 일:
        \(events.prefix(20).joined(separator: "\n"))
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
        scheduleAutosave()
    }

    private func scheduleAutosave() {
        autosave?.cancel()
        autosave = Task { [weak self] in
            try? await Task.sleep(for: Self.autosaveDelay)
            guard !Task.isCancelled else { return }
            await self?.save()
        }
    }

    /// 지금 쓴다. 노트를 바꾸기 전 · 앱이 뒤로 갈 때 · 읽기로 넘길 때 부른다.
    ///
    /// **저장은 한 번에 하나만 돈다** (빌드 29 · 4번). 부르는 곳이 여럿이다 — 2초 자동
    /// 저장 · 제목 줄 이탈(89) · 노트 바꾸기 · 앱이 뒤로 가기 · 지켜보기. 이것들이
    /// 겹쳐 돌면 앞엣것이 옛 글을 디스크에 넣는 사이 뒤엣것이 새 글을 넣어, 다음 저장이
    /// **제 손으로 쓴 글을 남의 글로 보고** 충돌 사본을 만들었다. 뒤엣것은 앞엣것이
    /// 끝나기를 기다린다.
    func save(settlingTitle: Bool = false) async {
        autosave?.cancel()
        autosave = nil
        // **쓰는 중에 다시 불렸다.** 충돌 사본을 만든 뒤 목록을 다시 읽는 길이 여기로
        // 돌아온다 (`reloadNotes` → `loadSelectedText` → `save`). 앞엣것을 기다리면
        // 그것이 곧 나 자신이라 영영 안 끝난다. 이미 쓰는 중이니 할 일도 없다.
        guard !isWriting else { return }
        let queued = saveChain
        let task = Task { @MainActor [weak self] in
            await queued?.value
            await self?.write(settlingTitle: settlingTitle)
        }
        saveChain = task
        await task.value
    }

    /// 실제로 쓰는 자리. `save` 만 부른다 — 줄 세우기는 그쪽이 한다.
    ///
    /// **자료 유실이 가장 비싼 자리다.** 실패하면 오류를 올리고 `isDirty` 를
    /// 그대로 둔다 — 다음 기회(2초 뒤 · 화면 전환 · 앱 종료 직전)에 다시 쓴다.
    /// `settlingTitle` 은 **제목 줄을 떠났다**는 뜻 — 그때만 파일명을 맞춘다 (89).
    private func write(settlingTitle: Bool) async {
        guard let store, var path = draftPath else { return }
        isWriting = true
        defer { isWriting = false }
        guard isDirty else {
            // 쓸 글은 없지만 **제목 줄을 떠났다** — 이름은 맞춰야 한다 (빌드 29 · 2번).
            // 제목을 치고 2초가 지나면 자동 저장이 글을 먼저 넣어 버린다. 그때는 더는
            // 더럽지 않으니 여기서 물러나면 **이름이 영영 안 맞는다.**
            if settlingTitle { await followTitle(of: draft, at: path) }
            return
        }
        // **쓸 글과 견줄 글을 여기서 한 번 붙든다** (빌드 29 · 4번). 아래의 `await` 가
        // 도는 동안 사용자는 계속 친다. 그때 `draft` 를 다시 읽으면 **디스크에 간 글**과
        // **기억해 둔 글**이 어긋나고, 다음 저장이 그 어긋남을 다른 기기의 글로 읽어
        // 헛충돌 사본을 만든다. 지금 쓰는 것은 이 글 하나다.
        let written = draft
        let expecting = noteText
        let original = path
        var conflictPath: String?
        do {
            // **덮어쓰기 전에 파일이 그대로인지 본다** (설계서 §7.2 · A15). 검사는 저장소가
            // 조정 **안**에서 한다 — 검사와 쓰기 사이에 다른 기기의 글이 들어와도 덮지 않는다.
            // 정말 다른 글이면 **덮어쓰지 않고** `이름 (충돌 …).md` 로 나란히 쓰고 그쪽을 연다.
            do {
                try await store.writeText(written, to: path, expecting: expecting)
                lastError = nil
            } catch WriteConflict.changedOnDisk {
                let name = path.split(separator: "/").last.map(String.init) ?? path
                let conflict = try await store.createNote(
                    named: FolderStore.conflictName(for: name),
                    in: Paths.directory(of: path), text: written)
                draftPath = conflict
                path = conflict
                conflictPath = conflict
                let shown = conflict.split(separator: "/").last.map(String.init) ?? conflict
                lastError = "다른 기기에서 고친 노트입니다. 내 글은 \(shown) 로 나란히 저장했습니다."
                log("충돌: \(name) 이 디스크에서 바뀌어 내 글을 \(shown) 로 저장")
            }
            draftStamp = await store.stamp(of: path)
            noteText = written
            // 쓰는 동안 더 쳤으면 **아직 더럽다.** 무턱대고 내리면 그 글자들이 다음
            // 편집 때까지 파일에 안 들어간다 (빌드 29 · 4번).
            isDirty = draft != written
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
                                           size: (written as NSString).length, isDownloaded: old.isDownloaded)
                notes.sort { $0.modifiedAt > $1.modifiedAt }
            }
            await renderReading(path: path, text: written)
            // **제목 줄에 커서가 있는 동안에는 이름을 안 바꾼다** (89).
            if settlingTitle || !cursorOnTitleLine {
                await followTitle(of: written, at: path)
            }
            scheduleIndexRefresh()
            if isDirty { scheduleAutosave() }
        } catch ReadError.notDownloaded {
            // 디스크를 확인할 수 없어 **덮지 않았다.** `isDirty` 를 그대로 둬 다음 기회에 다시 쓴다 (86).
            saveFailed = true
            lastError = "iCloud 에서 받는 중이라 아직 저장하지 않았습니다. 잠시 뒤 다시 저장합니다."
            log("내려받는 중이라 저장을 미룸: \(path)")
        } catch {
            saveFailed = true
            lastError = "저장하지 못했습니다: \(error.localizedDescription)"
            log("저장 실패: \(path) — \(error.localizedDescription)")
        }
    }

    /// **첫 줄 `# 제목` 을 파일명이 따라간다** (54, 사용자 요청). 저장이 성공한 뒤에만.
    /// 제목이 없거나 이미 같으면 아무것도 안 한다. 이름이 겹치면 `제목 2.md` 가 되고,
    /// 그 뒤로는 `제목 2` 자리를 지킨다 (`FolderStore.rename` 의 `keeping`).
    /// 편집기는 건드리지 않는다 — `editorSession` 이 그대로라 커서도 키보드도 그대로다.
    private func followTitle(of text: String, at path: String) async {
        guard syncsFileName, let store, let heading = FrontMatterParser.firstLine(of: text) else { return }
        let wanted = Paths.safeFileName(heading, fallback: "")
        let fileName = path.split(separator: "/").last.map(String.init) ?? path
        guard !wanted.isEmpty, wanted != Paths.baseName(fileName) else { return }
        do {
            let moved = try await store.rename(path, to: wanted)
            guard moved != path else { return }
            // 이름이 바뀌면 고정도 따라간다 (T10) — 안 그러면 제목을 고쳤을 때 고정이 풀린다.
            pinned = await store.followPins(from: path, to: moved)
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

    func clearError() {
        lastError = nil
        errorIsAboutNote = false
    }

    /// 지금 띠에 뜬 오류가 **이 노트를 읽다가 난 것인가** (138, 사용자 — 노트를 열면 띠가
    /// 사라져 확인할 수 없었다). 노트를 성공적으로 읽으면 *그 노트에 대한* 오류만 치운다 —
    /// **저장 실패 · 지우기 실패 같은 남의 오류는 그대로 둔다.** 그것까지 지우면
    /// **진짜 실패도 노트만 열면 사라진다.**
    private var errorIsAboutNote = false

    /// 화면이 오류를 올리는 문. `lastError` 의 setter 는 모델 안에만 있다.
    func report(_ message: String) {
        lastError = message
        errorIsAboutNote = false
        log("오류: \(message)")
    }

    /// **방금 읽은 목록으로 그 폴더의 숫자를 맞춘다** (153).
    ///
    /// 목록과 숫자가 **한 번 읽은 것**에서 같이 나오므로 둘이 갈라질 수 없다. 노트를
    /// 만들거나 지우는 길은 하나같이 `reloadNotes()` 를 부르므로, 길마다
    /// `reloadFolders()` 를 손으로 덧붙이는 것보다 **여기 한 자리**가 낫다 — 덧붙이는
    /// 쪽은 다음에 길이 하나 늘면 또 잊는다.
    ///
    /// `notes(in:)` 과 `noteCount(in:)` 이 **같은 거름망**(`Paths.countsAsNote`)을 쓰므로
    /// 여기서 넣는 값과 폴더를 다시 읽어 센 값이 어긋나지 않는다.
    private func syncCount(of folder: String, to count: Int) {
        if folder.isEmpty {
            if rootNoteCount != count { rootNoteCount = count }
            return
        }
        guard let at = folders.firstIndex(where: { $0.relativePath == folder }),
              folders[at].noteCount != count else { return }
        folders[at] = FolderSummary(relativePath: folders[at].relativePath,
                                    name: folders[at].name, noteCount: count)
    }

    /// **값이 같으면 갈아 끼우지 않는다.** 지켜보기가 이따금 부르는 길이라,
    /// 같은 목록을 다시 넣으면 화면이 까닭 없이 다시 그려진다.
    func reloadFolders() async {
        guard let store else { return }
        let loaded = await store.folders()
        if loaded != folders { folders = loaded }
        // 맨 윗줄도 아래 폴더들과 **같은 셈법**으로 센다 (153).
        let root = await store.noteCount(in: "")
        if root != rootNoteCount { rootNoteCount = root }
        rootStamp = await store.stamp(of: "")
        lastFolderSweep = Date()
    }

    func reloadNotes() async {
        guard let store else { return }
        isLoading = true
        // **목록에 걸린 시간을 앱이 잰다** (S1 — 300개를 3초 안에). 사람이 초시계를
        // 들 수는 없다. 오래 걸렸을 때만 적는다 — 평소에 최근 일을 어지럽히지 않는다.
        let started = Date()
        folderStamp = await store.stamp(of: selectedFolder)
        let loaded = await store.notes(in: selectedFolder)
        listSeconds = Date().timeIntervalSince(started)
        if loaded.count >= 100 || listSeconds > 0.5 {
            let where_ = selectedFolder.isEmpty ? "최상위" : selectedFolder
            log("목록 \(loaded.count)개 — \(String(format: "%.2f", listSeconds))초 · \(where_)")
        }
        notes = Self.withPreviews(loaded, from: previews)
        // 다 받아진 것은 `받는 중` 에서 뺀다 (156).
        let arrived = Set(loaded.filter(\.isDownloaded).map(\.relativePath))
        if !arrived.isDisjoint(with: downloading) { downloading.subtract(arrived) }
        syncCount(of: selectedFolder, to: loaded.count)
        scheduleIndexRefresh()
        // 링크를 따라온 노트는 목록에 없는 것이 맞다 — 지우지 않는다 (T7).
        if let current = selectedNoteID, current != linkedNote?.relativePath,
           !loaded.contains(where: { $0.id == current }) {
            selectedNoteID = nil
        }
        if selectedNoteID == nil, autoSelectsFirstNote {
            selectedNoteID = loaded.first?.id
        }
        isLoading = false
        await loadSelectedText()
    }

    func loadSelectedText() async {
        // 노트를 떠난다 — 제목 줄에 커서가 있었어도 여기서 확정한다 (89).
        cursorOnTitleLine = false
        // 붙여넣을 때 쓸 금고 목록을 뒤에서 읽어 둔다 (144).
        refreshVaultPathsIfNeeded()
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
        // **커서가 튀면 여기를 의심한다.** 열려 있는 노트를 다시 읽으면 편집기가 글을
        // 통째로 갈아 끼우고, 그때 커서는 글 끝으로 가며 화면이 그리로 끌려간다.
        // 제자리 걸음이면 위에서 이미 물러났으므로, 여기까지 왔다는 것은 디스크가 정말
        // 달라졌다는 뜻이다 — 최근 일에 남겨 둬야 다음에 원인을 짚을 수 있다 (빌드 31 · 2번).
        if note.relativePath == draftPath {
            log("열려 있는 노트를 다시 읽음 — 편집기가 글을 갈아 끼운다: \(note.relativePath)")
        }
        do {
            let text = try await store.readText(at: note.relativePath)
            // **이 파일이 UTF-8 이었나.** 아니면 예전 인코딩으로 읽어 낸 것이고,
            // 여는 것만으로 고쳐 쓰면 남의 파일을 바꾸는 셈이다 (62를 건너뛴다).
            let encoding = await store.encoding(of: note.relativePath)
            let isUTF8 = encoding == .utf8
            if let encoding, !isUTF8 {
                log("UTF-8 이 아닌 파일을 \(FolderStore.encodingName(encoding)) 로 읽음: \(note.relativePath)")
            }
            // **이미 깨진 글자가 든 파일.** 앱이 그렇게 만든 것이 아니라 파일에 그렇게
            // 저장돼 있다 — 고쳐 쓰지 않고 알리기만 한다 (빌드 19 · 14번).
            let broken = text.contains("\u{FFFD}")
            if broken {
                log("이미 깨진 글자가 든 파일: \(note.relativePath)")
                lastError = "이 노트에는 이미 깨진 글자가 있습니다. 파일이 그렇게 저장돼 있어 앱이 되살릴 수 없습니다."
                errorIsAboutNote = true
            }
            // **앱은 본문을 고치지 않는다** (T6, 2026-09-16 사용자 결정). 예전에는 여기서
            // 62(파일명이 이긴다)가 돌아 밖에서 온 파일의 `# 제목` 을 `## ` 로 내리고 파일명을
            // 위에 얹었다. 자료 사고가 전부 거기서 나왔다 (빌드 20 · 1, 30 · 5, 32 · 103).
            // 이제 맞추는 길은 **한 방향뿐이다 — 첫 줄이 파일명을 끌고 간다** (`followTitle`).
            // 밖에서 온 파일은 이름이 달라도 **그대로 둔다.** 목록에는 첫 줄이 보인다.
            let isNewlyOpened = note.relativePath != draftPath
            noteText = text
            draft = text
            draftPath = note.relativePath
            draftStamp = await store.stamp(of: note.relativePath)
            isDirty = false
            // **다른 노트로 갈 때만 정체성을 바꾼다** (103). 정체성이 바뀌면 편집기는
            // 글을 **묻지 않고** 갈아 끼운다 — 한글을 조합하는 중이었다면 그 자리에서
            // 쪼개진다 (`팀 이` 와 `ㅅ` 이 따로 남았다). 같은 노트를 다시 읽는 것은
            // 편집기의 `load` 가 판정한다: 사용자가 손댔으면 그쪽이 최신이라 안 덮는다.
            if isNewlyOpened { editorSession = UUID() }
            // **노트를 열 때 읽기 모드로** (124). 부른 쪽이 모드를 이미 정했으면(새 노트 ·
            // `왔던 노트` · 시험 파일) 그쪽을 따른다. **편집 모드로 되돌리지는 않는다** —
            // 스위치는 켜는 쪽으로만 움직인다.
            if isNewlyOpened {
                if modeAlreadyChosen { modeAlreadyChosen = false }
                else if opensInReadingMode { isReading = true }
            }
            noteIsDownloading = false
            // **이 노트에 대한 오류만 치운다** (138). 예전에는 어떤 오류든 지웠다.
            if !broken, isUTF8, errorIsAboutNote {
                lastError = nil
                errorIsAboutNote = false
            }
            await renderReading(path: note.relativePath, text: text)
        } catch ReadError.notDownloaded {
            // 아직 내려받는 중이다. **아무것도 쓰지 않는다** — 다 오면 지켜보기가 다시 부른다 (86).
            // 띠 대신 **내용 자리에 도는 표시**를 띄운다 — 띠는 잠깐 떴다 사라져 못 보고 지나친다.
            clearNote()
            noteIsDownloading = true
            // **받으라고 시킨 것을 적어 둔다** (156). `readText` 가 이 자리에서
            // `startDownloadingUbiquitousItem` 을 불렀으므로, 이제는 정말 받는 중이다.
            downloading.insert(note.relativePath)
            log("아직 내려받는 중: \(note.relativePath)")
        } catch CocoaError.fileReadInapplicableStringEncoding {
            clearNote()
            log("글자 인코딩을 못 알아본 파일: \(note.relativePath)")
            lastError = "이 파일의 글자 인코딩을 알아보지 못했습니다. UTF-8 로 저장한 뒤 다시 열어 주세요."
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
    ///
    /// **목록에 없다고 없는 파일은 아니다** — 목록이 늦었을 수 있다. 그래서 폴더를 다시 읽고
    /// 고른다. 정말 없으면 그렇다고 말한다 (빌드 20 · 10 · 11번 — 링크로 열 때만 어긋났다).
    /// **링크를 따라 다른 노트로 간다** (T7, 사용자 요청 — 메모 앱의 메모 간 링크처럼).
    ///
    /// **보고 있는 폴더를 건드리지 않는다.** 예전에는 그 파일의 폴더로 목록을 통째로 옮겨,
    /// `assets/` 안의 `.md` 로 가면 목록이 `assets` 로 끌려갔다 (빌드 24 · 17번). 지금은
    /// 상세 칸에만 띄우고, 왔던 자리를 **자취**에 쌓아 되돌아갈 수 있게 한다.
    /// 도착하면 **편집 모드**다 — 돌아올 때는 떠날 때의 모드를 되살린다.
    func open(relativePath: String) async {
        guard let store else { return }
        guard await store.existingPaths(among: [relativePath]).contains(relativePath) else {
            log("링크가 가리키는 노트가 없음: \(relativePath)")
            lastError = "링크가 가리키는 노트가 폴더에 없습니다: \(relativePath)"
            return
        }
        guard relativePath != selectedNoteID else { return }
        await save()
        var trail = linkTrail
        trail.append(LinkStep(folder: selectedFolder, notePath: selectedNoteID,
                              linked: linkedNote != nil, wasReading: isReading))
        // 목록에 있으면 그 줄을 쓰고(선택 표시가 산다), 없으면 파일에서 요약을 만든다.
        if let match = notes.first(where: { $0.relativePath == relativePath }) {
            linkedNote = nil
            selectedNoteID = match.id
        } else {
            linkedNote = await store.summary(of: relativePath)
            selectedNoteID = relativePath
        }
        linkTrail = trail   // `selectedNoteID` 의 `didSet` 이 접은 것을 되돌린다.
        isReading = false
        log("링크를 따라 감: \(relativePath)")
    }

    /// **왔던 노트로 되돌아간다** (T7). 폴더 · 노트 · 모드를 떠날 때대로 되살린다.
    func goBackAlongLink() async {
        guard let step = linkTrail.popLast() else { return }
        await save()
        let trail = linkTrail
        if step.folder != selectedFolder {
            selectedFolder = step.folder
            await reloadFolders()
            await reloadNotes()
        }
        if step.linked, let path = step.notePath, let store {
            linkedNote = await store.summary(of: path)
        } else {
            linkedNote = nil
        }
        modeAlreadyChosen = true    // 떠날 때의 모드를 되살린다 — 스위치가 덮지 않는다 (124)
        selectedNoteID = step.notePath
        linkTrail = trail       // `selectedNoteID` 의 `didSet` 이 접은 것을 되돌린다.
        isReading = step.wasReading
    }

    private func clearNote() {
        noteIsDownloading = false
        cursorImage = nil
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
