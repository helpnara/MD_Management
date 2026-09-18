#!/usr/bin/env python3
"""기댓값을 파이썬으로 **독립 계산**해 JSON 으로 적는다.

왜 있나
-------
원격 세션(리눅스)에는 Swift 툴체인이 없다. 컴파일 못 하는 환경에서 테스트 기댓값을
손으로 적으면 **테스트가 버그를 승인한다**. 그래서 마크다운 파싱은 다른 구현
(`markdown-it-py`)으로, 머리말은 진짜 YAML 파서(`PyYAML`)로, 경로 해석과 공유 묶음은
설계서를 보고 파이썬으로 다시 구현해 대조한다.

  python3 Tools/golden/generate.py          # 기댓값을 다시 만든다
  python3 Tools/golden/generate.py --check  # 커밋된 것과 다르면 실패한다 (CI)

이 스크립트가 만드는 파일을 Swift 테스트(`GoldenTests.swift`)가 그대로 읽는다.
"""

from __future__ import annotations

import argparse
import json
import pathlib
import sys
import unicodedata
import urllib.parse

try:
    from markdown_it import MarkdownIt
    import yaml
except ImportError:  # pragma: no cover
    sys.exit("먼저 설치하세요: pip install -r Tools/golden/requirements.txt")

ROOT = pathlib.Path(__file__).resolve().parents[2]
FIXTURES = ROOT / "Tools" / "golden" / "fixtures"
CASES = ROOT / "Tools" / "golden" / "cases.json"
STYLE_CASES = ROOT / "Tools" / "golden" / "style-cases.json"
INDENT_CASES = ROOT / "Tools" / "golden" / "indent-cases.json"
RENUMBER_CASES = ROOT / "Tools" / "golden" / "renumber-cases.json"
LINK_CASES = ROOT / "Tools" / "golden" / "relative-link-cases.json"
TAG_CASES = ROOT / "Tools" / "golden" / "tag-cases.json"
REBASE_CASES = ROOT / "Tools" / "golden" / "rebase-cases.json"
PIN_CASES = ROOT / "Tools" / "golden" / "pin-cases.json"
FORMAT_CASES = ROOT / "Tools" / "golden" / "format-cases.json"
OUT = ROOT / "Packages" / "Core" / "Tests" / "CoreTests" / "Golden" / "expected.json"

NOTE_EXTS = {"md", "markdown", "txt"}
MARKDOWN_EXTS = {"md", "markdown"}


# ── 링크 뽑기 — markdown-it-py 로 (swift-markdown 과 다른 구현) ────────────────

def make_parser() -> MarkdownIt:
    """CommonMark + 표.

    `swift-markdown` 은 cmark-gfm 이라 표를 기본으로 읽는다. linkify(맨 URL 을
    링크로 바꾸는 것)는 양쪽 다 안 하므로 켜지 않는다.

    `strikethrough_single_tilde` — cmark-gfm 은 `~하나~` 도 취소선으로 읽는데
    markdown-it 의 기본값은 `~~둘~~` 만 읽는다. 앱의 읽기 모드가 cmark-gfm 이므로
    심판도 그쪽에 맞춘다 (빌드 29 · 3번).
    """
    return MarkdownIt("commonmark", {"strikethrough_single_tilde": True}).enable(
        ["table", "strikethrough"])


def extract_links(text: str) -> list[dict]:
    """머리말을 뗀 본문에서 이미지와 링크를 나온 순서대로."""
    _, body = split_front_matter(text)
    md = make_parser()
    found: list[dict] = []

    def walk(tokens):
        for token in tokens:
            if token.type == "inline" and token.children:
                walk(token.children)
            elif token.type == "link_open":
                href = token.attrGet("href") or ""
                if href:
                    found.append({"destination": href, "kind": "link"})
            elif token.type == "image":
                src = token.attrGet("src") or ""
                if src:
                    found.append({"destination": src, "kind": "image"})

    walk(md.parse(body))
    return found


# ── 머리말 — PyYAML 로 ────────────────────────────────────────────────────────

def split_front_matter(text: str) -> tuple[str | None, str]:
    source = text[1:] if text.startswith("﻿") else text
    lines = source.split("\n")
    if not lines or lines[0].strip() != "---":
        return None, text
    for i in range(1, len(lines)):
        if lines[i].strip() in ("---", "..."):
            return "\n".join(lines[1:i]), "\n".join(lines[i + 1:])
    return None, text


def parse_front_matter(text: str) -> dict | None:
    raw, _ = split_front_matter(text)
    if raw is None:
        return None
    try:
        data = yaml.safe_load(raw) or {}
    except yaml.YAMLError:
        data = {}
    if not isinstance(data, dict):
        data = {}

    title = data.get("title")
    created = data.get("created", data.get("date"))
    tags = data.get("tags", [])
    if isinstance(tags, str):
        tags = tags.split()
    if not isinstance(tags, list):
        tags = []

    def text_of(value):
        if value is None:
            return None
        return nfc(str(value).strip()) or None

    return {
        "title": text_of(title),
        "tags": [nfc(str(t).strip()) for t in tags if str(t).strip()],
        "created": text_of(created),
    }


def strip_heading_marker(line: str) -> str:
    """`# 제목` · `### 제목` 에서 마커를 뗀다. 마커가 없으면 그대로."""
    hashes = 0
    for ch in line:
        if ch == "#":
            hashes += 1
        else:
            break
    if 1 <= hashes <= 6:
        after = line[hashes:]
        # `#태그` 는 제목이 아니다 — 마커 뒤에 빈칸이 있어야 한다 (CommonMark).
        if after == "" or after[0] == " ":
            line = after.rstrip("#")
    return line.strip()


def first_line(text: str) -> str | None:
    """**첫 줄이 곧 제목이다** (T6). `#` 은 있어도 없어도 된다.

    글자가 한 자도 없는 줄(`---` 수평선 · 장식)은 건너뛴다 — 사람이 파일명으로
    삼고 싶은 줄이 아니다.
    """
    _, body = split_front_matter(text)
    for line in body.split("\n"):
        stripped = strip_heading_marker(line.strip())
        if not stripped:
            continue
        if not any(ch.isalpha() or ch.isdigit() for ch in stripped):
            continue
        return stripped
    return None


def note_title(text: str, file_name: str) -> str:
    matter = parse_front_matter(text)
    if matter and matter["title"]:
        return matter["title"]
    first = first_line(text)
    if first:
        return first
    name = nfc(file_name)
    dot = name.rfind(".")
    return name[:dot] if dot > 0 else name


# ── 경로 해석 — 설계서 §7.3 을 보고 다시 구현 ────────────────────────────────

def nfc(text: str) -> str:
    return unicodedata.normalize("NFC", text)


def has_scheme(text: str) -> bool:
    if not text or not text[0].isascii() or not text[0].isalpha():
        return False
    for ch in text[1:]:
        if ch == ":":
            return True
        if ch.isascii() and (ch.isalnum() or ch in "+-."):
            continue
        return False
    return False


def directory_of(path: str) -> str:
    path = nfc(path)
    slash = path.rfind("/")
    return path[:slash] if slash >= 0 else ""


def join(base: str, relative: str):
    stack = [p for p in nfc(base).split("/") if p]
    for part in [p for p in nfc(relative).split("/") if p]:
        if part == ".":
            continue
        if part == "..":
            if not stack:
                return None
            stack.pop()
            continue
        stack.append(part)
    return "/".join(stack) if stack else None


def resolve(raw: str, note_path: str) -> dict:
    text = raw.strip()
    if len(text) >= 2 and text.startswith("<") and text.endswith(">"):
        text = text[1:-1]
    if not text:
        return {"kind": "empty", "value": ""}
    if has_scheme(text):
        return {"kind": "external", "value": text}
    if text.startswith("#"):
        return {"kind": "empty", "value": ""}
    if "#" in text:
        text = text.split("#", 1)[0]
    if not text:
        return {"kind": "empty", "value": ""}

    decoded = nfc(urllib.parse.unquote(text))
    if decoded.startswith("/"):
        return {"kind": "absolute", "value": decoded}
    joined = join(directory_of(note_path), decoded)
    if joined is None:
        return {"kind": "outside", "value": decoded}
    return {"kind": "relative", "value": joined}


def file_extension(path: str) -> str:
    name = path.rsplit("/", 1)[-1]
    dot = name.rfind(".")
    return name[dot + 1:].lower() if dot > 0 else ""


# ── 뷰어 HTML — 설계서 §7.3 · ADR-0004 를 보고 다시 구현 ────────────────────

# `CharacterSet.urlPathAllowed` 와 같은 집합이다. Swift 의 encode(path:) 와 맞춰야 한다.
PATH_SAFE = "/-._~!$&'()*+,;=:@"


def asset_url(path: str) -> str:
    return "yb://note/" + urllib.parse.quote(nfc(path), safe=PATH_SAFE)


def html_facts(note_path: str, text: str, existing: set[str]) -> dict:
    """뷰어가 내놓아야 하는 **구조**를 markdown-it 으로 따로 센다.

    HTML 문자열을 통째로 견주지 않는 이유: 두 구현의 줄바꿈 · 속성 순서 같은
    껍데기 차이가 진짜 차이를 덮는다. 세는 것은 뜻이 있는 것들뿐이다.
    """
    _, body = split_front_matter(text)
    tokens = make_parser().parse(body)

    headings: list[int] = []
    list_items = 0
    tables = 0
    code_blocks = 0
    for token in tokens:
        if token.type == "heading_open":
            headings.append(int(token.tag[1:]))
        elif token.type == "list_item_open":
            list_items += 1
        elif token.type == "table_open":
            tables += 1
        elif token.type in ("fence", "code_block"):
            code_blocks += 1

    # 작업 목록(`- [ ]`)은 CommonMark 가 아니라 GFM 확장이다. markdown-it 의
    # commonmark 프리셋은 안 읽으므로 줄로 직접 센다.
    checked = unchecked = 0
    for line in body.split("\n"):
        stripped = line.lstrip()
        for prefix in ("- ", "* ", "+ "):
            if stripped.startswith(prefix):
                rest = stripped[len(prefix):]
                if rest.startswith("[ ] "):
                    unchecked += 1
                elif rest[:4].lower() == "[x] ":
                    checked += 1
                break

    image_srcs: list[str] = []
    missing: list[str] = []
    seen: set[str] = set()

    def miss(raw: str):
        if raw not in seen:
            seen.add(raw)
            missing.append(raw)

    for link in extract_links(text):
        target = resolve(link["destination"], note_path)
        kind, value = target["kind"], target["value"]
        if link["kind"] == "image":
            if kind == "empty":
                continue
            if kind == "relative" and value in existing:
                image_srcs.append(asset_url(value))
            else:
                # 외부 이미지도 안 보인다 — CSP 가 네트워크를 막는다.
                miss(link["destination"])
        else:
            if kind == "relative" and value not in existing:
                miss(link["destination"])
            elif kind == "outside":
                miss(link["destination"])

    return {
        "headings": headings,
        "listItems": list_items,
        "checkboxes": {"checked": checked, "unchecked": unchecked},
        "tables": tables,
        "codeBlocks": code_blocks,
        "imageSrcs": image_srcs,
        "missing": missing,
        "missingDecoded": [nfc(urllib.parse.unquote(m)) for m in missing],
    }


# ── 공유 묶음 — 설계서 §7.6 을 보고 다시 구현 ────────────────────────────────

def share_plan(note_path: str, text: str, existing: set[str], follow: bool) -> dict:
    note = nfc(note_path)
    includes = [note]
    seen = {note}
    missing: list[str] = []
    missing_seen: set[str] = set()

    for link in extract_links(text):
        target = resolve(link["destination"], note)
        kind = target["kind"]
        if kind in ("empty", "external", "absolute"):
            continue
        if kind == "outside":
            if link["destination"] not in missing_seen:
                missing_seen.add(link["destination"])
                missing.append(link["destination"])
            continue
        path = target["value"]
        if path in seen:
            continue
        if file_extension(path) in MARKDOWN_EXTS and not follow:
            continue
        if path in existing:
            seen.add(path)
            includes.append(path)
        elif link["destination"] not in missing_seen:
            missing_seen.add(link["destination"])
            missing.append(link["destination"])

    return {
        "mode": "zip" if len(includes) > 1 else "mdOnly",
        "includes": includes,
        # 원문에 적힌 그대로. 사용자에게 "어느 링크가 없는지" 를 보여 줄 때 쓴다.
        "missing": missing,
        # **Swift 테스트가 견주는 것은 이쪽이다.** markdown-it 은 링크 목적지를
        # 퍼센트 인코딩해서 주고 swift-markdown 은 원문 그대로 준다. 두 구현이
        # 다른 것은 인코딩뿐이므로, 디코딩한 값으로 견줘야 진짜 차이만 잡힌다.
        "missingDecoded": [nfc(urllib.parse.unquote(m)) for m in missing],
    }


# ── 라이브 편집기 — 한 줄의 모습 (ADR-0005 L1) ──────────────────────────────

BLOCK_OF_TOKEN = {
    "blockquote_open": "quote",
    "bullet_list_open": "listItem",
    "ordered_list_open": "orderedItem",
    "fence": "codeBlock",
    "code_block": "codeBlock",
    "hr": "thematicBreak",
    "paragraph_open": None,
}

SPAN_OF_OPEN = {
    "strong_open": "strong",
    "em_open": "emphasis",
    "s_open": "strikethrough",
    "link_open": "link",
}
SPAN_CLOSE = {"strong_close", "em_close", "s_close", "link_close"}


def inline_spans(children) -> list[dict]:
    """겹친 것까지 **여는 태그 순서로** 준다.

    바깥 구간의 글자에는 안쪽 마커가 그대로 들어간다 — Swift 쪽 `StyleSpan` 이
    원문을 잘라 주기 때문이다. 그래서 여닫는 토큰의 `markup` 을 도로 붙여 쌓는다.
    """
    out: list[dict] = []
    stack: list[dict] = []

    def emit(text: str) -> None:
        for record in stack:
            record["text"] += text

    for token in children or []:
        kind = token.type
        if kind in SPAN_OF_OPEN:
            opening = "[" if kind == "link_open" else token.markup
            emit(opening)
            record = {"token": SPAN_OF_OPEN[kind], "text": "",
                      "_href": token.attrGet("href") or ""}
            out.append(record)
            stack.append(record)
        elif kind in SPAN_CLOSE:
            record = stack.pop()
            emit("](" + record["_href"] + ")" if kind == "link_close" else token.markup)
        elif kind == "code_inline":
            emit(token.markup + token.content + token.markup)
            out.append({"token": "inlineCode", "text": token.content})
        elif kind == "image":
            emit("![" + token.content + "](" + (token.attrGet("src") or "") + ")")
            out.append({"token": "image", "text": token.content})
        else:
            emit(token.content)

    return [{"token": record["token"], "text": record["text"]} for record in out]


def strip_checkbox(content: str) -> str:
    """`- [ ] 우유` 의 `[ ] ` 를 뗀다.

    작업 목록은 GFM 확장이고 commonmark 프리셋은 안 읽는다 (`html_facts` 도 같은
    이유로 줄을 직접 센다). 편집기는 체크박스를 마커로 먹으므로 여기서도 뗀다.
    """
    for mark in ("[ ]", "[x]", "[X]"):
        if content.startswith(mark):
            return content[len(mark):].lstrip(" ")
    return content


def list_marker_width(line: str) -> int | None:
    """줄 첫머리의 목록 마커가 몇 칸인가 (앞 빈칸 제외). 목록이 아니면 `None`."""
    rest = line.lstrip(" \t")
    if rest[:2] in ("- ", "* ", "+ "):
        return 2
    digits = ""
    for ch in rest:
        if ch in "0123456789":
            digits += ch
        else:
            break
    if digits and len(digits) <= 9 and rest[len(digits):len(digits) + 2] in (". ", ") "):
        return len(digits) + 2
    return None


def indent_width(line: str) -> int:
    return sum(4 if ch == "\t" else 1 for ch in line[:len(line) - len(line.lstrip(" \t"))])


def style_facts(line: str) -> dict:
    """한 줄의 블록 종류 · 마커 뗀 내용 · 강조 구간."""
    # 표는 여러 줄이라 한 줄만으로는 markdown-it 이 표로 읽지 않는다. 편집기는 줄
    # 단위라서 `|` 로 시작하면 표 줄로 보고 고정폭 원문 그대로 둔다 (ADR-0005).
    if line.strip().startswith("|"):
        return {"block": "tableRow", "content": "", "spans": []}

    # **깊이 들여쓴 목록 줄은 문맥째로 물어본다** (T4). 한 줄만 주면 markdown-it 도
    # 네 칸 이상을 코드로 읽는다 — 그것이 CommonMark 다. 하지만 파일에서는 앞 줄이
    # 목록이므로 겹친 항목이 맞다. **조상 항목을 앞에 붙여** markdown-it 이 스스로
    # `겹친 항목` 이라고 답하게 한다. 기댓값을 손으로 적지 않기 위해서다.
    if indent_width(line) >= 4 and list_marker_width(line) is not None:
        return style_facts_in_list_context(line)

    tokens = make_parser().parse(line)
    if not tokens:
        return {"block": None, "content": "", "spans": []}

    first = tokens[0].type
    if first == "heading_open":
        block = "heading" + tokens[0].tag[1:]
    elif first in BLOCK_OF_TOKEN:
        block = BLOCK_OF_TOKEN[first]
    else:
        raise SystemExit(f"모르는 블록 토큰 {first!r} — {line!r}")

    if block in ("codeBlock", "thematicBreak"):
        return {"block": block, "content": "", "spans": []}

    inline = next((t for t in tokens if t.type == "inline"), None)
    if inline is None:
        return {"block": block, "content": "", "spans": []}

    content = inline.content
    if block in ("listItem", "orderedItem"):
        content = strip_checkbox(content)

    return {"block": block, "content": content, "spans": inline_spans(inline.children)}


def style_facts_in_list_context(line: str) -> dict:
    """조상 항목을 앞에 붙여 물어본 뒤, **마지막 항목**의 값을 쓴다."""
    goal = indent_width(line)
    # 두 칸에 한 단계씩 조상을 세운다: `- 조상`, `  - 조상`, …
    context = "".join(f"{'  ' * step}- 조상\n" for step in range(goal // 2))
    tokens = make_parser().parse(context + line)

    block = None
    for token in tokens:
        if token.type == "bullet_list_open":
            block = "listItem"
        elif token.type == "ordered_list_open":
            block = "orderedItem"
    inline = None
    for token in tokens:
        if token.type == "inline":
            inline = token
    if block is None or inline is None:
        raise SystemExit(f"문맥을 붙여도 목록으로 안 읽힌다 — {line!r}")

    content = strip_checkbox(inline.content)
    return {"block": block, "content": content, "spans": inline_spans(inline.children)}


def build_style_cases() -> list[dict]:
    spec = json.loads(STYLE_CASES.read_text(encoding="utf-8"))
    out = []
    for case in spec["cases"]:
        text = case["text"]
        out.append({"name": case["name"], "text": text, **style_facts(text)})
    return out


# ── 탭 들여쓰기 — 설계서 §7.3 의 규칙을 파이썬으로 다시 (빌드 29 · 1번) ─────────

INDENT_STEP = "  "


def is_list_item(line: str) -> bool:
    """앞 빈칸을 뗀 뒤 `- ` · `* ` · `+ ` · `1. ` · `1) ` 로 시작하나.

    markdown-it 에 묻지 않는 이유: 한 줄만 주면 네 칸 이상 들여쓴 줄을 코드로 읽는데,
    겹친 목록은 두 단계만 내려가도 그보다 깊어진다.
    """
    rest = line.lstrip(" \t")
    if rest[:2] in ("- ", "* ", "+ "):
        return True
    digits = ""
    for ch in rest:
        if ch.isdigit():
            digits += ch
        else:
            break
    if not digits or len(digits) > 9:
        return False
    return rest[len(digits):len(digits) + 2] in (". ", ") ")


def indent_block(block: str):
    """탭 — 목록 줄이 하나라도 있으면 빈 줄을 뺀 모든 줄 앞에 빈칸 둘."""
    lines = block.split("\n")
    if not any(is_list_item(line) for line in lines):
        return None
    first_delta = 0
    out = []
    for index, line in enumerate(lines):
        if not line.strip():
            out.append(line)
            continue
        if index == 0:
            first_delta = len(INDENT_STEP.encode("utf-16-le")) // 2
        out.append(INDENT_STEP + line)
    return {"text": "\n".join(out), "firstLineDelta": first_delta}


def outdent_block(block: str):
    """시프트 탭 — 줄마다 앞의 탭 하나 또는 빈칸 둘까지."""
    changed = False
    first_delta = 0
    out = []
    for index, line in enumerate(block.split("\n")):
        removed = 0
        if line.startswith("\t"):
            line = line[1:]
            removed = 1
        else:
            while removed < len(INDENT_STEP) and line.startswith(" "):
                line = line[1:]
                removed += 1
        if removed:
            changed = True
            if index == 0:
                first_delta = -removed
        out.append(line)
    if not changed:
        return None
    return {"text": "\n".join(out), "firstLineDelta": first_delta}


def build_indent_cases() -> list[dict]:
    spec = json.loads(INDENT_CASES.read_text(encoding="utf-8"))
    return [{
        "name": case["name"],
        "text": case["text"],
        "indented": indent_block(case["text"]),
        "outdented": outdent_block(case["text"]),
    } for case in spec["cases"]]


# ── 번호 다시 매기기 — 설계서의 규칙을 파이썬으로 다시 (빌드 32 · 104) ─────────


def renumber_block(block: str) -> list[dict]:
    """번호 목록을 1 · 2 · 3 으로. 고칠 자리만 돌려준다 (UTF-16 오프셋).

    - 첫 항목의 번호는 그대로 (CommonMark 는 `5.` 로 시작하는 목록을 허용한다)
    - 겹친 단계는 따로 센다 (앞 빈칸 수가 단계)
    - 빈 줄은 목록을 끊지 않는다
    - 글줄이나 같은 단계의 글머리표가 오면 그 단계부터 아래는 끊긴다
    """
    fixes: list[dict] = []
    nxt: dict[int, int] = {}
    offset = 0

    for line in block.split("\n"):
        length = len(line.encode("utf-16-le")) // 2
        here = offset
        offset += length + 1

        if not line.strip():
            continue

        indent = line[:len(line) - len(line.lstrip(" \t"))]
        depth = sum(4 if ch == "\t" else 1 for ch in indent)
        rest = line[len(indent):]

        if rest[:2] in ("- ", "* ", "+ "):
            nxt = {k: v for k, v in nxt.items() if k < depth}
            continue

        digits = ""
        for ch in rest:
            if ch in "0123456789":   # 아스키 숫자만 — 스위프트 쪽과 같게
                digits += ch
            else:
                break
        after = rest[len(digits):]
        if not digits or len(digits) > 9 or after[:2] not in (". ", ") "):
            nxt = {k: v for k, v in nxt.items() if k < depth}
            continue

        nxt = {k: v for k, v in nxt.items() if k <= depth}
        read = int(digits)
        wanted = nxt.get(depth, read)
        if wanted != read:
            fixes.append({
                "start": here + len(indent.encode("utf-16-le")) // 2,
                "length": len(digits),
                "number": str(wanted),
            })
        nxt[depth] = wanted + 1
    return fixes


def build_renumber_cases() -> list[dict]:
    spec = json.loads(RENUMBER_CASES.read_text(encoding="utf-8"))
    return [{"name": case["name"], "text": case["text"], "fixes": renumber_block(case["text"])}
            for case in spec["cases"]]


# ── 상대 링크 — `join` 의 반대 (빌드 34 · 108) ────────────────────────────────


def relative_link(note_folder: str, target: str) -> str:
    """노트 위치에서 목표 파일로 가는 상대 링크. `join` 을 거꾸로 돌린 것이다."""
    base = [p for p in nfc(note_folder).split("/") if p]
    goal = [p for p in nfc(target).split("/") if p]
    if not goal:
        return ""
    shared = 0
    goal_folders = len(goal) - 1     # 마지막 조각은 파일 이름이다
    while shared < len(base) and shared < goal_folders and base[shared] == goal[shared]:
        shared += 1
    return "../" * (len(base) - shared) + "/".join(goal[shared:])


def build_link_cases() -> list[dict]:
    spec = json.loads(LINK_CASES.read_text(encoding="utf-8"))
    out = []
    for case in spec["cases"]:
        link = relative_link(case["folder"], case["target"])
        out.append({
            "name": case["name"],
            "folder": case["folder"],
            "target": case["target"],
            "link": link,
            # **되돌아오나.** `join(folder, link)` 이 목표와 같아야 링크가 산다.
            "resolved": join(case["folder"], link),
        })
    return out


# ── `#태그` — 설계서의 규칙을 파이썬으로 다시 (빌드 34 · T2) ──────────────────

TAG_EXTRA = "_-/"


def is_tag_character(ch: str) -> bool:
    return ch.isalnum() or ch in TAG_EXTRA


def scan_tags(text: str) -> list[dict]:
    """`#태그` 를 다 찾는다. UTF-16 오프셋.

    1. `#` 앞이 줄 첫머리이거나 빈칸이다
    2. 바로 뒤에 태그 글자가 온다
    3. 숫자만인 것은 태그가 아니다
    """
    found = []
    chars = list(text)
    offset = 0
    i = 0
    while i < len(chars):
        width = len(chars[i].encode("utf-16-le")) // 2
        if chars[i] != "#" or not (i == 0 or chars[i - 1].isspace()):
            offset += width
            i += 1
            continue
        end = i + 1
        length = 1
        has_letter = False
        while end < len(chars) and is_tag_character(chars[end]):
            if not chars[end].isdigit():
                has_letter = True
            length += len(chars[end].encode("utf-16-le")) // 2
            end += 1
        if length > 1 and has_letter:
            found.append({"start": offset, "length": length,
                          "text": "".join(chars[i:end])})
            offset += length
            i = end
            continue
        offset += width
        i += 1
    return found


def build_tag_cases() -> list[dict]:
    spec = json.loads(TAG_CASES.read_text(encoding="utf-8"))
    return [{"name": case["name"], "text": case["text"], "tags": scan_tags(case["text"])}
            for case in spec["cases"]]


# ── 옮길 때 링크 고치기 — 설계서의 규칙을 파이썬으로 다시 (빌드 34 · T1) ──────


def read_destination(text: str, start: int):
    """`](` 바로 뒤에서 닫는 `)` 까지. `<…>` 와 겹친 괄호를 다룬다."""
    if start >= len(text):
        return None
    if text[start] == "<":
        i = start + 1
        while i < len(text) and text[i] != ">":
            if text[i] == "\n":
                return None
            i += 1
        if i >= len(text) or i + 1 >= len(text) or text[i + 1] != ")":
            return None
        return text[start:i + 1], i + 1
    depth = 0
    i = start
    while i < len(text):
        ch = text[i]
        if ch == "\n":
            return None
        if ch == "(":
            depth += 1
        elif ch == ")":
            if depth == 0:
                return text[start:i], i
            depth -= 1
        i += 1
    return None


def rebase_one(raw: str, note: str, new_folder: str) -> str:
    wrapped = len(raw) >= 2 and raw.startswith("<") and raw.endswith(">")
    inner = raw[1:-1] if wrapped else raw
    anchor = ""
    target = inner
    hash_at = inner.find("#")
    if hash_at > 0:
        anchor = inner[hash_at:]
        target = inner[:hash_at]
    got = resolve(target, note)
    if got["kind"] != "relative":
        return raw
    link = relative_link(new_folder, got["value"]) + anchor
    return "<" + link + ">" if (wrapped or " " in link) else link


def rebase_links(text: str, old_folder: str, new_folder: str) -> str:
    if old_folder == new_folder:
        return text
    note = "노트.md" if not old_folder else old_folder + "/노트.md"
    out = []
    cursor = 0
    while True:
        bracket = text.find("](", cursor)
        if bracket < 0:
            break
        out.append(text[cursor:bracket + 2])
        cursor = bracket + 2
        piece = read_destination(text, cursor)
        if piece is None:
            continue
        raw, end = piece
        out.append(rebase_one(raw, note, new_folder))
        out.append(text[end])
        cursor = end + 1
    out.append(text[cursor:])
    return "".join(out)


def build_rebase_cases() -> list[dict]:
    spec = json.loads(REBASE_CASES.read_text(encoding="utf-8"))
    return [{"name": case["name"], "text": case["text"], "from": case["from"], "to": case["to"],
             "rebased": rebase_links(case["text"], case["from"], case["to"])}
            for case in spec["cases"]]


# ── 고정된 노트 — 설계서의 규칙을 파이썬으로 다시 (빌드 35 · T10) ────────────


def pins_tidy(paths: list[str]) -> list[str]:
    seen = set()
    out = []
    for path in paths:
        clean = nfc(path.strip())
        if not clean or clean in seen:
            continue
        seen.add(clean)
        out.append(clean)
    return out


def pins_following(paths: list[str], old: str, new: str) -> list[str]:
    old_n, new_n = nfc(old), nfc(new)
    if not old_n or old_n == new_n:
        return pins_tidy(paths)
    moved = []
    for path in paths:
        if path == old_n:
            moved.append(new_n)
        elif path.startswith(old_n + "/"):
            moved.append(new_n + path[len(old_n):])
        else:
            moved.append(path)
    return pins_tidy(moved)


def pins_removing(paths: list[str], gone: str) -> list[str]:
    target = nfc(gone)
    if not target:
        return pins_tidy(paths)
    return pins_tidy([p for p in paths if p != target and not p.startswith(target + "/")])


def build_pin_cases() -> list[dict]:
    spec = json.loads(PIN_CASES.read_text(encoding="utf-8"))
    out = []
    for case in spec["cases"]:
        entry = {"name": case["name"], "pins": case["pins"]}
        if "merge" in case:
            entry["merge"] = case["merge"]
            entry["merged"] = pins_tidy(case["pins"] + case["merge"])
        if "from" in case:
            entry["from"] = case["from"]
            entry["to"] = case["to"]
            entry["followed"] = pins_following(case["pins"], case["from"], case["to"])
        if "gone" in case:
            entry["gone"] = case["gone"]
            entry["removed"] = pins_removing(case["pins"], case["gone"])
        entry["tidied"] = pins_tidy(case["pins"])
        out.append(entry)
    return out


# ── 만들기 ───────────────────────────────────────────────────────────────────

def resolved_entry(link: dict, note_path: str) -> dict:
    target = resolve(link["destination"], note_path)
    return {
        "linkKind": link["kind"],       # image | link
        "target": target["kind"],       # empty | external | absolute | outside | relative
        "value": target["value"],
    }


def build() -> dict:
    spec = json.loads(CASES.read_text(encoding="utf-8"))
    out_cases = []

    for case in spec["cases"]:
        path = FIXTURES / case["file"]
        text = path.read_text(encoding="utf-8")
        note_path = nfc(case["notePath"])
        existing = {nfc(p) for p in case.get("existing", [])}
        follow = case.get("followLinkedNotes", True)

        links = extract_links(text)
        _, body = split_front_matter(text)

        out_cases.append({
            "name": case.get("name", case["file"]),
            "file": case["file"],
            "notePath": note_path,
            "existing": sorted(existing),
            "followLinkedNotes": follow,
            "source": text,
            "body": body,
            "frontMatter": parse_front_matter(text),
            "title": note_title(text, path.name),
            "links": links,
            "resolved": [resolved_entry(link, note_path) for link in links],
            "sharePlan": share_plan(note_path, text, existing, follow),
            "html": html_facts(note_path, text, existing),
        })

    return {
        "_generator": "Tools/golden/generate.py (markdown-it-py + PyYAML)",
        "_warning": "손으로 고치지 마세요. generate.py 를 다시 돌리세요.",
        "cases": out_cases,
        "styleCases": build_style_cases(),
        "indentCases": build_indent_cases(),
        "renumberCases": build_renumber_cases(),
        "linkCases": build_link_cases(),
        "tagCases": build_tag_cases(),
        "rebaseCases": build_rebase_cases(),
        "pinCases": build_pin_cases(),
        "formatCases": build_format_cases(),
    }


# ── 편집 도구 띠 — 굵게 · 기울임 · 취소선 · 인용 · 표 (T13 1차) ────────────────
#
# **스위프트와 따로 구현한다.** 같은 규칙을 두 번 적어 서로를 잡게 하는 것이 이 심판의
# 전부다 — 한쪽만 있으면 테스트가 버그를 승인한다 (CLAUDE.md §2).
# 게다가 결과가 **정말 그 마크다운이 되는지**는 markdown-it 이 한 번 더 본다.

WRAPS = {"bold": "**", "italic": "*", "strikethrough": "~~"}
WRAP_TAG = {"bold": "strong", "italic": "em", "strikethrough": "s"}


def to_units(text: str) -> list[int]:
    raw = text.encode("utf-16-le")
    return [int.from_bytes(raw[i:i + 2], "little") for i in range(0, len(raw), 2)]


def from_units(units: list[int]) -> str:
    return b"".join(u.to_bytes(2, "little") for u in units).decode("utf-16-le")


def u16len(text: str) -> int:
    return len(text.encode("utf-16-le")) // 2


def scan_wrap(op: str, units: list[int], start: int, length: int) -> dict:
    """양옆의 표시 개수를 센다. `toggle_wrap` 과 `active_at` 이 같이 쓴다."""
    mark = to_units(WRAPS[op])[0]
    need = 1 if op == "italic" else 2
    blanks = {0x20, 0x09, 0x0A}

    begin = max(0, min(start, len(units)))
    finish = max(begin, min(start + length, len(units)))
    while begin < finish and units[begin] == mark:
        begin += 1
    while finish > begin and units[finish - 1] == mark:
        finish -= 1
    while begin < finish and units[begin] in blanks:
        begin += 1
    while finish > begin and units[finish - 1] in blanks:
        finish -= 1

    left = 0
    while begin - left - 1 >= 0 and units[begin - left - 1] == mark:
        left += 1
    right = 0
    while finish + right < len(units) and units[finish + right] == mark:
        right += 1

    both = min(left, right)
    is_on = (both % 2 == 1) if op == "italic" else (both >= need)
    return {"from": begin, "to": finish, "left": left, "right": right, "on": is_on}


def active_at(text: str, start: int, length: int) -> dict:
    """커서 자리에 **지금 걸려 있는 표시** (128). 도구 띠의 눌린 모습이 이것이다."""
    units = to_units(text)
    active = {op: scan_wrap(op, units, start, length)["on"] for op in WRAPS}
    begin, finish = line_range(units, start, length)
    first = from_units(units[begin:finish]).split("\n")[0]
    active["quote"] = first.lstrip(" \t").startswith(">")
    return active


def toggle_wrap(op: str, text: str, start: int, length: int) -> dict:
    """표시의 **개수를 센다** — 별 하나는 기울임, 둘은 굵게, 셋은 둘 다.

    굵게는 둘 이상이면 걸린 것, 기울임은 개수가 홀수면 걸린 것이다. 그래야
    `***글***` 에서 기울임만 풀어 `**글**` 이 되고 다시 걸면 제자리로 돌아온다.
    """
    units = to_units(text)
    mark = to_units(WRAPS[op])[0]
    need = 1 if op == "italic" else 2
    scan = scan_wrap(op, units, start, length)
    begin, finish = scan["from"], scan["to"]
    left, right, is_on = scan["left"], scan["right"], scan["on"]
    new_left = max(0, left - need if is_on else left + need)
    new_right = max(0, right - need if is_on else right + need)

    inner = from_units(units[begin:finish])
    one = from_units([mark])
    piece = one * new_left + inner + one * new_right
    edit_start = begin - left
    edit_length = (finish + right) - edit_start
    return {"start": edit_start, "length": edit_length, "text": piece,
            "selectionStart": edit_start + new_left, "selectionLength": u16len(inner)}


def line_range(units: list[int], start: int, length: int) -> tuple[int, int]:
    newline = to_units("\n")[0]
    begin = max(0, min(start, len(units)))
    finish = max(begin, min(start + length, len(units)))
    while begin > 0 and units[begin - 1] != newline:
        begin -= 1
    while finish < len(units) and units[finish] != newline:
        finish += 1
    if finish > begin and length > 0 and units[finish - 1] == newline:
        finish -= 1
    return begin, finish


def unquote(line: str) -> str:
    lead = line[:len(line) - len(line.lstrip(" \t"))]
    rest = line[len(lead):]
    if not rest.startswith(">"):
        return line
    rest = rest[1:]
    if rest.startswith(" "):
        rest = rest[1:]
    return lead + rest


def toggle_quote(text: str, start: int, length: int) -> dict:
    units = to_units(text)
    begin, finish = line_range(units, start, length)
    lines = from_units(units[begin:finish]).split("\n")
    meaningful = [line for line in lines if line.strip()]
    all_quoted = bool(meaningful) and all(line.strip().startswith(">") for line in meaningful)

    def quoted(line: str) -> str:
        if not line.strip():
            return ">"
        # 이미 인용인 줄에 또 걸지 않는다 — `> > 첫 줄` 이 되면 인용 속 인용이다.
        return line if line.lstrip(" \t").startswith(">") else "> " + line

    changed = [unquote(line) if all_quoted else quoted(line) for line in lines]
    joined = "\n".join(changed)
    return {"start": begin, "length": finish - begin, "text": joined,
            "selectionStart": begin, "selectionLength": u16len(joined)}


def make_table(text: str, start: int, rows: int = 3, columns: int = 3) -> dict:
    units = to_units(text)
    begin, finish = line_range(units, start, 0)
    current = from_units(units[begin:finish])
    empty_line = not current.strip()

    header = "| " + " | ".join(f"제목 {n}" for n in range(1, columns + 1)) + " |"
    rule = "| " + " | ".join(["---"] * columns) + " |"
    body = ["|" + "  |" * columns] * max(1, rows - 1)
    table = "\n".join([header, rule] + body)

    insert_at = begin if empty_line else finish
    before = "" if empty_line else "\n\n"
    after = "\n" if insert_at >= len(units) else "\n\n"
    piece = before + table + after
    lead = u16len(before + "| ")
    return {"start": insert_at, "length": 0, "text": piece,
            "selectionStart": insert_at + lead, "selectionLength": u16len("제목 1")}


def apply_edit(text: str, edit: dict) -> str:
    units = to_units(text)
    head = units[:edit["start"]]
    tail = units[edit["start"] + edit["length"]:]
    return from_units(head) + edit["text"] + from_units(tail)


def check_with_markdown(op: str, applied: str, edit: dict) -> None:
    """**결과가 정말 그 마크다운인가.** 우리 규칙이 맞다고 우기지 않고 파서에게 묻는다."""
    md = make_parser()
    html = md.render(applied)
    # **건 것만 본다.** 푸는 쪽은 표시가 사라지는 것이 맞으므로 파서에게 물을 것이 없다.
    added = u16len(edit["text"]) > edit["length"]
    if op in WRAP_TAG and added:
        inner = from_units(to_units(applied)[edit["selectionStart"]:
                                             edit["selectionStart"] + edit["selectionLength"]])
        if not inner.strip():
            return
        tag = WRAP_TAG[op]
        if f"<{tag}>" not in html:
            raise SystemExit(f"::error::{op} 를 걸었는데 <{tag}> 가 안 나온다: {applied!r}")
    if op == "quote" and ">" in edit["text"] and "<blockquote>" not in html:
        raise SystemExit(f"::error::인용을 걸었는데 blockquote 가 안 나온다: {applied!r}")
    if op == "table" and "<table>" not in html:
        raise SystemExit(f"::error::표를 넣었는데 table 이 안 나온다: {applied!r}")


def build_format_cases() -> list[dict]:
    spec = json.loads(FORMAT_CASES.read_text(encoding="utf-8"))
    out: list[dict] = []
    for case in spec["cases"]:
        op, text = case["op"], case["text"]
        start, length = case["start"], case.get("length", 0)
        if op in WRAPS:
            edit = toggle_wrap(op, text, start, length)
        elif op == "quote":
            edit = toggle_quote(text, start, length)
        elif op == "table":
            edit = make_table(text, start)
        else:
            raise SystemExit(f"::error::모르는 도구 {op!r}")
        applied = apply_edit(text, edit)
        check_with_markdown(op, applied, edit)
        out.append({"name": case["name"], "op": op, "text": text,
                    "start": start, "length": length, "edit": edit, "applied": applied,
                    # **누르기 전과 누른 뒤에 무엇이 걸려 있나** (128). 눌린 모습과 실제
                    # 동작이 갈리지 않는지를 이 두 값이 지킨다.
                    "activeBefore": active_at(text, start, length),
                    "activeAfter": active_at(applied, edit["selectionStart"],
                                             edit["selectionLength"])})
    return out


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--check", action="store_true",
                        help="다시 계산한 것과 커밋된 것이 다르면 실패한다")
    args = parser.parse_args()

    fresh = json.dumps(build(), ensure_ascii=False, indent=2, sort_keys=True) + "\n"

    if args.check:
        if not OUT.exists():
            print(f"::error::{OUT} 가 없습니다. generate.py 를 돌려 커밋하세요.")
            return 1
        current = OUT.read_text(encoding="utf-8")
        if current != fresh:
            print("::error::기댓값이 어긋납니다. `python3 Tools/golden/generate.py` 를 돌리고 커밋하세요.")
            return 1
        loaded = json.loads(current)
        print(f"기댓값 {len(loaded['cases'])}건 · 줄 모양 {len(loaded['styleCases'])}건"
              f" · 들여쓰기 {len(loaded['indentCases'])}건"
              f" · 번호 {len(loaded['renumberCases'])}건"
              f" · 상대 링크 {len(loaded['linkCases'])}건"
              f" · 태그 {len(loaded['tagCases'])}건"
              f" · 옮기기 {len(loaded['rebaseCases'])}건"
              f" · 고정 {len(loaded['pinCases'])}건"
              f" · 편집 도구 {len(loaded['formatCases'])}건 — 커밋된 것과 같습니다.")
        return 0

    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(fresh, encoding="utf-8")
    loaded = json.loads(fresh)
    print(f"{OUT.relative_to(ROOT)} — 사례 {len(loaded['cases'])}건"
          f" · 줄 모양 {len(loaded['styleCases'])}건"
          f" · 들여쓰기 {len(loaded['indentCases'])}건"
          f" · 번호 {len(loaded['renumberCases'])}건"
          f" · 상대 링크 {len(loaded['linkCases'])}건"
          f" · 태그 {len(loaded['tagCases'])}건"
          f" · 옮기기 {len(loaded['rebaseCases'])}건"
          f" · 고정 {len(loaded['pinCases'])}건"
          f" · 편집 도구 {len(loaded['formatCases'])}건")
    return 0


if __name__ == "__main__":
    sys.exit(main())
