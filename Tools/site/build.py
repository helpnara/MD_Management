#!/usr/bin/env python3
"""개인정보 처리방침 **한 장만** 정적 사이트로 만든다.

`/docs` 폴더를 통째로 GitHub Pages 에 올리면 설계 문서가 다 공개된다.
그래서 이 스크립트가 `docs/privacy.md` 하나만 HTML 로 바꾼다.

  python3 Tools/site/build.py _site
"""

from __future__ import annotations

import html
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]
SOURCE = ROOT / "docs" / "privacy.md"

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

    for raw in markdown.split("\n"):
        line = raw.rstrip()
        stripped = line.strip()

        if stripped.startswith("<!--"):
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


def main() -> int:
    destination = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else "_site")
    meta, body = strip_front_matter(SOURCE.read_text(encoding="utf-8"))

    page = PAGE.format(
        title=meta.get("title", "개인정보 처리방침"),
        body=render(body),
        updated=meta.get("updated", ""),
    )

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
