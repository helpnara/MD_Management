#!/usr/bin/env python3
"""**스크린샷 위에 글귀 한 줄** (2026-10-11 사용자 — 스토어 손질 3번 · `docs/44-store-refresh.md`).

검색 결과에는 앞의 세 장만 보인다 — 그 세 장이 *무엇을 하는 앱인지* 말해야 한다. 앱 화면을 조금 줄여 아래에 두고,
위에 짧은 글귀를 얹는다. **결과는 칸 크기 그대로**다 (늘리지 않는 원본을 줄여 넣는다 · 마지막 단계가 잰다).

    python3 Tools/store/frame.py <원본.png> <칸> <글귀> <결과.png> [--font 글꼴]

칸: `iphone-6.5` (1242 × 2688 · 한국어 칸) · `iphone-6.1` (1206 × 2622 · 영어 칸) · `ipad-13` (2064 × 2752 · 세로).
글꼴: 맥 러너의 `AppleSDGothicNeo.ttc` 에서 굵은 것을 고른다 (한글 · 영문 둘 다). `--font` 로 바꿀 수 있다.
"""
import argparse
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont

SLOTS = {
    "iphone-6.5": (1242, 2688),
    "iphone-6.1": (1206, 2622),
    "ipad-13": (2064, 2752),
}
# 종이 같은 바탕 · 먹색 글 — 앱의 *여백* 과 같은 결.
PAPER = (244, 239, 230)
INK = (43, 42, 40)
# 맥 판마다 자리가 다를 수 있어 차례로 찾는다 — 한글 · 영문이 둘 다 있는 굵은 고딕.
MAC_FONTS = [
    "/System/Library/Fonts/AppleSDGothicNeo.ttc",
    "/System/Library/Fonts/Supplemental/AppleSDGothicNeo.ttc",
    "/System/Library/Fonts/Supplemental/AppleGothic.ttf",
]


def pick_font(path: str, size: int) -> ImageFont.FreeTypeFont:
    """`.ttc` 안에서 굵은 것을 고른다 — 차례 번호가 맥 판마다 다를 수 있어 이름으로 찾는다."""
    if not path.endswith(".ttc"):
        return ImageFont.truetype(path, size)
    found = {}
    for index in range(32):
        try:
            font = ImageFont.truetype(path, size, index=index)
        except OSError:
            break
        found[font.getname()[1].lower()] = font
    for style in ("bold", "semibold", "medium", "regular"):
        if style in found:
            return found[style]
    if not found:
        raise SystemExit(f"::error::글꼴을 못 읽었다: {path}")
    return next(iter(found.values()))


def rounded(image: Image.Image, radius: int) -> Image.Image:
    mask = Image.new("L", image.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, image.width - 1, image.height - 1), radius=radius, fill=255)
    out = Image.new("RGBA", image.size)
    out.paste(image, (0, 0), mask)
    return out


def frame(raw: Image.Image, slot: tuple[int, int], caption: str, font_path: str) -> Image.Image:
    width, height = slot
    canvas = Image.new("RGB", slot, PAPER)
    draw = ImageDraw.Draw(canvas)

    # 글귀 — 한 줄, 칸 폭의 86% 안에 들어가게 글자 크기를 줄여 가며.
    size = int(width * (0.074 if width < 1500 else 0.056))
    font = pick_font(font_path, size)
    while draw.textlength(caption, font=font) > width * 0.86 and size > 20:
        size -= 2
        font = pick_font(font_path, size)
    top = int(height * 0.055)
    box = draw.textbbox((0, 0), caption, font=font)
    text_w, text_h = box[2] - box[0], box[3] - box[1]
    draw.text(((width - text_w) / 2 - box[0], top - box[1]), caption, font=font, fill=INK)

    # 앱 화면 — 글귀 아래 남은 자리에 맞춰 줄인다 (모양은 그대로).
    gap = int(height * 0.04)
    area_top = top + text_h + gap
    area_h = height - area_top - int(height * 0.035)
    area_w = int(width * 0.86)
    scale = min(area_w / raw.width, area_h / raw.height)
    shot = raw.convert("RGB").resize((round(raw.width * scale), round(raw.height * scale)), Image.LANCZOS)
    radius = int(shot.width * 0.06)
    shot = rounded(shot, radius)
    x = (width - shot.width) // 2
    y = area_top

    # 옅은 그림자 — 종이 위에 놓인 것처럼.
    shadow = Image.new("RGBA", slot, (0, 0, 0, 0))
    ImageDraw.Draw(shadow).rounded_rectangle((x, y + 10, x + shot.width, y + shot.height + 10), radius=radius,
                                             fill=(0, 0, 0, 60))
    shadow = shadow.filter(ImageFilter.GaussianBlur(24))
    canvas = Image.alpha_composite(canvas.convert("RGBA"), shadow)
    canvas.paste(shot, (x, y), shot)
    return canvas.convert("RGB")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("raw")
    parser.add_argument("slot", choices=sorted(SLOTS))
    parser.add_argument("caption")
    parser.add_argument("out")
    parser.add_argument("--font")
    args = parser.parse_args()
    font = args.font or next((f for f in MAC_FONTS if Path(f).exists()), None)
    if not font or not Path(font).exists():
        print(f"::error::글꼴이 없다: {args.font or MAC_FONTS}")
        return 1
    args.font = font
    result = frame(Image.open(args.raw), SLOTS[args.slot], args.caption, args.font)
    assert result.size == SLOTS[args.slot] and result.mode == "RGB", result.size
    result.save(args.out, "PNG")
    print(f"글귀 얹음: {args.out} {result.size} — {args.caption}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
