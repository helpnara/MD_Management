import XCTest

/// **영어 앱 미리보기 영상의 손가락** (2026-10-12 사용자 — *직접 촬영하지 않고도 영어 버전 영상을 만들 수 있다면*).
///
/// 이 파일은 앱에 들어가지 않는다 — `store-preview.yml` 이 그때만 시험 대상으로 붙여 빌드한다 (`add-target.py`).
/// 시뮬레이터 화면을 녹화하는 동안 이 시험이 앱을 손가락처럼 조작하고, 시작 · 끝 시각을 `PREVIEW_MARK` 로 찍는다 — 흐름이 그 사이만 잘라 쓴다.
/// 한국어 영상(`docs/store/preview/slow-margin-preview-ko.mp4`)과 같은 차례: 쓰기 → 목록 → 링크 모음 → 검색 → 읽기.
final class StorePreviewUITests: XCTestCase {

    func testPreview() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US", "-storeFolder"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Watch Later"].firstMatch.waitForExistence(timeout: 30), "목록이 안 떴다")
        pause(2.0)
        mark("START")
        pause(1.2)

        // ① 새 노트 — 제목을 Today 로, 본문은 커서 줄만 기호가 보이는 모습
        app.buttons["New Note"].firstMatch.tap()
        let editor = app.textViews.firstMatch
        XCTAssertTrue(editor.waitForExistence(timeout: 10), "편집기가 안 떴다")
        pause(0.8)
        // 시뮬레이터에서는 새 노트의 편집기에 커서가 저절로 안 들어간다 (첫 녹화 — *Neither element nor any descendant has keyboard focus*).
        // 제목 줄의 오른쪽 끝을 눌러 커서를 `# New Note` 끝에 둔다.
        editor.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.04)).tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5), "키보드가 안 올라왔다")
        pause(0.6)
        editor.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: "New Note".count))
        pause(0.3)
        type(editor, ["To", "day"])
        pause(0.5)
        type(editor, ["\n", "Write ", "in ", "plain ", "text. "])
        type(editor, ["Only ", "this ", "line ", "shows ", "**", "marks", "**"])
        pause(1.2)
        type(editor, ["\n", "- [ ] ", "Read ", "it ", "later"])
        pause(1.8)

        // ② 목록으로
        app.navigationBars.buttons.element(boundBy: 0).tap()
        pause(1.5)

        // ③ 링크 모음 (읽기)
        app.staticTexts["Watch Later"].firstMatch.tap()
        pause(3.2)
        app.navigationBars.buttons.element(boundBy: 0).tap()
        pause(1.2)

        // ④ 검색 → 읽기 (사진 · 표)
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5), "검색 칸이 없다")
        search.tap()
        pause(0.6)
        type(search, ["Lis", "bon"])
        pause(1.8)
        app.staticTexts["Lisbon Trip"].firstMatch.tap()
        pause(3.5)
        mark("END")
    }

    /// 낱말 조각마다 조금 쉬어 사람이 치는 것처럼.
    private func type(_ element: XCUIElement, _ pieces: [String]) {
        for piece in pieces {
            element.typeText(piece)
            pause(0.18)
        }
    }

    private func pause(_ seconds: Double) {
        Thread.sleep(forTimeInterval: seconds)
    }

    private func mark(_ name: String) {
        print(String(format: "PREVIEW_MARK %@ %.3f", name, Date().timeIntervalSince1970))
    }
}
