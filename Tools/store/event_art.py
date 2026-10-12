#!/usr/bin/env python3
"""**인앱 이벤트 그림 두 장** (2026-10-12 사용자 — *그림 두 장 지금 만들어 줘* · `docs/promo/launch-kit.md` §3).

이벤트 카드(가로 1920 × 1080)와 상세(세로 1080 × 1920). 글자는 넣지 않는다 — 앱 스토어가 이벤트 이름 · 짧은 설명을
**그림 아래쪽에 얹는다**. 그래서 앱 화면은 위쪽에 두고, 아래쪽은 먹색으로 서서히 어둡게 해 그 위의 흰 글이 읽히게 한다.
양옆도 조금 잘릴 수 있어 화면은 가운데에 둔다.

원본은 스토어 스크린샷 3번(링크 모음)이다 — 글귀를 얹은 판에서 **앱 화면만** 도로 잘라 쓴다(흰 화면의 테두리를 찾는다).
글귀 없는 원본은 흐름의 결과 묶음에만 있는데, 여기서는 그 묶음을 받을 수 없다.

    python3 Tools/store/event_art.py            # docs/store/event/{ko,en}-{card,detail}.png
"""
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "docs/store/screenshots/{lang}/iphone-3-links.png"
OUT = ROOT / "docs/store/event"
# frame.py 와 같은 종이 · 먹.
PAPER = (244, 239, 230)
INK = (43, 42, 40)

# 칸 크기 · 화면 폭 · 화면 위 끝 · 어둡게 하기 시작하는 높이(비율).
LAYOUTS = {
    "card": {"size": (1920, 1080), "width": 640, "top": 64, "fade_from": 0.52},
    "detail": {"size": (1080, 1920), "width": 860, "top": 120, "fade_from": 0.60},
}


def screen_of(framed: Image.Image) -> Image.Image:
    """글귀 얹은 스크린샷에서 흰 앱 화면의 사각형을 찾아 잘라 낸다 (둥근 모서리 · 그림자는 빼고)."""
    im = framed.convert("RGB")
    px = im.load()
    w, h = im.size

    def white(p):
        return min(p) >= 252

    x = int(w * 0.3)
    ys = [y for y in range(h) if white(px[x, y])]
    y = int(h * 0.6)
    xs = [x for x in range(w) if white(px[x, y])]
    top, bottom, left, right = ys[0], ys[-1], xs[0], xs[-1]
    return im.crop((left, top, right + 1, bottom + 1))


def compose(screen: Image.Image, layout: dict) -> Image.Image:
    size = layout["size"]
    canvas = Image.new("RGBA", size, PAPER + (255,))
    scale = layout["width"] / screen.width
    shot = screen.resize((layout["width"], round(screen.height * scale)), Image.LANCZOS)
    radius = int(shot.width * 0.06)
    x = (size[0] - shot.width) // 2
    y = layout["top"]

    # 옅은 그림자 — 스크린샷의 결과 같게.
    shadow = Image.new("RGBA", size, (0, 0, 0, 0))
    ImageDraw.Draw(shadow).rounded_rectangle((x, y + 10, x + shot.width, y + shot.height + 10), radius=radius,
                                             fill=(0, 0, 0, 60))
    canvas = Image.alpha_composite(canvas, shadow.filter(ImageFilter.GaussianBlur(24)))
    mask = Image.new("L", shot.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, shot.width - 1, shot.height - 1), radius=radius, fill=255)
    canvas.paste(shot, (x, y), mask)

    # 아래쪽을 먹색으로 — 앱 스토어가 얹는 이벤트 이름 · 설명 자리.
    fade = Image.new("L", size, 0)
    draw = ImageDraw.Draw(fade)
    start = int(size[1] * layout["fade_from"])
    for row in range(start, size[1]):
        t = (row - start) / (size[1] - 1 - start)
        draw.line((0, row, size[0], row), fill=int(255 * 0.82 * (t ** 1.4)))
    ink = Image.new("RGBA", size, INK + (255,))
    canvas = Image.composite(ink, canvas, fade)
    return canvas.convert("RGB")


def main() -> int:
    OUT.mkdir(parents=True, exist_ok=True)
    for lang in ("ko", "en"):
        screen = screen_of(Image.open(str(SOURCE).format(lang=lang)))
        for name, layout in LAYOUTS.items():
            result = compose(screen, layout)
            assert result.size == layout["size"] and result.mode == "RGB", result.size
            path = OUT / f"{lang}-{name}.png"
            result.save(path, "PNG")
            print(f"{path.relative_to(ROOT)} {result.size}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
