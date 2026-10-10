# 홍보 영상 — 기능 소개 모션그래픽

> 2026-10-10 사용자 — *이 앱을 블로그나 기타 소셜 네트워크 서비스에 홍보하기 위한 기능 중심의 소개로 구성한 모션그래픽을 만들어줘.*

- `slow-margin-promo.mp4` — **세로 1080 × 1920 · 30fps · 49초 · 소리 없음** (릴스 · 쇼츠 · 블로그 본문)
- `promo.html` — 장면 원본. `render(t)` 가 t초의 화면을 그린다 (CSS 애니메이션을 쓰지 않아 프레임마다 똑같이 찍힌다)
- `render.js` — 프레임을 찍어 ffmpeg 로 묶는다

## 장면 (앱이 실제로 하는 일만 — CLAUDE.md §6)

| 초 | 장면 | 근거 (스토어 설명 · 이슈) |
|---|---|---|
| 0 | 아이콘 · 느린 여백 · *글이 파일로 남는 마크다운 기록* | 부제 |
| 3.6 | 01 파일 — 아이클라우드 `Slow Margin` 폴더의 `.md` · `assets` | 설명 첫 절 · 221 (폴더 이름) |
| 8.4 | 02 쓰기 — `# ` · `**` 가 커서 줄에서만 보이고 떠나면 접힌다 · `#태그` 색 · 도구 띠 | ADR-0005 · T2 · 127 |
| 15.4 | 03 읽기 — 체크상자를 누르면 파일의 `[ ]` 가 `[x]` | 211 |
| 20.4 | 04 연결 — `[[9월` → 고르기 띠 → 표준 링크 | 147 |
| 26.0 | 05 보내기 — 공유 메뉴 → 받은 글 폴더 · 앱이 띄우는 실제 알림 문구 | 213 |
| 31.2 | 06 찾기 — 제목 · 본문, 두 글자부터 | ADR-0003 |
| 35.6 | 07 아이패드 — 세 칸 · ⌘B | 230 |
| 40.4 | 08 계정 없음 — 회원가입 · 서버 · 광고 · 추적 없음 · 한국어 · English | 설명 · 219 |
| 44.6 | 끝 — 앱스토어에서 ‘느린 여백’ | |

노트 내용은 모두 지어낸 견본이다 (개인 자료 없음). 다른 앱 이름 · 로고는 없다 — 공유 메뉴의 다른 앱 자리는 회색 칸.

## 다시 만들기

여기서는 원격 세션에서 만들었다. 글꼴(Noto Sans KR · Noto Serif KR · Noto Sans Mono)은 크기가 커서 저장소에 넣지 않았다 —
Google Fonts 에서 받아 `fonts/` 에 두고 `fonts.css` 를 `fonts/local.css` 로 옮긴다 (파일 이름은 `fonts.css` 안에 있다).

```
PROMO_DIR=$(pwd)/docs/promo FFMPEG=<ffmpeg 경로> NODE_PATH=$(npm root -g) node docs/promo/render.js video out.mp4 30
PROMO_DIR=$(pwd)/docs/promo NODE_PATH=$(npm root -g) node docs/promo/render.js stills 2.5,11,18   # 정지 화면
```

`icon.png` 는 `App/Assets.xcassets/AppIcon.appiconset/icon-1024.png` 를 복사해 둔다.
