#!/usr/bin/env python3
"""색 대비를 센다 (191). `CLAUDE.md` §6 과 같은 까닭 — 손으로 세지 않는다.

`App/DesignSystem/Palette.swift` 의 `quoteUIColor` 두 벌(어두움 · 밝음)을 **그 파일에서 읽어** 바탕(검정 · 흰색)과의
대비를 낸다. 숫자를 문서에 옮겨 적지 않는다 — 색을 고치면 이것만 다시 돌린다. 글자 기준은 4.5:1 (WCAG AA).
"""
import re
import sys
from pathlib import Path

PALETTE = Path("App/DesignSystem/Palette.swift")


def luminance(rgb):
    def channel(v):
        return v / 12.92 if v <= 0.03928 else ((v + 0.055) / 1.055) ** 2.4
    r, g, b = (channel(c) for c in rgb)
    return 0.2126 * r + 0.7152 * g + 0.0722 * b


def ratio(a, b):
    la, lb = sorted([luminance(a), luminance(b)], reverse=True)
    return (la + 0.05) / (lb + 0.05)


def main():
    text = PALETTE.read_text(encoding="utf-8")
    block = re.search(r"static let quoteUIColor = UIColor \{(.*?)\n    \}", text, re.S)
    if not block:
        sys.exit("quoteUIColor 를 못 찾았다")
    colors = re.findall(r"red: ([0-9.]+), green: ([0-9.]+), blue: ([0-9.]+)", block.group(1))
    if len(colors) != 2:
        sys.exit("어두움 · 밝음 두 벌이 아니다")
    failed = False
    for (name, background), rgb in zip((("어두움", (0, 0, 0)), ("밝음", (1, 1, 1))), colors):
        value = tuple(float(c) for c in rgb)
        r = ratio(value, background)
        hexed = "#%02X%02X%02X" % tuple(round(c * 255) for c in value)
        ok = r >= 4.5
        failed |= not ok
        print(f"인용 · {name}: {hexed} 대비 {r:.1f}:1 {'OK' if ok else '— 4.5 에 못 미친다'}")
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
