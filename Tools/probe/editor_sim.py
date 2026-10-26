"""편집기(MarkdownEditor.swift)의 번호 관련 셈을 줄 배열 위에 그대로 옮긴 모형. Core 쪽은 파이썬 쌍둥이(generate.py)를 그대로 쓴다."""
import re, sys
sys.path.insert(0, '/home/user/MD_Management/Tools/golden')
import generate as g

ORDERED = re.compile(r'^[ \t]*[0-9]{1,9}[.)] ')

class Editor:
    def __init__(self, lines, note=""):
        self.lines = list(lines); self.note = note
    # ── 줄 판정 (Swift: isItemLine · isBlankLine · continuesText · nonBlankLine · isFirstItem) ──
    def item(self, i): return g.marker_prefix(self.lines[i]) is not None
    def blank(self, i): return not self.lines[i].strip()
    def continues(self, i):
        block = [self.lines[i]]; at = i
        while at > 0 and len(block) < 200:
            if self.blank(at - 1):
                b = self.above(at - 1)
                if b is None or not (self.item(b) or g.leading_width(self.lines[b]) > 0): break
                block.insert(0, ""); at -= 1; continue
            at -= 1; block.insert(0, self.lines[at])
        role = g.context_roles(block, editor=True)[-1]
        return role in ("continuation", "code")
    def above(self, i):
        for j in range(i - 1, -1, -1):
            if not self.blank(j): return j
        return None
    def below(self, i):
        for j in range(i + 1, len(self.lines)):
            if not self.blank(j): return j
        return None
    def first_item(self, i):
        a = self.above(i)
        if a is None: return True
        if not self.item(a) or self.continues(a): return True
        return not ORDERED.match(self.lines[a])
    def ordered(self, i): return bool(ORDERED.match(self.lines[i]))
    # ── 묶음 (listRun) → (start, end) 줄 차례, end 는 끝 다음 ──
    def list_run(self, i, seed_may_continue=False):
        if not self.item(i) or (not seed_may_continue and self.continues(i)): return None
        start, end = i, i + 1
        while start > 0:
            p = start - 1
            if self.item(p):
                if self.continues(p): break
                start = p; continue
            if not self.blank(p): break
            a = self.above(p)
            if a is None or not self.item(a) or self.continues(a): break
            start = a
        while end < len(self.lines):
            n = end
            if self.item(n): end = n + 1; continue
            if not self.blank(n): break
            b = self.below(n)
            if b is None or not self.item(b): break
            end = b + 1
        return (start, end)
    # ── 번호 맞추기 (renumberList) ──
    def renumber(self, i, start=None, frm=None, seed_may_continue=False):
        run = self.list_run(i, seed_may_continue)
        if run is None: return False
        s, e = run
        if frm is not None and s < frm < e: s = frm
        text = "\n".join(self.lines[s:e])
        fixes = g.renumber_block(text, start)
        if not fixes: return False
        u = g.to_units(text)
        for f in sorted(fixes, key=lambda f: -f['start']):
            u = u[:f['start']] + g.to_units(f['number']) + u[f['start'] + f['length']:]
        self.lines[s:e] = g.from_units(u).split("\n")
        return True
    def renumber_after_unlist(self, i, here, number):
        anchor, start, frm, smc = i, None, None, False
        if not self.item(i):
            b = self.below(i)
            if b is not None:
                anchor = b
                if number is not None and self.list_run(b, True) is not None and g.leading_width(self.lines[b]) <= here:
                    if self.first_item(b): start, frm = number, b
        self.renumber(anchor, start, frm, seed_may_continue=start is not None)
    # ── 엔터 (continueList) ──
    def enter(self, i, caret):
        line = self.lines[i]
        if self.continues(i):
            self.lines[i:i+1] = [line[:caret], line[caret:]]; return "plain"
        here = g.leading_width(line)
        shallower = None
        for j in range(i - 1, -1, -1):
            if not self.blank(j) and g.leading_width(self.lines[j]) < here: shallower = self.lines[j]; break
        act = g.return_pressed(line, shallower, caret)
        if act is None:
            self.lines[i:i+1] = [line[:caret], line[caret:]]; return "plain"
        if act["kind"] == "insert":
            self.lines[i:i+1] = (line[:caret] + act["text"] + line[caret:]).split("\n")
            self.renumber(i + 1); return "insert"
        if act["kind"] == "insertAt":
            at = act["at"]; self.lines[i:i+1] = (line[:at] + act["text"] + line[at:]).split("\n")
            self.renumber(i + 1); return "insertAt"
        number = g.ordered_number(line)       # 글을 바꾸기 전에 읽는다 (285)
        self.lines[i] = act["text"] + line[act["length"]:]
        if act["text"] == "":
            self.renumber_after_unlist(i, here, number)
        else:
            self.renumber(i)
        return "unlist"
    # ── 지우기 (unlistOnBackspace) ──
    def backspace(self, i, caret):
        line = self.lines[i]
        if self.continues(i):
            self.lines[i] = line[:caret-1] + line[caret:]; return "plain"
        here = g.leading_width(line)
        shallower = None
        for j in range(i - 1, -1, -1):
            if not self.blank(j) and g.leading_width(self.lines[j]) < here: shallower = self.lines[j]; break
        act = g.backspace_pressed(line, caret, shallower)
        if act is None:
            self.lines[i] = line[:caret-1] + line[caret:]; return "plain"
        number = g.ordered_number(line) if act["text"] == "" else None
        self.lines[i] = act["text"] + line[act["length"]:]
        self.renumber_after_unlist(i, here, number)
        return "unlist"
    # ── 목록 모양 바꾸기 (format list) ──
    def restyle(self, i, to):
        run = self.list_run(i)
        s, e = run if run else (i, i + 1)
        lines = self.lines[s:e]; first = i - s
        lost = g.ordered_number(lines[first]) if to != "number" and self.first_item(i) else None
        restyled = g.restyle_lines(lines, first, 1, to)
        self.lines[s:e] = restyled
        anchor = i if self.item(i) else (self.below(i) if self.below(i) is not None else i)
        self.renumber(anchor, lost, frm=i if lost is not None else None, seed_may_continue=lost is not None)

def run(name, before, action, expect):
    ed = Editor(before); action(ed)
    ok = ed.lines == expect
    print(("✅" if ok else "❌"), name)
    if not ok:
        print("   기대:", expect); print("   결과:", ed.lines)
    return ok

PRE = ["# 시험", "", "16. 가", "17. 나", "", "- 사과", ""]   # 사용자 시험 노트의 위쪽 모양 (다른 목록 · 글머리표)
def W(lines): return PRE + lines   # 시험 노트 안에서
results = []
R = lambda *a: results.append(run(*a))
# ── 빌드 124 (278) ──
R("124-1 번호 줄 맨 앞 엔터", ["1. 가","2. 나","3. 다"], lambda e: e.enter(0,0), ["","1. 가","2. 나","3. 다"])
R("124-3 가운데 항목 맨 앞 엔터", ["1. 가","2. 나","3. 다"], lambda e: e.enter(1,0), ["1. 가","","2. 나","3. 다"])
R("124-4 1 과 . 사이 엔터", ["1. 가","2. 나","3. 다"], lambda e: e.enter(0,1), ["1. ","2. 가","3. 나","4. 다"])
R("124-5 글 바로 앞 엔터", ["1. 가","2. 나","3. 다"], lambda e: e.enter(0,3), ["1. ","2. 가","3. 나","4. 다"])
def s6(e): e.enter(1,4); e.enter(2,3)
R("124-6 줄 끝 엔터 → 빈 항목 엔터", ["1. 가","2. 나","3. 다"], s6, ["1. 가","2. 나","","3. 다"])
R("124-7 글머리 맨 앞 엔터", ["- 사과","- 배"], lambda e: e.enter(0,0), ["","- 사과","- 배"])
R("124-8 체크 맨 앞 엔터", ["- [ ] 할 일"], lambda e: e.enter(0,0), ["","- [ ] 할 일"])
R("124-9 들여쓴 항목 맨 앞 엔터", ["- 가","  - 나"], lambda e: e.enter(1,0), ["- 가","","  - 나"])
# ── 빌드 125 (280) — 새 노트 ──
R("125-1 가운데 항목 글 앞 지우기", ["1. 가","2. 나","3. 다"], lambda e: e.backspace(1,3), ["1. 가","나","2. 다"])
R("125-3 첫 항목 글 앞 지우기", ["1. 가","2. 나","3. 다"], lambda e: e.backspace(0,3), ["가","1. 나","2. 다"])
R("125-4 마지막 항목 글 앞 지우기", ["1. 가","2. 나","3. 다"], lambda e: e.backspace(2,3), ["1. 가","2. 나","다"])
R("125-5 글머리 · 체크", ["- 사과","- [ ] 할 일"], lambda e: (e.backspace(0,2), e.backspace(1,6)), ["사과","할 일"])
def s6b(e): e.backspace(1,4); e.backspace(1,2)
R("125-6 겹친 항목 두 번 지우기", ["- 가","  - 나"], s6b, ["- 가","나"])
R("125-7 마커 안 · 글 끝 지우기", ["1. 가","2. 나"], lambda e: (e.backspace(0,2), e.backspace(1,4)), ["1 가","2. "])
# 같은 것을 시험 노트 안에서 (위에 다른 목록 · 글머리표)
R("125-1 (시험 노트) 가운데 지우기", W(["1. 가","2. 나","3. 다"]), lambda e: e.backspace(8,3), W(["1. 가","나","2. 다"]))
R("125-3 (시험 노트) 첫 항목 지우기", W(["1. 가","2. 나","3. 다"]), lambda e: e.backspace(7,3), W(["가","1. 나","2. 다"]))
# ── 빌드 126 (283) ──
R("126-12 마지막 빈 항목 지우기 · 아래 글머리", ["1. 가","2. 나","3. ","","","- 사과"], lambda e: e.backspace(2,3), ["1. 가","2. 나","","","","- 사과"])
R("126-13 마지막 빈 항목 엔터 · 아래 글머리", ["1. 가","2. 나","3. ","","","- 사과"], lambda e: e.enter(2,3), ["1. 가","2. 나","","","","- 사과"])
# ── 빌드 129 (281 · 282 · 284 · 285) ──
R("129-10 빈 줄 둘 건너", ["1. 가","","","2. 나"], lambda e: e.enter(0,4), ["1. 가","2. ","","","3. 나"])
R("129-11 항목 안 문단 밑 다음 항목", ["1. 가","","   설명","2. 나"], lambda e: e.enter(3,4), ["1. 가","","   설명","2. 나","3. "])
R("129-14a 가운데 빈 항목 엔터", ["1. 가","2. ","3. 다"], lambda e: e.enter(1,3), ["1. 가","","2. 다"])
R("129-14b 첫 빈 항목 엔터 (시험 노트)", W(["1. ","","2. 다"]), lambda e: e.enter(7,3), W(["","","1. 다"]))
R("129-14b 첫 빈 항목 엔터 (새 노트)", ["1. ","2. 나","3. 다"], lambda e: e.enter(0,3), ["","1. 나","2. 다"])
def s16(e):
    e.enter(0,4); e.enter(1,3); e.enter(1,0); e.enter(2,0)
R("129-16 문서 끝에서 엔터 반복 (죽지 않고)", ["1. 가"], s16, ["1. 가","","",""])
R("282 항목 밖 문단 밑 번호는 이어지는 글 (198 그대로)", ["1. 가","","설명","2. 나"], lambda e: e.enter(3,4), ["1. 가","","설명","2. 나",""])
R("198 글 밑 번호는 이어지는 글", ["가나다","2. 나"], lambda e: e.enter(1,4), ["가나다","2. 나",""])
R("282 글머리 밑 들여쓴 글 뒤 글머리", ["- 가","","  설명","- 나"], lambda e: e.enter(3,3), ["- 가","","  설명","- 나","- "])
# ── 빌드 130 · 131 (284 목록 모양) ──
R("130-15 글머리표로 (시험 노트)", W(["1. 가","2. 나","3. 다"]), lambda e: e.restyle(7,"bullet"), W(["- 가","1. 나","2. 다"]))
R("131-15 보통 글로 (시험 노트)", W(["1. 가","2. 나","3. 다"]), lambda e: e.restyle(7,"plain"), W(["가","1. 나","2. 다"]))
R("131-15 보통 글로 (새 노트)", ["1. 가","2. 나","3. 다"], lambda e: e.restyle(0,"plain"), ["가","1. 나","2. 다"])
# ── 예전 동작 (192 · 195 · 141) ──
R("192 첫 항목 줄 통째로 지운 뒤", ["2. 나","3. 다"], lambda e: e.renumber(0, start=1), ["1. 나","2. 다"])
R("141 겹친 빈 항목 엔터 → 한 단계", ["- 가","  - "], lambda e: e.enter(1,4), ["- 가","- "])
print("\n통과", sum(results), "/", len(results))
