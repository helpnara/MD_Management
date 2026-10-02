import Foundation

/// **늘 보이는 스크롤 막대** (202, 2026-10-02 사용자 — *노트마다 얼마나 긴지 가늠이 안 되고 지금 위치가 어디쯤인지 확인할 방법이 없다*).
///
/// 막대 길이 = 보이는 양 ÷ 전체, 막대 자리 = 지금 위치. 쓰기 화면과 읽기 화면이 **이 셈 하나**를 쓴다 — 같은 것을 재는 곳이
/// 둘이면 갈린다 (CLAUDE.md §1). 노트가 화면보다 짧으면 그리지 않는다(`nil`). 너무 긴 노트에서도 막대가 손톱만큼은 남게
/// `minimum` 보다 짧아지지 않는다. 튕겨 넘친 자리(맨 위 · 맨 아래를 지나 당길 때)는 끝에 붙여 둔다.
///
/// **파이썬 `scroll_thumb` 와 같은 셈이다** (`Tools/golden`, `scrollGaugeCases`).
public enum ScrollGauge {

    public struct Thumb: Equatable, Sendable {
        /// 막대 위쪽 끝 — 트랙 맨 위에서부터.
        public let start: Double
        public let length: Double

        public init(start: Double, length: Double) {
            self.start = start
            self.length = length
        }
    }

    /// - Parameters:
    ///   - content: 글 전체 높이
    ///   - viewport: 보이는 높이 (위아래 여백을 뺀 것)
    ///   - offset: 지금 맨 위에 보이는 자리 (0 = 처음)
    ///   - track: 막대가 오르내릴 수 있는 길이
    ///   - minimum: 막대의 가장 짧은 길이
    public static func thumb(content: Double, viewport: Double, offset: Double,
                             track: Double, minimum: Double) -> Thumb? {
        guard content.isFinite, viewport.isFinite, offset.isFinite, track.isFinite,
              viewport > 0, track > 0, content > viewport + 1 else { return nil }
        let length = min(track, max(minimum, track * viewport / content))
        let progress = min(1, max(0, offset / (content - viewport)))
        return Thumb(start: (track - length) * progress, length: length)
    }
}
