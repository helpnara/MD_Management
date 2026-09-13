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
OUT = ROOT / "Packages" / "Core" / "Tests" / "CoreTests" / "Golden" / "expected.json"

NOTE_EXTS = {"md", "markdown", "txt"}
MARKDOWN_EXTS = {"md", "markdown"}


# ── 링크 뽑기 — markdown-it-py 로 (swift-markdown 과 다른 구현) ────────────────

def extract_links(text: str) -> list[dict]:
    """머리말을 뗀 본문에서 이미지와 링크를 나온 순서대로."""
    _, body = split_front_matter(text)
    md = MarkdownIt("commonmark")
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


def note_title(text: str, file_name: str) -> str:
    matter = parse_front_matter(text)
    if matter and matter["title"]:
        return matter["title"]
    _, body = split_front_matter(text)
    for line in body.split("\n"):
        stripped = line.strip()
        if stripped.startswith("#"):
            heading = stripped.lstrip("#").strip()
            if heading:
                return heading
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
        })

    return {
        "_generator": "Tools/golden/generate.py (markdown-it-py + PyYAML)",
        "_warning": "손으로 고치지 마세요. generate.py 를 다시 돌리세요.",
        "cases": out_cases,
    }


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
        print(f"기댓값 {len(json.loads(current)['cases'])}건 — 커밋된 것과 같습니다.")
        return 0

    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(fresh, encoding="utf-8")
    print(f"{OUT.relative_to(ROOT)} — 사례 {len(json.loads(fresh)['cases'])}건")
    return 0


if __name__ == "__main__":
    sys.exit(main())
