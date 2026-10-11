import Foundation

/// **글로 온 주소를 주소로** (240, 2026-10-11 사용자 — *유튜브에서 공유하면 받은 글에 링크만 들어온다*).
///
/// 사파리는 주소를 *주소* 로 주지만 유튜브 같은 앱은 주소 한 줄을 *글* 로 준다. 그대로 두면 글의 첫 줄(주소)이
/// 노트 제목 · 파일 이름(`https---…`)이 되고, 주소가 아니니 공유 창이 쪽 제목을 가져오지도 않는다.
/// 그래서 **받은 글이 웹 주소 하나뿐이면** 그것을 주소로 옮기고 글을 비운다 — 그러면 사파리와 같은 길(제목 가져오기 →
/// `# 제목` · `[제목](주소)`)을 탄다. 이미 같은 주소가 주소로 왔으면 글만 비운다.
/// 글이 조금이라도 함께 있으면(*이것 봐 https://…*) 건드리지 않는다 — 사용자가 쓴 글이 제목이다.
///
/// **이 파일은 공유 확장도 함께 빌드한다** (`project.yml` — 확장은 Core 를 잇지 않는다). 그래서 Foundation 밖의
/// Core 것을 부르지 않는다. 셈하는 곳은 여기 하나다 — 확장이 부르고, 리눅스 테스트가 정답표로 본다.
/// 파이썬 쌍둥이: `Tools/golden/generate.py` 의 `shared_address` (`sharedAddressCases`).
public enum SharedAddress {

    /// 주소 앞뒤에서 떼고, 주소 안에 있으면 주소가 아닌 것으로 보는 빈칸들 (파이썬과 같은 목록 — 플랫폼마다 *빈칸* 의 뜻이 달라 못 박는다).
    static let blanks: Set<Unicode.Scalar> = [
        " ", "\t", "\n", "\r", "\u{0B}", "\u{0C}", "\u{85}", "\u{A0}", "\u{2028}", "\u{2029}", "\u{3000}", "\u{FEFF}",
    ]

    /// 받은 글 · 받은 주소 → 노트로 넘길 글 · 주소.
    public static func separate(text: String, url: String?) -> (text: String, url: String?) {
        guard let lone = webAddress(text) else { return (text, url) }
        if url == nil { return ("", lone) }
        if url == lone { return ("", url) }
        return (text, url)
    }

    /// 글이 앞뒤 빈칸을 빼고 `http://` · `https://` 주소 하나뿐이면 그 주소. 사이트 이름이 없으면(`https://`) 아니다.
    public static func webAddress(_ text: String) -> String? {
        var scalars = Array(text.unicodeScalars)
        while let first = scalars.first, blanks.contains(first) { scalars.removeFirst() }
        while let last = scalars.last, blanks.contains(last) { scalars.removeLast() }
        guard !scalars.contains(where: { blanks.contains($0) }) else { return nil }
        for scheme in ["https://", "http://"] {
            let head = Array(scheme.unicodeScalars)
            guard scalars.count > head.count,
                  zip(scalars, head).allSatisfy({ pair in asciiLower(pair.0) == pair.1 }) else { continue }
            let host = scalars[head.count...].prefix { $0 != "/" && $0 != "?" && $0 != "#" }
            guard !host.isEmpty else { return nil }
            var view = String.UnicodeScalarView()
            view.append(contentsOf: scalars)
            return String(view)
        }
        return nil
    }

    /// 영어 대문자만 소문자로 — 다른 글자는 그대로 (파이썬과 같게).
    private static func asciiLower(_ scalar: Unicode.Scalar) -> Unicode.Scalar {
        guard scalar.value >= 0x41, scalar.value <= 0x5A, let lower = Unicode.Scalar(scalar.value + 32) else { return scalar }
        return lower
    }
}
