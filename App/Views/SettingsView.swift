import SwiftUI
import UniformTypeIdentifiers
import QuickLook
import Core

/// 설정 — **폴더 · 노트 · 정리 · 도움** 네 구역과 맨 아래 판 (293, 2026-11-01).
///
/// 진단은 여기 안으로 들어왔다. 청진기 아이콘을 늘 보여 주는 것보다, 설정 안에 두고 필요할 때 찾아 들어가는 편이 맞다.
/// 122(빌드 36)에서 *섞임*(쓰는 사람 · 만드는 사람)을 갈랐고, 293 에서 *양*을 줄였다 — 긴 안내는 **사용법** 한 화면으로,
/// 시험 도구 스위치는 화면에서 빼고 판을 다섯 번 누르는 것으로.
struct SettingsView: View {
    @EnvironmentObject private var library: LibraryModel
    @Environment(\.dismiss) private var dismiss
    /// 바깥 화면이 compact 인가 (아이폰). 시트 자신의 size class 는 아이패드에서도 compact 라 못 쓴다.
    @Environment(\.rootIsCompact) private var rootIsCompact
    @State private var showsTrash = false
    /// 폴더 고르기 창 (b). `fileImporter` 는 시트 위에 문서 선택 창을 띄운다.
    /// **창은 하나, 쓰임은 둘** (289) — 쓸 폴더 고르기 · 메모에서 내보낸 폴더 가져오기. `fileImporter` 를 둘 걸면 하나만 뜬다.
    @State private var pickingFolder = false
    @State private var picksNotesExport = false
    /// **`첫 줄을 파일명으로` 를 켤 때 한 번 물어본다** (메뉴 검토 4). 여는 것만으로
    /// 파일을 고치는 유일한 스위치다 — 끄는 것은 안 묻는다.
    @State private var confirmsFileNameSync = false

    var body: some View {
        NavigationStack {
            List {
                // **폴더** — 어디에 쓰나 · 무엇을 들여오나 (293, 2026-11-01 사용자 — *너무 덕지덕지 메뉴들이 붙어 있어서*).
                // 가져오기(289)는 **새 폴더를 들여오는 일**이라 여기다 — 노트 구역에서 빠지면 그 구역은 스위치만 남는다.
                //
                // **사용자가 보는 글에는 다른 앱 이름을 쓰지 않는다** (2026-09-22 사용자 — *이슈가 될만한 것은 사전에 제거하자*).
                // 남의 상표는 심사에서 걸리는 자리다. 뜻은 그대로 두고 **하는 일**로 적는다 (ADR-0002 의 임의 폴더 · 메모 앱의 내보내기).
                Section {
                    row(String(localized: "쓰는 곳"), library.kind.label)
                    row(String(localized: "폴더 이름"), library.folderName)
                    row(String(localized: "노트"), String(localized: "\(library.notes.count)개"))
                    Button {
                        picksNotesExport = false
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
                    Button {
                        picksNotesExport = true
                        pickingFolder = true
                    } label: {
                        Label("마크다운으로 내보낸 폴더 가져오기", systemImage: "square.and.arrow.down.on.square")
                    }
                } header: {
                    Text("폴더")
                } footer: {
                    // **글자 그대로 둘로 가른다** (293) — 삼항식으로 `String` 을 넘겼더니 `**…**` 가 별표 그대로 보였다
                    // (`screenshots/09-settings.png` · 219 와 같은 자리). `Text` 는 글자 그대로일 때만 굵게 그린다.
                    if library.kind == .userChosen {
                        Text("고른 폴더를 쓰고 있습니다. 돌아가기를 눌러도 파일은 지워지지 않습니다 — 앱이 보는 곳만 바뀝니다.")
                    } else {
                        Text("**이미 마크다운을 모아 둔 폴더**를 그대로 열 수 있습니다. 내보낸 폴더 가져오기는 같은 이름의 새 폴더로 들여옵니다. 자세한 것은 아래 **사용법**에 있습니다.")
                    }
                }

                // **노트** — 스위치 셋 (293: 구역 셋에 하나씩 흩어져 머리글 · 안내글이 스위치보다 많았다).
                //
                // **첫 줄을 파일명으로** 는 파일 이름을 바꾸는 유일한 스위치다 (메뉴 검토 4, 2026-09-22 사용자). 예전(62)에는 여는 것만으로
                // 본문까지 고쳤고 지난 자료 사고가 모두 거기서 났다 (빌드 20 · 30 · 32). 지금(T6 · 224)은 **앱에서 고친 노트의 이름만**
                // 첫 줄을 따라간다. 지킴은 **켤 때 한 번 묻는 창**이 한다 — 경고 머리글 구역은 293 에서 뺐다 (2026-11-01 사용자 결정 ②).
                // **끄는 것은 안 묻는다** (안전한 쪽이다).
                Section {
                    // **노트를 열 때 읽기 모드로** (124, 사용자 — 평소에는 읽기 모드로 보고 편집은 회의 뒤나 자료를 쓸 때만). 기본은 꺼짐.
                    Toggle("노트를 열 때 읽기 모드로", isOn: $library.opensInReadingMode)
                        .font(.scaled(.body))
                    // **앱을 열면 마지막 노트로** (302) · **목록 차례** (305) — 2026-11-06 사용자 브레인스토밍.
                    Toggle("앱을 열면 마지막 노트로", isOn: $library.opensLastNote)
                        .font(.scaled(.body))
                    Picker("노트 목록 차례", selection: $library.sortsByName) {
                        Text("최근 고친 순").tag(false)
                        Text("이름순").tag(true)
                    }
                    .font(.scaled(.body))
                    Toggle("첫 줄을 파일명으로", isOn: Binding(
                        get: { library.syncsFileName },
                        set: { wants in
                            if wants { confirmsFileNameSync = true }
                            else { library.syncsFileName = false }
                        }))
                        .font(.scaled(.body))
                    Toggle("공유할 때 링크된 노트도 넣기", isOn: $library.sharesLinkedNotes)
                        .font(.scaled(.body))
                } header: {
                    Text("노트")
                } footer: {
                    Text("**첫 줄을 파일명으로**는 앱에서 고친 노트의 파일 이름을 첫 줄 제목에 맞춥니다 — 파일 이름을 바꾸는 유일한 설정이라 켤 때 한 번 더 묻습니다. 공유는 첨부가 없으면 `.md` 하나, 있으면 `.zip` 하나로 보냅니다.")
                }

                // **정리** — 휴지통 · 안 쓰는 첨부 (122 에서 *노트* 였던 구역. 가져오기가 폴더로, `파일` 앱 안내가 사용법으로 가고 둘이 남았다).
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
                    // **안 쓰는 첨부** (174) — 본문에서 사진 줄을 지워도 파일은 남는다. 편집 중에는 손대지 않고, 여기서 모아 보고 고른다.
                    NavigationLink {
                        UnusedAttachmentsView().environmentObject(library)
                    } label: {
                        Label("안 쓰는 첨부", systemImage: "photo.stack")
                    }
                } header: {
                    Text("정리")
                } footer: {
                    Text("지운 노트는 폴더 안 `.trash` 에 있다가 휴지통에서 되돌립니다. **안 쓰는 첨부**는 어느 노트도 가리키지 않는 사진 · 파일입니다.")
                }

                // **도움** — 읽는 것(사용법) · 문제가 났을 때(진단) · 만드는 사람(시험 도구, 켰을 때만).
                // 시험 도구는 **누르면 파일을 만든다** — 쓰는 사람 화면에 스위치를 두지 않고, 맨 아래 판을 다섯 번 누르면 켜진다 (293 결정 ①).
                Section {
                    NavigationLink {
                        HelpView()
                    } label: {
                        Label("사용법", systemImage: "book")
                    }
                    // **시트를 갈아 끼우지 않고 밀어 넣는다.** 떠 있는 시트의 item 을 바꾸면 SwiftUI 가 닫았다 여는 사이에 화면이 튄다.
                    NavigationLink {
                        DiagnosticsView(isPushed: true).environmentObject(library)
                    } label: {
                        Label("진단", systemImage: "stethoscope")
                    }
                    if library.showsTestTools {
                        NavigationLink {
                            TestToolsView().environmentObject(library)
                        } label: {
                            Label("시험 도구", systemImage: "wrench.and.screwdriver")
                        }
                    }
                } header: {
                    Text("도움")
                }

                // **판은 맨 아래** (293, 사용자 — *진단에 들어가면 나오는 앱 정보는 설정 아래에 있는 것이 맞고*). 확인 목록 0번이 여기를 본다.
                // 다섯 번 누르면 시험 도구가 켜지고 꺼진다. 띠로 알리지 않는다 — 아이폰의 설정 시트 안 띠는 오류만 보인다(`errorsOnly`).
                // 대신 **바로 위 도움 구역에 시험 도구 줄이 생기고**, 여기 한 줄이 더 붙는다.
                Section {
                    VStack(spacing: Metrics.rowSpacing / 2) {
                        Text("느린 여백 \(Bundle.appVersion) (\(Bundle.appBuild))")
                        if library.showsTestTools {
                            Text("시험 도구를 보이고 있습니다 — 다섯 번 더 누르면 감춥니다")
                        }
                    }
                    .font(.scaled(.caption))
                    .foregroundStyle(Palette.inkFaint)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                    .onTapGesture(count: 5) { library.showsTestTools.toggle() }
                    .listRowBackground(Color.clear)
                }
            }
            .navigationTitle("설정")
            .alert("제목을 따라 파일 이름이 바뀝니다", isPresented: $confirmsFileNameSync) {
                Button("켜기") { library.syncsFileName = true }
                Button("취소", role: .cancel) { }
            } message: {
                Text("켜면 앱에서 고친 노트의 이름이 첫 줄 제목을 따라 바뀝니다. 다른 앱에서 이 노트를 가리키는 링크가 있으면 끊길 수 있습니다.")
            }
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
                    if picksNotesExport {
                        Task { await library.importNotesExport(from: url) }
                    } else {
                        Task { await library.chooseFolder(url) }
                    }
                case .failure(let error):
                    library.report(String(localized: "폴더를 고르지 못했습니다: \(error.localizedDescription)"))
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

/// **사용법** (293 — 설정 구역마다 붙어 있던 안내글 · 요령을 한 화면에 모았다. 설정은 한 줄 안내만 남겼다).
///
/// 앱에 도움말 화면이 없어 설정 칸의 설명이 그 노릇을 했다 (247). 그 설명이 두 달 동안 구역마다 3~5줄로 자라
/// 설정 화면의 반이 안내글이 됐다 (2026-11-01 사용자 — *정돈된 느낌이 들지 않아*). **앱이 실제로 하는 일만 적는다** (CLAUDE.md §3 · §6).
///
/// `파일` 앱 절은 **정직해야 한다** (122 · T11). 켜고 끄는 스위치를 만들 수 없다 — iOS 의 `설정 → 앱 → 기본 앱` 은 브라우저 · 메일 · 메시지
/// 같은 것만 다루고 **문서 종류는 목록에 없다.** 앱이 스스로를 `.md` 의 기본 앱으로 만드는 API 도 없다. 그래서 스위치 대신
/// **어디를 눌러야 하는지**를 적는다. 없는 스위치를 그려 두면 눌러도 아무 일이 없어 더 나쁘다.
struct HelpView: View {
    var body: some View {
        List {
            Section {
                step(1, String(localized: "`파일` 앱에서 `.md` 파일을 **길게 누릅니다**."))
                step(2, String(localized: "**공유** → 목록에서 **느린 여백** 을 고릅니다."))
                step(3, String(localized: "**Slow Margin 폴더 안의 파일이면 그 노트가 바로 열립니다.** 폴더 밖의 파일이면 가져올지 묻습니다."))
            } header: {
                Text("`파일` 앱에서 열기")
            } footer: {
                Text("""
                iOS 에는 **확장자마다 기본 앱을 정하는 설정이 없습니다.** `설정 → 앱 → 기본 앱` 은 브라우저 · 메일 · 메시지 같은 것만 다룹니다. 앱이 스스로를 기본으로 만드는 방법도 없습니다.

                느린 여백 은 자기가 마크다운을 다룰 수 있다고 iOS 에 알려 둡니다. 그래서 **공유** 와 **다음으로 열기** 목록에 뜹니다. `파일` 앱이 `다음으로 열기` 를 보여 준다면 거기서도 고를 수 있습니다.

                평소 쓰는 노트는 **Slow Margin 폴더 안**에 두시는 편이 낫습니다. 그 안의 파일은 앱이 그대로 고치고 저장합니다.
                """)
            }

            // **노트 잇기 안내** (247, 2026-10-13 사용자 — *사용자가 알 수 있게 도움말 정도에서만*). `>>` 는 적지 않는다 (줄 맨 앞에서는
            // 인용 표시라 목록이 안 뜬다 — 160). `>>` 는 그대로 동작한다.
            topic(String(localized: "노트 잇기"),
                  String(localized: "글 안에서 `[[` 를 치고 제목을 이어 치면 노트 목록이 뜹니다. 고르면 그 노트로 가는 링크가 들어갑니다. 읽기 화면에서 그 링크를 누르면 그 노트로 갑니다."))

            // 외장 자판 (309 · 2026-11-06 사용자 — *100프로 외장 자판*). 아이패드에서 ⌘ 를 누르고 있으면 뜨는 목록과 같다.
            topic(String(localized: "외장 자판"),
                  String(localized: "⌘N 새 노트 · ⌘⇧N 새 폴더 · ⌘F 찾기 · ⌘E 읽기와 쓰기 · ⌥⌘↑ ⌥⌘↓ 이전 · 다음 노트. 쓰기 화면에서 ⌘B 굵게 · ⌘I 기울임 · ⌘K 링크 · ⌘⇧D 날짜 · 시각 · Tab Shift+Tab ⌘] ⌘[ 들여 · 내어쓰기. ⌘ 를 누르고 있으면 쓸 수 있는 단축키 목록이 뜹니다."))

            topic(String(localized: "태그"),
                  String(localized: "글 안의 `#태그` 는 색이 붙고, 읽기 화면에서 누르면 그 태그가 든 노트를 찾습니다. 찾기 칸에 `#태그` 를 쳐도 같습니다."))

            topic(String(localized: "읽기 모드"),
                  String(localized: "위 도구 줄의 책 단추로 읽기와 편집을 오갑니다. 설정의 **노트를 열 때 읽기 모드로**를 켜면 노트를 고를 때마다 읽기 모드로 시작합니다. 새 노트를 만들 때는 그대로 편집 모드입니다."))

            // 287 — 메뉴는 고칠 글자가 있을 때만 선다 (`LibraryModel.foreignCharacters`).
            topic(String(localized: "줄바꿈 고치기"),
                  String(localized: "다른 곳에서 옮겨 온 글에 보이지 않는 줄바꿈 · 빈칸 글자가 있으면 붙여 넣을 때 저절로 고칩니다. 이미 들어온 노트는 오른쪽 위 **···** 메뉴의 **줄바꿈 고치기**로 고칩니다 — 고칠 글자가 있을 때만 보입니다. 제목과 목록이 제 모양으로 섭니다."))

            // 289 — 화면 글에는 다른 앱 이름을 쓰지 않는다 (CLAUDE.md §6).
            topic(String(localized: "마크다운으로 내보낸 폴더 가져오기"),
                  String(localized: "다른 노트 앱이 노트마다 폴더 하나(노트 + 첨부 폴더)로 내보낸 것을 설정 → 폴더에서 **같은 이름의 새 폴더**로 들여옵니다 — 노트는 한 폴더에 나란히, 사진은 그 안 `assets` 로, 링크는 새 자리에 맞춰. 압축 파일이면 `파일` 앱에서 먼저 눌러 풀어 주세요. 고른 폴더는 그대로 남습니다."))

            // T1 · 291 — 이 노트만 쓰는 첨부는 같이 간다.
            topic(String(localized: "노트 옮기기"),
                  String(localized: "노트 줄을 왼쪽으로 밀어 **이동**(아이패드는 폴더로 끌어다 놓기). 폴더 안을 가리키는 링크가 있으면 묻습니다 — **고치고 옮기기**는 이 노트만 쓰는 사진을 새 폴더로 함께 옮기고 링크를 맞춥니다. **그냥 옮기기**는 본문도 파일도 그대로 둡니다."))

            // 172 · 173 · 174 · 292.
            topic(String(localized: "휴지통 · 안 쓰는 첨부"),
                  String(localized: "지운 노트는 폴더 안 `.trash` 로 갑니다. `파일` 앱은 숨김 폴더를 보여 주지 않으므로 설정 → 정리 → **휴지통**에서 봅니다. 폴더째 지운 것은 폴더 줄로 묶여 한 번에 되돌립니다. 노트를 지우면 그 노트만 쓰던 사진도 같이 갑니다. 영구 삭제는 확인 문구를 입력해야 합니다. **안 쓰는 첨부**는 본문에서 사진 줄을 지워도 남은 파일입니다 — 모아 보고 휴지통으로 보냅니다."))

            // ADR-0002 (b) — 임의 폴더.
            topic(String(localized: "다른 폴더 고르기"),
                  String(localized: "이미 마크다운을 모아 둔 폴더를 그대로 열 수 있습니다. 점으로 시작하는 숨김 폴더는 목록에 보이지 않습니다. 고른 폴더는 다른 앱과 같이 쓰는 곳이므로 **첫 줄을 파일명으로**를 끄는 편이 안전합니다. 앱을 지워도 그 폴더는 그대로 남고, 기본 폴더로 돌아가도 파일은 지워지지 않습니다."))

            // T6 · 224 — 앱에서 고친 노트의 이름만.
            topic(String(localized: "첫 줄을 파일명으로"),
                  String(localized: "켜면 앱에서 고친 노트의 **첫 줄 `# 제목`**을 파일 이름이 따라갑니다. 제목 줄을 벗어날 때 한 번 바뀝니다. 열어 보기만 한 노트의 이름은 바꾸지 않습니다. 다른 앱에서 이 노트를 링크해 두었다면 이름이 바뀔 때 그 링크가 끊길 수 있습니다."))
        }
        .navigationTitle("사용법")
        .navigationBarTitleDisplayMode(.inline)
    }

    /// 주제 하나 — 머리글과 글 한 덩이. 글은 `**…**` · `` `…` `` 를 그린다.
    private func topic(_ title: String, _ text: String) -> some View {
        Section {
            Text(.init(text))
                .font(.scaled(.callout))
                .foregroundStyle(Palette.ink)
                .fixedSize(horizontal: false, vertical: true)
        } header: {
            Text(title)
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
                            Text("이 파일은 **Slow Margin 폴더 밖**에 있습니다.")
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
                    Text(file.text.isEmpty ? String(localized: "(빈 파일)") : String(file.text.prefix(1200)))
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
            // **지운 폴더는 폴더째** (292, 2026-11-01 사용자 — *폴더가 목록에 나와서 복구 가능하게*). 원래 폴더가 지금 없는 것끼리
            // 한 줄로 — 되돌리기 한 번에 안의 노트 · 첨부가 모두 원래 자리로. 펼치면 안의 것을 하나씩 되돌릴 수도 있다.
            if !library.trashFolders.isEmpty {
                Section {
                    ForEach(library.trashFolders) { folder in
                        folderRow(folder)
                    }
                } header: {
                    Text("지운 폴더")
                } footer: {
                    Text("폴더 줄의 **되돌리기**는 안의 노트와 첨부를 모두 원래 폴더로 돌려놓습니다. 줄을 누르면 안의 것이 보입니다.")
                }
            }
            Section {
                ForEach(looseNotes) { note in
                    row(note)
                }
            } footer: {
                if !library.trashed.isEmpty {
                    Text("**되돌리기**는 원래 있던 폴더로 돌려놓습니다. 줄을 왼쪽으로 밀면 **영구 삭제**할 수 있습니다. 영구 삭제는 되돌릴 수 없어 확인 문구를 입력해야 합니다. 노트를 영구 삭제하면 **그 노트만 쓰던 첨부**도 함께 지워집니다.")
                }
            }
            // **휴지통의 첨부도 보여 준다** (173). 예전에는 노트만 보여 줘서, 휴지통에 쌓인 사진은
            // 이 화면에도 `파일` 앱에도 안 보였다.
            if !library.trashedFiles.isEmpty {
                Section {
                    ForEach(looseFiles) { file in
                        fileRow(file)
                    }
                } header: {
                    Text("첨부 \(library.trashedFiles.count)개 · \(ByteCountFormatter.string(fromByteCount: Int64(library.trashedFiles.reduce(0) { $0 + $1.size }), countStyle: .file))")
                } footer: {
                    Text("**비우기**를 하면 첨부도 모두 지워집니다.")
                }
            }
        }
        .overlay {
            if library.trashed.isEmpty && library.trashedFiles.isEmpty {
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
                .disabled(library.trashed.isEmpty && library.trashedFiles.isEmpty)
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
    fileprivate func fileRow(_ file: TrashedFile) -> some View {
        let original = FolderStore.originalPath(ofTrashed: file.relativePath)
        return HStack(spacing: Metrics.rowSpacing) {
            AttachmentLabel(path: original, size: file.size, folderName: library.folderName)
            Spacer(minLength: Metrics.rowSpacing)
            Button("되돌리기") {
                Task { await library.restoreAttachment(file) }
            }
            .buttonStyle(.bordered)
            .font(.scaled(.callout))
        }
    }

    /// 폴더 줄에 안 든 노트 · 첨부 (292). 개수 · 비우기는 전부(`trashed` · `trashedFiles`)를 본다.
    fileprivate var looseNotes: [NoteSummary] {
        let grouped = library.groupedTrashPaths
        return library.trashed.filter { !grouped.contains($0.relativePath) }
    }

    fileprivate var looseFiles: [TrashedFile] {
        let grouped = library.groupedTrashPaths
        return library.trashedFiles.filter { !grouped.contains($0.relativePath) }
    }

    /// 지운 폴더 한 줄 (292) — 이름 · 안의 개수 · **되돌리기**. 펼치면 안의 노트 · 첨부 줄(낱개와 같은 줄).
    fileprivate func folderRow(_ folder: LibraryModel.TrashFolder) -> some View {
        DisclosureGroup {
            ForEach(folder.notes) { note in
                row(note)
            }
            ForEach(folder.files) { file in
                fileRow(file)
            }
        } label: {
            HStack(spacing: Metrics.rowSpacing) {
                VStack(alignment: .leading, spacing: Metrics.rowSpacing) {
                    Label(folder.folder, systemImage: "folder")
                        .font(.scaled(.body))
                        .foregroundStyle(Palette.ink)
                    Text("노트 \(folder.notes.count)개 · 첨부 \(folder.files.count)개")
                        .font(.scaled(.caption))
                        .foregroundStyle(Palette.inkFaint)
                }
                Spacer(minLength: Metrics.rowSpacing)
                Button("되돌리기") {
                    Task { await library.restoreTrashFolder(folder) }
                }
                .buttonStyle(.bordered)
                .font(.scaled(.callout))
            }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) {
                library.purgeText = ""
                library.purging = .folder(folder)
            } label: {
                Label("영구 삭제", systemImage: "trash.slash")
            }
        }
    }

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
            Text("휴지통의 노트 \(library.trashed.count)개와 첨부 \(library.trashedFiles.count)개를 완전히 지웁니다. 되돌릴 수 없습니다. 지우려면 \(LibraryModel.purgeConfirmation) 라고 입력하세요.")
        case .one(let note):
            Text("\(note.title) 과 그 노트만 쓰던 첨부를 완전히 지웁니다. 되돌릴 수 없습니다. 지우려면 \(LibraryModel.purgeConfirmation) 라고 입력하세요.")
        case .folder(let folder):
            Text("\(folder.folder) 폴더의 노트 \(folder.notes.count)개와 첨부를 완전히 지웁니다. 다른 노트가 쓰는 첨부는 남깁니다. 되돌릴 수 없습니다. 지우려면 \(LibraryModel.purgeConfirmation) 라고 입력하세요.")
        }
    }
}

/// 첨부 한 줄 — 이름 · 원래 폴더 · 크기. 휴지통(173)과 안 쓰는 첨부(174)가 같이 쓴다.
private struct AttachmentLabel: View {
    let path: String
    let size: Int
    let folderName: String

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: Metrics.rowSpacing) {
                Text(path.split(separator: "/").last.map(String.init) ?? path)
                    .font(.scaled(.body))
                    .foregroundStyle(Palette.ink)
                    .lineLimit(2)
                Text("\(folder) · \(ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file))")
                    .font(.scaled(.caption))
                    .foregroundStyle(Palette.inkFaint)
            }
        } icon: {
            Image(systemName: Self.isImage(path) ? "photo" : "doc")
                .foregroundStyle(Palette.inkFaint)
        }
    }

    /// `회의/assets/a.png` → `회의`. 최상위의 `assets/` 면 폴더 이름.
    private var folder: String {
        let directory = Paths.directory(of: path)
        let owner = directory.hasSuffix("assets") ? Paths.directory(of: directory) : directory
        return owner.isEmpty ? folderName : owner
    }

    private static func isImage(_ path: String) -> Bool {
        ["jpg", "jpeg", "png", "heic", "gif", "webp"].contains(Paths.fileExtension(path))
    }
}

/// **안 쓰는 첨부** (174) — 어느 노트도 가리키지 않는 `assets/` 안의 사진 · 파일.
///
/// 셈은 노트 지우기(172)와 **같은 것**이다 (`AttachmentLedger`). 의심스러우면 쓰는 것으로 본다 —
/// 파일 이름이 본문 어디에든 있으면 남기고, **아직 안 내려온 노트가 있으면 세지 않는다.**
/// 치우는 곳은 휴지통이다 — 휴지통 화면에서 되돌릴 수 있다 (CLAUDE.md §1 · 모든 삭제에 확인).
struct UnusedAttachmentsView: View {
    @EnvironmentObject private var library: LibraryModel
    @State private var confirming: [TrashedFile] = []
    @State private var previewing: URL?

    var body: some View {
        List {
            switch library.unusedAttachments {
            case .counting:
                HStack(spacing: Metrics.rowSpacing) {
                    ProgressView()
                    Text("노트를 읽어 세는 중입니다")
                        .font(.scaled(.callout))
                        .foregroundStyle(Palette.inkFaint)
                }
            case .cannotJudge:
                Text("iCloud 에서 아직 받지 않은 노트가 있어 셀 수 없습니다. 그 노트가 쓰는 첨부일 수 있습니다. 노트를 모두 받은 뒤 다시 열어 주세요.")
                    .font(.scaled(.callout))
                    .foregroundStyle(Palette.inkFaint)
            case .ready(let files):
                Section {
                    ForEach(files) { file in
                        Button {
                            previewing = library.fileURL(file.relativePath)
                        } label: {
                            AttachmentLabel(path: file.relativePath, size: file.size,
                                            folderName: library.folderName)
                        }
                        .buttonStyle(.plain)
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button {
                                confirming = [file]
                            } label: {
                                Label("휴지통으로", systemImage: "trash")
                            }
                            .tint(.red)
                        }
                    }
                } header: {
                    if !files.isEmpty {
                        Text("\(files.count)개 · \(ByteCountFormatter.string(fromByteCount: Int64(files.reduce(0) { $0 + $1.size }), countStyle: .file))")
                    }
                } footer: {
                    if !files.isEmpty {
                        Text("눌러서 미리 보고, 줄을 왼쪽으로 밀어 **휴지통으로** 옮깁니다. 파일 이름이 어느 노트에든 적혀 있으면 쓰는 것으로 보고 여기 넣지 않습니다.")
                    }
                }
            }
        }
        .overlay {
            if case .ready(let files) = library.unusedAttachments, files.isEmpty {
                ContentUnavailableView("안 쓰는 첨부가 없습니다", systemImage: "checkmark.circle",
                                       description: Text("모든 사진 · 파일을 어느 노트든 가리키고 있습니다."))
            }
        }
        .navigationTitle("안 쓰는 첨부")
        .navigationBarTitleDisplayMode(.inline)
        .task { await library.countUnusedAttachments() }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if case .ready(let files) = library.unusedAttachments, !files.isEmpty {
                    Button("모두 휴지통으로", role: .destructive) { confirming = files }
                }
            }
        }
        .confirmationDialog(confirmTitle, isPresented: confirmPresented, titleVisibility: .visible) {
            Button("휴지통으로", role: .destructive) {
                let files = confirming
                confirming = []
                Task { await library.trashUnusedAttachments(files) }
            }
            Button("취소", role: .cancel) { confirming = [] }
        } message: {
            Text("설정 → 휴지통에서 되돌릴 수 있습니다.")
        }
        .quickLookPreview($previewing)
    }

    private var confirmTitle: String {
        let first = confirming.first.map { $0.relativePath.split(separator: "/").last.map(String.init) ?? "" } ?? ""
        return confirming.count == 1
            ? String(localized: "\(first) 을 휴지통으로 옮길까요?")
            : String(localized: "첨부 \(confirming.count)개를 휴지통으로 옮길까요?")
    }

    private var confirmPresented: Binding<Bool> {
        Binding(get: { !confirming.isEmpty }, set: { if !$0 { confirming = [] } })
    }
}

