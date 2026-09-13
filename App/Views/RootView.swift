import SwiftUI
import Core

/// 아이패드는 3단, 아이폰은 같은 뷰가 스택으로 접힌다 (ADR-0006).
struct RootView: View {
    @EnvironmentObject private var library: LibraryModel
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
        .task { await library.start() }
        .task(id: library.selectedFolder) { await library.reloadNotes() }
        .task(id: library.selectedNoteID) { await library.loadSelectedText() }
        .safeAreaInset(edge: .top, spacing: 0) { SampleBanner() }
    }
}

/// 둘러보기 중에는 배너가 늘 떠 있다 — 실제 자료와 섞이지 않게 (`LESSONS_LEARNED` §5).
private struct SampleBanner: View {
    @EnvironmentObject private var library: LibraryModel

    var body: some View {
        if library.isSample {
            Text("둘러보기 자료입니다 · 실제 파일이 아닙니다")
                .font(.scaled(.footnote, weight: .semibold))
                .foregroundStyle(Palette.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(maxWidth: .infinity)
                .padding(.vertical, Metrics.rowSpacing)
                .background(Palette.paperRaised)
                .overlay(alignment: .bottom) {
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

    var body: some View {
        Group {
            if let note = library.selectedNote {
                ScrollView {
                    VStack(alignment: .leading, spacing: Metrics.blockSpacing) {
                        // 1주차: 아직 라이브 편집기가 아니다. 원문을 그대로 보여 준다.
                        // 2주차에 ADR-0005 의 L1 → L2 로 갈아 끼운다.
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
                .navigationTitle(note.title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { toolbarContent }
            } else {
                ContentUnavailableView("노트를 고르세요", systemImage: "doc.text.magnifyingglass")
            }
        }
        .background(Palette.paper)
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            // 위 토글: 읽기(WKWebView 완전 렌더) ↔ 쓰기(라이브). 쓰기가 기본이다.
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
