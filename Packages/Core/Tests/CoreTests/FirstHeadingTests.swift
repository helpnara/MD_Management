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

    func testNotAHeading() {
        XCTAssertNil(FrontMatterParser.firstHeading(of: "그냥 글\n# 나중 제목"), "첫 줄이 제목이 아니면 없다")
        XCTAssertNil(FrontMatterParser.firstHeading(of: "## 둘째 단계"), "`##` 은 보지 않는다")
        XCTAssertNil(FrontMatterParser.firstHeading(of: "#태그"), "`#` 뒤에 빈칸이 없으면 제목이 아니다")
        XCTAssertNil(FrontMatterParser.firstHeading(of: "# \n본문"), "빈 제목은 없다")
        XCTAssertNil(FrontMatterParser.firstHeading(of: ""))
    }
}
