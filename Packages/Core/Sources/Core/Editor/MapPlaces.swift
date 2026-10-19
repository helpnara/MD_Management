import Foundation

/// **지도 앱이 공유한 장소 글을 링크로** (252, 2026-10-19 사용자 — *붙여넣기 기능 개선*).
///
/// 지도 앱의 *공유 → 복사* 는 이런 글을 준다 (장소 이름 · 주소 · 짧은 주소):
///
///     [네이버지도]                 [카카오맵] 우레https://kko.to/E6exlP7ZR2
///     우레 분당 정자본점
///     경기 성남시 분당구 정자일로 158
///     https://naver.me/GcAsok6a
///
/// **장소는 머리말(`[네이버지도]` · `[카카오맵]`)에서 다음 머리말까지다** — 줄이 아니라 머리말로 나눈다 (빌드 109 사용자 —
/// *카카오맵 둘이 하나처럼 인식*). 줄로 나누면 두 장소가 한 줄로 붙어 오거나 빈 줄에 보이지 않는 글자(`U+00A0` · `U+200B`)가
/// 끼어 올 때 통째로 못 읽었다. 장소 안에서 `http(s)://` 주소 앞의 글 줄은 **첫 줄이 이름, 나머지가 주소**이고 주소 뒤에는
/// 빈칸만 있어야 한다. 장소는 `[이름](<주소>) : 주소` 한 줄.
///
/// - **글 전체가 장소들이어야만 바꾼다** — 첫 머리말 앞의 글 · 주소 없는 장소 · 주소 뒤에 남은 글이 하나라도 있으면 nil.
///   모르는 글은 손대지 않는다 (붙여넣기는 원래 글을 그대로 붙인다).
/// - 빈칸 · 줄바꿈은 **못 박은 목록**(`blanks` · `breaks`)으로 본다 — 플랫폼마다 *빈칸* 의 뜻이 달라 파이썬 쌍둥이와 갈리지 않게.
///   글은 먼저 NFC 로 모은다 — 풀어 쓴(NFD) 한글 머리말도 같은 머리말이다.
/// - 장소 사이에 **빈 줄**을 둔다 — 한 번 엔터로 이으면 읽기 화면에서 한 문단으로 붙는다 (199 · 207 과 같은 까닭).
///
/// 파이썬 쌍둥이: `Tools/golden/generate.py` 의 `map_places` (`mapCases`).
public enum MapPlaces {

    public struct Place: Equatable, Sendable {
        public let name: String
        /// 이름 다음 글 줄들을 빈칸으로 이은 것. 카카오맵처럼 이름뿐이면 nil.
        public let address: String?
        public let url: String
    }

    /// 지도 앱의 공유 글 머리말.
    static let headers: [[Unicode.Scalar]] = ["[네이버지도]", "[카카오맵]"].map { Array($0.unicodeScalars) }

    /// 줄바꿈으로 보는 글자.
    static let breaks: Set<Unicode.Scalar> = ["\n", "\r", "\u{0B}", "\u{0C}", "\u{85}", "\u{2028}", "\u{2029}"]

    /// 빈칸으로 보는 글자 — 줄바꿈 · 빈칸 · 탭 · 붙는 빈칸(`U+00A0`) · 넓은 빈칸 · 보이지 않는 폭 없는 글자.
    static let blanks: Set<Unicode.Scalar> = breaks.union([
        " ", "\t", "\u{A0}", "\u{1680}", "\u{2000}", "\u{2001}", "\u{2002}", "\u{2003}", "\u{2004}", "\u{2005}",
        "\u{2006}", "\u{2007}", "\u{2008}", "\u{2009}", "\u{200A}", "\u{200B}", "\u{200C}", "\u{200D}", "\u{202F}",
        "\u{205F}", "\u{2060}", "\u{3000}", "\u{FEFF}",
    ])

    /// 글 전체가 지도 장소들이면 그 장소들. 아니면 nil.
    public static func places(in text: String) -> [Place]? {
        let scalars = Array(text.precomposedStringWithCanonicalMapping.unicodeScalars)
        // 머리말 자리 — 앞에서부터 겹치지 않게.
        var marks: [(start: Int, end: Int)] = []
        var index = 0
        while index < scalars.count {
            if let header = headers.first(where: { starts(scalars, at: index, with: $0) }) {
                marks.append((index, index + header.count))
                index += header.count
            } else {
                index += 1
            }
        }
        guard let first = marks.first, scalars[..<first.start].allSatisfy({ blanks.contains($0) }) else { return nil }
        var places: [Place] = []
        for (number, mark) in marks.enumerated() {
            let end = number + 1 < marks.count ? marks[number + 1].start : scalars.count
            guard let place = parsePlace(Array(scalars[mark.end..<end])) else { return nil }
            places.append(place)
        }
        return places
    }

    /// 머리말 뒤 한 장소의 글자들 → 장소. 주소가 없거나 주소 뒤에 글이 남으면 nil.
    private static func parsePlace(_ scalars: [Unicode.Scalar]) -> Place? {
        let https = Array("https://".unicodeScalars)
        let http = Array("http://".unicodeScalars)
        guard let start = scalars.indices.first(where: { starts(scalars, at: $0, with: https) || starts(scalars, at: $0, with: http) })
        else { return nil }
        var stop = start
        while stop < scalars.count, !blanks.contains(scalars[stop]) { stop += 1 }
        let url = string(scalars[start..<stop])
        guard scalars[stop...].allSatisfy({ blanks.contains($0) }), Pasting.isWebAddress(url),
              !url.contains("<"), !url.contains(">") else { return nil }
        // 주소 앞의 글 — 줄마다 앞뒤 빈칸을 떼고 빈 줄은 버린다.
        var texts: [String] = []
        var line: [Unicode.Scalar] = []
        for scalar in Array(scalars[..<start]) + ["\n"] {
            if breaks.contains(scalar) {
                var from = 0, to = line.count
                while from < to, blanks.contains(line[from]) { from += 1 }
                while to > from, blanks.contains(line[to - 1]) { to -= 1 }
                if from < to { texts.append(string(line[from..<to])) }
                line = []
            } else {
                line.append(scalar)
            }
        }
        guard let name = texts.first else { return nil }
        let address = texts.dropFirst().joined(separator: " ")
        return Place(name: name, address: address.isEmpty ? nil : address, url: url)
    }

    /// 글에 지도 머리말이 들어 있나 — 장소로 못 읽었을 때 붙여넣기 진단에 남기려고 (빌드 109).
    public static func mentioned(in text: String) -> Bool {
        let scalars = Array(text.precomposedStringWithCanonicalMapping.unicodeScalars)
        return scalars.indices.contains { index in headers.contains { starts(scalars, at: index, with: $0) } }
    }

    /// 장소 한 줄 — `[이름](<주소>) : 주소`. 이름의 대괄호는 노트 연결과 같이 역슬래시로 피한다.
    public static func line(_ place: Place) -> String {
        "[" + NoteLinking.escapedLabel(place.name) + "](<" + place.url + ">)"
            + (place.address.map { " : " + $0 } ?? "")
    }

    /// **붙여넣을 글** — 장소마다 한 줄, 사이에 빈 줄. 지도 장소 글이 아니면 nil.
    public static func pasted(_ text: String) -> String? {
        places(in: text).map { $0.map(line).joined(separator: "\n\n") }
    }

    // MARK: - 자잘한 것

    private static func starts(_ scalars: [Unicode.Scalar], at index: Int, with mark: [Unicode.Scalar]) -> Bool {
        guard index + mark.count <= scalars.count else { return false }
        for offset in 0..<mark.count where scalars[index + offset] != mark[offset] { return false }
        return true
    }

    private static func string<S: Sequence>(_ scalars: S) -> String where S.Element == Unicode.Scalar {
        var view = String.UnicodeScalarView()
        view.append(contentsOf: scalars)
        return String(view)
    }
}
