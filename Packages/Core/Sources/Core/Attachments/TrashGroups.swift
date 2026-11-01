import Foundation

/// **휴지통에서 폴더째 보이기** (292, 2026-11-01 사용자 — *휴지통에서 폴더가 삭제된 경우 폴더가 목록에 나와서 복구 가능하게 되어야 하는데,
/// 폴더 내 파일 목록만 나열되는 상황*).
///
/// 폴더 지우기(`FolderStore.trashFolder`)는 파일을 하나씩 `.trash/폴더/…` 로 옮긴다 — 폴더라는 표시는 따로 없다.
/// 그래서 **원래 폴더가 지금 없으면** 그것을 지운 폴더로 본다: 휴지통 안의 것마다 원래 자리의 폴더를 바깥부터 살펴,
/// 처음으로 없는 폴더에 묶는다. 다 있으면(그 폴더에서 노트 하나만 지운 경우) · 맨 위 노트면 낱개다.
///
/// 파일을 읽지 않는다 — 휴지통 경로들과 *지금 있는 폴더* 를 받는다. 있는지는 앱이 `candidates` 의 폴더마다 본다.
/// 기댓값은 `Tools/golden/generate.py` 의 `trashGroupCases`.
public enum TrashGroups {

    public struct Folder: Equatable, Sendable {
        /// 원래 폴더 (`.trash/` 없이) — 되돌리면 생길 자리.
        public let folder: String
        /// 안의 것 — 휴지통 경로(`.trash/…`), 노트 · 첨부 모두. 코드 포인트 순.
        public let paths: [String]

        public init(folder: String, paths: [String]) {
            self.folder = folder
            self.paths = paths
        }
    }

    public struct Grouping: Equatable, Sendable {
        public let folders: [Folder]
        /// 폴더로 안 묶인 것 — 지금처럼 낱개로 보인다.
        public let loose: [String]

        public init(folders: [Folder], loose: [String]) {
            self.folders = folders
            self.loose = loose
        }
    }

    /// 있는지 봐야 할 폴더 — 휴지통 것들의 원래 자리 폴더와 그 바깥 폴더 모두. 코드 포인트 순.
    public static func candidates(_ trashed: [String]) -> [String] {
        var found: Set<String> = []
        for path in trashed { found.formUnion(ancestors(of: path)) }
        return AttachmentLedger.ordered(found)
    }

    /// 묶는다. `existing` 은 `candidates` 가운데 지금 있는 폴더.
    public static func group(_ trashed: [String], existing: Set<String>) -> Grouping {
        let existing = Set(existing.map(Paths.normalized))
        var folders: [String: [String]] = [:]
        var loose: [String] = []
        for path in trashed {
            if let missing = ancestors(of: path).first(where: { !existing.contains($0) }) {
                folders[missing, default: []].append(path)
            } else {
                loose.append(path)
            }
        }
        let grouped = AttachmentLedger.ordered(folders.keys).map {
            Folder(folder: $0, paths: AttachmentLedger.ordered(folders[$0] ?? []))
        }
        return Grouping(folders: grouped, loose: AttachmentLedger.ordered(loose))
    }

    /// 원래 자리의 폴더들 — 바깥부터. `.trash/A/B/x.md` → `A` · `A/B`. 맨 위 것이면 빈 목록.
    static func ancestors(of trashed: String) -> [String] {
        let original = Paths.normalized(AttachmentLedger.originalPath(of: trashed))
        let parts = original.split(separator: "/").dropLast().map(String.init)
        var out: [String] = []
        var current = ""
        for part in parts {
            current = current.isEmpty ? part : current + "/" + part
            out.append(current)
        }
        return out
    }
}
