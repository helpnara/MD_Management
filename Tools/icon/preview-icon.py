#!/usr/bin/env python3
"""아이콘을 **실제로 보일 크기**로 줄여 한 장에 늘어놓는다.

    python3 Tools/icon/preview-icon.py [출력경로]

홈 화면 60pt(=180px @3x) 가 진짜 크기다. 1024 로만 보면 반드시 속는다.
"""

import sys
from pathlib import Path

from PIL import Image

SOURCE = Path("App/Assets.xcassets/AppIcon.appiconset/icon-1024.png")
SIZES = [180, 120, 87, 60]
PAPER = (255, 255, 255)
GAP = 24


def main() -> None:
    destination = Path(sys.argv[1] if len(sys.argv) > 1 else "icon-preview.png")
    icon = Image.open(SOURCE).convert("RGB")

    width = sum(SIZES) + GAP * (len(SIZES) + 1)
    height = max(SIZES) + GAP * 2
    sheet = Image.new("RGB", (width, height), PAPER)

    x = GAP
    for size in SIZES:
        sheet.paste(icon.resize((size, size), Image.LANCZOS), (x, (height - size) // 2))
        x += size + GAP

    sheet.save(destination, "PNG")
    print(f"{destination} — {SIZES} px")


if __name__ == "__main__":
    main()
