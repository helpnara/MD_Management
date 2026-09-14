import SwiftUI
import PhotosUI
import Core

/// 아이패드는 3단, 아이폰은 같은 뷰가 스택으로 접힌다 (ADR-0006).
struct RootView: View {
    @EnvironmentObject private var library: LibraryModel
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.scenePhase) private var scenePhase
    @State private var columnVisibility = NavigationSplitViewVisibility.all

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            FolderSidebar()
        } content: {
            NoteList()
        } detail: {
            NoteDetail()
        }
        .navigationSplitViewStyle(.balanced)
        .tint(Palette.accent)
        .task {
            library.autoSelectsFirstNote = prefersPreselectedNote
            await library.start()
            if library.launch.attachmentTest { await library.makeAttachmentTest() }
            if library.launch.newNote { await library.createNote() }
        }
        .task(id: library.selectedFolder) {
            library.autoSelectsFirstNote = prefersPreselectedNote
            await library.reloadNotes()
        }
        .task(id: library.selectedNoteID) { await library.loadSelectedText() }
        // 앱이 다시 앞으로 나올 때 iCloud 를 한 번 더 찾아본다. 설치 직후
        // 첫 실행은 컨테이너가 아직 준비되지 않아 못 잡는 일이 있다 (A2).
        .task(id: scenePhase) {
            if scenePhase == .active {
                await library.retryICloud()
                // 앞에 있는 동안만 다른 기기의 변경을 지켜본다. 뒤로 가면 멈춘다.
                library.startWatching()
            } else {
                library.stopWatching()
            }
        }
        // **앱이 뒤로 갈 때 반드시 쓴다.** `.task(id:)` 는 화면이 사라지면 함께
        // 끊기므로 여기서는 쓰지 않는다 — 저장이 끊기면 그대로 자료가 사라진다.
        .onChange(of: scenePhase) { _, phase in
            guard phase != .active else { return }
            Task { await library.save() }
        }
        // **배너는 아래에 둔다.** 위에 두면 내비게이션 바를 덮어 제목과 버튼이
        // 잘린다 (빌드 2 스크린샷). 아래는 덮을 것이 없다.
        .safeAreaInset(edge: .bottom, spacing: 0) { StatusBanner() }
        // **시트는 하나로 모은다.** 한 뷰에 `.sheet` 를 여러 개 걸면 마지막
        // 것만 뜬다 — 진단을 눌렀는데 설정이 뜨는 식으로 조용히 어긋난다.
        .modifier(NoteActionAlerts())
        .sheet(item: $library.sheet) { sheet in
            switch sheet {
            case .settings:
                SettingsView().environmentObject(library)
            case .diagnostics:
                DiagnosticsView().environmentObject(library)
            case .incoming(let file):
                IncomingFileSheet(file: file).environmentObject(library)
            case .preview(let url):
                AttachmentPreview(url: url)
            }
        }
    }

    /// 아이패드(regular)는 상세 칸이 비면 어색하니 첫 노트를 미리 고른다.
    /// 아이폰은 목록으로 열려야 한다 — `-openFirstNote` 는 CI 가 상세를 찍을 때만.
    private var prefersPreselectedNote: Bool {
        horizontalSizeClass == .regular || library.launch.openFirstNote
    }
}

/// 이름 바꾸기 · 지우기 확인창. **따로 뗀 이유:** 본체의 수식어 체인에 알림창
/// 둘을 더 걸었더니 컴파일러가 타입 검사 시간을 넘겼다 (빌드 8 첫 시도).
private struct NoteActionAlerts: ViewModifier {
    @EnvironmentObject private var library: LibraryModel

    func body(content: Content) -> some View {
        content
            .alert("이름 바꾸기", isPresented: renamePresented, presenting: library.renaming,
                   actions: renameActions, message: renameMessage)
            // **모든 삭제에 확인.** 지우지 않고 `.trash/` 로 옮긴다 (CLAUDE.md §1).
            .alert("지울까요?", isPresented: trashPresented, presenting: library.trashing,
                   actions: trashActions, message: trashMessage)
    }

    private var renamePresented: Binding<Bool> {
        Binding(get: { library.renaming != nil }, set: { if !$0 { library.renaming = nil } })
    }

    private var trashPresented: Binding<Bool> {
        Binding(get: { library.trashing != nil }, set: { if !$0 { library.trashing = nil } })
    }

    @ViewBuilder
    private func renameActions(_ note: NoteSummary) -> some View {
        TextField("파일 이름", text: $library.renameText)
        Button("바꾸기") { Task { await library.finishRename(note) } }
        Button("취소", role: .cancel) { library.renaming = nil }
    }

    private func renameMessage(_ note: NoteSummary) -> some View {
        Text("\(note.fileName) 의 새 이름입니다. 확장자는 안 적어도 됩니다.")
    }

    @ViewBuilder
    private func trashActions(_ note: NoteSummary) -> some View {
        Button("지우기", role: .destructive) { Task { await library.finishTrash(note) } }
        Button("취소", role: .cancel) { library.trashing = nil }
    }

    private func trashMessage(_ note: NoteSummary) -> some View {
        Text("\(note.title) 을 폴더 안 .trash 로 옮깁니다. 설정 → 휴지통에서 되돌릴 수 있습니다.")
    }
}

/// 하위 폴더의 이름 바꾸기 · 지우기 확인창. 노트의 것과 같은 말투로 (사용자 요청).
private struct FolderActionAlerts: ViewModifier {
    @EnvironmentObject private var library: LibraryModel

    func body(content: Content) -> some View {
        content
            .alert("폴더 이름 바꾸기", isPresented: renamePresented, presenting: library.renamingFolder,
                   actions: renameActions, message: renameMessage)
            .alert("폴더를 지울까요?", isPresented: trashPresented, presenting: library.trashingFolder,
                   actions: trashActions, message: trashMessage)
    }

    private var renamePresented: Binding<Bool> {
        Binding(get: { library.renamingFolder != nil }, set: { if !$0 { library.renamingFolder = nil } })
    }

    private var trashPresented: Binding<Bool> {
        Binding(get: { library.trashingFolder != nil }, set: { if !$0 { library.trashingFolder = nil } })
    }

    @ViewBuilder
    private func renameActions(_ folder: FolderSummary) -> some View {
        TextField("폴더 이름", text: $library.folderRenameText)
        Button("바꾸기") { Task { await library.finishRenameFolder(folder) } }
        Button("취소", role: .cancel) { library.renamingFolder = nil }
    }

    private func renameMessage(_ folder: FolderSummary) -> some View {
        Text("\(folder.name) 폴더의 새 이름입니다. 안의 노트는 그대로 따라갑니다.")
    }

    @ViewBuilder
    private func trashActions(_ folder: FolderSummary) -> some View {
        Button("지우기", role: .destructive) { Task { await library.finishTrashFolder(folder) } }
        Button("취소", role: .cancel) { library.trashingFolder = nil }
    }

    private func trashMessage(_ folder: FolderSummary) -> some View {
        Text("\(folder.name) 폴더와 안의 노트 \(folder.noteCount)개를 폴더 안 .trash 로 옮깁니다. 설정 → 휴지통에서 노트를 되돌리면 폴더도 다시 생깁니다.")
    }
}

/// 화면 아래 띠. 지금 무엇이 이상한지 **늘 보이게** 한다.
///
/// - 둘러보기 중: 실제 자료와 섞이지 않게 (`LESSONS_LEARNED` §5)
/// - iCloud 로 못 갔을 때: 조용히 기기 안 폴더를 쓰는 것을 숨기지 않는다 (A2)
struct StatusBanner: View {
    @EnvironmentObject private var library: LibraryModel
    /// 시트 안에서는 **오류만** 보여 준다 — iCloud · 둘러보기 안내는 바깥 화면의 몫이다.
    var errorsOnly = false

    var body: some View {
        if let error = library.lastError {
            // **실패는 보여야 한다.** 빌드 7 에서 이 자리를 없앴더니 빌드 8 의
            // 이름 바꾸기 · 지우기가 조용히 실패해도 아무도 몰랐다.
            Button {
                library.clearError()
            } label: {
                HStack(spacing: Metrics.rowSpacing) {
                    Image(systemName: "exclamationmark.circle.fill")
                    Text(error)
                        .multilineTextAlignment(.leading)
                    Spacer(minLength: 0)
                    Image(systemName: "xmark")
                }
                .font(.scaled(.footnote, weight: .semibold))
                .foregroundStyle(Palette.ink)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, Metrics.gutter)
                .padding(.vertical, Metrics.rowSpacing)
                .background(Color.red.opacity(0.16))
                .overlay(alignment: .top) {
                    Rectangle().fill(Palette.rule).frame(height: 0.5)
                }
            }
            .buttonStyle(.plain)
        } else if library.isFallenBackFromICloud, !errorsOnly {
            Button {
                library.sheet = .diagnostics
            } label: {
                HStack(spacing: Metrics.rowSpacing) {
                    Image(systemName: "exclamationmark.icloud")
                    Text("iCloud 폴더를 쓰지 못하고 있습니다 · 눌러서 보기")
                        .multilineTextAlignment(.leading)
                    Spacer(minLength: 0)
                }
                .font(.scaled(.footnote, weight: .semibold))
                .foregroundStyle(Palette.ink)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, Metrics.gutter)
                .padding(.vertical, Metrics.rowSpacing)
                .background(Color.orange.opacity(0.18))
                .overlay(alignment: .top) {
                    Rectangle().fill(Palette.rule).frame(height: 0.5)
                }
            }
            .buttonStyle(.plain)
        } else if library.isSample, !errorsOnly {
            // 한 낱말이 아니라 문장이다. 큰 글씨에서는 **줄을 바꿔야** 한다 —
            // `lineLimit(1)` 은 배지 · 짧은 라벨에만 쓴다.
            Text("둘러보기 자료입니다 · 실제 파일이 아닙니다")
                .font(.scaled(.footnote, weight: .semibold))
                .foregroundStyle(Palette.ink)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, Metrics.gutter)
                .padding(.vertical, Metrics.rowSpacing)
                .background(Palette.paperRaised)
                .overlay(alignment: .top) {
                    Rectangle().fill(Palette.rule).frame(height: 0.5)
                }
        }
    }
}

private struct FolderSidebar: View {
    @EnvironmentObject private var library: LibraryModel
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    /// 목록의 선택은 `library.selectedFolder` 와 따로 둔다.
    ///
    /// 아이폰에서 뒤로 가 폴더 화면으로 오면 **이미 고른 폴더가 선택된 채**라서,
    /// 다시 눌러도 값이 안 바뀌어 목록으로 넘어가지 않았다 (빌드 9). 그래서 이
    /// 화면이 나타날 때 선택만 비운다 — 어느 줄을 눌러도 값이 바뀌어 넘어간다.
    /// 그 비움이 `library` 까지 가면 목록이 지워지므로 여기 갈라 둔다.
    @State private var selection: String? = ""
    /// 처음 나타날 때는 비우지 않는다 — 비우면 **앱이 폴더 화면으로 열린다**
    /// (빌드 10 첫 시도, CI 스크린샷이 잡았다). 뒤로 돌아왔을 때만 비운다.
    @State private var hasAppeared = false

    var body: some View {
        List(selection: $selection) {
            Section {
                row(name: library.folderName, path: "", count: library.notes.count, isRoot: true)
                ForEach(library.folders) { folder in
                    row(name: folder.name, path: folder.relativePath, count: folder.noteCount, isRoot: false)
                        .swipeActions(edge: .trailing) { folderSwipeActions(for: folder) }
                }
            } footer: {
                Label(library.kind.label, systemImage: icon(for: library.kind))
                    .font(.scaled(.caption))
                    .foregroundStyle(Palette.inkFaint)
            }
        }
        .navigationTitle("폴더")
        .navigationBarTitleDisplayMode(.inline)
        // 노트 목록과 같이 당겨서 새로 고침 (사용자 요청). 지켜보기가 놓친 것도 여기서 잡는다.
        .refreshable {
            await library.reloadFolders()
            await library.reloadNotes()
        }
        .onAppear {
            defer { hasAppeared = true }
            guard hasAppeared, horizontalSizeClass == .compact, library.sheet == nil else { return }
            selection = nil
        }
        .onChange(of: selection) { _, chosen in
            guard let chosen, chosen != library.selectedFolder else { return }
            library.selectedFolder = chosen
        }
        // 새 폴더를 만들면 `library.selectedFolder` 가 먼저 바뀐다. 그때 이 화면의
        // 선택도 따라가야 목록으로 **넘어간다** (빌드 15 · 2번 — `nil` 이면 안 따라가
        // 폴더만 생기고 화면은 그대로였다).
        .onChange(of: library.selectedFolder) { _, folder in
            selection = folder
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    library.newFolderName = ""
                    library.creatingFolder = true
                } label: {
                    Label("새 폴더", systemImage: "folder.badge.plus")
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    library.sheet = .settings
                } label: {
                    Label("설정", systemImage: "gearshape")
                }
            }
        }
        .modifier(FolderActionAlerts())
        // 새 폴더 (52). 최상위 바로 아래 한 단계만 — 폴더 안의 폴더는 아직 없다.
        .alert("새 폴더", isPresented: $library.creatingFolder) {
            TextField("폴더 이름", text: $library.newFolderName)
            Button("만들기") { Task { await library.finishCreateFolder() } }
            Button("취소", role: .cancel) { library.creatingFolder = false }
        } message: {
            Text("\(library.folderName) 안에 폴더를 만듭니다. 같은 이름이 있으면 뒤에 번호를 붙입니다.")
        }
    }

    /// 하위 폴더에도 노트처럼 지우기 · 이름 (사용자 요청, 빌드 17). 최상위는 없다.
    @ViewBuilder
    private func folderSwipeActions(for folder: FolderSummary) -> some View {
        // 노트 줄과 같은 이유로 `role: .destructive` 를 안 쓴다 (위 `swipeActions` 주석).
        Button {
            library.trashingFolder = folder
        } label: {
            Label("지우기", systemImage: "trash")
        }
        .tint(.red)
        Button {
            library.beginRenameFolder(folder)
        } label: {
            Label("이름", systemImage: "pencil.line")
        }
        .tint(Palette.accent)
    }

    private func row(name: String, path: String, count: Int, isRoot: Bool) -> some View {
        Label {
            HStack(spacing: Metrics.rowSpacing) {
                Text(name)
                    .font(.scaled(.body, weight: isRoot ? .semibold : .regular))
                Spacer(minLength: 0)
                if count > 0 {
                    Text("\(count)")
                        .font(.scaled(.caption))
                        .foregroundStyle(Palette.inkFaint)
                        .lineLimit(1)
                        .fixedSize()
                }
            }
        } icon: {
            Image(systemName: isRoot ? "tray.full" : "folder")
        }
        .tag(path)
    }

    private func icon(for kind: FolderKind) -> String {
        switch kind {
        case .iCloudContainer: return "icloud"
        case .userChosen: return "folder.badge.gearshape"
        case .localDocuments: return "iphone"
        case .sample: return "eyeglasses"
        }
    }
}

private struct NoteList: View {
    @EnvironmentObject private var library: LibraryModel

    var body: some View {
        List(selection: $library.selectedNoteID) {
            ForEach(library.notes) { note in
                row(for: note)
                    .tag(note.id)
                    .swipeActions(edge: .trailing) { swipeActions(for: note) }
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task { await library.createNote() }
                } label: {
                    Label("새 노트", systemImage: "square.and.pencil")
                }
                .keyboardShortcut("n", modifiers: .command)
            }
        }
        // 당겨서 새로 고침 — iCloud 로 다른 기기에서 온 변화 · 휴지통에서 되돌린 것.
        .refreshable {
            await library.reloadFolders()
            await library.reloadNotes()
        }
        .overlay {
            if library.notes.isEmpty && !library.isLoading {
                ContentUnavailableView(
                    "노트가 없습니다",
                    systemImage: "doc.text",
                    description: Text("이 폴더에 마크다운 파일이 없습니다."))
            }
        }
        .navigationTitle(library.selectedFolder.isEmpty ? library.folderName : library.selectedFolder)
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private func swipeActions(for note: NoteSummary) -> some View {
        // **`role: .destructive` 를 쓰지 않는다.** 그 역할을 주면 SwiftUI 가 누르는 즉시
        // **줄이 지워지는 시늉**을 한다 — 아래 노트가 위로 올라왔다가, 우리는 확인창만
        // 띄우고 아무것도 안 지우므로 도로 내려온다. 그 깜빡임이 어색했다 (빌드 21 · 사용자).
        // 빨간색은 손으로 준다 — 보이는 모습은 같고 지우는 시늉만 없앤다.
        Button {
            library.trashing = note
        } label: {
            Label("지우기", systemImage: "trash")
        }
        .tint(.red)
        Button {
            library.beginRename(note)
        } label: {
            Label("이름", systemImage: "pencil.line")
        }
        .tint(Palette.accent)
    }

    private func row(for note: NoteSummary) -> some View {
                VStack(alignment: .leading, spacing: Metrics.rowSpacing) {
                    HStack(spacing: Metrics.rowSpacing) {
                        Text(note.title)
                            .font(.scaled(.body, weight: .medium))
                            .foregroundStyle(Palette.ink)
                        if !note.isDownloaded {
                            // iCloud 에 있지만 아직 안 내려온 파일 (설계서 §7.1)
                            Image(systemName: "icloud.and.arrow.down")
                                .foregroundStyle(Palette.inkFaint)
                        }
                    }
                    // 날짜만으로는 오늘 고친 여러 노트가 안 갈린다 — 시각까지 (50).
                    Text(note.modifiedAt, format: .dateTime.year().month().day().hour().minute())
                        .font(.scaled(.caption))
                        .foregroundStyle(Palette.inkFaint)
                }
                .padding(.vertical, 2)
    }
}

private struct NoteDetail: View {
    @EnvironmentObject private var library: LibraryModel
    @Environment(\.openURL) private var openURL
    @State private var alert: String?
    /// 사진첩에서 고른 것들. 고르면 바로 읽어 **한 번에** 넣고 비운다 (77).
    @State private var pickedPhotos: [PhotosPickerItem] = []
    @State private var showsPhotoPicker = false
    @State private var showsCamera = false
    /// 문서 첨부 창 (78). 사진과 같은 길 — `assets/` 로 복사하고 링크를 넣는다.
    @State private var showsDocumentPicker = false

    var body: some View {
        Group {
            if let note = library.selectedNote {
                content(for: note)
                    // 제목은 **직접 그린다.** 기본 제목은 iOS 가 툴바 버튼 수에 따라
                    // 가운데 · 왼쪽으로 옮겨 이름마다 자리가 달랐다 (49). 늘 왼쪽 ·
                    // 한 줄 · 꼬리 `…` 로 통일한다.
                    .navigationTitle("")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        // `topBarLeading` 에 두면 iOS 26 이 뒤로 버튼 옆 작은 캡슐로 묶어
                        // `20…` 으로 눌러 버린다 (빌드 13 스크린샷). `principal` 은 가운데
                        // 칸을 통째로 받으므로, 그 안에서 왼쪽에 붙이고 남은 폭을 다 쓴다.
                        ToolbarItem(placement: .principal) {
                            HStack(spacing: 0) {
                                Text(note.title)
                                    .font(.scaled(.headline))
                                    .foregroundStyle(Palette.ink)
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                                Spacer(minLength: 0)
                            }
                            .frame(maxWidth: .infinity)
                        }
                        toolbarContent(for: note)
                    }
            } else {
                ContentUnavailableView("노트를 고르세요", systemImage: "doc.text.magnifyingglass")
            }
        }
        .background(Palette.paper)
        .photosPicker(isPresented: $showsPhotoPicker, selection: $pickedPhotos,
                      maxSelectionCount: 20, matching: .images)
        .onChange(of: pickedPhotos) { _, items in
            guard !items.isEmpty else { return }
            pickedPhotos = []
            Task {
                var datas: [Data] = []
                for item in items {
                    if let data = try? await item.loadTransferable(type: Data.self) { datas.append(data) }
                }
                await library.insertPhotos(datas)
            }
        }
        .fileImporter(isPresented: $showsDocumentPicker, allowedContentTypes: [.item],
                      allowsMultipleSelection: true) { result in
            switch result {
            case .success(let urls):
                Task { await library.attachDocuments(urls) }
            case .failure(let error):
                library.lastError = "문서를 고르지 못했습니다: \(error.localizedDescription)"
            }
        }
        .fullScreenCover(isPresented: $showsCamera) {
            CameraView { data in Task { await library.insertPhoto(data) } }
                .ignoresSafeArea()
        }
        .alert("찾을 수 없습니다", isPresented: Binding(
            get: { alert != nil },
            set: { if !$0 { alert = nil } })) {
            Button("확인", role: .cancel) { alert = nil }
        } message: {
            Text(alert ?? "")
        }
    }

    @ViewBuilder
    private func content(for note: NoteSummary) -> some View {
        if library.isReading {
            // 읽기 — 표 · 코드 · 핀치 줌이 공짜다 (ADR-0004)
            // **`ignoresSafeArea` 를 쓰지 않는다.** 바깥 `NavigationSplitView` 에
            // 아래쪽 `safeAreaInset`(배너)이 걸려 있는데 안쪽에서 안전 영역을
            // 무시하면, 아이패드에서 이 뷰가 칸 밖으로 넘쳐 화면 전체를 덮었다
            // (빌드 4 스크린샷 — 사이드바 · 목록까지 사라졌다).
            NoteWebView(
                html: library.pageHTML,
                assets: library.assetProvider ?? EmptyAssetProvider(),
                onOpen: handle)
        } else {
            // 쓰기 — 라이브 편집기 L1 (ADR-0005). 원문은 그대로 두고 속성만 바뀐다.
            MarkdownEditor(
                noteID: library.editorSession.uuidString,
                text: library.noteText,
                onEdit: library.noteEdited,
                insertion: library.insertion,
                onInserted: { library.insertion = nil })
        }
    }

    private func handle(_ action: NoteLinkAction) {
        switch action {
        case .note(let path):
            Task { await library.open(relativePath: path) }
        case .external(let url):
            openURL(url)
        case .attachment(let path):
            Task { await library.previewAttachment(path) }
        case .missing(let path):
            // 빈 경로만 띄우면 오류처럼 보인다 — 무엇이 없는지 말한다 (빌드 20 · 10번).
            alert = "이 링크가 가리키는 파일이 폴더에 없습니다.\n\(path)\n\n링크의 경로는 노트가 있는 폴더 기준입니다."
        }
    }

    @ToolbarContentBuilder
    private func toolbarContent(for note: NoteSummary) -> some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            // 저장 상태를 숨기지 않는다. 아무 표시가 없는 것이 가장 무섭다.
            SaveIndicator()
        }
        if !library.isReading {
            ToolbarItem(placement: .topBarTrailing) {
                // 사진첩 · 카메라 → assets/ → 커서 자리에 링크 (설계서 §2-4).
                Menu {
                    Button {
                        showsPhotoPicker = true
                    } label: {
                        Label("사진첩에서", systemImage: "photo.on.rectangle")
                    }
                    if CameraView.isAvailable {
                        Button {
                            showsCamera = true
                        } label: {
                            Label("카메라로 찍기", systemImage: "camera")
                        }
                    }
                    Divider()
                    Button {
                        showsDocumentPicker = true
                    } label: {
                        Label("문서 첨부", systemImage: "doc.badge.plus")
                    }
                } label: {
                    Label("넣기", systemImage: "photo")
                }
            }
        }
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Button {
                    library.beginRename(note)
                } label: {
                    Label("이름 바꾸기", systemImage: "pencil.line")
                }
                Button(role: .destructive) {
                    library.trashing = note
                } label: {
                    Label("지우기", systemImage: "trash")
                }
            } label: {
                Label("더 보기", systemImage: "ellipsis.circle")
            }
        }
        ToolbarItem(placement: .topBarTrailing) {
            // 위 토글: 읽기(WKWebView 완전 렌더) ↔ 쓰기(원문). 쓰기가 기본이다.
            Button {
                // 읽기로 넘기기 전에 쓴다 — 읽기 화면은 파일을 다시 렌더한다.
                if !library.isReading { Task { await library.save() } }
                library.isReading.toggle()
            } label: {
                Label(library.isReading ? "쓰기" : "읽기",
                      systemImage: library.isReading ? "pencil" : "book")
            }
            .keyboardShortcut("e", modifiers: .command)
        }
    }

}

/// 저장됐나 · 저장할 것이 남았나. 글자 하나로 늘 보인다.
private struct SaveIndicator: View {
    @EnvironmentObject private var library: LibraryModel

    var body: some View {
        if library.saveFailed {
            Label("저장 실패", systemImage: "exclamationmark.triangle.fill")
                .labelStyle(.iconOnly)
                .foregroundStyle(.red)
        } else if library.isDirty {
            Label("쓰는 중", systemImage: "pencil.circle")
                .labelStyle(.iconOnly)
                .foregroundStyle(Palette.inkFaint)
        } else if library.lastSaved != nil {
            Label("저장됨", systemImage: "checkmark.circle")
                .labelStyle(.iconOnly)
                .foregroundStyle(Palette.inkFaint)
        }
    }
}

/// 폴더가 아직 없을 때 쓰는 빈 제공자.
private struct EmptyAssetProvider: AssetProvider {
    func data(forRelativePath path: String) async -> Data? { nil }
}
