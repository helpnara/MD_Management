#!/usr/bin/env python3
"""색 대비를 센다 (191). `CLAUDE.md` §6 과 같은 까닭 — 손으로 세지 않는다.

`App/DesignSystem/Palette.swift` 의 `quoteUIColor` · `tagUIColor` 두 벌(어두움 · 밝음)을 **그 파일에서 읽어** 바탕(종이 · 글자 인용 바탕)과의
대비를 낸다. 태그는 232 에서 더했다 — 밝은 화면에서 3.3:1 이었다. 숫자를 문서에 옮겨 적지 않는다 — 색을 고치면 이것만 다시 돌린다. 글자 기준은 4.5:1 (WCAG AA).
"""
import re
import sys
from pathlib import Path

PALETTE = Path("App/DesignSystem/Palette.swift")

# 바탕. 인용은 종이 위, 글자 인용(196)은 한 단 뜬 바탕(`secondarySystemBackground`) 위에 놓인다. 시스템 색이라
# 파일에서 못 읽는다 — iOS 가 정한 값이다 (어두움 #1C1C1E · 밝음 #F2F2F7).
DARK = (("인용", (0, 0, 0)), ("글자 인용", (28 / 255, 28 / 255, 30 / 255)))
LIGHT = (("인용", (1, 1, 1)), ("글자 인용", (242 / 255, 242 / 255, 247 / 255)))
# 태그(`#일`)는 종이 위에만 놓인다 — 쓰기 · 읽기 둘 다 (232).
TAG_DARK = (("태그", (0, 0, 0)),)
TAG_LIGHT = (("태그", (1, 1, 1)),)

# 잴 색 · 그 색이 놓이는 바탕 (어두움 · 밝음).
CHECKS = (("quoteUIColor", DARK, LIGHT), ("tagUIColor", TAG_DARK, TAG_LIGHT))


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
    failed = False
    for symbol, dark, light in CHECKS:
        block = re.search(r"static let " + symbol + r" = UIColor \{(.*?)\n    \}", text, re.S)
        if not block:
            sys.exit(f"{symbol} 를 못 찾았다")
        colors = re.findall(r"red: ([0-9.]+), green: ([0-9.]+), blue: ([0-9.]+)", block.group(1))
        if len(colors) != 2:
            sys.exit(f"{symbol}: 어두움 · 밝음 두 벌이 아니다")
        for (name, papers), rgb in zip((("어두움", dark), ("밝음", light)), colors):
            value = tuple(float(c) for c in rgb)
            hexed = "#%02X%02X%02X" % tuple(round(c * 255) for c in value)
            for where, background in papers:
                r = ratio(value, background)
                ok = r >= 4.5
                failed |= not ok
                print(f"{where} · {name}: {hexed} 대비 {r:.1f}:1 {'OK' if ok else '— 4.5 에 못 미친다'}")
    sys.exit(1 if failed else 0)

if __name__ == "__main__":
    main()
