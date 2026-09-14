import XCTest
@testable import Core

/// 파일명이 따라갈 제목의 규칙 (54). 기댓값은 규칙 그 자체다.
final class FirstHeadingTests: XCTestCase {

    func testFirstLineHeading() {
        XCTAssertEqual(FrontMatter.firstHeading(of: "# 여행 계획\n\n본문"), "여행 계획")
        XCTAssertEqual(FrontMatter.firstHeading(of: "\n\n# 빈 줄 뒤\n본문"), "빈 줄 뒤", "앞의 빈 줄은 건너뛴다")
        XCTAssertEqual(FrontMatter.firstHeading(of: "#   양끝 공백   \n"), "양끝 공백")
        XCTAssertEqual(FrontMatter.firstHeading(of: "# 닫는 표시 ##\n"), "닫는 표시")
    }

    func testSkipsFrontMatter() {
        XCTAssertEqual(FrontMatter.firstHeading(of: "---\ntitle: 머리말\n---\n# 본문 제목\n"), "본문 제목")
    }

    func testNotAHeading() {
        XCTAssertNil(FrontMatter.firstHeading(of: "그냥 글\n# 나중 제목"), "첫 줄이 제목이 아니면 없다")
        XCTAssertNil(FrontMatter.firstHeading(of: "## 둘째 단계"), "`##` 은 보지 않는다")
        XCTAssertNil(FrontMatter.firstHeading(of: "#태그"), "`#` 뒤에 빈칸이 없으면 제목이 아니다")
        XCTAssertNil(FrontMatter.firstHeading(of: "# \n본문"), "빈 제목은 없다")
        XCTAssertNil(FrontMatter.firstHeading(of: ""))
    }
}
