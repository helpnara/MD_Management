#!/usr/bin/env python3
"""**녹화를 30초 안의 앱 미리보기로** (`store-preview.yml`).

시뮬레이터 녹화는 **화면이 바뀔 때만** 장면을 남긴다 (가변 프레임). UI 시험은 동작마다 멈추고 러너에서는 글자 하나에
수백 ms 가 걸려 그대로 두면 97초 · 170초가 됐다 (두 · 네 번째 녹화). 그래서 녹화의 시간을 **구간마다 다르게** 다시 편다:

- `PREVIEW_HOLD <시각> <초>` 부터 그 초 동안 — **그 길이 그대로** (링크 모음 · 여행 노트를 보여 주는 멈춤).
- `PREVIEW_TYPE <시작> <끝>` — 글자 치는 구간. 남는 시간에 맞춰 **같은 비율로 빨리 감는다** (적어도 TYPE_MIN 초 · 느려지게는 안 한다).
- 나머지 — 기계가 기다린 시간. 장면마다 **CAP 초까지** 자르고, 그래도 남는 몫보다 길면 **같은 비율로 빨리 감는다**.
- 나머지를 REST_MIN 배보다 빨리 감아야 하면 멈춤들을 같은 비율로 줄인다 (0.7배까지).

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
LIGHT, DARK = 170, 110  # 밝은 화면 · 어두운 화면의 평균 밝기 (0~255) — 시계 맞춤 장면을 가른다
SYNC_LAG = 0.15     # 시험이 시각을 찍고 화면이 실제로 바뀌기까지 (초 · 어림)
REST_MIN = 0.3      # 나머지를 이보다 빨리 감아야 하면 멈춤들을 줄인다 (0.7배까지)


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
    # 영상의 0초가 시험 시계로 언제인가. 녹화 도구가 *Recording started* 를 찍은 때(워크플로가 잰다)로는 4~5초 어긋났다
    # (일곱 번째 녹화) — 그래서 시험이 화면을 어둡게 바꾼 장면(PREVIEW_SYNC)을 녹화에서 찾아 맞춘다. 못 찾으면 그 시각으로.
    rec0 = float(Path(rec_start_file).read_text().strip())
    sync = re.search(r"PREVIEW_SYNC ([0-9.]+)", text)
    if sync:
        seen = find_dark(ffmpeg, raw, float(sync.group(1)) - rec0 + 10)
        if seen is None:
            print("::warning::어두워지는 장면을 못 찾았다 — Recording started 시각으로 자른다")
        else:
            fixed = float(sync.group(1)) + SYNC_LAG - seen
            print(f"시계 맞춤: 어두워진 장면 {seen:.2f}초 → 영상 0초를 {fixed - rec0:+.2f}초 옮김")
            rec0 = fixed
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

    # 몫을 나눈다 — 러너 빠르기가 매번 세 배씩 달라(시험 63초 · 180초, 다섯 · 여섯 번째 녹화) 한도 하나를 줄여 가는 것으로는 못 맞췄다.
    capped = [min(r, CAP) for r in rest_s]
    rest0 = sum(capped)
    for scale in (1.0, 0.95, 0.9, 0.85, 0.8, 0.75, 0.7):
        held = sum(hold_s) * scale
        typed_out = min(typed, max(TYPE_MIN, LIMIT - held - rest0))
        rest_out = LIMIT - held - typed_out
        rest_speed = min(1.0, rest_out / rest0) if rest0 else 1.0
        if rest_speed >= REST_MIN:
            break
    if rest_out <= 0.5:
        print("::error::30초 안에 못 넣었다 — 멈춤 · 글자만으로 다 찼다")
        return 1
    type_speed = typed_out / typed if typed else 1.0
    durs = [max(0.001, h * scale + t * type_speed + c * rest_speed) for h, t, c in zip(hold_s, type_s, capped)]
    print(f"멈춤 {sum(hold_s):.1f}초 → {held:.1f}초 · 글자 {typed:.1f}초 → {typed_out:.1f}초 · "
          f"나머지 {sum(rest_s):.1f}초 → (장면마다 {CAP}초까지) {rest0:.1f}초 → {rest0 * rest_speed:.1f}초")
    print(f"길이 {sum(durs):.2f}초")
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


def find_dark(ffmpeg: str, raw: str, until: float) -> float | None:
    """녹화의 처음부터 until 초까지에서 **밝던 화면이 어두워진 첫 장면**의 시각."""
    run = subprocess.run(
        [ffmpeg, "-hide_banner", "-t", f"{max(until, 5):.3f}", "-i", raw,
         "-vf", "scale=120:-2,showinfo", "-f", "null", "-"],
        capture_output=True, text=True)
    last_light = None
    for t, y in re.findall(r"pts_time:\s*(-?[0-9.]+).*?mean:\[(\d+)", run.stderr):
        t, y = float(t), int(y)
        if y >= LIGHT:
            last_light = t
        elif y <= DARK and last_light is not None and t - last_light < 1.5:
            return t
    return None


def overlap(a: float, b: float, windows: list[tuple[float, float]]) -> float:
    """a ~ b 가 구간들과 겹치는 길이 (구간끼리는 안 겹친다 — 시험이 차례로 찍는다)."""
    return sum(max(0.0, min(b, w1) - max(a, w0)) for w0, w1 in windows)


if __name__ == "__main__":
    sys.exit(main())
