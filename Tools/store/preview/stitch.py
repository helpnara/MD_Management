#!/usr/bin/env python3
"""**시험이 찍은 화면들을 30초 안의 앱 미리보기로** (`store-preview.yml`).

`StorePreviewUITests.swift` 가 장면마다 화면을 찍어 `PV_<차례>_<초>_<cut|fade>` 이름으로 남긴다.
흐름이 결과 묶음(xcresult)에서 그림을 꺼내면(`xcresulttool export attachments` — `manifest.json` 과 그림들) 이 스크립트가:

- 차례대로 늘어놓고, 이름에 적힌 초만큼 보여 준다.
- `fade` 장면은 앞 장면과 FADE 초 겹쳐 넘긴다 (화면이 바뀌는 자리). `cut` 은 바로 바꾼다 (글자를 치는 자리).
- 886 × 1920 (아이폰 6.1"/6.5"/6.9" 칸의 미리보기 크기) · 30fps · H.264 · BT.709 · 빈 소리 칸. 30초를 넘으면 같은 비율로 줄인다.

처음에는 시뮬레이터 녹화를 잘라 썼다 (`cut.py`, 첫~아홉 번째) — 녹화가 읽기 화면을 놓쳐 그만뒀다 (시험 파일 머리말).

    python3 stitch.py <ffmpeg> <attachments 폴더> <out.mp4>
"""
import json
import re
import subprocess
import sys
from pathlib import Path

LIMIT = 29.5        # 애플 한도 30초 — 끝의 반올림 몫
FADE = 0.3          # 화면이 바뀌는 자리의 겹침 (초)
WIDTH, HEIGHT = 886, 1920
NAME = re.compile(r"PV_(\d+)_([0-9.]+)_(cut|fade)")


def shots(folder: Path) -> list[tuple[int, float, bool, Path]]:
    """manifest.json 에서 PV_ 이름표가 붙은 그림들 — 차례대로."""
    found = {}

    def walk(node):
        if isinstance(node, dict):
            file = node.get("exportedFileName")
            label = " ".join(str(node.get(k, "")) for k in ("suggestedHumanReadableName", "name"))
            m = NAME.search(label) or (NAME.search(file) if file else None)
            if file and m:
                found[int(m.group(1))] = (int(m.group(1)), float(m.group(2)), m.group(3) == "fade", folder / file)
            for value in node.values():
                walk(value)
        elif isinstance(node, list):
            for value in node:
                walk(value)

    walk(json.loads((folder / "manifest.json").read_text(encoding="utf-8")))
    return [found[k] for k in sorted(found)]


def main() -> int:
    ffmpeg, folder, out = sys.argv[1], Path(sys.argv[2]), sys.argv[3]
    items = shots(folder)
    if len(items) < 2:
        print("::error::찍은 화면이 없다 — manifest.json 을 본다")
        print((folder / "manifest.json").read_text(encoding="utf-8")[:3000])
        return 1
    missing = sorted(set(range(1, items[-1][0] + 1)) - {i for i, *_ in items})
    if missing:
        print(f"::warning::빠진 차례가 있다: {missing}")
    total = sum(d for _, d, _, _ in items)
    scale = min(1.0, LIMIT / total)
    print(f"장면 {len(items)}장 · {total:.2f}초" + (f" → {total * scale:.2f}초 ({scale:.2f}배)" if scale < 1 else ""))

    # 장면 k 는 d_k 초 — 다음 장면이 fade 면 FADE 만큼 더 길게 둬서 겹치는 동안에도 제 길이를 보인다.
    inputs, chains = [], []
    durs = [d * scale for _, d, _, _ in items]
    for k, (_, _, _, path) in enumerate(items):
        nxt_fade = k + 1 < len(items) and items[k + 1][2]
        length = durs[k] + (FADE if nxt_fade else 0)
        inputs += ["-loop", "1", "-framerate", "30", "-t", f"{length:.3f}", "-i", str(path)]
        chains.append(
            f"[{k}:v]scale={WIDTH}:-2:flags=lanczos,crop={WIDTH}:{HEIGHT}:0:(ih-{HEIGHT})/2,"
            f"fps=30,format=rgb24,setsar=1,settb=1/30[s{k}]")
    acc, length = "s0", durs[0] + (FADE if len(items) > 1 and items[1][2] else 0)
    for k in range(1, len(items)):
        own = durs[k] + (FADE if k + 1 < len(items) and items[k + 1][2] else 0)
        if items[k][2]:
            chains.append(f"[{acc}][s{k}]xfade=transition=fade:duration={FADE}:offset={length - FADE:.3f},settb=1/30[a{k}]")
            length += own - FADE
        else:
            chains.append(f"[{acc}][s{k}]concat=n=2:v=1:a=0,settb=1/30[a{k}]")
            length += own
        acc = f"a{k}"
    chains.append(f"[{acc}]scale=out_color_matrix=bt709:out_range=tv,format=yuv420p[v]")
    print(f"이어 붙인 길이 {length:.2f}초")

    script = Path(out).with_suffix(".filter.txt")
    script.parent.mkdir(parents=True, exist_ok=True)
    script.write_text(";\n".join(chains), encoding="utf-8")
    run = subprocess.run(
        [ffmpeg, "-hide_banner", "-loglevel", "error", "-y", *inputs,
         "-f", "lavfi", "-i", "anullsrc=channel_layout=stereo:sample_rate=44100",
         "-filter_complex_script", str(script), "-map", "[v]", "-map", f"{len(items)}:a",
         "-t", f"{length:.3f}", "-r", "30",
         "-colorspace", "bt709", "-color_primaries", "bt709", "-color_trc", "bt709", "-color_range", "tv",
         "-c:v", "libx264", "-profile:v", "high", "-level", "4.0", "-preset", "slow", "-crf", "16",
         "-maxrate", "10M", "-bufsize", "20M", "-c:a", "aac", "-b:a", "128k", "-movflags", "+faststart", out],
        capture_output=True, text=True)
    script.unlink()
    if run.returncode != 0:
        print(run.stderr[-3000:])
        return 1
    probe = subprocess.run([ffmpeg, "-hide_banner", "-i", out], capture_output=True, text=True).stderr
    print("\n".join(l for l in probe.splitlines() if "Duration" in l or "Stream" in l))
    h, m, sec = re.search(r"Duration: (\d+):(\d+):([0-9.]+)", probe).groups()
    if int(h) * 3600 + int(m) * 60 + float(sec) > 30:
        print("::error::결과 영상이 30초를 넘는다")
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
