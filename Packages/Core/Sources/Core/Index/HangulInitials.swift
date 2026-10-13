import Foundation

/// **제목 초성 찾기** (246, 2026-10-13 사용자 — *제목만 초성으로 찾는 것만 진행하면 될 것 같아. 본문 내용을 초성을 통해서
/// 검색할 일은 거의 없을 것 같아*).
///
/// 검색 칸의 말이 **한글 자음만**(빈칸은 빼고 둘 이상)이면 노트 **제목**의 첫소리와 견준다 — `ㅎㅇㄹ` → *회의록*.
/// 본문은 안 본다. 보통 검색을 대신하지 않고 **더한다** — 본문에 `ㅎㅎ` 를 쓴 노트도 지금처럼 찾힌다 (`SearchIndex.search`).
///
/// 아이폰 한글 자판은 `ㄱ` `ㅅ` 를 이어 치면 `ㄳ` 한 글자로 합칠 수 있다 — 겹자음은 **풀어서** 견준다 (`ㄳ` → `ㄱㅅ`).
/// 된소리(`ㄲ`)는 그대로다 — `까` 만 맞고 `가` 는 안 맞는다. 제목의 숫자 · 영어 · 빈칸 · 모음은 건너뛴다.
///
/// 파이썬 쌍둥이: `Tools/golden/generate.py` 의 `hangul_initials` (`initialsCases`) — 글자 **이름**으로 셈한다
/// (`HANGUL CHOSEONG …` → `HANGUL LETTER …`). 여기는 음절 번호 셈이라 두 셈이 서로의 심판이다.
public enum HangulInitials {

    /// 음절의 첫소리 19개 — 한글 음절 번호 `(글자 - 0xAC00) / 588` 의 차례.
    static let leads: [Unicode.Scalar] = [
        "ㄱ", "ㄲ", "ㄴ", "ㄷ", "ㄸ", "ㄹ", "ㅁ", "ㅂ", "ㅃ", "ㅅ",
        "ㅆ", "ㅇ", "ㅈ", "ㅉ", "ㅊ", "ㅋ", "ㅌ", "ㅍ", "ㅎ",
    ]

    /// 겹자음을 푼 모양.
    static let clusters: [Unicode.Scalar: String] = [
        "ㄳ": "ㄱㅅ", "ㄵ": "ㄴㅈ", "ㄶ": "ㄴㅎ", "ㄺ": "ㄹㄱ", "ㄻ": "ㄹㅁ", "ㄼ": "ㄹㅂ",
        "ㄽ": "ㄹㅅ", "ㄾ": "ㄹㅌ", "ㄿ": "ㄹㅍ", "ㅀ": "ㄹㅎ", "ㅄ": "ㅂㅅ",
    ]

    /// 한글 호환 자음 (`ㄱ` U+3131 ~ `ㅎ` U+314E).
    static func isConsonant(_ scalar: Unicode.Scalar) -> Bool {
        (0x3131...0x314E).contains(scalar.value)
    }

    /// 자음 하나를 풀어 쓴 것 — 겹자음이면 둘, 아니면 그대로.
    static func expanded(_ scalar: Unicode.Scalar) -> String {
        clusters[scalar] ?? String(Character(scalar))
    }

    /// **제목의 첫소리 줄** — 음절은 첫소리, 자음 글자는 풀어서 그대로, 나머지는 건너뛴다.
    public static func initials(of title: String) -> String {
        var out = ""
        for scalar in Paths.normalized(title).unicodeScalars {
            let value = scalar.value
            if (0xAC00...0xD7A3).contains(value) {
                out.unicodeScalars.append(leads[Int((value - 0xAC00) / 588)])
            } else if isConsonant(scalar) {
                out += expanded(scalar)
            }
        }
        return out
    }

    /// **검색 말이 초성 찾기인가** — 빈칸을 빼고 모두 한글 자음이고, 풀어서 둘 이상이면 푼 자음 줄. 아니면 `nil`.
    public static func query(_ raw: String) -> String? {
        var out = ""
        for scalar in Paths.normalized(raw).unicodeScalars {
            if CharacterSet.whitespacesAndNewlines.contains(scalar) { continue }
            guard isConsonant(scalar) else { return nil }
            out += expanded(scalar)
        }
        return out.unicodeScalars.count >= 2 ? out : nil
    }

    /// 제목의 첫소리 줄에 검색 자음 줄이 **이어서** 들어 있나.
    public static func matches(title: String, query: String) -> Bool {
        !query.isEmpty && initials(of: title).contains(query)
    }
}
