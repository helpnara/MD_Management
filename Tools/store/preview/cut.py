#!/usr/bin/env python3
"""**녹화를 30초 안의 앱 미리보기로** (`store-preview.yml`).

시뮬레이터 녹화는 **화면이 바뀔 때만** 장면을 남긴다 (가변 프레임). UI 시험은 동작마다 멈추고 러너에서는 글자 하나에
수백 ms 가 걸려 그대로 두면 97초 · 170초가 됐다 (두 · 네 번째 녹화). 그래서 녹화의 시간을 **구간마다 다르게** 다시 편다:

- `PREVIEW_HOLD <시각> <초>` 부터 그 초 동안 — **그 길이 그대로** (링크 모음 · 여행 노트를 보여 주는 멈춤).
- `PREVIEW_TYPE <시작> <끝>` — 글자 치는 구간. 남는 시간에 맞춰 **같은 비율로 빨리 감는다** (느려지게는 안 한다).
- 나머지 — 기계가 기다린 시간이라 장면마다 **CAP 초까지만** (넘기는 움직임은 원래 빠르기 그대로).
- 글자 구간에 줄 시간이 TYPE_MIN 보다 적으면 CAP 을 줄이고, 그래도 모자라면 멈춤들을 같은 비율로 줄인다.

장면 하나가 여러 구간에 걸치면 구간마다 따로 펴서 더한다.

결과는 886 × 1920 · 30fps · H.264 · 빈 소리 칸 (애플 미리보기 규격 — 아이폰 6.1"/6.5"/6.9" 칸).

    python3 cut.py <ffmpeg> <raw.mov> <test.log> <record-start> <out.mp4>
"""
import re
import subprocess
import sys
from pathlib import Path

LIMIT = 29.5        # 애플 한도 30초 — 끝의 반올림 몫
CAP = 0.35          # 기계 기다림을 줄이는 한도 (초 · 장면마다)
TYPE_MIN = 6.0      # 글자 구간 전체에 적어도 이만큼 (초) — 더 빠르면 무엇을 쳤는지 못 읽는다


def main() -> int:
    ffmpeg, raw, log, rec_start_file, out = sys.argv[1:6]
    text = Path(log).read_text(encoding="utf-8", errors="replace")
    start = float(re.search(r"PREVIEW_MARK START ([0-9.]+)", text).group(1))
    end = float(re.search(r"PREVIEW_MARK END ([0-9.]+)", text).group(1))
    # 시각은 모두 START 기준 초로 — 잘라 낸 영상의 0초가 START 다.
    holds = [(float(t) - start, float(t) - start + float(s))
             for t, s in re.findall(r"PREVIEW_HOLD ([0-9.]+) ([0-9.]+)", text)]
    typing = [(float(a) - start, float(b) - start)
              for a, b in re.findall(r"PREVIEW_TYPE ([0-9.]+) ([0-9.]+)", text)]
    # record-start = 녹화 도구가 *Recording started* 를 찍은 때 = 영상의 0초 (워크플로가 잰다).
    rec0 = float(Path(rec_start_file).read_text().strip())
    seg0, seg1 = start - rec0, end - rec0
    print(f"시험 {end - start:.1f}초 · 녹화 안의 자리 {seg0:.2f} ~ {seg1:.2f} · 멈춤 {len(holds)}곳 · 글자 {len(typing)}곳")

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
    times = [float(t) for t in re.findall(r"pts_time:\s*(-?[0-9.]+)", run.stderr)]
    files = sorted(frames.glob("*.jpg"))
    n = min(len(times), len(files))
    times, files = times[:n], files[:n]
    if n < 2:
        print("::error::장면이 너무 적다")
        return 1
    print(f"장면 {n}개")

    # 장면 i 는 times[i] ~ times[i+1] 동안 보인다 (마지막은 END 까지). 그 동안을 멈춤 · 글자 · 나머지로 나눠 잰다.
    spans = list(zip(times, times[1:] + [max(times[-1] + 1 / 30, seg1 - seg0)]))
    hold_s = [overlap(a, b, holds) for a, b in spans]
    type_s = [overlap(a, b, typing) for a, b in spans]
    rest_s = [max(0.0, (b - a) - h - t) for (a, b), h, t in zip(spans, hold_s, type_s)]
    typed = sum(type_s)

    def plan(cap: float, hold_scale: float) -> tuple[list[float], float]:
        fixed = sum(h * hold_scale + min(r, cap) for h, r in zip(hold_s, rest_s))
        speed = min(1.0, (LIMIT - fixed) / typed) if typed else 1.0
        durs = [h * hold_scale + t * speed + min(r, cap) for h, t, r in zip(hold_s, type_s, rest_s)]
        return durs, speed

    cap, scale = CAP, 1.0
    durs, speed = plan(cap, scale)
    while typed and speed * typed < TYPE_MIN and cap > 0.08:
        cap -= 0.03
        durs, speed = plan(cap, scale)
    while typed and speed * typed < TYPE_MIN and scale > 0.6:
        scale -= 0.05
        durs, speed = plan(cap, scale)
    durs = [max(0.001, d) for d in durs]
    print(f"멈춤 {sum(hold_s):.1f}초 → {sum(hold_s) * scale:.1f}초 · 글자 {typed:.1f}초 → {typed * speed:.1f}초 ({1 / speed if speed else 0:.1f}배 빠르게) · "
          f"나머지 {sum(rest_s):.1f}초 → {sum(min(r, cap) for r in rest_s):.1f}초 (한도 {cap:.2f})")
    print(f"길이 {sum(durs):.2f}초")
    if sum(durs) > 30 or speed <= 0:
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
         # 그림(JPEG)은 전 범위로 뽑힌다 — 영상의 제한 범위로 되돌린다. 그냥 두면 `yuvj420p(pc)` 로 남았다 (다섯 번째 녹화).
         # 뽑을 때 색 행렬은 바뀌지 않아(BT.709 그대로) 행렬은 둘 다 BT.709 — 여기서 파랑 · 회색을 재어 원본과 같은 값인 조합이다.
         "-vf", "fps=30,scale=in_range=pc:in_color_matrix=bt709:out_range=tv:out_color_matrix=bt709,format=yuv420p,setsar=1",
         "-colorspace", "bt709", "-color_primaries", "bt709", "-color_trc", "bt709", "-color_range", "tv", "-map", "0:v", "-map", "1:a", "-shortest",
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


def overlap(a: float, b: float, windows: list[tuple[float, float]]) -> float:
    """a ~ b 가 구간들과 겹치는 길이 (구간끼리는 안 겹친다 — 시험이 차례로 찍는다)."""
    return sum(max(0.0, min(b, w1) - max(a, w0)) for w0, w1 in windows)


if __name__ == "__main__":
    sys.exit(main())
