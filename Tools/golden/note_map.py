"""329 · 330 — **노트 지도.** Swift `NoteMap` 의 쌍둥이 (설계 `docs/92-note-map-design.md`).

2026-11-26 사용자 — *노트 맵을 만들어보는 것은 어떻게 생각해? … 최근 나의 관심사라던가 내가 해온 일을 정리하는데 도움이 될 것 같은데*.

## 노트 하나 → 낱말 꼴 (`terms`) — 색인에 쓸 때 한 번

1. NFC → 머리말을 뗀 본문(`split_front_matter`) → `\\n` 으로 줄을 가르고 줄 끝 `\\r` 하나를 뗀다.
2. 줄 역할(`context_roles` — Swift `BlockContext.roles`)이 `code` · `indentedCode` · `comment` 인 줄, 울타리 줄(`FENCE_RE`)은 뺀다.
3. 남은 줄은 미리보기(`preview` — Swift `PreviewLine.plain`)로 보이는 글만.
4. 덩이 자르기 — **한글 음절이 이어진 덩이 · 영문 숫자(ASCII)가 이어진 덩이**. 둘이 붙어 있으면 갈린다 (`iOS27에서` → `iOS27` · `에서`).
   영문 덩이 바로 뒤가 `://` 이거나 덩이가 `www`(대소문자 무관) 이고 바로 뒤가 `.` 이면 **다음 빈칸까지 건너뛴다** (주소).
5. 영문 덩이 — 숫자로 시작하면 버린다. 소문자로. 세 글자 미만(대문자 두 글자 약어 *AI · UX* 는 받는다) · `EN_STOP` 은 버린다. 꼴은 `""`.
   영문 덩이 바로 앞이나 뒤가 악센트 붙은 라틴 글자(U+00C0 ~ U+024F)면 버린다 (*café* → `caf` 를 막는다).
6. 한글 덩이 — 두 글자 미만은 버린다. 조사 표(`JOSA` — 긴 것부터, 같은 길이는 가나다순)에서 **떼고 남은 말이 두 글자 이상이
   되는 첫 조사** 하나를 뗀다 (*사과는* — `과는` 은 한 글자가 남아 건너뛰고 `는`). 없으면 (덩이, `""`).
   *전에는* → *전에* 같은 것은 `STOP` 이 거른다.
7. 노트 안에서 같은 (말, 꼴) 은 하나로. 차례는 (말, 꼴) 의 코드 포인트 순.

## 폴더 전체 → 키워드 — 지도를 열 때

- **줄기 꼴 모음** `stem_forms[말]` — 모든 노트의 (말, 꼴).
- **풀기** (말, 꼴) → (키워드, 꼴): 꼴이 **한 글자 조사**이고 `말+꼴` 이 다른 데서 **센 조사**(`STRONG`)를 받은 적이 있으면 `(말+꼴, "")` —
  *전문가 · 고양이 · 어린이* 처럼 조사 같은 글자로 끝나는 말을 지킨다. 아니면 그대로.
- **키워드 꼴 모음** `kw_forms[키워드]` — 푼 꼴.
- **받는 키워드** — 영문은 그대로. 한글은 두 글자 이상 · `STOP` 아님 · 동사 끝(`is_bad_stem`) 아님 ·
  **꼴 증거 둘 이상** — 맨꼴(`""`) 과 센 조사 꼴을 센다 (약한 조사 `도 · 만 · 나 · 들` … 은 떼기만 하고 증거가 아니다 — *만들어도* 같은 동사 꼴).
- 숨긴 말(`hidden`)은 뺀다. 노트의 키워드는 집합.

## 구절 (331)

- 낱말 꼴에 더해 **구절 후보** — 한 줄 안에서 빈칸 하나(U+0020)로만 떨어진 한글 덩이 둘, 앞 덩이는 조사가 없는 맨꼴.
  `(앞말 + " " + 뒷말의 줄기, 뒷말의 조사)` 로 담는다 (빈칸이 든 말 = 구절). 낱말 셈(꼴 증거 · 풀기)에는 안 든다.
- 받는 구절 — 뒷말을 낱말처럼 풀어 **받은 키워드**이고, 앞말은 `STOP` · 동사 줄기 · 숨긴 말이 아니면 된다
  (*주간 · 개인정보* 는 늘 맨꼴로 앞에만 서서 낱말로는 못 받는다). 앞말이 동사의 꾸밈꼴 · 연결꼴이면 못 선다 (`bad_front`). 둘이 다르고, **노트 셋 이상**에 나오고
  `구절 노트 수 × 10 ≥ 4 × min(앞말이 든 노트 수, 뒷말 노트 수)` (드문 말이 든 노트의 40% 이상에서 함께). 숨긴 구절이면 뺀다.
- 받은 구절은 노트의 키워드에 더해져 낱말과 똑같이 센다. 둘레(330)에서는 가운데와 낱말이 겹치는 것을 뺀다.

## 기간 · 순위 (329)

- 날은 1970-01-01 부터 센 날 수 (앱이 기기 달력으로 셈해 준다). `age = today - day`. 이 기간 `age < D` (앞날도 든다) · 앞 기간 `D <= age < 2D`.
- `N` = 노트 수(본문이 든 것) · `df[k]` = k 가 든 노트 수 (전체).
- 이 기간 노트가 10개 미만이면 한 번 나온 말도, 아니면 두 노트 이상에 나온 말만.
- 점수 = `cur × ln((N+1)/df)` 을 **백만 배 해 반올림한 정수**(`floor(x + 0.5)` — 파이썬 `round` 는 반에서 짝수로 가서 쓰지 않는다) — 수학으로 같은 값(2·ln4 · ln16)이 언어마다 끝자리가 달라 차례가 갈리지 않게.
  차례 (331 · 사용자 정함 — 기본 많이 쓴 순) — `count`: 노트 수 큰 것부터, 같으면 점수 큰 것, 같으면 코드 포인트 순 ·
  `score`: 점수 큰 것부터, 같으면 코드 포인트 순.
- 표시 — 앞 기간에 노트가 하나도 없으면 없음. 아니면 앞 기간 0 → `new` · `cur > prev` → `up` · 아니면 없음.

## 함께 나온 말 (330)

- 가운데 말이 든 **이 기간 노트**에서 다른 키워드를 센다 (`co`). 그 노트가 4개 미만이면 한 번 나온 말도, 아니면 둘 이상.
- 점수는 위와 같은 셈(`co` 로). 위 6개. 선 굵기 = `ceil(3·co / 가장 큰 co)` (1~3).
- 노트 목록 — 이 기간 · 그 말(과 둘째 말)이 든 노트, 날 늦은 것부터, 같으면 경로 순.

## 관계도 자리

둘레 n 개(0~6)를 12시부터 시계 방향으로 고르게 — i 번째 각 `2πi/n` (넷이면 `π/4` 를 더한다 — 3시 · 9시 자리가 가운데 칸에 붙지 않게), 자리 `(sin, -cos)` (화면 좌표 — y 가 아래로).
"""
from __future__ import annotations

import math
import re
import unicodedata

from preview_line import preview

FENCE_RE = re.compile(r"^ {0,3}(`{3,}|~{3,})")

# 센 조사 — 꼴 증거가 된다. 약한 조사 — 떼기만 한다 (동사 연결 꼴 *-어도 · -야만 · -거나* 와 겹친다).
STRONG = [
    "은", "는", "이", "가", "을", "를", "의", "에", "에서", "에게", "께서", "한테", "으로", "로",
    "으로서", "로서", "으로써", "로써", "와", "과", "이랑", "랑", "하고", "까지", "부터", "처럼", "보다", "만큼",
    "에는", "에도", "에서는", "에서도", "으로는", "로는", "으로도", "로도", "과는", "와는", "에게는", "에게서",
    "이라는", "라는", "이란",
]
WEAK = [
    "도", "만", "이나", "나", "들", "들이", "들은", "들을", "들의", "들에", "들도", "들과", "들로",
    "마저", "조차", "이라도", "라도",
]
JOSA = sorted(set(STRONG) | set(WEAK), key=lambda j: (-len(j), j))
STRONG_SET = set(STRONG)

STOP = {
    "그리고", "그러나", "하지만", "그래서", "그런데", "그러면", "또는", "이것", "그것", "저것", "여기", "거기", "저기",
    "이런", "그런", "저런", "이렇게", "그렇게", "오늘", "어제", "내일", "지금", "이번", "다음", "지난", "우리", "저희",
    "자신", "다시", "바로", "아직", "이미", "먼저", "모두", "함께", "같이", "정말", "너무", "아주", "매우", "가장",
    "계속", "항상", "위해", "대한", "대해", "통해", "때문", "경우", "정도", "이상", "이하", "하나", "어떤", "무엇",
    "누구", "어디", "언제", "이제", "그냥", "조금", "많이", "동안", "에서", "으로", "부터", "까지", "처럼", "보다",
    "개월", "아니", "이후", "이전", "전에", "후에", "여기서", "거기서", "따로", "안에", "밖에", "위에",
    "아래", "없이", "있으면", "없으면", "처음", "마지막", "보내", "하면", "되면", "다른", "같은", "없음", "있음",
}
EN_STOP = {
    "the", "and", "for", "with", "that", "this", "from", "you", "your", "are", "was", "were", "not", "but",
    "have", "has", "had", "will", "can", "all", "any", "our", "its", "into", "out", "about",
    "http", "https", "www", "com", "org", "net", "html", "div", "span",
}
# 동사 · 형용사 줄기 — 마지막 음절, 또는 `…다` 앞 음절.
BAD_LAST = set("하되있없했됐겠였었았")
BAD_BEFORE_DA = set("하되있없했됐였었았겠한된간온본준갔왔봤줬좋많같싶는")

SPACES = {0x09, 0x0A, 0x0B, 0x0C, 0x0D, 0x20, 0xA0, 0x1680, 0x2028, 0x2029, 0x202F, 0x205F, 0x3000} | set(range(0x2000, 0x200B))
NEIGHBOR_LIMIT = 6
# 구절 (331) — 노트 셋 이상 · 둘 중 드문 말이 든 노트의 40% 이상에서 함께.
PHRASE_MIN_NOTES = 3
# 구절의 앞말로 못 서는 꼴 — 동사의 꾸밈꼴(*삭제된 · 않은 · 지운*) · 연결꼴(*아니면 · 완료되면 · 하고*).
FRONT_BAD_LAST = set("은는던된운")
FRONT_VERB_LAST = set("한인")       # 앞부분이 따로 쓰이는 말이면 꾸밈꼴 (*고정한* ← *고정*) — *디자인 · 확인 · 권한* 은 남는다
FRONT_BAD_SUFFIXES = ["하면", "되면", "으면", "라면", "다면", "이면", "니면", "려면", "하고", "되고", "해서", "하며", "하게", "되게",
                      "하지", "되지", "해도"]
PHRASE_SHARE_TENTHS = 4
SCORE_SCALE = 1_000_000


def is_hangul(ch: str) -> bool:
    return "가" <= ch <= "힣"


def is_ascii_alnum(ch: str) -> bool:
    return ("0" <= ch <= "9") or ("a" <= ch <= "z") or ("A" <= ch <= "Z")


def is_bad_stem(word: str) -> bool:
    if word[-1] in BAD_LAST:
        return True
    return len(word) >= 2 and word[-1] == "다" and word[-2] in BAD_BEFORE_DA


def strip_josa(run: str) -> tuple[str, str]:
    for j in JOSA:
        if run.endswith(j) and len(run) - len(j) >= 2:
            return run[: -len(j)], j
    return run, ""


def is_accented_letter(ch: str) -> bool:
    """라틴 글자에 붙는 악센트 글자 (U+00C0 ~ U+024F · × ÷ 빼고) — *café* 의 `caf` 를 버리려고."""
    o = ord(ch)
    return 0xC0 <= o <= 0x24F and o not in (0xD7, 0xF7)


def scan(text: str) -> list[tuple[str, str]]:
    """보이는 글 한 줄 → (말, 꼴) 들 (거르기 전 — 5 · 6 단계까지). 구절 후보는 `(앞말 + " " + 뒷말, 뒷말의 조사)`."""
    out = []
    i, n = 0, len(text)
    bare_end = -1           # 바로 앞 한글 덩이가 조사 없는 맨꼴이면 그 끝 자리 (구절의 앞말)
    bare_word = ""
    while i < n:
        c = text[i]
        hangul = is_hangul(c)
        if not hangul and not is_ascii_alnum(c):
            i += 1
            continue
        j = i
        while j < n and (is_hangul(text[j]) if hangul else is_ascii_alnum(text[j])):
            j += 1
        run = text[i:j]
        if not hangul and (text[j:j + 3] == "://" or (run.lower() == "www" and text[j:j + 1] == ".")):
            while j < n and ord(text[j]) not in SPACES:
                j += 1
            i = j
            continue
        i = j
        start = j - len(run)
        if hangul:
            if len(run) < 2:
                bare_end = -1
                continue
            stem, form = strip_josa(run)
            out.append((stem, form))
            # 구절 (331) — 빈칸 하나(U+0020)로만 떨어진 앞의 맨꼴 덩이와 묶는다.
            if bare_end >= 0 and start == bare_end + 1 and text[bare_end] == " ":
                out.append((bare_word + " " + stem, form))
            if form:
                bare_end = -1
            else:
                bare_end, bare_word = j, stem
        else:
            bare_end = -1
            before = text[i - len(run) - 1] if i - len(run) - 1 >= 0 else ""
            after = text[i] if i < n else ""
            if "0" <= run[0] <= "9" or (before and is_accented_letter(before)) or (after and is_accented_letter(after)):
                continue
            word = run.lower()
            acronym = len(run) == 2 and all("A" <= c <= "Z" for c in run)
            if (len(word) < 3 and not acronym) or word in EN_STOP:
                continue
            out.append((word, ""))
    return out


def terms(text: str, roles_of, split_front_matter) -> list[list[str]]:
    """노트 하나의 낱말 꼴 — [[말, 꼴], …] (중복 없음 · 차례 고정)."""
    _, body = split_front_matter(unicodedata.normalize("NFC", text))
    lines = [line[:-1] if line.endswith("\r") else line for line in body.split("\n")]
    roles = roles_of(lines)
    found = set()
    for line, role in zip(lines, roles):
        if role in ("code", "indentedCode", "comment") or FENCE_RE.match(line):
            continue
        for term in scan(preview(line)):
            found.add(term)
    return [list(t) for t in sorted(found)]


def is_ascii_word(word: str) -> bool:
    return all(is_ascii_alnum(c) for c in word)


class Model:
    """폴더 전체 — rows: [{"path", "day", "terms": [[말, 꼴], …]}]."""

    def __init__(self, rows: list[dict], hidden: list[str] | None = None):
        hidden_set = set(hidden or [])
        word_terms = [[(s, f) for s, f in row["terms"] if " " not in s] for row in rows]
        phrase_terms = [[(s, f) for s, f in row["terms"] if " " in s] for row in rows]
        stem_forms: dict[str, set[str]] = {}
        for pairs in word_terms:
            for stem, form in pairs:
                stem_forms.setdefault(stem, set()).add(form)

        def resolve(stem: str, form: str) -> tuple[str, str]:
            # 한 글자 조사만 (*전문가 · 고양이*) — 두 글자 조사까지 풀면 *화면에서* 가 한 말이 된다 (331 시제품).
            if len(form) == 1:
                raw = stem + form
                if any(f in STRONG_SET for f in stem_forms.get(raw, ())):
                    return raw, ""
            return stem, form

        resolved = [[resolve(s, f) for s, f in pairs] for pairs in word_terms]
        kw_forms: dict[str, set[str]] = {}
        for pairs in resolved:
            for k, f in pairs:
                kw_forms.setdefault(k, set()).add(f)

        def accept(k: str) -> bool:
            if k in hidden_set:
                return False
            if is_ascii_word(k):
                return True
            if len(k) < 2 or k in STOP or is_bad_stem(k):
                return False
            return sum(1 for f in kw_forms[k] if f == "" or f in STRONG_SET) >= 2

        accepted = {k: accept(k) for k in kw_forms}
        words = [{k for k, _ in pairs if accepted[k]} for pairs in resolved]
        # 구절의 앞말은 낱말 키워드가 아니어도 된다 (*주간 · 개인정보* 는 늘 맨꼴로 앞에만 선다). 그 말이 든 노트 수.
        stem_df: dict[str, int] = {}
        for pairs in resolved:
            for k in {k for k, _ in pairs}:
                stem_df[k] = stem_df.get(k, 0) + 1
        word_df: dict[str, int] = {}
        for ks in words:
            for k in ks:
                word_df[k] = word_df.get(k, 0) + 1

        # 구절 (331) — 앞말 · 뒷말(풀어서)이 다 받은 키워드이고 서로 다를 때 후보. 노트 수 · 함께 나온 몫을 본다.
        def bad_front(word: str) -> bool:
            if word[-1] in FRONT_BAD_LAST:
                return True
            if word[-1] in FRONT_VERB_LAST and len(word) >= 3 and word[:-1] in stem_forms:
                return True
            return any(len(word) > len(x) and word.endswith(x) for x in FRONT_BAD_SUFFIXES)

        candidates = []
        for pairs in phrase_terms:
            found = set()
            for stem, form in pairs:
                first, second = stem.split(" ", 1)
                second = resolve(second, form)[0]
                if (first != second and accepted.get(second) and first not in hidden_set
                        and first not in STOP and not is_bad_stem(first) and not bad_front(first)):
                    found.add(first + " " + second)
            candidates.append(found)
        phrase_df: dict[str, int] = {}
        for found in candidates:
            for p in found:
                phrase_df[p] = phrase_df.get(p, 0) + 1

        def accept_phrase(p: str) -> bool:
            first, second = p.split(" ", 1)
            c = phrase_df[p]
            return (p not in hidden_set and c >= PHRASE_MIN_NOTES
                    and c * 10 >= PHRASE_SHARE_TENTHS * min(stem_df[first], word_df[second]))

        good = {p for p in phrase_df if accept_phrase(p)}
        self.notes = [
            {"path": row["path"], "day": row["day"], "keywords": ks | (found & good)}
            for row, ks, found in zip(rows, words, candidates)
        ]
        self.df: dict[str, int] = {}
        for note in self.notes:
            for k in note["keywords"]:
                self.df[k] = self.df.get(k, 0) + 1
        self.total = len(self.notes)

    def score(self, count: int, keyword: str) -> int:
        return math.floor(count * math.log((self.total + 1) / self.df[keyword]) * SCORE_SCALE + 0.5)

    def in_period(self, today: int, days: int) -> list[dict]:
        return [n for n in self.notes if today - n["day"] < days]

    def overview(self, today: int, days: int, by: str = "count") -> dict:
        current = self.in_period(today, days)
        previous = [n for n in self.notes if days <= today - n["day"] < 2 * days]
        cur: dict[str, int] = {}
        prev: dict[str, int] = {}
        for n in current:
            for k in n["keywords"]:
                cur[k] = cur.get(k, 0) + 1
        for n in previous:
            for k in n["keywords"]:
                prev[k] = prev.get(k, 0) + 1
        minimum = 1 if len(current) < 10 else 2
        chosen = [k for k, c in cur.items() if c >= minimum]
        # 차례 (331) — `count` 많이 쓴 순(같으면 두드러진 순) · `score` 두드러진 순.
        if by == "count":
            chosen.sort(key=lambda k: (-cur[k], -self.score(cur[k], k), k))
        else:
            chosen.sort(key=lambda k: (-self.score(cur[k], k), k))
        entries = []
        for k in chosen:
            p = prev.get(k, 0)
            mark = "" if not previous else ("new" if p == 0 else ("up" if cur[k] > p else ""))
            entries.append({"keyword": k, "count": cur[k], "previous": p, "mark": mark})
        return {"notes": len(current), "previousNotes": len(previous), "entries": entries}

    def neighbors(self, center: str, today: int, days: int) -> list[dict]:
        around = [n for n in self.in_period(today, days) if center in n["keywords"]]
        co: dict[str, int] = {}
        for n in around:
            for k in n["keywords"]:
                # 가운데와 낱말이 겹치는 것(구절과 그 안의 낱말)은 둘레에 세우지 않는다 — 늘 함께 나오니 뜻이 없다.
                if k != center and not set(k.split(" ")) & set(center.split(" ")):
                    co[k] = co.get(k, 0) + 1
        minimum = 1 if len(around) < 4 else 2
        chosen = [k for k, c in co.items() if c >= minimum]
        chosen.sort(key=lambda k: (-self.score(co[k], k), k))
        chosen = chosen[:NEIGHBOR_LIMIT]
        top = max((co[k] for k in chosen), default=1)
        return [{"keyword": k, "count": co[k], "level": min(3, max(1, (3 * co[k] + top - 1) // top))} for k in chosen]

    def note_paths(self, keyword: str, also: str | None, today: int, days: int) -> list[str]:
        picked = [n for n in self.in_period(today, days)
                  if keyword in n["keywords"] and (also is None or also in n["keywords"])]
        picked.sort(key=lambda n: (-n["day"], n["path"]))
        return [n["path"] for n in picked]


def layout(count: int) -> list[list[float]]:
    # 넷이면 45도 돌린다 — 3시 · 9시 자리의 말이 가로로 긴 가운데 칸에 붙는다 (빌드 화면 사진).
    start = math.pi / 4 if count == 4 else 0.0
    out = []
    for i in range(count):
        angle = start + 2 * math.pi * i / count
        out.append([round(math.sin(angle), 6), round(-math.cos(angle), 6)])
    return out


def civil_day(year: int, month: int, day: int) -> int:
    """1970-01-01 부터 센 날 (그레고리력 · 하워드 히넌트의 셈)."""
    y = year - (1 if month <= 2 else 0)
    era = (y if y >= 0 else y - 399) // 400
    yoe = y - era * 400
    doy = (153 * (month + (-3 if month > 2 else 9)) + 2) // 5 + day - 1
    doe = yoe * 365 + yoe // 4 - yoe // 100 + doy
    return era * 146097 + doe - 719468


CREATED_RE = re.compile(r"^([0-9]{4})-([0-9]{2})-([0-9]{2})")


def created_day(created: str | None) -> int | None:
    """머리말 `created` · `date` 의 앞 열 글자 `YYYY-MM-DD` → 날. 꼴이 틀리거나 없는 날짜면 None."""
    if not created:
        return None
    m = CREATED_RE.match(created.lstrip("".join(chr(c) for c in sorted(SPACES))))
    if not m:
        return None
    y, mo, d = int(m.group(1)), int(m.group(2)), int(m.group(3))
    if not (1 <= mo <= 12 and 1 <= d <= 31):
        return None
    leap = y % 4 == 0 and (y % 100 != 0 or y % 400 == 0)
    days_in = [31, 29 if leap else 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31][mo - 1]
    if d > days_in:
        return None
    return civil_day(y, mo, d)
