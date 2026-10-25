---
title: 출시 주 홍보 묶음 — 추천 신청 · 인앱 이벤트 · 캠페인 링크 · 글 초안
updated: 2026-10-12
---

# 출시 주 홍보 묶음 (브레인스토밍 4 · 5)

> 2026-10-11 사용자 — *무료 앱 중에서 상위에 랭크하기 위해서 … 내가 무엇을 더 준비하면 좋을까* → 준비물 표 4 · 5 →
> *4·5 홍보 준비* (스크린샷을 찍는 동안). 무료 차트는 **며칠 사이의 다운로드 속도**로 움직인다 — 흩어 올리지 말고 **한 주에 몰아서** 낸다.
>
> **판 번호를 글에 박지 않는다** — 링크 모으기 · 코드 상자는 1.1.3 에 들어갔고, 1.1.4 는 평가 부탁 · 스토어 손질이다. *최근 업데이트* 로 쓴다.
>
> **지킬 것.** 다른 앱 이름을 쓰지 않는다 (CLAUDE §6 — 블로그 · 커뮤니티 글도 사용자가 읽는 글이다). **하는 일만** 적는다.
> 이 저장소는 공개다 — 실제 메일 · 개인 정보를 여기 적지 않는다. 글자 수는 셌다 (`python3` · 칸 한도 옆 괄호).

## 0. 한 주의 차례

> **D = 2026-11-02 (월)** (2026-10-12 사용자 — *출시 주 홍보 첫 단계부터 하자*). 1.1.4 는 이미 나왔고 1.1.5 는 심사 중이라 *판 출시 날* 이 아니라
> **홍보 주**로 잡았다 — 애플이 권하는 추천 신청 시간(3주)을 지키고, 그 주에 인앱 이벤트 · 블로그 · 커뮤니티를 몰아 낸다. 그때 나와 있는 판을 알린다 (2026-10-25 — **1.1.15 출시** · 폴더 화면 찾기 칸 · 최근 고친 노트 · 노트가 많아도 빠름까지 다 나와 있다).

| 언제 | 할 일 | 어디 |
|---|---|---|
| ✅ 3주 전 — 10-12 | 애플 추천 신청 (§2) — **제출함** (2026-10-12 사용자) | App Store Connect → 앱 → 느린 여백 → 사이드바 Featuring → Nominations |
| ✅ 2주 전 — 10-19 | 인앱 이벤트 **공개 시작** (§3) — **승인 2026-10-16** (제출 10-15 · 바로 가기 `slowmargin://event` · 그림 네 장) | App Store Connect → 인앱 이벤트 |
| **1주 전 — 10-26 (다음)** | 캠페인 링크 만들기 (§1) · 글 초안 다듬기 (§4~§6) — **아래 *10-26 할 일*** | 이 문서 |
| **D — 11-02 (월)** | 인앱 이벤트 시작 · 프로모션 텍스트 갈기 · 블로그 글 (§4) | 네이버 블로그 |
| D+1 | 국내 커뮤니티 두 곳 (§5) | 메이커 모임 · 개발자 소식 |
| D+2 | 스레드 · 맥 · 아이폰 사용자 게시판 (§5) | |
| D+3~4 | 해외 — Product Hunt 하루 · Reddit · Show HN (§6) | 영어판 |
| D+7 | **결과 적기** — App Store Connect *앱 분석* 의 출처별 다운로드 (§1 의 `ct`) · 순위 · 평점 수 | 이 문서 맨 아래 |

### 10-26 할 일 (2026-10-25 준비 — 사용자 — *10월 26일 할 일도 같이 준비하자*)

| # | 누가 | 할 일 | 끝나면 |
|---|---|---|---|
| 1 | 사용자 | ⚠️ **보류 — 다운로드가 적어 만들 수 없음 (2026-10-25) · 글에는 기본 주소** · App Store Connect → 앱 → 맨 위 **분석** 탭 (왼쪽 메뉴가 아니다 — 왼쪽 메뉴는 *App Store* 탭의 것) → **획득** 아래 **캠페인** → **캠페인 옆 +** → 이름 `test` → 나온 링크의 **`pt=` 뒤 숫자**가 공급자 번호 → 대화에 알려 준다 (저장소에는 적지 않는다 · 처음 링크를 만들 때 생기고 늘 같다). 휴대폰에서 탭이 안 보이면 사파리 **데스크톱 웹사이트 요청** (2026-10-25 사용자 — 왼쪽 메뉴에서 못 찾음) | 세션이 `python3 Tools/promo/links.py <번호>` 로 꼬리표 11개의 링크를 만들어 글마다 넣는다 (§1) |
| 2 | 사용자 | ✅ **2026-10-25 다시 찍음 · 준비 끝** — 블로그 **[사진 4]** 다시 찍기 — 지금 사진은 옛 찾기 칸(빌드 115 전)이다. **폴더 화면 맨 위 찾기 칸**에 `ㅎㅇㄹ` · 자판이 보이게 · 상태 막대 잘라 냄. [사진 1 ~ 3] 이 기기에 있는지도 본다 | §4 의 *사진 준비* 줄에 적는다 |
| 3 | 사용자 | **추천 신청 설명 갈기** (고칠 수 있으면) — App Store Connect → 앱 → App Store 탭 왼쪽 메뉴 **피처링 → 피처링 요청** → 낸 신청 → 설명을 §2 의 **2026-10-25 판**으로. 안 고쳐지면 그대로 둔다 | §2 에 적는다 |
| 4 | 사용자 | 국내 · 해외 게시판의 **자기 홍보 규칙** 확인 — 허용 게시판 · 말머리 · 횟수 (§5 · §6) | 안 되는 곳은 표에서 지운다 |
| 6 | 사용자 | **11월 쇼츠** (`slow-margin-links.mp4` — 보던 링크를 한 노트에) 유튜브에 올리기 | ✅ 2026-10-25 |
| 5 | 세션 | 글 초안 마지막 손질 — 1.1.15 까지 반영 (§4 ~ §6) · D 날 **프로모션 텍스트** (아래) | ✅ 2026-10-25 |

**D 날(11-02) 프로모션 텍스트** — 11-02 아침에 갈고 **12-01 에 되돌린다** (지금 것은 `docs/12-submission.md` §1 · §1-영어). 심사 없이 바뀐다.

| 칸 | 글 (글자 수) |
|---|---|
| 한국어 (170) | `11월 한 달, 보던 링크를 한 노트에 모아 보세요. 공유 한 번이면 고른 노트 끝에 제목과 링크가 쌓이고, 그 노트는 그대로 내 아이클라우드의 마크다운 파일입니다.` (92) |
| 영어 (170) | `This November, gather the links you find in one note. Share once and the title and link land at the end of a note you pick, still a plain Markdown file in your iCloud.` (167) |

## 1. 캠페인 링크 — 어느 글에서 왔는지 재기

앱 안에서 아무것도 모으지 않아도, **스토어 링크에 꼬리표**를 붙이면 App Store Connect *앱 분석* 이 출처별 노출 · 다운로드를 보여 준다.

```
https://apps.apple.com/app/id6811515067?pt=<공급자 번호>&ct=<꼬리표>&mt=8
```

- `<공급자 번호>` — App Store Connect → **앱 분석** → 위의 **캠페인 링크 만들기**(또는 *Campaign Generator*)에서 얻는다. 여기 적지 않는다 (사용자가 채운다).
- ⚠️ **2026-10-25 — 캠페인 링크를 만들 수 없다** (사용자 — *다운로드 수가 부족해서 캠페인 링크가 생성이 안되는 것 같아*). 애플은 앱에 분석 자료가 쌓이기 전에는 링크 만들기를 막는다.
  → 글의 *(캠페인 링크 — …)* 자리에는 **기본 주소** `https://apps.apple.com/app/id6811515067` 를 넣는다. 어느 글에서 왔는지는 못 잰다 — 홍보 주가 끝나고 다운로드가 쌓이면 다시 해 본다 (`links.py` 는 그대로 둔다).
- **링크는 손으로 잇지 않는다** — `python3 Tools/promo/links.py <공급자 번호>` 가 아래 표의 꼬리표마다 링크를 찍는다 (2026-10-25).
- `<꼬리표>` — 글마다 하나. 영문 · 숫자 · `-` 만:

| 꼬리표 | 글 |
|---|---|
| `blog-links` | 네이버 블로그 — 링크 모으기 (§4) |
| `blog-intro` | 앱 소개 글 (`docs/blog/앱-소개.md`) |
| `shorts-ko` · `shorts-en` | 유튜브 쇼츠 설명 (`docs/promo/youtube-shorts*.md`) |
| `disquiet` · `geeknews` · `threads` · `forum-ko` | 국내 (§5) |
| `ph` · `reddit` · `hn` | 해외 (§6) |

## 2. 애플 추천 신청 (Featuring Nomination)

App Store Connect 의 **추천 신청**은 편집팀에 *이런 앱 · 이런 업데이트가 나온다* 고 알리는 칸이다. 뽑힐지는 애플이 정한다 — 내는 데 돈은 안 든다.
**칸 이름 · 한도는 콘솔에 보이는 것이 최종이다** (여기서는 열어 볼 수 없다). 영어로 낸다 — 편집팀이 여러 나라다.

| 칸 | 값 |
|---|---|
| 신청 이름 (우리끼리 보는 이름) | `Slow Margin — gather links, photos and videos as files` |
| 종류 | **App Enhancements** (업데이트) |
| 날짜 (알릴 때) | **2026-11-02** (D — 홍보 주 첫날). 그때 나와 있는 판을 알린다 |
| 나라 | 대한민국 · 미국 (+ 전 세계) |
| 관련 인앱 이벤트 | §3 의 이벤트 (승인 2026-10-16) — 추천 신청에 잇는 칸이 보이면 잇는다 · 이었는지는 아직 기록 없음 |

**설명 — 2026-10-25 판 (영어 · 921자 · 1.1.15 까지: 최근 고친 노트로 보내기 · 폴더 화면 찾기 칸 · 지도 장소 · 노트가 많아도 빠름)** — 10-26 할 일 3. 고칠 수 있으면 이것으로 간다.

```
Slow Margin is a Markdown notes app for iPhone and iPad, made by a solo developer in Korea around one promise: your writing stays as plain files. There is no app database and no account. Every note is a .md file in your own iCloud folder, visible in the Files app, readable in any editor, and still there if you delete the app.

Recent updates make it a calm place to gather and find what you keep. Share a video or a web page from any app, pick a pinned or recently edited note, and its title and link are added as a new line at the end of that note. A search field at the top of the folders screen searches every note, and tapping it shows your ten most recently edited notes. Pasting a place copied from a map app turns it into one line with the place name and address, and the app stays quick even with thousands of notes.

The app is fully localized in Korean and English, follows Dynamic Type, and collects no data.
```

**설명 (영어 · 그대로 붙인다 · 892자 — 2026-10-12 다시 씀: 1.1.5 의 깔끔한 미리보기 · 사진 · 동영상 붙여넣기를 더함) — 낸 것**

```
Slow Margin is a Markdown notes app for iPhone and iPad, made by a solo developer in Korea around one promise: your writing stays as plain files. There is no app database and no account. Every note is a .md file in your own iCloud folder, visible in the Files app, readable in any editor, and still there if you delete the app.

Recent updates make it a calm place to gather what you find. Share a video or a web page from any app, pick a pinned note, and its title and link are added as a new line at the end of that note. Paste a note that mixes text, photos and videos, and each photo and video lands in its place, saved as a real file next to the note. The note list and search results now show clean text instead of Markdown symbols, and code blocks in Read mode have Copy and Expand buttons.

The app is fully localized in Korean and English, follows Dynamic Type, and collects no data.
```

**한국어 뜻 (확인용 — 내지 않는다).** 느린 여백은 *글은 파일로 남는다* 는 약속 하나로 한국의 1인 개발자가 만든 아이폰 · 아이패드 마크다운 노트 앱입니다.
앱 데이터베이스도 계정도 없습니다 — 모든 노트는 사용자 iCloud 폴더의 `.md` 파일이고, 파일 앱에서 보이며 어떤 편집기로도 열리고, 앱을 지워도 남습니다.
최근 업데이트로 *찾은 것을 차분히 모으는 곳* 이 되었습니다 — 어떤 앱에서든 동영상이나 웹 쪽을 공유하고 고정한 노트를 고르면 그 노트 끝에 제목과 링크가 한 줄씩 쌓입니다.
글 · 사진 · 동영상이 섞인 노트를 붙여 넣으면 사진과 동영상이 제자리에 들어가고, 노트 옆에 진짜 파일로 저장됩니다. 노트 목록과 검색 결과는 마크다운 기호 대신 깔끔한 글을 보여 주고,
읽기 화면의 코드 상자에는 복사 · 크게 보기 단추가 있습니다. 한국어 · 영어로 모두 쓸 수 있고, 글자 크기 설정을 따르며, 데이터를 모으지 않습니다.

**콘솔에서 (사용자):** App Store Connect **웹 사이트** → **앱**(Apps) → *느린 여백* → 왼쪽 사이드바 **Featuring** 제목 아래 **Nominations** →
**+** (처음이면 **Get Started**) → 위 표대로 채우기 → 설명 붙이기 → **제출**. 제출 전에는 초안으로 남는다.
역할이 Account Holder · Admin · App Manager · Marketing 중 하나여야 메뉴가 보인다.
칸이 위와 다르면(이름 · 한도 · 고를 것) 화면을 보내 주신다 — 맞춰 고친다.
(2026-10-12 고침 — 처음에 *홈 화면 → 추천 신청* 으로 잘못 적어 사용자가 메뉴를 못 찾았다. 애플 도움말 *Nominate your app for featuring* 기준.)

> ✅ **제출함 — 2026-10-12** (사용자 — *추천 신청 제출 완료했어*). 관련 인앱 이벤트 칸은 비워 냈다 — §3 의 이벤트를 만든 뒤 이을 수 있으면 잇는다.
> 뽑혔는지는 따로 알려 주지 않는다 — D 주에 투데이 탭 · 검색을 보고 §7 에 적는다.

## 3. 인앱 이벤트 — 검색 결과 · 투데이 탭의 카드

**이벤트는 앱 안에서 실제로 할 수 있는 일**이어야 한다. *고정한 노트에 링크 모으기* 는 지금 앱에서 된다 (1.1.3). 기간은 최대 31일.

| 칸 (한도) | 한국어 | 영어 |
|---|---|---|
| 배지 | **대규모 업데이트** (Major Update) — 또는 *특별 이벤트* | Major Update |
| 이벤트 이름 (30) | 보던 링크를 한 노트에 모으기 (16) | Collect Links in One Note (25) |
| 짧은 설명 (50) | 공유 한 번이면 고정한 노트 끝에 제목과 링크가 쌓입니다 (31) | Share once. The title and link land in your note. (49) |
| 긴 설명 (120) | 동영상이나 웹 쪽을 보다가 공유 → 느린 여백 → 고정한 노트를 고르면, 그 노트 맨 끝에 제목과 링크가 한 줄씩 쌓입니다. 같은 주제는 한 노트에. (83) | Share a video or page to Slow Margin and pick a pinned note. Its title and link are added as a new line at the end. (115) |
| 목적 | 기존 사용자에게 알리기 · 새 사용자 끌기 | |
| 바로 가기 | `slowmargin://event` (필수 칸 — 아래 표 · 1.1.7 부터) | |

**그림 두 장 — 만들었다 (2026-10-12 사용자 — *그림 두 장 지금 만들어 줘*).** `python3 Tools/store/event_art.py` →

| 칸 | 한국어 | 영어 |
|---|---|---|
| 이벤트 카드 (가로 1920 × 1080) | `docs/store/event/ko-card.png` | `docs/store/event/en-card.png` |
| 이벤트 상세 (세로 1080 × 1920) | `docs/store/event/ko-detail.png` | `docs/store/event/en-detail.png` |

- 원본은 1.1.5 와 함께 낸 스토어 스크린샷 3번(링크 모음)에서 **앱 화면만** 도로 잘라 썼다 — 글귀는 없다.
- 앱 스토어가 이벤트 이름 · 짧은 설명을 **그림 아래쪽에 얹는다** — 앱 화면은 위쪽 · 가운데에 두고(카드는 양옆이 조금 잘릴 수 있다),
  아래쪽은 먹색으로 서서히 어둡게 했다. 링크 줄은 카드에서 위 62% 안, 상세에서 위 55% 안에 있다.
- 이벤트는 언어마다 그림을 따로 올린다 — 한국어 칸에 `ko-…`, 영어 칸에 `en-…`.
- 애플은 안전 영역을 숫자로 밝히지 않는다 — 콘솔의 **미리보기**에서 글이 링크 줄을 가리면 화면을 보내 주신다 (`LAYOUTS` 의 `top` · `width` 를 고친다).

**콘솔 순서 (2026-10-14 사용자 — *인앱 이벤트 만들기 순서 알려줘*).** 애플 도움말 *Offer in-app events* · WWDC21 *Meet in-app events* 기준. 칸 이름 · 자리는 콘솔이 최종이다.

| 칸 | 값 |
|---|---|
| 참조 이름 (64 · 콘솔에서만 보임) | `Slow Margin launch week 2026-11` — 영문으로 |
| 공개 시작 (이벤트 시작 **최대 14일 전**) | **2026-10-19** — 이날부터 *곧 시작* 카드로 보이고, 사용자가 *알림 받기* 를 누를 수 있다 |
| 이벤트 시작 · 끝 (최대 31일) | **2026-11-02 09:00 ~ 2026-11-30 23:00** (한국 시각) |
| 목적 | 하나만 고른다 — **모든 사용자에게 적합** (Appropriate for All Users). 없으면 가장 가까운 것 |
| 우선순위 | 보통 (이벤트가 하나뿐) |
| 바로 가기(딥 링크) | **필수 칸이다** (2026-10-15 사용자) — `slowmargin://event` · 이 주소를 여는 판(1.1.7 · 248)이 **먼저 나와 있어야** 한다 |
| 나라 | 전체 (앱 판매 지역과 같게) |

1. App Store Connect → **앱** → *느린 여백* → 왼쪽 사이드바 **인앱 이벤트**(In-App Events) → **+** (처음이면 *인앱 이벤트 만들기*)
2. **참조 이름** 을 넣고 만든다
3. 기본 언어 **한국어** 칸 — 이벤트 이름 · 짧은 설명 · 긴 설명 (위 표) · **배지** *대규모 업데이트* ·
   **이벤트 카드** 칸에 `docs/store/event/ko-card.png` · **이벤트 상세** 칸에 `docs/store/event/ko-detail.png`
4. 미리보기에서 이름 · 짧은 설명이 링크 줄을 가리는지 본다 — 가리면 화면을 보내 주신다 (그림을 고친다)
5. **현지화**에 **영어(미국)** 를 더한다 → 영어 이름 · 짧은 설명 · 긴 설명 · `docs/store/event/en-card.png` · `en-detail.png`
6. **이벤트 정보** — 목적 · 우선순위 · 바로 가기(`slowmargin://event` — 1.1.7 출시 뒤) · **일정** — 공개 시작 · 이벤트 시작 · 끝 · 나라 (위 표)
7. **저장** → **심사에 추가** → **심사에 제출**. 앱 판 없이 이벤트만 따로 심사받는다
8. 승인되면 알려 주신다 — 추천 신청(§2)을 고칠 수 있으면 *관련 인앱 이벤트* 에 이 이벤트를 잇는다

> ✅ **1.1.7 출시 (2026-10-15 사용자 — *심사 배포 완료*) → 이벤트 제출.** ✅ **이벤트 심사 제출 — 2026-10-15** (사용자 — *이벤트 심사 제출 했어*). 바로 가기 `slowmargin://event` · 시작 11-02 09:00 · 끝 11-30 23:00. 승인되면 추천 신청(§2)에 잇는다. ✅ **이벤트 승인 — 2026-10-16** (사용자 — *이벤트도 승인되었어*). (2026-10-15 사용자 — *1.1.7 앱 심사부터 우선 제출했어. 배포가 되면 그때 이벤트 제출을 할게*). 이벤트는 바로 가기만 빼고 **저장**해 두었다.
> 1.1.7 (빌드 106 · `slowmargin://`) 출시 → 바로 가기 `slowmargin://event` · 공개 시작 날짜(지났으면 오늘 뒤로) 확인 → 이벤트 심사 제출. 1.1.6 은 이 주소를 몰라 먼저 내면 거절될 수 있다.
>
> 일찍 내도 된다 — 공개 시작 날짜 전에는 보이지 않는다. 심사가 며칠 걸릴 수 있으니 **10-19 전에 내 두는 편**이 안전하다.
> 승인된 이벤트는 앱마다 15개 · 공개는 10개까지. 이벤트는 최소 15분 · 최대 31일.

## 4. 블로그 글 — 출시 날 (네이버 · 1 · 2 · 3편과 같은 꼴: 본문에 기호 없음 · ▌ 줄만 소제목 · [사진 n] 자리)

```
보던 링크를 한 노트에 모으는 법 — 느린 여백

볼 만한 영상이나 글을 발견하면 어떻게 하시나요. 저는 늘 "나중에 봐야지" 하고 어딘가에 링크를 던져 두었다가, 정작 다시 찾을 때는 어디에 두었는지 몰라 헤맸습니다. 그래서 느린 여백에 모으는 길을 하나 만들었습니다.

▌ 공유 한 번이면 끝

[사진 1 — 공유 창의 넣을 곳]
동영상이나 웹 쪽을 보다가 공유를 누르고 느린 여백을 고릅니다. 공유 창 아래 "넣을 곳"에서 고정해 둔 노트나 최근에 고친 노트를 고르고 보내면 끝입니다. 앱을 열면 그 노트 맨 끝에 제목과 링크가 한 줄로 붙어 있습니다.

[사진 2 — 링크가 쌓인 노트]
같은 주제는 한 노트에 계속 쌓입니다. 마지막에 고른 노트를 기억해 두니, 두 번째부터는 공유 → 보내기 두 번이면 됩니다. 공유 창 글 칸에 "2부부터" 같은 메모를 쓰면 그 줄 끝에 같이 붙습니다.

▌ 주소만 보내는 앱이어도 제목이 들어갑니다

어떤 앱은 공유할 때 주소만 보냅니다. 그러면 노트에 알 수 없는 주소만 남지요. 느린 여백은 그럴 때 그 쪽의 제목을 한 번 읽어 와 링크 이름으로 씁니다. 제목 말고는 아무것도 주고받지 않습니다.

▌ 그래도 파일입니다

[사진 3 — 파일 앱의 같은 폴더]
이렇게 모인 노트도 결국 내 iCloud 폴더의 .md 파일 하나입니다. 파일 앱에서 그대로 보이고, 다른 편집기로 열어도 같은 줄들이 보입니다. 앱을 지워도 남습니다. 느린 여백이 처음부터 지키려던 한 가지입니다.

▌ 자음만 쳐도 찾습니다

[사진 4 — 찾기 칸에 ㅎㅇㄹ]
(사진 설명: 제목 옆 가가 표시는 제목에서 찾았다는 뜻입니다)
노트가 쌓이면 찾는 일이 늘어납니다. 폴더 화면 맨 위 찾기 칸에 ㅎㅇㄹ 처럼 자음만 쳐도 제목이 한여름 일기, 회의록인 노트가 나옵니다. 자판이 ㄱㅅ 을 ㄳ 한 글자로 합쳐도 알아서 풀어 찾습니다. 본문은 지금처럼 두 글자부터 찾습니다.

▌ 최근 업데이트에 함께 들어간 것

폴더 화면 맨 위에 모든 노트에서 찾기 칸이 생겼습니다. 폴더에 들어가지 않아도 모든 노트를 찾고, 빈 칸을 누르면 최근에 고친 노트 열 개가 먼저 보입니다. 지도 앱에서 복사한 장소를 붙이면 장소 이름 링크와 주소 한 줄이 됩니다. 노트가 수천 개여도 빠르게 움직이고, 오래 걸리는 일은 화면 아래 띠로 얼마나 남았는지 보여 줍니다. 앱 아이콘도 새로 그렸습니다.

사진 · 동영상 · 글이 섞인 내용을 통째로 복사해 붙이면 사진과 동영상이 제자리에 들어가고, 노트 옆에 진짜 파일로 저장됩니다.

느린 여백은 무료이고, 계정도 광고도 없습니다. 써 보시고 좋았다면 앱 스토어에 평가 한 줄 남겨 주시면 큰 힘이 됩니다.

앱 스토어: (캠페인 링크 — blog-links)
```

> **2026-10-22 — 1.1.10 ~ 1.1.12 를 더했다** (폴더 화면 찾기 칸 · 최근 고친 노트 · 지도 장소 · 속도 · 진행 띠 · 새 아이콘). **2026-10-25 — 1.1.15 까지 출시되어 모든 문장을 그대로 쓴다.**
> [사진 4] 는 옛 찾기 칸(빌드 115 전)에서 찍었다 → **10-26 할 일 2 — 폴더 화면 맨 위 찾기 칸에서 다시 찍는다.**
>
> **[사진 4] 다시 찍음 — 2026-10-25** (사용자 화면 — 폴더 화면 맨 위 찾기 칸 · `ㅎㅇㄹ` · 한여름 일기 · 회의록 둘 다 가가 표시 · 자판 보임). ✅ 상태 막대 · 맨 아래 지구본 줄까지 잘라 냄 — **준비 끝** (2026-10-25 다시 검토). 사진에 둘 다 나와서 본문을 *한여름 일기, 회의록* 으로 고쳤다.
> **[사진 1 ~ 3] 찍는 법** (2026-10-25 사용자 — *사진 1-3도 다시 찍을 수 있게 가이드해줘.* · 공유 화면 `ShareViewController` · 기억하는 넣을 곳 · 덧붙는 줄 `share_entry` 를 읽고 적었다)
> - **준비** — 앱에서 새 폴더 `블로그 시험` → 그 안에 노트 `읽을거리` (본문 `천천히 읽을 것들.`) → 노트 목록에서 왼쪽으로 밀어 **고정**. 사파리에서 공개 글 2~3개를 골라 둔다 (제목에 사이트 · 서비스 이름이 없는 글).
> - **[사진 1]** 글 하나에서 공유 → **느린 여백** → *느린 여백에 보내기* → **넣을 곳** 을 눌러 메뉴(새 노트 · 고정한 노트 · 최근 고친 노트)가 펼쳐진 채로 찍는다 → 읽을거리를 고르고 글 칸에 `2부부터` → 보내기.
> - **[사진 2]** 나머지 글도 공유 → 보내기 (넣을 곳은 읽을거리가 기억돼 있다) → 앱을 연다 → 읽을거리를 **읽기 모드**로 → 링크 줄들과 `— 2부부터` 가 붙은 줄이 보이게 찍는다.
> - **[사진 3]** 파일 앱 → 둘러보기 → iCloud Drive → 앱이 쓰는 폴더(기본은 `Slow Margin`) → `블로그 시험` → `읽을거리` 가 보이게 찍는다. 덤: 파일을 눌러 미리보기에 `- [제목](주소)` 줄이 글로 보이면 그것도 한 장.
> - 모두 상태 막대를 잘라 낸다. 블로그를 올린 뒤 `블로그 시험` 폴더는 지워도 된다.
> **[사진 1 ~ 4] 검토 — 2026-10-25** (사용자 화면 넷). [사진 4] ✅. [사진 1] ✅ 쓸 수 있음 (넣을 곳 메뉴를 펼친 판이면 더 좋다 — 고르지 않아도 됨).
> [사진 2] 링크 줄에 **실존 인물 이름 · 항공사 이름**이 든 영상 제목이 있다 → 그 두 줄을 이름 없는 글로 바꿔 다시 찍는다 (`— 2부부터` 줄은 그대로 좋다).
> [사진 3] 개인 노트 이름(가족 · 돈 · 인물)이 그대로 보이고 맨 아래 *동기화하는 중* 띠 → **시험 폴더에서 다시 찍는다** (파일 이름은 공개 저장소에 적지 않는다).
> (옛 판) **[사진 4] 준비됨** (2026-10-14 사용자 — 시험 노트 `회의록` · `한여름 일기` · 검색 `ㅎㅇㄹ` · 자판이 보이게 · 상태 막대는 잘라 냄).
> 사진은 사용자 기기에 있다 — 공개 저장소라 올리지 않는다. 블로그를 올린 뒤 시험 노트 둘은 지워도 된다.

## 5. 국내 — 메이커 모임 · 개발자 소식 · 스레드 · 사용자 게시판

**올리기 전에 그 게시판의 자기 홍보 규칙을 먼저 본다** — 허용 게시판 · 말머리 · 횟수. 같은 글을 여러 곳에 그대로 붙이지 않는다 (아래 셋은 서로 다르게 썼다).

**메이커 모임 (만든 이야기 중심)**

```
혼자 만든 아이폰 마크다운 노트 앱, 느린 여백을 업데이트했습니다.

처음 정한 원칙은 하나였습니다 — 글은 파일로 남는다. 앱 데이터베이스가 없고, 모든 노트가 내 iCloud 폴더의 .md 파일입니다. 최근 판에서 "모으는 길"을 더했습니다. 어떤 앱에서든 공유 → 고정한 노트나 최근 고친 노트를 고르면 그 노트 끝에 제목과 링크가 한 줄씩 쌓입니다. 찾는 길도 넓혔습니다 — 찾기 칸에 ㅎㅇㄹ 처럼 자음만 쳐도 제목으로 찾고, 폴더 화면 맨 위 찾기 칸은 모든 노트를 찾으며 비워 두면 최근 고친 노트 열 개를 보여 줍니다.

만들면서 배운 것 하나: 공유로 넘어오는 것이 앱마다 다릅니다. 주소를 "주소"로 주는 앱이 있고 "글"로 주는 앱이 있어서, 글 칸에 주소 하나만 온 경우를 따로 가려야 했습니다. 이런 판단은 파이썬으로 같은 셈을 한 번 더 짜서 정답표를 만들고, 앱의 테스트가 그 표를 따르게 했습니다. 초성 찾기는 일부러 두 셈을 다르게 짰습니다 — 앱은 음절 번호로, 파이썬은 유니코드 글자 이름으로 첫소리를 구해 서로의 심판이 되게 했습니다.

무료 · 계정 없음 · 데이터 수집 없음입니다. 피드백 주시면 다음 판에 반영하겠습니다.
(캠페인 링크 — disquiet)
```

**개발자 소식 (Show 글 · 기술 중심)**

```
Show: 느린 여백 — 노트가 그냥 iCloud 의 .md 파일인 iOS 마크다운 앱

- 앱 DB 없음. 파일이 원본이고, 검색 색인(SQLite FTS5)은 언제 지워도 되는 캐시입니다.
- 편집기의 문자열은 언제나 마크다운 원문 하나 — 보이는 모양은 글꼴 · 색 · 기호 숨김 같은 속성으로만 냅니다. 저장은 원문 그대로.
- 리눅스 원격 세션에서 개발하고 macOS 자동 빌드 검사 · TestFlight 로 확인합니다. 순수 로직은 파이썬으로 같은 셈을 짜 만든 정답표로 시험합니다.
- 최근 업데이트: 공유로 받은 링크를 고정한 노트 · 최근 고친 노트 끝에 한 줄씩 덧붙이기 · 제목 초성 검색(앱은 음절 번호, 파이썬 쌍둥이는 유니코드 글자 이름으로 셈해 서로 검증) · 안 받은 노트가 아주 많은 iCloud 폴더는 제목만 색인 · 역링크를 색인에서 읽고 저장은 그 노트 하나만 다시 색인(노트 1,000개 첫 색인 4.26초) · 폴더 화면에서 모든 노트 찾기 · 빈 칸이면 최근 고친 노트 10개.
(캠페인 링크 — geeknews)
```

**스레드 (네 번에 나눠)**

```
1) 볼 영상 · 읽을 글 링크, 어디에 모아 두세요? 저는 이제 노트 한 장에 모읍니다. 공유 → 느린 여백 → 고정한 노트. 끝.
2) 모인 노트는 그냥 내 iCloud 의 .md 파일이에요. 파일 앱에서도 보이고, 앱을 지워도 남습니다.
3) 찾을 때는 검색 칸에 ㅎㅇㄹ 만 쳐도 회의록이 나와요.
4) 혼자 만든 무료 앱이고 계정도 광고도 없습니다. (캠페인 링크 — threads)
```

**아이폰 · 맥 사용자 게시판 (사용기 꼴)** — 블로그 글(§4)을 줄여 사진 세 장(공유 창 · 링크가 쌓인 노트 · 초성 검색)과 함께. 꼬리표 `forum-ko`.

## 6. 해외 — 영어판

**Product Hunt**

| 칸 (한도) | 값 |
|---|---|
| Name | Slow Margin |
| Tagline (60) | Markdown notes that stay as files in your iCloud (48) |
| Description (260) | Slow Margin is an iPhone and iPad Markdown notes app with no database: every note is a plain .md file in your own iCloud folder. Write with live formatting, read cleanly, link notes, and collect links from the share menu into a pinned note. (240) |
| 첫 댓글 | 아래 Reddit 글을 줄여서 — 왜 만들었나 · 무엇을 안 하나(계정 · 광고 · 수집 없음) |

**Reddit (아이폰 앱 게시판 — 자기 홍보 규칙 · 말머리 확인)** — 꼬리표 `reddit`

```
I made a Markdown notes app where every note is just a file in your iCloud

Hi! I'm a solo developer from Korea. Slow Margin is a free iPhone/iPad notes app built around one rule: your writing stays as plain .md files in your own iCloud folder. No database, no account, no ads, no data collection. Delete the app and your notes are still there in the Files app.

What it does:
- Live Markdown editing: only the line with the cursor shows the symbols
- A clean Read mode with tables, images, and code blocks (copy / expand)
- Link notes with [[ and see which notes link back
- New: share a video or web page, pick a pinned or recently edited note, and the title + link are added as a new line at the end
- New: paste a mix of text, photos and videos, and each photo and video lands in place, saved as a real file next to the note
- New: search Korean note titles by their initial consonants (ㅎㅇㄹ finds 회의록)
- New: a search field at the top of the folders screen searches every note; tap it while empty to see your 10 most recently edited notes

Feedback very welcome, especially on what feels missing.
```

**Show HN** — 제목 (80): `Show HN: Slow Margin – iOS Markdown notes that are just files in iCloud` (71) · 본문은 개발자 소식 글(§5)을 영어로 — 파일이 원본 · 색인은 캐시 · 원문 하나 · 정답표.

## 7. 결과 (출시 뒤 적는다)

| 날 | 꼬리표 | 노출 · 다운로드 (앱 분석) | 메모 |
|---|---|---|---|
| | | | |
