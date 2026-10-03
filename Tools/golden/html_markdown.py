"""206 · 207 — **붙여넣은 HTML 전체를 마크다운으로.** Swift `HTMLMarkdown` 의 쌍둥이.

159 는 HTML 에서 **표 하나만** 꺼내 그것만 붙였다 — 표가 든 긴 글을 붙이면 나머지 글이 모두 사라졌다
(2026-10-02 사용자 — *아이폰 메모에서 표가 포함된 긴 글을 복사해서 붙여 넣으면 표만 변환되고 나머지 글을
모두 날라가는데 이 부분은 반드시 수정*). 이제 **글 전체를 순서대로** 읽어 바꾼다.

**같은 규칙을 두 번 적는다.** Swift 와 파이썬이 따로 셈해서 같은 글을 내야 한다. 그래서 정규식 · 파서
라이브러리를 쓰지 않고 **한 글자씩** 훑는다 — 라이브러리마다 다른 자리를 피한다. 글자는 유니코드
스칼라(코드 포인트) 단위로 본다 (Swift 의 `Character` 는 `\\r\\n` 을 한 자로 보므로 거기서도 스칼라로 본다).

규칙 (Swift 와 같다):
- 태그 · 속성 · 엔터티(`&amp;` · `&#123;` · `&#x1F;` · `&nbsp;` …)를 읽어 나무를 세운다. 짝이 없는 닫는 태그는 버린다.
- `<style>` 의 `태그.이름 {…}` · `.이름 {…}` 규칙과 `style=""` 를 읽는다 — 아이폰 메모는 굵게 · 글자 크기를 이렇게 싣는다.
- 블록: 제목(h1~h6, 그리고 **글자가 본문보다 큰 문단**) · 문단 · 목록(겹침 · 번호 · 체크) · 표 · 인용 · 코드 · 가로줄.
- 글자 속: 굵게 · 기울임 · 취소선 · 고정폭(코드) · 링크. 밑줄은 마크다운에 없어 글자만 남긴다.
- 사진(`<img>` · 글 속 U+FFFC)은 **U+FFFC 한 자**로 자리만 남긴다 — 앱이 파일로 저장한 뒤 링크로 바꾼다 (207).
"""
from __future__ import annotations

import unicodedata

VOID = {"area", "base", "br", "col", "embed", "hr", "img", "input", "link", "meta", "param",
        "source", "track", "wbr"}
RAW = {"script", "style", "textarea", "title", "xmp"}
SKIP = {"head", "script", "style", "title", "meta", "link", "noscript", "template", "svg", "math",
        "iframe", "button", "select", "option", "textarea", "xmp"}
BLOCK = {"address", "article", "aside", "blockquote", "body", "center", "dd", "details", "dialog", "div",
         "dl", "dt", "fieldset", "figcaption", "figure", "footer", "form", "h1", "h2", "h3", "h4", "h5",
         "h6", "header", "hr", "html", "li", "main", "nav", "ol", "p", "pre", "section", "summary",
         "table", "tbody", "td", "tfoot", "th", "thead", "tr", "ul"}
HEADINGS = {"h1": 1, "h2": 2, "h3": 3, "h4": 4, "h5": 5, "h6": 6}
SPACE = {" ", "\t", "\n", "\r", "\f"}
NBSP = " "
OBJECT = "￼"
NAMED = {"amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'", "nbsp": NBSP}


# ── 엔터티 ────────────────────────────────────────────────────────────────

def _is_ascii_letter(c: str) -> bool:
    return ("a" <= c <= "z") or ("A" <= c <= "Z")


def _is_ascii_digit(c: str) -> bool:
    return "0" <= c <= "9"


def _is_hex(c: str) -> bool:
    return _is_ascii_digit(c) or ("a" <= c <= "f") or ("A" <= c <= "F")


def decode_entities(text: str) -> str:
    if "&" not in text:
        return text
    out = []
    i, n = 0, len(text)
    while i < n:
        c = text[i]
        if c != "&":
            out.append(c)
            i += 1
            continue
        # `;` 까지 32자 안에서만 본다.
        j = i + 1
        while j < n and j - i <= 32 and text[j] != ";" and text[j] != "&":
            j += 1
        if j < n and text[j] == ";" and j > i + 1:
            body = text[i + 1:j]
            got = _entity(body)
            if got is not None:
                out.append(got)
                i = j + 1
                continue
        out.append("&")
        i += 1
    return "".join(out)


def _entity(body: str):
    if body.startswith("#x") or body.startswith("#X"):
        digits = body[2:]
        if not digits or len(digits) > 8 or not all(_is_hex(c) for c in digits):
            return None
        value = int(digits, 16)
    elif body.startswith("#"):
        digits = body[1:]
        if not digits or len(digits) > 8 or not all(_is_ascii_digit(c) for c in digits):
            return None
        value = int(digits)
    else:
        return NAMED.get(body)
    if value <= 0 or value > 0x10FFFF or 0xD800 <= value <= 0xDFFF:
        return None
    return chr(value)


# ── 글자를 태그로 ──────────────────────────────────────────────────────────

def _is_name_char(c: str) -> bool:
    return _is_ascii_letter(c) or _is_ascii_digit(c) or c in "-:"


def _find(s: str, needle: str, start: int) -> int:
    """`s` 에서 `needle` 이 처음 나오는 자리 (없으면 -1). 한 글자씩 견준다."""
    n, m = len(s), len(needle)
    i = start
    while i + m <= n:
        if s[i:i + m] == needle:
            return i
        i += 1
    return -1


def _find_raw_end(s: str, name: str, start: int) -> int:
    """`</이름` (아스키 대소문자 무시) 이 처음 나오는 자리."""
    n, m = len(s), len(name)
    i = start
    while i + 2 + m <= n:
        if s[i] == "<" and s[i + 1] == "/" and _ascii_lower(s[i + 2:i + 2 + m]) == name:
            return i
        i += 1
    return -1


def tokenize(s: str) -> list:
    tokens = []
    text: list[str] = []
    i, n = 0, len(s)

    def flush():
        if text:
            tokens.append(("text", "".join(text)))
            text.clear()

    while i < n:
        c = s[i]
        if c != "<":
            text.append(c)
            i += 1
            continue
        if s[i:i + 4] == "<!--":
            j = _find(s, "-->", i + 4)
            i = n if j < 0 else j + 3
            continue
        if i + 1 < n and s[i + 1] in "!?":
            j = _find(s, ">", i + 2)
            i = n if j < 0 else j + 1
            continue
        k = i + 1
        closing = False
        if k < n and s[k] == "/":
            closing = True
            k += 1
        if not (k < n and _is_ascii_letter(s[k])):
            text.append("<")
            i += 1
            continue
        start = k
        while k < n and _is_name_char(s[k]):
            k += 1
        name = _ascii_lower(s[start:k])
        attrs: dict[str, str] = {}
        self_close = False
        done = False
        while k < n:
            while k < n and s[k] in SPACE:
                k += 1
            if k >= n:
                break
            if s[k] == ">":
                k += 1
                done = True
                break
            if s[k] == "/":
                self_close = True
                k += 1
                continue
            a = k
            while k < n and s[k] not in SPACE and s[k] not in "=>/":
                k += 1
            if k == a:
                k += 1          # 이름으로 못 읽는 글자 하나 — 건너뛴다
                continue
            attr = _ascii_lower(s[a:k])
            while k < n and s[k] in SPACE:
                k += 1
            value = ""
            if k < n and s[k] == "=":
                k += 1
                while k < n and s[k] in SPACE:
                    k += 1
                if k < n and s[k] in "\"'":
                    quote = s[k]
                    k += 1
                    v = k
                    while k < n and s[k] != quote:
                        k += 1
                    value = s[v:k]
                    if k < n:
                        k += 1
                else:
                    v = k
                    while k < n and s[k] not in SPACE and s[k] != ">":
                        k += 1
                    value = s[v:k]
            if attr not in attrs:
                attrs[attr] = decode_entities(value)
        if not done:
            text.append("<")
            i += 1
            continue
        flush()
        if closing:
            tokens.append(("end", name))
            i = k
            continue
        tokens.append(("start", name, attrs, self_close))
        i = k
        if name in RAW and not self_close:
            j = _find_raw_end(s, name, i)
            end = n if j < 0 else j
            tokens.append(("raw", s[i:end]))
            i = end
    flush()
    return tokens


class El:
    __slots__ = ("name", "attrs", "children")

    def __init__(self, name: str, attrs: dict, children: list):
        self.name = name
        self.attrs = attrs
        self.children = children


def build_tree(s: str) -> El:
    root = El("#root", {}, [])
    stack = [root]
    for tok in tokenize(s):
        kind = tok[0]
        if kind == "start":
            name, attrs, self_close = tok[1], tok[2], tok[3]
            top = stack[-1].name
            if (name == "li" and top == "li") or (name == "p" and top == "p") \
                    or (name in ("td", "th") and top in ("td", "th")) or (name == "tr" and top == "tr"):
                stack.pop()
            el = El(name, attrs, [])
            stack[-1].children.append(el)
            if name not in VOID and not self_close:
                stack.append(el)
        elif kind == "end":
            name = tok[1]
            for index in range(len(stack) - 1, 0, -1):
                if stack[index].name == name:
                    del stack[index:]
                    break
        elif kind == "text":
            stack[-1].children.append(decode_entities(tok[1]))
        else:                   # raw — 글자 그대로 (CSS)
            stack[-1].children.append(tok[1])
    return root


# ── CSS ────────────────────────────────────────────────────────────────────

def _strip_comments(css: str) -> str:
    out = []
    i, n = 0, len(css)
    while i < n:
        if css[i:i + 2] == "/*":
            j = _find(css, "*/", i + 2)
            i = n if j < 0 else j + 2
            continue
        out.append(css[i])
        i += 1
    return "".join(out)


def _trim(s: str) -> str:
    a, b = 0, len(s)
    while a < b and s[a] in SPACE:
        a += 1
    while b > a and s[b - 1] in SPACE:
        b -= 1
    return s[a:b]


def _ascii_lower(s: str) -> str:
    return "".join(c.lower() if "A" <= c <= "Z" else c for c in s)


def parse_declarations(text: str) -> list:
    out = []
    for part in text.split(";"):
        colon = part.find(":")
        if colon < 0:
            continue
        prop = _ascii_lower(_trim(part[:colon]))
        value = _ascii_lower(_trim(part[colon + 1:]))
        if prop:
            out.append((prop, value))
    return out


def _class_of_selector(sel: str):
    """`p.p1` · `.s2` 꼴만 — 이름이 하나뿐인 갈래."""
    dot = sel.find(".")
    if dot < 0:
        return None
    tag, cls = sel[:dot], sel[dot + 1:]
    if not all(_is_ascii_letter(c) or _is_ascii_digit(c) for c in tag):
        return None
    if not cls or not all(_is_ascii_letter(c) or _is_ascii_digit(c) or c in "_-" for c in cls):
        return None
    return cls


def parse_css(css: str) -> dict:
    rules: dict[str, list] = {}
    for chunk in _strip_comments(css).split("}"):
        brace = chunk.find("{")
        if brace < 0:
            continue
        decls = parse_declarations(chunk[brace + 1:])
        for sel in chunk[:brace].split(","):
            cls = _class_of_selector(_trim(sel))
            if cls is not None:
                rules.setdefault(cls, []).extend(decls)
    return rules


def _collect_css(node, out: list):
    for ch in node.children:
        if isinstance(ch, El):
            if ch.name == "style":
                out.extend(c for c in ch.children if isinstance(c, str))
            else:
                _collect_css(ch, out)


def _split_space(s: str) -> list:
    out, cur = [], []
    for c in s:
        if c in SPACE:
            if cur:
                out.append("".join(cur))
                cur = []
        else:
            cur.append(c)
    if cur:
        out.append("".join(cur))
    return out


class Doc:
    def __init__(self, root: El):
        self.root = root
        css: list[str] = []
        _collect_css(root, css)
        self.rules = parse_css("\n".join(css))
        self._block_memo: dict[int, bool] = {}
        self.list_counter = 0
        self.cell_depth = 0         # 표 칸 안인가 — 칸 안의 표는 글자만 (159 와 같다)
        self.item_depth = 0         # 목록 항목 안인가

    def decls(self, el: El) -> dict:
        d: dict[str, str] = {}
        for cls in _split_space(el.attrs.get("class", "")):
            for prop, value in self.rules.get(cls, []):
                d[prop] = value
        for prop, value in parse_declarations(el.attrs.get("style", "")):
            d[prop] = value
        return d

    def has_block(self, el: El) -> bool:
        key = id(el)
        if key in self._block_memo:
            return self._block_memo[key]
        found = False
        for ch in el.children:
            if isinstance(ch, El) and ch.name not in SKIP and (ch.name in BLOCK or self.has_block(ch)):
                found = True
                break
        self._block_memo[key] = found
        return found

    def is_block(self, el: El) -> bool:
        return el.name in BLOCK or self.has_block(el)


# ── 스타일 ──────────────────────────────────────────────────────────────────

def _number_with_unit(v: str):
    """처음 나오는 `숫자px` · `숫자pt` 의 숫자."""
    n = len(v)
    i = 0
    while i < n:
        if _is_ascii_digit(v[i]) and (i == 0 or not (_is_ascii_digit(v[i - 1]) or v[i - 1] == ".")):
            j = i
            while j < n and _is_ascii_digit(v[j]):
                j += 1
            if j + 1 < n and v[j] == "." and _is_ascii_digit(v[j + 1]):
                j += 1
                while j < n and _is_ascii_digit(v[j]):
                    j += 1
            number = v[i:j]
            k = j
            while k < n and v[k] in SPACE:
                k += 1
            if v[k:k + 2] in ("px", "pt"):
                return float(number)
            i = j
            continue
        i += 1
    return None


def font_size(d: dict):
    if "font-size" in d:
        return _number_with_unit(d["font-size"])
    if "font" in d:
        return _number_with_unit(d["font"])
    return None


def css_bold(d: dict):
    w = d.get("font-weight")
    if w in ("bold", "bolder", "600", "700", "800", "900"):
        return True
    if w in ("normal", "lighter", "100", "200", "300", "400", "500"):
        return False
    family = d.get("font-family", "") + " " + d.get("font", "")
    if "bold" in family:
        return True
    return None


def css_italic(d: dict):
    s = d.get("font-style")
    if s in ("italic", "oblique"):
        return True
    if s == "normal":
        return False
    if "italic" in d.get("font", ""):
        return True
    return None


def css_strike(d: dict):
    t = d.get("text-decoration", "") + " " + d.get("text-decoration-line", "")
    if "line-through" in t:
        return True
    if _trim(t) == "none":
        return False
    return None


MONO = ("menlo", "courier", "monaco", "consolas", "monospace", "sfmono", "sf mono")


def css_mono(d: dict) -> bool:
    family = d.get("font-family", "") + " " + d.get("font", "")
    return any(m in family for m in MONO)


class Style:
    """`code` — 고정폭으로 그린다 (`<code>` 든 고정폭 글꼴이든). `mono` — **글꼴**이 고정폭이다 (메모의 고정폭 문단)."""
    __slots__ = ("bold", "italic", "strike", "code", "mono", "href")

    def __init__(self, bold=False, italic=False, strike=False, code=False, mono=False, href=None):
        self.bold, self.italic, self.strike, self.code, self.mono, self.href = bold, italic, strike, code, mono, href

    def copy(self) -> "Style":
        return Style(self.bold, self.italic, self.strike, self.code, self.mono, self.href)


def style_of(doc: Doc, el: El, parent: Style) -> Style:
    s = parent.copy()
    n = el.name
    if n in ("b", "strong"):
        s.bold = True
    if n in ("i", "em", "cite", "dfn"):
        s.italic = True
    if n in ("s", "strike", "del"):
        s.strike = True
    if n in ("code", "tt", "kbd", "samp"):
        s.code = True
    if n == "a":
        href = _trim(el.attrs.get("href", ""))
        if href and not _ascii_lower(href).startswith("javascript:"):
            s.href = href
    d = doc.decls(el)
    b = css_bold(d)
    if b is not None:
        s.bold = b
    i = css_italic(d)
    if i is not None:
        s.italic = i
    t = css_strike(d)
    if t is not None:
        s.strike = t
    if css_mono(d):
        s.code = True
        s.mono = True
    return s


# ── 글자 줄기 (run) ─────────────────────────────────────────────────────────

class Run:
    __slots__ = ("text", "style", "br")

    def __init__(self, text: str, style: Style | None, br: bool = False):
        self.text, self.style, self.br = text, style, br


def collapse(text: str) -> str:
    out = []
    space = False
    for c in text:
        if c in SPACE:
            if not space:
                out.append(" ")
            space = True
        else:
            out.append(c)
            space = False
    return "".join(out)


class RunState:
    def __init__(self):
        self.last_space = True


def inline_runs(doc: Doc, nodes: list, style: Style, state: RunState, out: list):
    for ch in nodes:
        if isinstance(ch, str):
            text = collapse(ch)
            if text.startswith(" ") and state.last_space:
                text = text[1:]
            if not text:
                continue
            # 글 속 U+FFFC 는 사진 자리 — 따로 떼어 둔다.
            piece = []
            for c in text:
                if c == OBJECT:
                    if piece:
                        out.append(Run("".join(piece), style))
                        piece = []
                    out.append(Run(OBJECT, style))
                else:
                    piece.append(c)
            if piece:
                out.append(Run("".join(piece), style))
            state.last_space = text.endswith(" ")
            continue
        if ch.name in SKIP or ch.name == "input":
            continue
        if ch.name == "br":
            out.append(Run("\n", None, br=True))
            state.last_space = True
            continue
        if ch.name == "img":
            out.append(Run(OBJECT, style))
            state.last_space = False
            continue
        inline_runs(doc, ch.children, style_of(doc, ch, style), state, out)


def _is_space(c: str) -> bool:
    return c == " " or c == NBSP


def _tokens(style: Style, drop_bold: bool) -> list:
    out = []
    if style.href is not None:
        out.append(("link", style.href))
    if style.bold and not drop_bold:
        out.append(("bold", None))
    if style.italic:
        out.append(("italic", None))
    if style.strike:
        out.append(("strike", None))
    if style.code:
        out.append(("code", None))
    return out


def _link_target(href: str) -> str:
    if any(c in href for c in " ()<>"):
        return "<" + href.replace("<", "%3C").replace(">", "%3E") + ">"
    return href


def emit(runs: list, drop_bold: bool = False) -> list:
    """줄기들을 마크다운 줄들로. 강조 기호는 **글자에 붙인다** — 빈칸은 기호 밖으로 낸다."""
    out: list[str] = []
    stack: list = []            # (token, opener)
    pending = ""

    def close_to(k: int):
        nonlocal stack
        while len(stack) > k:
            token, opener = stack.pop()
            kind = token[0]
            if kind == "link":
                out.append("](" + _link_target(token[1]) + ")")
            elif kind == "bold":
                out.append("**")
            elif kind == "italic":
                out.append("*")
            elif kind == "strike":
                out.append("~~")
            else:
                out.append(" ``" if opener == "`` " else "`")

    for run in runs:
        if run.br:
            close_to(0)
            out.append(pending)
            pending = ""
            out.append("\n")
            continue
        text = run.text
        a, b = 0, len(text)
        while a < b and _is_space(text[a]):
            a += 1
        while b > a and _is_space(text[b - 1]):
            b -= 1
        core = text[a:b]
        if not core:
            pending += text
            continue
        want = _tokens(run.style, drop_bold)
        k = 0
        while k < len(stack) and k < len(want) and stack[k][0] == want[k]:
            k += 1
        close_to(k)
        out.append(pending + text[:a])
        pending = ""
        for token in want[k:]:
            kind = token[0]
            if kind == "link":
                opener = "["
            elif kind == "bold":
                opener = "**"
            elif kind == "italic":
                opener = "*"
            elif kind == "strike":
                opener = "~~"
            else:
                opener = "`` " if "`" in core else "`"
            out.append(opener)
            stack.append((token, opener))
        out.append(core)
        pending = text[b:]
    close_to(0)
    out.append(pending)
    lines = []
    for line in "".join(out).split("\n"):
        line = line.replace(NBSP, " ")
        a, b = 0, len(line)
        while a < b and line[a] == " ":
            a += 1
        while b > a and line[b - 1] == " ":
            b -= 1
        lines.append(line[a:b])
    return lines


# ── 블록 ────────────────────────────────────────────────────────────────────

class Block:
    __slots__ = ("kind", "lines", "group", "runs", "from_para")

    def __init__(self, kind: str, lines: list, group: str, runs=None, from_para=False):
        self.kind, self.lines, self.group, self.runs, self.from_para = kind, lines, group, runs, from_para


def _has_content(runs: list) -> bool:
    return any(not r.br and any(not _is_space(c) for c in r.text) for r in runs)


def flush(doc: Doc, nodes: list, style: Style) -> list:
    if not nodes:
        return []
    runs: list[Run] = []
    inline_runs(doc, nodes, style, RunState(), runs)
    if not _has_content(runs):
        return [Block("blank", [], "blank")] if any(r.br for r in runs) else []
    content = [r for r in runs if not r.br and any(not _is_space(c) for c in r.text)]
    if doc.cell_depth == 0 and doc.item_depth == 0 and all(r.style.mono and r.text != OBJECT for r in content):
        # 고정폭 **글꼴**만 든 문단 (메모의 고정폭) — 코드 줄로. 여러 문단이 이어지면 한 덩어리로 모은다.
        # 표 칸 · 목록 항목 안에서는 하지 않는다 — 거기서는 글 속 코드로 둔다.
        raw = "".join("\n" if r.br else r.text for r in runs)
        lines = [_rstrip_space(l.replace(NBSP, " ")) for l in raw.split("\n")]
        while lines and lines[0] == "":
            lines.pop(0)
        while lines and lines[-1] == "":
            lines.pop()
        return [Block("code", lines, "code", from_para=True)]
    return [Block("para", emit(runs), "text", runs=runs)]


def _rstrip_space(s: str) -> str:
    b = len(s)
    while b > 0 and s[b - 1] in (" ", "\t"):
        b -= 1
    return s[:b]


def container_blocks(doc: Doc, el: El, style: Style) -> list:
    out: list[Block] = []
    buf: list = []
    for ch in el.children:
        if isinstance(ch, str):
            buf.append(ch)
            continue
        if ch.name in SKIP:
            continue
        if doc.is_block(ch):
            out += flush(doc, buf, style)
            buf = []
            out += block_of(doc, ch, style)
        else:
            buf.append(ch)
    out += flush(doc, buf, style)
    return out


def text_content(doc: Doc, el: El) -> str:
    parts: list[str] = []

    def walk(node):
        for ch in node.children:
            if isinstance(ch, str):
                parts.append(ch)
            elif ch.name not in SKIP:
                walk(ch)

    walk(el)
    return _trim(collapse("".join(parts)))


def block_size(doc: Doc, el: El):
    own = font_size(doc.decls(el))
    whole = text_content(doc, el)
    best = own

    def walk(node):
        nonlocal best
        for ch in node.children:
            if isinstance(ch, El) and ch.name not in SKIP:
                size = font_size(doc.decls(ch))
                if size is not None and text_content(doc, ch) == whole:
                    if best is None or size > best:
                        best = size
                walk(ch)

    walk(el)
    return best


def body_size(doc: Doc):
    counts: dict[float, int] = {}

    def walk(node):
        for ch in node.children:
            if not isinstance(ch, El) or ch.name in SKIP:
                continue
            if ch.name in ("p", "div", "li") and not doc.has_block(ch) and text_content(doc, ch):
                size = block_size(doc, ch)
                if size is not None:
                    counts[size] = counts.get(size, 0) + 1
            walk(ch)

    walk(doc.root)
    if not counts:
        return None
    best = max(counts.values())
    return min(size for size, count in counts.items() if count == best)


def heading_level(doc: Doc, el: El, runs: list):
    if doc.body is None:
        return None
    size = block_size(doc, el)
    if size is None:
        return None
    ratio = size / doc.body
    if ratio >= 1.45:
        return 1
    if ratio >= 1.18:
        return 2
    content = [r for r in runs if not r.br and any(not _is_space(c) for c in r.text)]
    if ratio >= 1.05 and content and all(r.style.bold for r in content):
        return 3
    return None


def heading_block(level: int, runs: list) -> list:
    lines = [l for l in emit([r for r in runs], drop_bold=True) if l]
    text = " ".join(lines)
    if not text:
        return []
    return [Block("heading", ["#" * level + " " + text], "heading")]


def block_of(doc: Doc, el: El, style: Style) -> list:
    s = style_of(doc, el, style)
    n = el.name
    if n in HEADINGS:
        runs: list[Run] = []
        inline_runs(doc, el.children, s, RunState(), runs)
        runs = [Run(" ", s) if r.br else r for r in runs]
        return heading_block(HEADINGS[n], runs)
    if n in ("ul", "ol"):
        doc.list_counter += 1
        return list_blocks(doc, el, s, "", "list%d" % doc.list_counter)
    if n == "table":
        if doc.cell_depth > 0:
            text = text_content(doc, el)
            return [Block("para", [text], "text", runs=[])] if text else []
        return table_blocks(doc, el, s)
    if n == "pre":
        return pre_block(doc, el)
    if n == "blockquote":
        text = join_blocks(container_blocks(doc, el, s))
        if not text:
            return []
        return [Block("quote", ["> " + l if l else ">" for l in text.split("\n")], "quote")]
    if n == "hr":
        return [Block("hr", ["---"], "hr")]
    blocks = container_blocks(doc, el, s)
    if n in ("p", "div") and len(blocks) == 1 and blocks[0].kind == "para" and len(blocks[0].lines) == 1:
        level = heading_level(doc, el, blocks[0].runs)
        if level is not None:
            return heading_block(level, blocks[0].runs)
    return blocks


def pre_block(doc: Doc, el: El) -> list:
    parts: list[str] = []

    def walk(node):
        for ch in node.children:
            if isinstance(ch, str):
                parts.append(ch)
            elif ch.name == "br":
                parts.append("\n")
            elif ch.name == "img":
                parts.append(OBJECT)
            elif ch.name not in SKIP:
                walk(ch)

    walk(el)
    raw = "".join(parts).replace("\r\n", "\n").replace("\r", "\n").replace(NBSP, " ")
    lines = [_rstrip_space(l) for l in raw.split("\n")]
    while lines and lines[0] == "":
        lines.pop(0)
    while lines and lines[-1] == "":
        lines.pop()
    if not lines:
        return []
    fence = "~~~" if any("```" in l for l in lines) else "```"
    return [Block("code", [fence] + lines + [fence], "code")]


CHECKED = "☑☒✅✓✔"       # ☑ ☒ ✅ ✓ ✔
UNCHECKED = "☐□◻"                  # ☐ □ ◻
BULLETS = "•◦▪▫●○■–—·"   # • ◦ ▪ ▫ ● ○ ■ – — ·


def _strip_glyphs(text: str, ordered: bool):
    """항목 글 앞의 글머리 · 체크 글자를 뗀다. (남은 글, 체크 — 없으면 None)."""
    check = None
    t = text
    if t and (t[0] in CHECKED or t[0] in UNCHECKED):
        check = t[0] in CHECKED
        t = t[1:]
        if t.startswith("️"):
            t = t[1:]
        t = t.lstrip(" ")
        return t, check
    if len(t) >= 2 and t[0] in BULLETS and t[1] in (" ", "\t"):
        return t[2:].lstrip(" \t"), None
    if ordered:
        j = 0
        while j < len(t) and _is_ascii_digit(t[j]):
            j += 1
        if 0 < j and j + 1 < len(t) and t[j] in ".)" and t[j + 1] in (" ", "\t"):
            return t[j + 2:].lstrip(" \t"), None
    return t, None


def _checkbox(doc: Doc, li: El):
    def walk(node):
        for ch in node.children:
            if isinstance(ch, El):
                if ch.name in ("ul", "ol"):
                    continue
                if ch.name == "input" and _ascii_lower(ch.attrs.get("type", "")) == "checkbox":
                    return "checked" in ch.attrs
                got = walk(ch)
                if got is not None:
                    return got
        return None
    return walk(li)


def _start_number(el: El) -> int:
    v = _trim(el.attrs.get("start", ""))
    j = 0
    while j < len(v) and j < 9 and _is_ascii_digit(v[j]):
        j += 1
    return int(v[:j]) if j else 1


def list_blocks(doc: Doc, el: El, style: Style, indent: str, group: str) -> list:
    ordered = el.name == "ol"
    number = _start_number(el)
    out: list[Block] = []
    stray: list = []
    last_width = 2

    def items_from(content: El | None, nodes: list):
        nonlocal number, last_width
        holder = content if content is not None else El("li", {}, nodes)
        s = style_of(doc, holder, style)
        body = El(holder.name, holder.attrs,
                  [c for c in holder.children if not (isinstance(c, El) and c.name in ("ul", "ol"))])
        nested = [c for c in holder.children if isinstance(c, El) and c.name in ("ul", "ol")]
        doc.item_depth += 1
        blocks = [b for b in container_blocks(doc, body, s) if b.kind != "blank"]
        doc.item_depth -= 1
        lines: list[str] = []
        for b in blocks:
            lines += b.lines
        first = lines[0] if lines else ""
        rest = lines[1:]
        text, check = _strip_glyphs(first, ordered)
        box = _checkbox(doc, holder)
        if box is not None:
            check = box
        marker = (str(number) + ". ") if ordered else "- "
        width = len(marker)
        last_width = width
        number += 1
        if check is not None:
            marker += "[x] " if check else "[ ] "
        item = [_rstrip_space(indent + marker + text)]
        pad = indent + " " * width
        item += [pad + l if l else "" for l in rest]
        out.append(Block("item", item, group))
        for sub in nested:
            out.extend(list_blocks(doc, sub, s, pad, group))

    def flush_stray():
        nonlocal stray
        if any(not isinstance(c, str) or _trim(collapse(c)) for c in stray):
            items_from(None, stray)
        stray = []

    for ch in el.children:
        if isinstance(ch, El) and ch.name == "li":
            flush_stray()
            items_from(ch, [])
        elif isinstance(ch, El) and ch.name in ("ul", "ol"):
            flush_stray()
            out.extend(list_blocks(doc, ch, style, indent + " " * last_width, group))
        elif isinstance(ch, El) and ch.name in SKIP:
            continue
        else:
            stray.append(ch)
    flush_stray()
    return out


def escape_cell(text: str) -> str:
    out = []
    for c in text:
        if c == "|":
            out.append("\\")
        out.append(c)
    return "".join(out).replace("\r\n", "\n").replace("\n", "<br>")


def table_blocks(doc: Doc, el: El, style: Style) -> list:
    rows = []

    def find_rows(node):
        for ch in node.children:
            if not isinstance(ch, El) or ch.name in SKIP or ch.name == "table":
                continue
            if ch.name == "tr":
                cells, headers = [], 0
                for cell in ch.children:
                    if isinstance(cell, El) and cell.name in ("td", "th"):
                        s = style_of(doc, cell, style)
                        lines = []
                        doc.cell_depth += 1
                        inner = container_blocks(doc, cell, s)
                        doc.cell_depth -= 1
                        for b in inner:
                            if b.kind != "blank":
                                lines += b.lines
                        cells.append(escape_cell(_trim("\n".join(lines))))
                        headers += 1 if cell.name == "th" else 0
                if cells:
                    rows.append((cells, headers == len(cells)))
            else:
                find_rows(ch)

    find_rows(el)
    if not rows:
        return []
    width = max(len(r[0]) for r in rows)
    # **첫 줄이 곧 머리줄이다** (2026-10-03 사용자 — 빈 머리줄 대신 첫 줄을 머리줄로). 메모의 표는 `<th>` 없이 첫 줄을
    # 머리처럼 쓴다. 159 는 *자료를 머리줄로 올리지 않는다* 며 빈 머리줄을 세웠는데, 표 맨 위에 빈 줄이 하나 더 생겼다.
    head, body = rows[0], rows[1:]

    def line(cells):
        padded = cells + [""] * (width - len(cells))
        return "| " + " | ".join(c if c else " " for c in padded) + " |"

    lines = [line(head[0]), "|" + " --- |" * width] + [line(r[0]) for r in body]
    return [Block("table", lines, "table")]


def join_blocks(blocks: list) -> str:
    merged: list[Block] = []
    for b in blocks:
        if b.kind == "code" and b.from_para and merged and merged[-1].kind == "code" and merged[-1].from_para:
            merged[-1] = Block("code", merged[-1].lines + b.lines, "code", from_para=True)
            continue
        merged.append(b)
    out: list[str] = []
    prev = None
    blank = False
    for b in merged:
        if b.kind == "blank":
            if prev is not None:
                blank = True
            continue
        lines = b.lines
        if b.kind == "code" and b.from_para:
            fence = "~~~" if any("```" in l for l in lines) else "```"
            lines = [fence] + lines + [fence]
        if not lines:
            continue
        # 같은 목록의 항목끼리만 붙인다. 문단과 문단 사이도 빈 줄 하나 — 메모는 줄마다 `<p>` 이고, 한 줄 띄움으로
        # 이으면 읽기 화면에서 한 문단으로 붙는다 (표준 · 199). 빌드 74 사용자 진단에서 본 실제 메모 모양이다.
        together = b.group == prev.group and b.kind == "item" if prev is not None else False
        if prev is not None and (blank or not together):
            out.append("")
        blank = False
        out += lines
        prev = b
    return "\n".join(out)


def convert(html: str):
    """HTML 을 마크다운으로. 글이 없으면 None. 사진 자리는 U+FFFC 로 남는다."""
    doc = Doc(build_tree(html))
    doc.body = body_size(doc)
    text = join_blocks(container_blocks(doc, doc.root, Style()))
    # 앞뒤 빈 줄을 뗀다.
    lines = text.split("\n")
    while lines and not lines[0].strip(" "):
        lines.pop(0)
    while lines and not lines[-1].strip(" "):
        lines.pop()
    out = "\n".join(lines)
    return out if out else None


def image_slots(html: str) -> list:
    """사진 자리 — 문서 차례대로 `<img>` 와 글 속 U+FFFC. `convert` 의 U+FFFC 와 수 · 차례가 같다."""
    root = build_tree(html)
    out = []

    def walk(node):
        for ch in node.children:
            if isinstance(ch, str):
                out.extend({"src": "", "alt": ""} for c in ch if c == OBJECT)
            elif ch.name not in SKIP:
                if ch.name == "img":
                    out.append({"src": _trim(ch.attrs.get("src", "")), "alt": _trim(ch.attrs.get("alt", ""))})
                walk(ch)

    walk(root)
    return out


def fill_images(markdown: str, links: list) -> str:
    """U+FFFC 를 차례로 링크로 (없으면 지운다). 수가 안 맞으면 모두 지운다. 빈 줄은 둘까지만."""
    count = markdown.count(OBJECT)
    out = []
    index = 0
    for c in markdown:
        if c == OBJECT:
            link = links[index] if count == len(links) else None
            index += 1
            if link:
                out.append(link)
            continue
        out.append(c)
    lines = [_rstrip_space(l) for l in "".join(out).split("\n")]
    result: list[str] = []
    for l in lines:
        if l == "" and len(result) >= 1 and result[-1] == "":
            continue
        result.append(l)
    while result and result[0] == "":
        result.pop(0)
    while result and result[-1] == "":
        result.pop()
    return "\n".join(result)


def _drop_list_numbers(text: str) -> str:
    """줄 첫머리의 번호(`2.` · `3)`)를 뗀다 — 안전장치가 견주지 않는 글자다.

    메모는 표에 끊긴 번호 목록을 평문에서 **이어 센다**(`2.`) — HTML 은 `<ol>` 마다 1 부터다. 그 차이를 *글자가 빠졌다*
    로 읽어 변환을 버리고 평문을 붙였다 (빌드 74 · 사용자 진단). 번호는 목록이 다시 매기는 것이라 글이 아니다."""
    out = []
    for line in text.split("\n"):
        i = 0
        while i < len(line) and line[i] in " \t":
            i += 1
        j = i
        while j < len(line) and j - i < 9 and _is_ascii_digit(line[j]):
            j += 1
        if j > i and j < len(line) and line[j] in ".)" and (j + 1 == len(line) or line[j + 1] in " \t"):
            line = line[:i] + line[j + 1:]
        out.append(line)
    return "\n".join(out)


def letters(text: str) -> list:
    t = unicodedata.normalize("NFC", _drop_list_numbers(text))
    return [c for c in t if unicodedata.category(c) in ("Lu", "Ll", "Lt", "Lm", "Lo", "Nd")]


def keeps_letters(plain: str, converted: str) -> bool:
    """평문의 글자 · 숫자가 **차례대로 모두** 바꾼 글에 있나 (바꾼 글에 더 있는 것은 된다 — 링크 주소)."""
    want = letters(plain)
    have = letters(converted)
    i = 0
    for c in have:
        if i < len(want) and want[i] == c:
            i += 1
    return i == len(want)


def _is_table_row(line: str) -> bool:
    return _trim(line).startswith("|")


def _is_blank_row(line: str) -> bool:
    t = _trim(line)
    return t.startswith("|") and all(c in " |\t" for c in t)


def _is_separator(line: str) -> bool:
    t = _trim(line)
    return t.startswith("|") and "-" in t and all(c in " |-:\t" for c in t)


def promote_empty_headers(markdown: str) -> str:
    """**빈 머리줄을 첫 줄로 갈아 끼운다** (2026-10-03 사용자). 머리줄이 비고 바로 밑이 구분줄 · 그 밑이 표 줄이면
    그 표 줄을 머리줄 자리로 올린다. 보낸 앱이 실어 준 마크다운(메모)에도 같은 규칙을 건다 — 우리 변환과 갈리지 않게."""
    lines = markdown.split("\n")
    out = []
    i = 0
    while i < len(lines):
        if i + 2 < len(lines) and _is_blank_row(lines[i]) and _is_separator(lines[i + 1]) \
                and _is_table_row(lines[i + 2]) and not _is_separator(lines[i + 2]):
            out += [lines[i + 2], lines[i + 1]]
            i += 3
            continue
        out.append(lines[i])
        i += 1
    return "\n".join(out)


# ── 읽기 화면에서 체크상자 누르기 (211) — Swift `TaskToggle` 의 쌍둥이 ──────────────────

def _task_marker(line: str):
    """체크상자가 든 목록 줄이면 `[` 다음 글자(` ` · `x` · `X`)의 자리. 아니면 None.

    앞 빈칸 · 인용(`>`) 몇 겹 · 목록 기호(`-` `*` `+` · `1.` `1)`) · 빈칸 · `[ ]`/`[x]` · 그 뒤 빈칸이나 줄 끝."""
    i, n = 0, len(line)

    def spaces(k):
        while k < n and line[k] in " \t":
            k += 1
        return k

    i = spaces(i)
    while i < n and line[i] == ">":
        i = spaces(i + 1)
    if i < n and line[i] in "-*+":
        i += 1
    else:
        j = i
        while j < n and j - i < 9 and _is_ascii_digit(line[j]):
            j += 1
        if j == i or j >= n or line[j] not in ".)":
            return None
        i = j + 1
    if i >= n or line[i] not in " \t":
        return None
    i = spaces(i)
    # `[ ]` 뒤에는 빈칸이 있어야 한다 — `- [ ]` 혼자는 체크상자가 아니다 (cmark-gfm).
    if i + 3 < n and line[i] == "[" and line[i + 2] == "]" and line[i + 1] in " xX" and line[i + 3] in " \t":
        return i + 1
    return None


def task_toggled(markdown: str, line: int):
    """`line`(0 부터 · 머리말도 센다) 의 체크상자를 뒤집은 글. 체크상자 줄이 아니면 None."""
    lines = markdown.split("\n")
    if line < 0 or line >= len(lines):
        return None
    at = _task_marker(lines[line])
    if at is None:
        return None
    text = lines[line]
    mark = " " if text[at] in "xX" else "x"
    lines[line] = text[:at] + mark + text[at + 1:]
    return "\n".join(lines)


def task_lines(markdown: str) -> list:
    """체크상자 줄들 (코드 울타리 안은 빼고) — 읽기 화면이 누를 수 있게 만드는 줄."""
    out = []
    fence = False
    for k, line in enumerate(markdown.split("\n")):
        stripped = line.lstrip(" ")
        if stripped.startswith("```") or stripped.startswith("~~~"):
            fence = not fence
            continue
        if not fence and _task_marker(line) is not None:
            out.append(k)
    return out
