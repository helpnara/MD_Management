import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// **문서 첨부의 파일 고르기 창** (325 · 2026-11-20).
///
/// 증상: 앱을 켜고 처음 열 때만 지금 노트의 폴더에서 열리고, 두 번째부터는 예전에 지운 폴더(*최근 삭제된 항목* 안)에서 열려
/// 위 폴더 · 다른 폴더로 못 나갔다. 빌드 154 에서 SwiftUI `fileImporter` 를 이 창으로 바꿔 **열 때마다 새로 만들고 시작 폴더를 매번** 정했지만 **그대로였다.**
///
/// **원인 (사용자가 그 폴더를 완전 삭제하자 갇힘이 사라짐으로 확정).** 아이폰의 파일 고르기(앱 밖 프로세스)는 두 번째부터 앱이 정한
/// 시작 폴더(`directoryURL`)를 무시하고 **스스로 기억한 마지막 자리**를 연다. 그 자리가 지운 폴더면 갇힌다. 그 기억은 iOS 가 쥐고 있어 앱이 못 지운다 —
/// 사용법에 *문서 첨부 창이 한 폴더에 갇힐 때* (복구하거나 삭제) 를 적었다.
///
/// 이 창은 그대로 둔다 — 처음 열 때 지금 노트의 폴더에서 여는 것은 맞고, `fileImporter` 와 같은 주소를 받는다. 고르기 종류는 296 그대로 **파일만**
/// (`.data` — 폴더는 *들어갈 곳*), 여러 개, 원본(`asCopy: false` — 받는 쪽 `attachDocuments` 가 파일마다 보안 범위를 연다).
struct DocumentPicker: UIViewControllerRepresentable {
    /// 창을 여는 폴더 — 지금 노트가 든 폴더. 없으면 iOS 에 맡긴다.
    let start: URL?
    /// 고른 파일들. 취소하면 안 불린다.
    let onPick: @MainActor ([URL]) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.data], asCopy: false)
        picker.allowsMultipleSelection = true
        picker.directoryURL = start
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: UIDocumentPickerViewController, context: Context) {}

    @MainActor
    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let parent: DocumentPicker
        init(parent: DocumentPicker) { self.parent = parent }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            parent.onPick(urls)
            parent.dismiss()
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            parent.dismiss()
        }
    }
}
