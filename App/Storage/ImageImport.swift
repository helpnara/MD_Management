import UIKit

/// 사진첩에서 온 사진을 노트 옆 `assets/` 에 넣을 모양으로 다듬는다.
///
/// **JPEG 로 통일한다.** HEIC 는 맥 · 윈도우 · 옵시디언에서 안 열리는 곳이 있다.
/// 긴 변을 줄여 파일을 작게 한다 — 노트 300개 · 20MB 예산(S1) 안에 사진이 들어와야 한다.
enum ImageImport {

    /// 긴 변 상한. 화면 폭 2배면 어느 기기에서도 선명하다.
    static let maxSide: CGFloat = 2048

    /// 주 액터 밖에서 부른다 — 디코딩과 인코딩이 수백 ms 걸린다.
    static func jpeg(from data: Data, quality: CGFloat = 0.85) -> Data? {
        guard let image = UIImage(data: data) else { return nil }
        let size = image.size
        let longest = max(size.width, size.height)
        guard longest > 0 else { return nil }

        let scale = min(1, maxSide / longest)
        let target = CGSize(width: (size.width * scale).rounded(), height: (size.height * scale).rounded())

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1   // 점 크기 = 화소 크기. 안 그러면 3배로 커진다.
        let rendered = UIGraphicsImageRenderer(size: target, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
        return rendered.jpegData(compressionQuality: quality)
    }

    /// `2026-09-13` — 저장소가 뒤에 `-1.jpg` `-2.jpg` 를 붙인다. 공백이 없어 링크에
    /// 꺾쇠가 필요 없다.
    static func stem(for date: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    /// 경로에 빈칸이 있으면 `<>` 로 감싼다 — CommonMark 는 빈칸 있는 주소를 링크로
    /// 안 읽는다. 우리가 만든 이름에는 없지만, 사용자가 바꾼 이름에는 있을 수 있다.
    static func markdownImage(path: String) -> String {
        let needsBrackets = path.contains(" ")
        return "![](" + (needsBrackets ? "<" + path + ">" : path) + ")"
    }

    /// 문서 첨부의 링크 — `[이름.pdf](<assets/이름-1.pdf>)`. 사진과 같은 규칙으로 빈칸은 꺾쇠.
    static func markdownLink(label: String, path: String) -> String {
        let needsBrackets = path.contains(" ")
        let safeLabel = label.replacingOccurrences(of: "]", with: " ")
        return "[" + safeLabel + "](" + (needsBrackets ? "<" + path + ">" : path) + ")"
    }
}
