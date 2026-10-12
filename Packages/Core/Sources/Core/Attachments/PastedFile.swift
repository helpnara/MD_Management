import Foundation

/// **붙여넣은 첨부가 무엇인가** (243, 2026-10-12 사용자 — *메모 내용이 사진과 아이폰 녹음 파일 그리고 텍스트로 구성이 되어
/// 있는데 이를 전체복사 후 붙여넣기하면 올바르게 복사 붙여넣기가 안 된다*).
///
/// 메모에서 글 · 사진 · 녹음을 함께 복사하면 첨부가 서식 있는 글(RTFD)에 **같이** 온다. 예전에는 그 첨부를 모두 사진으로 여겼고,
/// 사진 판별은 앞 바이트에 `ftyp` 상자가 있으면 **무조건** HEIC 사진으로 봤다 — 아이폰 녹음(m4a) · 동영상(mov · mp4)도 같은
/// `ftyp` 상자로 시작한다. 그래서 녹음을 사진(`.jpg`)으로 줄이려다 실패해 *사진을 저장하지 못했다* 가 뜨고 깨진 사진 링크가 남았다.
///
/// 이제 `ftyp` 은 **브랜드**까지 본다. 사진이면 사진(`![](…)`), 아니면 **원래 바이트 그대로** 파일로 두고 이름 붙은 링크
/// (`[새로운 녹음 3.m4a](assets/…)`)로 넣는다 — 문서 첨부(78)와 같은 모양. 읽기 화면에서 누르면 미리보기로 들린다.
///
/// 파이썬 쌍둥이: `Tools/golden/generate.py` 의 `pasted_file_kind` · `pasted_file_label` (`pastedFileCases`).
public enum PastedFile {

    public enum Kind: Equatable, Sendable {
        /// 사진 — 저장할 확장자. PNG · GIF 는 그대로, 사진기 사진(JPEG · HEIC · AVIF)은 줄여서 `jpg`.
        case image(String)
        /// 사진이 아닌 파일 — 원래 바이트 그대로 이 확장자로.
        case file(String)
        /// 앞 바이트 · 이름으로 모르겠다 — 앱이 사진으로 읽어 보고, 아니면 버린다.
        case unknown
    }

    static let heifImageBrands: Set<String> = ["heic", "heif", "heix", "hevc", "hevx", "heim", "heis", "hevm", "hevs",
                                               "mif1", "msf1", "avif", "avis"]
    static let namedImageExtensions: Set<String> = ["png", "jpg", "jpeg", "gif", "heic", "heif", "webp", "tif", "tiff", "bmp"]

    /// 앞 바이트(16 바이트면 넉넉하다)와 첨부가 실어 온 이름으로 가른다.
    public static func kind(head: [UInt8], fileName: String?) -> Kind {
        let h = head
        func starts(_ bytes: [UInt8]) -> Bool { h.starts(with: bytes) }
        if starts([0x89, 0x50, 0x4E, 0x47]) { return .image("png") }
        if starts([0x47, 0x49, 0x46, 0x38]) { return .image("gif") }
        if starts([0xFF, 0xD8, 0xFF]) { return .image("jpg") }
        if h.count >= 12, Array(h[4..<8]) == Array("ftyp".utf8) {
            let brand = String(h[8..<12].map { Character(Unicode.Scalar($0)) })
            if heifImageBrands.contains(brand.lowercased()) { return .image("jpg") }
            switch brand {
            case "M4A ": return .file("m4a")
            case "M4B ": return .file("m4b")
            case "M4V ": return .file("m4v")
            case "qt  ": return .file("mov")
            default: break
            }
            if brand.hasPrefix("3g") { return .file("3gp") }
            if let named = nameExtension(fileName), ["mp4", "m4a", "mov", "m4v"].contains(named) { return .file(named) }
            return .file("mp4")
        }
        if starts(Array("%PDF".utf8)) { return .file("pdf") }
        if starts(Array("RIFF".utf8)), h.count >= 12, Array(h[8..<12]) == Array("WAVE".utf8) { return .file("wav") }
        if starts(Array("ID3".utf8)) || starts([0xFF, 0xFB]) || starts([0xFF, 0xF3]) || starts([0xFF, 0xF2]) {
            return .file("mp3")
        }
        if starts(Array("caff".utf8)) { return .file("caf") }
        if starts([0x50, 0x4B, 0x03, 0x04]) { return .file(nameExtension(fileName) ?? "zip") }
        if let named = nameExtension(fileName), !namedImageExtensions.contains(named) { return .file(named) }
        return .unknown
    }

    /// 링크에 보일 이름 — 첨부가 실어 온 이름(NFC). 확장자가 없으면 붙이고, 이름이 없으면 `fallback.확장자`.
    public static func label(fileName: String?, ext: String, fallback: String) -> String {
        let name = (fileName ?? "").trimmingCharacters(in: .whitespacesAndNewlines).precomposedStringWithCanonicalMapping
        guard !name.isEmpty else { return fallback + "." + ext }
        return nameExtension(name) != nil ? name : name + "." + ext
    }

    /// **첨부 자리마다 쓸 첨부의 차례** (243, 2026-10-12 사용자 진단 — 메모는 동영상을 `<object data="file:///이름">`, 사진을
    /// `<img src="file:///이름">` 로 싣고, 첨부(RTFD)도 따로 실었다. 예전에는 차례로만 짝지어 첫 첨부(동영상)가 사진 자리에 들어갔다).
    ///
    /// `slots` 는 자리의 주소 — `nil` 이면 첨부를 안 쓰는 자리(웹 · `data:` 주소). `names` 는 첨부가 실어 온 이름.
    /// ① **이름으로 먼저** — 자리 주소의 파일 이름과 첨부 이름이 같으면(퍼센트 부호 · NFC · 대소문자 무시). ② 남은 자리는 안 쓴 첨부를
    /// 차례대로. 모자라면 `nil`. 파이썬 쌍둥이: `pasted_file_matches`.
    public static func matches(slots: [String?], names: [String?]) -> [Int?] {
        var out = [Int?](repeating: nil, count: slots.count)
        var used = Set<Int>()
        let keys = names.map(fileKey)
        for (i, slot) in slots.enumerated() {
            guard let slot, let want = fileKey(slot) else { continue }
            if let k = keys.indices.first(where: { !used.contains($0) && keys[$0] == want }) {
                out[i] = k
                used.insert(k)
            }
        }
        for (i, slot) in slots.enumerated() where slot != nil && out[i] == nil {
            if let k = names.indices.first(where: { !used.contains($0) }) {
                out[i] = k
                used.insert(k)
            }
        }
        return out
    }

    /// 주소 · 이름의 **파일 이름 열쇠** — 마지막 `/` 뒤, 퍼센트 부호 풀기, NFC, 소문자. 비면 `nil`.
    static func fileKey(_ text: String?) -> String? {
        guard let text, !text.isEmpty else { return nil }
        let last = text.split(separator: "/", omittingEmptySubsequences: false).last.map(String.init) ?? text
        let name = (last.removingPercentEncoding ?? last).precomposedStringWithCanonicalMapping.lowercased()
        return name.isEmpty ? nil : name
    }

    /// 이름의 확장자 — 영어 · 숫자 1~8 자일 때만 (소문자). 아니면 `nil`.
    static func nameExtension(_ fileName: String?) -> String? {
        guard let fileName, !fileName.isEmpty else { return nil }
        let base = fileName.split(separator: "/", omittingEmptySubsequences: false).last.map(String.init) ?? fileName
        guard let dot = base.lastIndex(of: ".") else { return nil }
        let ext = base[base.index(after: dot)...]
        guard (1...8).contains(ext.count),
              ext.unicodeScalars.allSatisfy({ $0.isASCII && (CharacterSet.alphanumerics.contains($0)) }) else { return nil }
        return ext.lowercased()
    }
}
