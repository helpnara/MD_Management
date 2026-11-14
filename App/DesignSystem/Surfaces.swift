import SwiftUI

// **바탕과 줄** (316 · 318 · 320, 2026-11-12 사용자 — *항상 고급스럽게*). 목록마다 바탕을 따로 적지 않는다 —
// 같은 것을 칠하는 곳이 둘이면 언젠가 갈린다 (CLAUDE §1). 색은 `Palette` 에서만.

/// **묶음 목록** — 설정 · 도움말 · 단축키 · 휴지통 · 진단 · 찾기 시트. 시스템 바탕(옅은 회색 · 검정)과
/// 시스템 칸(흰색 · 짙은 회색)을 숨기고 **묶음 바탕 위에 종이 칸**을 깐다.
///
/// 칸 바탕은 안쪽 내용 전체에 `Group` 으로 한 번 건다 — `Group` 에 붙인 수식어는 그 안 하나하나(구역 · 줄)에 붙는다.
struct PaperList<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        List {
            Group { content }
                .listRowBackground(Palette.paper)
        }
        .scrollContentBackground(.hidden)
        .background(Palette.paperGrouped)
    }
}

/// **목록의 날짜** (318) — 올해 고친 것은 연도를 뺀다. `2026년 11월 7일 오전 12:59` 가 줄마다 되풀이되면 줄이 날짜로 무거워진다.
/// 시각은 남긴다 — 오늘 고친 여러 노트가 안 갈린다 (50). 노트 목록 · 최근 고친 노트가 **이것 하나**를 쓴다.
enum ListDate {
    static func style(for date: Date, now: Date = .now) -> Date.FormatStyle {
        Calendar.current.isDate(date, equalTo: now, toGranularity: .year)
            ? .dateTime.month().day().hour().minute()
            : .dateTime.year().month().day().hour().minute()
    }
}

/// **고른 줄** (318) — 시스템의 회색 둥근 칸 대신 잎 초록을 옅게 깐 둥근 칸. 고르지 않은 줄은 종이.
/// 줄 바탕을 우리가 칠하면 시스템이 고른 줄을 칠하지 않으므로, 고른 줄도 우리가 칠한다.
struct RowBackground: View {
    let selected: Bool

    var body: some View {
        if selected {
            ZStack {
                Palette.paper
                RoundedRectangle(cornerRadius: Metrics.scaledLength(12), style: .continuous)
                    .fill(Palette.accent.opacity(0.14))
                    .padding(.horizontal, Metrics.scaledLength(6))
                    .padding(.vertical, Metrics.scaledLength(2))
            }
        } else {
            Palette.paper
        }
    }
}
