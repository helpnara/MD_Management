import Foundation

/// **지금 어느 줄이 원문을 드러내고 있나** (162, 2026-09-24 사용자 · 아이패드 스크린샷).
///
/// 편집기는 **커서가 있는 문단 하나**만 마크다운 원문으로 보여 준다 (L2). 나머지는
/// 읽는 모습이다. 그런데 한 화면에 **세 줄**이 드러나 있었다 — `# 주간 계획` 의 `#`,
/// 첫 문단의 `**`, `참고자료` 줄의 `[…](…)`.
///
/// **까닭은 기억과 화면이 갈린 것이었다.** 예전에는 `UITextView` 대리자 셋이 각자
/// *어느 문단을 지우고 어느 문단을 드러낼까* 를 판단했고, 드러난 줄을 적어 두는 자리는
/// 하나였는데 **그 자리를 지우면서 화면은 안 지우는 길**이 있었다:
///
/// - 한글은 **늘 조합 중**이다. 조합 도중에 초점이 떠나면 숨기는 일이 건너뛰어진다.
/// - 그런데 바로 다음 줄에서 *드러난 줄이 없다* 고 적어 버렸다.
/// - 그 뒤로는 지울 근거가 사라져 그 줄이 **영영 드러난 채** 남았다. 드러난 줄이 쌓였다.
///
/// `CLAUDE.md` §1 — **같은 것을 재는 곳이 둘이면 언젠가 갈린다.** 여기서는 *어느 줄이
/// 드러났나* 를 화면과 기억이 따로 들고 있었다.
///
/// 그래서 **판단을 여기 하나로 모았다.** 대리자들은 *지금 커서가 어느 문단에 있나* 와
/// *지금 칠해도 되나* 만 말하고, 무엇을 지우고 무엇을 드러낼지는 이 함수가 정한다.
/// 순수 함수라 **리눅스 `swift test` 가 심판**이 된다 — 예전에는 사람 말고 심판이 없었다.
///
/// 오프셋은 **UTF-16** (`NSTextStorage` 단위 — `Formatting` 과 같다).
public enum MarkerFocus {

    /// 문단 하나가 차지하는 자리.
    public struct Span: Equatable, Sendable {
        public let start: Int
        public let length: Int

        public init(start: Int, length: Int) {
            self.start = start
            self.length = length
        }
    }

    /// **지금 화면이 어떤 상태인가.** 편집기가 이것 하나만 들고 있는다.
    public struct State: Equatable, Sendable {
        /// 원문이 드러나 있는 문단. `nil` 이면 드러난 줄이 없다.
        ///
        /// **이 값은 화면을 따라간다.** 실제로 숨긴 뒤에만 `nil` 이 되고, 실제로 드러낸
        /// 뒤에만 값이 들어간다. 숨기지 못했으면 **그대로 들고 있는다** — 그것이 162 다.
        public let dressed: Span?

        /// **갚을 것이 있다.** 칠하지 못하고 지나간 자리가 있었다는 표시.
        /// 다음에 칠할 수 있게 되면 같은 문단이라도 다시 칠한다.
        public let owes: Bool

        public init(dressed: Span? = nil, owes: Bool = false) {
            self.dressed = dressed
            self.owes = owes
        }
    }

    /// **무엇을 칠할 것인가.** 편집기는 이대로만 하면 된다.
    public struct Plan: Equatable, Sendable {
        /// 커서가 없는 모습으로 되돌릴 문단.
        public let hide: Span?
        /// 커서가 있는 모습으로 드러낼 문단.
        public let show: Span?
        /// 칠한 뒤의 상태.
        public let state: State

        public init(hide: Span?, show: Span?, state: State) {
            self.hide = hide
            self.show = show
            self.state = state
        }

        /// 칠할 것이 없다.
        public var isEmpty: Bool { hide == nil && show == nil }
    }

    /// **커서가 여기 있고, 지금 칠할 수 있나.** 그 둘만 주면 나머지는 여기서 정한다.
    ///
    /// - `cursor`: 커서가 든 문단. **초점이 없으면 `nil`** — 드러난 줄이 없어야 한다는 뜻이다.
    /// - `canPaint`: 지금 속성을 건드려도 되나. 한글 조합 중이면 **안 된다** — 건드리면
    ///   조합이 끊긴다 (S10). 그때는 아무것도 칠하지 않고 **갚을 것만 적어 둔다.**
    public static func plan(from state: State, cursor: Span?, canPaint: Bool) -> Plan {
        // 칠할 수 없다 — **기억을 지우지 않는다.** 화면에 드러난 줄은 그대로 있다.
        // 예전에는 여기서 *드러난 줄이 없다* 고 적어 버려 지울 근거를 잃었다 (162).
        guard canPaint else {
            return Plan(hide: nil, show: nil,
                        state: State(dressed: state.dressed,
                                     owes: state.owes || state.dressed != cursor))
        }
        // 이미 맞고 갚을 것도 없으면 가만히 둔다 — 움직일 때마다 칠하면 화면이 떤다 (135).
        guard state.dressed != cursor || state.owes else {
            return Plan(hide: nil, show: nil, state: State(dressed: state.dressed, owes: false))
        }
        let hide = state.dressed == cursor ? nil : state.dressed
        return Plan(hide: hide, show: cursor, state: State(dressed: cursor, owes: false))
    }

    /// **글을 통째로 다시 칠했다** (노트를 열거나 파일이 바뀌어 다시 읽었을 때).
    ///
    /// 그때는 커서가 든 문단이 **이미 드러난 채로 칠해진다.** 그 사실을 적어 두지 않으면
    /// 화면과 기억이 또 갈린다 — 드러난 줄을 아무도 못 지우게 된다.
    public static func afterWholeRepaint(cursor: Span?) -> State {
        State(dressed: cursor, owes: false)
    }

    /// **다음에는 같은 자리라도 반드시 다시 칠한다.**
    ///
    /// 초점이 돌아올 때 쓴다. 대리자가 불리는 차례 때문에 커서 자리가 아직 안 정해진
    /// 순간이 있어(빌드 31 · 100), 그 뒤에 오는 칠하기가 **건너뛰지 않게** 해야 한다.
    /// 예전에는 기억을 지워서 그 일을 했는데, 지우면 드러난 줄을 잃는다 (162).
    public static func nudged(_ state: State) -> State {
        State(dressed: state.dressed, owes: true)
    }
}
