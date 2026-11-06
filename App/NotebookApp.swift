import SwiftUI

@main
struct NotebookApp: App {
    @StateObject private var library = LibraryModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(library)
                // `파일` 앱에서 `.md` 를 눌렀을 때 (`CFBundleDocumentTypes`).
                // 폴더가 아직 안 섰으면 `LibraryModel` 이 붙들고 있다가 연다.
                // 앱 주소 `slowmargin://` (248 — 인앱 이벤트 바로 가기)도 여기로 온다 — 앱만 연다.
                .onOpenURL { url in
                    Task { await library.open(fileURL: url) }
                }
        }
        // **⌘ 단축키는 전부 여기** (309 · 빌드 148 · 9번, 2026-11-07 사용자 — *아무런 반응이 없어*). 아이패드의 단축키 목록 — iPadOS 18 까지는
        // ⌘ 를 누르고 있을 때 뜨는 판, **iPadOS 26 부터는 화면 맨 위의 메뉴 막대** (⌘ 길게 누르기는 없어졌다 · 빌드 149 · 6번 — 메모 앱도
        // 안 뜬다) — 는 앱의 **주 메뉴**(`UIMenuSystem.main`)로 만든다 — 화면 뒤의 숨은 단추(`keyboardShortcut`)와 편집기의
        // `keyCommands` 는 눌리긴 해도 그 목록에 안 선다. 한 자리에 두면 목록 · 동작 · 설정의 *단축키* 화면이 같은 것을 본다
        // (CLAUDE.md §1 — 같은 것을 재는 곳이 둘이면 갈린다). 편집기에는 ⌘ 가 없는 Tab · ⇧Tab · ↑↓ 만 남는다.
        // 아이폰도 같은 길로 눌린다 — 목록만 안 보일 뿐이다. 글쇠를 더하거나 바꾸면 `ShortcutsView` 도 같이 고친다.
        .commands {
            CommandMenu("노트") {
                Button("새 노트") { Task { await library.createNote() } }
                    .keyboardShortcut("n", modifiers: .command)
                Button("새 폴더") { library.beginCreateFolderHere() }
                    .keyboardShortcut("n", modifiers: [.command, .shift])
                // 찾기 칸을 어디에 열지는 화면이 정한다 (`RootView.openSearch` — 태그 찾기 301 과 같은 길).
                Button("찾기") { library.searchJumpRequestedAt = Date() }
                    .keyboardShortcut("f", modifiers: .command)
                Divider()
                // 보던 자리를 물은 뒤 바꾼다 (176). 저장도 거기서 한다.
                Button("읽기와 쓰기 오가기") { library.toggleReading() }
                    .keyboardShortcut("e", modifiers: .command)
                    .disabled(library.selectedNoteID == nil)
                // ⌘↑↓ 는 글의 처음 · 끝으로 가는 시스템 글쇠라 비워 두고 ⌥⌘↑↓ 로 (309).
                Button("이전 노트") { Task { await library.selectNeighborNote(step: -1) } }
                    .keyboardShortcut(.upArrow, modifiers: [.command, .option])
                Button("다음 노트") { Task { await library.selectNeighborNote(step: 1) } }
                    .keyboardShortcut(.downArrow, modifiers: [.command, .option])
            }
            // 쓰기 화면에서만 — 읽기 화면이나 노트가 없을 때는 흐리게 (목록에서 그렇게 보인다).
            CommandMenu("쓰기") {
                Button("굵게") { library.shortcut(.bold) }
                    .keyboardShortcut("b", modifiers: .command)
                    .disabled(!editing)
                Button("기울임") { library.shortcut(.italic) }
                    .keyboardShortcut("i", modifiers: .command)
                    .disabled(!editing)
                Button("링크") { library.shortcut(.link) }
                    .keyboardShortcut("k", modifiers: .command)
                    .disabled(!editing)
                Button("날짜 · 시각") { library.shortcut(.stamp) }
                    .keyboardShortcut("d", modifiers: [.command, .shift])
                    .disabled(!editing)
                Divider()
                // 띠 · Tab 과 같은 길 (`format(.shift)`).
                Button("들여쓰기") { library.format(.shift(deeper: true)) }
                    .keyboardShortcut("]", modifiers: .command)
                    .disabled(!editing)
                Button("내어쓰기") { library.format(.shift(deeper: false)) }
                    .keyboardShortcut("[", modifiers: .command)
                    .disabled(!editing)
            }
        }
    }

    /// 쓰기 화면인가 — 노트를 연 채 읽기가 아닐 때.
    private var editing: Bool { library.selectedNoteID != nil && !library.isReading }
}
