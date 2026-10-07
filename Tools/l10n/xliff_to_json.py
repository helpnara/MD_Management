#!/usr/bin/env python3
"""**번역 열쇠 뽑기** (219) — `xcodebuild -exportLocalizations` 가 낸 en.xliff 를 JSON 으로.

열쇠 글자(`노트 %lld개` 처럼 끼워 넣는 값이 바뀐 꼴)는 **컴파일러만 정확히 안다** — 손으로 적지 않는다
(정답표를 손으로 적지 않는 규칙과 같다, CLAUDE.md §2). CI(`l10n.yml`)가 이 스크립트로 `Tools/l10n/extracted.json` 을 만들어 커밋한다.

    python3 Tools/l10n/xliff_to_json.py <en.xliff> > Tools/l10n/extracted.json
"""
import json
import sys
import xml.etree.ElementTree as ET

NS = {"x": "urn:oasis:names:tc:xliff:document:1.2"}


def main(path):
    root = ET.parse(path).getroot()
    out = {}
    for file in root.findall("x:file", NS):
        original = file.get("original", "")
        # 번역 목록(.xcstrings)과 InfoPlist 만 — 다른 것은 없다.
        table = "InfoPlist" if "InfoPlist" in original else original.rsplit("/", 1)[-1].split(".")[0]
        target = original.split("/", 1)[0]
        for unit in file.iter("{urn:oasis:names:tc:xliff:document:1.2}trans-unit"):
            key = unit.get("id")
            source = unit.find("x:source", NS)
            note = unit.find("x:note", NS)
            out.setdefault(target, {}).setdefault(table, {})[key] = {
                "source": source.text if source is not None else key,
                "note": note.text if note is not None else "",
            }
    json.dump(out, sys.stdout, ensure_ascii=False, indent=1, sort_keys=True)
    sys.stdout.write("\n")


if __name__ == "__main__":
    main(sys.argv[1])
