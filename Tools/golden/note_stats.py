"""315 — **노트의 기초 통계.** Swift `NoteStats` 의 쌍둥이.

2026-11-07 사용자 — *노트에 대한 기초 통계량을 편집모드와 읽기모드에서 볼 수 있도록*.

셈은 **읽는 사람이 보는 글**로 한다 — 마크다운 표시(`**` · `[](주소)` · `#`)는 세지 않는다. 줄마다 목록 미리보기와 같은
`preview_line.preview` (Swift `PreviewLine.plain` — markdown-it 이 심판한 쌍둥이)를 부른다. 빼는 줄:

- 머리말 — 첫 줄이 `---` 이고 뒤에 `---` 나 `...` 줄이 있으면 그 사이 전부
- 코드 울타리 줄(```` ``` ```` · `~~~` — 앞 빈칸 셋까지). 울타리 **안의 줄은 그대로** 센다 (코드도 쓴 글이다)
- 가로줄 · 제목 밑줄 — 빈칸을 빼면 `-` `*` `_` `=` 한 가지로만 셋 이상
- 표의 구분 줄 (`|---|:--:|`) — 문단은 안 끊는다. 표의 줄(`|` 로 시작)은 칸마다 보이는 글로 바꿔 빈칸 하나로 잇는다

문단은 보이는 줄이 이어진 덩이다 — 빈 줄 · 뺀 줄(구분 줄 말고)이 끊는다.

글자는 **NFC 로 맞춘 뒤 유니코드 스칼라** 단위다 (한글 음절 하나 = 1). 빈칸은 아래 `SPACES` 한 벌 — 두 쪽이 같은 벌을 쓴다.
할 일 상자는 미리보기가 `☐ ` · `☑ ` 로 바꾼 것을 세고, 글자 셈에서는 뺀다. 링크 · 사진은 원문에서 `[…](…)` · `![…](…)` 를 센다
(머리말 · 코드 밖). 읽는 시간은 공백을 뺀 글자 500자에 1분 (한글 기준) — 올림.
"""
import math
import re
import unicodedata

from preview_line import preview

SPACES = {0x09, 0x0B, 0x0C, 0x20, 0xA0, 0x1680, 0x2028, 0x2029, 0x202F, 0x205F, 0x3000} | set(range(0x2000, 0x200B))
FENCE_RE = re.compile(r"^ {0,3}(`{3,}|~{3,})")
DELIMITER_RE = re.compile(r"^[ \t]*\|?[ \t]*:?-+:?[ \t]*(\|[ \t]*:?-+:?[ \t]*)*\|?[ \t]*\Z")
LINK_RE = re.compile(r"(!?)\[[^\]\n]*\]\([^)\n]*\)")
CHARS_PER_MINUTE = 500


def is_space(ch: str) -> bool:
    return ord(ch) in SPACES


def strip_spaces(s: str) -> str:
    start, end = 0, len(s)
    while start < end and is_space(s[start]):
        start += 1
    while end > start and is_space(s[end - 1]):
        end -= 1
    return s[start:end]


def is_rule(line: str) -> bool:
    body = [c for c in line if not is_space(c)]
    return len(body) >= 3 and len(set(body)) == 1 and body[0] in "-*_="


def front_matter_end(lines: list) -> int:
    """머리말이 끝난 다음 줄 번호. 없으면 0."""
    if not lines or lines[0].rstrip(" \t") != "---":
        return 0
    for i in range(1, len(lines)):
        if lines[i].rstrip(" \t") in ("---", "..."):
            return i + 1
    return 0


def table_text(line: str) -> str:
    cells = line.split("|")
    if cells and strip_spaces(cells[0]) == "":
        cells = cells[1:]
    if cells and strip_spaces(cells[-1]) == "":
        cells = cells[:-1]
    shown = [preview(c) for c in cells]
    return " ".join(c for c in shown if c)


def stats(text: str) -> dict:
    text = unicodedata.normalize("NFC", text)
    lines = [l[:-1] if l.endswith("\r") else l for l in text.split("\n")]
    start = front_matter_end(lines)
    chars = no_spaces = words = shown_lines = paragraphs = 0
    tasks = done = links = images = 0
    fence = None          # 열린 울타리 글자 (` 나 ~) · 길이
    in_paragraph = False
    for line in lines[start:]:
        visible = None
        opener = FENCE_RE.match(line)
        if fence is not None:
            if opener and opener.group(1)[0] == fence[0] and len(opener.group(1)) >= fence[1] \
                    and strip_spaces(line[opener.end():]) == "":
                fence = None
            else:
                visible = strip_spaces(line)
        elif opener:
            fence = (opener.group(1)[0], len(opener.group(1)))
        elif ("|" in line) and DELIMITER_RE.match(line):
            continue          # 표의 구분 줄 — 세지 않고 문단도 안 끊는다 (표 하나가 문단 하나)
        elif is_rule(line):
            pass
        else:
            for m in LINK_RE.finditer(line):
                if m.group(1):
                    images += 1
                else:
                    links += 1
            if strip_spaces(line).startswith("|"):
                visible = table_text(line)
            else:
                visible = preview(line)
                if visible.startswith("☐ ") or visible.startswith("☑ "):
                    tasks += 1
                    if visible.startswith("☑ "):
                        done += 1
                    visible = visible[2:]
        if visible:
            chars += len(visible)
            no_spaces += sum(1 for c in visible if not is_space(c))
            token = False
            for c in visible:
                if is_space(c):
                    token = False
                elif not token:
                    token = True
                    words += 1
            shown_lines += 1
            if not in_paragraph:
                paragraphs += 1
                in_paragraph = True
        else:
            in_paragraph = False
    minutes = math.ceil(no_spaces / CHARS_PER_MINUTE) if no_spaces > 0 else 0
    return {
        "characters": chars, "charactersNoSpaces": no_spaces, "words": words,
        "lines": shown_lines, "paragraphs": paragraphs,
        "tasks": tasks, "tasksDone": done, "links": links, "images": images,
        "readingMinutes": minutes,
    }
