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

/// 파일의 수정 시각과 크기. 편집을 시작할 때 기억해 두고 저장 직전에 견준다 —
/// 둘 중 하나가 바뀌었으면 다른 기기가 고친 것일 수 있다 (설계서 §7.2 · A15).
struct FileStamp: Equatable, Sendable {
    let modifiedAt: Date
    let size: Int
}

/// iCloud 충돌 판본을 한 번 훑은 결과. `pending` 이 남았으면 아직 못 읽은 판본이 있다 —
/// **그 판본은 그대로 살아 있다.** 다음 기회에 다시 훑는다 (빌드 21 · 4번).
struct ConflictSweep: Sendable {
    let made: [String]
    let pending: Int
}

/// 쓰려는데 디스크의 글이 우리가 아는 것과 달랐다 — 다른 기기가 고쳤다. 덮지 않았다.
enum WriteConflict: Error, Sendable {
    /// 지금 디스크에 있는 글.
    case changedOnDisk(String)
}

/// 파일을 아직 읽을 수 없다 — iCloud 가 이름만 주고 내용은 아직 안 준 상태.
/// **잘린 글을 읽거나 쓰지 않으려고** 여기서 물러난다 (86).
enum ReadError: Error {
    case notDownloaded
}

