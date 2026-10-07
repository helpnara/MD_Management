import Foundation
import UIKit

/// 둘러보기 자료.
///
/// **실제 폴더에 샘플을 뿌리지 않는다.** 지난 앱에서 체험 자료가 동기화 자료와
/// 섞였다 (`LESSONS_LEARNED` §5). 여기서는 임시 디렉터리에 통째로 만들고, 앱을 끄면
/// OS 가 치운다. 화면에는 배너가 늘 떠 있다.
@MainActor
enum SampleFolder {

    /// 견본 한 벌 — 폴더 · 파일 이름과 글. **이름도 글이다** (219) — 영어 화면에 한국어 파일 이름이 서면 견본이 아니다.
    private struct SampleSet {
        let folder, image, welcome, meeting, ideas, idea: String
        let welcomeText, meetingText, ideaText: String
    }

    private static let korean = SampleSet(
        folder: "둘러보기", image: "스케치.png", welcome: "반가워요.md", meeting: "2026-09-13 회의.md",
        ideas: "아이디어", idea: "앱 구상.md",
        welcomeText: sampleWelcome, meetingText: sampleMeeting, ideaText: sampleIdea)

    private static let english = SampleSet(
        folder: "Sample Notes", image: "sketch.png", welcome: "Welcome.md", meeting: "2026-09-13 Meeting.md",
        ideas: "Ideas", idea: "App Concept.md",
        welcomeText: englishWelcome, meetingText: englishMeeting, ideaText: englishIdea)

    static func make() -> URL {
        // 앱이 지금 보여 주는 언어를 따른다 — 화면 문구와 같은 판단(`AppLanguage`)이다.
        let set = AppLanguage.isEnglish ? english : korean
        let root = FileManager.default.temporaryDirectory
            // 폴더 이름이 곧 화면 상단 제목이다 (설계서 §0). `sample-folder` 가
            // 제목으로 뜨던 것을 고쳤다 (빌드 2 스크린샷).
            .appendingPathComponent(set.folder, isDirectory: true)
        try? FileManager.default.removeItem(at: root)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        let assets = root.appendingPathComponent("assets", isDirectory: true)
        try? FileManager.default.createDirectory(at: assets, withIntermediateDirectories: true)
        writePlaceholderImage(to: assets.appendingPathComponent(set.image))

        write(set.welcomeText, to: root.appendingPathComponent(set.welcome))
        write(set.meetingText, to: root.appendingPathComponent(set.meeting))

        let ideas = root.appendingPathComponent(set.ideas, isDirectory: true)
        try? FileManager.default.createDirectory(at: ideas, withIntermediateDirectories: true)
        write(set.ideaText, to: ideas.appendingPathComponent(set.idea))

        return root
    }

    private static func write(_ text: String, to url: URL) {
        try? text.write(to: url, atomically: true, encoding: .utf8)
    }

    /// 사진첩 없이 만든 그림.
    static func placeholderPNG() -> Data? {
        renderPlaceholder().pngData()
    }

    /// 첨부 시험용 — **납작하게** 만든다. 셋이 한 화면에 들어와야
    /// 어느 것이 안 보이는지 한눈에 갈린다 (진단 화면의 버튼 · CI 스크린샷).
    static func testPNG() -> Data? {
        renderPlaceholder(size: CGSize(width: 640, height: 150)).pngData()
    }

    /// 사진첩을 안 쓰고 그림 하나를 만든다 — CI 에서도 이미지 링크가 살아 있어야 한다.
    private static func writePlaceholderImage(to url: URL) {
        try? renderPlaceholder().pngData()?.write(to: url)
    }

    private static func renderPlaceholder(size: CGSize = CGSize(width: 640, height: 360)) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { context in
            UIColor.secondarySystemBackground.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            UIColor.tertiaryLabel.setStroke()
            // 크기가 달라져도 같은 모양이 나오게 비율로 그린다.
            let path = UIBezierPath()
            path.lineWidth = max(4, size.height / 60)
            path.move(to: CGPoint(x: size.width * 0.125, y: size.height * 0.72))
            path.addCurve(to: CGPoint(x: size.width * 0.875, y: size.height * 0.30),
                          controlPoint1: CGPoint(x: size.width * 0.375, y: size.height * 0.11),
                          controlPoint2: CGPoint(x: size.width * 0.594, y: size.height * 0.92))
            path.stroke()
        }
        return image
    }

    // 곧은 따옴표를 쓰지 않는다 — 지난 앱에서 빌드 시스템이 같은 자리에서 두 번 죽었다.

    private static let sampleWelcome = """
    # 반가워요

    이것은 **둘러보기 자료**입니다. 실제 폴더에는 아무것도 만들지 않았습니다.

    화면 위 배너가 보이는 동안은 전부 임시 자료입니다. 앱을 끄면 사라집니다.

    ## 여기서 해 볼 것

    - [ ] 줄을 눌러 커서를 놓아 보기 — 그 줄만 마크다운 원문으로 바뀝니다
    - [ ] 위 `읽기` 를 눌러 표와 코드가 어떻게 보이는지 보기
    - [x] 목록을 훑어보기

    | 하는 것 | 어디서 |
    |---|---|
    | 보기 · 고치기 | 파일을 열면 바로 |
    | 찾기 | 아래 검색 |
    | 보내기 | 위 공유 |

    > 파일은 당신의 것입니다. 앱을 지워도 자료는 그대로 남습니다.
    """

    private static let sampleMeeting = """
    ---
    title: 2026-09-13 회의
    tags: [회의, 기획]
    created: 2026-09-13
    ---

    # 2026-09-13 회의

    ![스케치](assets/스케치.png)

    ## 정한 것

    1. 파일이 원본이다 — 앱 안에 자료를 따로 두지 않는다
    2. 검색은 두 글자부터 된다
    3. 공유하면 파일 하나만 간다

    ## 다음에 볼 것

    - [ ] 실기기에서 한글 조합 확인
    - [ ] 아이패드 3단 화면

    ```swift
    // 코드 블록은 고정폭 그대로 보여 준다
    let note = try store.readText(at: "2026-09-13 회의.md")
    let summary = note.split(separator: "\\n").filter { !$0.isEmpty }.prefix(3).joined(separator: " / ") // 긴 줄은 화면 폭에서 접힌다
    ```
    """

    private static let sampleIdea = """
    # 앱 구상

    하위 폴더 안의 노트입니다. [회의 기록](<../2026-09-13 회의.md>) 처럼 옆 노트를
    링크하면, 공유할 때 한 단계까지 같이 묶입니다.

    ---

    *기울임* 과 **굵게** 와 `인라인 코드` 가 어떻게 보이는지 보세요.
    """

    // MARK: - 영어 견본 (219) — 한국어 견본과 같은 자리에 같은 것을 둔다 (목록 · 표 · 체크상자 · 사진 · 코드 · 링크).
    // 따옴표는 둥근 것(’)만 쓴다 — 곧은 따옴표 규칙(CLAUDE.md §5).

    private static let englishWelcome = """
    # Welcome

    These are **sample notes**. Nothing has been added to your own folders.

    Everything here is temporary while the banner at the top is showing. It goes away when you close the app.

    ## Things to try

    - [ ] Tap a line to place the cursor — only that line shows its Markdown
    - [ ] Tap the book icon at the top to see how tables and code look
    - [x] Browse the list

    | What | Where |
    |---|---|
    | View and edit | Open any note |
    | Find | Search below |
    | Send | Share at the top |

    > Your files are yours. Delete the app and they stay right where they are.
    """

    private static let englishMeeting = """
    ---
    title: 2026-09-13 Meeting
    tags: [meeting, planning]
    created: 2026-09-13
    ---

    # 2026-09-13 Meeting

    ![Sketch](assets/sketch.png)

    ## Decisions

    1. Files are the source of truth — the app keeps no copy of its own
    2. Search works from two characters
    3. Sharing sends a single file

    ## Next steps

    - [ ] Test typing on a real device
    - [ ] Three-column layout on iPad

    ```swift
    // Code blocks keep their fixed-width font
    let note = try store.readText(at: "2026-09-13 Meeting.md")
    let summary = note.split(separator: "\\n").filter { !$0.isEmpty }.prefix(3).joined(separator: " / ") // long lines wrap to the screen width
    ```
    """

    private static let englishIdea = """
    # App Concept

    This note lives in a subfolder. Link to a nearby note, like the [meeting notes](<../2026-09-13 Meeting.md>),
    and it travels along when you share — one level deep.

    ---

    See how *italic*, **bold**, and `inline code` look.
    """
}

/// 앱이 지금 보여 주는 언어 (219). 화면 문구는 번역 목록이 고르고, 앱이 **스스로 짓는 글**(견본 · 첫 노트)은 이것을 본다 —
/// 같은 판단이어야 영어 화면에 한국어 견본이 서지 않는다. 기기 언어가 아니라 **이 앱의 언어**다 (설정 → 앱 → 언어).
enum AppLanguage {
    static var isEnglish: Bool {
        Bundle.main.preferredLocalizations.first?.hasPrefix("en") == true
    }
}
