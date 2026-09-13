import Foundation

/// 사용자가 친 검색어를 두 갈래로 나눈 것.
///
/// **FTS5 의 trigram 토크나이저는 3글자 미만 질의에 아무것도 반환하지 않는다.**
/// 한국어에서 `회의` · `세금` 같은 2글자 검색어가 가장 흔하므로, 짧은 낱말은
/// `LIKE` 폴백으로 보낸다 (ADR-0003).
public struct SearchQuery: Equatable, Sendable {
    /// 3글자 이상 — `note_fts MATCH` 로 간다.
    public var ftsTerms: [String]
    /// 2글자 이하 — `body LIKE '%…%'` 폴백으로 간다.
    public var likeTerms: [String]
    /// `tag:앱`
    public var tags: [String]
    /// `path:아이디어/`
    public var pathPrefix: String?

    public init(ftsTerms: [String] = [], likeTerms: [String] = [], tags: [String] = [], pathPrefix: String? = nil) {
        self.ftsTerms = ftsTerms
        self.likeTerms = likeTerms
        self.tags = tags
        self.pathPrefix = pathPrefix
    }

    public var isEmpty: Bool {
        ftsTerms.isEmpty && likeTerms.isEmpty && tags.isEmpty && pathPrefix == nil
    }

    /// 느린 경로를 타야 하는가. 진단 화면에 보여 준다.
    public var needsFallback: Bool { !likeTerms.isEmpty }
}

public enum SearchQueryParser {

    /// trigram 이 다룰 수 있는 가장 짧은 길이.
    public static let trigramMinimum = 3

    /// 검색어를 판다. 순수 함수라 리눅스 `swift test` 로 검증한다.
    ///
    /// 문법: 공백 = AND · `"…"` = 구절 · `tag:앱` · `path:아이디어/`
    public static func parse(_ raw: String) -> SearchQuery {
        var query = SearchQuery()

        for token in tokenize(Paths.normalized(raw)) {
            if token.quoted {
                append(token.text, to: &query)
                continue
            }
            if let value = value(of: token.text, prefix: "tag:") {
                if !value.isEmpty { query.tags.append(value) }
                continue
            }
            if let value = value(of: token.text, prefix: "path:") {
                if !value.isEmpty { query.pathPrefix = value }
                continue
            }
            append(token.text, to: &query)
        }
        return query
    }

    /// `note_fts MATCH ?` 에 넣을 구문. 넣을 것이 없으면 `nil`.
    ///
    /// 낱말마다 큰따옴표로 감싸 **구절**로 만든다. trigram 색인에서는 이것이
    /// 부분 문자열 검색이 된다.
    ///
    /// **태그는 여기 넣지 않는다.** 태그는 대개 한두 글자라 trigram 이 아예 못 찾는다.
    /// `note.tags` 칼럼을 `tagLikePatterns(for:)` 로 직접 거른다.
    public static func ftsExpression(for query: SearchQuery) -> String? {
        guard !query.ftsTerms.isEmpty else { return nil }
        return query.ftsTerms.map { quoteForFTS($0) }.joined(separator: " AND ")
    }

    /// `note.tags LIKE ? ESCAPE '\\'` 에 넣을 무늬들.
    ///
    /// `note.tags` 는 공백으로 구분한 문자열이므로 앞뒤에 공백을 붙여 **낱말 전체**가
    /// 맞을 때만 걸리게 한다 (`앱` 이 `앱스토어` 에 걸리지 않게).
    public static func tagLikePatterns(for query: SearchQuery) -> [String] {
        query.tags.map { tag in
            var escaped = ""
            for ch in tag {
                if ch == "\\" || ch == "%" || ch == "_" { escaped.append("\\") }
                escaped.append(ch)
            }
            return "% " + escaped + " %"
        }
    }

    /// `body LIKE ? ESCAPE '\'` 에 넣을 무늬들. AND 로 엮는다.
    public static func likePatterns(for query: SearchQuery) -> [String] {
        query.likeTerms.map { likePattern(for: $0) }
    }

    /// 한 낱말을 `%…%` 무늬로. `%` `_` `\` 를 막는다.
    public static func likePattern(for term: String) -> String {
        var escaped = ""
        for ch in term {
            if ch == "\\" || ch == "%" || ch == "_" { escaped.append("\\") }
            escaped.append(ch)
        }
        return "%" + escaped + "%"
    }

    /// FTS5 문자열 안에서 큰따옴표는 두 번 적어 막는다.
    public static func quoteForFTS(_ term: String) -> String {
        "\"" + term.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    // MARK: - 속

    private static func append(_ text: String, to query: inout SearchQuery) {
        let term = text.trimmingCharacters(in: .whitespaces)
        guard !term.isEmpty else { return }
        // trigram 은 유니코드 스칼라 단위로 센다. NFC 한글은 한 글자가 한 스칼라다.
        if term.unicodeScalars.count >= trigramMinimum {
            query.ftsTerms.append(term)
        } else {
            query.likeTerms.append(term)
        }
    }

    private static func value(of token: String, prefix: String) -> String? {
        guard token.lowercased().hasPrefix(prefix) else { return nil }
        return String(token.dropFirst(prefix.count))
    }

    struct Token: Equatable {
        var text: String
        var quoted: Bool
    }

    /// 공백으로 나누되 `"…"` 안의 공백은 지킨다.
    static func tokenize(_ raw: String) -> [Token] {
        var tokens: [Token] = []
        var current = ""
        var inQuotes = false

        func flush(quoted: Bool) {
            let text = current.trimmingCharacters(in: .whitespaces)
            if !text.isEmpty { tokens.append(Token(text: text, quoted: quoted)) }
            current = ""
        }

        for ch in raw {
            if ch == "\"" {
                flush(quoted: inQuotes)
                inQuotes.toggle()
                continue
            }
            if !inQuotes, ch == " " || ch == "\t" || ch == "\n" {
                flush(quoted: false)
                continue
            }
            current.append(ch)
        }
        flush(quoted: inQuotes)
        return tokens
    }
}
