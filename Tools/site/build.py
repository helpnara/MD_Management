#!/usr/bin/env python3
"""개인정보 처리방침 **한 장만** 정적 사이트로 만든다.

`/docs` 폴더를 통째로 GitHub Pages 에 올리면 설계 문서가 다 공개된다.
그래서 이 스크립트가 `docs/privacy.md` 하나만 HTML 로 바꾼다.

  SUPPORT_EMAIL=… python3 Tools/site/build.py _site     # 게시용 (site.yml)
  python3 Tools/site/build.py _site --preview            # 미리 보기 — 자리표시자 그대로

**문의 메일은 문서에 적지 않는다** (저장소가 public · CLAUDE.md §5). `docs/privacy.md` 에는
`{{SUPPORT_EMAIL}}` 만 있고, 게시할 때 저장소 변수 `SUPPORT_EMAIL` 로 바꿔 넣는다 (171).

**자리표시자가 남은 채로는 게시하지 않는다.** 2026-09-27 까지 `support@example.com` 이
심사에 낸 지원 URL 에 그대로 게시되고 있었다 — 규칙(주소를 안 적는다)은 지켰는데 **페이지를
채우는 길이 없었다.** 그래서 게시하는 길을 막아 둔다: 주소가 없거나 가짜면 실패한다.
"""

from __future__ import annotations

import html
import os
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]
SOURCE = ROOT / "docs" / "privacy.md"

PLACEHOLDER = "{{SUPPORT_EMAIL}}"
# 게시된 페이지에 **이것이 하나라도 남으면** 실패한다.
LEFTOVERS = (PLACEHOLDER, "example.com", "TODO", "SUPPORT_EMAIL", "--&gt;")
EMAIL = re.compile(r"^[^@\s]+@[^@\s]+\.[^@\s]+$")

PAGE = """<!doctype html>
<html lang="ko">
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>{title}</title>
<style>
  :root {{ color-scheme: light dark; }}
  body {{
    font: 16px/1.7 -apple-system, BlinkMacSystemFont, "Apple SD Gothic Neo",
          "Malgun Gothic", system-ui, sans-serif;
    max-width: 42rem; margin: 0 auto; padding: 2.5rem 1.25rem 4rem;
  }}
  h1 {{ font-size: 1.6rem; letter-spacing: -0.01em; }}
  h2 {{ font-size: 1.15rem; margin-top: 2.2rem; }}
  table {{ border-collapse: collapse; width: 100%; margin: 1rem 0; }}
  th, td {{ text-align: left; padding: 0.5rem 0.6rem; border-bottom: 1px solid #8884; }}
  code {{ font-size: 0.92em; }}
  footer {{ margin-top: 3rem; font-size: 0.85rem; opacity: 0.7; }}
</style>
{body}
<footer>마지막 수정 {updated}</footer>
</html>
"""


def strip_front_matter(text: str) -> tuple[dict, str]:
    lines = text.split("\n")
    if not lines or lines[0].strip() != "---":
        return {}, text
    for i in range(1, len(lines)):
        if lines[i].strip() == "---":
            meta = {}
            for line in lines[1:i]:
                if ":" in line:
                    key, value = line.split(":", 1)
                    meta[key.strip()] = value.strip()
            return meta, "\n".join(lines[i + 1:])
    return {}, text


def inline(text: str) -> str:
    """아주 작은 인라인 마크다운만. 방침 한 장이라 이것으로 충분하다."""
    out = html.escape(text)
    out = re.sub(r"`([^`]+)`", r"<code>\1</code>", out)
    out = re.sub(r"\*\*([^*]+)\*\*", r"<strong>\1</strong>", out)
    out = re.sub(r"\[([^\]]+)\]\(([^)]+)\)", r'<a href="\2">\1</a>', out)
    return out


def render(markdown: str) -> str:
    out: list[str] = []
    in_list = False
    in_table = False

    def close_blocks():
        nonlocal in_list, in_table
        if in_list:
            out.append("</ul>")
            in_list = False
        if in_table:
            out.append("</table>")
            in_table = False

    in_comment = False
    for raw in markdown.split("\n"):
        line = raw.rstrip()
        stripped = line.strip()

        # **주석은 닫힐 때까지 통째로 건너뛴다.** 예전에는 첫 줄만 건너뛰어, 여러 줄 주석의
        # 둘째 줄부터 본문으로 게시됐다 (171 을 고치다 시험이 잡았다).
        if in_comment:
            if "-->" in stripped:
                in_comment = False
            continue
        if stripped.startswith("<!--"):
            in_comment = "-->" not in stripped
            continue
        if not stripped:
            close_blocks()
            continue

        if stripped.startswith("#"):
            close_blocks()
            level = len(stripped) - len(stripped.lstrip("#"))
            out.append(f"<h{level}>{inline(stripped[level:].strip())}</h{level}>")
            continue

        if stripped.startswith("|"):
            cells = [c.strip() for c in stripped.strip("|").split("|")]
            if all(set(c) <= set("-: ") for c in cells):
                continue  # 표 구분선
            if not in_table:
                close_blocks()
                out.append("<table>")
                in_table = True
                out.append("<tr>" + "".join(f"<th>{inline(c)}</th>" for c in cells) + "</tr>")
            else:
                out.append("<tr>" + "".join(f"<td>{inline(c)}</td>" for c in cells) + "</tr>")
            continue

        if stripped.startswith("- "):
            if not in_list:
                close_blocks()
                out.append("<ul>")
                in_list = True
            out.append(f"<li>{inline(stripped[2:])}</li>")
            continue

        close_blocks()
        out.append(f"<p>{inline(stripped)}</p>")

    close_blocks()
    return "\n".join(out)


def fill_contact(page: str, preview: bool) -> str:
    """문의 메일을 넣는다. 게시용인데 주소가 없거나 가짜면 **멈춘다**."""
    if preview:
        print("미리 보기 — 문의 칸은 자리표시자 그대로다. 게시용이 아니다.")
        return page
    email = os.environ.get("SUPPORT_EMAIL", "").strip()
    if not EMAIL.match(email) or "example.com" in email:
        print("::error::저장소 변수 SUPPORT_EMAIL 이 없거나 메일 주소가 아니다 — 게시하지 않는다. "
              "Settings → Secrets and variables → Actions → Variables 에 넣는다 (171).")
        sys.exit(1)
    page = page.replace(PLACEHOLDER, html.escape(email, quote=True))
    left = [bad for bad in LEFTOVERS if bad in page]
    if left:
        print(f"::error::게시할 페이지에 자리표시자가 남았다: {left} — 게시하지 않는다 (171).")
        sys.exit(1)
    return page


def main() -> int:
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    preview = "--preview" in sys.argv[1:]
    destination = pathlib.Path(args[0] if args else "_site")
    meta, body = strip_front_matter(SOURCE.read_text(encoding="utf-8"))

    page = PAGE.format(
        title=meta.get("title", "개인정보 처리방침"),
        body=render(body),
        updated=meta.get("updated", ""),
    )
    page = fill_contact(page, preview)

    privacy = destination / "privacy"
    privacy.mkdir(parents=True, exist_ok=True)
    (privacy / "index.html").write_text(page, encoding="utf-8")

    # 루트로 오면 방침으로 보낸다. **다른 문서는 올리지 않는다.**
    (destination / "index.html").write_text(
        '<!doctype html><meta charset="utf-8">'
        '<meta http-equiv="refresh" content="0; url=privacy/">'
        '<a href="privacy/">개인정보 처리방침</a>\n',
        encoding="utf-8")

    print(f"{destination}/privacy/index.html — {len(page)}바이트")
    return 0


if __name__ == "__main__":
    sys.exit(main())
