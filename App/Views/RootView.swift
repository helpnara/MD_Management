import SwiftUI
import Core

/// 아이패드는 3단, 아이폰은 같은 뷰가 스택으로 접힌다 (ADR-0006).
struct RootView: View {
    @EnvironmentObject private var library: LibraryModel
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
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
        }
        .task(id: library.selectedFolder) {
            library.autoSelectsFirstNote = prefersPreselectedNote
            await library.reloadNotes()
        }
        .task(id: library.selectedNoteID) { await library.loadSelectedText() }
        // **배너는 아래에 둔다.** 위에 두면 내비게이션 바를 덮어 제목과 버튼이
        // 잘린다 (빌드 2 스크린샷). 아래는 덮을 것이 없다.
        .safeAreaInset(edge: .bottom, spacing: 0) { SampleBanner() }
    }

    /// 아이패드(regular)는 상세 칸이 비면 어색하니 첫 노트를 미리 고른다.
    /// 아이폰은 목록으로 열려야 한다 — `-openFirstNote` 는 CI 가 상세를 찍을 때만.
    private var prefersPreselectedNote: Bool {
        horizontalSizeClass == .regular || library.launch.openFirstNote
    }
}

/// 둘러보기 중에는 배너가 늘 떠 있다 — 실제 자료와 섞이지 않게 (`LESSONS_LEARNED` §5).
private struct SampleBanner: View {
    @EnvironmentObject private var library: LibraryModel

    var body: some View {
        if library.isSample {
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

    var body: some View {
        List(selection: folderSelection) {
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
    }

    /// `List` 의 선택은 옵셔널이라야 한다. 최상위는 빈 문자열로 둔다.
    private var folderSelection: Binding<String?> {
        Binding(
            get: { library.selectedFolder },
            set: { library.selectedFolder = $0 ?? "" })
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
                .tag(note.id)
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
                    .toolbar { toolbarContent }
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
            NoteWebView(
                html: library.pageHTML,
                assets: library.assetProvider ?? EmptyAssetProvider(),
                onOpen: handle)
            .ignoresSafeArea(edges: .bottom)
        } else {
            // 쓰기 — 1주차는 아직 라이브 편집기가 아니다. 원문을 그대로 보여 준다.
            // 2주차에 ADR-0005 의 L1 → L2 로 갈아 끼운다.
            ScrollView {
                VStack(alignment: .leading, spacing: Metrics.blockSpacing) {
                    Text(library.noteText.isEmpty ? "(빈 파일)" : library.noteText)
                        .font(.scaledMono(.body))
                        .foregroundStyle(Palette.ink)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    footer(for: note)
                }
                .padding(.horizontal, Metrics.gutter)
                .padding(.vertical, Metrics.blockSpacing)
            }
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
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            // 위 토글: 읽기(WKWebView 완전 렌더) ↔ 쓰기(원문). 쓰기가 기본이다.
            Button {
                library.isReading.toggle()
            } label: {
                Label(library.isReading ? "쓰기" : "읽기",
                      systemImage: library.isReading ? "pencil" : "book")
            }
            .keyboardShortcut("e", modifiers: .command)
        }
    }

    private func footer(for note: NoteSummary) -> some View {
        VStack(alignment: .leading, spacing: Metrics.rowSpacing) {
            Divider()
            HStack(spacing: Metrics.gutter) {
                label("첨부", "\(library.attachmentCount)개")
                label("크기", "\(note.size)바이트")
                Spacer(minLength: 0)
            }
            if !library.missingAttachments.isEmpty {
                Text("찾을 수 없는 링크 \(library.missingAttachments.count)개")
                    .font(.scaled(.caption))
                    .foregroundStyle(.orange)
            }
            if let error = library.lastError {
                Text(error)
                    .font(.scaled(.caption))
                    .foregroundStyle(.red)
            }
        }
    }

    private func label(_ name: String, _ value: String) -> some View {
        HStack(spacing: 4) {
            Text(name).foregroundStyle(Palette.inkFaint)
            Text(value).foregroundStyle(Palette.ink)
        }
        .font(.scaled(.caption))
        .lineLimit(1)
        .fixedSize()
    }
}

/// 폴더가 아직 없을 때 쓰는 빈 제공자.
private struct EmptyAssetProvider: AssetProvider {
    func data(forRelativePath path: String) async -> Data? { nil }
}
