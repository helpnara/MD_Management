import XCTest
@testable import Core

/// 파일명이 따라갈 제목의 규칙 (54). 기댓값은 규칙 그 자체다.
final class FirstHeadingTests: XCTestCase {

    func testFirstLineHeading() {
        XCTAssertEqual(FrontMatterParser.firstHeading(of: "# 여행 계획\n\n본문"), "여행 계획")
        XCTAssertEqual(FrontMatterParser.firstHeading(of: "\n\n# 빈 줄 뒤\n본문"), "빈 줄 뒤", "앞의 빈 줄은 건너뛴다")
        XCTAssertEqual(FrontMatterParser.firstHeading(of: "#   양끝 공백   \n"), "양끝 공백")
        XCTAssertEqual(FrontMatterParser.firstHeading(of: "# 닫는 표시 ##\n"), "닫는 표시")
    }

    func testSkipsFrontMatter() {
        XCTAssertEqual(FrontMatterParser.firstHeading(of: "---\ntitle: 머리말\n---\n# 본문 제목\n"), "본문 제목")
    }

    func testReplacesFirstHeading() {
        XCTAssertEqual(FrontMatterParser.replacingFirstHeading(in: "# 옛 제목\n\n본문", with: "새 제목"), "# 새 제목\n\n본문")
        XCTAssertEqual(FrontMatterParser.replacingFirstHeading(in: "\n# 옛 제목 ##\n본문", with: "새"), "\n# 새\n본문", "빈 줄과 본문은 그대로")
        XCTAssertEqual(FrontMatterParser.replacingFirstHeading(in: "---\ntitle: 머리말\n---\n# 옛\n본문", with: "새"),
                       "---\ntitle: 머리말\n---\n# 새\n본문", "머리말은 건드리지 않는다")
        XCTAssertNil(FrontMatterParser.replacingFirstHeading(in: "본문뿐\n# 나중", with: "새"), "첫 줄이 제목이 아니면 만들지 않는다")
        XCTAssertNil(FrontMatterParser.replacingFirstHeading(in: "", with: "새"))
    }

    func testAlignsToFileName() {
        XCTAssertNil(FrontMatterParser.aligned("# 여행\n\n본문\n", toFileName: "여행.md"), "이미 맞으면 안 쓴다")
        XCTAssertEqual(FrontMatterParser.aligned("본문뿐\n", toFileName: "여행.md"), "# 여행\n\n본문뿐\n", "제목이 없으면 파일명을 넣는다")
        XCTAssertEqual(FrontMatterParser.aligned("", toFileName: "빈 노트.md"), "# 빈 노트\n\n")
        XCTAssertEqual(FrontMatterParser.aligned("# 옛 제목\n\n글\n\n# 둘째\n", toFileName: "새 이름.md"),
                       "# 새 이름\n\n## 옛 제목\n\n글\n\n## 둘째\n", "다른 제목이면 파일명이 이기고 `#` 은 `##` 로")
        XCTAssertEqual(FrontMatterParser.aligned("---\ntitle: 머리말\n---\n# 옛\n글\n", toFileName: "새.md"),
                       "---\ntitle: 머리말\n---\n# 새\n\n## 옛\n글\n", "머리말은 그대로")
        XCTAssertEqual(FrontMatterParser.aligned("# 옛\n```\n# 코드 안\n```\n", toFileName: "새.md"),
                       "# 새\n\n## 옛\n```\n# 코드 안\n```\n", "코드 블록 안은 건드리지 않는다")
        XCTAssertEqual(FrontMatterParser.aligned("## 부제목뿐\n", toFileName: "새.md"), "# 새\n\n## 부제목뿐\n", "`##` 은 제목이 아니므로 위에 넣기만")
    }

    func testLeavesNumberedCopiesAlone() {
        XCTAssertNil(FrontMatterParser.aligned("# A\n\n본문\n", toFileName: "A 2.md"), "`A 2` 안의 `# A` 는 번호 붙은 사본")
        XCTAssertNil(FrontMatterParser.aligned("# 새 노트\n\n", toFileName: "새 노트 12.md"))
        XCTAssertNotNil(FrontMatterParser.aligned("# A\n", toFileName: "A 2b.md"), "숫자만이어야 사본이다")
        XCTAssertNotNil(FrontMatterParser.aligned("# A\n", toFileName: "A2.md"), "빈칸이 없으면 다른 이름이다")
        XCTAssertNotNil(FrontMatterParser.aligned("# B\n", toFileName: "A 2.md"), "밑동이 다르면 사본이 아니다")
    }

    func testNotAHeading() {
        XCTAssertNil(FrontMatterParser.firstHeading(of: "그냥 글\n# 나중 제목"), "첫 줄이 제목이 아니면 없다")
        XCTAssertNil(FrontMatterParser.firstHeading(of: "## 둘째 단계"), "`##` 은 보지 않는다")
        XCTAssertNil(FrontMatterParser.firstHeading(of: "#태그"), "`#` 뒤에 빈칸이 없으면 제목이 아니다")
        XCTAssertNil(FrontMatterParser.firstHeading(of: "# \n본문"), "빈 제목은 없다")
        XCTAssertNil(FrontMatterParser.firstHeading(of: ""))
    }
}
