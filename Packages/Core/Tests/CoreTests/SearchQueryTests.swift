import XCTest
@testable import Core

/// 검색어 문법은 우리가 정한 규칙(ADR-0003)이므로 기댓값이 곧 설계서다.
/// 계산 결과가 걸린 것은 `GoldenTests` 가 파이썬과 대조한다.
final class SearchQueryTests: XCTestCase {

    func testLongTermsGoToFTS() {
        let query = SearchQueryParser.parse("노후자금 준비하기")
        XCTAssertEqual(query.ftsTerms, ["노후자금", "준비하기"])
        XCTAssertTrue(query.likeTerms.isEmpty)
        XCTAssertFalse(query.needsFallback)
    }

    func testShortTermsGoToLikeFallback() {
        // **이것이 ADR-0003 의 핵심이다.** trigram 은 3글자 미만 질의에 아무것도
        // 반환하지 않으므로, 가장 흔한 2글자 검색어가 조용히 빈 결과를 낸다.
        let query = SearchQueryParser.parse("회의")
        XCTAssertTrue(query.ftsTerms.isEmpty)
        XCTAssertEqual(query.likeTerms, ["회의"])
        XCTAssertTrue(query.needsFallback)
    }

    func testTwoLettersIsTheBoundary() {
        XCTAssertEqual(SearchQueryParser.trigramMinimum, 3)
        XCTAssertEqual(SearchQueryParser.parse("준비").likeTerms, ["준비"], "2글자 — 폴백")
        XCTAssertEqual(SearchQueryParser.parse("준비물").ftsTerms, ["준비물"], "3글자 — FTS")
    }

    func testMixedLengthsSplitBetweenBothPaths() {
        let query = SearchQueryParser.parse("회의 노후자금")
        XCTAssertEqual(query.likeTerms, ["회의"])
        XCTAssertEqual(query.ftsTerms, ["노후자금"])
        XCTAssertTrue(query.needsFallback, "하나라도 짧으면 느린 경로를 타야 한다")
    }

    func testPhraseKeepsItsSpaces() {
        let query = SearchQueryParser.parse("\"노후 자금\" 준비하기")
        XCTAssertEqual(query.ftsTerms, ["노후 자금", "준비하기"])
        XCTAssertTrue(query.likeTerms.isEmpty)
    }

    func testShortPhraseAlsoFallsBack() {
        XCTAssertEqual(SearchQueryParser.parse("\"세금\"").likeTerms, ["세금"])
    }

    func testTagAndPathFilters() {
        let query = SearchQueryParser.parse("tag:앱 path:아이디어/ 구상")
        XCTAssertEqual(query.tags, ["앱"])
        XCTAssertEqual(query.pathPrefix, "아이디어/")
        XCTAssertEqual(query.likeTerms, ["구상"], "구상은 2글자라 폴백으로 간다")
        XCTAssertTrue(query.ftsTerms.isEmpty)
    }

    func testEmptyQuery() {
        XCTAssertTrue(SearchQueryParser.parse("   ").isEmpty)
        XCTAssertTrue(SearchQueryParser.parse("").isEmpty)
        XCTAssertFalse(SearchQueryParser.parse("tag:앱").isEmpty)
    }

    func testFTSExpressionQuotesEveryTerm() {
        let query = SearchQueryParser.parse("노후자금 준비하기")
        XCTAssertEqual(SearchQueryParser.ftsExpression(for: query), "\"노후자금\" AND \"준비하기\"")
    }

    func testFTSExpressionEscapesDoubleQuote() {
        XCTAssertEqual(SearchQueryParser.quoteForFTS("a\"b"), "\"a\"\"b\"")
    }

    func testFTSExpressionIsNilWhenNothingToMatch() {
        XCTAssertNil(SearchQueryParser.ftsExpression(for: SearchQueryParser.parse("회의")),
            "짧은 낱말뿐이면 FTS 로 갈 것이 없다 — LIKE 폴백만 돈다")
        XCTAssertNil(SearchQueryParser.ftsExpression(for: SearchQueryParser.parse("tag:앱")),
            "태그는 FTS 가 아니라 note.tags 칼럼으로 거른다")
    }

    func testLikePatternEscapesWildcards() {
        XCTAssertEqual(SearchQueryParser.likePattern(for: "50%"), "%50\\%%")
        XCTAssertEqual(SearchQueryParser.likePattern(for: "a_b"), "%a\\_b%")
        XCTAssertEqual(SearchQueryParser.likePattern(for: "회의"), "%회의%")
    }

    func testTagPatternsMatchWholeWords() {
        let query = SearchQueryParser.parse("tag:앱")
        XCTAssertEqual(SearchQueryParser.tagLikePatterns(for: query), ["% 앱 %"],
            "앞뒤 공백이 있어야 `앱` 이 `앱스토어` 에 안 걸린다")
    }

    func testNFCNormalizationOnInput() {
        // 사용자가 NFD 로 붙여 넣어도 색인(NFC)과 맞아야 한다.
        let query = SearchQueryParser.parse("\u{110B}\u{1162}\u{11B8}")   // NFD "앱"
        XCTAssertEqual(query.likeTerms, ["앱"])
    }

    func testTokenizerKeepsQuotedSpaces() {
        XCTAssertEqual(
            SearchQueryParser.tokenize("a \"b c\" d"),
            [.init(text: "a", quoted: false),
             .init(text: "b c", quoted: true),
             .init(text: "d", quoted: false)])
    }
}
