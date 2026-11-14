import SwiftUI
import UIKit

/// **시스템 *찾기* 메뉴를 뺀다** (304, 2026-11-07 — 노트 안에서 찾기를 켜면서). 읽기 · 쓰기 화면에 iOS 의 찾기 막대(`UIFindInteraction`)를
/// 켜면 메뉴 막대의 시스템 *편집* 메뉴에 *찾기 ⌘F* · *선택 항목으로 찾기 ⌘E* · *다음 찾기 ⌘G* 가 저절로 선다. 우리 ⌘F(모든 노트에서 찾기 —
/// 사용자 *지금처럼*) · ⌘E(읽기와 쓰기 오가기)와 같은 글쇠라 어느 쪽이 받을지 모른다. 시스템 것을 빼고 같은 일을 *노트* 메뉴에
/// 우리 글쇠로 둔다 — 노트 안에서 찾기 ⌘⇧F · 다음 · 이전 찾은 곳 ⌘G · ⌘⇧G. 찾기 막대 자체는 그대로 뜬다.
final class AppDelegate: UIResponder, UIApplicationDelegate {
    /// **막대 제목 · 강조색** (316 · 317). SwiftUI 의 `navigationTitle` 은 글꼴을 고를 수 없어 UIKit 의 모양(appearance)으로 건다 —
    /// 화면이 서기 전, 한 번. 강조색은 SwiftUI 쪽은 `.tint`, UIKit 쪽(경고창 단추 · 문서 고르기 창 등)은 창의 `tintColor` 가 맡는다.
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        let bar = UINavigationBar.appearance()
        bar.titleTextAttributes = [.font: AppFont.serif(.headline, size: 17), .foregroundColor: Palette.inkUIColor]
        bar.largeTitleTextAttributes = [.font: AppFont.serif(.largeTitle, size: 34), .foregroundColor: Palette.inkUIColor]
        UIView.appearance(whenContainedInInstancesOf: [UIAlertController.self]).tintColor = Palette.accentUIColor
        return true
    }

    override func buildMenu(with builder: UIMenuBuilder) {
        super.buildMenu(with: builder)
        guard builder.system == .main else { return }
        builder.remove(menu: .find)
    }
}

@main
struct NotebookApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var library = LibraryModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(library)
                // 316 — 앱 전체의 강조색은 잎 초록 하나 (시트 · 설정까지 — 예전에는 노트 칸에만 걸려 있었다).
                .tint(Palette.accent)
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
                // **노트 안에서 찾기** (304) — 읽기 · 쓰기 화면의 iOS 찾기 막대. 쓰기 화면에서는 바꾸기도 된다.
                Button("노트 안에서 찾기") { library.findInNote() }
                    .keyboardShortcut("f", modifiers: [.command, .shift])
                    .disabled(library.selectedNoteID == nil)
                Button("다음 찾은 곳") { library.findAgain(forward: true) }
                    .keyboardShortcut("g", modifiers: .command)
                    .disabled(library.selectedNoteID == nil)
                Button("이전 찾은 곳") { library.findAgain(forward: false) }
                    .keyboardShortcut("g", modifiers: [.command, .shift])
                    .disabled(library.selectedNoteID == nil)
                Divider()
                // **노트 정보** (315) — 글자 · 낱말 · 문단 · 할 일 · 읽는 시간. ··· 메뉴와 같은 시트.
                Button("노트 정보") { library.showNoteInfo() }
                    .keyboardShortcut("i", modifiers: [.command, .shift])
                    .disabled(library.selectedNoteID == nil)
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
            // 이름은 **글쓰기** — *쓰기* 는 영어로 `Edit` 이라 메뉴 막대에 시스템의 `Edit` 메뉴와 같은 이름이 둘 선다 (빌드 150).
            CommandMenu("글쓰기") {
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
