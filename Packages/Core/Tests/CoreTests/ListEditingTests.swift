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

    /// 빈 항목에서 엔터 — **얕은 위 줄의 칸까지** 나온다 (141 뒷이야기).
    ///
    /// 사례와 기댓값은 `EnterGoldenTests` 가 파이썬 대조로 지킨다. 여기서는 **문맥이
    /// 없을 때** 무엇을 하는지만 본다 — 나올 데가 없으면 마커를 지운다.
    func testEmptyItemEndsWhenThereIsNowhereToGo() {
        XCTAssertEqual(ListEditing.returnPressed(in: "- "), .replacePrefix(length: 2, with: ""),
                       "최상위 빈 항목 → 보통 글")
        XCTAssertEqual(ListEditing.returnPressed(in: "1. "), .replacePrefix(length: 3, with: ""))
        XCTAssertEqual(ListEditing.returnPressed(in: "- [ ] "), .replacePrefix(length: 6, with: ""))
        // **얕은 위 줄이 없으면 맨 앞까지 나온다.** 빈칸 둘씩 야금야금이 아니다 — 위에
        // 아무것도 없는데 중간 칸에 서면 그 칸은 어느 단계도 아니다.
        XCTAssertEqual(ListEditing.returnPressed(in: "    - "), .replacePrefix(length: 6, with: "- "),
                       "문맥이 없으면 맨 앞으로")
        XCTAssertEqual(ListEditing.returnPressed(in: "    - 셋째"), .insert("\n    - "),
                       "글이 있으면 셋째 단계에서도 다음 항목을 이어 준다")
    }

    func testPlainParagraphIsNotHandled() {
        XCTAssertNil(ListEditing.returnPressed(in: "그냥 글"))
        XCTAssertNil(ListEditing.returnPressed(in: "# 제목"))
        XCTAssertNil(ListEditing.returnPressed(in: "> 인용"))
        XCTAssertNil(ListEditing.returnPressed(in: ""))
    }
}
