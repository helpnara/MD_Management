import Foundation
import Core

/// **평가 부탁에 쓰는 기억** — 처음 쓴 날 · 노트를 저장한 날 수 · 지난번 부탁 (이 기기의 설정에만 둔다).
///
/// 노트 본문은 한 글자도 담지 않는다 (ADR-0001). 날 수만 센다 — 하루에 여러 번 저장해도 하루다. 밖으로 보내는 것은 없다.
/// 언제 부탁할지는 Core `ReviewPrompt.isDue` 가 정한다 (정답표).
struct ReviewLedger {
    private let defaults: UserDefaults
    private static let firstUseKey = "review.firstUse"
    private static let activeDaysKey = "review.activeDays"
    private static let lastDayKey = "review.lastDay"
    private static let lastAskedKey = "review.lastAsked"
    private static let askedVersionKey = "review.askedVersion"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// 노트를 저장했다. 오늘 처음이면 하루를 센다.
    func noteSaved(now: Date = Date()) {
        if defaults.object(forKey: Self.firstUseKey) == nil {
            defaults.set(now, forKey: Self.firstUseKey)
        }
        let today = Self.dayStamp(now)
        guard defaults.string(forKey: Self.lastDayKey) != today else { return }
        defaults.set(today, forKey: Self.lastDayKey)
        defaults.set(defaults.integer(forKey: Self.activeDaysKey) + 1, forKey: Self.activeDaysKey)
    }

    func isDue(now: Date = Date(), version: String) -> Bool {
        guard let firstUse = defaults.object(forKey: Self.firstUseKey) as? Date else { return false }
        let lastAsked = defaults.object(forKey: Self.lastAskedKey) as? Date
        return ReviewPrompt.isDue(activeDays: defaults.integer(forKey: Self.activeDaysKey),
                                  daysSinceFirstUse: Self.days(from: firstUse, to: now),
                                  daysSinceLastAsk: lastAsked.map { Self.days(from: $0, to: now) },
                                  askedThisVersion: defaults.string(forKey: Self.askedVersionKey) == version)
    }

    func markAsked(now: Date = Date(), version: String) {
        defaults.set(now, forKey: Self.lastAskedKey)
        defaults.set(version, forKey: Self.askedVersionKey)
    }

    private static func dayStamp(_ date: Date) -> String {
        let parts = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return "\(parts.year ?? 0)-\(parts.month ?? 0)-\(parts.day ?? 0)"
    }

    /// 달력의 날 수 (시각이 아니라 날짜로) — 기기 시간을 되돌렸으면 음수가 나오고, 그러면 묻지 않는다.
    private static func days(from start: Date, to end: Date) -> Int {
        let calendar = Calendar.current
        return calendar.dateComponents([.day], from: calendar.startOfDay(for: start),
                                       to: calendar.startOfDay(for: end)).day ?? 0
    }
}
