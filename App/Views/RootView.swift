import SwiftUI
import UIKit
import Combine
import PhotosUI
import Core

/// 아이패드는 3단, 아이폰은 같은 뷰가 스택으로 접힌다 (ADR-0006).
struct RootView: View {
    @EnvironmentObject private var library: LibraryModel
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.scenePhase) private var scenePhase
    @State private var columnVisibility = NavigationSplitViewVisibility.all

    var body: some View {
        // **안내 띠는 제 칸에 둔다** (133 손질). 예전에는 `safeAreaInset` 으로 얹었는데,
        // 그러면 띠가 화면 맨 아래를 **겹쳐 덮는다** — 편집 도구 띠를 아래에 세우자
        // 그 아래로 깔려 잘렸다 (127 · 130 에서 세 바퀴 돌았다). 세로로 쌓으면
        // 겹칠 일이 없다: 위는 화면, 아래는 띠.
        VStack(spacing: 0) {
            splitView
            StatusBanner()
        }
    }

    private var splitView: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            FolderSidebar()
        } content: {
            NoteList()
        } detail: {
            NoteDetail()
        }
        .navigationSplitViewStyle(.balanced)
        // **상세 칸에도 바깥 폭을 알려 준다** (125). 아이패드의 상세 칸은 좁아도 regular 이고,
        // 도구 줄을 아이폰에서만 줄이려면 **바깥 화면**의 폭을 봐야 한다. 예전에는 이 값을
        // 시트에만 건넸다 — 그때는 띠가 둘이 되는 것만 막으면 됐다 (빌드 24 · 13번).
        .environment(\.rootIsCompact, horizontalSizeClass == .compact)
        .tint(Palette.accent)
        .task {
            library.autoSelectsFirstNote = prefersPreselectedNote
            await library.start()
            if library.launch.attachmentTest { await library.makeAttachmentTest() }
            if library.launch.newNote { await library.createNote() }
            if let term = library.launch.searchTerm { library.searchText = term }
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
            // 뒤로 갈 때는 제목도 확정한다 — 제목 줄에 커서를 둔 채 나갈 수 있다 (89).
            library.cursorOnTitleLine = false
            Task { await library.save(settlingTitle: true) }
        }
        // **시트는 하나로 모은다.** 한 뷰에 `.sheet` 를 여러 개 걸면 마지막
        // 것만 뜬다 — 진단을 눌렀는데 설정이 뜨는 식으로 조용히 어긋난다.
        .modifier(NoteActionAlerts())
        .sheet(item: $library.sheet) { sheet in
            // **시트에 바깥 화면의 폭을 알려 준다.** 아이패드의 시트는 자기 폭이 compact 라
            // 자기 size class 만 보면 아이폰인 줄 안다 — 그래서 띠가 둘이 됐다 (빌드 24 · 13번).
            Group {
                switch sheet {
            case .settings:
                SettingsView().environmentObject(library)
            case .diagnostics:
                DiagnosticsView().environmentObject(library)
            case .incoming(let file):
                IncomingFileSheet(file: file).environmentObject(library)
            case .preview(let url):
                AttachmentPreview(url: url)
            case .share(let url):
                ActivityView(url: url) { library.sheet = nil }
                    .ignoresSafeArea()
                    .onDisappear { library.shareSheetClosed() }
            case .linkFile:
                LinkFilePicker().environmentObject(library)
            case .brokenLinks:
                BrokenLinkList().environmentObject(library)
            }
            }
            .environment(\.rootIsCompact, horizontalSizeClass == .compact)
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
            // **링크를 고칠지 먼저 묻는다** (T1). 앱이 본문에 손대는 유일한 자리다.
            .alert("링크를 고칠까요?", isPresented: movePresented, presenting: library.moveConfirm,
                   actions: moveActions, message: moveMessage)
            // 아이폰 — 줄을 밀어 `이동` 하면 폴더를 고른다.
            .sheet(item: $library.movingNote) { note in
                FolderPickerView(note: note)
                    .environmentObject(library)
            }
    }

    private var movePresented: Binding<Bool> {
        Binding(get: { library.moveConfirm != nil }, set: { if !$0 { library.moveConfirm = nil } })
    }

    @ViewBuilder
    private func moveActions(_ move: LibraryModel.Move) -> some View {
        Button("고치고 옮기기") { Task { await library.finishMove(move, rebasesLinks: true) } }
        Button("그냥 옮기기") { Task { await library.finishMove(move, rebasesLinks: false) } }
        Button("취소", role: .cancel) { library.moveConfirm = nil }
    }

    private func moveMessage(_ move: LibraryModel.Move) -> some View {
        Text("이 노트에는 폴더 안을 가리키는 링크가 \(move.links)개 있습니다. "
             + "옮기면 자리가 달라지므로 링크도 새 자리에 맞춰 고쳐야 사진과 첨부가 보입니다. "
             + "**그냥 옮기기** 를 고르면 본문은 한 글자도 안 건드립니다.")
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
                    // 최상위로도 끌어다 놓을 수 있다 (T1).
                    .dropDestination(for: String.self) { paths, _ in drop(paths, into: "") }
                ForEach(library.folders) { folder in
                    row(name: folder.name, path: folder.relativePath, count: folder.noteCount, isRoot: false)
                        .swipeActions(edge: .trailing) { folderSwipeActions(for: folder) }
                        .dropDestination(for: String.self) { paths, _ in
                            drop(paths, into: folder.relativePath)
                        }
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
    /// 끌어다 놓은 노트를 그 폴더로 (T1). 실을 수 있는 것은 **노트 경로 문자열**이다 —
    /// 남의 앱에서 온 글자는 우리 목록에 없으므로 그냥 무시된다.
    private func drop(_ paths: [String], into folder: String) -> Bool {
        let notes = paths.compactMap { path in library.notes.first { $0.relativePath == path } }
        guard let note = notes.first else { return false }
        Task { await library.beginMove(note, to: folder) }
        return true
    }

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
    @State private var searchPresented = false

    var body: some View {
        List(selection: $library.selectedNoteID) {
            if library.searchText.trimmingCharacters(in: .whitespaces).isEmpty {
                // **고정된 노트** (T10, 메모 앱처럼). 없으면 구역 자체가 안 보인다.
                if !library.pinnedNotes.isEmpty {
                    Section("고정된 노트") {
                        ForEach(library.pinnedNotes) { note in
                            row(for: note)
                                .tag(note.id)
                                .swipeActions(edge: .trailing) { swipeActions(for: note) }
                        }
                    }
                }
                Section {
                    ForEach(library.looseNotes) { note in
                        row(for: note)
                            .tag(note.id)
                            .swipeActions(edge: .trailing) { swipeActions(for: note) }
                    }
                } header: {
                    // 고정이 없을 때는 머리글도 없다 — 구역이 하나뿐이면 이름이 군더더기다.
                    if !library.pinnedNotes.isEmpty { Text("노트") }
                }
            } else {
                // 검색 결과 — 파일명 일치가 앞, 본문 일치가 뒤 (설계서 §6-E). 폴더 전체를 본다.
                ForEach(library.searchResults) { hit in
                    Button {
                        Task { await library.open(relativePath: hit.relativePath) }
                    } label: {
                        VStack(alignment: .leading, spacing: Metrics.rowSpacing) {
                            HStack(spacing: Metrics.rowSpacing) {
                                Text(hit.title)
                                    .font(.scaled(.body, weight: .medium))
                                    .foregroundStyle(Palette.ink)
                                if hit.byTitle {
                                    Image(systemName: "textformat")
                                        .foregroundStyle(Palette.inkFaint)
                                }
                            }
                            if !hit.line.isEmpty {
                                Text(hit.line)
                                    .font(.scaled(.callout))
                                    .foregroundStyle(Palette.inkFaint)
                                    .lineLimit(2)
                            }
                            let folder = Paths.directory(of: hit.relativePath)
                            if !folder.isEmpty {
                                Label(folder, systemImage: "folder")
                                    .font(.scaled(.caption))
                                    .foregroundStyle(Palette.inkFaint)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                    .alignmentGuide(.listRowSeparatorLeading) { $0[.leading] }   // 121
                }
            }
        }
        // 검색 (ADR-0003). 150ms 디바운스는 모델이 한다. `⌘F` 로 칸을 연다 (S9).
        .searchable(text: $library.searchText, isPresented: $searchPresented,
                    placement: .navigationBarDrawer(displayMode: .automatic),
                    prompt: "제목 · 본문 · tag: · path:")
        .background {
            Button("찾기") { searchPresented = true }
                .keyboardShortcut("f", modifiers: .command)
                .hidden()
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
            if !library.searchText.trimmingCharacters(in: .whitespaces).isEmpty {
                if library.searchResults.isEmpty && !library.isSearching {
                    ContentUnavailableView.search(text: library.searchText)
                }
            } else if library.notes.isEmpty && !library.isLoading {
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
        // **이동** (T1). 아이패드는 폴더로 끌어다 놓아도 된다.
        Button {
            library.movingNote = note
        } label: {
            Label("이동", systemImage: "folder")
        }
        .tint(Palette.inkFaint)
        // **고정** (T10). 고정한 차례가 곧 위에서 아래 차례다.
        Button {
            Task { await library.togglePin(note) }
        } label: {
            let isPinned = library.pinned.contains(note.relativePath)
            Label(isPinned ? "고정 해제" : "고정", systemImage: isPinned ? "pin.slash" : "pin")
        }
        .tint(Palette.accent)
    }

    private func row(for note: NoteSummary) -> some View {
                // 아이패드에서 폴더로 끌어다 놓기 (T1). 싣는 것은 경로 하나다.
                VStack(alignment: .leading, spacing: Metrics.rowSpacing) {
                    HStack(spacing: Metrics.rowSpacing) {
                        Text(note.title)
                            .font(.scaled(.body, weight: .medium))
                            .foregroundStyle(Palette.ink)
                        if library.pinned.contains(note.relativePath) {
                            // 고정된 줄 (T10). 고정 구역 밖(검색 결과)에서도 알아볼 수 있게.
                            Image(systemName: "pin.fill")
                                .font(.scaled(.caption))
                                .foregroundStyle(Palette.inkFaint)
                        }
                        if !note.isDownloaded {
                            // iCloud 에 있지만 아직 안 내려온 파일 (설계서 §7.1).
                            // **글자를 함께 둔다** — 아이콘만으로는 눈에 안 띈다. 아이폰은 상세가
                            // 밀려 올라온 뒤에야 도는 표시가 보이므로, 목록에 선 채로 알아야 한다 (90).
                            Label("받는 중", systemImage: "icloud.and.arrow.down")
                                .font(.scaled(.caption))
                                .foregroundStyle(Palette.inkFaint)
                        }
                    }
                    // 첫 줄 미리보기 — **색인에서만** (설계서 §7.5). 색인 전이면 없다.
                    if !note.preview.isEmpty {
                        Text(note.preview)
                            .font(.scaled(.callout))
                            .foregroundStyle(Palette.inkFaint)
                            .lineLimit(1)
                    }
                    // 날짜만으로는 오늘 고친 여러 노트가 안 갈린다 — 시각까지 (50).
                    Text(note.modifiedAt, format: .dateTime.year().month().day().hour().minute())
                        .font(.scaled(.caption))
                        .foregroundStyle(Palette.inkFaint)
                }
                .padding(.vertical, 2)
                // **구분선을 줄 맨 앞에 맞춘다** (121, 사용자 첨부 — 줄이 끊어져 보였다).
                // SwiftUI 는 줄 안의 어느 요소를 기준으로 구분선을 들여쓸지 스스로 고르는데,
                // `받는 중` 딱지가 붙은 줄에서는 **그 딱지 앞**을 골라 구분선이 화면 가운데서
                // 시작했다. 딱지가 없는 줄은 맨 앞에서 시작하니 줄마다 길이가 달랐다.
                .alignmentGuide(.listRowSeparatorLeading) { $0[.leading] }
                // **끌어서 폴더로** (T1). 싣는 것은 경로 하나 — 폴더 줄이 그것을 받는다.
                .draggable(note.relativePath)
    }
}

/// **어느 폴더로 옮길까** (T1). 아이폰에는 끌어다 놓을 자리가 없어 목록으로 고른다.
private struct FolderPickerView: View {
    let note: NoteSummary
    @EnvironmentObject private var library: LibraryModel
    @Environment(\.dismiss) private var dismiss

    private var current: String { Paths.directory(of: note.relativePath) }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    row(name: library.folderName, path: "")
                    ForEach(library.folders) { folder in
                        row(name: folder.name, path: folder.relativePath)
                    }
                } footer: {
                    Text("**\(note.title)** 을 옮깁니다. 지금 있는 폴더는 고를 수 없습니다.")
                        .font(.scaled(.caption))
                }
            }
            .navigationTitle("어느 폴더로")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("취소") { library.movingNote = nil }
                }
            }
        }
    }

    @ViewBuilder
    private func row(name: String, path: String) -> some View {
        Button {
            Task { await library.beginMove(note, to: path) }
        } label: {
            Label {
                Text(name).font(.scaled(.body))
            } icon: {
                Image(systemName: path.isEmpty ? "tray" : "folder")
            }
            .foregroundStyle(path == current ? Palette.inkFaint : Palette.ink)
        }
        .disabled(path == current)
    }
}

private struct NoteDetail: View {
    @EnvironmentObject private var library: LibraryModel
    @Environment(\.openURL) private var openURL
    /// 아이폰인가 (125). **바깥 화면의 폭**을 본다 — 아이패드의 상세 칸은 좁아도 regular 다.
    @Environment(\.rootIsCompact) private var rootIsCompact
    /// **키보드가 지금 떠 있나** (126). 초점만 보면 안 된다 — 글을 아래로 끌어 키보드를
    /// 내리면(`keyboardDismissMode = .interactive`) 편집기는 **초점을 그대로 쥐고 있어서**
    /// `키보드 내리기` 단추가 키보드도 없이 남았다 (사용자 · 빌드 38 · 1번).
    @State private var keyboardIsUp = false
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
                    // **어디서 온 노트인가** (120 · T7 의 값). 링크를 따라오면 목록에 없는
                    // 노트가 상세 칸에 뜰 수 있다 — 목록은 `assets/` 를 안 보여 주기 때문이다.
                    // 그때 한 줄로 어느 폴더의 파일인지 알린다.
                    .safeAreaInset(edge: .top, spacing: 0) { linkedOrigin }
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
        // **키보드가 떠 있나** (126). UIKit 이 알려 주는 것을 그대로 받는다 — 끌어서 내린
        // 키보드도 여기서는 내려간 것으로 잡힌다. 초점(`editorHasFocus`)만으로는 못 잡는다.
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
            keyboardIsUp = true
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardDidHideNotification)) { _ in
            keyboardIsUp = false
        }
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
                library.report("문서를 고르지 못했습니다: \(error.localizedDescription)")
            }
        }
        .fullScreenCover(isPresented: $showsCamera) {
            CameraView { data in Task { await library.insertPhoto(data) } }
                .ignoresSafeArea()
        }
        // **조용히 빠뜨리지 않는다** (설계서 §7.6-4). 무엇이 없는지 보여 주고 고르게 한다.
        .alert("찾을 수 없는 첨부가 있습니다", isPresented: Binding(
            get: { library.sharePrompt != nil },
            set: { if !$0 { library.sharePrompt = nil } }),
            presenting: library.sharePrompt) { prompt in
            Button("그래도 보내기") { library.shareAnyway(prompt.package) }
            Button("취소", role: .cancel) { library.cancelShare(prompt.package) }
        } message: { prompt in
            Text("\(prompt.package.missing.count)개를 찾을 수 없어 빼고 보냅니다.\n\n"
                 + prompt.package.missing.prefix(5).joined(separator: "\n"))
        }
        .alert("찾을 수 없습니다", isPresented: Binding(
            get: { alert != nil },
            set: { if !$0 { alert = nil } })) {
            Button("확인", role: .cancel) { alert = nil }
        } message: {
            Text(alert ?? "")
        }
    }

    /// **지금 목록에 없는 노트**를 보고 있을 때의 출처 한 줄 (120 · 문구는 123).
    /// 링크를 따라왔거나 **검색으로 다른 폴더의 노트를 골랐을 때**다.
    /// 목록에 있는 노트면 `linkedNote` 가 비어 있어 아무것도 안 그린다.
    @ViewBuilder
    private var linkedOrigin: some View {
        if let linked = library.linkedNote {
            // **문구는 일어난 일이 아니라 지금 상태를 말한다** (123). 이 줄은 링크뿐 아니라
            // **검색으로 다른 폴더의 노트를 열었을 때도** 뜬다 — 오히려 그쪽이 흔하다.
            // 링크를 따라왔다고 하면 검색으로 온 사람에게는 틀린 말이 된다.
            let folder = Paths.directory(of: linked.relativePath)
            HStack(spacing: Metrics.rowSpacing) {
                Image(systemName: "folder")
                Text("지금 목록에 없는 노트입니다 — **\(folder.isEmpty ? library.folderName : folder)** 의 파일")
                Spacer(minLength: 0)
            }
            .font(.scaled(.caption))
            .foregroundStyle(Palette.inkFaint)
            .lineLimit(1)
            .padding(.horizontal, Metrics.gutter)
            .padding(.vertical, Metrics.rowSpacing)
            .frame(maxWidth: .infinity)
            .background(Palette.paperRaised)
        }
    }

    @ViewBuilder
    private func content(for note: NoteSummary) -> some View {
        if library.noteIsDownloading {
            // **화면이 가만히 있으면 이상하다** (사용자). iCloud 가 이름을 먼저 주고 내용을
            // 나중에 줄 때, 그 사이를 이 표시가 채운다. 다 오면 저절로 열린다 (86).
            VStack(spacing: Metrics.gutter) {
                ProgressView()
                Text("iCloud 에서 받는 중입니다")
                    .font(.scaled(.callout))
                    .foregroundStyle(Palette.inkFaint)
                Text(note.title)
                    .font(.scaled(.caption))
                    .foregroundStyle(Palette.inkFaint)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if library.isReading {
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
            //
            // **세로로 쌓는다** — 편집기가 남은 높이를 갖고, 아래 두 띠는 제 높이만 갖는다.
            // 예전에는 `safeAreaInset(edge: .bottom)` 으로 얹었는데 **띠가 아래로 잘렸다**
            // (시뮬레이터 스크린샷 · 127). 키보드가 올라오면 SwiftUI 가 이 쌓기 전체를
            // 밀어 올리므로 띠는 그대로 키보드 위에 선다 — **키보드 툴바를 쓰지 않는다**
            // (CLAUDE.md §1).
            VStack(spacing: 0) {
                MarkdownEditor(
                    noteID: library.editorSession.uuidString,
                    text: library.noteText,
                    onEdit: library.noteEdited,
                    insertion: library.insertion,
                    onInserted: { library.insertion = nil },
                    // **선언 순서가 곧 인자 순서다** (`MarkdownEditor` 의 메모와 같은 자리).
                    format: library.formatRequest,
                    onFormatted: { library.formatRequest = nil },
                    onTitleLineChanged: { library.cursorOnTitleLine = $0 },
                    onFocusChanged: { library.editorHasFocus = $0 },
                    onImageLineChanged: library.cursorImageLineChanged,
                    onActiveChanged: { library.activeFormats = $0 },
                    onLinkQueryChanged: library.linkQueryChanged,
                    onPasteLinks: library.repairPastedLinks)
                // **커서가 사진 줄에 있으면 아래에 작게 띄운다** (ADR-0005 L3 후퇴판).
                cursorImageBar
                // **`>>` · `[[` 를 치면 노트 목록이 여기 뜬다** (147).
                LinkPickerBar()
                // **도구 띠는 상세 칸 안에 선다** (130, 사용자 — 아이패드에서 화면 폭
                // 전체를 가로질렀다). 아이폰도 같은 길이다 — 화면이 곧 상세 칸이다.
                FormatBar()
            }
        }
    }

    /// 커서가 사진 줄에 있을 때만 서는 띠 (117 · ADR-0005 L3 후퇴판).
    @ViewBuilder
    private var cursorImageBar: some View {
        Group {
                if let found = library.cursorImage, let image = UIImage(data: found.image) {
                    Button {
                        Task { await library.previewAttachment(found.path) }
                    } label: {
                        HStack(spacing: Metrics.rowSpacing) {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFill()
                                .frame(width: Metrics.scaledLength(44), height: Metrics.scaledLength(44))
                                .clipShape(RoundedRectangle(cornerRadius: Metrics.scaledLength(6)))
                            Text(found.path.split(separator: "/").last.map(String.init) ?? found.path)
                                .font(.scaled(.caption))
                                .foregroundStyle(Palette.inkFaint)
                                .lineLimit(1)
                            Spacer(minLength: 0)
                            Image(systemName: "arrow.up.left.and.arrow.down.right")
                                .font(.scaled(.caption))
                                .foregroundStyle(Palette.inkFaint)
                        }
                        .padding(.horizontal, Metrics.gutter)
                        .padding(.vertical, Metrics.rowSpacing)
                    }
                    .buttonStyle(.plain)
                    .background(Palette.paperRaised)
                }
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

    /// 넣기 — 사진첩 · 카메라 · 문서 (설계서 §2-4). 아이패드는 제 단추로, **아이폰은
    /// `…` 안에** 선다 (125).
    @ViewBuilder
    private var insertItems: some View {
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
        Button {
            showsDocumentPicker = true
        } label: {
            Label("문서 첨부", systemImage: "doc.badge.plus")
        }
        // **이미 있는 파일은 사본을 만들지 않는다** (145). 제자리에 두고 링크만 넣는다 —
        // 사본이 늘면 내용이 갈라지고 어느 쪽이 진짜인지 아무도 모른다 (2026-09-18 사용자).
        Button {
            library.startLinkingExistingFile()
        } label: {
            Label("이미 있는 파일 연결", systemImage: "link")
        }
    }

    @ToolbarContentBuilder
    private func toolbarContent(for note: NoteSummary) -> some ToolbarContent {
        // **아이폰에서 늘 서 있는 것은 둘뿐이다** — `읽기 ↔ 쓰기` 와 `…` (125, 사용자 —
        // 단추가 제목을 밀어냈다). 나머지는 `…` 안으로 들어가거나, **쉬는 상태가 아닐 때만**
        // 나온다. 아이패드는 3단이라 위가 넓으므로 지금 그대로 둔다.
        //
        // **저장 상태를 아주 숨기지는 않는다** (설계서 §14 — 아무 표시가 없는 것이 가장
        // 무섭다). 아이폰에서는 **쉬는 상태(`저장됨`)일 때만** 접는다. 쓰는 중이면 연필이,
        // 실패하면 빨간 삼각형이 그대로 뜬다 — 연필이 사라지는 것이 곧 저장됐다는 말이다.
        if !rootIsCompact || library.isDirty || library.saveFailed {
            ToolbarItem(placement: .topBarTrailing) {
                SaveIndicator()
            }
        }
        if !library.linkTrail.isEmpty {
            ToolbarItem(placement: .topBarLeading) {
                // **왔던 노트로** (T7). 시스템 뒤로는 그대로 목록으로 간다 — 둘은 다른 길이다.
                Button {
                    Task { await library.goBackAlongLink() }
                } label: {
                    Label("왔던 노트", systemImage: "arrow.uturn.backward")
                }
            }
        }
        if !library.isReading, library.editorHasFocus, keyboardIsUp {
            ToolbarItem(placement: .topBarTrailing) {
                // **키보드를 내리는 길** (98). 아이폰에는 `완료` 자리가 없어 한번 커서가
                // 붙으면 키보드를 못 치웠다 — 그러면 편집이 끝나는 자리(92)에도 못 닿는다.
                // **키보드 위에 도구를 달지 않는다** (CLAUDE.md) — 위 도구 줄에 세운다.
                Button {
                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder),
                                                    to: nil, from: nil, for: nil)
                } label: {
                    Label("키보드 내리기", systemImage: "keyboard.chevron.compact.down")
                }
            }
        }
        if !library.isReading, !rootIsCompact {
            ToolbarItem(placement: .topBarTrailing) {
                // 사진첩 · 카메라 → assets/ → 커서 자리에 링크 (설계서 §2-4).
                Menu {
                    insertItems
                } label: {
                    Label("넣기", systemImage: "photo")
                }
            }
        }
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                // 아이폰에서는 넣기가 여기 산다 (125). 편집 모드일 때만이다 —
                // 읽기 모드에는 커서가 없어 넣을 자리가 없다.
                if rootIsCompact, !library.isReading {
                    Section {
                        insertItems
                    } header: {
                        Text("넣기")
                    }
                }
                // **안 열리는 링크를 한 번에 모아 본다** (146). 읽기 모드의 네모는 그
                // 자리까지 내려가야 보인다 — 긴 노트에서는 있는 줄도 모른다.
                // **넣기가 아니라 살펴보기다** — 읽기 모드에서도 쓸 수 있어야 한다.
                Button {
                    library.showBrokenLinks()
                } label: {
                    Label("안 열리는 링크 찾기", systemImage: "link.badge.exclamationmark")
                }
                Button {
                    library.beginRename(note)
                } label: {
                    Label("이름 바꾸기", systemImage: "pencil.line")
                }
                Button {
                    Task { await library.share(note) }
                } label: {
                    Label("공유", systemImage: "square.and.arrow.up")
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

/// **편집 도구 띠** (127 · T13 1차, 2026-09-18 사용자 — 워드의 도구 띠처럼).
///
/// **여기 있는 것은 마크다운 표준 안쪽뿐이다** — 굵게 · 기울임 · 취소선 · 인용 · 표 ·
/// 들여 · 내어쓰기. 글자색 · 밑줄 · 형광펜은 마크다운에 없어서 넣지 않았다 (로드맵 T13 검토):
/// 넣으면 **파일에 이 앱만 아는 글자를 심게 되고**, 그러면 다른 앱에서 그대로 드러난다.
///
/// 자리는 **편집기 아래**다. 키보드가 올라오면 `safeAreaInset` 이 그 위로 밀어 올리므로
/// 엄지가 닿는 자리에 선다 — **키보드 툴바(`placement: .keyboard`)는 쓰지 않는다**
/// (CLAUDE.md §1). 좁으면 가로로 민다.
/// **타이핑으로 노트 연결하기 — 고를 목록** (147, 2026-09-18 사용자 — 아이폰 메모처럼).
///
/// `>>회의` 라고 치면 제목에 `회의` 가 든 노트가 여기 뜬다. 고르면 그 자리에 링크가 들어간다.
///
/// **키보드 툴바를 쓰지 않는다** (CLAUDE.md §1). 편집 도구 띠와 같은 자리에, 상세 칸 안에
/// 세로로 쌓아 그린다 — 겹쳐 덮다가 세 바퀴를 돈 적이 있다 (130).
private struct LinkPickerBar: View {
    @EnvironmentObject private var library: LibraryModel

    var body: some View {
        if let query = library.linkQuery, !query.text.trimmingCharacters(in: .whitespaces).isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Metrics.rowSpacing) {
                    ForEach(library.linkCandidates) { hit in
                        Button { library.pickLink(hit) } label: {
                            Text(hit.title)
                                .font(Font.scaled(.body))
                                .lineLimit(1)
                                .padding(.horizontal, Metrics.rowSpacing)
                                .padding(.vertical, Metrics.rowSpacing / 2)
                                .background(Palette.paper)
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                    // **없으면 만든다** (147, 사용자 — 애플 메모처럼). 지금 노트와 같은 폴더에.
                    Button { library.createNoteAndLink(named: query.text) } label: {
                        Label(query.text + " — 새 노트", systemImage: "plus")
                            .font(Font.scaled(.body))
                            .lineLimit(1)
                            .padding(.horizontal, Metrics.rowSpacing)
                            .padding(.vertical, Metrics.rowSpacing / 2)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, Metrics.gutter)
                .padding(.vertical, Metrics.rowSpacing)
            }
            // 도구 띠와 같은 까닭으로 세로는 한 줄만 (빌드 40 에서 잘렸던 자리).
            .fixedSize(horizontal: false, vertical: true)
            .background(Palette.paperRaised)
            .overlay(alignment: .top) {
                Rectangle().fill(Palette.rule).frame(height: 0.5)
            }
        }
    }
}

/// **이미 있는 파일 연결하기** (145, 사용자 제안).
///
/// 금고 안의 노트와 첨부를 보여 주고, 고르면 **지금 노트 기준 상대 경로**로 링크를 넣는다.
/// **파일은 제자리에 그대로 둔다** — 사본을 만들면 내용이 갈라져 어느 쪽이 진짜인지
/// 아무도 모르게 된다 (2026-09-18 사용자).
///
/// 타이핑으로 부르는 `>>` · `[[` 와 **속이 같다** (147) — 넣는 부분은 `NoteLinking.link`
/// 하나뿐이고 입구만 둘이다.
private struct LinkFilePicker: View {
    @EnvironmentObject private var library: LibraryModel
    @State private var filter = ""

    var body: some View {
        NavigationStack {
            Group {
                if library.isLoadingLinkableFiles {
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if shown.isEmpty {
                    ContentUnavailableView("찾는 파일이 없습니다", systemImage: "doc.questionmark",
                                           description: Text("이름의 일부를 적어 보세요."))
                } else {
                    List(shown) { file in
                        Button {
                            library.linkExistingFile(file)
                        } label: {
                            VStack(alignment: .leading, spacing: Metrics.rowSpacing / 3) {
                                Text(file.name)
                                    .font(Font.scaled(.body))
                                    .foregroundStyle(Palette.ink)
                                if !file.folder.isEmpty {
                                    Text(file.folder)
                                        .font(Font.scaled(.caption))
                                        .foregroundStyle(Palette.inkFaint)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .navigationTitle("이미 있는 파일 연결")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $filter, prompt: "파일 이름")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("닫기") { library.sheet = nil }
                }
            }
        }
    }

    /// 이름이든 폴더든 적은 말이 들어 있으면 보여 준다.
    private var shown: [LinkableFile] {
        let needle = filter.trimmingCharacters(in: .whitespaces)
        guard !needle.isEmpty else { return library.linkableFiles }
        return library.linkableFiles.filter {
            $0.relativePath.localizedCaseInsensitiveContains(needle)
        }
    }
}

/// **안 열리는 링크 보기** (146, 사용자 제안).
///
/// 이 노트에서 가리키는 곳에 파일이 없는 링크를 **몇째 줄인지와 함께** 모아 준다.
///
/// **고치지 않는다. 보여 주기만 한다.** 앱이 본문을 고치는 자리는 둘뿐이다 — 노트를 옮길
/// 때와 붙여넣을 때, 둘 다 사람이 시킨 그 순간이고 몇 개를 고칠지 먼저 알린다.
/// 여기서 몰래 고치기 시작하면 셋째 자리가 생긴다.
private struct BrokenLinkList: View {
    @EnvironmentObject private var library: LibraryModel

    var body: some View {
        NavigationStack {
            Group {
                if library.brokenLinks.isEmpty {
                    ContentUnavailableView("안 열리는 링크가 없습니다", systemImage: "checkmark.circle",
                                           description: Text("이 노트의 링크가 모두 제 파일을 가리킵니다."))
                } else {
                    List(Array(library.brokenLinks.enumerated()), id: \.offset) { _, broken in
                        VStack(alignment: .leading, spacing: Metrics.rowSpacing / 3) {
                            Text("\(broken.line)째 줄")
                                .font(Font.scaled(.caption))
                                .foregroundStyle(Palette.inkFaint)
                            Text(broken.text)
                                .font(Font.scaled(.body))
                                .foregroundStyle(Palette.ink)
                                .lineLimit(2)
                            Text(broken.resolved.isEmpty
                                 ? "폴더 밖을 가리킵니다" : broken.resolved)
                                .font(Font.scaled(.caption))
                                .foregroundStyle(Palette.inkFaint)
                        }
                        .padding(.vertical, Metrics.rowSpacing / 3)
                    }
                }
            }
            .navigationTitle(library.brokenLinks.isEmpty
                             ? "링크 살펴보기" : "안 열리는 링크 \(library.brokenLinks.count)개")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("닫기") { library.sheet = nil }
                }
            }
        }
    }
}

private struct FormatBar: View {
    /// **모델을 여기서 바로 본다.** 클로저로 넘기면 주 액터 격리가 벗겨져 Swift 6 가
    /// 막는다 — 이 화면의 다른 단추들과 같은 꼴로 둔다.
    @EnvironmentObject private var library: LibraryModel

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Metrics.rowSpacing) {
                button("굵게", "bold", .wrap(.bold), on: library.activeFormats.bold)
                button("기울임", "italic", .wrap(.italic), on: library.activeFormats.italic)
                button("취소선", "strikethrough", .wrap(.strikethrough),
                       on: library.activeFormats.strikethrough)
                rule
                button("인용", "text.quote", .quote, on: library.activeFormats.quote)
                button("표 넣기", "tablecells", .table)
                rule
                button("내어쓰기", "decrease.indent", .shift(deeper: false))
                button("들여쓰기", "increase.indent", .shift(deeper: true))
            }
            .padding(.horizontal, Metrics.gutter)
            .padding(.vertical, Metrics.rowSpacing)
        }
        // **세로로는 딱 한 줄만 차지한다.** 가로 스크롤은 세로로도 남는 공간을 다 먹으려
        // 해서, 그냥 두면 띠 높이가 제멋대로 잡히고 **아래가 잘린다** (시뮬레이터
        // 스크린샷에서 잡혔다 — 아이콘 윗부분만 보였다).
        .fixedSize(horizontal: false, vertical: true)
        .background(Palette.paperRaised)
        .overlay(alignment: .top) {
            Rectangle().fill(Palette.rule).frame(height: 0.5)
        }
    }

    private var rule: some View {
        Rectangle()
            .fill(Palette.rule)
            .frame(width: 0.5, height: Metrics.scaledLength(20))
    }

    /// 글자는 안 보이고 **아이콘만** 선다 — 띠가 한 줄을 넘지 않게. 이름은 보이스오버와
    /// 길게 누르기가 읽는다.
    ///
    /// **걸려 있으면 눌린 모습**이다 (128) — 파란 칸에 흰 글자. 색만으로 가르지 않으려고
    /// 보이스오버에는 `켜짐` 을 함께 읽힌다 (색을 못 가리는 사람도 있다).
    private func button(_ name: String, _ symbol: String,
                        _ kind: LibraryModel.FormatRequest.Kind,
                        on isOn: Bool = false) -> some View {
        Button {
            library.format(kind)
        } label: {
            Label(name, systemImage: symbol)
                .labelStyle(.iconOnly)
                .font(.scaled(.body))
                .frame(minWidth: Metrics.scaledLength(40),
                       minHeight: Metrics.scaledLength(34))
                .foregroundStyle(isOn ? Palette.paper : Palette.accent)
                .background {
                    RoundedRectangle(cornerRadius: Metrics.scaledLength(7))
                        .fill(isOn ? Palette.accent : .clear)
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isOn ? "\(name) 켜짐" : name)
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

/// 바깥(루트) 화면이 compact 인가 — 시트가 바깥 띠를 가리는지 알려면 **시트 자신의** size class
/// 가 아니라 이것을 봐야 한다. 아이패드의 시트는 자기 폭이 compact 라 헷갈린다 (빌드 24 · 13번).
private struct RootIsCompactKey: EnvironmentKey {
    static let defaultValue = true
}

extension EnvironmentValues {
    var rootIsCompact: Bool {
        get { self[RootIsCompactKey.self] }
        set { self[RootIsCompactKey.self] = newValue }
    }
}

