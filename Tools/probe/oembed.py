"""240 — 앱과 같은 셈(`SharedAddress.titleService`)으로 oEmbed 주소를 만들어 유튜브가 주는 제목을 본다."""
import json
import sys
import urllib.parse
import urllib.request

for line in open(sys.argv[1], encoding="utf-8"):
    u = line.strip()
    if not u:
        continue
    service = "https://www.youtube.com/oembed?format=json&url=" + urllib.parse.quote(u, safe="")
    print("==", u)
    try:
        with urllib.request.urlopen(service, timeout=20) as r:
            d = json.load(r)
            print("   title:", d.get("title"), "| author:", d.get("author_name"), "|", r.status)
    except Exception as e:  # noqa: BLE001 — 살펴보기일 뿐이다
        print("   실패:", e)
