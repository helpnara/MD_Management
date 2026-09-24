#!/usr/bin/env python3
"""스토어가 요구하는 **정확한 화소 크기**로 스크린샷을 맞춘다.

애플은 칸마다 크기를 **딱 그 숫자로** 요구한다. 손에 있는 기기가 그 크기가 아니면
(11인치 아이패드 · iPhone 17 Air) 찍은 그림을 그 칸에 맞춰 줘야 한다.

두 가지 길만 쓴다.

- **모양이 같으면 그냥 늘린다.** iPhone 17 Air(1260x2736)와 6.9인치(1320x2868)는
  가로세로 비가 0.05% 밖에 안 다르다 — 늘리기만 하면 된다.
- **모양이 다르면 여백을 먼저 넣는다.** 11인치 아이패드(2388x1668, 1.432)를
  13인치 칸(2752x2064, 1.333)에 넣으려면 **높이를 조금 보태야** 한다. 잘라내지 않는다 —
  화면 한 귀퉁이가 사라지는 것이 여백보다 나쁘다.

여백 색은 **그림 테두리에서 뽑는다.** 어두운 화면이면 검정이라 이어 붙인 자리가 안 보인다.
"""
import sys
from collections import Counter
from PIL import Image

# 애플이 요구하는 칸 (App Store Connect 의 업로드 칸에 적힌 숫자가 최종이다).
#
# **칸마다 받는 크기가 다르다.** 우리 앱의 아이폰 칸은 6.5인치였다 (2026-09-24 사용자
# 실측 — 1242x2688 · 2688x1242 · 1284x2778 · 2778x1284 중 하나). 6.9인치 칸을 미리
# 짐작해 맞췄다가 한 바퀴를 버렸다. **올리는 칸에 적힌 숫자를 먼저 읽는다.**
TARGETS = {
    "iphone-6.5-portrait": (1242, 2688),
    "iphone-6.5-landscape": (2688, 1242),
    "iphone-6.5-portrait-alt": (1284, 2778),
    "iphone-6.5-landscape-alt": (2778, 1284),
    "iphone-6.9-portrait": (1320, 2868),
    "iphone-6.9-landscape": (2868, 1320),
    "ipad-12.9-portrait": (2048, 2732),
    "ipad-12.9-landscape": (2732, 2048),
    "ipad-13-portrait": (2064, 2752),
    "ipad-13-landscape": (2752, 2064),
}

# 이보다 모양이 덜 다르면 여백 없이 늘리기만 한다.
SAME_SHAPE = 0.005


def border_color(image):
    """테두리 한 줄에서 가장 흔한 색 — 여백을 그 색으로 채운다."""
    pixels = []
    width, height = image.size
    for x in range(0, width, max(1, width // 200)):
        pixels.append(image.getpixel((x, 0)))
        pixels.append(image.getpixel((x, height - 1)))
    for y in range(0, height, max(1, height // 200)):
        pixels.append(image.getpixel((0, y)))
        pixels.append(image.getpixel((width - 1, y)))
    return Counter(pixels).most_common(1)[0][0]


def fit(source, target, out):
    image = Image.open(source).convert("RGB")
    want_w, want_h = target
    have = image.width / image.height
    want = want_w / want_h
    padded = image
    if abs(have - want) / want > SAME_SHAPE:
        if have > want:                      # 너무 옆으로 길다 — 위아래에 보탠다
            new_w, new_h = image.width, round(image.width / want)
        else:                                # 너무 위아래로 길다 — 옆에 보탠다
            new_w, new_h = round(image.height * want), image.height
        padded = Image.new("RGB", (new_w, new_h), border_color(image))
        padded.paste(image, ((new_w - image.width) // 2, (new_h - image.height) // 2))
    result = padded.resize((want_w, want_h), Image.LANCZOS)
    result.save(out, "PNG")
    grew = round((want_w / padded.width - 1) * 100)
    pad = "여백 없음" if padded.size == image.size else \
        f"여백 {padded.width - image.width}x{padded.height - image.height}"
    print(f"{out}  {image.size} -> {result.size}  ({pad}, 확대 {grew}%)")
    assert result.size == target, "크기가 안 맞는다"


def main(argv):
    if len(argv) != 4 or argv[2] not in TARGETS:
        print("쓰는 법: fit.py <찍은 그림> <칸> <낼 파일>")
        print("칸: " + " · ".join(TARGETS))
        return 2
    fit(argv[1], TARGETS[argv[2]], argv[3])
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
