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
    /// 커서 자리에 넣을 글 (사진 링크). 넣고 나면 `onInserted` 로 알린다.
    var insertion: LibraryModel.Insertion? = nil
    var onInserted: @MainActor () -> Void = {}

    func makeCoordinator() -> Coordinator { Coordinator(onEdit: onEdit) }

    func makeUIView(context: Context) -> UITextView {
        // **TextKit 2 를 손으로 조립하지 않는다.** 빌드 7 에서 NSTextContentStorage ·
        // NSTextLayoutManager · 커스텀 NSTextStorage 를 직접 엮었다가 빈 화면이
        // 떴다 — 오류 하나 없이. 여기서는 컴파일해 볼 수 없는 조립이다.
        // 이 생성자가 같은 TextKit 2 를 만들어 주고, 칠하는 일은 대리자로 붙는다.
        let view = UITextView(usingTextLayoutManager: true)
        view.delegate = context.coordinator
        view.textStorage.delegate = context.coordinator

        view.backgroundColor = .systemBackground
        view.alwaysBounceVertical = true
        view.keyboardDismissMode = .interactive
        // **곧은 따옴표를 곡선으로 바꾸지 않는다.** 마크다운에서 `"` 는 글자 그대로다.
        view.smartQuotesType = .no
        view.smartDashesType = .no
        view.smartInsertDeleteType = .no
        // 빈 노트에 첫 글자를 칠 때 쓸 기본값. 없으면 12pt 로 찍힌다.
        view.font = .preferredFont(forTextStyle: .body)
        view.textColor = .label

        let gutter = Metrics.gutter
        view.textContainerInset = UIEdgeInsets(top: gutter, left: gutter,
                                               bottom: gutter * 3, right: gutter)

        context.coordinator.view = view
        context.coordinator.sheet = EditorStyleSheet()
        return view
    }

    func updateUIView(_ view: UITextView, context: Context) {
        let coordinator = context.coordinator
        // 클로저는 화면이 다시 그려질 때마다 새로 온다. 묵은 것을 들고 있으면
        // 저장이 **이전 노트로** 간다.
        coordinator.onEdit = onEdit
        coordinator.refreshStyleIfNeeded(for: view.traitCollection)
        coordinator.load(noteID: noteID, text: text)
        if let insertion, coordinator.insert(insertion) { onInserted() }
    }

    @MainActor
    final class Coordinator: NSObject, UITextViewDelegate, NSTextStorageDelegate {
        var onEdit: @MainActor (String) -> Void
        weak var view: UITextView?
        var sheet: EditorStyleSheet?

        private var loadedNoteID: String?
        private var loadedText = ""
        private var isStyling = false
        /// 지난번 머리말 길이. 바뀌면 그 구간을 통째로 다시 칠한다 (`MarkdownStyler.restyle`).
        private var headerLength = 0
        /// 지난번 커서 문단. 커서가 다른 문단으로 가면 **둘만** 다시 칠한다 (S11).
        private var cursorParagraph = NSRange(location: 0, length: 0)

        /// 커서 자리. 그 문단만 마커를 흐리게(L1) 두고 나머지는 숨긴다(L2).
        /// VoiceOver 후퇴는 두지 않는다 — 사용자 결정 (빌드 14 · 13번, A10).
        private var cursorHint: Int? { view?.selectedRange.location }
        /// 한글 조합 중에는 속성을 건드리지 않는다 — 조합이 끊겨 자음과 모음이
        /// 따로 찍힌다 (안정화 기준 S10).
        private var isComposing = false
        private var sizeCategory = UIApplication.shared.preferredContentSizeCategory

        init(onEdit: @escaping @MainActor (String) -> Void) {
            self.onEdit = onEdit
        }

        /// 노트를 열 때 · 파일 글이 뒤늦게 올 때.
        ///
        /// **글은 화면보다 늦게 온다.** 노트를 고르면 화면이 먼저 그려지고 파일은
        /// 그 뒤에 읽힌다. 그 사이 한 번은 빈 문자열로 그려지는데, 노트 이름만
        /// 보고 건너뛰면 **편집기가 빈 채로 남는다** — 빌드 7 스크린샷에서 잡혔다.
        func load(noteID: String, text: String) {
            guard let view else { return }

            if noteID != loadedNoteID {
                loadedNoteID = noteID
                loadedText = text
                view.text = text
                return
            }
            // 편집기와 파일이 이미 같다 (방금 저장했다).
            if view.text == text {
                loadedText = text
                return
            }
            // 글이 바뀌었다. **사용자가 손대지 않았을 때만** 갈아 끼운다 —
            // 손댄 뒤라면 그것이 최신이고, 덮으면 자료가 사라진다.
            guard view.text == loadedText else { return }
            loadedText = text
            view.text = text
        }

        private var lastInsertionID: UUID?

        /// 커서 자리에 한 줄로 넣는다. 줄 가운데면 앞뒤에 줄바꿈을 붙여 제 줄을 갖게.
        /// 같은 요청은 한 번만 넣는다 — `updateUIView` 는 여러 번 불린다.
        func insert(_ insertion: LibraryModel.Insertion) -> Bool {
            guard insertion.id != lastInsertionID, let view else { return false }
            lastInsertionID = insertion.id

            let text = view.textStorage.string as NSString
            let range = view.selectedRange
            let atLineStart = range.location == 0 || text.character(at: range.location - 1) == 0x0A
            let atLineEnd = NSMaxRange(range) >= text.length
                || text.character(at: NSMaxRange(range)) == 0x0A
            let piece = (atLineStart ? "" : "\n") + insertion.text + (atLineEnd ? "" : "\n")

            guard let target = textRange(view, range) else { return false }
            view.replace(target, withText: piece)
            view.selectedRange = NSRange(location: range.location + (piece as NSString).length, length: 0)
            onEdit(view.text)
            return true
        }

        /// Dynamic Type 이 바뀌면 값 묶음을 새로 만들어 전체를 다시 칠한다.
        func refreshStyleIfNeeded(for traits: UITraitCollection) {
            guard traits.preferredContentSizeCategory != sizeCategory else { return }
            sizeCategory = traits.preferredContentSizeCategory
            sheet = EditorStyleSheet()
            guard let storage = view?.textStorage, let sheet else { return }
            isStyling = true
            headerLength = MarkdownStyler.restyleAll(storage, with: sheet, cursor: cursorHint)
            isStyling = false
        }

        // MARK: - NSTextStorageDelegate

        /// **속성을 바꾸라고 애플이 정해 둔 자리다.** 여기서만 칠하면 되돌리기
        /// 스택이 속성 변경까지 기록하지 않는다 — 밖에서 바꾸면 `⌘Z` 가 이상해진다.
        ///
        /// `nonisolated` 로 두고 주 액터를 가정한다. 이 대리자는 언제나 주
        /// 스레드에서 불리고, 이렇게 적으면 UIKit 이 이 프로토콜에 `@MainActor` 를
        /// 붙였든 안 붙였든 컴파일된다.
        nonisolated func textStorage(_ storage: NSTextStorage,
                                     didProcessEditing editedMask: NSTextStorage.EditActions,
                                     range editedRange: NSRange,
                                     changeInLength delta: Int) {
            // 건너보내는 것은 값뿐이다. 저장소는 안에서 `view` 로 다시 집는다 —
            // `NSTextStorage` 는 `Sendable` 이 아니라 그대로 넘기면 막힌다.
            let mask = editedMask
            let edited = editedRange
            MainActor.assumeIsolated {
                guard mask.contains(.editedCharacters),
                      !isComposing, !isStyling,
                      let sheet, let storage = view?.textStorage else { return }
                isStyling = true
                // 고치는 중인 문단에 커서가 있다 — 선택값은 아직 옛것일 수 있으므로 고친 자리를 쓴다.
                let cursor = edited.location
                headerLength = MarkdownStyler.restyle(storage, touching: edited, with: sheet,
                                                      previousHeader: headerLength, cursor: cursor)
                isStyling = false
            }
        }

        // MARK: - UITextViewDelegate

        /// 글자가 바뀌기 **전에** 조합 중인지 본다. 조합 중 속성 갱신은 조합을
        /// 끊는다. 여기서 세운 것이 맞는지는 **실기기만 판정할 수 있다** (S10).
        func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange,
                      replacementText text: String) -> Bool {
            isComposing = textView.markedTextRange != nil
            // 조합 중의 줄바꿈은 건드리지 않는다 — 조합을 끊는다.
            if text == "\n", !isComposing, continueList(in: textView, at: range) {
                return false
            }
            // 빈칸은 되돌리기 묶음을 끊는다 (53).
            if text == " ", !isComposing, insertWordBreak(in: textView, at: range) {
                return false
            }
            return true
        }

        /// **되돌리기를 낱말 단위로** (53). UIKit 은 쉬지 않고 친 글을 한 묶음으로
        /// 되돌려 `가나다 라마` 가 한 번에 사라진다 (빌드 14 · 12번). 맥의 편집기처럼
        /// 빈칸에서 끊고 싶은데 `breakUndoCoalescing` 이 UIKit 에는 없다.
        ///
        /// 빈칸을 `replace(_:withText:)` 로 넣는다 — 타이핑(`insertText`)이 아닌 길이라
        /// UIKit 이 **제 이름으로 따로** 되돌리기에 올리고, 다음 글자부터 새 묶음이 된다.
        ///
        /// **텍스트 저장소를 직접 고치지 않는다.** 빌드 17 은 `textStorage.replaceCharacters`
        /// 로 넣고 되돌리기를 우리가 등록했는데, UIKit 은 제 손을 거치지 않은 변경을 보면
        /// **그 전에 쌓아 둔 되돌리기를 버린다** — 낱말 하나와 빈칸까지만 물러나고 멈췄다
        /// (빌드 17 · 11번). 편집기의 글은 언제나 UIKit 의 입력 경로로만 바꾼다.
        private func insertWordBreak(in textView: UITextView, at range: NSRange) -> Bool {
            guard let target = textRange(textView, range) else { return false }
            textView.replace(target, withText: " ")
            textView.selectedRange = NSRange(location: range.location + 1, length: 0)
            onEdit(textView.text)
            return true
        }

        /// **목록에서 줄바꿈** — 아이폰 메모처럼. 규칙은 Core 의 `ListEditing` 이 정한다.
        /// 여기서는 그 결과를 넣고 커서를 옮기기만 한다. `replace(_:withText:)` 를
        /// 쓰므로 되돌리기에도 한 번의 편집으로 남는다.
        private func continueList(in textView: UITextView, at range: NSRange) -> Bool {
            let text = textView.textStorage.string as NSString
            let paragraph = text.paragraphRange(for: NSRange(location: range.location, length: 0))
            var line = paragraph
            if line.length > 0, text.character(at: NSMaxRange(line) - 1) == 0x0A { line.length -= 1 }

            guard let action = ListEditing.returnPressed(in: text.substring(with: line)) else {
                return false
            }
            switch action {
            case .insert(let marker):
                guard let target = textRange(textView, range) else { return false }
                textView.replace(target, withText: marker)
                textView.selectedRange = NSRange(location: range.location + (marker as NSString).length, length: 0)
            case .replacePrefix(let length, let replacement):
                let prefix = NSRange(location: line.location, length: min(length, line.length))
                guard let target = textRange(textView, prefix) else { return false }
                textView.replace(target, withText: replacement)
                textView.selectedRange = NSRange(location: line.location + (replacement as NSString).length, length: 0)
            }
            onEdit(textView.text)
            return true
        }

        private func textRange(_ textView: UITextView, _ range: NSRange) -> UITextRange? {
            guard let start = textView.position(from: textView.beginningOfDocument, offset: range.location),
                  let end = textView.position(from: start, offset: range.length) else { return nil }
            return textView.textRange(from: start, to: end)
        }

        /// **커서가 다른 문단으로 갔다.** 떠난 문단은 마커를 숨기고, 온 문단은 드러낸다 (L2).
        /// 조합 중에는 건드리지 않는다 — 조합이 끊긴다 (S10).
        func textViewDidChangeSelection(_ textView: UITextView) {
            guard !isStyling, !isComposing, textView.markedTextRange == nil, let sheet else { return }
            let text = textView.textStorage.string as NSString
            guard text.length > 0 else { return }
            let location = min(textView.selectedRange.location, text.length)
            let current = text.paragraphRange(for: NSRange(location: min(location, text.length - 1), length: 0))
            guard current != cursorParagraph else { return }
            let previous = cursorParagraph
            cursorParagraph = current

            isStyling = true
            textView.textStorage.beginEditing()
            if previous.length > 0, NSMaxRange(previous) <= text.length {
                MarkdownStyler.restyle(textView.textStorage, touching: previous, with: sheet,
                                       previousHeader: headerLength, cursor: cursorHint)
            }
            headerLength = MarkdownStyler.restyle(textView.textStorage, touching: current, with: sheet,
                                                  previousHeader: headerLength, cursor: cursorHint)
            textView.textStorage.endEditing()
            isStyling = false
        }

        func textViewDidChange(_ textView: UITextView) {
            let composing = textView.markedTextRange != nil
            let wasComposing = isComposing
            isComposing = composing

            // 조합이 끝났다. 건너뛴 재칠을 여기서 갚는다.
            if wasComposing, !composing, let sheet {
                isStyling = true
                headerLength = MarkdownStyler.restyle(textView.textStorage,
                                                      touching: textView.selectedRange, with: sheet,
                                                      previousHeader: headerLength, cursor: cursorHint)
                isStyling = false
            }
            // **여기서 `loadedText` 를 갱신하지 않는다.** 갱신하면 "사용자가
            // 손대지 않았나" 가 늘 참이 되어, 뒤늦게 온 파일 글이 방금 친 것을
            // 덮는다. 파일과 편집기가 같아지는 것은 저장 뒤 `load` 가 판정한다.
            onEdit(textView.text)
        }
    }
}
