import SwiftUI
import UIKit

/// 공유 시트 (`UIActivityViewController`) — 파일 하나를 넘긴다 (설계서 §7.6).
/// 시트 안에 얹으므로 아이패드의 앵커 문제는 시트가 대신 풀어 준다.
struct ActivityView: UIViewControllerRepresentable {
    let url: URL
    var onFinish: () -> Void = {}

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        controller.completionWithItemsHandler = { _, _, _, _ in onFinish() }
        return controller
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
