import XCTest
@testable import Core

/// **노트 통계** (315). 기댓값은 `Tools/golden/generate.py` 의 `noteStatsCases` — 파이썬 쌍둥이(`note_stats.py`)가 셈했다.
/// 뜻을 적은 사례 + 같은 씨앗으로 뒤섞은 노트 120개. 손으로 적은 기댓값은 없다.
final class NoteStatsGoldenTests: XCTestCase {

    struct Golden: Decodable {
        struct Stats: Decodable {
            let characters, charactersNoSpaces, words, lines, paragraphs: Int
            let tasks, tasksDone, links, images, readingMinutes: Int
        }
        struct Case: Decodable {
            let name: String
            let text: String
            let stats: Stats
        }
        let noteStatsCases: [Case]
    }

    func testMatchesGolden() throws {
        let here = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let url = here.appendingPathComponent("Golden/expected.json")
        let cases = try JSONDecoder().decode(Golden.self, from: try Data(contentsOf: url)).noteStatsCases
        XCTAssertGreaterThan(cases.count, 120, "정답표가 모자라다")
        for item in cases {
            let got = NoteStats.of(item.text)
            let want = item.stats
            let label = "[\(item.name)] \(item.text.debugDescription)"
            XCTAssertEqual(got.characters, want.characters, "글자 " + label)
            XCTAssertEqual(got.charactersNoSpaces, want.charactersNoSpaces, "공백 뺀 글자 " + label)
            XCTAssertEqual(got.words, want.words, "낱말 " + label)
            XCTAssertEqual(got.lines, want.lines, "줄 " + label)
            XCTAssertEqual(got.paragraphs, want.paragraphs, "문단 " + label)
            XCTAssertEqual(got.tasks, want.tasks, "할 일 " + label)
            XCTAssertEqual(got.tasksDone, want.tasksDone, "끝낸 일 " + label)
            XCTAssertEqual(got.links, want.links, "링크 " + label)
            XCTAssertEqual(got.images, want.images, "사진 " + label)
            XCTAssertEqual(got.readingMinutes, want.readingMinutes, "읽는 시간 " + label)
        }
    }
}
