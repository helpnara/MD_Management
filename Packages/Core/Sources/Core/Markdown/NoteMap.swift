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
        "아래", "없이", "있으면", "없으면", "처음", "마지막", "보내", "하면", "되면", "다른", "같은", "없음", "있음",
        // 333 — 형식 · 기능 명사 (사용자가 숨긴 말 · 문맥 다양성이 못 잡는 드문 것까지)
        "관련", "가능", "기존", "기반", "여부", "대상", "부분", "내용", "방법", "사용", "필요", "해당", "각각",
        "일부", "전체", "현재", "최근", "그대로",
    ]
    /// 333 — 굳은 표현 (구절로 세우지 않는다).
    static let fixedPhrases: Set<String> = ["예를 들어", "다시 말해", "그럼에도 불구", "이와 같이"]
    /// 333 — 사람 이름 뒤에 붙는 직함 · 부름말. 성씨로 시작하는 세 글자 이름 + 이 말이면 `사람` 갈래. 직함은 낱말이 아니다.
    static let titles: Set<String> = [
        "대표", "대표님", "책임", "책임님", "선임", "선임님", "수석", "수석님", "팀장", "팀장님", "파트장", "실장", "실장님",
        "본부장", "센터장", "부장", "부장님", "차장", "차장님", "과장", "과장님", "대리", "대리님", "주임", "사원", "이사",
        "이사님", "상무", "상무님", "전무", "전무님", "부사장", "사장", "사장님", "회장", "회장님", "원장", "원장님",
        "소장", "국장", "교수", "교수님", "박사", "박사님", "연구원", "매니저", "프로", "선생님", "변호사", "위원", "위원장",
        "님께",
    ]
    /// 333 — 흔한 성씨 (한 글자 · 두 글자).
    static let surnames = Set("김이박최정강조윤장임한오서신권황안송류전홍고문양손배백허유남심노하곽성차주우구민진지엄채원천방공현함변염여추도소석선설마길연위표명기반라왕금옥육인맹제모탁국어은편용예경봉사부".unicodeScalars)
    static let doubleSurnames: Set<String> = ["남궁", "황보", "제갈", "선우", "독고", "사공", "서문"]
    /// 333 — 한 글자 조사 (두 글자 덩이 *것이 · 예를 · 일에* 를 가르는 데).
    static let oneJosa = Set("은는이가을를의에로와과랑도만나들".unicodeScalars)
    /// 336 — 상태 · 행위어: 주제가 아니라 주제의 상태 (*주제어 중심으로*). 낱말 목록에는 안 세우고 키워드 화면에 *함께 쓴 상태* 로.
    static let status: Set<String> = [
        "진행", "완료", "검토", "확인", "요청", "공유", "준비", "보고", "정리", "시작", "종료", "대기", "보류", "수정",
        "반영", "적용", "처리", "착수", "마감", "연기", "취소", "점검", "논의", "협의", "결정", "전달", "회신", "답변",
    ]
    public static let statusLimit = 5
    /// 335 — 노트 둘 이상의 제목 · 머리글에 나온 말은 꼴 증거 없이 받는다.
    static let headingMinNotes = 2
    static let headingMark = "#"
    /// 334 — 의존 명사 (*것 · 수 · 때 …*) + 한 글자 조사 두 글자 덩이는 늘 뺀다 (*것이* 가 *것이라는 · 것이라도* 때문에 빠져나갔다).
    static let boundNouns = Set("것수때적데등뿐줄바듯분".unicodeScalars)
    /// 334 — *이* 로 끝나는 덩이 뒤의 *라는 · 란 · 라도* 는 *이라는 · 이란 · 이라도* 가 갈라진 것 — 조사 증거로 세지 않는다.
    static let copulaTails: Set<String> = ["라는", "란", "라도"]
    static let i: Unicode.Scalar = "이"
    /// 333 — 동사 연결꼴 끝 (*들어 · 봐 · 해*).
    static let connectiveLast = Set("어아여해워".unicodeScalars)
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

    /// **숨긴 말** (329) — 사용자 폴더 안 숨김 파일. 고정한 노트(`Pins`)와 같은 자리 · 같은 꼴(글 목록 JSON)이라
    /// 읽기 · 쓰기 · 합치기는 `Pins.decode` · `encode` · `merged` 를 그대로 쓴다 (같은 일을 하는 길을 둘 두지 않는다).
    public static let hiddenFileName = ".여백/숨긴말.json"

    /// 333 — 문맥 다양성 (YAKE) — 폴더 전체에서 10번 이상 나온 낱말만 · `(왼쪽 이웃 종류 + 오른쪽) × 100 > 170 × 횟수` 면 뺀다.
    static let diversityMinCount = 10
    static let diversityMaxHundredths = 170
    /// 333 — 사람은 노트 둘 이상 · 구절이 70% 이상 덮는 낱말은 뺀다.
    static let personMinNotes = 2
    static let coverTenths = 7

    /// 구절 (331) — 노트 셋 이상 · 둘 중 드문 말이 든 노트의 40% 이상에서 함께.
    static let phraseMinNotes = 3
    static let phraseShareTenths = 4
    /// 구절의 앞말로 못 서는 꼴 — 동사의 꾸밈꼴(*삭제된 · 않은 · 지운*) · 연결꼴(*아니면 · 완료되면 · 하고*).
    static let frontBadLast = Set("은는던된운".unicodeScalars)
    /// 앞부분이 따로 쓰이는 말이면 꾸밈꼴 (*고정한* ← *고정*) — *디자인 · 확인 · 권한* 은 남는다.
    static let frontVerbLast = Set("한인".unicodeScalars)
    static let frontBadSuffixes = ["하면", "되면", "으면", "라면", "다면", "이면", "니면", "려면", "하고", "되고", "해서", "하며", "하게", "되게",
                                   "하지", "되지", "해도"]

    /// 빈칸이 든 키워드는 구절이다 (331 — 낱말에는 빈칸이 없다).
    public static func isPhrase(_ keyword: String) -> Bool { keyword.contains(" ") }

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

    /// 보이는 글 한 줄 → (말, 꼴) 들 (거르기 전). 구절 후보는 `(앞말 + " " + 뒷말, 뒷말의 조사)` (331).
    static func scan(_ text: [Unicode.Scalar]) -> [Term] {
        var out: [Term] = []
        var i = 0
        let n = text.count
        var bareEnd = -1            // 바로 앞 한글 덩이가 조사 없는 맨꼴이면 그 끝 자리 (구절의 앞말)
        var bareWord = ""
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
                if run.count < 2 {
                    bareEnd = -1
                    continue
                }
                let term = stripJosa(Array(run))
                out.append(term)
                // 구절 (331) — 빈칸 하나(U+0020)로만 떨어진 앞의 맨꼴 덩이와 묶는다.
                if bareEnd >= 0, start == bareEnd + 1, text[bareEnd] == " " {
                    out.append(Term(stem: bareWord + " " + term.stem, form: term.form))
                }
                if term.form.isEmpty {
                    bareEnd = j
                    bareWord = term.stem
                } else {
                    bareEnd = -1
                }
            } else {
                bareEnd = -1
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
        var found = Set<Term>()
        forEachVisibleLine(text) { line, heading in
            for term in scan(line) {
                found.insert(term)
                // 335 — 제목 · 머리글의 낱말 (구절은 빼고) — 꼴 앞에 `#`.
                if heading, !term.stem.contains(" ") { found.insert(Term(stem: term.stem, form: headingMark + term.form)) }
            }
        }
        return found.sorted(by: Term.precedes)
    }

    /// `#` 줄 (앞 빈칸 셋까지 · `#` 한 ~ 여섯 · 뒤가 빈칸 · 탭 · 줄 끝).
    static func isATXHeading(_ s: [Unicode.Scalar]) -> Bool {
        var k = 0
        while k < s.count, k < 4, s[k] == " " { k += 1 }
        guard k <= 3 else { return false }
        var n = 0
        while k + n < s.count, s[k + n] == "#" { n += 1 }
        guard (1...6).contains(n) else { return false }
        return k + n == s.count || s[k + n] == " " || s[k + n] == "\t"
    }

    /// 셈할 줄 — 머리말 뒤 · 코드 · 주석 · 울타리 줄을 빼고 · 미리보기로 보이는 글만. `terms` · `context` 가 **이것 하나**를 쓴다.
    static func forEachVisibleLine(_ text: String, _ body: ([Unicode.Scalar], Bool) -> Void) {
        let main = FrontMatterParser.parse(Paths.normalized(text)).body
        var lines: [[Unicode.Scalar]] = [[]]
        for s in main.unicodeScalars {
            if s == "\n" { lines.append([]) } else { lines[lines.count - 1].append(s) }
        }
        lines = lines.map { $0.last == "\r" ? Array($0.dropLast()) : $0 }
        let strings = lines.map { string(ArraySlice($0)) }
        let roles = BlockContext.roles(of: strings)
        for (index, line) in lines.enumerated() {
            switch roles[index] {
            case .code, .indentedCode, .comment: continue
            default: break
            }
            if NoteStats.fence(line) != nil { continue }
            let heading = roles[index] == .heading1 || roles[index] == .heading2 || isATXHeading(line)
            body(Array(PreviewLine.plain(strings[index]).unicodeScalars), heading)
        }
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
        /// 333 — 노트 하나의 문맥 (`context(of:)`). 없으면 문맥 다양성을 재지 않는다.
        public let context: [String: Context]

        public init(path: String, day: Int, terms: [Term], context: [String: Context] = [:]) {
            self.path = path
            self.day = day
            self.terms = terms
            self.context = context
        }
    }

    /// 333 — 낱말 하나의 문맥 — 나온 횟수 · 한 줄 안 바로 앞 · 뒤 낱말 줄기 (코드 포인트 순).
    public struct Context: Equatable, Sendable {
        public let count: Int
        public let left: [String]
        public let right: [String]

        public init(count: Int, left: [String], right: [String]) {
            self.count = count
            self.left = left
            self.right = right
        }
    }

    /// 333 — **노트 하나의 문맥** — 색인에 쓸 때 부른다 (`terms(of:)` 와 같은 줄 · 같은 낱말).
    public static func context(of text: String) -> [String: Context] {
        var stats: [String: (Int, Set<String>, Set<String>)] = [:]
        forEachVisibleLine(text) { line, _ in
            let toks = scan(line).map(\.stem).filter { !$0.contains(" ") }
            for (i, t) in toks.enumerated() {
                var entry = stats[t] ?? (0, [], [])
                entry.0 += 1
                if i > 0 { entry.1.insert(toks[i - 1]) }
                if i + 1 < toks.count { entry.2.insert(toks[i + 1]) }
                stats[t] = entry
            }
        }
        return stats.mapValues { Context(count: $0.0, left: $0.1.sorted(by: precedes), right: $0.2.sorted(by: precedes)) }
    }

    /// 색인 칸에 담는 문맥 — 줄마다 `말\t횟수\t왼쪽,…\t오른쪽,…` (낱말에는 빈칸 · 쉼표 · 줄바꿈이 없다).
    public static func encode(_ context: [String: Context]) -> String {
        context.keys.sorted(by: precedes).map { k in
            let c = context[k]!
            return k + "\t" + String(c.count) + "\t" + c.left.joined(separator: ",") + "\t" + c.right.joined(separator: ",")
        }.joined(separator: "\n")
    }

    public static func decodeContext(_ text: String) -> [String: Context] {
        var out: [String: Context] = [:]
        for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
            let parts = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            guard parts.count == 4, let count = Int(parts[1]) else { continue }
            func list(_ s: String) -> [String] { s.isEmpty ? [] : s.split(separator: ",").map(String.init) }
            out[parts[0]] = Context(count: count, left: list(parts[2]), right: list(parts[3]))
        }
        return out
    }

    /// 차례 (331 · 사용자 정함 — 기본 많이 쓴 순). `count` 노트 수 큰 것부터(같으면 두드러진 것) · `score` 두드러진 순.
    public enum Order: String, Sendable, Equatable, CaseIterable {
        case count
        case score
    }

    /// 333 — 키워드 갈래.
    public enum Kind: String, Sendable, Equatable {
        case word
        case phrase
        case person
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
            /// 335 — 제목 · 머리글에 나온 말.
            let heads: Set<String>
            /// 336 — 함께 쓴 상태어.
            let status: Set<String>
        }

        let notes: [Note]
        let df: [String: Int]
        /// 333 — 사람 (이름 + 직함) — 지도의 `사람` 구역 (참고용).
        public let people: Set<String>
        public var total: Int { notes.count }
        /// 받은 키워드 전부 (코드 포인트 순).
        public var keywords: [String] { df.keys.sorted(by: NoteMap.precedes) }

        public init(rows: [Row], hidden: Set<String> = []) {
            let wordTerms = rows.map { $0.terms.filter { !$0.stem.contains(" ") && !$0.form.hasPrefix(NoteMap.headingMark) } }
            let headingTerms = rows.map { row in
                row.terms.filter { $0.form.hasPrefix(NoteMap.headingMark) }.map { Term(stem: $0.stem, form: String($0.form.dropFirst())) }
            }
            let phraseTerms = rows.map { $0.terms.filter { $0.stem.contains(" ") } }
            var stemForms: [String: Set<String>] = [:]
            for terms in wordTerms {
                for term in terms { stemForms[term.stem, default: []].insert(term.form) }
            }
            // 한 글자 조사만 (*전문가 · 고양이*) — 두 글자 조사까지 풀면 *화면에서* 가 한 말이 된다 (331 시제품).
            func resolve(_ term: Term) -> Term {
                if term.form.unicodeScalars.count == 1, let forms = stemForms[term.stem + term.form],
                   forms.contains(where: { NoteMap.strongSet.contains($0) }) {
                    return Term(stem: term.stem + term.form, form: "")
                }
                return term
            }
            let resolved = wordTerms.map { $0.map(resolve) }
            // 335 — 노트마다 제목 · 머리글에 나온 말 (풀어서) · 그런 노트 수.
            let heads = headingTerms.map { Set($0.map { resolve($0).stem }) }
            var headDF: [String: Int] = [:]
            for hs in heads { for k in hs { headDF[k, default: 0] += 1 } }
            var kwForms: [String: Set<String>] = [:]
            for pairs in resolved {
                for term in pairs { kwForms[term.stem, default: []].insert(term.form) }
            }

            // 333 — 문맥 다양성: 폴더 전체의 나온 횟수 · 이웃 종류.
            var ctxCount: [String: Int] = [:]
            var ctxLeft: [String: Set<String>] = [:]
            var ctxRight: [String: Set<String>] = [:]
            for row in rows {
                for (k, c) in row.context {
                    ctxCount[k, default: 0] += c.count
                    ctxLeft[k, default: []].formUnion(c.left)
                    ctxRight[k, default: []].formUnion(c.right)
                }
            }
            func tooDiverse(_ k: String) -> Bool {
                let c = ctxCount[k] ?? 0
                return c >= NoteMap.diversityMinCount
                    && ((ctxLeft[k]?.count ?? 0) + (ctxRight[k]?.count ?? 0)) * 100 > NoteMap.diversityMaxHundredths * c
            }
            // 333 — 한 글자 + 한 글자 조사 (*것이 · 예를 · 일에*) — *회의 · 차이* 는 센 조사를 받아 남는다.
            var josaVariants: [Unicode.Scalar: Int] = [:]      // 앞 글자 → *그 글자 + 한 글자 조사* 덩이 수
            for x in kwForms.keys {
                let v = Array(x.unicodeScalars)
                if v.count == 2, NoteMap.oneJosa.contains(v[1]) { josaVariants[v[0], default: 0] += 1 }
            }
            func oneSyllableJosa(_ k: String) -> Bool {
                let s = Array(k.unicodeScalars)
                guard s.count == 2, NoteMap.oneJosa.contains(s[1]) else { return false }
                if NoteMap.boundNouns.contains(s[0]) { return true }
                let nounEvidence = (kwForms[k] ?? []).contains { f in
                    NoteMap.strongSet.contains(f) && !(s[1] == NoteMap.i && NoteMap.copulaTails.contains(f))
                }
                return !nounEvidence && (josaVariants[s[0]] ?? 0) >= 3
            }
            // 구절의 앞말 · 낱말 모두 — 동사의 꾸밈꼴 · 연결꼴 (333 부터 낱말에도).
            func badFront(_ word: String) -> Bool {
                let s = Array(word.unicodeScalars)
                guard let last = s.last else { return true }
                if NoteMap.frontBadLast.contains(last) { return true }
                if NoteMap.frontVerbLast.contains(last), s.count >= 3, stemForms[NoteMap.string(s[..<(s.count - 1)])] != nil { return true }
                return NoteMap.frontBadSuffixes.contains { suffix in
                    let x = Array(suffix.unicodeScalars)
                    return s.count > x.count && s.suffix(x.count).elementsEqual(x)
                }
            }
            var accepted: [String: Bool] = [:]
            for (k, forms) in kwForms {
                if hidden.contains(k) {
                    accepted[k] = false
                } else if NoteMap.isASCIIWord(k) {
                    accepted[k] = !tooDiverse(k)
                } else if k.unicodeScalars.count < 2 || NoteMap.stop.contains(k) || NoteMap.titles.contains(k)
                            || NoteMap.isBadStem(k) || badFront(k) || oneSyllableJosa(k) || tooDiverse(k) {
                    accepted[k] = false
                } else {
                    // 335 — 조사를 받은 꼴이 없어도 노트 둘 이상의 제목 · 머리글에 나오면 받는다.
                    accepted[k] = forms.filter { $0.isEmpty || NoteMap.strongSet.contains($0) }.count >= 2
                        || (headDF[k] ?? 0) >= NoteMap.headingMinNotes
                }
            }
            let taken = resolved.map { Set($0.map(\.stem).filter { accepted[$0] == true }) }
            // 336 — 상태어는 낱말에서 빼고 노트의 상태로 (표에 있으면 꼴 증거 없이 센다 · 구절의 뒷말로는 받은 말일 때 쓴다).
            let words = taken.map { $0.subtracting(NoteMap.status) }
            let statuses = resolved.map { Set($0.map(\.stem).filter { NoteMap.status.contains($0) && !hidden.contains($0) }) }
            var wordDF: [String: Int] = [:]
            for ks in taken { for k in ks { wordDF[k, default: 0] += 1 } }
            // 구절의 앞말은 낱말 키워드가 아니어도 된다 (*주간 · 개인정보* 는 늘 맨꼴로 앞에만 선다). 그 말이 든 노트 수.
            var stemDF: [String: Int] = [:]
            for pairs in resolved { for k in Set(pairs.map(\.stem)) { stemDF[k, default: 0] += 1 } }

            // 구절 (331) · 사람 (333) — 뒷말이 직함이면 사람 후보 (앞말은 성씨 + 두 글자 · 두 글자 성이면 네 글자).
            var candidates: [Set<String>] = []
            var personCandidates: [Set<String>] = []
            for terms in phraseTerms {
                var found = Set<String>()
                var people = Set<String>()
                for term in terms {
                    let parts = term.stem.split(separator: " ", maxSplits: 1).map(String.init)
                    guard parts.count == 2 else { continue }
                    let first = parts[0]
                    let second = resolve(Term(stem: parts[1], form: term.form)).stem
                    let f = Array(first.unicodeScalars)
                    if first == second || hidden.contains(first) || NoteMap.stop.contains(first) || NoteMap.isBadStem(first)
                        || badFront(first) || oneSyllableJosa(first)
                        || (f.last.map { NoteMap.connectiveLast.contains($0) } == true && accepted[first] != true) {
                        continue
                    }
                    if NoteMap.titles.contains(second) {
                        if (f.count == 3 && NoteMap.surnames.contains(f[0]))
                            || (f.count == 4 && NoteMap.doubleSurnames.contains(NoteMap.string(f[0..<2]))) {
                            people.insert(first + " " + second)
                        }
                        continue
                    }
                    let phrase = first + " " + second
                    if accepted[second] == true, !NoteMap.fixedPhrases.contains(phrase) { found.insert(phrase) }
                }
                candidates.append(found)
                personCandidates.append(people)
            }
            var phraseDF: [String: Int] = [:]
            for found in candidates { for p in found { phraseDF[p, default: 0] += 1 } }
            var good = Set<String>()
            for (p, c) in phraseDF where !hidden.contains(p) && c >= NoteMap.phraseMinNotes {
                let parts = p.split(separator: " ", maxSplits: 1).map(String.init)
                if c * 10 >= NoteMap.phraseShareTenths * min(stemDF[parts[0]] ?? 0, wordDF[parts[1]] ?? 0) { good.insert(p) }
            }

            var personDF: [String: Int] = [:]
            for people in personCandidates { for p in people { personDF[p, default: 0] += 1 } }
            let people = Set(personDF.filter { $0.value >= NoteMap.personMinNotes && !hidden.contains($0.key) }.keys)
            let names = Set(people.compactMap { $0.split(separator: " ", maxSplits: 1).first.map(String.init) })

            // 333 — 구절이 덮는 낱말: 낱말이 든 노트의 70% 이상에 그 낱말을 품은 받은 구절이 함께 있으면 낱말은 뺀다.
            var covered: [String: Int] = [:]
            for (ks, found) in zip(words, candidates) {
                var parts = Set<String>()
                for p in found.intersection(good) { parts.formUnion(p.split(separator: " ", maxSplits: 1).map(String.init)) }
                for k in ks.intersection(parts) { covered[k, default: 0] += 1 }
            }
            var dropped = names
            for (k, c) in covered where c * 10 >= NoteMap.coverTenths * (wordDF[k] ?? 0) { dropped.insert(k) }

            var notes: [Note] = []
            var df: [String: Int] = [:]
            for (i, row) in rows.enumerated() {
                let keywords = words[i].subtracting(dropped).union(candidates[i].intersection(good))
                    .union(personCandidates[i].intersection(people))
                for k in keywords { df[k, default: 0] += 1 }
                notes.append(Note(path: row.path, day: row.day, keywords: keywords, heads: heads[i], status: statuses[i]))
            }
            self.notes = notes
            self.df = df
            self.people = people
        }

        /// 333 — `person` (이름 + 직함) · `phrase` (두 낱말) · `word`.
        public func kind(of keyword: String) -> Kind {
            if people.contains(keyword) { return .person }
            return NoteMap.isPhrase(keyword) ? .phrase : .word
        }

        func score(_ count: Int, _ keyword: String) -> Int {
            let value = Double(count) * log(Double(total + 1) / Double(df[keyword] ?? 1)) * NoteMap.scoreScale
            return Int((value + 0.5).rounded(.down))
        }

        /// `heads` — 이 기간에 그 말이 제목 · 머리글에 나온 노트 수 (335 · 지도 목록만 · 둘레는 빈 것).
        func ranked(_ counts: [String: Int], minimum: Int, by order: Order = .score, heads: [String: Int] = [:]) -> [String] {
            let chosen = counts.filter { $0.value >= minimum }.map { entry -> (key: String, count: Int, head: Int, score: Int) in
                let h = heads[entry.key] ?? 0
                // 두드러진 순은 제목 노트를 한 번 더 센다 · 많이 쓴 순의 같은 수 안에서는 원래 점수.
                return (entry.key, entry.value, h, score(entry.value + (order == .score ? h : 0), entry.key))
            }
            return chosen.sorted { a, b in
                if order == .count {
                    if a.count != b.count { return a.count > b.count }
                    if a.head != b.head { return a.head > b.head }
                }
                return a.score != b.score ? a.score > b.score : NoteMap.precedes(a.key, b.key)
            }.map(\.key)
        }

        func inPeriod(today: Int, days: Int) -> [Note] {
            notes.filter { today - $0.day < days }
        }

        /// **329 — 이 기간의 키워드** (많이 나온 순 · 흔한 말은 낮게).
        public func overview(today: Int, days: Int, by order: Order = .count) -> Overview {
            let current = inPeriod(today: today, days: days)
            let previous = notes.filter { today - $0.day >= days && today - $0.day < 2 * days }
            var cur: [String: Int] = [:]
            var prev: [String: Int] = [:]
            var head: [String: Int] = [:]
            for note in current {
                for k in note.keywords {
                    cur[k, default: 0] += 1
                    if note.heads.contains(k) { head[k, default: 0] += 1 }
                }
            }
            for note in previous { for k in note.keywords { prev[k, default: 0] += 1 } }
            let keys = ranked(cur, minimum: current.count < 10 ? 1 : 2, by: order, heads: head)
            let entries = keys.map { k -> Entry in
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
            // 가운데와 낱말이 겹치는 것(구절과 그 안의 낱말)은 둘레에 세우지 않는다 — 늘 함께 나오니 뜻이 없다.
            let centerWords = Set(center.split(separator: " "))
            // 333 — 사람은 가운데가 사람일 때만 둘레에 (지도는 요즘 동향 · 사람은 참고용 — 사용자).
            let centerIsPerson = people.contains(center)
            for note in around {
                for k in note.keywords where k != center && centerWords.isDisjoint(with: k.split(separator: " "))
                    && (centerIsPerson || !people.contains(k)) {
                    co[k, default: 0] += 1
                }
            }
            let chosen = Array(ranked(co, minimum: around.count < 4 ? 1 : 2).prefix(NoteMap.neighborLimit))
            let top = chosen.map { co[$0] ?? 0 }.max() ?? 1
            return chosen.map { k in
                let c = co[k] ?? 0
                return Neighbor(keyword: k, count: c, level: min(3, max(1, (3 * c + top - 1) / top)))
            }
        }

        /// **336 — 가운데 말과 함께 쓴 상태어** (노트 수 · 많은 것부터 · 같으면 코드 포인트 순 · 다섯까지).
        public func statuses(of center: String, today: Int, days: Int) -> [(keyword: String, count: Int)] {
            var count: [String: Int] = [:]
            for note in inPeriod(today: today, days: days) where note.keywords.contains(center) {
                for k in note.status { count[k, default: 0] += 1 }
            }
            let order = count.keys.sorted { a, b in count[a]! != count[b]! ? count[a]! > count[b]! : NoteMap.precedes(a, b) }
            return order.prefix(NoteMap.statusLimit).map { ($0, count[$0]!) }
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
    /// 넷이면 45도 돌린다 — 3시 · 9시 자리의 말이 가로로 긴 가운데 칸에 붙는다 (빌드 화면 사진).
    public static func layout(count: Int) -> [Point] {
        let start = count == 4 ? Double.pi / 4 : 0
        return (0..<max(0, count)).map { i in
            let angle = start + 2 * Double.pi * Double(i) / Double(count)
            return Point(x: sin(angle), y: -cos(angle))
        }
    }
}
