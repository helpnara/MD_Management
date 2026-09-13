#!/usr/bin/env python3
"""보내 주신 그림을 App Store 규격 아이콘으로 굽는다.

    python3 Tools/icon/bake-icon.py [원본경로]

원본 기본값은 `Tools/icon/icon-source.png` 이고,
결과는 `App/Assets.xcassets/AppIcon.appiconset/icon-1024.png` 다.

의존성: Pillow (`pip install -r Tools/icon/requirements.txt`)

── 하는 일 ──────────────────────────────────────────────────────
1. **알파를 없앤다.** 알파가 있으면 App Store 가 반려한다. 그냥 `convert("RGB")`
   하면 투명했던 자리가 검게 남는 일이 있어서 흰 바탕에 합성한다.
2. **흰 여백을 걷어낸다.** 그림 주위의 흰 테두리를 잘라 그림이 꽉 차게 한다.
3. **깎여 온 모서리를 없앤다.** 원본이 이미 모서리를 둥글게 깎아 왔으면
   **iOS 가 제 곡선으로 다시 깎을 때** 두 곡선 차이로 흰 조각이 비친다.
   두 가지로 없애는데, 되는 쪽을 자동으로 고른다:

   · **잘라내기(우선)** — 흰 모서리가 사라질 만큼만 안쪽으로 잘라낸다.
     깨끗하지만 그림을 조금 잃는다. 12% 넘게 잘라야 하면 쓰지 않는다.
   · **되메우기(대안)** — 가장자리 색을 바깥으로 늘여 채운다. 그림을 안 잃지만
     늘인 자국이 번져 보일 수 있다.
4. 가운데를 기준으로 정사각형으로 자른다.
5. 1024×1024 로 줄인다 (LANCZOS).

**모서리를 깎지 않는다** — iOS 가 알아서 한다. 여기서 깎으면 이중으로 깎인다.

`python3 Tools/icon/preview-icon.py` 로 실제 크기(180 · 120 · 87 · 60px)를
반드시 확인한다. 1024 로만 보면 속는다 — 홈 화면에서는 60pt 다.
"""

import sys
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw, ImageFilter

DEFAULT_SOURCE = Path("Tools/icon/icon-source.png")
OUTPUT = Path("App/Assets.xcassets/AppIcon.appiconset/icon-1024.png")
SIZE = 1024

# 흰색으로 볼 문턱. 그림 가장자리의 안티에일리어싱 픽셀은 이 아래라 그림 쪽에 남는다.
WHITE_THRESHOLD = 24
# 늘여 채운 자리를 살짝 뭉개는 반경. 늘인 자국(줄무늬)이 안 보이게 한다.
FILL_BLUR = 6


def flatten(image: Image.Image) -> Image.Image:
    if image.mode in ("RGBA", "LA", "P"):
        image = image.convert("RGBA")
        flat = Image.new("RGB", image.size, (255, 255, 255))
        flat.paste(image, mask=image.split()[-1])
        return flat
    return image.convert("RGB")


def outside_mask(image: Image.Image):
    """테두리에서 이어진 흰 픽셀만 '바깥'으로 본다.

    그림 안의 흰 부분(구름 · 하이라이트)은 테두리와 안 이어져 있으니 안 잡힌다.
    돌려주는 것은 `known`(그림인 곳 = 255) 마스크다.
    """
    probe = image.copy()
    marker = (255, 0, 255)
    for corner in ((0, 0), (image.width - 1, 0), (0, image.height - 1),
                   (image.width - 1, image.height - 1)):
        ImageDraw.floodfill(probe, corner, marker, thresh=WHITE_THRESHOLD)
    return ImageChops.difference(probe, Image.new("RGB", image.size, marker)) \
        .convert("L").point(lambda v: 255 if v > 0 else 0)


def crop_rounded_corners(image: Image.Image, known: Image.Image, limit: float = 0.12):
    """흰 모서리가 사라질 만큼만 안쪽으로 잘라낸다. 너무 많이 잘려야 하면 `None`."""
    side = min(image.size)
    most = int(side * limit)
    step = max(1, side // 400)

    inset = 0
    while inset <= most:
        box = (inset, inset, image.width - inset, image.height - inset)
        if known.crop(box).getextrema()[0] == 255:
            # 안티에일리어싱된 가장자리 한 줄을 더 잘라 낸다.
            extra = min(most, inset + step * 2)
            return image.crop((extra, extra, image.width - extra, image.height - extra))
        inset += step
    return None


def trim_and_fill(image: Image.Image) -> Image.Image:
    """흰 여백을 잘라내고, 테두리와 이어진 흰 모서리를 가장자리 색으로 메운다."""
    white = Image.new("RGB", image.size, (255, 255, 255))
    ink = ImageChops.difference(image, white).convert("L")
    box = ink.point(lambda v: 255 if v > WHITE_THRESHOLD else 0).getbbox()
    if box is None:
        raise SystemExit("원본이 통째로 흰색입니다")
    image = image.crop(box)

    known = outside_mask(image)
    if known.getextrema()[0] == 255:
        print("  흰 모서리 없음 — 그대로 씁니다")
        return image

    # 되도록 잘라낸다. 늘인 자국이 안 남는 쪽이다.
    cropped = crop_rounded_corners(image, known)
    if cropped is not None:
        lost = 100 * (1 - min(cropped.size) / min(image.size))
        print(f"  깎여 온 모서리를 잘라냈습니다 (가장자리 {lost:.1f}% 손실)")
        return cropped

    print("  너무 많이 잘려서 대신 가장자리 색을 늘여 메웁니다")

    # 가장자리 색을 한 픽셀씩 바깥으로 민다. 채워질 자리가 다 채워질 때까지.
    filled = image
    original_known = known
    for _ in range(max(image.size)):
        for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            shifted = ImageChops.offset(filled, dx, dy)
            shifted_known = ImageChops.offset(known, dx, dy)
            fresh = ImageChops.subtract(shifted_known, known)
            filled = Image.composite(shifted, filled, fresh)
            known = ImageChops.lighter(known, shifted_known)
        if known.getextrema()[0] == 255:
            break

    # 늘인 자리만 뭉갠다. 그림 쪽은 건드리지 않는다.
    softened = filled.filter(ImageFilter.GaussianBlur(FILL_BLUR))
    outside = ImageChops.invert(original_known)
    return Image.composite(softened, filled, outside)


def square(image: Image.Image) -> Image.Image:
    width, height = image.size
    if width == height:
        return image
    side = min(width, height)
    left = (width - side) // 2
    top = (height - side) // 2
    return image.crop((left, top, left + side, top + side))


def main() -> None:
    source_path = Path(sys.argv[1]) if len(sys.argv) > 1 else DEFAULT_SOURCE
    if not source_path.exists():
        raise SystemExit(
            f"원본이 없습니다: {source_path}\n"
            "그림 파일을 그 자리에 두고 다시 돌리세요."
        )

    icon = square(trim_and_fill(flatten(Image.open(source_path)))) \
        .resize((SIZE, SIZE), Image.LANCZOS)

    assert icon.mode == "RGB", "알파 채널이 있으면 App Store 가 반려한다"
    assert icon.size == (SIZE, SIZE)

    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    icon.save(OUTPUT, "PNG")
    print(f"{OUTPUT} — {icon.size[0]}×{icon.size[1]} {icon.mode} "
          f"{OUTPUT.stat().st_size:,}바이트")
    print("이제 `python3 Tools/icon/preview-icon.py` 로 60px 에서 읽히는지 보세요.")


if __name__ == "__main__":
    main()
