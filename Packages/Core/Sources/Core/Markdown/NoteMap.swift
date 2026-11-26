import Foundation

/// **노트 지도** (329 · 330, 2026-11-26 사용자 — *최근 나의 관심사라던가 내가 해온 일을 정리하는데 도움이 될 것 같은데*).
///
/// 노트에 쓴 말을 세어 *이 기간에 무엇을 많이 썼나* (329) · 한 말과 함께 다닌 말 (330) 을 낸다. 설계 `docs/92-note-map-design.md`.
/// 파일은 한 글자도 바꾸지 않는다 — 노트 하나의 낱말 꼴(`terms`)은 색인(캐시)에 쓸 때 한 번 셈하고, 나머지는 지도를 열 때 한다.
///
/// **파이썬 `Tools/golden/note_map.py` 와 같은 셈이다** (`noteMapCases`) — 규칙의 원본 설명은 거기 머리에 있다. 고칠 때는 두 쪽을 같이 고친다.
/// 글자는 유니코드 스칼라 단위로 본다 (파이썬의 코드 포인트와 같게). 순수 함수다 — UIKit · SQLite 를 모른다.
///
/// 보이는 글은 이미 있는 셈을 부른다 — 머리말 `FrontMatterParser` · 줄 역할 `BlockContext.roles` · 울타리 `NoteStats.fence` ·
/// 미리보기 `PreviewLine.plain` (같은 것을 재는 곳을 둘 두지 않는다 — CLAUDE.md §1).
public enum NoteMap {

    // MARK: - 표

    /// 센 조사 — 꼴 증거가 된다.
    static let strong: [String] = [
        "은", "는", "이", "가", "을", "를", "의", "에", "에서", "에게", "께서", "한테", "으로", "로",
        "으로서", "로서", "으로써", "로써", "와", "과", "이랑", "랑", "하고", "까지", "부터", "처럼", "보다", "만큼",
        "에는", "에도", "에서는", "에서도", "으로는", "로는", "으로도", "로도", "과는", "와는", "에게는", "에게서",
        "이라는", "라는", "이란",
    ]
    /// 약한 조사 — 떼기만 한다 (동사 연결 꼴 *-어도 · -야만 · -거나* 와 겹친다).
    static let weak: [String] = [
        "도", "만", "이나", "나", "들", "들이", "들은", "들을", "들의", "들에", "들도", "들과", "들로",
        "마저", "조차", "이라도", "라도",
    ]
    static let strongSet = Set(strong)
    /// 긴 것부터, 같은 길이는 코드 포인트 순.
    static let josa: [[Unicode.Scalar]] = Set(strong + weak).map { Array($0.unicodeScalars) }.sorted { a, b in
        a.count != b.count ? a.count > b.count : a.lexicographicallyPrecedes(b, by: { $0.value < $1.value })
    }

    static let stop: Set<String> = [
        "그리고", "그러나", "하지만", "그래서", "그런데", "그러면", "또는", "이것", "그것", "저것", "여기", "거기", "저기",
        "이런", "그런", "저런", "이렇게", "그렇게", "오늘", "어제", "내일", "지금", "이번", "다음", "지난", "우리", "저희",
        "자신", "다시", "바로", "아직", "이미", "먼저", "모두", "함께", "같이", "정말", "너무", "아주", "매우", "가장",
        "계속", "항상", "위해", "대한", "대해", "통해", "때문", "경우", "정도", "이상", "이하", "하나", "어떤", "무엇",
        "누구", "어디", "언제", "이제", "그냥", "조금", "많이", "동안", "에서", "으로", "부터", "까지", "처럼", "보다",
        "개월", "아니", "이후", "이전", "전에", "후에", "여기서", "거기서", "따로", "안에", "밖에", "위에",
        "아래", "없이", "있으면", "없으면", "처음", "마지막", "보내", "하면", "되면",
    ]
    static let englishStop: Set<String> = [
        "the", "and", "for", "with", "that", "this", "from", "you", "your", "are", "was", "were", "not", "but",
        "have", "has", "had", "will", "can", "all", "any", "our", "its", "into", "out", "about",
        "http", "https", "www", "com", "org", "net", "html", "div", "span",
    ]
    /// 동사 · 형용사 줄기 — 마지막 음절, 또는 `…다` 앞 음절.
    static let badLast = Set("하되있없했됐겠였었았".unicodeScalars)
    static let badBeforeDa = Set("하되있없했됐였었았겠한된간온본준갔왔봤줬좋많같싶는".unicodeScalars)
    static let da: Unicode.Scalar = "다"

    static let spaces: Set<UInt32> = {
        var set: Set<UInt32> = [0x09, 0x0A, 0x0B, 0x0C, 0x0D, 0x20, 0xA0, 0x1680, 0x2028, 0x2029, 0x202F, 0x205F, 0x3000]
        for v in UInt32(0x2000)..<UInt32(0x200B) { set.insert(v) }
        return set
    }()

    /// 둘레 말은 여섯까지.
    public static let neighborLimit = 6
    static let scoreScale = 1_000_000.0

    // MARK: - 글자

    static func isHangul(_ s: Unicode.Scalar) -> Bool { s.value >= 0xAC00 && s.value <= 0xD7A3 }

    static func isASCIIAlnum(_ s: Unicode.Scalar) -> Bool {
        (s.value >= 0x30 && s.value <= 0x39) || (s.value >= 0x41 && s.value <= 0x5A) || (s.value >= 0x61 && s.value <= 0x7A)
    }

    static func isUpper(_ s: Unicode.Scalar) -> Bool { s.value >= 0x41 && s.value <= 0x5A }

    static func isDigit(_ s: Unicode.Scalar) -> Bool { s.value >= 0x30 && s.value <= 0x39 }

    /// 라틴 글자에 붙는 악센트 글자 (U+00C0 ~ U+024F · × ÷ 빼고) — *café* 의 `caf` 를 버리려고.
    static func isAccentedLetter(_ s: Unicode.Scalar) -> Bool {
        s.value >= 0xC0 && s.value <= 0x24F && s.value != 0xD7 && s.value != 0xF7
    }

    static func string(_ scalars: ArraySlice<Unicode.Scalar>) -> String {
        var view = String.UnicodeScalarView()
        view.append(contentsOf: scalars)
        return String(view)
    }

    static func lowercasedASCII(_ scalars: ArraySlice<Unicode.Scalar>) -> String {
        string(ArraySlice(scalars.map { isUpper($0) ? Unicode.Scalar($0.value + 0x20)! : $0 }))
    }

    /// 코드 포인트 순 (파이썬의 문자열 비교와 같게).
    static func precedes(_ a: String, _ b: String) -> Bool {
        a.unicodeScalars.lexicographicallyPrecedes(b.unicodeScalars, by: { $0.value < $1.value })
    }

    static func isBadStem(_ word: String) -> Bool {
        let s = Array(word.unicodeScalars)
        guard let last = s.last else { return false }
        if badLast.contains(last) { return true }
        return s.count >= 2 && last == da && badBeforeDa.contains(s[s.count - 2])
    }

    static func isASCIIWord(_ word: String) -> Bool { word.unicodeScalars.allSatisfy(isASCIIAlnum) }

    // MARK: - 노트 하나 → 낱말 꼴

    /// 낱말 하나의 (말, 꼴). 꼴은 뗀 조사 — 없으면 빈 글.
    public struct Term: Hashable, Sendable {
        public let stem: String
        public let form: String

        public init(stem: String, form: String) {
            self.stem = stem
            self.form = form
        }

        static func precedes(_ a: Term, _ b: Term) -> Bool {
            a.stem != b.stem ? NoteMap.precedes(a.stem, b.stem) : NoteMap.precedes(a.form, b.form)
        }
    }

    static func stripJosa(_ run: [Unicode.Scalar]) -> Term {
        for j in josa where run.count - j.count >= 2 && run.suffix(j.count).elementsEqual(j) {
            return Term(stem: string(run[..<(run.count - j.count)]), form: string(ArraySlice(j)))
        }
        return Term(stem: string(ArraySlice(run)), form: "")
    }

    /// 보이는 글 한 줄 → (말, 꼴) 들 (거르기 전).
    static func scan(_ text: [Unicode.Scalar]) -> [Term] {
        var out: [Term] = []
        var i = 0
        let n = text.count
        while i < n {
            let c = text[i]
            let hangul = isHangul(c)
            guard hangul || isASCIIAlnum(c) else {
                i += 1
                continue
            }
            let start = i
            var j = i
            while j < n, hangul ? isHangul(text[j]) : isASCIIAlnum(text[j]) { j += 1 }
            let run = text[start..<j]
            if !hangul {
                let isScheme = j + 3 <= n && text[j] == ":" && text[j + 1] == "/" && text[j + 2] == "/"
                let isWWW = lowercasedASCII(run) == "www" && j < n && text[j] == "."
                if isScheme || isWWW {
                    while j < n, !spaces.contains(text[j].value) { j += 1 }
                    i = j
                    continue
                }
            }
            i = j
            if hangul {
                if run.count < 2 { continue }
                out.append(stripJosa(Array(run)))
            } else {
                let before = start > 0 ? text[start - 1] : nil
                let after = j < n ? text[j] : nil
                if isDigit(run.first!) || before.map(isAccentedLetter) == true || after.map(isAccentedLetter) == true { continue }
                let word = lowercasedASCII(run)
                let acronym = run.count == 2 && run.allSatisfy(isUpper)
                if (run.count < 3 && !acronym) || englishStop.contains(word) { continue }
                out.append(Term(stem: word, form: ""))
            }
        }
        return out
    }

    /// **노트 하나의 낱말 꼴** — 중복 없이 · 차례 고정. 색인에 쓸 때 부른다.
    public static func terms(of text: String) -> [Term] {
        let body = FrontMatterParser.parse(Paths.normalized(text)).body
        var lines: [[Unicode.Scalar]] = [[]]
        for s in body.unicodeScalars {
            if s == "\n" { lines.append([]) } else { lines[lines.count - 1].append(s) }
        }
        lines = lines.map { $0.last == "\r" ? Array($0.dropLast()) : $0 }
        let strings = lines.map { string(ArraySlice($0)) }
        let roles = BlockContext.roles(of: strings)
        var found = Set<Term>()
        for (index, line) in lines.enumerated() {
            switch roles[index] {
            case .code, .indentedCode, .comment: continue
            default: break
            }
            if NoteStats.fence(line) != nil { continue }
            for term in scan(Array(PreviewLine.plain(strings[index]).unicodeScalars)) { found.insert(term) }
        }
        return found.sorted(by: Term.precedes)
    }

    /// 색인 칸에 담는 꼴 — `말\t꼴` 을 줄바꿈으로 잇는다 (낱말에는 빈칸 · 줄바꿈이 없다).
    public static func encode(_ terms: [Term]) -> String {
        terms.map { $0.stem + "\t" + $0.form }.joined(separator: "\n")
    }

    public static func decode(_ text: String) -> [Term] {
        guard !text.isEmpty else { return [] }
        return text.split(separator: "\n", omittingEmptySubsequences: true).map { line in
            let parts = line.split(separator: "\t", maxSplits: 1, omittingEmptySubsequences: false)
            return Term(stem: String(parts[0]), form: parts.count > 1 ? String(parts[1]) : "")
        }
    }

    // MARK: - 날

    /// 1970-01-01 부터 센 날 (그레고리력).
    public static func civilDay(year: Int, month: Int, day: Int) -> Int {
        let y = year - (month <= 2 ? 1 : 0)
        let era = (y >= 0 ? y : y - 399) / 400
        let yoe = y - era * 400
        let doy = (153 * (month + (month > 2 ? -3 : 9)) + 2) / 5 + day - 1
        let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
        return era * 146097 + doe - 719468
    }

    /// 머리말 `created` · `date` 의 앞 열 글자 `YYYY-MM-DD` → 날. 꼴이 틀리거나 없는 날짜면 nil.
    public static func createdDay(_ created: String?) -> Int? {
        guard let created else { return nil }
        let s = Array(created.unicodeScalars.drop(while: { spaces.contains($0.value) }))
        guard s.count >= 10, s[4] == "-", s[7] == "-",
              [0, 1, 2, 3, 5, 6, 8, 9].allSatisfy({ isDigit(s[$0]) }) else { return nil }
        func number(_ range: Range<Int>) -> Int { range.reduce(0) { $0 * 10 + Int(s[$1].value - 0x30) } }
        let y = number(0..<4), m = number(5..<7), d = number(8..<10)
        guard (1...12).contains(m), d >= 1 else { return nil }
        let leap = y % 4 == 0 && (y % 100 != 0 || y % 400 == 0)
        let days = [31, leap ? 29 : 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31][m - 1]
        guard d <= days else { return nil }
        return civilDay(year: y, month: m, day: d)
    }

    // MARK: - 폴더 전체

    /// 노트 한 줄 — 색인에서 읽은 것.
    public struct Row: Sendable {
        public let path: String
        public let day: Int
        public let terms: [Term]

        public init(path: String, day: Int, terms: [Term]) {
            self.path = path
            self.day = day
            self.terms = terms
        }
    }

    public enum Mark: String, Sendable, Equatable {
        case none = ""
        case up
        case new
    }

    public struct Entry: Equatable, Sendable {
        public let keyword: String
        public let count: Int
        public let previous: Int
        public let mark: Mark
    }

    public struct Overview: Equatable, Sendable {
        /// 이 기간 노트 수 · 앞 기간 노트 수.
        public let notes: Int
        public let previousNotes: Int
        public let entries: [Entry]
    }

    public struct Neighbor: Equatable, Sendable {
        public let keyword: String
        public let count: Int
        /// 선 굵기 1 ~ 3.
        public let level: Int
    }

    /// 폴더 전체를 한 번 읽어 둔 것 — 기간 · 가운데 말을 바꿔 가며 묻는다.
    public struct Model: Sendable {
        struct Note: Sendable {
            let path: String
            let day: Int
            let keywords: Set<String>
        }

        let notes: [Note]
        let df: [String: Int]
        public var total: Int { notes.count }
        /// 받은 키워드 전부 (코드 포인트 순).
        public var keywords: [String] { df.keys.sorted(by: NoteMap.precedes) }

        public init(rows: [Row], hidden: Set<String> = []) {
            var stemForms: [String: Set<String>] = [:]
            for row in rows {
                for term in row.terms { stemForms[term.stem, default: []].insert(term.form) }
            }
            func resolve(_ term: Term) -> Term {
                if !term.form.isEmpty, let forms = stemForms[term.stem + term.form],
                   forms.contains(where: { NoteMap.strongSet.contains($0) }) {
                    return Term(stem: term.stem + term.form, form: "")
                }
                return term
            }
            let resolved = rows.map { $0.terms.map(resolve) }
            var kwForms: [String: Set<String>] = [:]
            for pairs in resolved {
                for term in pairs { kwForms[term.stem, default: []].insert(term.form) }
            }
            var accepted: [String: Bool] = [:]
            for (k, forms) in kwForms {
                if hidden.contains(k) {
                    accepted[k] = false
                } else if NoteMap.isASCIIWord(k) {
                    accepted[k] = true
                } else if k.unicodeScalars.count < 2 || NoteMap.stop.contains(k) || NoteMap.isBadStem(k) {
                    accepted[k] = false
                } else {
                    accepted[k] = forms.filter { $0.isEmpty || NoteMap.strongSet.contains($0) }.count >= 2
                }
            }
            var notes: [Note] = []
            var df: [String: Int] = [:]
            for (row, pairs) in zip(rows, resolved) {
                let keywords = Set(pairs.map(\.stem).filter { accepted[$0] == true })
                for k in keywords { df[k, default: 0] += 1 }
                notes.append(Note(path: row.path, day: row.day, keywords: keywords))
            }
            self.notes = notes
            self.df = df
        }

        func score(_ count: Int, _ keyword: String) -> Int {
            let value = Double(count) * log(Double(total + 1) / Double(df[keyword] ?? 1)) * NoteMap.scoreScale
            return Int((value + 0.5).rounded(.down))
        }

        func ranked(_ counts: [String: Int], minimum: Int) -> [String] {
            let chosen = counts.filter { $0.value >= minimum }.map { (key: $0.key, score: score($0.value, $0.key)) }
            return chosen.sorted { a, b in a.score != b.score ? a.score > b.score : NoteMap.precedes(a.key, b.key) }.map(\.key)
        }

        func inPeriod(today: Int, days: Int) -> [Note] {
            notes.filter { today - $0.day < days }
        }

        /// **329 — 이 기간의 키워드** (많이 나온 순 · 흔한 말은 낮게).
        public func overview(today: Int, days: Int) -> Overview {
            let current = inPeriod(today: today, days: days)
            let previous = notes.filter { today - $0.day >= days && today - $0.day < 2 * days }
            var cur: [String: Int] = [:]
            var prev: [String: Int] = [:]
            for note in current { for k in note.keywords { cur[k, default: 0] += 1 } }
            for note in previous { for k in note.keywords { prev[k, default: 0] += 1 } }
            let order = ranked(cur, minimum: current.count < 10 ? 1 : 2)
            let entries = order.map { k -> Entry in
                let c = cur[k] ?? 0, p = prev[k] ?? 0
                let mark: Mark = previous.isEmpty ? .none : (p == 0 ? .new : (c > p ? .up : .none))
                return Entry(keyword: k, count: c, previous: p, mark: mark)
            }
            return Overview(notes: current.count, previousNotes: previous.count, entries: entries)
        }

        /// **330 — 가운데 말과 함께 나온 말** (위 여섯).
        public func neighbors(of center: String, today: Int, days: Int) -> [Neighbor] {
            let around = inPeriod(today: today, days: days).filter { $0.keywords.contains(center) }
            var co: [String: Int] = [:]
            for note in around { for k in note.keywords where k != center { co[k, default: 0] += 1 } }
            let chosen = Array(ranked(co, minimum: around.count < 4 ? 1 : 2).prefix(NoteMap.neighborLimit))
            let top = chosen.map { co[$0] ?? 0 }.max() ?? 1
            return chosen.map { k in
                let c = co[k] ?? 0
                return Neighbor(keyword: k, count: c, level: min(3, max(1, (3 * c + top - 1) / top)))
            }
        }

        /// 이 기간 · 그 말(과 둘째 말)이 든 노트 — 날 늦은 것부터, 같으면 경로 순.
        public func notePaths(keyword: String, also: String? = nil, today: Int, days: Int) -> [String] {
            inPeriod(today: today, days: days)
                .filter { note in note.keywords.contains(keyword) && (also.map { note.keywords.contains($0) } ?? true) }
                .sorted { a, b in a.day != b.day ? a.day > b.day : NoteMap.precedes(a.path, b.path) }
                .map(\.path)
        }
    }

    // MARK: - 관계도 자리

    public struct Point: Equatable, Sendable {
        public let x: Double
        public let y: Double
    }

    /// 둘레 n 개를 12시부터 시계 방향으로 고르게 — 단위 원 위 (화면 좌표 — y 가 아래로).
    public static func layout(count: Int) -> [Point] {
        (0..<max(0, count)).map { i in
            let angle = 2 * Double.pi * Double(i) / Double(count)
            return Point(x: sin(angle), y: -cos(angle))
        }
    }
}
