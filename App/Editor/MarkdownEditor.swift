import SwiftUI
import UIKit
import Core

/// 하드웨어 키보드의 **탭 · 시프트 탭**을 받으려고 둔 껍데기 (빌드 29 · 1번).
///
/// `UITextView` 는 탭을 제 입력으로 쓰지 않고 다음 칸으로 넘긴다.
/// `wantsPriorityOverSystemBehavior` 로 우리가 먼저 받는다.
final class MarkdownTextView: UITextView {
    /// `true` 면 들여쓰기, `false` 면 내어쓰기.
    var onTab: (@MainActor (Bool) -> Void)?

    override var keyCommands: [UIKeyCommand]? {
        let deeper = UIKeyCommand(input: "\t", modifierFlags: [], action: #selector(indentPressed))
        let shallower = UIKeyCommand(input: "\t", modifierFlags: .shift, action: #selector(outdentPressed))
        deeper.wantsPriorityOverSystemBehavior = true
        shallower.wantsPriorityOverSystemBehavior = true
        return [deeper, shallower]
    }

    @objc private func indentPressed() { onTab?(true) }
    @objc private func outdentPressed() { onTab?(false) }
}

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
    /// 편집 도구 띠의 부탁 (127). 하고 나면 `onFormatted` 로 알린다.
    var format: LibraryModel.FormatRequest? = nil
    var onFormatted: @MainActor () -> Void = {}
    /// 커서가 **제목 줄(머리말 뒤 첫 줄)** 에 있나. 바뀔 때만 알린다 — 그 줄을 떠나야
    /// 파일명을 바꾼다 (89). 치는 중간마다 바꾸면 iCloud 가 그 하나하나를 퍼뜨려 충돌을 부른다.
    var onTitleLineChanged: @MainActor (Bool) -> Void = { _ in }
    /// 커서가 편집기에 붙었나 · 떨어졌나 (98). 아이폰에는 키보드를 내릴 길이 없어
    /// 이 값으로 `키보드 내리기` 단추를 띄운다.
    var onFocusChanged: @MainActor (Bool) -> Void = { _ in }
    /// 커서가 있는 줄이 **사진 줄**이면 그 주소 (ADR-0005 의 L3 후퇴판).
    /// 편집기 안에 사진을 그리는 대신, 아래 띠에 작게 띄우고 눌러서 전체화면으로 본다.
    var onImageLineChanged: @MainActor (String?) -> Void = { _ in }
    /// 커서 자리에 **지금 걸려 있는 표시** (128). 도구 띠가 눌린 모습으로 보여 준다.
    var onActiveChanged: @MainActor (Formatting.Active) -> Void = { _ in }
    /// 커서 앞에 `>>` · `[[` 가 있나 (147). `nil` 이면 목록을 닫으라는 뜻이다.
    var onLinkQueryChanged: @MainActor (NoteLinking.Query?) -> Void = { _ in }

    func makeCoordinator() -> Coordinator {
        Coordinator(onEdit: onEdit, onTitleLine: onTitleLineChanged,
                    onFocus: onFocusChanged, onImageLine: onImageLineChanged,
                    onActive: onActiveChanged,
                    onLinkQuery: onLinkQueryChanged)
    }

    func makeUIView(context: Context) -> UITextView {
        // **TextKit 2 를 손으로 조립하지 않는다.** 빌드 7 에서 NSTextContentStorage ·
        // NSTextLayoutManager · 커스텀 NSTextStorage 를 직접 엮었다가 빈 화면이
        // 떴다 — 오류 하나 없이. 여기서는 컴파일해 볼 수 없는 조립이다.
        // 이 생성자가 같은 TextKit 2 를 만들어 주고, 칠하는 일은 대리자로 붙는다.
        let view = MarkdownTextView(usingTextLayoutManager: true)
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
        view.onTab = { [weak coordinator = context.coordinator] deeper in
            coordinator?.shiftIndent(deeper)
        }
        return view
    }

    func updateUIView(_ view: UITextView, context: Context) {
        let coordinator = context.coordinator
        // 클로저는 화면이 다시 그려질 때마다 새로 온다. 묵은 것을 들고 있으면
        // 저장이 **이전 노트로** 간다.
        coordinator.onEdit = onEdit
        coordinator.onTitleLine = onTitleLineChanged
        coordinator.onFocus = onFocusChanged
        coordinator.onImageLine = onImageLineChanged
        coordinator.onActive = onActiveChanged
        coordinator.onLinkQuery = onLinkQueryChanged
        coordinator.refreshStyleIfNeeded(for: view.traitCollection)
        coordinator.load(noteID: noteID, text: text)
        if let insertion, coordinator.insert(insertion) { onInserted() }
        if let format, coordinator.apply(format) { onFormatted() }
    }

    @MainActor
    final class Coordinator: NSObject, UITextViewDelegate, NSTextStorageDelegate {
        var onEdit: @MainActor (String) -> Void
        var onTitleLine: @MainActor (Bool) -> Void
        var onFocus: @MainActor (Bool) -> Void
        var onImageLine: @MainActor (String?) -> Void
        var onActive: @MainActor (Formatting.Active) -> Void
        var onLinkQuery: @MainActor (NoteLinking.Query?) -> Void
        /// 마지막으로 알린 표시 상태 (128). 바뀔 때만 알린다 — 커서가 움직일 때마다
        /// 화면을 다시 그리면 값도 없이 비싸다.
        private var lastActive: Formatting.Active?
        private var lastLinkQuery: NoteLinking.Query?
        /// 마지막으로 한 편집 도구 부탁 (127). 같은 것을 두 번 하지 않는다.
        private var lastFormatID: UUID?
        /// 지난 선택 (132). 어느 쪽 끝이 움직였는지 알려면 견줄 것이 있어야 한다.
        private var lastSelection: NSRange?
        /// 마지막으로 알린 사진 주소. 바뀔 때만 알린다.
        private var lastImageLine: String??
        /// 마지막으로 알린 값. 바뀔 때만 알린다.
        private var wasOnTitleLine = false
        weak var view: UITextView?
        var sheet: EditorStyleSheet?

        private var loadedNoteID: String?
        private var loadedText = ""
        private var isStyling = false
        /// 지난번 머리말 길이. 바뀌면 그 구간을 통째로 다시 칠한다 (`MarkdownStyler.restyle`).
        private var headerLength = 0
        /// 지난번 커서 문단. 커서가 다른 문단으로 가면 **둘만** 다시 칠한다 (S11).
        /// `noParagraph` 면 아직 모른다는 뜻 — 다음 선택 변화가 반드시 다시 칠한다.
        private var cursorParagraph = NSRange(location: NSNotFound, length: 0)

        /// 커서 자리. 그 문단만 마커를 흐리게(L1) 두고 나머지는 숨긴다(L2).
        /// VoiceOver 후퇴는 두지 않는다 — 사용자 결정 (빌드 14 · 13번, A10).
        private var cursorHint: Int? { view?.selectedRange.location }
        /// 한글 조합 중에는 속성을 건드리지 않는다 — 조합이 끊겨 자음과 모음이
        /// 따로 찍힌다 (안정화 기준 S10).
        private var isComposing = false
        /// 번호를 다시 매기는 중. 그 사이에 오는 선택 변화로 되돌아오지 않게 한다.
        private var isRenumbering = false
        private var sizeCategory = UIApplication.shared.preferredContentSizeCategory

        init(onEdit: @escaping @MainActor (String) -> Void,
             onTitleLine: @escaping @MainActor (Bool) -> Void,
             onFocus: @escaping @MainActor (Bool) -> Void,
             onImageLine: @escaping @MainActor (String?) -> Void,
             onActive: @escaping @MainActor (Formatting.Active) -> Void,
             onLinkQuery: @escaping @MainActor (NoteLinking.Query?) -> Void) {
            self.onEdit = onEdit
            self.onTitleLine = onTitleLine
            self.onFocus = onFocus
            self.onImageLine = onImageLine
            self.onActive = onActive
            self.onLinkQuery = onLinkQuery
        }

        /// **커서 앞에 방아쇠가 있나** (147). 규칙은 Core 의 `NoteLinking.query` 가 정한다.
        ///
        /// **조합 중에도 알린다.** 읽기만 하므로 조합을 깨지 않고, `>>회` 처럼 한글을 만드는
        /// 동안에도 목록이 따라와야 쓸 만하다. 글을 바꾸는 쪽(`applyLink`)만 조합을 피한다.
        private func reportLinkQuery(_ textView: UITextView) {
            let selection = textView.selectedRange
            guard selection.length == 0 else {
                if lastLinkQuery != nil { lastLinkQuery = nil; onLinkQuery(nil) }
                return
            }
            let found = NoteLinking.query(in: textView.textStorage.string, caret: selection.location)
            guard found != lastLinkQuery else { return }
            lastLinkQuery = found
            onLinkQuery(found)
        }

        /// 고른 노트를 커서 자리에 넣는다 (147). 방아쇠는 **다시 찾는다** — 사이에 커서가
        /// 움직였을 수 있다. 없으면 아무 일도 하지 않는다.
        func applyLink(title: String, path: String, noteFolder: String) -> Bool {
            guard let view, !isComposing, view.markedTextRange == nil else { return false }
            guard let found = NoteLinking.query(in: view.textStorage.string,
                                                caret: view.selectedRange.location) else { return false }
            let done = apply(NoteLinking.link(to: title, path: path,
                                              from: noteFolder, replacing: found), in: view)
            if done { lastLinkQuery = nil; onLinkQuery(nil) }
            return done
        }

        /// **커서 자리에 지금 무엇이 걸려 있나** (128). 규칙은 Core 의 `Formatting.active` 가
        /// 정한다 — 도구 띠를 누를 때와 **같은 훑기**라 눌린 모습과 실제 동작이 안 갈린다.
        private func reportActiveFormats(_ textView: UITextView) {
            guard !isComposing, textView.markedTextRange == nil else { return }
            let selection = textView.selectedRange
            let active = Formatting.active(in: textView.textStorage.string,
                                           start: selection.location, length: selection.length)
            guard active != lastActive else { return }
            lastActive = active
            onActive(active)
        }

        /// **커서 줄에 사진이 있나** (L3 후퇴판). 규칙은 Core 의 `MarkdownLinks` 가 정한다 —
        /// 줄 하나만 주고 첫 그림 링크의 주소를 가져온다. 바뀔 때만 바깥에 알린다.
        func reportImageLine(_ textView: UITextView) {
            let text = textView.textStorage.string as NSString
            var found: String?
            if text.length > 0 {
                let location = min(textView.selectedRange.location, text.length)
                let line = text.paragraphRange(for: NSRange(location: min(location, text.length - 1), length: 0))
                found = MarkdownLinks.extract(from: text.substring(with: line))
                    .first { $0.kind == .image }?.destination
            }
            guard lastImageLine != .some(found) else { return }
            lastImageLine = .some(found)
            onImageLine(found)
        }

        /// 커서가 제목 줄에 있나 — 머리말 뒤 **첫 문단**이 제목 줄이다.
        /// 바뀌었을 때만 바깥에 알린다 (89).
        func reportTitleLine(_ textView: UITextView) {
            let text = textView.textStorage.string as NSString
            let start = min(headerLength, max(0, text.length))
            let titleLine = text.length > 0
                ? text.paragraphRange(for: NSRange(location: min(start, text.length - 1), length: 0))
                : NSRange(location: 0, length: 0)
            let cursor = min(textView.selectedRange.location, text.length)
            let onLine = cursor >= titleLine.location && cursor <= NSMaxRange(titleLine)
            guard onLine != wasOnTitleLine else { return }
            wasOnTitleLine = onLine
            onTitleLine(onLine)
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

        /// **편집 도구 띠의 부탁을 한 번의 바꾸기로** (127 · T13 1차).
        ///
        /// 무엇을 넣을지는 `Core` 의 순수 함수가 정한다(`Formatting`) — 여기서는 그 결과를
        /// `UITextView` 에 그대로 옮기기만 한다. **한 번의 `replace` 로 끝내는 것이 중요하다** —
        /// 되돌리기(`⌘Z`)가 한 번에 걸린다.
        func apply(_ request: LibraryModel.FormatRequest) -> Bool {
            guard request.id != lastFormatID, let view else { return false }
            lastFormatID = request.id

            switch request.kind {
            case .shift(let deeper):
                shiftIndent(deeper)
                return true
            case .wrap(let wrap):
                let selection = view.selectedRange
                return apply(Formatting.toggle(wrap, in: view.textStorage.string,
                                               start: selection.location,
                                               length: selection.length), in: view)
            case .quote:
                let selection = view.selectedRange
                return apply(Formatting.toggleQuote(in: view.textStorage.string,
                                                    start: selection.location,
                                                    length: selection.length), in: view)
            case .table:
                let selection = view.selectedRange
                return apply(Formatting.table(in: view.textStorage.string,
                                              start: selection.location), in: view)
            case .link(let title, let path, let noteFolder):
                return applyLink(title: title, path: path, noteFolder: noteFolder)
            }
        }

        private func apply(_ edit: Formatting.Edit, in view: UITextView) -> Bool {
            let range = NSRange(location: edit.start, length: edit.length)
            guard let target = textRange(view, range) else { return false }
            view.replace(target, withText: edit.text)
            view.selectedRange = NSRange(location: edit.selectionStart, length: edit.selectionLength)
            keepCaretVisible(view)
            reportActiveFormats(view)
            reportLinkQuery(view)
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
        /// 줄이 통째로 지워졌다 — 바뀐 뒤에 번호를 맞출 자리 (104).
        private var pendingRenumber: Int?

        func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange,
                      replacementText text: String) -> Bool {
            isComposing = textView.markedTextRange != nil
            // **줄이 없어졌나.** 지워진 자리에 줄바꿈이 끼어 있으면 항목 하나가 사라진
            // 것이다 — 아래 번호가 어긋난다. 바뀐 뒤(`textViewDidChange`)에 맞춘다.
            // **커서가 줄을 떠날 때마다 맞추지 않는다** — 그러면 `6.` 다음에 손으로 친
            // `5.` 까지 `7.` 로 덮는다 (빌드 32 · 7번, 사용자). 손으로 친 번호는 그대로 둔다.
            if range.length > 0, !isRenumbering {
                let storage = textView.textStorage.string as NSString
                if NSMaxRange(range) <= storage.length,
                   storage.substring(with: range).contains("\n") {
                    pendingRenumber = range.location
                }
            }
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

            // **빈 항목에서 나올 때 얕은 위 줄까지** 간다 (141 뒷이야기). 단계의 너비는
            // 부모의 마커에 따라 다르므로 빈칸 둘로는 어느 단계에도 못 선다.
            let here = Self.leadingWidth(text.substring(with: line))
            let shallower = Self.line(text, above: paragraph.location, shallowerThan: here)
            guard let action = ListEditing.returnPressed(in: text.substring(with: line),
                                                         outdentingTo: shallower) else {
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
            // 가운데에 끼워 넣었으면 아래 번호들이 어긋난다 — 여기서 맞춘다 (104).
            renumberList(around: textView.selectedRange.location, in: textView)
            keepCaretVisible(textView)
            onEdit(textView.text)
            return true
        }

        /// **번호 목록을 1 · 2 · 3 으로 맞춘다** (104, 사용자 요청).
        ///
        /// 규칙은 Core 의 `ListEditing.renumber` 가 정하고 여기서는 **숫자만** 바꿔 넣는다.
        /// 줄 전체를 갈아 끼우지 않으므로 커서와 되돌리기가 덜 흔들린다. 뒤에서부터 넣어
        /// 앞의 자리가 밀리지 않게 한다.
        private func renumberList(around location: Int, in textView: UITextView) {
            guard !isRenumbering, !isComposing, textView.markedTextRange == nil else { return }
            let text = textView.textStorage.string as NSString
            guard text.length > 0, let run = listRun(in: text, around: location) else { return }
            let fixes = ListEditing.renumber(text.substring(with: run))
            guard !fixes.isEmpty else { return }

            isRenumbering = true
            defer { isRenumbering = false }
            var caret = textView.selectedRange.location
            for fix in fixes.reversed() {
                let range = NSRange(location: run.location + fix.start, length: fix.length)
                guard NSMaxRange(range) <= text.length, let target = textRange(textView, range) else { continue }
                textView.replace(target, withText: fix.number)
                if range.location < caret { caret += (fix.number as NSString).length - fix.length }
            }
            let length = (textView.textStorage.string as NSString).length
            textView.selectedRange = NSRange(location: max(0, min(caret, length)), length: 0)
        }

        /// 커서가 있는 줄을 둘러싼 **목록 한 덩이**. 목록 줄이 아니면 `nil`.
        /// 항목 사이의 빈 줄 하나는 목록을 끊지 않는다 — 그렇게 쓰는 사람이 많다.
        private func listRun(in text: NSString, around location: Int) -> NSRange? {
            let seed = text.paragraphRange(for: NSRange(location: min(location, text.length - 1), length: 0))
            guard Self.isItemLine(text, seed) else { return nil }
            var start = seed.location
            var end = NSMaxRange(seed)
            while start > 0 {
                let previous = text.paragraphRange(for: NSRange(location: start - 1, length: 0))
                if Self.isItemLine(text, previous) {
                    start = previous.location
                    continue
                }
                // 빈 줄 하나는 건너뛴다 — 그 위가 항목일 때만.
                guard Self.isBlankLine(text, previous), previous.location > 0 else { break }
                let above = text.paragraphRange(for: NSRange(location: previous.location - 1, length: 0))
                guard Self.isItemLine(text, above) else { break }
                start = above.location
            }
            while end < text.length {
                let next = text.paragraphRange(for: NSRange(location: end, length: 0))
                if Self.isItemLine(text, next) {
                    end = NSMaxRange(next)
                    continue
                }
                guard Self.isBlankLine(text, next), NSMaxRange(next) < text.length else { break }
                let below = text.paragraphRange(for: NSRange(location: NSMaxRange(next), length: 0))
                guard Self.isItemLine(text, below) else { break }
                end = NSMaxRange(below)
            }
            return NSRange(location: start, length: end - start)
        }

        private static func line(_ text: NSString, _ paragraph: NSRange) -> String {
            var line = paragraph
            if line.length > 0, text.character(at: NSMaxRange(line) - 1) == 0x0A { line.length -= 1 }
            return text.substring(with: line)
        }

        /// 이 자리 위로 올라가며 만나는 **빈 줄이 아닌 첫 줄** (139 · 141). 없으면 `nil`.
        ///
        /// **빈 줄을 건너뛴다** (141). 항목 사이에 빈 줄을 두는 사람이 많은데, 바로 위
        /// 줄만 보면 그 빈 줄에 걸려 부모를 못 찾았다 — `10. ` 부모 밑으로 들어가지
        /// 못하고 겹치지 않은 목록이 저장됐다.
        private static func line(_ text: NSString, above location: Int) -> String? {
            var at = location
            while at > 0 {
                let paragraph = text.paragraphRange(for: NSRange(location: at - 1, length: 0))
                let candidate = line(text, paragraph)
                if !candidate.trimmingCharacters(in: .whitespaces).isEmpty { return candidate }
                if paragraph.location == 0 { return nil }
                at = paragraph.location
            }
            return nil
        }

        /// 이 자리 위로 올라가며 만나는 **더 얕은 첫 줄** (139). 내어쓰기가 여기까지 나온다.
        private static func line(_ text: NSString, above location: Int,
                                 shallowerThan width: Int) -> String? {
            var at = location
            while at > 0 {
                let paragraph = text.paragraphRange(for: NSRange(location: at - 1, length: 0))
                let candidate = line(text, paragraph)
                if !candidate.trimmingCharacters(in: .whitespaces).isEmpty,
                   leadingWidth(candidate) < width {
                    return candidate
                }
                if paragraph.location == 0 { return nil }
                at = paragraph.location
            }
            return nil
        }

        /// 줄 앞의 빈칸 너비 (탭은 네 칸) — `ListEditing` 과 같은 셈.
        static func leadingWidth(_ line: String) -> Int {
            line.prefix { $0 == " " || $0 == "\t" }.reduce(0) { $0 + ($1 == "\t" ? 4 : 1) }
        }

        private static func isItemLine(_ text: NSString, _ paragraph: NSRange) -> Bool {
            ListEditing.returnPressed(in: line(text, paragraph)) != nil
                || LineStyler.style(paragraph: line(text, paragraph)).block == .orderedItem
        }

        private static func isBlankLine(_ text: NSString, _ paragraph: NSRange) -> Bool {
            line(text, paragraph).trimmingCharacters(in: .whitespaces).isEmpty
        }

        /// **탭 · 시프트 탭으로 들여쓰기** (빌드 29 · 1번). 규칙은 Core 의 `ListEditing` 이
        /// 정하고 여기서는 고른 줄들을 바꿔 넣기만 한다. `replace(_:withText:)` 를 쓰므로
        /// 되돌리기에 한 번의 편집으로 남는다 (53 과 같은 까닭).
        func shiftIndent(_ deeper: Bool) {
            guard let view else { return }
            let text = view.textStorage.string as NSString
            let selection = view.selectedRange
            guard text.length > 0 else { return }

            // 글 끝에 선 커서까지 안전하게 (다른 곳과 같은 죔쇠).
            let start = min(selection.location, text.length - 1)
            let clamped = NSRange(location: start, length: min(selection.length, text.length - start))
            var block = text.paragraphRange(for: clamped)
            if block.length > 0, text.character(at: NSMaxRange(block) - 1) == 0x0A { block.length -= 1 }
            let before = text.substring(with: block)

            // **딸린 줄까지 함께 옮기고, 붙을 자리는 앞 형제로** (148 · 150).
            // **셈까지 Core 가 한다** (`plan`) — 여기서는 줄 차례를 글자 자리로 바꾸기만 한다.
            // 예전에는 문단을 하나씩 걸어 구간을 넓혔는데, 시작 자리가 **줄바꿈 글자**를
            // 가리켜 첫 바퀴가 같은 문단을 다시 집었다. 그래서 딸린 줄을 **한 줄 덜**
            // 데려갔다 (사용자 · 빌드 45 — *모델링은 따라오는데 시스템화는 못 따라온다*).
            var parent: String?
            var shallower: String?
            if let run = listRun(in: text, around: block.location) {
                let runLines = text.substring(with: run).components(separatedBy: "\n")
                let head = text.substring(with: NSRange(location: run.location,
                                                        length: block.location - run.location))
                let first = head.isEmpty ? 0 : head.components(separatedBy: "\n").count - 1
                let selected = before.components(separatedBy: "\n").count
                let move = ListEditing.plan(movingFrom: first, count: selected, in: runLines)
                parent = move.parent
                shallower = move.shallower

                let from = run.location + ListEditing.offset(ofLine: move.first, in: runLines)
                let to = min(run.location + ListEditing.offset(ofLine: move.end, in: runLines),
                             NSMaxRange(run))
                var moved = NSRange(location: from, length: max(0, to - from))
                // 마지막 줄바꿈은 빼고 바꾼다 — 넣으면 줄이 하나 사라진다.
                if moved.length > 0, NSMaxRange(moved) <= text.length,
                   text.character(at: NSMaxRange(moved) - 1) == 0x0A { moved.length -= 1 }
                if moved.length > 0 { block = moved }
            } else {
                parent = Self.line(text, above: block.location)
                shallower = Self.line(text, above: block.location,
                                      shallowerThan: Self.leadingWidth(before))
            }
            let moving = text.substring(with: block)
            guard let shifted = deeper
                    ? ListEditing.indent(moving, under: parent)
                    : ListEditing.outdent(moving, to: shallower) else {
                // 목록이 아니다 — 탭은 빈칸 둘로, 시프트 탭은 아무 일도 없다.
                if deeper { insertPlainIndent(in: view, at: selection) }
                return
            }
            guard let target = textRange(view, block) else { return }
            view.replace(target, withText: shifted.text)
            if selection.length == 0 {
                let moved = max(block.location, selection.location + shifted.firstLineDelta)
                view.selectedRange = NSRange(location: moved, length: 0)
            } else {
                view.selectedRange = NSRange(location: block.location,
                                             length: (shifted.text as NSString).length)
            }
            // **단계를 바꿨으면 번호를 다시 맞춘다** (129, 사용자 — 들여쓰기 뒤 번호가
            // 어긋났다). 들여쓰거나 내어쓰면 그 줄이 **다른 단계로 옮겨 가므로** 위아래
            // 번호가 다 어긋난다. 치는 중에는 안 건다(106) — 이것은 **손으로 시킨 구조
            // 변경**이라 그 자리에서 맞추는 것이 맞다.
            renumberList(around: view.selectedRange.location, in: view)
            keepCaretVisible(view)
            onEdit(view.text)
        }

        /// 목록이 아닌 줄에서 탭 — 커서 자리에 빈칸 둘. 네 칸이 되면 코드가 되므로
        /// 마크다운에서 안전한 한 단계다.
        private func insertPlainIndent(in textView: UITextView, at range: NSRange) {
            guard let target = textRange(textView, range) else { return }
            textView.replace(target, withText: ListEditing.step)
            let step = (ListEditing.step as NSString).length
            textView.selectedRange = NSRange(location: range.location + step, length: 0)
            onEdit(textView.text)
        }

        /// **커서를 눈에 보이는 자리로** (131, 사용자 — *엔터를 빠르게 치면 커서가 키보드
        /// 안으로 숨는다*).
        ///
        /// 우리가 **글을 직접 넣는 자리**(목록 이어 주기 · 들여쓰기 · 편집 도구)에서는
        /// `UITextView` 가 스스로 스크롤을 맞춰 주지 않는다. 사람이 친 글자는 맞춰 주지만,
        /// 코드가 넣은 글은 그 대상이 아니다 — 그래서 빠르게 줄바꿈을 이어 가면 커서가
        /// 키보드 뒤로 내려가 버렸다. **한 바퀴 뒤에** 맞춘다: 방금 바꾼 글의 배치가
        /// 끝나야 커서 자리가 참이다.
        private func keepCaretVisible(_ textView: UITextView) {
            keepVisible(textView, at: textView.selectedRange.location)
        }

        /// **고르는 쪽 끝을 따라간다** (132, 사용자 — *복사하려고 범위를 아래로 끌면
        /// 커서가 키보드 안으로 숨는다*).
        ///
        /// 어느 쪽 끝이 움직였는지는 **지난 선택과 견주어** 안다 — 시작이 그대로면 끝을
        /// 늘린 것이고, 아니면 앞쪽을 옮긴 것이다. 움직인 쪽을 보여 준다.
        private func keepSelectionEdgeVisible(_ textView: UITextView) {
            let selection = textView.selectedRange
            defer { lastSelection = selection }
            guard textView.isFirstResponder, !isComposing, textView.markedTextRange == nil else { return }
            let moved: Int
            if let previous = lastSelection, previous.location == selection.location {
                moved = NSMaxRange(selection)
            } else {
                moved = selection.location
            }
            keepVisible(textView, at: moved)
        }

        /// **한 바퀴 뒤에** 맞춘다 — 방금 바꾼 글의 배치가 끝나야 그 자리가 참이다.
        ///
        /// **이미 보이면 가만히 둔다** (135, 사용자 — *조금 더 부드러웠으면*). 움직일 때마다
        /// 끌어오면 손가락을 따라 화면이 잘게 떨린다. 가장자리에서 **한 줄 남짓 남았을 때만**
        /// 움직이고, 그때도 딱 그만큼만 움직인다.
        private func keepVisible(_ textView: UITextView, at location: Int) {
            DispatchQueue.main.async { [weak textView] in
                guard let textView, textView.isFirstResponder else { return }
                let length = (textView.textStorage.string as NSString).length
                let safe = max(0, min(location, length))
                guard let position = textView.position(from: textView.beginningOfDocument, offset: safe) else { return }
                let caret = textView.caretRect(for: position)
                guard caret.height.isFinite, !caret.isNull, !caret.isInfinite else { return }

                // 지금 눈에 보이는 칸 — 키보드와 아래 띠가 먹은 만큼을 뺀다.
                let insets = textView.adjustedContentInset
                let visible = CGRect(x: textView.contentOffset.x,
                                     y: textView.contentOffset.y + insets.top,
                                     width: textView.bounds.width,
                                     height: textView.bounds.height - insets.top - insets.bottom)
                // 가장자리에 붙기 전에 조금 미리 움직인다 — 한 줄 반쯤.
                let margin = caret.height * 1.5
                let room = visible.insetBy(dx: 0, dy: margin)
                guard !room.contains(CGPoint(x: caret.midX, y: caret.midY)) else { return }
                textView.scrollRectToVisible(caret.insetBy(dx: 0, dy: -margin), animated: false)
            }
        }

        private func textRange(_ textView: UITextView, _ range: NSRange) -> UITextRange? {
            guard let start = textView.position(from: textView.beginningOfDocument, offset: range.location),
                  let end = textView.position(from: start, offset: range.length) else { return nil }
            return textView.textRange(from: start, to: end)
        }

        /// **커서가 다른 문단으로 갔다.** 떠난 문단은 마커를 숨기고, 온 문단은 드러낸다 (L2).
        /// 조합 중에는 건드리지 않는다 — 조합이 끊긴다 (S10).
        func textViewDidChangeSelection(_ textView: UITextView) {
            reportTitleLine(textView)
            reportImageLine(textView)
            reportActiveFormats(textView)
            reportLinkQuery(textView)
            keepSelectionEdgeVisible(textView)
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

        /// **편집이 끝났다** — 키보드가 내려갔거나 다른 곳으로 초점이 갔다 (빌드 29 · 2번).
        ///
        /// **커서가 마지막 줄에 있으면 떠날 자리가 없다.** 그 줄은 마커가 드러난 채
        /// 남고(L1), 그 줄이 제목 줄이면 파일명도 안 맞춰졌다. 커서가 사라지는 이
        /// 자리에서 둘 다 갚는다 — 커서가 없는 것처럼 다시 칠하고, 제목을 확정한다.
        func textViewDidEndEditing(_ textView: UITextView) {
            onFocus(false)
            hideMarkersOnCursorLine(textView)
            // 다음에 커서가 오면 **그 줄이 어디든** 다시 칠하게 한다 (아래 참고).
            cursorParagraph = Self.noParagraph
            guard wasOnTitleLine else { return }
            wasOnTitleLine = false
            onTitleLine(false)
        }

        /// **다시 커서가 왔다.** 여기서는 아무것도 칠하지 않는다.
        ///
        /// 이 대리자는 **커서 자리가 정해지기 전에** 불린다 (빌드 31 · 2번 — 탭하면 화면이
        /// 맨 아래로 끌려가고 커서가 글 끝으로 갔다). 여기서 속성을 바꾸면 TextKit 이
        /// **아직 옛 선택**을 보고 그 자리로 화면을 옮긴다. 칠하는 일은 커서가 실제로 놓인
        /// 뒤에 오는 `textViewDidChangeSelection` 에 맡기고, 여기서는 **지난 문단만 지워**
        /// 그쪽이 반드시 다시 칠하게 한다.
        func textViewDidBeginEditing(_ textView: UITextView) {
            onFocus(true)
            cursorParagraph = Self.noParagraph
            // **한 바퀴 뒤에 칠한다.** 지금은 커서 자리가 아직 안 정해졌다(100).
            // 한 바퀴 뒤면 커서가 제자리에 있고, **선택이 안 바뀌어 `…DidChangeSelection`
            // 이 아예 안 불리는 경우**(같은 자리를 다시 탭했을 때)도 여기서 갚는다 —
            // 그때 기호가 안 나타나 다른 줄에 갔다 와야 보였다 (빌드 32 · 3번).
            DispatchQueue.main.async { [weak self, weak textView] in
                guard let self, let textView, textView.isFirstResponder else { return }
                self.showMarkersOnCursorLine(textView)
                self.reportImageLine(textView)
            }
        }

        /// **커서가 온 줄의 기호를 드러낸다** (L1). 커서가 이미 제자리에 있을 때만 부른다.
        private func showMarkersOnCursorLine(_ textView: UITextView) {
            guard !isStyling, !isRenumbering, !isComposing,
                  textView.markedTextRange == nil, let sheet else { return }
            let text = textView.textStorage.string as NSString
            guard text.length > 0 else { return }
            let location = min(textView.selectedRange.location, text.length)
            let line = text.paragraphRange(for: NSRange(location: min(location, text.length - 1), length: 0))
            isStyling = true
            textView.textStorage.beginEditing()
            headerLength = MarkdownStyler.restyle(textView.textStorage, touching: line, with: sheet,
                                                  previousHeader: headerLength, cursor: location)
            textView.textStorage.endEditing()
            isStyling = false
            cursorParagraph = line
        }

        /// 어떤 문단과도 같지 않은 값. 이것이 들어 있으면 다음 선택 변화가 반드시 다시 칠한다.
        private static let noParagraph = NSRange(location: NSNotFound, length: 0)

        /// **커서가 떠났으니 그 줄의 마커도 숨긴다** (빌드 29 · 2번 — 마지막 줄은 떠날 자리가 없다).
        /// 커서가 사라지는 자리라 화면이 움직일 까닭이 없다 — 속성 때문에 딸려 움직이지 않도록
        /// 스크롤 자리를 붙들었다 놓는다.
        private func hideMarkersOnCursorLine(_ textView: UITextView) {
            guard !isStyling, !isComposing, textView.markedTextRange == nil, let sheet else { return }
            let text = textView.textStorage.string as NSString
            guard text.length > 0 else { return }
            let location = min(textView.selectedRange.location, text.length)
            let line = text.paragraphRange(for: NSRange(location: min(location, text.length - 1), length: 0))
            let offset = textView.contentOffset
            isStyling = true
            textView.textStorage.beginEditing()
            headerLength = MarkdownStyler.restyle(textView.textStorage, touching: line, with: sheet,
                                                  previousHeader: headerLength,
                                                  cursor: MarkdownStyler.noCursor)
            textView.textStorage.endEditing()
            isStyling = false
            textView.setContentOffset(offset, animated: false)
        }

        func textViewDidChange(_ textView: UITextView) {
            let composing = textView.markedTextRange != nil
            let wasComposing = isComposing
            isComposing = composing
            // 글자가 바뀔 때마다 방아쇠를 다시 본다 (147) — 조합 중에도 목록이 따라오게.
            reportLinkQuery(textView)

            // 조합이 끝났다. 건너뛴 재칠을 여기서 갚는다.
            if wasComposing, !composing, let sheet {
                isStyling = true
                headerLength = MarkdownStyler.restyle(textView.textStorage,
                                                      touching: textView.selectedRange, with: sheet,
                                                      previousHeader: headerLength, cursor: cursorHint)
                isStyling = false
            }
            // 줄이 없어졌으면 이제 번호를 맞춘다 (104).
            if let location = pendingRenumber {
                pendingRenumber = nil
                if !composing { renumberList(around: location, in: textView) }
            }
            // **여기서 `loadedText` 를 갱신하지 않는다.** 갱신하면 "사용자가
            // 손대지 않았나" 가 늘 참이 되어, 뒤늦게 온 파일 글이 방금 친 것을
            // 덮는다. 파일과 편집기가 같아지는 것은 저장 뒤 `load` 가 판정한다.
            onEdit(textView.text)
        }
    }
}
