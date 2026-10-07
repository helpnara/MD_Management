#!/usr/bin/env python3
"""App Store Connect 칸의 **글자 수를 센다.**

`CLAUDE.md` §6 — *글자 수는 세어 보고 적는다. 손으로 세지 않는다* (152 · 155 에서
세 번 틀렸다). 그런데 **센 숫자를 문서에 적어 두면 그것도 갈린다** — 2026-09-24 에
개념 문서의 *설명 938자* 가 실제와 12자 어긋나 있었다. 글을 고친 곳은 하나인데
**세어 적어 둔 곳이 둘**이었다.

그래서 숫자는 어디에도 안 적고 **여기서 센다.** 읽는 곳은 `docs/12-submission.md` §1
하나다 — 붙여넣을 값이 사는 자리.
"""
import re
import sys
from pathlib import Path

SOURCE = Path("docs/12-submission.md")
# 심사 답변 (2.1 Information Needed) — Notes 칸에도 붙이는 글. 한도는 4000 으로 알고 있다
# (여기서 애플 문서를 못 연다 — 칸에 적힌 숫자가 최종이다).
REPLY = Path("docs/13-review-reply.md")
REPLY_LIMIT = 4000

# 칸 이름 → 한도. App Store Connect 의 칸에 적힌 숫자가 최종이다.
LIMITS = {
    "이름": 30,
    "부제": 30,
    "프로모션 텍스트": 170,
    "키워드": 100,
    "설명": 4000,
    # 업데이트 판마다 새로 적는 칸 (12-submission §6). 판이 바뀌면 글만 갈아 끼운다.
    "이 버전의 새로운 기능": 4000,
    # 영어 칸 (219 · §1-영어). 한도는 한국어 칸과 같다 — 칸이 같고 언어만 다르다.
    "Name": 30,
    "Subtitle": 30,
    "Promotional Text": 170,
    "Keywords": 100,
    "Description": 4000,
    "What’s New in This Version": 4000,
}


def fields(text):
    """`### 칸 이름` 다음에 처음 나오는 코드 울타리 안의 글."""
    found = {}
    for name in LIMITS:
        after = re.split(r"^### " + re.escape(name) + r"\s*$", text, flags=re.M)
        if len(after) < 2:
            continue
        block = re.search(r"```\n(.*?)\n```", after[1], re.S)
        if block:
            found[name] = block.group(1).strip()
    return found


def main():
    if not SOURCE.exists():
        print(f"{SOURCE} 가 없습니다 — 저장소 뿌리에서 돌리세요")
        return 2
    found = fields(SOURCE.read_text(encoding="utf-8"))
    missing = [name for name in LIMITS if name not in found]
    bad = []
    width = max(len(name) for name in LIMITS)
    for name, limit in LIMITS.items():
        if name not in found:
            continue
        length = len(found[name])
        mark = "OK" if length <= limit else "넘침"
        if length > limit:
            bad.append(name)
        print(f"{name:<{width}}  {length:>5} / {limit:<5} {mark}")
    for name in missing:
        print(f"{name:<{width}}  {'—':>5}   못 찾음")
    if REPLY.exists():
        block = re.search(r"```\n(Hello App Review.*?)\n```", REPLY.read_text(encoding="utf-8"), re.S)
        if block:
            length = len(block.group(1).strip())
            mark = "OK" if length <= REPLY_LIMIT else "넘침"
            if length > REPLY_LIMIT:
                bad.append("심사 답변")
            print(f"{'심사 답변':<{width}}  {length:>5} / {REPLY_LIMIT:<5} {mark}")
    if missing or bad:
        print()
        if missing:
            print("못 찾은 칸: " + " · ".join(missing))
        if bad:
            print("한도를 넘은 칸: " + " · ".join(bad))
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
