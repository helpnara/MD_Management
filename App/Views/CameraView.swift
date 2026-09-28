import SwiftUI
import UIKit

/// 카메라로 바로 찍어 노트에 넣는다. `UIImagePickerController` 를 그대로 쓴다 —
/// 사진 한 장 찍는 데 AVFoundation 을 직접 다룰 이유가 없다.
struct CameraView: UIViewControllerRepresentable {
    /// 찍은 사진의 JPEG 원본. 취소하면 안 불린다.
    let onCapture: @MainActor (Data) -> Void
    @Environment(\.dismiss) private var dismiss

    static var isAvailable: Bool {
        UIImagePickerController.isSourceTypeAvailable(.camera)
    }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}

    @MainActor
    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraView
        init(parent: CameraView) { self.parent = parent }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            // 원본 그대로 넘긴다. 줄이고 JPEG 로 바꾸는 것은 `ImageImport` 가 한 곳에서 한다.
            if let image = info[.originalImage] as? UIImage,
               let data = image.jpegData(compressionQuality: 1.0) {
                parent.onCapture(data)
            }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}
