import SwiftUI
import QuickLook

/// 첨부 미리보기 — PDF · 문서 · 사진 · 동영상을 QuickLook 이 그린다 (78).
/// 파일은 폴더 안 것 그대로다. 여기서 고치지 않는다.
struct AttachmentPreview: View {
    let url: URL
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            QuickLookView(url: url)
                .ignoresSafeArea()
                .navigationTitle(url.lastPathComponent)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        // **다른 앱으로 열기** (119 · T7 셋째 물음). QuickLook 자체의 공유 단추는
                        // 제 내비게이션 안에 있을 때만 나온다 — 여기서는 SwiftUI 화면에 얹혀
                        // 있어 안 보인다. 그래서 우리가 세운다. 훑어보기가 못 그리는 형식
                        // (zip 같은 것)도 이 길로 다른 앱에 넘길 수 있다.
                        ShareLink(item: url) {
                            Label("공유", systemImage: "square.and.arrow.up")
                        }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("닫기") { dismiss() }
                    }
                }
        }
    }
}

/// `QLPreviewController` 를 SwiftUI 에 얹은 것. 파일 하나만 보여 준다.
private struct QuickLookView: UIViewControllerRepresentable {
    let url: URL

    func makeCoordinator() -> Coordinator { Coordinator(url: url) }

    func makeUIViewController(context: Context) -> QLPreviewController {
        let controller = QLPreviewController()
        controller.dataSource = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: QLPreviewController, context: Context) {
        if context.coordinator.url != url {
            context.coordinator.url = url
            controller.reloadData()
        }
    }

    final class Coordinator: NSObject, QLPreviewControllerDataSource {
        var url: URL
        init(url: URL) { self.url = url }

        func numberOfPreviewItems(in controller: QLPreviewController) -> Int { 1 }

        func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> any QLPreviewItem {
            url as NSURL
        }
    }
}
