import Foundation

/// 공유할 때 파일 하나로 무엇을 보낼지.
public enum ShareMode: String, Equatable, Sendable {
    /// 참조하는 첨부가 없다 — `.md` 파일 그대로 보낸다. 가장 흔하고 가장 가벼워야 한다.
    case mdOnly
    /// 첨부가 하나라도 있다 — 상대경로 구조 그대로 zip 하나로 묶는다.
    case zip
}

/// 무엇을 묶어 보낼지 계산한 결과.
public struct SharePlan: Equatable, Sendable {
    public var mode: ShareMode
    /// 폴더 기준 상대경로. **첫 번째가 노트 자신**이다.
    public var includes: [String]
    /// 참조했는데 폴더 안에 없는 것. **원문에 적힌 링크 문자열 그대로** 담는다 —
    /// 사용자에게 "어느 줄의 무엇이 없는지" 를 보여 줘야 하기 때문이다.
    public var missing: [String]

    public init(mode: ShareMode, includes: [String], missing: [String]) {
        self.mode = mode
        self.includes = includes
        self.missing = missing
    }
}

/// 공유 묶음 계산 — 순수 함수라 리눅스 `swift test` 로 검증한다 (설계서 §7.6).
public enum ShareBundle {

    /// 노트 하나를 공유할 때 무엇을 넣을지 정한다.
    ///
    /// 규칙 (설계서 §7.6):
    /// - 외부 URL · 절대경로는 넣지 않는다.
    /// - **`../` 로 폴더 밖을 가리키면 `missing` 으로 본다.** zip 안에 상위 경로가
    ///   들어가면 받는 쪽에서 풀 때 다른 폴더를 덮는다.
    /// - 상대 `.md` 링크는 **한 단계만** 따라간다. B 를 넣되 B 가 링크하는 C 는 안 넣는다.
    /// - 참조했는데 없는 파일은 조용히 빠뜨리지 않고 `missing` 에 담아 알린다.
    ///
    /// - Parameters:
    ///   - notePath: 폴더 기준 상대경로 (예: `아이디어/앱 구상.md`)
    ///   - noteText: 노트 본문 전체 (머리말 포함)
    ///   - followLinkedNotes: 설정의 "링크된 노트 포함" — 끄면 `.md` 링크를 안 따라간다
    ///   - exists: 폴더 기준 상대경로가 실제로 있는지 묻는다
    public static func plan(
        notePath: String,
        noteText: String,
        followLinkedNotes: Bool = true,
        exists: (String) -> Bool
    ) -> SharePlan {
        let note = Paths.normalized(notePath)
        var includes: [String] = [note]
        var seen: Set<String> = [note]
        var missing: [String] = []
        var missingSeen: Set<String> = []

        func recordMissing(_ raw: String) {
            guard !missingSeen.contains(raw) else { return }
            missingSeen.insert(raw)
            missing.append(raw)
        }

        for link in MarkdownLinks.extract(from: noteText) {
            switch Paths.resolve(link: link.destination, fromNoteAt: note) {
            case .empty, .external, .absolute:
                continue

            case .outside:
                // 폴더 밖을 가리킨다. 넣지 않고 사용자에게 보여 준다.
                recordMissing(link.destination)

            case .relative(let path):
                if seen.contains(path) { continue }
                if Paths.isMarkdownFile(path) && !followLinkedNotes { continue }
                if exists(path) {
                    seen.insert(path)
                    includes.append(path)
                } else {
                    recordMissing(link.destination)
                }
            }
        }

        return SharePlan(
            mode: includes.count > 1 ? .zip : .mdOnly,
            includes: includes,
            missing: missing
        )
    }

    /// zip 파일 이름. 임시 폴더 이름도 이것으로 만든다 —
    /// `NSFileCoordinator … .forUploading` 이 **넘긴 폴더 이름을 zip 최상위에 넣기**
    /// 때문이다 (설계서 §7.6 구현 결정).
    public static func archiveName(forTitle title: String) -> String {
        Paths.safeFileName(title)
    }
}
