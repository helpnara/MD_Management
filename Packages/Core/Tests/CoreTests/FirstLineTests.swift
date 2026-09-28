import XCTest
@testable import Core

/// **첫 줄이 곧 파일명** (T6, 2026-09-16 사용자 결정). 기댓값은 규칙 그 자체다.
///
/// 예전에는 `# 제목` 을 요구했고, 그래서 반대 방향(파일명이 본문을 이긴다)이 필요했다.
/// 자료 사고가 전부 거기서 나왔으므로 그 방향을 없앴다 — **이제 앱은 본문을 고치지 않는다.**
final class FirstLineTests: XCTestCase {

    func testFirstLineWithoutMarker() {
        XCTAssertEqual(FrontMatterParser.firstLine(of: "팀 이슈회의\n\n본문"), "팀 이슈회의",
                       "`#` 을 치지 않아도 된다")
        XCTAssertEqual(FrontMatterParser.firstLine(of: "\n\n  빈 줄 뒤  \n본문"), "빈 줄 뒤",
                       "앞의 빈 줄과 양끝 공백은 뗀다")
        XCTAssertNil(FrontMatterParser.firstLine(of: ""))
        XCTAssertNil(FrontMatterParser.firstLine(of: "\n\n   \n"))
    }

    func testFirstLineWithMarker() {
        XCTAssertEqual(FrontMatterParser.firstLine(of: "# 여행 계획\n\n본문"), "여행 계획",
                       "마커가 있으면 뗀다 — 예전 노트가 그대로 동작한다")
        XCTAssertEqual(FrontMatterParser.firstLine(of: "### 셋째 단계\n"), "셋째 단계")
        XCTAssertEqual(FrontMatterParser.firstLine(of: "# 닫는 표시 ##\n"), "닫는 표시")
        XCTAssertEqual(FrontMatterParser.firstLine(of: "#태그만 있는 줄"), "#태그만 있는 줄",
                       "`#` 뒤에 빈칸이 없으면 마커가 아니다 (CommonMark)")
        XCTAssertEqual(FrontMatterParser.firstLine(of: "####### 일곱 개"), "####### 일곱 개",
                       "여섯 개까지만 마커다")
    }

    func testSkipsFrontMatter() {
        XCTAssertEqual(FrontMatterParser.firstLine(of: "---\ntitle: 머리말\n---\n본문 첫 줄\n"), "본문 첫 줄")
        XCTAssertEqual(FrontMatterParser.firstLine(of: "---\ntitle: 머리말\n---\n# 본문 제목\n"), "본문 제목")
    }

    func testReplacesFirstLine() {
        XCTAssertEqual(FrontMatterParser.replacingFirstLine(in: "# 옛 제목\n\n본문", with: "새 제목"),
                       "# 새 제목\n\n본문", "마커는 그대로 두고 글자만")
        XCTAssertEqual(FrontMatterParser.replacingFirstLine(in: "옛 제목\n\n본문", with: "새 제목"),
                       "새 제목\n\n본문", "마커가 없으면 만들지 않는다")
        XCTAssertEqual(FrontMatterParser.replacingFirstLine(in: "\n## 옛\n본문", with: "새"),
                       "\n## 새\n본문", "빈 줄과 단계는 그대로")
        XCTAssertEqual(FrontMatterParser.replacingFirstLine(in: "---\ntitle: 머리말\n---\n옛\n본문", with: "새"),
                       "---\ntitle: 머리말\n---\n새\n본문", "머리말은 건드리지 않는다")
        XCTAssertNil(FrontMatterParser.replacingFirstLine(in: "", with: "새"), "쓸 줄이 없으면 만들지 않는다")
    }

    /// 목록에 보여 줄 제목 — 머리말 → 첫 줄 → 파일명.
    func testTitleFallsBack() {
        XCTAssertEqual(FrontMatterParser.title(of: "---\ntitle: 머리말\n---\n첫 줄", fileName: "파일.md"), "머리말")
        XCTAssertEqual(FrontMatterParser.title(of: "첫 줄", fileName: "파일.md"), "첫 줄")
        XCTAssertEqual(FrontMatterParser.title(of: "# 첫 줄", fileName: "파일.md"), "첫 줄")
        XCTAssertEqual(FrontMatterParser.title(of: "", fileName: "파일.md"), "파일")
    }
}
