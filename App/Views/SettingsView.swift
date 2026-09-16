import SwiftUI
import UniformTypeIdentifiers
import Core

/// 설정 — **폴더** · **`파일` 앱에서 열기** · **휴지통** · 진단.
///
/// 진단은 여기 안으로 들어왔다. 청진기 아이콘을 늘 보여 주는 것보다, 설정 안에
/// 두고 필요할 때 찾아 들어가는 편이 맞다.
struct SettingsView: View {
    @EnvironmentObject private var library: LibraryModel
    @Environment(\.dismiss) private var dismiss
    /// 바깥 화면이 compact 인가 (아이폰). 시트 자신의 size class 는 아이패드에서도 compact 라 못 쓴다.
    @Environment(\.rootIsCompact) private var rootIsCompact
    @State private var showsTrash = false
    /// 폴더 고르기 창 (b). `fileImporter` 는 시트 위에 문서 선택 창을 띄운다.
    @State private var pickingFolder = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    row("쓰는 곳", library.kind.label)
                    row("폴더 이름", library.folderName)
                    row("노트", "\(library.notes.count)개")
                    // (b) 임의 폴더 — 옵시디언 볼트 · iCloud Drive 의 다른 폴더 (ADR-0002).
                    Button {
                        pickingFolder = true
                    } label: {
                        Label("다른 폴더 고르기", systemImage: "folder.badge.gearshape")
                    }
                    if library.kind == .userChosen {
                        Button(role: .destructive) {
                            Task { await library.returnToDefaultFolder() }
                        } label: {
                            Label("기본 iCloud 폴더로 돌아가기", systemImage: "icloud")
                        }
                    }
                } header: {
                    Text("폴더")
                } footer: {
                    Text(library.kind == .userChosen
                         ? "고른 폴더를 쓰고 있습니다. 앱을 지워도 그 폴더는 그대로 남습니다. 돌아가기를 눌러도 파일은 지워지지 않습니다 — 앱이 보는 곳만 바뀝니다."
                         : "옵시디언 볼트처럼 **이미 있는 폴더**를 열 수 있습니다. 숨김 폴더(`.obsidian` 등)는 목록에 보이지 않습니다. 고른 폴더는 다른 앱과 같이 쓰는 곳이므로, 위 **제목** 스위치를 끄는 편이 안전합니다.")
                }

                Section {
                    Toggle("첫 줄을 파일명으로", isOn: $library.syncsFileName)
                        .font(.scaled(.body))
                } header: {
                    Text("제목")
                } footer: {
                    Text("노트를 열 때 첫 줄 `# 제목` 이 파일명과 다르면 **파일명으로** 맞춥니다. 제목이 없으면 넣고, 다른 제목이면 `##` 로 한 단계 내립니다. 앱 안에서 제목을 고치면 파일명이 따라갑니다. 다른 앱과 같이 쓰는 폴더라면 끄세요 — 여는 것만으로 파일이 바뀝니다.")
                }

                Section {
                    Toggle("공유할 때 링크된 노트도 넣기", isOn: $library.sharesLinkedNotes)
                        .font(.scaled(.body))
                } header: {
                    Text("공유")
                } footer: {
                    Text("첨부가 없으면 `.md` 하나, 있으면 `.zip` 하나로 보냅니다. 이 스위치를 켜면 본문이 링크한 다른 노트도 **한 단계만** 함께 넣습니다.")
                }

                filesSection

                Section {
                    NavigationLink {
                        TrashView().environmentObject(library)
                    } label: {
                        Label {
                            HStack {
                                Text("휴지통")
                                Spacer(minLength: Metrics.rowSpacing)
                                Text("\(library.trashed.count)개")
                                    .foregroundStyle(Palette.inkFaint)
                            }
                        } icon: {
                            Image(systemName: "trash")
                        }
                    }
                } footer: {
                    Text("지운 노트는 폴더 안 `.trash` 로 옮겨집니다. `파일` 앱은 숨김 폴더를 보여 주지 않으므로 여기서 봅니다.")
                }

                Section {
                    // **시트를 갈아 끼우지 않고 밀어 넣는다.** 떠 있는 시트의
                    // item 을 바꾸면 SwiftUI 가 닫았다 여는 사이에 화면이 튄다.
                    NavigationLink {
                        DiagnosticsView(isPushed: true).environmentObject(library)
                    } label: {
                        Label("진단 정보", systemImage: "stethoscope")
                    }
                } footer: {
                    Text("무엇이 어긋났는지 복사해 보낼 수 있는 화면입니다.")
                }
            }
            .navigationTitle("설정")
            .navigationBarTitleDisplayMode(.inline)
            // CI 가 휴지통을 찍으려고 `-trash` 로 연다. 사람은 위의 링크로 들어간다.
            .navigationDestination(isPresented: $showsTrash) {
                TrashView().environmentObject(library)
            }
            .task {
                await library.reloadTrash()
                if library.launch.showTrash { showsTrash = true }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("닫기") { dismiss() }
                }
            }
            .fileImporter(isPresented: $pickingFolder, allowedContentTypes: [.folder]) { result in
                switch result {
                case .success(let url):
                    Task { await library.chooseFolder(url) }
                case .failure(let error):
                    library.report("폴더를 고르지 못했습니다: \(error.localizedDescription)")
                }
            }
        }
        // **띠는 시트 안에도 있어야 한다.** 바깥 화면의 띠는 시트 뒤에 가려져 영구
        // 삭제의 확인 문구 오류가 안 보였다 (빌드 15 · 6번). **스택에 건다** — 목록에
        // 걸었더니 밀어 넣은 휴지통 화면에는 안 나왔다 (빌드 16 · 9번).
        // **바깥 화면이 compact(아이폰)일 때만.** 아이패드는 시트가 화면을 다 가리지 않아
        // 바깥 띠가 보이므로 안에 또 두면 둘이 된다 (빌드 19 · 5번, 76). 시트 **자신의**
        // size class 는 아이패드에서도 compact 라 그것으로 가르면 또 둘이 된다 (빌드 24 · 13번, 81).
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if rootIsCompact { StatusBanner(errorsOnly: true) }
        }
    }

    /// **여기서 정직해야 한다.** 켜고 끄는 스위치를 만들 수 없다.
    ///
    /// iOS 의 `설정 → 앱 → 기본 앱` 은 브라우저 · 메일 · 메시지 같은 것만 다루고
    /// **문서 종류는 목록에 없다.** 앱이 스스로를 `.md` 의 기본 앱으로 만드는 API 도
    /// 없다. 그래서 스위치 대신 **어디를 눌러야 하는지**를 적는다. 없는 스위치를
    /// 그려 두면 눌러도 아무 일이 없어 더 나쁘다.
    private var filesSection: some View {
        Section {
            step(1, "`파일` 앱에서 `.md` 파일을 **길게 누릅니다**.")
            step(2, "**공유** → 목록에서 **느린 여백** 을 고릅니다.")
            step(3, "**느린 여백 폴더 안의 파일이면 그 노트가 바로 열립니다.** 폴더 밖의 파일이면 가져올지 묻습니다.")
        } header: {
            Text("파일 앱에서 열기")
        } footer: {
            Text("""
            iOS 에는 **확장자마다 기본 앱을 정하는 설정이 없습니다.** `설정 → 앱 → 기본 앱` 은 브라우저 · 메일 · 메시지 같은 것만 다룹니다. 앱이 스스로를 기본으로 만드는 방법도 없습니다.

            느린 여백 은 자기가 마크다운을 다룰 수 있다고 iOS 에 알려 둡니다. 그래서 **공유** 와 **다음으로 열기** 목록에 뜹니다. `파일` 앱이 `다음으로 열기` 를 보여 준다면 거기서도 고를 수 있습니다.

            평소 쓰는 노트는 **느린 여백 폴더 안**에 두시는 편이 낫습니다. 그 안의 파일은 앱이 그대로 고치고 저장합니다.
            """)
        }
    }

    private func step(_ number: Int, _ text: String) -> some View {
        Label {
            Text(.init(text))
                .font(.scaled(.callout))
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Text("\(number)")
                .font(.scaled(.caption, weight: .bold))
                .foregroundStyle(Palette.paper)
                .frame(width: Metrics.iconSide, height: Metrics.iconSide)
                .background(Circle().fill(Palette.inkFaint))
        }
    }

    private func row(_ name: String, _ value: String) -> some View {
        HStack(spacing: Metrics.gutter) {
            Text(name)
                .foregroundStyle(Palette.ink)
            Spacer(minLength: Metrics.rowSpacing)
            // 문장이 아니라 짧은 값이다. 큰 글씨에서는 줄을 바꾸게 둔다.
            Text(value)
                .foregroundStyle(Palette.inkFaint)
                .multilineTextAlignment(.trailing)
        }
        .font(.scaled(.body))
    }
}

/// 폴더 **밖**의 파일을 `파일` 앱에서 건네받았을 때.
///
/// 그 자리에서 고치게 하지 않는다 — 보안 범위 접근이 언제 끊길지 모르는 파일에
/// 자동 저장을 걸면 저장이 조용히 실패한다 (ADR-0001).
struct IncomingFileSheet: View {
    @EnvironmentObject private var library: LibraryModel
    let file: LibraryModel.IncomingFile

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Label {
                        VStack(alignment: .leading, spacing: Metrics.rowSpacing) {
                            Text(file.name)
                                .font(.scaled(.body, weight: .semibold))
                            Text("이 파일은 **느린 여백 폴더 밖**에 있습니다.")
                                .font(.scaled(.callout))
                                .foregroundStyle(Palette.inkFaint)
                        }
                    } icon: {
                        Image(systemName: "doc.badge.arrow.up")
                            .foregroundStyle(Palette.accent)
                    }
                } footer: {
                    Text("가져오면 **복사본**이 내 폴더에 생깁니다. 원본은 그대로 둡니다. 같은 이름이 있으면 뒤에 번호를 붙입니다.")
                }

                Section("미리보기") {
                    Text(file.text.isEmpty ? "(빈 파일)" : String(file.text.prefix(1200)))
                        .font(.scaledMono(.caption))
                        .foregroundStyle(Palette.ink)
                        .textSelection(.enabled)
                }
            }
            .navigationTitle("가져올까요?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("닫기") { library.sheet = nil }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("가져오기") {
                        Task { await library.importIncoming(file) }
                    }
                    .font(.scaled(.body, weight: .semibold))
                }
            }
        }
    }
}


/// 휴지통 — `.trash/` 안의 노트. **되돌리기**가 기본이고, 영구 삭제는 **타이핑
/// 확인**(`지우기` 를 그대로 입력) 뒤에만 한다 (설계서 §7.1 · 51). 가정 A14(`.trash/`
/// 가 iCloud 에서 되는가)를 이 화면이 판정한다.
struct TrashView: View {
    @EnvironmentObject private var library: LibraryModel

    var body: some View {
        List {
            Section {
                ForEach(library.trashed) { note in
                    row(note)
                }
            } footer: {
                if !library.trashed.isEmpty {
                    Text("**되돌리기**는 원래 있던 폴더로 돌려놓습니다. 줄을 왼쪽으로 밀면 **영구 삭제**할 수 있습니다. 영구 삭제는 되돌릴 수 없어 확인 문구를 입력해야 합니다.")
                }
            }
        }
        .overlay {
            if library.trashed.isEmpty {
                ContentUnavailableView("휴지통이 비었습니다", systemImage: "trash",
                                       description: Text("지운 노트가 여기에 모입니다."))
            }
        }
        .navigationTitle("휴지통")
        .navigationBarTitleDisplayMode(.inline)
        .task { await library.reloadTrash() }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("비우기", role: .destructive) {
                    library.purgeText = ""
                    library.purging = .all
                }
                .disabled(library.trashed.isEmpty)
            }
        }
        .modifier(PurgeAlert())
    }

    private func row(_ note: NoteSummary) -> some View {
        HStack(spacing: Metrics.rowSpacing) {
            VStack(alignment: .leading, spacing: Metrics.rowSpacing) {
                Text(note.title)
                    .font(.scaled(.body))
                    .foregroundStyle(Palette.ink)
                Text(note.modifiedAt, format: .dateTime.year().month().day().hour().minute())
                    .font(.scaled(.caption))
                    .foregroundStyle(Palette.inkFaint)
                // 어디서 왔는지. 다른 폴더의 같은 이름과 여기서 갈린다 (빌드 15 · 5번).
                Label(originFolder(of: note).isEmpty ? library.folderName : originFolder(of: note),
                      systemImage: "folder")
                    .font(.scaled(.caption))
                    .foregroundStyle(Palette.inkFaint)
            }
            Spacer(minLength: Metrics.rowSpacing)
            Button("되돌리기") {
                Task { await library.restore(note) }
            }
            .buttonStyle(.bordered)
            .font(.scaled(.callout))
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) {
                library.purgeText = ""
                library.purging = .one(note)
            } label: {
                Label("영구 삭제", systemImage: "trash.slash")
            }
        }
    }
}

extension TrashView {
    /// `.trash/여행/A.md` → `여행`. 최상위면 빈 문자열.
    fileprivate func originFolder(of note: NoteSummary) -> String {
        Paths.directory(of: FolderStore.originalPath(ofTrashed: note.relativePath))
    }
}

/// 영구 삭제 확인창. **되돌릴 수 없는 유일한 삭제**라 버튼 하나로 끝내지 않는다 —
/// `지우기` 를 그대로 쳐야 지운다 (설계서 §7.1). 문구가 다르면 아무것도 안 하고
/// 아래 띠로 알린다. 알림창 안의 버튼은 `.disabled` 가 믿음직하지 않아 검사는 모델이 한다.
private struct PurgeAlert: ViewModifier {
    @EnvironmentObject private var library: LibraryModel

    func body(content: Content) -> some View {
        content
            .alert("영구 삭제", isPresented: presented, presenting: library.purging,
                   actions: actions, message: message)
    }

    private var presented: Binding<Bool> {
        Binding(get: { library.purging != nil }, set: { if !$0 { library.purging = nil } })
    }

    @ViewBuilder
    private func actions(_ target: LibraryModel.Purge) -> some View {
        TextField("확인 문구", text: $library.purgeText)
        Button("영구 삭제", role: .destructive) { Task { await library.finishPurge(target) } }
        Button("취소", role: .cancel) { library.purging = nil }
    }

    @ViewBuilder
    private func message(_ target: LibraryModel.Purge) -> some View {
        switch target {
        case .all:
            Text("휴지통의 노트 \(library.trashed.count)개를 완전히 지웁니다. 되돌릴 수 없습니다. 지우려면 \(LibraryModel.purgeConfirmation) 라고 입력하세요.")
        case .one(let note):
            Text("\(note.title) 을 완전히 지웁니다. 되돌릴 수 없습니다. 지우려면 \(LibraryModel.purgeConfirmation) 라고 입력하세요.")
        }
    }
}
