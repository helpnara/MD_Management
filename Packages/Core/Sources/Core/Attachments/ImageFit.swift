import Foundation

/// **사진을 줄일 때의 긴 변** (299, 2026-11-01 사용자 — 아이패드 메모의 긴 손글씨 그림이 *해상도가 너무 낮아서 글자를 알아볼 수가 없어* ·
/// *높이가 짧으면 나름 선명하게 나오는데*).
///
/// 예전에는 **긴 변만 2048** 로 맞췄다. 보통 사진(4:3 · 16:9)은 그걸로 어느 화면에서도 선명하지만, 세로로 길게 쓴 손글씨(1:4 · 1:6)는
/// 긴 변 2048 이면 **가로가 512 · 340** 이 되어 글자가 뭉개진다 — 읽기 화면은 가로를 화면 폭에 맞춰 키우므로 더 흐리다.
/// 그래서 **짧은 변을 1024 까지 지킨다** — 긴 변 2048 로 줄였을 때 짧은 변이 1024 아래로 떨어지면, 짧은 변을 1024(원본이 그보다 작으면 원본)
/// 로 두고 긴 변은 그 비율대로 둔다. 긴 변은 8192 를 넘지 않는다(그 위는 기기가 그리기도 버겁다). 작은 사진은 키우지 않는다.
///
/// 파이썬 쌍둥이: `image_fit_long_side`.
public enum ImageFit {
    /// 긴 변 상한. 화면 폭 2배면 어느 기기에서도 선명하다.
    public static let maxSide: Double = 2048
    /// 짧은 변의 하한 — 긴 그림의 가로가 이 아래로 떨어지지 않게.
    public static let minShortSide: Double = 1024
    /// 그래도 긴 변은 여기까지.
    public static let hardMaxSide: Double = 8192

    /// 줄인 뒤의 긴 변(픽셀). 원본의 가로 · 세로가 0 이하면 `maxSide`.
    public static func longSide(width: Double, height: Double) -> Double {
        let long = max(width, height)
        let short = min(width, height)
        guard long > 0, short > 0 else { return maxSide }
        if long <= maxSide { return long }
        let shortAtMax = short * maxSide / long
        if shortAtMax >= minShortSide { return maxSide }
        let keptShort = min(short, minShortSide)
        return min(long * keptShort / short, hardMaxSide, long).rounded(.down)
    }
}
