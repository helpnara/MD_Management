import XCTest
@testable import Core

/// 162 — **원문이 드러난 줄과 기억이 갈리지 않는가.**
///
/// 기댓값을 손으로 적지 않는다. 여기서 재는 것은 **성질**이다:
///
/// 1. 원문이 드러난 줄은 **많아야 하나**
/// 2. **화면과 기억이 같다** — 드러난 줄을 아무도 못 지우게 되는 일이 없다
/// 3. 칠할 수 있었으면 **커서를 따라간다**
///
/// 화면을 **집합**으로 흉내 낸다. 줄이 둘 이상 드러날 수 있어야 162 를 표현할 수 있다 —
/// 표현 못 하는 시험은 통과해도 아무 말을 안 한 것이다.
///
/// 같은 걸음을 `Tools/golden/marker_focus.py` 가 리눅스 세션에서 먼저 돌린다. 거기서
/// **옛 규칙이 걸리는 것**을 보고 왔다 (걸음 `초점 없음 → 초점 없음 → A → 조합 중 초점 이탈`).
final class MarkerFocusTests: XCTestCase {

    private static let a = MarkerFocus.Span(start: 0, length: 10)
    private static let b = MarkerFocus.Span(start: 10, length: 8)

    /// 한 걸음에 일어날 수 있는 일.
    private enum Step {
        case plan(MarkerFocus.Span?, Bool)   // 커서 자리 · 지금 칠할 수 있나
        case wholeRepaint(MarkerFocus.Span?) // 글을 통째로 다시 칠했다
        case nudge                           // 다음에는 반드시 다시 칠한다
    }

    private static let steps: [Step] = {
        let cursors: [MarkerFocus.Span?] = [nil, MarkerFocusTests.a, MarkerFocusTests.b]
        var all: [Step] = []
        for cursor in cursors {
            all.append(.plan(cursor, true))
            all.append(.plan(cursor, false))
            all.append(.wholeRepaint(cursor))
        }
        all.append(.nudge)
        return all
    }()

    /// **모든 갈래를 걸어 본다.** 10 가지 × 4 걸음 = 10,000 갈래.
    func testScreenAndMemoryNeverDiverge() {
        var walked = 0
        for first in Self.steps {
            for second in Self.steps {
                for third in Self.steps {
                    for fourth in Self.steps {
                        walk([first, second, third, fourth])
                        walked += 1
                    }
                }
            }
        }
        XCTAssertEqual(walked, 10_000, "갈래를 다 걷지 않았다")
    }

    private func walk(_ path: [Step]) {
        var state = MarkerFocus.State()
        var screen: [MarkerFocus.Span] = []   // 화면에 드러난 줄들

        for step in path {
            switch step {
            case .plan(let cursor, let canPaint):
                let plan = MarkerFocus.plan(from: state, cursor: cursor, canPaint: canPaint)
                if let hide = plan.hide { screen.removeAll { $0 == hide } }
                if let show = plan.show, !screen.contains(show) { screen.append(show) }
                state = plan.state
                if canPaint {
                    XCTAssertEqual(state.dressed, cursor,
                                   "칠할 수 있었는데 커서를 안 따라갔다 — \(describe(path))")
                }
            case .wholeRepaint(let cursor):
                screen = cursor.map { [$0] } ?? []
                state = MarkerFocus.afterWholeRepaint(cursor: cursor)
            case .nudge:
                state = MarkerFocus.nudged(state)
            }

            XCTAssertLessThanOrEqual(screen.count, 1,
                                     "원문이 드러난 줄이 둘 이상이다 — \(describe(path))")
            XCTAssertEqual(screen, state.dressed.map { [$0] } ?? [],
                           "화면과 기억이 갈렸다 — \(describe(path))")
        }
    }

    /// **162 그 자체.** 한글을 치다 초점이 떠나면 숨기기가 건너뛰어진다 —
    /// 그래도 **기억은 남아야** 다음에 갚는다.
    func testKeepsTheRecordWhenItCouldNotHide() {
        var state = MarkerFocus.State()

        // 커서가 A 에 왔다 — A 가 드러난다.
        var plan = MarkerFocus.plan(from: state, cursor: Self.a, canPaint: true)
        XCTAssertEqual(plan.show, Self.a)
        state = plan.state
        XCTAssertEqual(state.dressed, Self.a)

        // 한글 조합 도중에 초점이 떠났다 — 아무것도 못 칠한다.
        plan = MarkerFocus.plan(from: state, cursor: nil, canPaint: false)
        XCTAssertTrue(plan.isEmpty, "조합을 끊지 않는다")
        state = plan.state
        XCTAssertEqual(state.dressed, Self.a, "못 지웠으면 **기억을 지우지 않는다** (162)")
        XCTAssertTrue(state.owes, "갚을 것이 있다고 적어 둔다")

        // 초점이 B 로 돌아왔다 — 그때 A 를 갚는다.
        plan = MarkerFocus.plan(from: state, cursor: Self.b, canPaint: true)
        XCTAssertEqual(plan.hide, Self.a, "남아 있던 A 를 지운다")
        XCTAssertEqual(plan.show, Self.b)
        XCTAssertEqual(plan.state.dressed, Self.b)
        XCTAssertFalse(plan.state.owes)
    }

    /// 조합이 끝나 다시 칠할 수 있게 되면, **초점이 없어도** 갚는다.
    func testPaysBackWhenCompositionEndsWithoutFocus() {
        var state = MarkerFocus.State()
        state = MarkerFocus.plan(from: state, cursor: Self.a, canPaint: true).state
        state = MarkerFocus.plan(from: state, cursor: nil, canPaint: false).state

        let plan = MarkerFocus.plan(from: state, cursor: nil, canPaint: true)
        XCTAssertEqual(plan.hide, Self.a)
        XCTAssertNil(plan.show)
        XCTAssertNil(plan.state.dressed)
    }

    /// **같은 자리면 가만히 둔다** (135 — 움직일 때마다 칠하면 화면이 떤다).
    func testDoesNothingWhenAlreadyRight() {
        var state = MarkerFocus.State()
        state = MarkerFocus.plan(from: state, cursor: Self.a, canPaint: true).state

        let plan = MarkerFocus.plan(from: state, cursor: Self.a, canPaint: true)
        XCTAssertTrue(plan.isEmpty)
        XCTAssertEqual(plan.state.dressed, Self.a)
    }

    /// **갚을 것이 있으면 같은 자리라도 다시 칠한다** (빌드 31 · 100 — 초점이 돌아오는 자리).
    func testRepaintsTheSameLineWhenNudged() {
        var state = MarkerFocus.State()
        state = MarkerFocus.plan(from: state, cursor: Self.a, canPaint: true).state
        state = MarkerFocus.nudged(state)

        let plan = MarkerFocus.plan(from: state, cursor: Self.a, canPaint: true)
        XCTAssertNil(plan.hide, "지울 것은 없다 — 같은 줄이다")
        XCTAssertEqual(plan.show, Self.a, "그래도 다시 드러낸다")
        XCTAssertFalse(plan.state.owes)
    }

    /// 글을 통째로 다시 칠하면 **그 사실을 적는다.** 안 적으면 아무도 못 지운다.
    func testWholeRepaintRecordsWhatIsDressed() {
        XCTAssertEqual(MarkerFocus.afterWholeRepaint(cursor: Self.a).dressed, Self.a)
        XCTAssertNil(MarkerFocus.afterWholeRepaint(cursor: nil).dressed)
    }

    private func describe(_ path: [Step]) -> String {
        path.map { step in
            switch step {
            case .plan(let cursor, let canPaint):
                return "칠(\(name(cursor)), \(canPaint ? "가능" : "조합중"))"
            case .wholeRepaint(let cursor): return "전체칠(\(name(cursor)))"
            case .nudge: return "다시칠하기"
            }
        }.joined(separator: " → ")
    }

    private func name(_ span: MarkerFocus.Span?) -> String {
        guard let span else { return "초점없음" }
        return span == Self.a ? "A" : "B"
    }
}
