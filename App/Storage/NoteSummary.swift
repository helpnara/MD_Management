import Foundation

/// 목록 한 줄. **`Sendable` 값만 화면으로 건넨다** — `FolderStore` 는 actor 다 (설계서 §8).
struct NoteSummary: Identifiable, Hashable, Sendable {
    /// 폴더 기준 상대경로. 이것이 신원이다 (NFC 로 정규화된 것).
    let relativePath: String
    let title: String
    /// 목록에 보여 줄 첫 줄. **색인이 없으면 비어 있다** (설계서 §7.5) —
    /// 목록을 그리려고 파일 300개를 열지 않는다.
    let preview: String
    let modifiedAt: Date
    let size: Int
    /// iCloud 에 있지만 아직 안 내려온 파일. 목록에 구름 아이콘으로 보인다.
    let isDownloaded: Bool

    var id: String { relativePath }

    var fileName: String {
        relativePath.split(separator: "/").last.map(String.init) ?? relativePath
    }
}

/// 사이드바의 폴더 한 줄.
struct FolderSummary: Identifiable, Hashable, Sendable {
    /// 폴더 기준 상대경로. 최상위는 빈 문자열.
    let relativePath: String
    let name: String
    let noteCount: Int

    var id: String { relativePath }
}

/// 어떤 폴더를 쓰고 있나. 진단 화면과 시작 화면이 이것을 보여 준다.
enum FolderKind: String, Sendable {
    /// (a) 앱 iCloud Drive 컨테이너 — 기본 (ADR-0002)
    case iCloudContainer
    /// (b) 사용자가 고른 임의 폴더 (보안 범위 북마크)
    case userChosen
    /// iCloud 를 못 쓸 때의 기기 안 폴더 (시뮬레이터 · CI · iCloud 로그아웃)
    case localDocuments
    /// 둘러보기 — 임시 디렉터리. **실제 폴더에 샘플을 뿌리지 않는다**
    case sample

    var label: String {
        switch self {
        case .iCloudContainer: return "iCloud"
        case .userChosen: return "고른 폴더"
        case .localDocuments: return "이 기기"
        case .sample: return "임시 폴더"
        }
    }
}
