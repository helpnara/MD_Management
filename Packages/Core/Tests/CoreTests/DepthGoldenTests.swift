import XCTest
@testable import Core

/// **편집기가 목록을 몇 단계로 그려야 하나** (141).
///
/// 편집기는 오래도록 **앞 빈칸 ÷ 2** 로 단계를 그렸고, 마크다운은 **부모의 글칸**으로
/// 센다. 잣대가 둘이라 사용자는 *편집 모드는 맞는데 읽기 모드가 다르다* 를 두 번 겪었다
/// (빌드 41 · 42). 이제 그리는 쪽이 읽는 쪽과 같은 셈을 쓴다.
///
/// 기댓값은 `Tools/golden/generate.py` 가 세고, **그 셈을 markdown-it 에게 다시 물어**
/// 연 항목의 깊이와 맞춰 본 것이다. 손으로 적은 숫자는 한 개도 없다.
final class DepthGoldenTests: XCTestCase {

    struct Golden: Decodable {
        struct Case: Decodable {
            let name: String
            let lines: [String]
            let depths: [Int]
        }
        let depthCases: [Case]
    }

    static func load() throws -> Golden {
        let here = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let url = here.appendingPathComponent("Golden/expected.json")
        return try JSONDecoder().decode(Golden.self, from: try Data(contentsOf: url))
    }

    func testMatchesGolden() throws {
        for item in try Self.load().depthCases {
            XCTAssertEqual(ListEditing.depths(in: item.lines), item.depths,
                           "단계가 어긋난다 — [\(item.name)] \(item.lines)")
        }
    }

    /// **줄 수만큼 나온다.** 하나라도 빠지면 화면이 엉뚱한 줄에 들여쓰기를 건다.
    func testOneAnswerPerLine() throws {
        for item in try Self.load().depthCases {
            XCTAssertEqual(ListEditing.depths(in: item.lines).count, item.lines.count,
                           "줄 수와 다르다 — [\(item.name)]")
        }
    }

    /// **목록이 아닌 줄은 0.**
    func testPlainLinesHaveNoDepth() {
        XCTAssertEqual(ListEditing.depths(in: ["그냥 글", "또 글"]), [0, 0])
    }

    /// **한 번에 한 단계씩만 깊어진다.** 두 단계를 건너뛰면 마크다운은 그 줄을 코드로
    /// 읽거나 앞 문단에 붙인다 — 화면만 깊어 보이고 파일은 무너진 자리다 (141).
    func testDepthGrowsOneStepAtATime() throws {
        for item in try Self.load().depthCases {
            var previous = 0
            for (line, depth) in zip(item.lines, ListEditing.depths(in: item.lines)) {
                if line.trimmingCharacters(in: .whitespaces).isEmpty { continue }
                XCTAssertLessThanOrEqual(depth, previous + 1,
                                         "한 번에 두 단계를 뛰었다 — [\(item.name)] \(line)")
                previous = depth
            }
        }
    }
}
