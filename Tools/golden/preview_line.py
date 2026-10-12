"""242 — **목록 · 검색 결과에 보이는 한 줄을 글로.** Swift `PreviewLine` 의 쌍둥이.

2026-10-12 사용자 미리보기 영상 검토에서 찾음 — 검색 결과 줄에 `[시니어 명소](<>)` 가, 목록 미리보기에
`**clearing what's piled up**` 이 마크다운 원문째 보였다. 읽기 화면에서는 링크 제목 · 굵은 글로 보이는 것들이다.

규칙: 앞의 블록 표시(제목 `#` · 인용 `>` · 목록 `-` `1.`)를 떼고, 목록의 할 일 상자는 ☐ · ☑ 로 바꾼 뒤,
**줄 안 표시는 markdown-it 이 읽는 그대로** 보이는 글만 남긴다 — 링크 · 이미지는 제목(대체 글)만, 굵게 · 기울임 ·
취소선(`~` · `~~`) 표시는 짝이 맞을 때만 떼고, 코드는 안의 글, `\` 빗금 풀기, 자동 링크 `<주소>` 는 주소, 문자 참조는 글자.
HTML 태그는 그대로 둔다 (읽기 화면도 그렇게 보인다).

**심판은 markdown-it 이다** (`generate.py` 의 `build_preview_cases`). 이 파일은 markdown-it 의 줄 안 규칙
(escape · backticks · strikethrough · emphasis · link · image · autolink · html_inline · entity, 그리고 `balance_pairs`)을
그대로 옮긴 것이다 — 링크 표를 찾을 때의 `` ` `` 기억까지. 뒤섞은 줄 17만 개로 심판과 견줘 한 번도 안 어긋났다 (2026-10-12).
문자 참조는 자주 쓰는 이름만 안다 (ENTITIES) — 모르는 이름은 글자 그대로다 (markdown-it 은 HTML5 전부를 안다. 정답표에는 아는 이름만 넣는다).

글자는 유니코드 스칼라(코드 포인트) 단위로 본다 — Swift 도 스칼라로 본다.
"""
import re
import unicodedata

ESCAPABLE = set('\\!"#$%&\'()*+,./:;<=>?@[]^_`{|}~-')
MD_ASCII_PUNCT = set('!"#$%&\'()*+,-./:;<=>?@[\\]^_`{|}~')
MD_WHITESPACE = {0x09, 0x0A, 0x0B, 0x0C, 0x0D, 0x20, 0xA0, 0x1680, 0x202F, 0x205F, 0x3000}
ENTITIES = {
    "amp": "&", "lt": "<", "gt": ">", "quot": '"', "apos": "'", "nbsp": "\u00a0",
    "copy": "©", "reg": "®", "trade": "™", "hellip": "…", "mdash": "—", "ndash": "–",
    "middot": "·", "laquo": "«", "raquo": "»", "lsquo": "‘", "rsquo": "’", "ldquo": "“", "rdquo": "”",
    "deg": "°", "times": "×", "bull": "•",
}
AUTOLINK_RE = re.compile(r"^([a-zA-Z][a-zA-Z0-9+.\-]{1,31}):([^<>\x00-\x20]*)$")
EMAIL_RE = re.compile(r"^([a-zA-Z0-9.!#$%&'*+/=?^_`{|}~-]+@[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(?:\.[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)*)$")
_attr_name = "[a-zA-Z_:][a-zA-Z0-9:._-]*"
_attr_value = "(?:" + "[^\"'=<>`\\x00-\\x20]+" + "|" + "'[^']*'" + "|" + '"[^"]*"' + ")"
_attribute = "(?:\\s+" + _attr_name + "(?:\\s*=\\s*" + _attr_value + ")?)"
HTML_TAG_RE = re.compile(
    "^(?:" + "<[A-Za-z][A-Za-z0-9\\-]*" + _attribute + "*\\s*\\/?>" + "|" + "<\\/[A-Za-z][A-Za-z0-9\\-]*\\s*>"
    + "|" + "<!---?>|<!--(?:[^-]|-[^-]|--[^>])*-->" + "|" + "<[?][\\s\\S]*?[?]>" + "|" + "<![A-Za-z][^>]*>"
    + "|" + "<!\\[CDATA\\[[\\s\\S]*?\\]\\]>" + ")")
DIGITAL_RE = re.compile(r"^&#((?:x[a-f0-9]{1,6}|[0-9]{1,7}));", re.IGNORECASE)
NAMED_RE = re.compile(r"^&([a-z][a-z0-9]{1,31});", re.IGNORECASE)
BAD_PROTO_RE = re.compile(r"^(vbscript|javascript|file|data):")
GOOD_DATA_RE = re.compile(r"^data:image\/(gif|png|jpeg|webp);")


def is_punct(ch):
    return ch in MD_ASCII_PUNCT or unicodedata.category(ch).startswith(("P", "S"))


def is_white(ch):
    c = ord(ch)
    return 0x2000 <= c <= 0x200A or c in MD_WHITESPACE


def valid_entity_code(c):
    if 0xD800 <= c <= 0xDFFF or 0xFDD0 <= c <= 0xFDEF:
        return False
    if (c & 0xFFFF) in (0xFFFF, 0xFFFE):
        return False
    if 0x00 <= c <= 0x08 or c == 0x0B or 0x0E <= c <= 0x1F or 0x7F <= c <= 0x9F:
        return False
    return c <= 0x10FFFF


def unescape(s):
    """`\\` 빗금 풀기와 문자 참조 풀기 (주소 · 제목 안) — 링크 판정에만 쓰인다 (나쁜 주소 거르기)."""
    out, i = [], 0
    while i < len(s):
        if s[i] == "\\" and i + 1 < len(s) and s[i + 1] in ESCAPABLE:
            out.append(s[i + 1]); i += 2; continue
        if s[i] == "&":
            m = DIGITAL_RE.match(s[i:]) or NAMED_RE.match(s[i:])
            if m:
                g = m.group(1)
                if s[i + 1] == "#":
                    code = int(g[1:], 16) if g[0] in "xX" else int(g)
                    out.append(chr(code) if valid_entity_code(code) else "\ufffd"); i += len(m.group(0)); continue
                if g in ENTITIES:
                    out.append(ENTITIES[g]); i += len(m.group(0)); continue
        out.append(s[i]); i += 1
    return "".join(out)


def valid_link(url):
    url = url.strip().lower()
    return bool(GOOD_DATA_RE.search(url)) if BAD_PROTO_RE.search(url) else True


class Delim:
    __slots__ = ("marker", "length", "token", "end", "open", "close")

    def __init__(self, marker, length, token, can_open, can_close):
        self.marker, self.length, self.token, self.end = marker, length, token, -1
        self.open, self.close = can_open, can_close


class Inline:
    def __init__(self, src):
        self.src = src
        # markdown-it 의 `` ` `` 기억 (`backticks` · `backticksScanned`) — 링크 표를 찾다 끝까지 훑은 뒤로는
        # 그 뒤에 같은 길이의 닫는 줄이 없으면 여는 줄도 글자다. 결과가 이 기억에 따라 달라져 그대로 옮긴다.
        self.backticks = {}
        self.scanned = False

    # ── 판정 ──
    def scan_delims(self, start, end, can_split):
        src, marker = self.src, self.src[start]
        last = src[start - 1] if start > 0 else " "
        pos = start
        while pos < end and src[pos] == marker:
            pos += 1
        nxt = src[pos] if pos < end else " "
        last_p, next_p = is_punct(last), is_punct(nxt)
        last_w, next_w = is_white(last), is_white(nxt)
        left = not (next_w or (next_p and not (last_w or last_p)))
        right = not (last_w or (last_p and not (next_w or next_p)))
        can_open = left and (can_split or (not right) or last_p)
        can_close = right and (can_split or (not left) or next_p)
        return can_open, can_close, pos - start

    def code_span(self, pos, end):
        """`` ` `` 줄 — (끝 자리, 내용 또는 None). 닫는 줄이 없으면 내용 None 으로 그 줄만 넘긴다."""
        src, start = self.src, pos
        pos += 1
        while pos < end and src[pos] == "`":
            pos += 1
        opener = pos - start
        if self.scanned and self.backticks.get(opener, 0) <= start:
            return start + opener, None
        match_end = pos
        while True:
            k = src.find("`", match_end)
            if k < 0:
                break
            match_end = k + 1
            while match_end < end and src[match_end] == "`":
                match_end += 1
            if match_end - k == opener:
                content = src[pos:k]
                if content.startswith(" ") and content.endswith(" ") and len(content.strip()) > 0:
                    content = content[1:-1]
                return match_end, content
            self.backticks[match_end - k] = k
        self.scanned = True
        return start + opener, None

    def autolink(self, pos, end):
        src = self.src
        k = pos
        while True:
            k += 1
            if k >= end:
                return None
            if src[k] == "<":
                return None
            if src[k] == ">":
                break
        url = src[pos + 1:k]
        if AUTOLINK_RE.search(url):
            return (k + 1, url) if valid_link(url) else None
        if EMAIL_RE.search(url):
            return k + 1, url
        return None

    def html(self, pos, end):
        src = self.src
        if pos + 2 >= end:
            return None
        ch = src[pos + 1]
        if ch not in "!?/" and not ("a" <= ch.lower() <= "z" and ch.isascii()):
            return None
        m = HTML_TAG_RE.search(src[pos:])
        return pos + len(m.group(0)) if m else None

    def entity(self, pos, end):
        src = self.src
        if pos + 1 >= end:
            return None
        if src[pos + 1] == "#":
            m = DIGITAL_RE.search(src[pos:])
            if m:
                g = m.group(1)
                code = int(g[1:], 16) if g[0] in "xX" else int(g, 10)
                return pos + len(m.group(0)), (chr(code) if valid_entity_code(code) else "\ufffd")
            return None
        m = NAMED_RE.search(src[pos:])
        if m and m.group(1) in ENTITIES:
            return pos + len(m.group(0)), ENTITIES[m.group(1)]
        return None

    def destination(self, pos, end):
        src = self.src
        start = pos
        if pos < len(src) and src[pos] == "<":
            pos += 1
            while pos < end:
                c = src[pos]
                if c == "\n" or c == "<":
                    return None
                if c == ">":
                    return pos + 1, unescape(src[start + 1:pos])
                if c == "\\" and pos + 1 < end:
                    pos += 2
                    continue
                pos += 1
            return None
        level = 0
        while pos < end:
            c = src[pos]
            if c == " " or ord(c) < 0x20 or ord(c) == 0x7F:
                break
            if c == "\\" and pos + 1 < end:
                if src[pos + 1] == " ":
                    break
                pos += 2
                continue
            if c == "(":
                level += 1
                if level > 32:
                    return None
            if c == ")":
                if level == 0:
                    break
                level -= 1
            pos += 1
        if start == pos or level != 0:
            return None
        return pos, unescape(src[start:pos])

    def title(self, pos, end):
        src = self.src
        if pos >= end:
            return None
        marker = src[pos]
        if marker not in "\"'(":
            return None
        if marker == "(":
            marker = ")"
        pos += 1
        while pos < end:
            c = src[pos]
            if c == marker:
                return pos + 1
            if c == "(" and marker == ")":
                return None
            if c == "\\" and pos + 1 < end:
                pos += 1
            pos += 1
        return None

    def label_end(self, start, end, disable_nested):
        """`[` 자리 start 에서 짝 `]` 자리 (없으면 -1)."""
        pos, level = start + 1, 1
        while pos < end:
            marker = self.src[pos]
            if marker == "]":
                level -= 1
                if level == 0:
                    return pos
            prev = pos
            pos = self.skip(pos, end)
            if marker == "[":
                if prev == pos - 1:
                    level += 1
                elif disable_nested:
                    return -1
        return -1

    def link_tail(self, label_end, end):
        """`](…)` 뒤 — 링크가 되면 끝 자리, 아니면 None."""
        src = self.src
        pos = label_end + 1
        if not (pos < end and src[pos] == "("):
            return None
        pos += 1
        while pos < end and src[pos] in " \t\n":
            pos += 1
        if pos >= end:
            return None
        dest = self.destination(pos, end)
        if dest is not None:
            if valid_link(dest[1]):
                pos = dest[0]
            start = pos
            while pos < end and src[pos] in " \t\n":
                pos += 1
            t = self.title(pos, end)
            if pos < end and start != pos and t is not None:
                pos = t
                while pos < end and src[pos] in " \t\n":
                    pos += 1
        if pos >= end or src[pos] != ")":
            return None
        return pos + 1

    def try_link(self, pos, end):
        """[…](…) — (끝 자리, 라벨 시작, 라벨 끝) 또는 None."""
        le = self.label_end(pos, end, True)
        if le < 0:
            return None
        tail = self.link_tail(le, end)
        return None if tail is None else (tail, pos + 1, le)

    def try_image(self, pos, end):
        src = self.src
        if pos + 1 < end and src[pos + 1] != "[":
            return None
        le = self.label_end(pos + 1, end, False)
        if le < 0:
            return None
        tail = self.link_tail(le, end)
        return None if tail is None else (tail, pos + 2, le)

    def skip(self, pos, end):
        """한 토큰 건너뛰기 (조용히) — markdown-it `skipToken`."""
        c = self.src[pos]
        if c == "\\":
            if pos + 1 < end:
                return pos + 2
        elif c == "`":
            return self.code_span(pos, end)[0]
        elif c == "[":
            r = self.try_link(pos, end)
            if r:
                return r[0]
        elif c == "!":
            r = self.try_image(pos, end)
            if r:
                return r[0]
        elif c == "<":
            r = self.autolink(pos, end)
            if r:
                return r[0]
            r = self.html(pos, end)
            if r:
                return r
        elif c == "&":
            r = self.entity(pos, end)
            if r:
                return r[0]
        return pos + 1

    # ── 글로 ──
    def text(self, start, end):
        src = self.src
        tokens = []  # [내용, 남기나]
        delims = []
        pos = start
        while pos < end:
            c = src[pos]
            if c == "\\" and pos + 1 < end:
                nxt = src[pos + 1]
                tokens.append([nxt if nxt in ESCAPABLE else "\\" + nxt, True])
                pos += 2
                continue
            if c == "`":
                after, content = self.code_span(pos, end)
                tokens.append([content if content is not None else src[pos:after], True])
                pos = after
                continue
            if c == "~":
                can_open, can_close, n = self.scan_delims(pos, end, True)
                tokens.append(["~" * n, True])
                if n <= 2:
                    delims.append(Delim("~", 0, len(tokens) - 1, can_open, can_close))
                pos += n
                continue
            if c in "*_":
                can_open, can_close, n = self.scan_delims(pos, end, c == "*")
                for _ in range(n):
                    tokens.append([c, True])
                    delims.append(Delim(c, n, len(tokens) - 1, can_open, can_close))
                pos += n
                continue
            if c == "[":
                r = self.try_link(pos, end)
                if r:
                    tokens.append([self.text(r[1], r[2]), True])
                    pos = r[0]
                    continue
            if c == "!":
                r = self.try_image(pos, end)
                if r:
                    tokens.append([Inline(src[r[1]:r[2]]).text(0, r[2] - r[1]), True])
                    pos = r[0]
                    continue
            if c == "<":
                r = self.autolink(pos, end)
                if r:
                    tokens.append([r[1], True])
                    pos = r[0]
                    continue
                r = self.html(pos, end)
                if r:
                    tokens.append([src[pos:r], True])
                    pos = r
                    continue
            if c == "&":
                r = self.entity(pos, end)
                if r:
                    tokens.append([r[1], True])
                    pos = r[0]
                    continue
            tokens.append([c, True])
            pos += 1
        balance(delims)
        for d in delims:
            if d.end < 0:
                continue
            closer = delims[d.end]
            if d.marker == "~" and tokens[d.token][0] != tokens[closer.token][0]:
                continue
            tokens[d.token][1] = False
            tokens[closer.token][1] = False
        return "".join(t[0] for t in tokens if t[1])


def balance(delims):
    """markdown-it `processDelimiters` — 여는 표시마다 닫는 짝을 찾는다."""
    if not delims:
        return
    bottoms = {}
    header, last_token = 0, -2
    jumps = []
    for ci, closer in enumerate(delims):
        jumps.append(0)
        if delims[header].marker != closer.marker or last_token != closer.token - 1:
            header = ci
        last_token = closer.token
        if not closer.close:
            continue
        if closer.marker not in bottoms:
            bottoms[closer.marker] = [-1] * 6
        slot = (3 if closer.open else 0) + (closer.length % 3)
        minimum = bottoms[closer.marker][slot]
        oi = header - jumps[header] - 1
        new_min = oi
        while oi > minimum:
            opener = delims[oi]
            if opener.marker != closer.marker:
                oi -= jumps[oi] + 1
                continue
            if opener.open and opener.end < 0:
                odd = ((opener.close or closer.open) and (opener.length + closer.length) % 3 == 0
                       and (opener.length % 3 != 0 or closer.length % 3 != 0))
                if not odd:
                    last_jump = jumps[oi - 1] + 1 if oi > 0 and not delims[oi - 1].open else 0
                    jumps[ci] = ci - oi + last_jump
                    jumps[oi] = last_jump
                    closer.open = False
                    opener.end = ci
                    opener.close = False
                    new_min = -1
                    last_token = -2
                    break
            oi -= jumps[oi] + 1
        if new_min != -1:
            bottoms[closer.marker][slot] = new_min


HEADING_RE = re.compile(r"^#{1,6}(?:[ \t]+|$)")
QUOTE_RE = re.compile(r"^>[ \t]?")
LIST_RE = re.compile(r"^(?:[-*+]|[0-9]{1,9}[.)])[ \t]+")
TASK_RE = re.compile(r"^\[([ xX])\][ \t]+")
CLOSING_HASHES_RE = re.compile(r"(?:^|[ \t]+)#+[ \t]*$")


def strip_block(line):
    """앞의 블록 표시(제목 · 인용 · 목록 — 겹쳐도)를 뗀 (상자, 나머지). 목록 바로 뒤의 할 일 상자는 ☐ · ☑ 로.
    제목 끝의 `#` 줄은 앞에 빈칸이 있을 때만 뗀다 (`C#` 은 둔다)."""
    s = line.strip(" \t")
    box = ""
    while True:
        m = HEADING_RE.match(s)
        if m:
            s = CLOSING_HASHES_RE.sub("", s[m.end():])
            continue
        m = QUOTE_RE.match(s)
        if m:
            s = s[m.end():]
            continue
        m = LIST_RE.match(s)
        if m:
            s = s[m.end():]
            t = TASK_RE.match(s)
            if t:
                box = "☐ " if t.group(1) == " " else "☑ "
                s = s[t.end():]
                break
            continue
        break
    return box, s.strip(" \t")


def preview(line):
    """목록 · 검색 결과에 보이는 한 줄."""
    box, s = strip_block(line)
    return (box + Inline(s).text(0, len(s))).strip(" \t")
