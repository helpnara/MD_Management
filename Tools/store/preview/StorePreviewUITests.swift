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
        // 읽기 화면을 미리 데운다 — 러너에서는 첫 읽기 화면이 그려지기까지 몇 초가 걸려 멈춤 구간이 흰 화면이 됐다 (다섯 번째 녹화).
        app.staticTexts["Weekly Plan"].firstMatch.tap()
        waitForReading("Weekly Plan")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.staticTexts["Watch Later"].firstMatch.waitForExistence(timeout: 10), "목록으로 못 돌아왔다")
        // **시계 맞추기** — 녹화의 시각과 이 시험의 시각이 4~5초 어긋났다 (일곱 번째 녹화 — 녹화는 화면이 처음 바뀔 때부터 센다).
        // 화면을 잠깐 어둡게 바꾸고 그 시각을 찍는다. 자르는 단계가 녹화에서 밝던 화면이 어두워지는 장면을 찾아 두 시계를 맞춘다.
        pause(1.0)
        print(String(format: "PREVIEW_SYNC %.3f", Date().timeIntervalSince1970))
        XCUIDevice.shared.appearance = .dark
        pause(1.5)
        XCUIDevice.shared.appearance = .light
        pause(2.0)
        mark("START")
        hold(1.2)

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
        typing { editor.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: "New Note".count)) }
        pause(0.3)
        type(editor, ["To", "day"])
        hold(0.5)
        type(editor, ["\n", "Write ", "in ", "plain ", "text. "])
        type(editor, ["Only ", "this ", "line ", "shows ", "**", "marks", "**"])
        hold(1.2)
        type(editor, ["\n", "- [ ] ", "Read ", "it ", "later"])
        hold(1.8)

        // ② 목록으로
        app.navigationBars.buttons.element(boundBy: 0).tap()
        hold(1.5)

        // ③ 링크 모음 (읽기)
        app.staticTexts["Watch Later"].firstMatch.tap()
        waitForReading("Walk Slowly")
        hold(3.2)
        app.navigationBars.buttons.element(boundBy: 0).tap()
        hold(1.0)

        // ④ 검색 → 읽기 (사진 · 표)
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5), "검색 칸이 없다")
        search.tap()
        pause(0.6)
        type(search, ["Lis", "bon"])
        hold(1.8)
        app.staticTexts["Lisbon Trip"].firstMatch.tap()
        waitForReading("Day by day")
        hold(3.5)
        mark("END")
    }

    /// 낱말 조각마다 조금 쉬어 사람이 치는 것처럼.
    private func type(_ element: XCUIElement, _ pieces: [String]) {
        typing {
            for piece in pieces {
                element.typeText(piece)
                pause(0.18)
            }
        }
    }

    /// **글자 치는 구간** — 자르는 단계가 이 구간을 남는 시간에 맞춰 빨리 감는다. 러너에서는 한 글자에 수백 ms 가 걸려
    /// (네 번째 녹화 — 시험 170초, 장면 2071개) 원래 빠르기로는 30초에 못 들어갔다.
    private func typing(_ body: () -> Void) {
        let start = Date().timeIntervalSince1970
        body()
        print(String(format: "PREVIEW_TYPE %.3f %.3f", start, Date().timeIntervalSince1970))
    }

    /// 읽기 화면(웹 보기)에 이 글이 보일 때까지 — 그 뒤 그림이 화면에 칠해지도록 조금 더. 기다린 시간은 영상에서 줄어든다.
    private func waitForReading(_ text: String) {
        let app = XCUIApplication()
        let found = app.webViews.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
        XCTAssertTrue(found.waitForExistence(timeout: 30), "읽기 화면에 \(text) 가 안 떴다")
        pause(0.8)
    }

    private func pause(_ seconds: Double) {
        Thread.sleep(forTimeInterval: seconds)
    }

    /// **영상에서 이만큼 보여 준다** — 자르는 단계(`cut.py`)가 이 자리의 장면을 이 길이로 둔다. 다른 기다림은 줄인다
    /// (UI 시험은 동작마다 1~3초씩 멈춰 있어, 그대로면 97초가 됐다 — 두 번째 녹화).
    private func hold(_ seconds: Double) {
        print(String(format: "PREVIEW_HOLD %.3f %.2f", Date().timeIntervalSince1970, seconds))
        pause(seconds)
    }

    private func mark(_ name: String) {
        print(String(format: "PREVIEW_MARK %@ %.3f", name, Date().timeIntervalSince1970))
    }
}
