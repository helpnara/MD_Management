import XCTest
@testable import Core

/// 골든 대조(`GoldenTests`)가 실제 본문으로 검사하고, 여기서는 **경계 규칙**을 본다.
final class ShareBundleTests: XCTestCase {

    func testNoAttachmentsGivesSingleMarkdownFile() {
        let plan = ShareBundle.plan(
            notePath: "회의.md",
            noteText: "# 회의\n\n첨부가 없다.",
            exists: { _ in true })
        XCTAssertEqual(plan.mode, .mdOnly)
        XCTAssertEqual(plan.includes, ["회의.md"])
        XCTAssertTrue(plan.missing.isEmpty)
    }

    func testNoteIsAlwaysFirst() {
        let plan = ShareBundle.plan(
            notePath: "회의.md",
            noteText: "![](assets/a.png)",
            exists: { _ in true })
        XCTAssertEqual(plan.includes.first, "회의.md")
    }

    func testMissingAttachmentIsReportedNotSilentlyDropped() {
        let plan = ShareBundle.plan(
            notePath: "회의.md",
            noteText: "![](assets/없다.png)",
            exists: { _ in false })
        XCTAssertEqual(plan.mode, .mdOnly)
        XCTAssertEqual(plan.missing, ["assets/없다.png"],
            "조용히 빠뜨리지 않는다 — 보내기 전에 알린다 (설계서 §7.6-4)")
    }

    func testParentEscapeIsBlocked() {
        let plan = ShareBundle.plan(
            notePath: "회의.md",
            noteText: "![](../../etc/passwd)",
            exists: { _ in true })
        XCTAssertEqual(plan.includes, ["회의.md"], "폴더 밖은 절대 넣지 않는다")
        XCTAssertEqual(plan.missing, ["../../etc/passwd"])
    }

    func testExternalLinksAreIgnored() {
        let plan = ShareBundle.plan(
            notePath: "회의.md",
            noteText: "[사이트](https://example.com/a.png) [메일](mailto:a@b.c) [절대](/etc/hosts)",
            exists: { _ in true })
        XCTAssertEqual(plan.mode, .mdOnly)
        XCTAssertTrue(plan.missing.isEmpty)
    }

    func testDuplicateLinksAreIncludedOnce() {
        let plan = ShareBundle.plan(
            notePath: "회의.md",
            noteText: "![](assets/a.png)\n\n![또](assets/a.png)",
            exists: { _ in true })
        XCTAssertEqual(plan.includes, ["회의.md", "assets/a.png"])
    }

    func testLinkedNotesAreFollowedOneLevelOnly() {
        // A 가 B 를 링크하면 B 는 넣되, B 가 링크하는 C 는 넣지 않는다.
        // (B 의 본문을 아예 읽지 않으므로 구조적으로 한 단계다.)
        let plan = ShareBundle.plan(
            notePath: "A.md",
            noteText: "[B](B.md)",
            exists: { _ in true })
        XCTAssertEqual(plan.includes, ["A.md", "B.md"])
    }

    func testLinkedNotesCanBeTurnedOff() {
        let plan = ShareBundle.plan(
            notePath: "A.md",
            noteText: "[B](B.md)\n\n![](assets/a.png)",
            followLinkedNotes: false,
            exists: { _ in true })
        XCTAssertEqual(plan.includes, ["A.md", "assets/a.png"],
            "설정에서 끄면 .md 링크는 안 따라가되 첨부는 그대로 넣는다")
    }

    func testArchiveNameIsSafe() {
        XCTAssertEqual(ShareBundle.archiveName(forTitle: "2026/09 회의"), "2026-09 회의")
    }
}
