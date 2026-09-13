import XCTest
@testable import Core

/// 여기 기댓값은 **규칙 그 자체**다 (아이폰 메모의 개요 입력을 따른다).
final class ListEditingTests: XCTestCase {

    func testContinuesBulletList() {
        XCTAssertEqual(ListEditing.returnPressed(in: "- 항목"), .insert("\n- "))
        XCTAssertEqual(ListEditing.returnPressed(in: "* 항목"), .insert("\n* "))
        XCTAssertEqual(ListEditing.returnPressed(in: "  - 안쪽"), .insert("\n  - "), "겹친 단계를 지킨다")
    }

    func testIncrementsOrderedList() {
        XCTAssertEqual(ListEditing.returnPressed(in: "1. 첫째"), .insert("\n2. "))
        XCTAssertEqual(ListEditing.returnPressed(in: "9) 아홉"), .insert("\n10) "))
        XCTAssertEqual(ListEditing.returnPressed(in: "  3. 안쪽"), .insert("\n  4. "))
    }

    func testChecklistStartsUnchecked() {
        XCTAssertEqual(ListEditing.returnPressed(in: "- [x] 한 일"), .insert("\n- [ ] "))
        XCTAssertEqual(ListEditing.returnPressed(in: "- [ ] 할 일"), .insert("\n- [ ] "))
    }

    func testEmptyItemEndsOrOutdents() {
        XCTAssertEqual(ListEditing.returnPressed(in: "- "), .replacePrefix(length: 2, with: ""),
                       "최상위 빈 항목 → 보통 글")
        XCTAssertEqual(ListEditing.returnPressed(in: "1. "), .replacePrefix(length: 3, with: ""))
        XCTAssertEqual(ListEditing.returnPressed(in: "- [ ] "), .replacePrefix(length: 6, with: ""))
        XCTAssertEqual(ListEditing.returnPressed(in: "  - "), .replacePrefix(length: 4, with: "- "),
                       "겹친 빈 항목 → 한 단계 위로")
        // 빈칸 네 개부터는 CommonMark 가 **코드 블록**으로 읽는다 — 문단 하나만 보는
        // `LineStyler` 도 그렇게 판정한다 (ADR-0005 의 "겹친 블록은 L1 범위 밖").
        // 그래서 세 단계 이상 겹친 목록은 여기서 잇지 않는다. 빌드 9 CI 가 잡았다.
        XCTAssertNil(ListEditing.returnPressed(in: "    - "))
    }

    func testPlainParagraphIsNotHandled() {
        XCTAssertNil(ListEditing.returnPressed(in: "그냥 글"))
        XCTAssertNil(ListEditing.returnPressed(in: "# 제목"))
        XCTAssertNil(ListEditing.returnPressed(in: "> 인용"))
        XCTAssertNil(ListEditing.returnPressed(in: ""))
    }
}
