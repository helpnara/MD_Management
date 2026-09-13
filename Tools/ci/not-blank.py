#!/usr/bin/env python3
"""화면이 **정말 그려졌는지** 화소로 본다.

왜 있나
-------
`build.yml` 의 스크린샷 가드는 PNG **파일 크기**로 빈 화면을 가렸다. 크기는
대리 지표라서 두 번 틀렸다:

  빌드 4  아이패드 빈 읽기 화면이 119,762바이트로 문턱(50,000)을 넘어갔다 — **놓쳤다**
  빌드 7  아이패드 큰 글씨가 239,561바이트로 문턱(250,000)에 걸렸다 — **헛짚었다**
  빌드 7  아이폰 편집기가 **빈 채로** 114,161바이트를 내고 문턱(100,000)을 넘어갔다 — **놓쳤다**

셋 다 같은 원인이다. 크기는 "글이 있나" 가 아니라 "화소가 얼마나 복잡한가" 를
잰다. 그래서 여기서는 **글이 있는가**를 직접 본다 — 바탕색과 다른 화소가
내용 칸에 얼마나 있는지.

화면마다 **어디를 봐야 하는지**가 다르다. 아이폰은 내비게이션 바 아래가 본문이고,
아이패드는 오른쪽 칸이 본문이다 (왼쪽 둘은 사이드바와 목록이라 편집기가 비어도
글자가 있다). 그래서 볼 곳을 인자로 받는다:

  python3 Tools/ci/not-blank.py 파일:왼쪽,위,오른쪽,아래   (0~1 비율)
  python3 Tools/ci/not-blank.py screenshots/02-note.png:0,0.12,1,0.93
"""

from __future__ import annotations

import sys

try:
    from PIL import Image
except ImportError:  # pragma: no cover
    print("::warning::pillow 가 없습니다 — 화소 검사를 건너뜁니다")
    sys.exit(0)

# 안 적었을 때 볼 곳. 위는 상태 바 · 내비게이션 바, 아래는 상태 띠(둘러보기
# 배너)가 늘 뭔가를 그리므로 빼고 본다 — 그대로 두면 빈 화면도 통과한다.
DEFAULT_REGION = (0.0, 0.12, 1.0, 0.93)

# 바탕과 이만큼 다르면 글자 · 그림으로 본다 (0~255).
INK_DELTA = 12
# 내용 칸의 이만큼은 글이어야 한다.
MIN_INK = 0.005


def parse(argument: str) -> tuple[str, tuple[float, float, float, float]]:
    """`파일:왼쪽,위,오른쪽,아래`. 비율을 안 적으면 기본 칸을 본다."""
    if ":" not in argument:
        return argument, DEFAULT_REGION
    path, _, raw = argument.rpartition(":")
    parts = [float(value) for value in raw.split(",")]
    if len(parts) != 4:
        raise SystemExit(f"볼 곳은 네 값이어야 합니다: {argument}")
    return path, (parts[0], parts[1], parts[2], parts[3])


def ink_ratio(path: str, region: tuple[float, float, float, float]) -> float:
    image = Image.open(path).convert("L")
    width, height = image.size
    left, top, right, bottom = region
    band = image.crop((int(width * left), int(height * top),
                       int(width * right), int(height * bottom)))

    # 줄여서 본다 — 빠르고, 글자는 줄여도 바탕과 다른 회색으로 남는다.
    if band.width > 300:
        band = band.resize((300, max(1, band.height * 300 // band.width)), Image.BOX)

    histogram = band.histogram()
    background = histogram.index(max(histogram))
    total = band.width * band.height
    ink = sum(count for value, count in enumerate(histogram)
              if abs(value - background) > INK_DELTA)
    return ink / total if total else 0.0


def main(paths: list[str]) -> int:
    failed = []
    for argument in paths:
        path, region = parse(argument)
        try:
            ratio = ink_ratio(path, region)
        except FileNotFoundError:
            print(f"::error::{path} 가 없습니다")
            failed.append(path)
            continue
        mark = "OK " if ratio >= MIN_INK else "빈 "
        print(f"{mark} {path} — 내용 칸의 {ratio * 100:.2f}% 가 글입니다")
        if ratio < MIN_INK:
            print(f"::error::{path} — 내용 칸이 비어 있습니다 "
                  f"({ratio * 100:.2f}% < {MIN_INK * 100:.2f}%). "
                  "화면은 떴는데 **안이 비었습니다.**")
            failed.append(path)
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
