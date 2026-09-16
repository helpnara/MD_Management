import Foundation

/// **고정된 노트** (T10, 사용자 요청 — 메모 앱처럼 목록 맨 위에).
///
/// ## 어디에 적어 두나
///
/// 사용자 폴더 안의 **숨김 파일** 하나다 (`.여백/고정.json`). 세 자리 중에 골랐다:
///
/// - **노트 머리말** — 앱이 본문을 고치게 된다. 107 에서 지운 바로 그 길이라 **안 쓴다.**
/// - **기기 안(`UserDefaults`)** — 아이폰에서 고정한 것이 아이패드에 없다. 고정은
///   "늘 위에 두고 싶다" 는 뜻이고 그 마음이 기기마다 다를 리 없다.
/// - **폴더 안 숨김 파일** — iCloud 로 따라가고 **본문은 한 글자도 안 건드린다.** 이것이다.
///
/// 숨김 폴더는 목록에서 이미 빠진다 (`Paths.isHidden`). 옵시디언의 `.obsidian/` 과 같은 자리다.
///
/// ## 부딪히면 합친다
///
/// 두 기기가 각각 고정하면 파일이 충돌한다. **노트 본문과 달리 이것은 합칠 수 있다** —
/// 고정 목록은 집합이므로 **둘을 합치면 된다.** 판본을 꺼내는 기계를 안 끌어와도 된다.
public enum Pins {

    /// 폴더 안의 자리. 숨김 폴더라 노트 목록에 안 보인다.
    public static let folder = ".여백"
    public static let fileName = ".여백/고정.json"

    /// 적힌 것을 읽는다. 깨졌거나 없으면 **빈 목록** — 고정은 잃어도 자료가 아니다.
    public static func decode(_ data: Data) -> [String] {
        guard let raw = try? JSONDecoder().decode([String].self, from: data) else { return [] }
        return tidy(raw)
    }

    public static func encode(_ paths: [String]) -> Data {
        (try? JSONEncoder().encode(tidy(paths))) ?? Data("[]".utf8)
    }

    /// **둘을 합친다** (부딪혔을 때). 겹치는 것은 한 번만, 차례는 앞엣것을 먼저.
    public static func merged(_ mine: [String], _ theirs: [String]) -> [String] {
        tidy(mine + theirs)
    }

    /// 빈 것을 걷어내고 NFC 로 맞추고 겹치는 것을 한 번만. 차례는 그대로 둔다 —
    /// 고정한 순서가 곧 위에서 아래 순서다.
    public static func tidy(_ paths: [String]) -> [String] {
        var seen: Set<String> = []
        var out: [String] = []
        for path in paths {
            let clean = Paths.normalized(path.trimmingCharacters(in: .whitespacesAndNewlines))
            guard !clean.isEmpty, !seen.contains(clean) else { continue }
            seen.insert(clean)
            out.append(clean)
        }
        return out
    }

    /// **이름이 바뀌거나 옮겨졌을 때 고정도 따라간다** (T10 의 고갱이).
    ///
    /// 이 앱은 첫 줄을 고치면 파일명이 따라 바뀐다(107). 고정을 **경로**로 적어 두므로
    /// 따라가지 않으면 *제목 고쳤더니 고정이 풀렸다* 가 된다. 이름 바꾸기 · 옮기기 ·
    /// 제목 따라가기 **세 자리**가 다 이것을 지나야 한다.
    ///
    /// 폴더가 통째로 바뀌면(`회의` → `주간회의`) 그 아래 것들도 따라간다.
    public static func following(_ paths: [String], from old: String, to new: String) -> [String] {
        let from = Paths.normalized(old)
        let to = Paths.normalized(new)
        guard !from.isEmpty, from != to else { return tidy(paths) }
        return tidy(paths.map { path in
            if path == from { return to }
            if path.hasPrefix(from + "/") { return to + String(path.dropFirst(from.count)) }
            return path
        })
    }

    /// 지워진 것을 뺀다. 폴더째 지워도 그 아래가 다 빠진다.
    public static func removing(_ paths: [String], at gone: String) -> [String] {
        let target = Paths.normalized(gone)
        guard !target.isEmpty else { return tidy(paths) }
        return tidy(paths.filter { $0 != target && !$0.hasPrefix(target + "/") })
    }
}
