import SwiftUI
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
            if scenePhase == .active { await library.retryICloud() }
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
        Text("\(note.title) 을 폴더 안 .trash 로 옮깁니다. 파일 앱에서 되돌릴 수 있습니다.")
    }
}

/// 화면 아래 띠. 지금 무엇이 이상한지 **늘 보이게** 한다.
///
/// - 둘러보기 중: 실제 자료와 섞이지 않게 (`LESSONS_LEARNED` §5)
/// - iCloud 로 못 갔을 때: 조용히 기기 안 폴더를 쓰는 것을 숨기지 않는다 (A2)
private struct StatusBanner: View {
    @EnvironmentObject private var library: LibraryModel

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
        } else if library.isFallenBackFromICloud {
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
        } else if library.isSample {
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
                }
            } footer: {
                Label(library.kind.label, systemImage: icon(for: library.kind))
                    .font(.scaled(.caption))
                    .foregroundStyle(Palette.inkFaint)
            }
        }
        .navigationTitle("폴더")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            defer { hasAppeared = true }
            guard hasAppeared, horizontalSizeClass == .compact, library.sheet == nil else { return }
            selection = nil
        }
        .onChange(of: selection) { _, chosen in
            guard let chosen, chosen != library.selectedFolder else { return }
            library.selectedFolder = chosen
        }
        .onChange(of: library.selectedFolder) { _, folder in
            if selection != nil { selection = folder }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    library.sheet = .settings
                } label: {
                    Label("설정", systemImage: "gearshape")
                }
            }
        }
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
        Button(role: .destructive) {
            library.trashing = note
        } label: {
            Label("지우기", systemImage: "trash")
        }
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
                    Text(note.modifiedAt, format: .dateTime.year().month().day())
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

    var body: some View {
        Group {
            if let note = library.selectedNote {
                content(for: note)
                    .navigationTitle(note.title)
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar { toolbarContent(for: note) }
            } else {
                ContentUnavailableView("노트를 고르세요", systemImage: "doc.text.magnifyingglass")
            }
        }
        .background(Palette.paper)
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
                noteID: note.id,
                text: library.noteText,
                onEdit: library.noteEdited)
        }
    }

    private func handle(_ action: NoteLinkAction) {
        switch action {
        case .note(let path):
            library.open(relativePath: path)
        case .external(let url):
            openURL(url)
        case .attachment(let path):
            // QuickLook 은 2주차. 지금은 무엇을 눌렀는지라도 알려 준다.
            alert = "첨부 미리보기는 아직 없습니다.\n\(path)"
        case .missing(let path):
            alert = path
        }
    }

    @ToolbarContentBuilder
    private func toolbarContent(for note: NoteSummary) -> some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            // 저장 상태를 숨기지 않는다. 아무 표시가 없는 것이 가장 무섭다.
            SaveIndicator()
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
