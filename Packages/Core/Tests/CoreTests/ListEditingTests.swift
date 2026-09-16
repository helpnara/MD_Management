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
        // **세 단계 이상도 이어진다** (T4, 빌드 34). 빌드 9 부터 빌드 33 까지는 여기서
        // `nil` 이었다 — 빈칸 네 개를 CommonMark 가 코드로 읽기 때문이다. 그러나 그것은
        // **앞 줄이 목록이라는 문맥이 없을 때** 이야기고, 파일에서는 겹친 항목이 맞다.
        // 이제 목록 마커가 네 칸 규칙을 이긴다 (`LineStyler.startsListItem`).
        XCTAssertEqual(ListEditing.returnPressed(in: "    - "), .replacePrefix(length: 6, with: "  - "),
                       "셋째 단계 빈 항목 → 둘째 단계로")
        XCTAssertEqual(ListEditing.returnPressed(in: "    - 셋째"), .insert("\n    - "),
                       "셋째 단계에서도 다음 항목을 이어 준다")
    }

    func testPlainParagraphIsNotHandled() {
        XCTAssertNil(ListEditing.returnPressed(in: "그냥 글"))
        XCTAssertNil(ListEditing.returnPressed(in: "# 제목"))
        XCTAssertNil(ListEditing.returnPressed(in: "> 인용"))
        XCTAssertNil(ListEditing.returnPressed(in: ""))
    }
}
