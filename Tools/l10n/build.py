#!/usr/bin/env python3
"""**영어 번역 → 번역 목록** (219).

- `Tools/l10n/extracted.json` — CI(`l10n.yml`)가 `xcodebuild -exportLocalizations` 로 뽑은 열쇠. 손으로 고치지 않는다.
- `Tools/l10n/en.json` — 사람이 읽고 고치는 영어 번역. `{ "<한국어 열쇠>": "<English>" }`. **번역의 원본은 이것 하나**다.
- 이 스크립트가 두 파일로 `App/Localizable.xcstrings` · `ShareExtension/Localizable.xcstrings` 를 만들고,
  검토용 표 `docs/en/strings-review.md` 를 쓴다.

    python3 Tools/l10n/build.py           # 만든다
    python3 Tools/l10n/build.py --check   # 만든 것과 커밋된 것이 같은지 · 빠진 번역 · 자리표시자 어긋남

**자리표시자 검사.** `노트 %lld개` 의 `%lld` 같은 것이 영어에 **같은 갯수 · 같은 종류**로 있어야 한다 —
다르면 앱이 그 자리에서 죽거나 엉뚱한 값을 찍는다. 순서를 바꾸려면 `%1$@` · `%2$lld` 꼴로 적는다.
"""
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
EXTRACTED = ROOT / "Tools/l10n/extracted.json"
EN = ROOT / "Tools/l10n/en.json"
REVIEW = ROOT / "docs/en/strings-review.md"
# xliff 의 대상(target) 이름 → 번역 목록 파일. 대상 이름은 xcodebuild 가 정한다 — 모르는 이름이면 멈춘다.
CATALOGS = {
    "App": ROOT / "App/Localizable.xcstrings",
    "ShareExtension": ROOT / "ShareExtension/Localizable.xcstrings",
}

SPEC = re.compile(r"%(?:(\d+)\$)?(?:lld|ld|d|@|lf|f|\.\d+f|%)")


def placeholders(text):
    """자리표시자 목록 — 차례 번호가 있으면 그 번호 순으로. `%%` 는 뺀다."""
    found = []
    auto = 0
    for m in SPEC.finditer(text):
        token = m.group(0)
        if token == "%%":
            continue
        kind = re.sub(r"^%(\d+\$)?", "", token)
        kind = {"ld": "lld", "d": "lld"}.get(kind, kind)
        if m.group(1):
            index = int(m.group(1))
        else:
            auto += 1
            index = auto
        found.append((index, kind))
    return sorted(found)


def load():
    if not EXTRACTED.exists():
        sys.exit("::error::Tools/l10n/extracted.json 이 없다 — l10n.yml 을 먼저 돌린다 (Tools/l10n/request.txt)")
    extracted = json.loads(EXTRACTED.read_text(encoding="utf-8"))
    en = json.loads(EN.read_text(encoding="utf-8")) if EN.exists() else {}
    return extracted, en


def build(extracted, en):
    problems = []
    catalogs = {}
    review_rows = []
    used = set()
    for target, tables in sorted(extracted.items()):
        if target not in CATALOGS:
            problems.append(f"모르는 대상: {target} — CATALOGS 에 더한다")
            continue
        strings = {}
        for table, keys in sorted(tables.items()):
            if table != "Localizable":
                continue          # InfoPlist 는 en.lproj/InfoPlist.strings 가 맡는다
            for key, meta in sorted(keys.items()):
                value = en.get(key)
                used.add(key)
                if value is None:
                    problems.append(f"번역 없음 [{target}] {key!r}")
                    strings[key] = {}
                    review_rows.append((target, key, "❓"))
                    continue
                # 단수 · 복수 (`{"one": …, "other": …}`) — 숫자 자리가 **하나뿐인** 문구에만 쓴다. 자리가 여럿이면 어느 숫자로
                # 고를지 모호하다 — 그런 문구는 *Links updated …: 3* 처럼 숫자를 뒤로 빼서 단수 · 복수가 필요 없게 쓴다.
                forms = value if isinstance(value, dict) else {"": value}
                if isinstance(value, dict):
                    if set(value) - {"zero", "one", "two", "few", "many", "other"} or "other" not in value:
                        problems.append(f"단수 · 복수 꼴이 틀렸다 [{target}] {key!r}")
                    if len(placeholders(key)) != 1 or placeholders(key)[0][1] != "lld":
                        problems.append(f"단수 · 복수는 숫자 자리 하나뿐인 문구에만 [{target}] {key!r}")
                for form in forms.values():
                    if placeholders(key) != placeholders(form):
                        problems.append(f"자리표시자 어긋남 [{target}] {key!r} → {form!r}")
                if isinstance(value, dict):
                    unit = {"variations": {"plural": {
                        name: {"stringUnit": {"state": "translated", "value": text}} for name, text in value.items()}}}
                    shown = " / ".join(f"{name}: {text}" for name, text in value.items())
                else:
                    unit = {"stringUnit": {"state": "translated", "value": value}}
                    shown = value
                strings[key] = {"localizations": {"en": unit}}
                review_rows.append((target, key, shown))
        catalogs[target] = {"sourceLanguage": "ko", "strings": strings, "version": "1.0"}
    stale = sorted(set(en) - used)
    for key in stale:
        problems.append(f"쓰이지 않는 번역 (코드에서 사라진 문구): {key!r}")
    return catalogs, review_rows, problems


def render_catalog(data):
    # Xcode 가 쓰는 꼴과 같게 — 두 칸 들여쓰기 · 열쇠 차례 정렬 · ` : `. 커밋 차이가 작아진다.
    text = json.dumps(data, ensure_ascii=False, indent=2, sort_keys=True)
    return text.replace('": ', '" : ') + "\n"


def render_review(rows):
    def cell(s):
        return s.replace("|", "\\|").replace("\n", "↵")
    out = [
        "# 영문판 화면 문구 — 검토 표 (219)",
        "",
        "> `python3 Tools/l10n/build.py` 가 만든다 — **이 파일을 고치지 말고** `Tools/l10n/en.json` 을 고친다.",
        "> 2026-10-07 사용자 결정: 세션이 쓰고 사용자가 읽고 고친다. `❓` 는 아직 번역이 없는 문구.",
        "> `%lld` · `%@` 는 앱이 숫자 · 이름을 끼워 넣는 자리다 (`↵` 는 줄바꿈).",
        "",
    ]
    for target in sorted({r[0] for r in rows}):
        title = "앱" if target == "App" else "공유 메뉴 (확장)"
        out += [f"## {title}", "", "| 한국어 | English |", "|---|---|"]
        out += [f"| {cell(k)} | {cell(v)} |" for t, k, v in rows if t == target]
        out.append("")
    return "\n".join(out)


def main():
    check = "--check" in sys.argv
    extracted, en = load()
    catalogs, rows, problems = build(extracted, en)
    outputs = {CATALOGS[t]: render_catalog(d) for t, d in catalogs.items()}
    outputs[REVIEW] = render_review(rows)
    if check:
        stale = [str(p.relative_to(ROOT)) for p, text in outputs.items()
                 if not p.exists() or p.read_text(encoding="utf-8") != text]
        if stale:
            problems.append("만든 것과 커밋된 것이 다르다: " + ", ".join(stale) + " — build.py 를 돌려 커밋한다")
    else:
        for path, text in outputs.items():
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(text, encoding="utf-8")
    total = sum(len(d["strings"]) for d in catalogs.values())
    done = sum(1 for _, _, v in rows if v != "❓")
    print(f"번역 {done} / {total}")
    for p in problems:
        print("::error::" + p if check else "· " + p)
    if check and problems:
        sys.exit(1)


if __name__ == "__main__":
    main()
