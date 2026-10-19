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
/// 머리말 뒤의 글 줄은 **첫 줄이 이름, 나머지가 주소**이고, 주소(`http(s)://`)가 나오면 그 장소가 끝난다 —
/// 같은 줄 앞에 붙은 글(카카오맵은 이름과 주소 사이에 빈칸이 없다)은 글 줄이다. 장소는 `[이름](<주소>) : 주소` 한 줄.
///
/// - **글 전체가 장소들이어야만 바꾼다** — 머리말이 아닌 줄 · 주소 없이 끝난 장소 · 주소 뒤에 남은 글이 하나라도 있으면 nil.
///   모르는 글은 손대지 않는다 (붙여넣기는 원래 글을 그대로 붙인다).
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
    static let headers = ["[네이버지도]", "[카카오맵]"]

    /// 글 전체가 지도 장소들이면 그 장소들. 아니면 nil.
    public static func places(in text: String) -> [Place]? {
        let lines = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n").map { IncomingShare.trimmed($0) }
        var places: [Place] = []
        var index = 0
        while index < lines.count {
            if lines[index].isEmpty { index += 1; continue }
            guard let header = headers.first(where: { lines[index].hasPrefix($0) }) else { return nil }
            var rest = IncomingShare.trimmed(String(lines[index].dropFirst(header.count)))
            var texts: [String] = []
            var url = ""
            while true {
                if let start = addressStart(in: rest) {
                    let before = IncomingShare.trimmed(String(rest[..<start]))
                    let tail = rest[start...]
                    url = String(tail.prefix { $0 != " " && $0 != "\t" })
                    guard IncomingShare.trimmed(String(tail.dropFirst(url.count))).isEmpty,
                          Pasting.isWebAddress(url), !url.contains("<"), !url.contains(">") else { return nil }
                    if !before.isEmpty { texts.append(before) }
                    break
                }
                if !rest.isEmpty { texts.append(rest) }
                index += 1
                // 주소 없이 글이 끝났거나 · 빈 줄 · 다음 머리말이 먼저 나왔다 — 장소가 아니다.
                guard index < lines.count, !lines[index].isEmpty,
                      !headers.contains(where: { lines[index].hasPrefix($0) }) else { return nil }
                rest = lines[index]
            }
            guard let name = texts.first else { return nil }
            let address = texts.dropFirst().joined(separator: " ")
            places.append(Place(name: name, address: address.isEmpty ? nil : address, url: url))
            index += 1
        }
        return places.isEmpty ? nil : places
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

    /// `http://` · `https://` 가 처음 나오는 자리.
    private static func addressStart(in text: String) -> String.Index? {
        [text.range(of: "https://"), text.range(of: "http://")].compactMap { $0?.lowerBound }.min()
    }
}
