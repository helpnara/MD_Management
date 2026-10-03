import XCTest
@testable import Core

/// 213 — **공유로 받은 것을 노트 글로.** 기댓값은 `Tools/golden/generate.py` 의 `shareCases` — 같은 셈을 파이썬으로
/// 적고, 그 글을 cmark-gfm 으로 그려 주소는 링크 하나 · 사진은 그림 · 글자는 빠짐없이 · 제목은 첫 줄과 같은지 보고 왔다.
final class IncomingShareGoldenTests: XCTestCase {

    struct Golden: Decodable {
        struct Case: Decodable {
            let name: String
            let text: String
            let url: String?
            let pageTitle: String?
            let images: [String]
            let fallback: String
            let title: String
            let markdown: String
        }
        let shareCases: [Case]
    }

    func testMatchesGolden() throws {
        let here = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let url = here.appendingPathComponent("Golden/expected.json")
        let cases = try JSONDecoder().decode(Golden.self, from: try Data(contentsOf: url)).shareCases
        XCTAssertFalse(cases.isEmpty, "정답표가 비었다")
        for item in cases {
            let got = IncomingShare.note(text: item.text, url: item.url, pageTitle: item.pageTitle,
                                         images: item.images, fallback: item.fallback)
            XCTAssertEqual(got.title, item.title, "제목 — [\(item.name)]")
            XCTAssertEqual(got.markdown, item.markdown, "글 — [\(item.name)]")
            // 파일 이름과 첫 줄이 갈리지 않는다 — 목록의 제목과 같은 셈.
            XCTAssertEqual(FrontMatterParser.title(of: got.markdown, fileName: "아무개.md"), got.title, "[\(item.name)]")
        }
    }
}
