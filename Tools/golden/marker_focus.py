#!/usr/bin/env python3
"""162 — **원문이 드러난 줄과 기억이 갈리지 않는가**를 여기서 먼저 따진다.

`MarkerFocus` 는 순수 함수라 CI 의 `swift test` 가 심판이 된다. 다만 **리눅스 세션에서는
Swift 를 못 돌린다** (`CLAUDE.md` §2). 그래서 같은 규칙을 파이썬으로 한 번 더 적고
**경우의 수를 다 돌려** 규칙 자체가 옳은지 여기서 본다.

화면을 **집합**으로 흉내 낸다 — 드러난 줄이 둘 이상일 수 있어야 162 를 표현할 수 있다.
옛 규칙을 같이 넣어 둔 까닭은 **이 시험이 무는지 보이기 위해서**다. 무는 것을 못 본
시험은 통과해도 아무 말을 안 한 것이다.

    python3 Tools/golden/marker_focus.py
"""
import itertools
import sys

# 문단 둘이면 충분하다 — 셋째는 둘째와 같은 말을 한다.
A, B = "A", "B"
CURSORS = [None, A, B]

# 한 걸음에 일어날 수 있는 일.
#   ("plan", 커서, 칠할 수 있나)  — 선택이 바뀌었다 · 초점이 오갔다 · 조합이 끝났다
#   ("whole", 커서)               — 글을 통째로 다시 칠했다 (노트를 열었다)
#   ("nudge",)                    — 다음에는 같은 자리라도 반드시 다시 칠한다
STEPS = (
    [("plan", c, p) for c in CURSORS for p in (True, False)]
    + [("whole", c) for c in CURSORS]
    + [("nudge",)]
)


def plan_new(state, cursor, can_paint):
    dressed, owes = state
    if not can_paint:
        return (None, None), (dressed, owes or dressed != cursor)
    if dressed == cursor and not owes:
        return (None, None), (dressed, False)
    hide = None if dressed == cursor else dressed
    return (hide, cursor), (cursor, False)


def plan_old(state, cursor, can_paint):
    """빌드 52 까지의 규칙 — 칠하지 못했는데 **기억을 지운다.**"""
    dressed, owes = state
    if cursor is None:                      # textViewDidEndEditing
        if can_paint:
            return (dressed, None), (None, False)
        return (None, None), (None, False)  # ← 못 지웠는데 기억만 지운다 (162)
    if not can_paint:
        return (None, None), (dressed, owes)
    if dressed == cursor:
        return (None, None), (dressed, owes)
    return (dressed, cursor), (cursor, False)


def run(rule, steps):
    """규칙대로 걸어 보며 **화면**과 **기억**을 따로 들고 간다."""
    state = (None, False)
    screen = set()
    for step in steps:
        if step[0] == "plan":
            (hide, show), state = rule(state, step[1], step[2])
            if hide is not None:
                screen.discard(hide)
            if show is not None:
                screen.add(show)
        elif step[0] == "whole":
            screen = {step[1]} if step[1] is not None else set()
            state = (step[1], False)
        else:
            state = (state[0], True)

        remembered = {state[0]} if state[0] is not None else set()
        if len(screen) > 1:
            return step, "원문이 드러난 줄이 둘 이상이다", screen, state
        if screen != remembered:
            return step, "화면과 기억이 갈렸다", screen, state
        if step[0] == "plan" and step[2] and state[0] != step[1]:
            return step, "칠할 수 있었는데 커서를 안 따라갔다", screen, state
    return None


def check(name, rule, depth):
    for steps in itertools.product(STEPS, repeat=depth):
        bad = run(rule, steps)
        if bad:
            return name, steps, bad
    return None


def main():
    depth = 4
    total = len(STEPS) ** depth
    print(f"한 걸음에 {len(STEPS)} 가지 · {depth} 걸음 = {total:,} 갈래")

    old = check("옛 규칙", plan_old, depth)
    if old is None:
        print("옛 규칙이 안 걸렸다 — **시험이 안 무는 것이다.** 규칙을 다시 본다.")
        return 1
    _, steps, (step, why, screen, state) = old
    print(f"\n옛 규칙 ✗ {why}")
    print(f"  걸음: {' → '.join(str(s) for s in steps)}")
    print(f"  걸린 자리: {step} · 화면 {sorted(screen)} · 기억 {state}")

    new = check("새 규칙", plan_new, depth)
    if new is not None:
        _, steps, (step, why, screen, state) = new
        print(f"\n새 규칙 ✗ {why}")
        print(f"  걸음: {' → '.join(str(s) for s in steps)}")
        print(f"  걸린 자리: {step} · 화면 {sorted(screen)} · 기억 {state}")
        return 1
    print(f"\n새 규칙 ✓ {total:,} 갈래를 다 걸어도 화면과 기억이 안 갈린다")
    return 0


if __name__ == "__main__":
    sys.exit(main())
