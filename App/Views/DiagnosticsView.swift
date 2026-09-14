import SwiftUI
import UIKit
import Core

/// 진단 — **복사해 붙일 수 있는 것**을 앱에 둔다.
///
/// 지난 앱의 교훈: 크래시 로그 · 진단 정보처럼 사용자가 복사해 보낼 수 있는 것이
/// 있으면 "동기화가 안 돼요" 를 한 바퀴에 끝낸다. 없으면 여러 바퀴를 추측으로 돈다.
///
/// 2026-09-13 에 이것이 없어서 **A2 반증의 원인을 화면으로 못 봤다** — 앱은 멀쩡히
/// 돌고 있었고 폴더만 조용히 기기 안으로 물러나 있었다.
struct DiagnosticsView: View {
    /// 설정 화면 **안에서 밀려 들어온** 것인가. 그러면 자기 `NavigationStack` 과
    /// 닫기 버튼을 두지 않는다 — 스택을 겹치면 제목 줄이 두 개가 된다.
    var isPushed = false

    @EnvironmentObject private var library: LibraryModel
    @Environment(\.dismiss) private var dismiss
    @State private var copied = false

    // 가지가 둘이라 `@ViewBuilder` 가 필요하다 — 두 가지의 타입이 다르다.
    @ViewBuilder
    var body: some View {
        if isPushed {
            content
        } else {
            NavigationStack { content }
        }
    }

    private var content: some View {
        Group {
            List {
                if library.isFallenBackFromICloud {
                    Section {
                        Label {
                            VStack(alignment: .leading, spacing: Metrics.rowSpacing) {
                                Text("iCloud 폴더를 쓰지 못하고 있습니다")
                                    .font(.scaled(.body, weight: .semibold))
                                Text("지금 쓰는 곳은 **이 기기 안**입니다. `파일` 앱의 iCloud Drive 에는 폴더가 생기지 않고, 다른 기기와도 안 맞춰집니다.")
                                    .font(.scaled(.callout))
                                    .foregroundStyle(Palette.inkFaint)
                            }
                        } icon: {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                        }
                        Button("iCloud 폴더 다시 찾기") {
                            Task { await library.retryICloud() }
                        }
                    } header: {
                        Text("문제")
                    } footer: {
                        Text("설정 앱 → 맨 위 이름 → iCloud → **iCloud Drive** 가 켜져 있는지 보세요. 켜져 있는데도 이러면 앱을 지웠다 다시 설치해 보세요.")
                    }
                }

                Section("폴더") {
                    row("쓰는 곳", library.kind.label)
                    row("iCloud 를 잡았나", library.iCloudAvailable ? "예" : "아니오")
                    row("폴더 이름", library.folderName)
                    row("노트", "\(library.notes.count)개")
                    row("하위 폴더", "\(library.folders.count)개")
                }

                Section("경로") {
                    Text(library.rootPath)
                        .font(.scaledMono(.caption))
                        .foregroundStyle(Palette.inkFaint)
                        .textSelection(.enabled)
                }

                Section("앱") {
                    row("판", "\(Bundle.appVersion) (\(Bundle.appBuild))")
                    row("번들 ID", Bundle.main.bundleIdentifier ?? "—")
                }

                if let error = library.lastError {
                    Section("마지막 오류") {
                        Text(error)
                            .font(.scaled(.callout))
                            .foregroundStyle(.red)
                    }
                }

                if !library.events.isEmpty {
                    Section {
                        ForEach(Array(library.events.prefix(20).enumerated()), id: \.offset) { _, event in
                            Text(event)
                                .font(.scaledMono(.caption))
                                .foregroundStyle(Palette.ink)
                        }
                    } header: {
                        Text("최근 일")
                    } footer: {
                        Text("충돌 · 저장 실패 · 다른 기기의 변경이 여기 쌓입니다. 빨간 띠가 떴는데 이유를 모르겠으면 이것을 복사해 보내 주세요.")
                    }
                }

                Section {
                    Button {
                        Task { await library.makeAttachmentTest() }
                    } label: {
                        Label("첨부 시험 파일 만들기", systemImage: "photo.badge.plus")
                    }
                } header: {
                    Text("첨부 시험")
                } footer: {
                    Text("`첨부 시험.md` 와 `assets` 의 사진 둘을 만들고 **읽기 모드로 엽니다.** 사진 셋이 다 보이면 첨부가 제대로 도는 것입니다. 만든 파일은 언제든 지우셔도 됩니다.")
                }

                Section {
                    Button {
                        UIPasteboard.general.string = library.diagnosticsText
                        copied = true
                    } label: {
                        Label(copied ? "복사했습니다" : "진단 정보 복사",
                              systemImage: copied ? "checkmark" : "doc.on.doc")
                    }
                } footer: {
                    Text("문제를 알릴 때 이것을 붙여 주세요. 글과 사진은 담기지 않습니다 — 폴더 종류 · 파일 수 · 판 번호뿐입니다.")
                }
            }
            .navigationTitle("진단")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if !isPushed {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("닫기") { dismiss() }
                    }
                }
            }
        }
    }

    private func row(_ name: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(name)
                .foregroundStyle(Palette.inkFaint)
            Spacer(minLength: Metrics.gutter)
            Text(value)
                .foregroundStyle(Palette.ink)
                .multilineTextAlignment(.trailing)
                .textSelection(.enabled)
        }
        .font(.scaled(.callout))
    }
}

extension Bundle {
    static var appVersion: String {
        main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
    }
    static var appBuild: String {
        main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
    }
}
