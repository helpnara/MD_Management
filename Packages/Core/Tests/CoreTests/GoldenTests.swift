import XCTest
@testable import Core

/// 파이썬이 **독립 계산**한 기댓값과 Core 의 결과를 견준다.
///
/// 왜 이렇게 하나 — 원격 세션에는 Swift 툴체인이 없다. 컴파일 못 하는 환경에서
/// 기댓값을 손으로 적으면 테스트가 버그를 승인한다. 그래서 마크다운 파싱은
/// `markdown-it-py`(다른 구현)로, 머리말은 진짜 YAML 파서로 계산한 값만 쓴다.
/// 기댓값을 고치려면 `python3 Tools/golden/generate.py` 를 돌린다.
final class GoldenTests: XCTestCase {

    // MARK: - 기댓값 읽기

    struct Golden: Decodable {
        struct Link: Decodable {
            let destination: String
            let kind: String
        }
        struct Resolved: Decodable {
            let linkKind: String
            let target: String
            let value: String
        }
        struct Matter: Decodable {
            let title: String?
            let tags: [String]
            let created: String?
        }
        struct Plan: Decodable {
            let mode: String
            let includes: [String]
            let missing: [String]
            let missingDecoded: [String]
        }
        struct Checkboxes: Decodable {
            let checked: Int
            let unchecked: Int
        }
        struct HTMLFacts: Decodable {
            let headings: [Int]
            let listItems: Int
            let checkboxes: Checkboxes
            let tables: Int
            let codeBlocks: Int
            let imageSrcs: [String]
            let missing: [String]
            let missingDecoded: [String]
        }
        struct Case: Decodable {
            let name: String
            let file: String
            let notePath: String
            let existing: [String]
            let followLinkedNotes: Bool
            let source: String
            let body: String
            let frontMatter: Matter?
            let title: String
            let links: [Link]
            let resolved: [Resolved]
            let sharePlan: Plan
            let html: HTMLFacts
        }
        let cases: [Case]
    }

    /// `Bundle.module` 대신 소스 위치에서 직접 읽는다 — 리눅스에서 더 단순하고 확실하다.
    static func loadGolden() throws -> Golden {
        let here = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let url = here.appendingPathComponent("Golden/expected.json")
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(Golden.self, from: data)
    }

    func testGoldenFileIsPresentAndNotEmpty() throws {
        let golden = try Self.loadGolden()
        XCTAssertGreaterThanOrEqual(golden.cases.count, 10,
            "기댓값 사례가 너무 적습니다. Tools/golden/generate.py 를 돌렸나요?")
    }

    // MARK: - 링크 추출

    /// **목적지 문자열을 그대로 견주지 않는다.** `markdown-it` 은 링크 목적지를
    /// 퍼센트 인코딩해서 주고 `swift-markdown` 은 원문 그대로 준다. 인코딩 차이는
    /// 진짜 차이가 아니므로 개수 · 종류 · **푼 결과**를 견준다.
    func testLinkExtractionMatchesPython() throws {
        for item in try Self.loadGolden().cases {
            let found = MarkdownLinks.extract(from: item.source)

            XCTAssertEqual(found.count, item.links.count,
                "[\(item.name)] 뽑은 링크 개수가 다릅니다: \(found.map(\.destination))")
            guard found.count == item.links.count else { continue }

            for (index, expected) in item.links.enumerated() {
                XCTAssertEqual(found[index].kind.rawValue, expected.kind,
                    "[\(item.name)] \(index)번째 링크의 종류가 다릅니다")
            }
        }
    }

    // MARK: - 경로 해석 (§7.3 — 퍼센트 디코딩 · NFC · ../ 차단)

    func testLinkResolutionMatchesPython() throws {
        for item in try Self.loadGolden().cases {
            let found = MarkdownLinks.extract(from: item.source)
            guard found.count == item.resolved.count else {
                XCTFail("[\(item.name)] 링크 개수가 달라 해석을 견줄 수 없습니다")
                continue
            }

            for (index, expected) in item.resolved.enumerated() {
                let target = Paths.resolve(link: found[index].destination, fromNoteAt: item.notePath)
                let (kind, value) = describe(target)
                XCTAssertEqual(kind, expected.target,
                    "[\(item.name)] \(index)번째 링크가 가리키는 곳이 다릅니다 (\(found[index].destination))")
                if expected.target == "relative" || expected.target == "outside" || expected.target == "absolute" {
                    XCTAssertEqual(value, expected.value,
                        "[\(item.name)] \(index)번째 링크의 경로가 다릅니다")
                }
            }
        }
    }

    private func describe(_ target: LinkTarget) -> (String, String) {
        switch target {
        case .empty: return ("empty", "")
        case .external(let value): return ("external", value)
        case .absolute(let value): return ("absolute", value)
        case .outside(let value): return ("outside", value)
        case .relative(let value): return ("relative", value)
        }
    }

    // MARK: - 머리말

    func testFrontMatterMatchesPyYAML() throws {
        for item in try Self.loadGolden().cases {
            let parsed = FrontMatterParser.parse(item.source)

            if let expected = item.frontMatter {
                guard let matter = parsed.frontMatter else {
                    XCTFail("[\(item.name)] 머리말을 못 읽었습니다")
                    continue
                }
                XCTAssertEqual(matter.title, expected.title, "[\(item.name)] title")
                XCTAssertEqual(matter.tags, expected.tags, "[\(item.name)] tags")
                XCTAssertEqual(matter.created, expected.created, "[\(item.name)] created")
            } else {
                XCTAssertNil(parsed.frontMatter,
                    "[\(item.name)] 머리말이 없어야 하는데 읽었습니다")
            }

            // 본문은 **줄바꿈까지 그대로** 남아야 한다 (CRLF 보존).
            XCTAssertEqual(parsed.body, item.body, "[\(item.name)] 본문이 다릅니다")
        }
    }

    /// `headerLength` 로 자른 앞부분 뒤에 파이썬이 뗀 본문이 그대로 이어져야 한다.
    func testHeaderLengthMatchesPythonBody() throws {
        for item in try Self.loadGolden().cases {
            let length = FrontMatterParser.headerLength(of: item.source)
            if item.frontMatter == nil {
                XCTAssertEqual(length, 0, "[\(item.name)] 머리말이 없는데 길이가 있다")
                continue
            }
            XCTAssertGreaterThan(length, 0, "[\(item.name)] 머리말이 있는데 길이가 0 이다")
            let rest = String(decoding: Array(item.source.utf16.dropFirst(length)), as: UTF16.self)
            XCTAssertTrue(rest.isEmpty || rest == "\n" + item.body,
                          "[\(item.name)] 머리말 뒤에 본문이 이어지지 않는다")
        }
    }

    func testTitleMatchesPython() throws {
        for item in try Self.loadGolden().cases {
            XCTAssertEqual(
                FrontMatterParser.title(of: item.source, fileName: item.file),
                item.title,
                "[\(item.name)] 목록에 보여 줄 제목이 다릅니다")
        }
    }

    // MARK: - 공유 묶음 (§7.6)

    func testSharePlanMatchesPython() throws {
        for item in try Self.loadGolden().cases {
            let existing = Set(item.existing)
            let plan = ShareBundle.plan(
                notePath: item.notePath,
                noteText: item.source,
                followLinkedNotes: item.followLinkedNotes,
                exists: { existing.contains($0) }
            )

            XCTAssertEqual(plan.mode.rawValue, item.sharePlan.mode, "[\(item.name)] 공유 방식")
            XCTAssertEqual(plan.includes, item.sharePlan.includes, "[\(item.name)] 넣을 파일")

            // 인코딩 차이를 걷어내고 견준다 (위 testLinkExtraction 의 주석과 같은 이유).
            let decoded = plan.missing.map { Paths.normalized($0.removingPercentEncoding ?? $0) }
            XCTAssertEqual(decoded, item.sharePlan.missingDecoded, "[\(item.name)] 빠진 파일")
        }
    }
}
