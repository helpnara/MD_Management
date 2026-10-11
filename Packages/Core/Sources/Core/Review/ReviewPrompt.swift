import Foundation

/// **앱 평가를 부탁할 때인가** (2026-10-11 사용자 — *무료 앱 상위에 랭크하기 위해서* · 브레인스토밍 1번).
///
/// 평점 수는 검색 순위와 검색 결과에서 눌러 받는 비율 양쪽에 걸린다. 그런데 부탁을 아무 때나 띄우면 별 하나가 온다 —
/// **이 앱을 며칠 써 본 사람에게, 노트를 고치고 떠나는 순간에만** 부탁한다. 애플은 창을 1년에 세 번까지만 띄워 주고,
/// 띄울지 말지도 애플이 정한다 — 여기서는 **우리가 묻지 않을 때**를 정한다.
///
/// - 서로 다른 날 **5일 이상** 노트를 저장했다 (하루에 여러 번은 하루)
/// - 처음 쓴 날부터 **7일 이상** 지났다
/// - 지난번 부탁에서 **120일 이상** 지났다 (처음이면 상관없다)
/// - **이 판에서는 아직 안 물었다** — 같은 판으로 두 번 묻지 않는다
///
/// 파이썬 쌍둥이: `Tools/golden/generate.py` 의 `review_due` (`reviewCases`).
public enum ReviewPrompt {
    public static let minimumActiveDays = 5
    public static let minimumDaysSinceFirstUse = 7
    public static let minimumDaysBetweenAsks = 120

    public static func isDue(activeDays: Int, daysSinceFirstUse: Int, daysSinceLastAsk: Int?,
                             askedThisVersion: Bool) -> Bool {
        guard !askedThisVersion else { return false }
        guard activeDays >= minimumActiveDays, daysSinceFirstUse >= minimumDaysSinceFirstUse else { return false }
        if let daysSinceLastAsk, daysSinceLastAsk < minimumDaysBetweenAsks { return false }
        return true
    }
}
