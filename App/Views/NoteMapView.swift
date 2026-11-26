import SwiftUI
import Core

// **노트 지도** (329 · 330, 2026-11-26 사용자 — *최근 나의 관심사라던가 내가 해온 일을 정리하는데 도움이 될 것 같은데*).
// 설계 `docs/92-note-map-design.md`. 셈은 Core `NoteMap` (파이썬 쌍둥이 · 정답표) — 여기는 그리기만 한다.
// 색은 `Palette` 에서만 · 목록은 `PaperList` · 노트 줄은 최근 고친 노트와 같은 `RecentNoteRow` (CLAUDE.md §7).

/// 기간 — 4주 · 3개월 · 1년 (2026-11-26 사용자 정함).
enum NoteMapPeriod: Int, CaseIterable, Identifiable {
    case weeks = 28
    case months = 91
    case year = 365

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .weeks: return String(localized: "4주")
        case .months: return String(localized: "3개월")
        case .year: return String(localized: "1년")
        }
    }
}

/// **노트 지도 시트** — 기간을 고르면 그동안의 키워드가 막대 목록으로. 줄을 누르면 키워드 화면(330)이 밀려 들어온다.
struct NoteMapView: View {
    @EnvironmentObject private var library: LibraryModel
    /// 마지막에 고른 기간 — 기기마다 (설계 §3.1).
    @AppStorage("noteMap.period") private var periodDays = NoteMapPeriod.weeks.rawValue
    /// 차례 (331 · 사용자 정함 — 기본 많이 쓴 순). 기기마다.
    @AppStorage("noteMap.order") private var orderRaw = NoteMap.Order.count.rawValue
    @State private var snapshot: LibraryModel.NoteMapSnapshot?
    @State private var loaded = false
    @State private var shown = Self.pageSize
    @State private var shownPhrases = Self.phrasePageSize
    @State private var route: [String] = []

    static let pageSize = 30
    /// 332 — 구절 구역은 열 개씩.
    static let phrasePageSize = 10

    private var period: NoteMapPeriod { NoteMapPeriod(rawValue: periodDays) ?? .weeks }
    private var order: NoteMap.Order { NoteMap.Order(rawValue: orderRaw) ?? .count }

    var body: some View {
        NavigationStack(path: $route) {
            content
                .navigationTitle("노트 지도")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("닫기") { library.sheet = nil }
                            .keyboardShortcut(.cancelAction)
                    }
                }
                .navigationDestination(for: String.self) { keyword in
                    if let snapshot {
                        NoteMapKeywordView(snapshot: snapshot, days: period.rawValue, center: keyword, route: $route)
                    }
                }
        }
        .task { await reload() }
        .onAppear { library.noteMapVisible = true }
        .onDisappear { library.noteMapVisible = false }
        .onChange(of: periodDays) { _, _ in
            shown = Self.pageSize
            shownPhrases = Self.phrasePageSize
        }
        .onChange(of: library.hiddenWords) { _, _ in Task { await reload() } }
    }

    @ViewBuilder
    private var content: some View {
        let overview = snapshot?.model.overview(today: snapshot?.today ?? 0, days: period.rawValue, by: order)
        PaperList {
            if let overview, let snapshot {
                // 332 — **구절과 낱말을 두 구역으로** (2026-11-26 사용자 — *구절하고 단어하고 구분이 필요할 것 같은데*).
                // 구절은 늘 제 낱말보다 노트 수가 적어 한 목록에 섞으면 가라앉았다 (빌드 159). 구역마다 따로 겨루고 막대도 따로 잰다.
                let phrases = overview.entries.filter { NoteMap.isPhrase($0.keyword) }
                let words = overview.entries.filter { !NoteMap.isPhrase($0.keyword) }
                if !phrases.isEmpty {
                    Section {
                        rows(phrases, limit: shownPhrases)
                        if phrases.count > shownPhrases {
                            Button("더 보기") { shownPhrases += Self.phrasePageSize }
                                .font(.scaled(.body))
                                .foregroundStyle(Palette.accent)
                        }
                    } header: {
                        VStack(alignment: .leading, spacing: Metrics.rowSpacing) {
                            summary(overview: overview, snapshot: snapshot)
                            sectionTitle(String(localized: "구절 — 자주 붙여 쓰는 말"), count: phrases.count)
                        }
                    }
                }
                Section {
                    rows(words, limit: shown)
                    if words.count > shown {
                        Button("더 보기") { shown += Self.pageSize }
                            .font(.scaled(.body))
                            .foregroundStyle(Palette.accent)
                    }
                } header: {
                    VStack(alignment: .leading, spacing: Metrics.rowSpacing) {
                        if phrases.isEmpty { summary(overview: overview, snapshot: snapshot) }
                        sectionTitle(String(localized: "낱말"), count: words.count)
                    }
                }
                if !library.hiddenWords.isEmpty {
                    Section {
                        NavigationLink {
                            NoteMapHiddenWords()
                        } label: {
                            Text("숨긴 말 \(library.hiddenWords.count)개")
                                .font(.scaled(.body))
                                .foregroundStyle(Palette.ink)
                        }
                    }
                }
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            VStack(spacing: Metrics.rowSpacing) {
                Picker("기간", selection: $periodDays) {
                    ForEach(NoteMapPeriod.allCases) { p in
                        Text(p.label).tag(p.rawValue)
                    }
                }
                .pickerStyle(.segmented)
                // 331 — 차례. 막대 · 숫자는 늘 노트 수다 — *많이 쓴 순* 이면 위에서 아래로 줄어든다.
                Picker("차례", selection: $orderRaw) {
                    Text("많이 쓴 순").tag(NoteMap.Order.count.rawValue)
                    Text("두드러진 순").tag(NoteMap.Order.score.rawValue)
                }
                .pickerStyle(.segmented)
            }
            .padding(.horizontal, Metrics.gutter)
            .padding(.vertical, Metrics.rowSpacing)
            .background(Palette.paperGrouped)
        }
        .overlay {
            if !loaded {
                ProgressView()
            } else if let overview, overview.notes == 0 {
                ContentUnavailableView("이 기간에 고친 노트가 없습니다", systemImage: "calendar",
                                       description: Text("기간을 늘려 보세요."))
            } else if let overview, overview.entries.isEmpty {
                ContentUnavailableView("아직 키워드가 될 만한 말이 없습니다", systemImage: "text.word.spacing",
                                       description: Text("노트가 쌓이면 자주 쓴 말이 여기에 보입니다."))
            } else if snapshot == nil {
                ContentUnavailableView("노트 지도를 만들 수 없습니다", systemImage: "exclamationmark.circle",
                                       description: Text("색인이 아직 준비되지 않았습니다. 잠시 뒤 다시 열어 보세요."))
            }
        }
    }

    /// 줄들 — 막대는 이 구역에서 가장 많이 나온 말을 끝으로 (구절 막대가 낱말에 견주어 늘 짧아 보이지 않게).
    @ViewBuilder
    private func rows(_ entries: [NoteMap.Entry], limit: Int) -> some View {
        let top = entries.map(\.count).max() ?? 1
        ForEach(entries.prefix(limit), id: \.keyword) { entry in
            NavigationLink(value: entry.keyword) {
                NoteMapKeywordRow(entry: entry, top: top)
            }
            .contextMenu {
                Button {
                    Task { await library.hideWord(entry.keyword) }
                } label: {
                    Label("이 말 숨기기", systemImage: "eye.slash")
                }
            }
        }
    }

    private func sectionTitle(_ title: String, count: Int) -> some View {
        HStack(spacing: Metrics.rowSpacing) {
            Text(title)
                .font(.scaled(.subheadline, weight: .semibold))
                .foregroundStyle(Palette.ink)
            Text(verbatim: "\(count)")
                .font(.scaled(.subheadline))
                .monospacedDigit()
                .foregroundStyle(Palette.inkFaint)
        }
        .textCase(nil)
        .padding(.top, Metrics.rowSpacing)
    }

    private func summary(overview: NoteMap.Overview, snapshot: LibraryModel.NoteMapSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("노트 \(overview.notes)개에서")
            if order == .score {
                Text("앞 기간 · 다른 노트보다 이 기간에 두드러진 말이 위로 옵니다. 숫자는 노트 수입니다.")
            }
            if snapshot.titleOnly > 0 {
                Text("내려받지 않은 노트 \(snapshot.titleOnly)개는 빠졌습니다")
            }
        }
        .font(.scaled(.footnote))
        .foregroundStyle(Palette.inkFaint)
        .textCase(nil)
    }

    private func reload() async {
        snapshot = await library.loadNoteMap()
        loaded = true
        // CI — 첫 키워드 화면을 손가락과 같은 길로 연다 (`-noteMapKeyword`).
        if library.launch.noteMapKeyword, route.isEmpty,
           let first = snapshot?.model.overview(today: snapshot?.today ?? 0, days: period.rawValue, by: order).entries.first {
            try? await Task.sleep(for: .milliseconds(500))
            route = [first.keyword]
        }
    }
}

/// **키워드 한 줄** — 말 · 옅은 막대 · 노트 수 · 늘어난 표시. 큰 글자(접근성 크기)에서는 말 아래로 막대를 내린다.
struct NoteMapKeywordRow: View {
    let entry: NoteMap.Entry
    let top: Int
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        Group {
            if typeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: Metrics.rowSpacing) {
                    word
                    HStack(spacing: Metrics.rowSpacing) { bar; count; mark }
                }
            } else {
                HStack(spacing: Metrics.scaledLength(10)) {
                    word
                    Spacer(minLength: Metrics.rowSpacing)
                    bar
                    count
                    mark.frame(minWidth: Metrics.scaledLength(28), alignment: .leading)
                }
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var word: some View {
        Text(entry.keyword)
            .font(.scaled(.body))
            .foregroundStyle(Palette.ink)
            .lineLimit(1)
    }

    private var bar: some View {
        let track = Metrics.scaledLength(72)
        let ratio = CGFloat(entry.count) / CGFloat(max(top, 1))
        return ZStack(alignment: .leading) {
            Capsule().fill(Palette.fill)
                .frame(width: track)
            Capsule().fill(Palette.accent.opacity(0.55))
                .frame(width: max(Metrics.scaledLength(4), track * ratio))
        }
        .frame(width: track, height: Metrics.scaledLength(6))
    }

    private var count: some View {
        Text(verbatim: "\(entry.count)")
            .font(.scaled(.subheadline))
            .monospacedDigit()
            .foregroundStyle(Palette.inkFaint)
    }

    @ViewBuilder
    private var mark: some View {
        switch entry.mark {
        case .up:
            Text(verbatim: "↑").font(.scaled(.subheadline, weight: .semibold)).foregroundStyle(Palette.accent)
        case .new:
            Text("새로").font(.scaled(.caption, weight: .semibold)).foregroundStyle(Palette.accent)
        case .none:
            Text(verbatim: "").font(.scaled(.caption))
        }
    }

    private var accessibilityText: String {
        switch entry.mark {
        case .up: return String(localized: "\(entry.keyword), 노트 \(entry.count)개, 앞 기간보다 늘어남")
        case .new: return String(localized: "\(entry.keyword), 노트 \(entry.count)개, 새로 나옴")
        case .none: return String(localized: "\(entry.keyword), 노트 \(entry.count)개")
        }
    }
}

/// **키워드 화면** (330) — 위는 작은 관계도(가운데 말 · 함께 나온 말 여섯까지), 아래는 이 말이 든 노트.
struct NoteMapKeywordView: View {
    @EnvironmentObject private var library: LibraryModel
    let snapshot: LibraryModel.NoteMapSnapshot
    let days: Int
    let center: String
    @Binding var route: [String]
    /// 둘째 말 — 두 말이 함께 든 노트만.
    @State private var also: String?
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let neighbors = snapshot.model.neighbors(of: center, today: snapshot.today, days: days)
        let paths = snapshot.model.notePaths(keyword: center, also: also, today: snapshot.today, days: days)
        PaperList {
            if !neighbors.isEmpty {
                Section {
                    // 큰 글자에서는 둘레 말이 겹친다 — 같은 내용을 줄 목록으로 (설계 §3.3).
                    if typeSize.isAccessibilitySize {
                        ForEach(neighbors, id: \.keyword) { n in
                            Button { route.append(n.keyword) } label: {
                                HStack {
                                    Text(n.keyword).font(.scaled(.body)).foregroundStyle(Palette.ink)
                                    Spacer(minLength: Metrics.rowSpacing)
                                    Text("함께 \(n.count)").font(.scaled(.footnote)).foregroundStyle(Palette.inkFaint)
                                }
                            }
                            .contextMenu { filterButton(n.keyword) }
                        }
                    } else {
                        NoteMapGraph(center: center, neighbors: neighbors, also: also,
                                     open: { route.append($0) }, filter: { toggle($0) })
                            .frame(height: Metrics.scaledLength(300))
                            .listRowInsets(EdgeInsets())
                    }
                } header: {
                    Text("함께 나온 말").textCase(nil)
                } footer: {
                    Text("말을 누르면 그 말이 가운데로 옵니다. 길게 누르면 두 말이 함께 든 노트만 봅니다.")
                        .font(.scaled(.caption))
                        .foregroundStyle(Palette.inkFaint)
                }
            }
            Section {
                if let also {
                    Button {
                        self.also = nil
                    } label: {
                        Label("\(also) 거르기 풀기", systemImage: "xmark.circle")
                            .font(.scaled(.body))
                            .foregroundStyle(Palette.accent)
                    }
                }
                ForEach(paths, id: \.self) { path in
                    if let note = snapshot.notes[path] {
                        Button {
                            library.openFromNoteMap(path: path, keyword: center)
                        } label: {
                            RecentNoteRow(note: note)
                        }
                    }
                }
            } header: {
                Group {
                    if let also {
                        Text("\(center) · \(also) 함께 든 노트 \(paths.count)개")
                    } else {
                        Text("이 말이 든 노트 \(paths.count)개")
                    }
                }
                .textCase(nil)
            }
        }
        .navigationTitle(center)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func toggle(_ keyword: String) {
        also = also == keyword ? nil : keyword
    }

    private func filterButton(_ keyword: String) -> some View {
        Button {
            toggle(keyword)
        } label: {
            Label(also == keyword ? String(localized: "거르기 풀기") : String(localized: "두 말이 함께 든 노트만"),
                  systemImage: "line.3.horizontal.decrease.circle")
        }
    }
}

/// **작은 관계도** — 가운데 말 하나, 둘레에 함께 나온 말을 12시부터 시계 방향으로 고르게 (`NoteMap.layout`).
/// 선 굵기 = 함께 든 노트 수(세 단계). 물리 흉내 · 끌기는 없다 — 늘 같은 자리에 선다.
struct NoteMapGraph: View {
    let center: String
    let neighbors: [NoteMap.Neighbor]
    let also: String?
    let open: (String) -> Void
    let filter: (String) -> Void

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            let mid = CGPoint(x: size.width / 2, y: size.height / 2)
            let rx = max(0, size.width / 2 - Metrics.scaledLength(70))
            let ry = max(0, size.height / 2 - Metrics.scaledLength(26))
            let points = NoteMap.layout(count: neighbors.count).map {
                CGPoint(x: mid.x + CGFloat($0.x) * rx, y: mid.y + CGFloat($0.y) * ry)
            }
            ZStack {
                ForEach(Array(neighbors.enumerated()), id: \.element.keyword) { i, n in
                    Path { path in
                        path.move(to: mid)
                        path.addLine(to: points[i])
                    }
                    .stroke(n.keyword == also ? Palette.accent : Palette.inkFaint.opacity(0.45),
                            lineWidth: CGFloat(n.level) * 1.2)
                }
                chip(center, emphasized: true)
                    .position(mid)
                    .accessibilityAddTraits(.isHeader)
                ForEach(Array(neighbors.enumerated()), id: \.element.keyword) { i, n in
                    Button { open(n.keyword) } label: {
                        chip(n.keyword, emphasized: n.keyword == also)
                    }
                    .buttonStyle(.borderless)     // 목록 줄 안의 단추가 하나씩 눌리게 — 아니면 줄 전체가 한 단추가 된다
                    .contextMenu {
                        Button {
                            filter(n.keyword)
                        } label: {
                            Label(n.keyword == also ? String(localized: "거르기 풀기") : String(localized: "두 말이 함께 든 노트만"),
                                  systemImage: "line.3.horizontal.decrease.circle")
                        }
                    }
                    .accessibilityLabel(String(localized: "\(n.keyword), 함께 든 노트 \(n.count)개"))
                    .position(points[i])
                }
            }
        }
        .background(Palette.paper)
    }

    private func chip(_ text: String, emphasized: Bool) -> some View {
        Text(text)
            .font(.scaled(emphasized ? .headline : .subheadline, weight: emphasized ? .semibold : .regular))
            .foregroundStyle(Palette.ink)
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(maxWidth: Metrics.scaledLength(92))
            .padding(.horizontal, Metrics.scaledLength(10))
            .padding(.vertical, Metrics.scaledLength(5))
            // 바탕은 불투명하게 — 가운데로 모이는 선이 말 뒤로 비치지 않게 (종이를 깔고 잎 초록을 옅게 얹는다).
            .background(
                ZStack {
                    Capsule().fill(Palette.paperRaised)
                    if emphasized { Capsule().fill(Palette.accent.opacity(0.16)) }
                }
            )
            // 332 — 구절은 점선 테두리 (둘레에서도 낱말과 갈린다).
            .overlay(
                Capsule().stroke(emphasized ? Palette.accent : Palette.rule,
                                 style: StrokeStyle(lineWidth: 1, dash: NoteMap.isPhrase(text) ? [4, 3] : []))
            )
    }
}

/// **숨긴 말** — 되살리기. 숨긴 말은 지도 · 함께 나온 말 둘 다에서 빠진다.
struct NoteMapHiddenWords: View {
    @EnvironmentObject private var library: LibraryModel

    var body: some View {
        PaperList {
            Section {
                ForEach(library.hiddenWords, id: \.self) { word in
                    HStack {
                        Text(word).font(.scaled(.body)).foregroundStyle(Palette.ink)
                        Spacer(minLength: Metrics.rowSpacing)
                        Button("되살리기") {
                            Task { await library.unhideWord(word) }
                        }
                        .font(.scaled(.subheadline))
                        .foregroundStyle(Palette.accent)
                        .buttonStyle(.borderless)
                    }
                }
            } footer: {
                Text("숨긴 말은 이 폴더 안의 숨김 파일에 적혀 다른 기기에도 따라갑니다. 노트 글은 바뀌지 않습니다.")
                    .font(.scaled(.caption))
                    .foregroundStyle(Palette.inkFaint)
            }
        }
        .overlay {
            if library.hiddenWords.isEmpty {
                ContentUnavailableView("숨긴 말이 없습니다", systemImage: "eye")
            }
        }
        .navigationTitle("숨긴 말")
        .navigationBarTitleDisplayMode(.inline)
    }
}
