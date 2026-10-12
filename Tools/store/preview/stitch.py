#!/usr/bin/env python3
"""**시험이 찍은 화면들을 30초 안의 앱 미리보기로** (`store-preview.yml`).

`StorePreviewUITests.swift` 가 장면마다 화면을 찍어 `PV_<차례>_<100분의 1초>_<cut|fade>` 이름으로 남긴다.
흐름이 결과 묶음(xcresult)에서 그림을 꺼내면(`xcresulttool export attachments` — `manifest.json` 과 그림들) 이 스크립트가:

- 차례대로 늘어놓고, 이름에 적힌 초만큼 보여 준다.
- `fade` 장면은 첫 FADE 초 동안 앞 장면에서 조금씩 바뀐다 (화면이 바뀌는 자리). `cut` 은 바로 바꾼다 (글자를 치는 자리).
- 그림은 파이썬(Pillow)이 한 장씩 만들어 영상 도구에 흘려 넣는다 — 영상 도구의 판과 상관없이 같은 결과.
- 886 × 1920 (아이폰 6.1"/6.5"/6.9" 칸의 미리보기 크기) · 30fps · H.264 · BT.709 · 빈 소리 칸. 30초를 넘으면 같은 비율로 줄인다.

처음에는 시뮬레이터 녹화를 잘라 썼다 (`cut.py`, 첫~아홉 번째) — 녹화가 읽기 화면을 놓쳐 그만뒀다 (시험 파일 머리말).

    python3 stitch.py <ffmpeg> <attachments 폴더> <out.mp4>
"""
import json
import re
import subprocess
import sys
from pathlib import Path

from PIL import Image

LIMIT = 29.5        # 애플 한도 30초 — 끝의 반올림 몫
FADE = 0.3          # 화면이 바뀌는 자리의 겹침 (초)
WIDTH, HEIGHT = 886, 1920
FPS = 30
NAME = re.compile(r"PV_(\d{3})_(\d{4})_(cut|fade)")   # 길이는 100분의 1초 — 이름의 점은 확장자로 읽혀 쪼개졌다 (열한 번째)


def shots(folder: Path) -> list[tuple[int, float, bool, Path]]:
    """manifest.json 에서 PV_ 이름표가 붙은 그림들 — 차례대로."""
    found = {}

    def walk(node):
        if isinstance(node, dict):
            file = node.get("exportedFileName")
            label = " ".join(str(node.get(k, "")) for k in ("suggestedHumanReadableName", "name"))
            m = NAME.search(label) or (NAME.search(file) if file else None)
            if file and m:
                found[int(m.group(1))] = (int(m.group(1)), int(m.group(2)) / 100, m.group(3) == "fade", folder / file)
            for value in node.values():
                walk(value)
        elif isinstance(node, list):
            for value in node:
                walk(value)

    walk(json.loads((folder / "manifest.json").read_text(encoding="utf-8")))
    return [found[k] for k in sorted(found)]


def fit(path: Path) -> Image.Image:
    """화면 그림을 칸 폭에 맞춰 줄이고 위아래를 같게 잘라 886 × 1920 RGB 로."""
    image = Image.open(path).convert("RGB")
    height = round(image.height * WIDTH / image.width)
    image = image.resize((WIDTH, height), Image.LANCZOS)
    top = (height - HEIGHT) // 2
    if top < 0:
        canvas = Image.new("RGB", (WIDTH, HEIGHT), (255, 255, 255))
        canvas.paste(image, (0, -top))
        return canvas
    return image.crop((0, top, WIDTH, top + HEIGHT))


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

    # **그림을 파이썬이 한 장씩 만들어 영상 도구에 흘려 넣는다.** 영상 도구의 필터(xfade · concat)로 이으면 러너의 판에서
    # 21번째 장면(긴 이어 붙이기 뒤 첫 겹쳐 넘기기)에서 그림이 끊겼다 (열두 · 열세 번째 — 여기 판에서는 멀쩡했다).
    # 장면 k 는 frames[k] 장. fade 장면은 그 첫 fade_n 장 동안 앞 장면에서 조금씩 바뀐다 — 길이의 합은 그대로다.
    fade_n = round(FADE * FPS)
    frames = [max(1, round(d * scale * FPS)) for _, d, _, _ in items]
    length = sum(frames)
    seconds = length / FPS
    print(f"이어 붙인 길이 {length}장 = {seconds:.2f}초")

    Path(out).parent.mkdir(parents=True, exist_ok=True)
    enc = subprocess.Popen(
        [ffmpeg, "-hide_banner", "-loglevel", "error", "-y",
         "-f", "rawvideo", "-pix_fmt", "rgb24", "-s", f"{WIDTH}x{HEIGHT}", "-r", str(FPS), "-i", "-",
         "-f", "lavfi", "-i", "anullsrc=channel_layout=stereo:sample_rate=44100",
         "-map", "0:v", "-map", "1:a", "-t", f"{seconds:.3f}",
         "-vf", "scale=in_range=pc:out_color_matrix=bt709:out_range=tv,format=yuv420p,setsar=1",
         "-colorspace", "bt709", "-color_primaries", "bt709", "-color_trc", "bt709", "-color_range", "tv",
         "-c:v", "libx264", "-profile:v", "high", "-level", "4.0", "-preset", "slow", "-crf", "16",
         "-maxrate", "10M", "-bufsize", "20M", "-c:a", "aac", "-b:a", "128k", "-movflags", "+faststart", out],
        stdin=subprocess.PIPE, stderr=subprocess.PIPE)
    previous = None
    for k, (_, _, fade, path) in enumerate(items):
        image = fit(path)
        raw = image.tobytes()
        for i in range(frames[k]):
            if fade and previous is not None and i < fade_n:
                enc.stdin.write(Image.blend(previous, image, (i + 1) / (fade_n + 1)).tobytes())
            else:
                enc.stdin.write(raw)
        previous = image
    enc.stdin.close()
    err = enc.stderr.read().decode(errors="replace")
    if enc.wait() != 0:
        print(err[-3000:])
        return 1
    probe = subprocess.run([ffmpeg, "-hide_banner", "-i", out], capture_output=True, text=True).stderr
    print("\n".join(l for l in probe.splitlines() if "Duration" in l or "Stream" in l))
    h, m, sec = re.search(r"Duration: (\d+):(\d+):([0-9.]+)", probe).groups()
    if int(h) * 3600 + int(m) * 60 + float(sec) > 30:
        print("::error::결과 영상이 30초를 넘는다")
        return 1
    # 영상 줄기가 끝까지 있는가 — 소리 칸 때문에 길이는 맞아 보여도 그림이 11.5초에서 끊긴 적이 있다 (열두 번째).
    count = subprocess.run([ffmpeg, "-hide_banner", "-i", out, "-map", "0:v", "-f", "null", "-"],
                           capture_output=True, text=True).stderr
    got = int(re.findall(r"frame=\s*(\d+)", count)[-1])
    print(f"영상 장면 {got}장 (기대 {length}장)")
    if abs(got - length) > 2:
        print("::error::영상 줄기가 중간에 끊겼다")
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
