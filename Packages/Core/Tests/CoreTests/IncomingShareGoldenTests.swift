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
        struct Inbox: Decodable {
            let name: String
            let existing: [String: Int]
            let preferred: String
            let result: String
        }
        struct Address: Decodable {
            let name: String
            let text: String
            let url: String?
            let resultText: String
            let resultURL: String?
        }
        let shareCases: [Case]
        let inboxCases: [Inbox]
        struct Service: Decodable {
            let name: String
            let address: String
            let result: String?
        }
        let sharedAddressCases: [Address]
        let titleServiceCases: [Service]
        struct Entry: Decodable {
            let name: String
            let text: String
            let url: String?
            let pageTitle: String?
            let images: [String]
            let result: String?
        }
        struct Append: Decodable {
            let name: String
            let text: String
            let entry: String
            let result: String
        }
        let shareEntryCases: [Entry]
        let shareAppendCases: [Append]
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

    /// 219 · ADR-0009 — **받은 글 폴더 고르기.** 한국어 · 영어 이름이 둘 다 있을 때 갈라지지 않게 고른다.
    func testInboxFolderMatchesGolden() throws {
        let here = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let url = here.appendingPathComponent("Golden/expected.json")
        let cases = try JSONDecoder().decode(Golden.self, from: try Data(contentsOf: url)).inboxCases
        XCTAssertFalse(cases.isEmpty, "정답표가 비었다")
        for item in cases {
            XCTAssertEqual(IncomingShare.inboxFolder(existing: item.existing, preferred: item.preferred),
                           item.result, "[\(item.name)]")
        }
    }

    /// 240 — **글로 온 주소를 주소로.** 공유 확장이 같은 파일(`SharedAddress.swift`)을 빌드해 부른다.
    func testSharedAddressMatchesGolden() throws {
        let here = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let url = here.appendingPathComponent("Golden/expected.json")
        let cases = try JSONDecoder().decode(Golden.self, from: try Data(contentsOf: url)).sharedAddressCases
        XCTAssertFalse(cases.isEmpty, "정답표가 비었다")
        for item in cases {
            let got = SharedAddress.separate(text: item.text, url: item.url)
            XCTAssertEqual(got.text, item.resultText, "글 — [\(item.name)]")
            XCTAssertEqual(got.url, item.resultURL, "주소 — [\(item.name)]")
        }
    }

    /// 240 — **제목을 알려 주는 공식 창구.** 유튜브 주소만 oEmbed 로, 비슷한 이름 · 속인 주소는 링크 미리보기로.
    func testTitleServiceMatchesGolden() throws {
        let here = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let url = here.appendingPathComponent("Golden/expected.json")
        let cases = try JSONDecoder().decode(Golden.self, from: try Data(contentsOf: url)).titleServiceCases
        XCTAssertFalse(cases.isEmpty, "정답표가 비었다")
        for item in cases {
            XCTAssertEqual(SharedAddress.titleService(for: item.address), item.result, "[\(item.name)]")
        }
    }

    /// 241 — **이미 있는 노트에 덧붙이기.** 항목 한 줄 · 노트 끝에 잇기. 파이썬이 cmark 로 그려 목록이 하나 느는지 보고 왔다.
    func testShareAppendMatchesGolden() throws {
        let here = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let url = here.appendingPathComponent("Golden/expected.json")
        let golden = try JSONDecoder().decode(Golden.self, from: try Data(contentsOf: url))
        XCTAssertFalse(golden.shareEntryCases.isEmpty, "정답표가 비었다")
        XCTAssertFalse(golden.shareAppendCases.isEmpty, "정답표가 비었다")
        for item in golden.shareEntryCases {
            XCTAssertEqual(IncomingShare.entry(text: item.text, url: item.url, pageTitle: item.pageTitle, images: item.images),
                           item.result, "[\(item.name)]")
        }
        for item in golden.shareAppendCases {
            XCTAssertEqual(IncomingShare.appending(item.entry, to: item.text), item.result, "[\(item.name)]")
        }
    }
}
