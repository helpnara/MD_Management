import XCTest
@testable import Core

/// 여기 기댓값은 **설계서에 적힌 규칙 그 자체**다 (계산 결과가 아니다).
/// 계산 결과가 걸린 것은 `GoldenTests` 가 파이썬과 대조한다.
final class PathsTests: XCTestCase {

    func testFileExtension() {
        XCTAssertEqual(Paths.fileExtension("회의.md"), "md")
        XCTAssertEqual(Paths.fileExtension("아이디어/앱 구상.MARKDOWN"), "markdown")
        XCTAssertEqual(Paths.fileExtension("assets/a.PNG"), "png")
        XCTAssertEqual(Paths.fileExtension("확장자없음"), "")
        XCTAssertEqual(Paths.fileExtension(".gitignore"), "", "점으로 시작하는 이름은 확장자가 없다")
        XCTAssertEqual(Paths.fileExtension("a.b/c"), "", "마지막 조각에 점이 없으면 확장자가 없다")
    }

    func testNoteAndMarkdownFiles() {
        XCTAssertTrue(Paths.isNoteFile("a.md"))
        XCTAssertTrue(Paths.isNoteFile("a.txt"), ".txt 도 편집한다 (설계서 §14-2)")
        XCTAssertFalse(Paths.isNoteFile("a.png"))

        XCTAssertTrue(Paths.isMarkdownFile("a.markdown"))
        XCTAssertFalse(Paths.isMarkdownFile("a.txt"), "공유할 때 .txt 는 따라가지 않는다")
    }

    func testHiddenFolders() {
        XCTAssertTrue(Paths.isHidden(".obsidian/config"), "옵시디언 볼트를 열어도 목록을 안 어지럽힌다 (A6)")
        XCTAssertTrue(Paths.isHidden(".trash/지운 것.md"))
        XCTAssertTrue(Paths.isHidden("아이디어/.git/HEAD"))
        XCTAssertFalse(Paths.isHidden("아이디어/앱 구상.md"))
    }

    func testDirectoryOf() {
        XCTAssertEqual(Paths.directory(of: "회의/2026-09-13.md"), "회의")
        XCTAssertEqual(Paths.directory(of: "a/b/c.md"), "a/b")
        XCTAssertEqual(Paths.directory(of: "최상위.md"), "")
    }

    func testJoinStaysInsideFolder() {
        XCTAssertEqual(Paths.join(base: "회의", relative: "assets/a.png"), "회의/assets/a.png")
        XCTAssertEqual(Paths.join(base: "회의", relative: "./assets/a.png"), "회의/assets/a.png")
        XCTAssertEqual(Paths.join(base: "회의/하위", relative: "../a.png"), "회의/a.png")
        XCTAssertEqual(Paths.join(base: "", relative: "a.png"), "a.png")
    }

    func testJoinRefusesToEscape() {
        XCTAssertNil(Paths.join(base: "", relative: "../a.png"),
            "폴더 밖으로 나가면 nil — zip 에 들어가면 받는 쪽에서 다른 폴더를 덮는다")
        XCTAssertNil(Paths.join(base: "회의", relative: "../../etc/passwd"))
    }

    func testSchemeDetection() {
        XCTAssertTrue(Paths.hasScheme("https://example.com"))
        XCTAssertTrue(Paths.hasScheme("mailto:me@example.com"))
        XCTAssertTrue(Paths.hasScheme("yb://note/a.md"))
        XCTAssertFalse(Paths.hasScheme("assets/a.png"))
        XCTAssertFalse(Paths.hasScheme("2026-09-13 10:30.md"),
            "공백이 있으면 스킴이 아니다 — 시각이 든 파일명을 외부 링크로 보면 안 된다")
        XCTAssertFalse(Paths.hasScheme("://a"))
    }

    func testResolveAnchorsAndEmpty() {
        XCTAssertEqual(Paths.resolve(link: "#머리말", fromNoteAt: "a.md"), .empty)
        XCTAssertEqual(Paths.resolve(link: "   ", fromNoteAt: "a.md"), .empty)
        XCTAssertEqual(Paths.resolve(link: "b.md#절", fromNoteAt: "a.md"), .relative("b.md"))
        XCTAssertEqual(Paths.resolve(link: "https://a.com/x#y", fromNoteAt: "a.md"),
                       .external("https://a.com/x#y"),
                       "외부 URL 의 # 은 앵커가 아니라 URL 의 일부다")
    }

    func testResolveDecodesPercentEncoding() {
        XCTAssertEqual(
            Paths.resolve(link: "assets/%EB%82%B4%20%EC%82%AC%EC%A7%84.jpg", fromNoteAt: "a.md"),
            .relative("assets/내 사진.jpg"))
    }

    func testResolveNormalizesToNFC() {
        // 자모가 분리된 채로 적힌 링크. iCloud · Files · 옵시디언이 이렇게 넘긴다.
        let nfd = "assets/\u{110B}\u{1162}\u{11B8}.png"          // NFD 로 적은 "앱.png"
        let nfc = "assets/\u{C571}.png"                          // NFC
        XCTAssertEqual(Paths.resolve(link: nfd, fromNoteAt: "a.md"), .relative(nfc),
            "NFC 로 안 맞추면 한글 이름 첨부가 전부 깨진 링크가 된다 (A13 · S13)")
    }

    func testResolveAngleBrackets() {
        XCTAssertEqual(Paths.resolve(link: "<assets/내 사진.jpg>", fromNoteAt: "a.md"),
                       .relative("assets/내 사진.jpg"))
    }

    func testResolveRefusesToEscapeFolder() {
        XCTAssertEqual(Paths.resolve(link: "../바깥.png", fromNoteAt: "a.md"), .outside("../바깥.png"))
        XCTAssertEqual(Paths.resolve(link: "/etc/passwd", fromNoteAt: "a.md"), .absolute("/etc/passwd"))
    }

    func testSafeFileName() {
        XCTAssertEqual(Paths.safeFileName("회의/기록"), "회의-기록")
        XCTAssertEqual(Paths.safeFileName("a:b*c?d\"e<f>g|h"), "a-b-c-d-e-f-g-h")
        XCTAssertEqual(Paths.safeFileName("  제목  "), "제목")
        XCTAssertEqual(Paths.safeFileName("끝에 점..."), "끝에 점")
        XCTAssertEqual(Paths.safeFileName(""), "제목 없음")
        // `///` 는 `---` 가 된다 — 구분 기호만 남으면 이름이 아니다.
        XCTAssertEqual(Paths.safeFileName("///"), "제목 없음")
        XCTAssertEqual(Paths.safeFileName(" - _ . "), "제목 없음")
        XCTAssertEqual(Paths.safeFileName("2026-09-13"), "2026-09-13", "숫자가 섞이면 멀쩡한 이름이다")
        XCTAssertEqual(Paths.safeFileName("여러   칸"), "여러 칸")
    }

    func testTruncateCountsUTF8Bytes() {
        // 한글 한 글자가 UTF-8 로 3바이트다.
        XCTAssertEqual(Paths.truncate("가나다라", maxUTF8Bytes: 9), "가나다")
        XCTAssertEqual(Paths.truncate("가나다라", maxUTF8Bytes: 8), "가나",
            "글자 중간에서 자르지 않는다")
        XCTAssertEqual(Paths.truncate("abc", maxUTF8Bytes: 10), "abc")
    }
}

extension PathsTests {
    func testBaseName() {
        XCTAssertEqual(Paths.baseName("회의/2026-09-13 회의.md"), "2026-09-13 회의")
        XCTAssertEqual(Paths.baseName("확장자없음"), "확장자없음")
        XCTAssertEqual(Paths.baseName(".gitignore"), ".gitignore")
    }

    /// `파일` 앱이 건넨 파일이 내 폴더의 것인가.
    func testRelativeUnderRoot() {
        let root = "/var/mobile/Containers/느린 여백/Documents"

        XCTAssertEqual(Paths.relative(of: root + "/회의/2026.md", under: root), "회의/2026.md")
        XCTAssertEqual(Paths.relative(of: root + "/첫 노트.md", under: root), "첫 노트.md")

        // 끝의 빗금 · 겹친 빗금은 조각으로 자르면 사라진다.
        XCTAssertEqual(Paths.relative(of: root + "//회의//2026.md", under: root + "/"), "회의/2026.md")

        // **앞부분만 같은 남의 폴더.** 글자로 견주면 여기서 뚫린다.
        XCTAssertNil(Paths.relative(of: "/a/bc/note.md", under: "/a/b"))
        XCTAssertNil(Paths.relative(of: "/다른 곳/note.md", under: root))

        // 폴더 자기 자신은 그 안의 파일이 아니다.
        XCTAssertNil(Paths.relative(of: root, under: root))

        // 한글 이름이 NFD 로 와도 같은 폴더로 본다 (A13).
        let nfd = (root + "/회의/2026.md").decomposedStringWithCanonicalMapping
        XCTAssertEqual(Paths.relative(of: nfd, under: root), "회의/2026.md")
    }
}
