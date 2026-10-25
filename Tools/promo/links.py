#!/usr/bin/env python3
"""**캠페인 링크를 한 번에 만든다** (홍보 주 · `docs/promo/launch-kit.md` §1).

공급자 번호(`pt`)는 App Store Connect → 앱 분석 → 캠페인 링크 만들기에서 사용자가 얻는다. **저장소에 적지 않는다** —
실행할 때 인자로만 받는다. 꼬리표는 launch-kit §1 표와 같은 것 하나를 쓴다 (손으로 링크를 열몇 개 이어 붙이다 틀리지 않게).

    python3 Tools/promo/links.py <공급자 번호>
"""
import sys

APP_ID = "6811515067"
# 꼬리표 → 쓰는 글 (launch-kit §1 과 같은 차례). 영문 · 숫자 · `-` 만.
TAGS = [
    ("blog-links", "네이버 블로그 — 링크 모으기 (§4)"),
    ("blog-intro", "앱 소개 글 (docs/blog/앱-소개.md)"),
    ("shorts-ko", "유튜브 쇼츠 설명 — 한국어"),
    ("shorts-en", "유튜브 쇼츠 설명 — 영어"),
    ("disquiet", "메이커 모임 (§5)"),
    ("geeknews", "개발자 소식 (§5)"),
    ("threads", "스레드 (§5)"),
    ("forum-ko", "아이폰 · 맥 사용자 게시판 (§5)"),
    ("ph", "Product Hunt (§6)"),
    ("reddit", "Reddit (§6)"),
    ("hn", "Show HN (§6)"),
]


def link(provider: str, tag: str) -> str:
    return f"https://apps.apple.com/app/id{APP_ID}?pt={provider}&ct={tag}&mt=8"


def main() -> int:
    if len(sys.argv) != 2 or not sys.argv[1].isdigit():
        print("쓰는 법: python3 Tools/promo/links.py <공급자 번호 — 숫자>", file=sys.stderr)
        return 2
    provider = sys.argv[1]
    for tag, where in TAGS:
        assert all(c.isalnum() or c == "-" for c in tag), tag
        print(f"{tag:<11} {link(provider, tag)}   ← {where}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
