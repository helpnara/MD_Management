#!/usr/bin/env python3
"""앱 아이콘을 그린다.

    python3 Tools/icon/make-icon.py

`App/Assets.xcassets/AppIcon.appiconset/icon-1024.png` 를 만든다.
의존성: Pillow (`pip install pillow`)

── 무엇을 그리나 ────────────────────────────────────────────────
종이 바탕에 먹색 가로줄 몇 개, 그리고 **줄 사이의 빈 자리**.
그 빈 자리가 이 앱의 이름이자 하는 일이다 (docs/roadmap.md §4).

홈 화면에서 아이콘은 **60pt** 로 그려진다. 그래서:

· 글자를 넣지 않는다 — 한글은 60pt 에서 안 읽힌다 (Apple HIG)
· 큰 색 덩어리만 쓴다 — 잔 디테일은 뭉개진다
· 모서리를 깎지 않는다 — iOS 가 알아서 깎는다. 여기서 깎으면 이중으로 깎인다
· 알파 채널을 없앤다 — 알파가 있으면 App Store 가 반려한다

`python3 Tools/icon/preview-icon.py` 로 실제 크기를 미리 볼 수 있다.
"""

from pathlib import Path

from PIL import Image, ImageDraw

OUTPUT = Path("App/Assets.xcassets/AppIcon.appiconset/icon-1024.png")
SIZE = 1024

PAPER = (247, 244, 237)   # 따뜻한 종이
INK = (38, 40, 44)        # 먹
INK_SOFT = (168, 166, 160)  # 흐린 먹 — 여백 쪽 줄

# (세로 위치, 가로 시작, 가로 끝, 색) — 전부 0~1 비율
LINES = [
    (0.255, 0.20, 0.80, INK),
    (0.355, 0.20, 0.62, INK),
    # ── 여기가 여백이다 ──
    (0.620, 0.20, 0.80, INK_SOFT),
    (0.720, 0.20, 0.55, INK_SOFT),
]

BAR_HEIGHT = 0.062   # 줄 두께 (비율)


def draw() -> Image.Image:
    image = Image.new("RGB", (SIZE, SIZE), PAPER)
    canvas = ImageDraw.Draw(image)

    thickness = SIZE * BAR_HEIGHT
    radius = thickness / 2

    for top, start, end, color in LINES:
        y = SIZE * top
        canvas.rounded_rectangle(
            [SIZE * start, y, SIZE * end, y + thickness],
            radius=radius,
            fill=color,
        )

    # 줄 사이의 빈 자리를 **한 번 더 말해 준다** — 가는 세로 표시 하나.
    # 60pt 에서는 안 보이지만 큰 크기(스토어 · 설정)에서 뜻이 읽힌다.
    mark_x = SIZE * 0.845
    canvas.rounded_rectangle(
        [mark_x, SIZE * 0.355 + thickness, mark_x + SIZE * 0.016, SIZE * 0.620],
        radius=SIZE * 0.008,
        fill=INK_SOFT,
    )
    return image


def main() -> None:
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    image = draw()
    # 알파 없이 저장한다.
    image.convert("RGB").save(OUTPUT, "PNG", optimize=True)
    print(f"{OUTPUT} — {OUTPUT.stat().st_size:,}바이트 {image.size[0]}x{image.size[1]}")


if __name__ == "__main__":
    main()
