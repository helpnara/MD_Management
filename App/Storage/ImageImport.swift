import UIKit
import ImageIO
import UniformTypeIdentifiers
import Core

/// 사진첩에서 온 사진을 노트 옆 `assets/` 에 넣을 모양으로 다듬는다.
///
/// **JPEG 로 통일한다.** HEIC 는 맥 · 윈도우 · 옵시디언에서 안 열리는 곳이 있다.
/// 긴 변을 줄여 파일을 작게 한다 — 노트 300개 · 20MB 예산(S1) 안에 사진이 들어와야 한다.
enum ImageImport {

    /// 긴 변 상한. 화면 폭 2배면 어느 기기에서도 선명하다.
    static let maxSide: CGFloat = 2048

    /// 주 액터 밖에서 부른다 — 디코딩과 인코딩이 수백 ms 걸린다.
    ///
    /// **전체 해상도로 풀지 않는다** (181). 예전에는 `UIImage` 로 통째로 푼 뒤 줄여 그렸다 —
    /// 1억 화소 사진이면 풀기만 해도 수백 MB 라 iOS 가 앱을 끈다. ImageIO 가 **줄이면서 읽는다**.
    /// 사진의 방향(EXIF)도 여기서 바로 세운다. 작은 사진은 키우지 않는다.
    static func jpeg(from data: Data, quality: CGFloat = 0.85) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions),
              let image = downsampled(source, maxPixel: maxSide) else { return nil }
        return UIImage(cgImage: image).jpegData(compressionQuality: quality)
    }

    /// 폴더 안 사진의 **작은 그림**(PNG) — 커서 줄 사진 띠에 쓴다 (181). 파일을 통째로 메모리에
    /// 올리지 않고 파일에서 바로 줄여 읽는다. 사진이 아니면 `nil`.
    static func thumbnailPNG(at url: URL, maxPixel: CGFloat) -> Data? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, sourceOptions),
              let image = downsampled(source, maxPixel: maxPixel) else { return nil }
        let out = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            out, UTType.png.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return out as Data
    }

    /// 원본을 캐시에 풀어 두지 않는다 — 줄인 것만 남는다.
    private static var sourceOptions: CFDictionary {
        [kCGImageSourceShouldCache: false] as CFDictionary
    }

    private static func downsampled(_ source: CGImageSource, maxPixel: CGFloat) -> CGImage? {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
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
    ///
    /// **규칙은 Core 에 하나뿐이다** (147). 타이핑으로 노트를 연결할 때도 같은 함수를 쓴다 —
    /// 두 군데에 적어 두면 한쪽만 고쳐지는 날이 온다.
    static func markdownLink(label: String, path: String) -> String {
        NoteLinking.markdownLink(label: label, path: path)
    }
}
