import Foundation
import UIKit

/// 둘러보기 자료.
///
/// **실제 폴더에 샘플을 뿌리지 않는다.** 지난 앱에서 체험 자료가 동기화 자료와
/// 섞였다 (`LESSONS_LEARNED` §5). 여기서는 임시 디렉터리에 통째로 만들고, 앱을 끄면
/// OS 가 치운다. 화면에는 배너가 늘 떠 있다.
@MainActor
enum SampleFolder {

    static func make() -> URL {
        let root = FileManager.default.temporaryDirectory
            // 폴더 이름이 곧 화면 상단 제목이다 (설계서 §0). `sample-folder` 가
            // 제목으로 뜨던 것을 고쳤다 (빌드 2 스크린샷).
            .appendingPathComponent("둘러보기", isDirectory: true)
        try? FileManager.default.removeItem(at: root)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        let assets = root.appendingPathComponent("assets", isDirectory: true)
        try? FileManager.default.createDirectory(at: assets, withIntermediateDirectories: true)
        writePlaceholderImage(to: assets.appendingPathComponent("스케치.png"))

        write(sampleWelcome, to: root.appendingPathComponent("반가워요.md"))
        write(sampleMeeting, to: root.appendingPathComponent("2026-09-13 회의.md"))

        let ideas = root.appendingPathComponent("아이디어", isDirectory: true)
        try? FileManager.default.createDirectory(at: ideas, withIntermediateDirectories: true)
        write(sampleIdea, to: ideas.appendingPathComponent("앱 구상.md"))

        return root
    }

    private static func write(_ text: String, to url: URL) {
        try? text.write(to: url, atomically: true, encoding: .utf8)
    }

    /// 사진첩을 안 쓰고 그림 하나를 만든다 — CI 에서도 이미지 링크가 살아 있어야 한다.
    private static func writePlaceholderImage(to url: URL) {
        let size = CGSize(width: 640, height: 360)
        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { context in
            UIColor.secondarySystemBackground.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            UIColor.tertiaryLabel.setStroke()
            let path = UIBezierPath()
            path.lineWidth = 6
            path.move(to: CGPoint(x: 80, y: 260))
            path.addCurve(to: CGPoint(x: 560, y: 110),
                          controlPoint1: CGPoint(x: 240, y: 40),
                          controlPoint2: CGPoint(x: 380, y: 330))
            path.stroke()
        }
        try? image.pngData()?.write(to: url)
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
    ```
    """

    private static let sampleIdea = """
    # 앱 구상

    하위 폴더 안의 노트입니다. [회의 기록](<../2026-09-13 회의.md>) 처럼 옆 노트를
    링크하면, 공유할 때 한 단계까지 같이 묶입니다.

    ---

    *기울임* 과 **굵게** 와 `인라인 코드` 가 어떻게 보이는지 보세요.
    """
}
