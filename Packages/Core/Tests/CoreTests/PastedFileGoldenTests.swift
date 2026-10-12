import XCTest
@testable import Core

/// **붙여넣은 첨부가 무엇인가** (243). 기댓값은 `Tools/golden/generate.py` 의 `pastedFileCases` — 같은 판별을 파이썬으로 적었다.
final class PastedFileGoldenTests: XCTestCase {

    struct Golden: Decodable {
        struct Kind: Decodable {
            let name: String
            let head: String
            let fileName: String?
            let result: String
        }
        struct Label: Decodable {
            let name: String
            let fileName: String?
            let ext: String
            let result: String
        }
        struct Cases: Decodable {
            let kinds: [Kind]
            let labels: [Label]
        }
        let pastedFileCases: Cases
    }

    private func load() throws -> Golden.Cases {
        let here = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let url = here.appendingPathComponent("Golden/expected.json")
        return try JSONDecoder().decode(Golden.self, from: try Data(contentsOf: url)).pastedFileCases
    }

    private func bytes(_ hex: String) -> [UInt8] {
        var out: [UInt8] = []
        var index = hex.startIndex
        while index < hex.endIndex {
            let next = hex.index(index, offsetBy: 2)
            out.append(UInt8(hex[index..<next], radix: 16)!)
            index = next
        }
        return out
    }

    private func text(_ kind: PastedFile.Kind) -> String {
        switch kind {
        case .image(let ext): return "image:" + ext
        case .file(let ext): return "file:" + ext
        case .unknown: return "unknown"
        }
    }

    func testKindsMatchGolden() throws {
        let cases = try load().kinds
        XCTAssertFalse(cases.isEmpty, "정답표가 비었다")
        for item in cases {
            XCTAssertEqual(text(PastedFile.kind(head: bytes(item.head), fileName: item.fileName)), item.result, "[\(item.name)]")
        }
    }

    func testLabelsMatchGolden() throws {
        let cases = try load().labels
        XCTAssertFalse(cases.isEmpty, "정답표가 비었다")
        for item in cases {
            XCTAssertEqual(PastedFile.label(fileName: item.fileName, ext: item.ext, fallback: "첨부"), item.result, "[\(item.name)]")
        }
    }
}
