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

## 333 — 덜어내기 (사용자가 숨긴 말 · 2026-11-26)

- **기능 명사** (`STOP` 에 더함) · **직함은 낱말이 아니다** (`TITLES`) · **꾸밈꼴 · 연결꼴은 낱말에도** (`bad_front`).
- **한 글자 + 한 글자 조사** (*것이 · 예를 · 일에*) — 같은 앞 글자에 다른 한 글자 조사가 붙은 두 글자 덩이가 셋 이상이고
  그 덩이 자신은 센 조사를 받지 않을 때 (`one_syllable_josa` — *회의 · 차이* 는 *회의를 · 차이가* 를 받아 남는다). 구절 앞말로도 못 선다.
- **문맥 다양성** (YAKE · `context`) — 폴더 전체에서 10번 이상 나온 낱말의 `(왼쪽 이웃 종류 + 오른쪽 이웃 종류) × 100 > 170 × 나온 횟수`
  이면 뺀다 (*아무 데나 붙는 말*). 이웃은 한 줄 안에서 바로 앞 · 뒤 낱말의 줄기 (구절 후보는 빼고).
- **굳은 표현** (`FIXED_PHRASES`) · 구절 앞말이 동사 연결꼴(`CONNECTIVE_LAST`)이고 낱말로 못 받은 말이면 거른다.
- **사람** — 구절의 뒷말(풀어서)이 직함이고 앞말이 *성씨 + 두 글자* (두 글자 성이면 네 글자)이면 `사람` 후보. 노트 둘 이상이면 받는다.
  받은 사람의 이름은 낱말에서 뺀다. 사람은 가운데가 사람일 때만 둘레에 선다.
- **구절이 덮는 낱말** — 낱말이 든 노트 가운데 그 낱말을 품은 받은 구절도 든 노트가 70% 이상이면 낱말은 뺀다 (*독서* → *독서 모임*).

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
    # 333 — 형식 · 기능 명사 (사용자가 숨긴 말 · 문맥 다양성이 못 잡는 드문 것까지)
    "관련", "가능", "기존", "기반", "여부", "대상", "부분", "내용", "방법", "진행", "사용", "필요", "해당", "각각",
    "일부", "전체", "현재", "최근", "그대로",
}
# 333 — 굳은 표현 (구절로 세우지 않는다).
FIXED_PHRASES = {"예를 들어", "다시 말해", "그럼에도 불구", "이와 같이"}
# 333 — 사람 이름 뒤에 붙는 직함 · 부름말 (두 글자 이상). 성씨로 시작하는 세 글자 이름 + 이 말이면 `사람` 갈래.
TITLES = {
    "대표", "대표님", "책임", "책임님", "선임", "선임님", "수석", "수석님", "팀장", "팀장님", "파트장", "실장", "실장님",
    "본부장", "센터장", "부장", "부장님", "차장", "차장님", "과장", "과장님", "대리", "대리님", "주임", "사원", "이사",
    "이사님", "상무", "상무님", "전무", "전무님", "부사장", "사장", "사장님", "회장", "회장님", "원장", "원장님",
    "소장", "국장", "교수", "교수님", "박사", "박사님", "연구원", "매니저", "프로", "선생님", "변호사", "위원", "위원장",
    "대리님", "님께",
}
# 333 — 흔한 성씨 (한 글자 · 두 글자). 사람 구절의 앞말은 성씨 + 이름 두 글자 (세 글자, 두 글자 성이면 네 글자) —
# *노트 이사 · 스테이지 매니저* 같은 것을 거른다 (저장소 문서 시제품).
SURNAMES = set("김이박최정강조윤장임한오서신권황안송류전홍고문양손배백허유남심노하곽성차주우구민진지엄채원천방공현함변염여추도소석선설마길연위표명기반라왕금옥육인맹제모탁국어은편용예경봉사부")
DOUBLE_SURNAMES = {"남궁", "황보", "제갈", "선우", "독고", "사공", "서문"}
# 333 — 동사 연결꼴 끝 (*들어 · 봐 · 해*) — 구절 앞말이 이것으로 끝나고 낱말로 못 받은 말이면 거른다 (*영어 · 단어* 는 조사를 받아 남는다).
CONNECTIVE_LAST = set("어아여해워")
# 333 — 한 글자 조사 (두 글자 덩이 *것이 · 예를 · 일에* 를 가르는 데).
ONE_JOSA = set("은는이가을를의에로와과랑도만나들")
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
# 333 — 문맥 다양성 (YAKE 의 relatedness to context). 폴더 전체에서 이만큼 넘게 나온 낱말만 잰다.
DIVERSITY_MIN_COUNT = 10
# (왼쪽 이웃 종류 + 오른쪽 이웃 종류) × 100 > 이것 × 나온 횟수 이면 *아무 데나 붙는 말* 로 뺀다.
DIVERSITY_MAX_HUNDREDTHS = 170
# 333 — 사람 (이름 + 직함) 은 노트 둘 이상에서.
PERSON_MIN_NOTES = 2
# 333 — 낱말이 든 노트의 70% 이상이 그 낱말을 품은 구절로 덮이면 낱말은 뺀다 (*독서* → *독서 모임*).
COVER_TENTHS = 7
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


def context(text: str, roles_of, split_front_matter) -> dict:
    """333 — 노트 하나의 문맥 — {말: [나온 횟수, [왼쪽 이웃 …], [오른쪽 이웃 …]]} (이웃은 한 줄 안 바로 앞 · 뒤 낱말의 줄기 · 코드 포인트 순)."""
    _, body = split_front_matter(unicodedata.normalize("NFC", text))
    lines = [line[:-1] if line.endswith("\r") else line for line in body.split("\n")]
    roles = roles_of(lines)
    stats: dict[str, list] = {}
    for line, role in zip(lines, roles):
        if role in ("code", "indentedCode", "comment") or FENCE_RE.match(line):
            continue
        toks = [stem for stem, _ in scan(preview(line)) if " " not in stem]
        for i, t in enumerate(toks):
            entry = stats.setdefault(t, [0, set(), set()])
            entry[0] += 1
            if i > 0:
                entry[1].add(toks[i - 1])
            if i + 1 < len(toks):
                entry[2].add(toks[i + 1])
    return {k: [v[0], sorted(v[1]), sorted(v[2])] for k, v in sorted(stats.items())}


def is_ascii_word(word: str) -> bool:
    return all(is_ascii_alnum(c) for c in word)


class Model:
    """폴더 전체 — rows: [{"path", "day", "terms": [[말, 꼴], …], "context": {말: [횟수, 왼쪽, 오른쪽]}}]."""

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

        # 333 — 문맥 다양성: 폴더 전체의 나온 횟수 · 이웃 종류.
        ctx_count: dict[str, int] = {}
        ctx_left: dict[str, set[str]] = {}
        ctx_right: dict[str, set[str]] = {}
        for row in rows:
            for k, (c, left, right) in row.get("context", {}).items():
                ctx_count[k] = ctx_count.get(k, 0) + c
                ctx_left.setdefault(k, set()).update(left)
                ctx_right.setdefault(k, set()).update(right)

        def too_diverse(k: str) -> bool:
            c = ctx_count.get(k, 0)
            return c >= DIVERSITY_MIN_COUNT and \
                (len(ctx_left.get(k, ())) + len(ctx_right.get(k, ()))) * 100 > DIVERSITY_MAX_HUNDREDTHS * c

        # 333 — 앞말 한 글자 + 한 글자 조사 (*것이 · 예를 · 일에*): 같은 앞 글자에 다른 조사가 붙은 두 글자 덩이가 셋 이상이고
        # 그 덩이 자신은 센 조사를 받지 않을 때 (*회의 · 차이* 는 *회의를 · 차이가* 를 받아 남는다).
        def one_syllable_josa(k: str) -> bool:
            if len(k) != 2 or k[1] not in ONE_JOSA or any(f in STRONG_SET for f in kw_forms.get(k, ())):
                return False
            variants = {x for x in kw_forms if len(x) == 2 and x[0] == k[0] and x[1] in ONE_JOSA}
            return len(variants) >= 3

        # 구절의 앞말 · 낱말 모두 — 동사의 꾸밈꼴 · 연결꼴 (333 부터 낱말에도).
        def bad_front(word: str) -> bool:
            if word[-1] in FRONT_BAD_LAST:
                return True
            if word[-1] in FRONT_VERB_LAST and len(word) >= 3 and word[:-1] in stem_forms:
                return True
            return any(len(word) > len(x) and word.endswith(x) for x in FRONT_BAD_SUFFIXES)

        def accept(k: str) -> bool:
            if k in hidden_set:
                return False
            if is_ascii_word(k):
                return not too_diverse(k)
            if (len(k) < 2 or k in STOP or k in TITLES or is_bad_stem(k) or bad_front(k) or one_syllable_josa(k)
                    or too_diverse(k)):
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
        # 333 — 뒷말이 직함이면 **사람** 후보 (앞말은 두 ~ 네 글자 한글 · 뒷말은 키워드가 아니어도 된다).
        candidates = []
        person_candidates = []
        for pairs in phrase_terms:
            found = set()
            people = set()
            for stem, form in pairs:
                first, second = stem.split(" ", 1)
                second = resolve(second, form)[0]
                if (first == second or first in hidden_set or first in STOP or is_bad_stem(first) or bad_front(first)
                        or one_syllable_josa(first) or (first[-1] in CONNECTIVE_LAST and not accepted.get(first))):
                    continue
                if second in TITLES:
                    if (len(first) == 3 and first[0] in SURNAMES) or (len(first) == 4 and first[:2] in DOUBLE_SURNAMES):
                        people.add(first + " " + second)
                    continue
                if accepted.get(second) and first + " " + second not in FIXED_PHRASES:
                    found.add(first + " " + second)
            candidates.append(found)
            person_candidates.append(people)
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

        person_df: dict[str, int] = {}
        for people in person_candidates:
            for p in people:
                person_df[p] = person_df.get(p, 0) + 1
        self.people = {p for p, c in person_df.items() if c >= PERSON_MIN_NOTES and p not in hidden_set}
        names = {p.split(" ", 1)[0] for p in self.people}

        # 333 — 구절이 덮는 낱말: 낱말이 든 노트의 70% 이상에 그 낱말을 품은 받은 구절이 함께 있으면 낱말은 뺀다.
        covered: dict[str, int] = {}
        for ks, found in zip(words, candidates):
            parts = set()
            for p in found & good:
                parts.update(p.split(" ", 1))
            for k in ks & parts:
                covered[k] = covered.get(k, 0) + 1
        dropped = {k for k, c in covered.items() if c * 10 >= COVER_TENTHS * word_df[k]} | names
        self.notes = [
            {"path": row["path"], "day": row["day"], "keywords": (ks - dropped) | (found & good) | (people & self.people)}
            for row, ks, found, people in zip(rows, words, candidates, person_candidates)
        ]
        self.df: dict[str, int] = {}
        for note in self.notes:
            for k in note["keywords"]:
                self.df[k] = self.df.get(k, 0) + 1
        self.total = len(self.notes)

    def kind(self, keyword: str) -> str:
        """333 — `person` (이름 + 직함) · `phrase` (두 낱말) · `word`."""
        if keyword in self.people:
            return "person"
        return "phrase" if " " in keyword else "word"

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
                # 333 — 사람은 가운데가 사람일 때만 둘레에 (지도는 요즘 동향 · 사람은 참고용 — 사용자).
                if k != center and not set(k.split(" ")) & set(center.split(" ")) \
                        and (k not in self.people or center in self.people):
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
