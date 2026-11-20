import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// **문서 첨부의 파일 고르기 창** (325 — 300 의 넷째 고침, 2026-11-20 사용자 화면 두 장).
///
/// 예전에는 SwiftUI 의 `fileImporter` + `fileDialogDefaultDirectory`(300 셋째)였다. 그런데 **앱을 켜고 처음 열 때만** 그 시작 폴더가 먹고,
/// 한 번 고르거나 취소한 뒤 **다시 열면 iOS 가 기억하는 옛 자리**(지운 폴더 — *최근 삭제된 항목* 안)에서 열려 갇혔다.
/// SwiftUI 가 고르기 창을 한 번 만들어 두고 다시 쓰면서 시작 폴더를 다시 안 거는 것으로 본다.
///
/// 그래서 창을 **열 때마다 새로 만든다** — 시트가 뜰 때마다 `makeUIViewController` 가 불리고, 거기서 `directoryURL` 을 매번 정한다.
/// 고르기 종류는 296 그대로 **파일만**(`.data` — 폴더는 *들어갈 곳*), 여러 개 고르기, 원본을 연다(`asCopy: false` — 받는 쪽 `attachDocuments` 가
/// 파일마다 보안 범위를 열고 닫는다. `fileImporter` 와 같은 주소를 받는다).
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
