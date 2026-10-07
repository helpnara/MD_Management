import Foundation

/// **폴더 안의 폴더** (203) — 폴더 화면에 무엇을 어떤 차례로 보이나.
///
/// 폴더 화면은 **두 단계까지** 펼친다 — 최상위 폴더와 그 바로 아래 (2026-10-02 사용자 — *기본적으로 보여 주는 화면은 이
/// 단계까지를 원칙으로*). 그보다 깊은 폴더는 두 번째 단계 폴더를 **열면** 노트 목록 위에 나오고, 눌러서 계속 내려간다. 두 번째
/// 단계 줄에는 *안에 폴더가 있다*는 표시만 붙인다(`Entry.subfolders`). **이 앱에서 만드는 폴더는 두 단계에서 멈춘다**
/// (`creatableDepth`) — 더 깊은 폴더는 다른 앱이 만든 것이다.
///
/// 차례는 **받은 그대로** 둔다 — 이름 차례는 앱이 정해서 넘긴다(`localizedStandardCompare`, 리눅스 심판과 셈이 다를 수 있는
/// 자리라 여기서 하지 않는다). 여기서는 *누가 누구의 아래인가* 만 정한다.
///
/// **파이썬 `folder_sidebar` · `folder_children` 과 같은 셈이다** (`Tools/golden`, `folderTreeCases`).
public enum FolderTree {

    /// 이 앱에서 폴더를 만들 수 있는 가장 깊은 단계. 최상위 폴더가 1.
    public static let creatableDepth = 2
    /// 폴더 화면에 펼쳐 보이는 가장 깊은 단계.
    public static let sidebarDepth = 2

    public struct Entry: Equatable, Sendable {
        public let path: String
        public let depth: Int
        /// 바로 아래 폴더 수. 두 번째 단계 줄은 이것으로 *안에 폴더가 있다* 를 보여 준다.
        public let subfolders: Int

        public init(path: String, depth: Int, subfolders: Int) {
            self.path = path
            self.depth = depth
            self.subfolders = subfolders
        }
    }

    /// 폴더 기준 상대경로의 깊이 — `회의` 는 1, `회의/2026` 은 2. 최상위(빈 문자열)는 0.
    public static func depth(of path: String) -> Int {
        path.isEmpty ? 0 : path.split(separator: "/", omittingEmptySubsequences: true).count
    }

    /// 경로의 바로 위 폴더. 최상위 폴더의 위는 빈 문자열.
    public static func parent(of path: String) -> String {
        guard let slash = path.lastIndex(of: "/") else { return "" }
        return String(path[path.startIndex..<slash])
    }

    /// `paths` 가운데 `folder` 의 **바로 아래** 폴더들 — 받은 차례 그대로. `folder` 가 빈 문자열이면 최상위 폴더들.
    public static func children(of folder: String, in paths: [String]) -> [String] {
        paths.filter { parent(of: $0) == folder && !$0.isEmpty }
    }

    /// 폴더 화면의 줄 — 최상위 폴더마다 **그 다음에 바로 아래 폴더들**. 두 단계까지.
    /// 부모가 목록에 없는 폴더(그 사이 지워졌다)는 보이지 않는다.
    public static func sidebar(_ paths: [String]) -> [Entry] {
        var out: [Entry] = []
        for top in children(of: "", in: paths) {
            let below = children(of: top, in: paths)
            out.append(Entry(path: top, depth: 1, subfolders: below.count))
            for child in below {
                out.append(Entry(path: child, depth: 2, subfolders: children(of: child, in: paths).count))
            }
        }
        return out
    }

    /// 같은 부모 안에서 이름만 바꾼 경로 — `회의/2026` 을 `2027` 로 → `회의/2027`.
    /// 예전 `renameFolder` 는 새 이름을 **최상위**에 만들어, 하위 폴더 이름을 바꾸면 최상위로 빠져나갔을 것이다.
    public static func renamed(_ path: String, to name: String) -> String {
        let up = parent(of: path)
        return up.isEmpty ? name : up + "/" + name
    }

    /// 폴더를 `parent` 안으로 옮긴 경로 — 이름은 그대로 (204). `parent` 가 빈 문자열이면 맨 위로.
    public static func moved(_ path: String, into parent: String) -> String {
        let name = path.split(separator: "/").last.map(String.init) ?? path
        return parent.isEmpty ? name : parent + "/" + name
    }

    /// 폴더를 **옮겨 넣을 수 있는 자리** (204) — 맨 위(빈 문자열, 이미 맨 위면 빼고)와 최상위 폴더들.
    /// 자기 자신 · 지금 있는 자리는 뺀다. 최상위 폴더 안으로만 넣으므로 옮긴 폴더는 **두 단계**에 선다
    /// (`creatableDepth` 와 같은 선). 그 안의 폴더는 함께 한 단계씩 내려가 열어서 들어가는 자리가 된다.
    public static func moveTargets(for path: String, in paths: [String]) -> [String] {
        let here = parent(of: path)
        var out: [String] = here.isEmpty ? [] : [""]
        for top in children(of: "", in: paths) where top != path && top != here {
            out.append(top)
        }
        return out
    }

    /// 폴더가 `old` 에서 `new` 로 옮겨 갔을 때 `path` 의 새 자리 — 그 폴더거나 그 안이면. 아니면 `nil`.
    /// 보고 있던 폴더가 이름이 바뀐 폴더의 **안**이어도 따라간다.
    public static func rebased(_ path: String, from old: String, to new: String) -> String? {
        guard !old.isEmpty else { return nil }
        if path == old { return new }
        guard path.hasPrefix(old + "/") else { return nil }
        return new + String(path.dropFirst(old.count))
    }

    /// **새 폴더를 만들 자리** (218, 2026-10-07 사용자 — *다른 폴더를 클릭한 상태에서 새폴더를 만들면 하위 폴더를*).
    /// 지금 고른 폴더 안 — 다만 이 앱이 만드는 폴더는 `creatableDepth` 에서 멈추므로, 고른 폴더가 이미 그 단계(또는 다른 앱이
    /// 만든 더 깊은 폴더)면 **그 폴더의 조상 가운데 안에 만들 수 있는 가장 깊은 폴더** 안이다. 두 단계면 최상위 조상 — 고른 폴더와 같은 줄.
    /// 최상위(빈 문자열)면 최상위.
    public static func creationParent(for selected: String) -> String {
        let parts = selected.split(separator: "/", omittingEmptySubsequences: true)
        return parts.prefix(min(parts.count, creatableDepth - 1)).joined(separator: "/")
    }

    /// `path` 가 `folder` 이거나 그 안인가.
    public static func isInside(_ path: String, _ folder: String) -> Bool {
        !folder.isEmpty && (path == folder || path.hasPrefix(folder + "/"))
    }
}
