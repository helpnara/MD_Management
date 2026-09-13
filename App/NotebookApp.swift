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
                .onOpenURL { url in
                    Task { await library.open(fileURL: url) }
                }
        }
    }
}
