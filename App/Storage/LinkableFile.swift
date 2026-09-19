import Foundation
import Core

/// **금고 안의 파일 하나** — 이어 붙일 후보 (145).
///
/// 화면에는 `Sendable` 값만 건넨다 (`NoteSummary` 와 같은 꼴).
struct LinkableFile: Identifiable, Hashable, Sendable {
    /// 금고 기준 상대경로. 이것이 신원이다 (NFC 로 정규화된 것).
    let relativePath: String
    /// 파일 이름 — 목록에 굵게 보여 준다.
    let name: String
    var id: String { relativePath }

    /// 들어 있는 폴더. 목록에서 이름 아래 작게 보여 준다 — 같은 이름이 여럿일 수 있다.
    var folder: String { Paths.directory(of: relativePath) }
}
