import SwiftUI
import Core

/// 설정 — 지금은 **폴더**와 **`파일` 앱에서 열기** 둘이다.
///
/// 진단은 여기 안으로 들어왔다. 청진기 아이콘을 늘 보여 주는 것보다, 설정 안에
/// 두고 필요할 때 찾아 들어가는 편이 맞다.
struct SettingsView: View {
    @EnvironmentObject private var library: LibraryModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("폴더") {
                    row("쓰는 곳", library.kind.label)
                    row("폴더 이름", library.folderName)
                    row("노트", "\(library.notes.count)개")
                }

                filesSection

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
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("닫기") { dismiss() }
                }
            }
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
