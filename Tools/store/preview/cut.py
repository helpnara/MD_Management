#!/usr/bin/env python3
"""**녹화를 30초 안의 앱 미리보기로** (`store-preview.yml`).

시뮬레이터 녹화는 **화면이 바뀔 때만** 장면을 남긴다 (가변 프레임). UI 시험은 동작마다 1~3초씩 멈춰 있어 그대로 두면
97초가 됐다 (두 번째 녹화). 그래서 장면마다 머무는 시간을 다시 매긴다:

- 시험이 `PREVIEW_HOLD <시각> <초>` 로 찍은 자리 — 그 장면을 **그 길이로** (링크 모음 · 여행 노트를 보여 주는 멈춤).
- 나머지 — 기계가 기다린 시간이라 **CAP 초까지만** (치는 글자 · 넘기는 움직임은 원래 빠르기 그대로).
- 합이 30초를 넘으면 CAP 을 줄이고, 그래도 넘으면 멈춤들을 같은 비율로 줄인다.

결과는 886 × 1920 · 30fps · H.264 · 빈 소리 칸 (애플 미리보기 규격 — 아이폰 6.1"/6.5"/6.9" 칸).

    python3 cut.py <ffmpeg> <raw.mov> <test.log> <record-start> <out.mp4>
"""
import re
import subprocess
import sys
from pathlib import Path

LIMIT = 29.5        # 애플 한도 30초 — 끝의 반올림 몫
CAP = 0.35          # 기계 기다림을 줄이는 한도 (초)
MIN = 1 / 30        # 멈춤 장면은 적어도 한 프레임


def main() -> int:
    ffmpeg, raw, log, rec_start_file, out = sys.argv[1:6]
    text = Path(log).read_text(encoding="utf-8", errors="replace")
    start = float(re.search(r"PREVIEW_MARK START ([0-9.]+)", text).group(1))
    end = float(re.search(r"PREVIEW_MARK END ([0-9.]+)", text).group(1))
    holds = [(float(t), float(s)) for t, s in re.findall(r"PREVIEW_HOLD ([0-9.]+) ([0-9.]+)", text)]
    # 녹화는 record-start 를 적기 3초 전에 켰다.
    rec0 = float(Path(rec_start_file).read_text().strip()) - 3
    seg0, seg1 = start - rec0, end - rec0
    print(f"시험 {end - start:.1f}초 · 녹화 안의 자리 {seg0:.2f} ~ {seg1:.2f} · 멈춤 {len(holds)}곳")

    frames = Path("raw-video/cut-frames")
    frames.mkdir(parents=True, exist_ok=True)
    for old in frames.glob("*.jpg"):
        old.unlink()
    # 장면 시각은 showinfo 가 원래 값으로 적는다. 그 뒤로는 시간 단위를 1/600 으로 맞추고 시각 대신 **차례 번호**(settb · setpts=N)를 넘긴다 — 세 번째 녹화에서
    # 15ms 간격 장면들이 그림 인코더의 거친 시간 단위로 반올림돼 같은 시각이 되어 멈췄다 (`Invalid pts (2) <= last (2)`).
    run = subprocess.run(
        [ffmpeg, "-hide_banner", "-ss", f"{seg0:.3f}", "-to", f"{seg1:.3f}", "-i", raw,
         "-fps_mode", "passthrough", "-enc_time_base", "1/600",
         "-vf", "showinfo,settb=1/600,setpts=N,scale=886:-2:flags=lanczos,crop=886:1920:0:(ih-1920)/2",
         "-q:v", "2", str(frames / "%05d.jpg")],
        capture_output=True, text=True)
    if run.returncode != 0:
        print(run.stderr[-3000:])
        return 1
    times = [float(t) for t in re.findall(r"pts_time:\s*([0-9.]+)", run.stderr)]
    files = sorted(frames.glob("*.jpg"))
    n = min(len(times), len(files))
    times, files = times[:n], files[:n]
    if n < 2:
        print("::error::장면이 너무 적다")
        return 1
    print(f"장면 {n}개")

    raw_dur = [times[i + 1] - times[i] for i in range(n - 1)] + [max(MIN, (seg1 - seg0) - times[-1])]
    hold_of = [0.0] * n
    for t, secs in holds:
        rel = t - start
        i = max(k for k in range(n) if times[k] <= rel) if rel >= times[0] else 0
        hold_of[i] += secs

    def plan(cap: float, hold_scale: float) -> list[float]:
        # 움직이는 장면(초당 60장)은 원래 길이 그대로 — 1/30초로 늘리면 영상이 두 배가 됐다 (여기서 시험). fps=30 이 알아서 고른다.
        return [max(MIN, h * hold_scale) if h else max(0.001, min(d, cap)) for d, h in zip(raw_dur, hold_of)]

    cap, scale = CAP, 1.0
    durs = plan(cap, scale)
    while sum(durs) > LIMIT and cap > 0.08:
        cap -= 0.03
        durs = plan(cap, scale)
    while sum(durs) > LIMIT and scale > 0.4:
        scale -= 0.05
        durs = plan(cap, scale)
    print(f"길이 {sum(durs):.2f}초 (기다림 한도 {cap:.2f}초 · 멈춤 비율 {scale:.2f})")
    if sum(durs) > 30:
        print("::error::30초 안에 못 넣었다")
        return 1

    listing = Path("raw-video/cut-list.txt")
    lines = []
    for f, d in zip(files, durs):
        lines.append(f"file '{f.resolve()}'\nduration {d:.4f}")
    lines.append(f"file '{files[-1].resolve()}'")
    listing.write_text("\n".join(lines) + "\n", encoding="utf-8")

    Path(out).parent.mkdir(parents=True, exist_ok=True)
    run = subprocess.run(
        [ffmpeg, "-hide_banner", "-loglevel", "error", "-y",
         "-f", "concat", "-safe", "0", "-i", str(listing),
         "-f", "lavfi", "-t", "40", "-i", "anullsrc=channel_layout=stereo:sample_rate=44100",
         "-vf", "fps=30,format=yuv420p,setsar=1", "-map", "0:v", "-map", "1:a", "-shortest",
         "-r", "30", "-fps_mode", "cfr", "-c:v", "libx264", "-profile:v", "high", "-level", "4.0",
         "-preset", "slow", "-crf", "16", "-maxrate", "10M", "-bufsize", "20M",
         "-c:a", "aac", "-b:a", "128k", "-movflags", "+faststart", out],
        capture_output=True, text=True)
    if run.returncode != 0:
        print(run.stderr[-3000:])
        return 1
    probe = subprocess.run([ffmpeg, "-hide_banner", "-i", out], capture_output=True, text=True).stderr
    print("\n".join(l for l in probe.splitlines() if "Duration" in l or "Stream" in l))
    return 0


if __name__ == "__main__":
    sys.exit(main())
