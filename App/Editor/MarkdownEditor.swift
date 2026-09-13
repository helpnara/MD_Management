import SwiftUI
import UIKit
import Core

/// 라이브 편집기 (ADR-0005 L1).
///
/// `UITextView`(TextKit 2) 하나 안에서 원문은 그대로 두고 **속성만** 바꾼다.
/// 저장은 `textStorage.string` 을 그대로 쓴다 — 매핑 버그가 생길 자리가 없다.
struct MarkdownEditor: UIViewRepresentable {

    /// 어느 노트인가. 이것이 바뀌면 원문을 통째로 갈아 끼운다.
    let noteID: String
    /// 파일에서 읽은 원문.
    let text: String
    /// 한 글자 바뀔 때마다. 자동 저장이 여기서 시작한다.
    ///
    /// **`@MainActor` 를 붙여 둔다.** `LibraryModel` 이 주 액터라 그 메서드를
    /// 그냥 넘기면 격리가 벗겨져 Swift 6 가 막는다.
    let onEdit: @MainActor (String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onEdit: onEdit) }

    func makeUIView(context: Context) -> UITextView {
        let storage = MarkdownTextStorage()
        storage.sheet = EditorStyleSheet()

        // TextKit 2 — L3 의 이미지 · 체크박스 프래그먼트가 여기에 붙는다 (ADR-0005).
        let content = NSTextContentStorage()
        content.textStorage = storage
        let layout = NSTextLayoutManager()
        content.addTextLayoutManager(layout)
        let container = NSTextContainer(size: CGSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = true
        layout.textContainer = container

        let view = UITextView(frame: .zero, textContainer: container)
        view.delegate = context.coordinator
        view.backgroundColor = .systemBackground
        view.alwaysBounceVertical = true
        view.keyboardDismissMode = .interactive
        // **곧은 따옴표를 곡선으로 바꾸지 않는다.** 마크다운에서 `"` 는 글자 그대로다.
        view.smartQuotesType = .no
        view.smartDashesType = .no
        view.smartInsertDeleteType = .no
        let gutter = Metrics.gutter
        view.textContainerInset = UIEdgeInsets(top: gutter, left: gutter,
                                               bottom: gutter * 3, right: gutter)

        // **셋 다 붙들어 둔다.** TextKit 2 에서 `NSTextContainer.textLayoutManager` 와
        // `NSTextLayoutManager.textContentManager` 는 약한 참조다. 여기서 놓으면
        // 화면이 빈 채로 뜬다 — 아무 오류도 나지 않는다.
        context.coordinator.storage = storage
        context.coordinator.content = content
        context.coordinator.layout = layout
        return view
    }

    func updateUIView(_ view: UITextView, context: Context) {
        let coordinator = context.coordinator
        // 클로저는 화면이 다시 그려질 때마다 새로 온다. 묵은 것을 들고 있으면
        // 저장이 **이전 노트로** 간다.
        coordinator.onEdit = onEdit
        coordinator.load(noteID: noteID, text: text)
        coordinator.refreshStyleIfNeeded(for: view.traitCollection)
    }

    @MainActor
    final class Coordinator: NSObject, UITextViewDelegate {
        var onEdit: @MainActor (String) -> Void
        var storage: MarkdownTextStorage?
        var content: NSTextContentStorage?
        var layout: NSTextLayoutManager?
        private var loadedNoteID: String?
        private var sizeCategory = UIApplication.shared.preferredContentSizeCategory

        init(onEdit: @escaping @MainActor (String) -> Void) {
            self.onEdit = onEdit
        }

        func load(noteID: String, text: String) {
            guard loadedNoteID != noteID, let storage else { return }
            loadedNoteID = noteID
            storage.load(text)
        }

        /// Dynamic Type 이 바뀌면 값 묶음을 새로 만들어 전체를 다시 칠한다.
        func refreshStyleIfNeeded(for traits: UITraitCollection) {
            guard traits.preferredContentSizeCategory != sizeCategory, let storage else { return }
            sizeCategory = traits.preferredContentSizeCategory
            storage.restyleAll(sheet: EditorStyleSheet())
        }

        // MARK: - UITextViewDelegate

        /// **한글 조합 중에는 속성을 건드리지 않는다** (S10).
        ///
        /// 조합 중 속성 갱신은 조합을 끊어 자음과 모음이 따로 찍힌다. 글자가
        /// 바뀌기 **전에** 켜 두고, 조합이 끝난 뒤 그 문단만 갚아 칠한다.
        /// 여기서 세운 것이 맞는지는 **실기기만 판정할 수 있다.**
        func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange,
                      replacementText text: String) -> Bool {
            storage?.isComposing = textView.markedTextRange != nil
            return true
        }

        func textViewDidChange(_ textView: UITextView) {
            let composing = textView.markedTextRange != nil
            storage?.isComposing = composing
            if !composing {
                storage?.restyleParagraph(containing: textView.selectedRange.location)
            }
            onEdit(textView.text)
        }
    }
}
