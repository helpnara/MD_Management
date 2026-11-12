#!/usr/bin/env python3
"""색 대비를 센다 (191). `CLAUDE.md` §6 과 같은 까닭 — 손으로 세지 않는다.

`App/DesignSystem/Palette.swift` 의 글자 색들(먹 · 옅은 먹 · 잎 초록 · 인용 · 태그) 두 벌(어두움 · 밝음)을 **그 파일에서 읽어** 바탕(종이 · 뜬 종이 · 묶음 바탕 — 316 부터 이것도 그 파일에서 바탕)과의
대비를 낸다. 태그는 232 에서 더했다 — 밝은 화면에서 3.3:1 이었다. 숫자를 문서에 옮겨 적지 않는다 — 색을 고치면 이것만 다시 돌린다. 글자 기준은 4.5:1 (WCAG AA).
"""
import re
import sys
from pathlib import Path

PALETTE = Path("App/DesignSystem/Palette.swift")

# **바탕도 이 파일에서 읽는다** (316 — 종이색). 예전에는 시스템 흰색 · 검정을 여기 적어 두었다 — 바탕이 바뀌면 이 숫자가 거짓이 된다.
# (글자 색, 그 색이 놓이는 바탕들). 인용은 종이 위, 글자 인용(196)은 한 겹 뜬 바탕 위. 태그는 종이 위에만 (232).
CHECKS = (
    ("inkUIColor", ("paperUIColor", "paperRaisedUIColor", "paperGroupedUIColor")),
    ("inkFaintUIColor", ("paperUIColor", "paperRaisedUIColor", "paperGroupedUIColor")),
    ("accentUIColor", ("paperUIColor", "paperRaisedUIColor", "paperGroupedUIColor")),
    ("quoteUIColor", ("paperUIColor", "paperRaisedUIColor")),
    ("tagUIColor", ("paperUIColor",)),
)
NAMES = {"paperUIColor": "종이", "paperRaisedUIColor": "뜬 종이", "paperGroupedUIColor": "묶음 바탕"}


def luminance(rgb):
    def channel(v):
        return v / 12.92 if v <= 0.03928 else ((v + 0.055) / 1.055) ** 2.4
    r, g, b = (channel(c) for c in rgb)
    return 0.2126 * r + 0.7152 * g + 0.0722 * b


def ratio(a, b):
    la, lb = sorted([luminance(a), luminance(b)], reverse=True)
    return (la + 0.05) / (lb + 0.05)


def read(text, symbol):
    """그 색의 (어두움, 밝음) — 파일에 적힌 차례 그대로."""
    block = re.search(r"static let " + symbol + r" = UIColor \{(.*?)\n    \}", text, re.S)
    if not block:
        sys.exit(f"{symbol} 를 못 찾았다")
    colors = re.findall(r"red: ([0-9.]+), green: ([0-9.]+), blue: ([0-9.]+)", block.group(1))
    if len(colors) != 2:
        sys.exit(f"{symbol}: 어두움 · 밝음 두 벌이 아니다")
    return [tuple(float(c) for c in rgb) for rgb in colors]


def main():
    text = PALETTE.read_text(encoding="utf-8")
    failed = False
    for symbol, papers in CHECKS:
        fg = read(text, symbol)
        for paper in papers:
            bg = read(text, paper)
            for i, name in enumerate(("어두움", "밝음")):
                r = ratio(fg[i], bg[i])
                ok = r >= 4.5
                failed |= not ok
                hexed = "#%02X%02X%02X" % tuple(round(c * 255) for c in fg[i])
                print(f"{symbol[:-7]} · {NAMES[paper]} · {name}: {hexed} 대비 {r:.1f}:1 {'OK' if ok else '— 4.5 에 못 미친다'}")
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
