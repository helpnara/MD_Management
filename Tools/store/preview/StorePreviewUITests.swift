import XCTest

/// **영어 앱 미리보기 영상의 손가락과 눈** (2026-10-12 사용자 — *직접 촬영하지 않고도 영어 버전 영상을 만들 수 있다면*).
///
/// 이 파일은 앱에 들어가지 않는다 — `store-preview.yml` 이 그때만 시험 대상으로 붙여 빌드한다 (`add-target.py`).
/// 시험이 앱을 손가락처럼 조작하고, **장면마다 화면을 직접 찍어** 보여 줄 길이와 함께 남긴다 (`shot`).
/// 흐름이 그림들을 이어 붙여 영상으로 만든다 (`stitch.py`).
///
/// 처음에는 시뮬레이터 화면을 녹화했다 (첫~아홉 번째). 녹화는 읽기 화면(웹 보기)이 그리는 것을 놓쳐 — 다른 것이 움직일 때만
/// 한 장씩 잡혔다 — 링크 모음 · 여행 노트를 보여 주는 자리가 흰 화면이 됐고, 러너 빠르기가 매번 세 배씩 달라 시계도 못 맞췄다.
/// 화면 찍기는 앱 스토어 스크린샷과 같은 길이라 읽기 화면도 그대로 찍히고, 길이는 여기서 정하니 러너 빠르기와 상관없다.
///
/// 한국어 영상(`docs/store/preview/slow-margin-preview-ko.mp4`)과 같은 차례: 쓰기 → 목록 → 링크 모음 → 검색 → 읽기.
final class StorePreviewUITests: XCTestCase {

    private var count = 0

    func testPreview() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US", "-storeFolder"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Watch Later"].firstMatch.waitForExistence(timeout: 30), "목록이 안 떴다")
        // 읽기 화면을 미리 데운다 — 러너에서는 첫 읽기 화면이 그려지기까지 몇 초가 걸렸다.
        app.staticTexts["Weekly Plan"].firstMatch.tap()
        waitForReading("Weekly Plan")
        back(app)
        XCTAssertTrue(app.staticTexts["Watch Later"].firstMatch.waitForExistence(timeout: 10), "목록으로 못 돌아왔다")
        pause(1.0)

        // ⓪ 목록
        shot(2.0)

        // ① 새 노트 — 제목을 Today 로, 본문은 커서 줄만 기호가 보이는 모습
        app.buttons["New Note"].firstMatch.tap()
        let editor = app.textViews.firstMatch
        XCTAssertTrue(editor.waitForExistence(timeout: 10), "편집기가 안 떴다")
        pause(0.8)
        // 시뮬레이터에서는 새 노트의 편집기에 커서가 저절로 안 들어간다 (첫 녹화 — *Neither element nor any descendant has keyboard focus*).
        // 제목 줄의 오른쪽 끝을 눌러 커서를 `# New Note` 끝에 둔다.
        editor.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.04)).tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5), "키보드가 안 올라왔다")
        pause(0.8)
        shot(0.8, fade: true)
        editor.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: "New Note".count))
        shot(0.3)
        type(editor, [("To", 0.25), ("day", 0.6)])
        type(editor, [("\nWrite ", 0.3), ("in ", 0.25), ("plain ", 0.25), ("text. ", 0.35)])
        type(editor, [("Only ", 0.25), ("this ", 0.25), ("line ", 0.25), ("shows ", 0.3),
                      ("**", 0.3), ("marks", 0.3), ("**", 2.0)])
        type(editor, [("\n- [ ] ", 0.45), ("Read ", 0.25), ("it ", 0.25), ("later", 2.0)])

        // ② 목록으로 — 방금 쓴 노트가 맨 위에
        back(app)
        pause(1.0)
        shot(1.8, fade: true)

        // ③ 링크 모음 (읽기)
        app.staticTexts["Watch Later"].firstMatch.tap()
        waitForReading("Walk Slowly")
        shot(3.8, fade: true)
        back(app)
        pause(1.0)
        shot(0.6, fade: true)

        // ④ 검색 → 읽기 (사진 · 표)
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5), "검색 칸이 없다")
        search.tap()
        pause(1.0)
        shot(0.6, fade: true)
        type(search, [("Lis", 0.35), ("bon", 1.3)])
        app.staticTexts["Lisbon Trip"].firstMatch.tap()
        waitForReading("Day by day")
        shot(2.8, fade: true)
        app.webViews.firstMatch.swipeUp(velocity: .slow)
        pause(1.5)
        shot(3.4, fade: true)
    }

    /// 낱말 조각을 치고 그 화면을 찍는다 — 조각마다 보여 줄 길이와 함께.
    private func type(_ element: XCUIElement, _ pieces: [(String, Double)]) {
        for (piece, seconds) in pieces {
            element.typeText(piece)
            shot(seconds)
        }
    }

    /// **이 화면을 영상에 이만큼** — 이름에 차례 · 길이 · 넘기는 법을 적어 남긴다 (`PV_<차례>_<초>_<cut|fade>`).
    /// `stitch.py` 가 이름을 읽어 이어 붙인다. 화면이 다 그려지도록 조금 쉬고 찍는다.
    private func shot(_ seconds: Double, fade: Bool = false) {
        pause(0.4)
        count += 1
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = String(format: "PV_%03d_%.2f_%@", count, seconds, fade ? "fade" : "cut")
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func back(_ app: XCUIApplication) {
        app.navigationBars.buttons.element(boundBy: 0).tap()
    }

    /// 읽기 화면(웹 보기)에 이 글이 보일 때까지 — 그 뒤 그림이 화면에 칠해지도록 조금 더.
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
}
