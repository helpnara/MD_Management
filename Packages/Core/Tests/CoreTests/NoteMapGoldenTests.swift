import XCTest
@testable import Core

/// **노트 지도** (329 · 330). 기댓값은 `Tools/golden/generate.py` 의 `noteMapCases` — 파이썬 쌍둥이(`note_map.py`)가 셈했다.
/// 손으로 적은 기댓값은 없다.
final class NoteMapGoldenTests: XCTestCase {

    struct Golden: Decodable {
        struct TermCase: Decodable {
            let name: String
            let text: String
            let terms: [[String]]
        }
        struct Note: Decodable {
            let path: String
            let day: Int
            let text: String
        }
        struct Entry: Decodable {
            let keyword: String
            let count: Int
            let previous: Int
            let mark: String
        }
        struct Overview: Decodable {
            let days: Int
            let by: String
            let notes: Int
            let previousNotes: Int
            let entries: [Entry]
        }
        struct Neighbor: Decodable {
            let keyword: String
            let count: Int
            let level: Int
        }
        struct Neighbors: Decodable {
            let center: String
            let days: Int
            let neighbors: [Neighbor]
        }
        struct Paths: Decodable {
            let keyword: String
            let also: String?
            let days: Int
            let paths: [String]
        }
        struct Folder: Decodable {
            let name: String
            let today: Int
            let hidden: [String]
            let notes: [Note]
            let keywords: [String]
            let overviews: [Overview]
            let neighbors: [Neighbors]
            let paths: [Paths]
        }
        struct Created: Decodable {
            let text: String
            let day: Int?
        }
        struct Layout: Decodable {
            let count: Int
            let points: [[Double]]
        }
        struct Cases: Decodable {
            let terms: [TermCase]
            let folders: [Folder]
            let created: [Created]
            let layout: [Layout]
        }
        let noteMapCases: Cases
    }

    static func golden() throws -> Golden.Cases {
        let here = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let url = here.appendingPathComponent("Golden/expected.json")
        return try JSONDecoder().decode(Golden.self, from: try Data(contentsOf: url)).noteMapCases
    }

    func testTerms() throws {
        let cases = try Self.golden().terms
        XCTAssertGreaterThan(cases.count, 15, "정답표가 모자라다")
        for item in cases {
            let got = NoteMap.terms(of: item.text).map { [$0.stem, $0.form] }
            XCTAssertEqual(got, item.terms, "[\(item.name)] \(item.text.debugDescription)")
            // 색인 칸에 담았다 꺼내도 같다.
            let back = NoteMap.decode(NoteMap.encode(NoteMap.terms(of: item.text))).map { [$0.stem, $0.form] }
            XCTAssertEqual(back, item.terms, "[\(item.name)] 담기 · 꺼내기")
        }
    }

    func testFolders() throws {
        let folders = try Self.golden().folders
        XCTAssertGreaterThanOrEqual(folders.count, 5, "정답표가 모자라다")
        for folder in folders {
            let rows = folder.notes.map { NoteMap.Row(path: $0.path, day: $0.day, terms: NoteMap.terms(of: $0.text)) }
            let model = NoteMap.Model(rows: rows, hidden: Set(folder.hidden))
            let label = "[\(folder.name)]"
            XCTAssertEqual(model.keywords, folder.keywords, "키워드 " + label)
            for want in folder.overviews {
                let got = model.overview(today: folder.today, days: want.days, by: NoteMap.Order(rawValue: want.by)!)
                XCTAssertEqual(got.notes, want.notes, "기간 노트 \(want.days) " + label)
                XCTAssertEqual(got.previousNotes, want.previousNotes, "앞 기간 노트 \(want.days) " + label)
                XCTAssertEqual(got.entries.map(\.keyword), want.entries.map(\.keyword), "차례 \(want.days) \(want.by) " + label)
                XCTAssertEqual(got.entries.map(\.count), want.entries.map(\.count), "노트 수 \(want.days) " + label)
                XCTAssertEqual(got.entries.map(\.previous), want.entries.map(\.previous), "앞 기간 수 \(want.days) " + label)
                XCTAssertEqual(got.entries.map(\.mark.rawValue), want.entries.map(\.mark), "표시 \(want.days) " + label)
            }
            for want in folder.neighbors {
                let got = model.neighbors(of: want.center, today: folder.today, days: want.days)
                XCTAssertEqual(got.map(\.keyword), want.neighbors.map(\.keyword), "이웃 \(want.center) " + label)
                XCTAssertEqual(got.map(\.count), want.neighbors.map(\.count), "이웃 수 \(want.center) " + label)
                XCTAssertEqual(got.map(\.level), want.neighbors.map(\.level), "선 굵기 \(want.center) " + label)
            }
            for want in folder.paths {
                let got = model.notePaths(keyword: want.keyword, also: want.also, today: folder.today, days: want.days)
                XCTAssertEqual(got, want.paths, "노트 \(want.keyword) · \(want.also ?? "-") " + label)
            }
        }
    }

    func testCreatedDay() throws {
        let cases = try Self.golden().created
        XCTAssertGreaterThan(cases.count, 8)
        for item in cases {
            XCTAssertEqual(NoteMap.createdDay(item.text), item.day, item.text.debugDescription)
        }
        XCTAssertNil(NoteMap.createdDay(nil))
    }

    func testLayout() throws {
        for item in try Self.golden().layout {
            let got = NoteMap.layout(count: item.count)
            XCTAssertEqual(got.count, item.points.count, "둘레 \(item.count)")
            for (p, want) in zip(got, item.points) {
                XCTAssertEqual(p.x, want[0], accuracy: 1e-6, "둘레 \(item.count)")
                XCTAssertEqual(p.y, want[1], accuracy: 1e-6, "둘레 \(item.count)")
            }
        }
    }

    /// 노트 1만 개 — 지도를 열 때의 셈(모델 · 4주 · 이웃)이 몇 초 안에 끝나는가. 시간은 기록만 하고 넉넉한 한도로 본다 (CI 디버그 빌드).
    func testTenThousandNotes() {
        let words = (0..<400).map { "낱말\($0)" }
        let forms = ["", "을", "이", "의", "에서"]
        var rows: [NoteMap.Row] = []
        var seed: UInt64 = 42
        func next() -> Int {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return Int(seed >> 33)
        }
        for i in 0..<10_000 {
            var terms: [NoteMap.Term] = []
            for _ in 0..<60 { terms.append(NoteMap.Term(stem: words[next() % words.count], form: forms[next() % forms.count])) }
            rows.append(NoteMap.Row(path: "n\(i).md", day: 20_000 - next() % 400, terms: Array(Set(terms))))
        }
        let started = Date()
        let model = NoteMap.Model(rows: rows)
        let overview = model.overview(today: 20_000, days: 28)
        let first = overview.entries.first?.keyword ?? ""
        _ = model.neighbors(of: first, today: 20_000, days: 28)
        _ = model.notePaths(keyword: first, today: 20_000, days: 28)
        let seconds = Date().timeIntervalSince(started)
        print("노트 지도 1만 개: \(String(format: "%.2f", seconds))초 · 키워드 \(model.keywords.count)")
        XCTAssertFalse(overview.entries.isEmpty)
        XCTAssertLessThan(seconds, 20)
    }
}
