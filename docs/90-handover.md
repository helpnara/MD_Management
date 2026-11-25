---
title: 이관 안내 — 다른 계정에서 느린 여백을 이어 관리하기
updated: 2026-11-25
---

# 이관 안내 — 다른 계정에서 이어 받기

> 2026-11-25 사용자 — *현재 앱을 다른 계정에서 계속 사후 관리 및 기능 개선을 할 수 있도록 이관 MD 파일을 만들어줘.*
>
> **이 문서 하나로 새 계정의 첫 세션이 이어 받는다.** 자세한 것은 이미 저장소의 문서에 있다 — 여기는 **지도와 순서**만 둔다.
> **이 저장소는 공개다** — 비밀 값 · 메일 주소 · 개인 정보는 적지 않았다. 이름과 자리만 적었다. 값은 사람이 따로 보관한다.

---

## 0. 새 계정의 첫 세션에 이렇게 말한다

새 계정에서 Claude Code 원격 세션을 `helpnara/MD_Management` 저장소로 연 뒤, 첫 메시지로:

```
느린 여백 앱을 이어 받는다. 먼저 작업 브랜치 claude/yeobek-app-design-review-gljamw 를 지금 브랜치에 병합하고,
docs/90-handover.md 의 §3 첫 세션 점검을 한 뒤, CLAUDE.md 의 읽는 순서대로 읽고 지금 어디까지인지 한 줄로 알려줘.
```

새 세션이 할 일은 이 문서 §3 에 있다. 그 뒤로는 **`CLAUDE.md` 가 세션 규약의 원본**이다 — 이 문서와 갈리면 `CLAUDE.md` 를 따른다.

---

## 1. 앱 한눈에

| | |
|---|---|
| 이름 | 한국어 **느린 여백** · 영어 **Slow Margin** |
| 하는 일 | 아이폰 · 아이패드 마크다운 기록 앱. **파일이 원본** — 사용자 iCloud 폴더의 `.md` 와 이미지를 그대로 읽고 쓴다. 앱 DB 없음 |
| 번들 | `com.helpnara.markdown` (앱) · `com.helpnara.markdown.share` (공유 확장) · iCloud 컨테이너 `iCloud.com.helpnara.markdown` |
| 앱 스토어 | `https://apps.apple.com/app/id6811515067` |
| 저장소 | `helpnara/MD_Management` (**공개** — macOS 러너가 무료라서. 비공개로 바꾸면 처리방침 페이지가 꺼진다 — CLAUDE.md §5) |
| 만드는 법 | 세션(리눅스 · Xcode 없음) → GitHub Actions macOS 러너(`xcode-27` · Xcode 27.1 · iOS 27 SDK) → TestFlight → 사람이 실기기 확인 → 심사 |
| 구조 | `Packages/Core/` 순수 로직(리눅스 `swift test`) · `App/` SwiftUI + UIKit · `ShareExtension/` · `Shared/` · `Tools/` 파이썬 도구 — `README.md` §구조 |

---

## 2. 지금 상태 (2026-11-25)

| | |
|---|---|
| 출시된 판 | **1.1.28 (빌드 156)** — 2026-11-22 승인 · 배포. 326 · 327 제목 앞의 HTML 주석 (`docs/89-build-156.md`) |
| `main` | **= 1.1.28** (병합 커밋 `d0946c1`). 그 뒤 작업 브랜치에는 **문서 커밋만** 있다 (승인 기록 · 328 · 이 문서) |
| 작업 브랜치 | `claude/yeobek-app-design-review-gljamw` — 지금까지의 모든 일이 여기. **새 세션은 이것을 먼저 병합한다** (§3) |
| 열린 이슈 | **328** 🟡 — 문서 첨부로 PDF 를 못 넣었을 때 빨간 띠에 *파일 앱에서 그 파일을 길게 눌러 복제한 뒤 사본을 넣어 보세요* 안내 문구만 더한다 (사용자 결정). 다음 빌드에 다른 이슈와 묶는다 — `docs/08-feedback.md` 맨 위 표 |
| 다음 판 | 1.1.29 — 이슈가 5개 안팎 모이면 *착수할까요?* (CLAUDE.md §3·1) |
| 쓰는 규모 | 사용자가 노트 약 450개로 날마다 쓴다 — 작은 이슈도 번호로 받는다 |

### 날짜가 정해진 일 — **사람이 직접 챙긴다**

| 날짜 (한국 시간) | 할 일 | 비고 |
|---|---|---|
| **12-01 (화) 아침** | App Store Connect **프로모션 텍스트를 원래 글로 되돌린다** (한국어 · 영어 둘 다 · 심사 없이 바뀐다) | 원래 글은 `docs/12-submission.md` §1 *프로모션 텍스트* · §1-영어 *Promotional Text*. 끝나면 `docs/promo/launch-kit.md` §0 의 D 날 줄에 *12-01 되돌림* 을 적는다. **옛 계정에 예약해 둔 알림은 새 계정으로 안 따라온다** — 새 세션에 *12월 1일에 알려줘* 라고 다시 예약하거나 직접 챙긴다 |
| 11-26 (목) 18:00 | 유튜브 쇼츠 *회의록 찾기 편* 게시 (이미 예약됨) | 조회수 비교는 `docs/promo/youtube-shorts.md` |

---

## 3. 새 계정에서 처음 한 번

### 3.1 사람이 할 것 (세션 밖)

| # | 무엇 | 어디서 |
|---|---|---|
| 1 | 새 Claude 계정에 **GitHub 연결** — 이 저장소에 **쓰기(Write) 권한**이 있는 GitHub 계정이어야 한다 | claude.ai → 설정 → 커넥터 → GitHub. 다른 GitHub 계정이면 저장소 주인 계정에서 Settings → Collaborators 로 초대 |
| 2 | Claude Code 원격 환경은 **기본 네트워크**(패키지 레지스트리 허용)면 된다 | 새 세션을 만들 때 저장소 `helpnara/MD_Management` 를 고른다 |
| 3 | GitHub **시크릿 4개는 저장소에 그대로 있다** — 다시 넣을 필요 없다 (저장소가 같으면) | Settings → Secrets and variables → Actions: `APPLE_TEAM_ID` · `APP_STORE_CONNECT_ISSUER_ID` · `APP_STORE_CONNECT_KEY_ID` · `APP_STORE_CONNECT_KEY_P8` |
| 4 | 애플 개발자 계정 · App Store Connect · 유튜브 채널 · 블로그는 **사람 계정 그대로** — 바꿀 것 없다 | — |

> 저장소를 **다른 GitHub 계정 · 다른 저장소로 옮기는** 경우만 시크릿 넷을 새로 넣는다. `.p8` 키 파일은 처음 받을 때 한 번만 내려받을 수 있다 — 보관본이 없으면 App Store Connect 에서 새 키를 만든다 (`docs/06-ci.md` §2.0). 처리방침 페이지(GitHub Pages)도 새 저장소에서 Settings → Pages → Source 를 **GitHub Actions** 로 켜야 하고, 주소가 바뀌면 App Store Connect 의 처리방침 · 지원 URL 도 바꿔야 한다.

### 3.2 새 세션이 할 것 — 첫 세션 점검

```bash
# 1) 최신 일을 가져온다 — 새 세션은 main(= 1.1.28 병합 시점)에서 새 claude/… 브랜치를 받는다
git fetch origin claude/yeobek-app-design-review-gljamw
git merge --no-edit FETCH_HEAD          # 문서 커밋만 더해진다 (충돌 없음이 정상)

# 2) 여기서 돌릴 수 있는 심판 — 모두 통과해야 정상
pip install -r Tools/golden/requirements.txt   # markdown-it-py · PyYAML · cmarkgfm (없을 때만)
python3 Tools/golden/generate.py --check       # 기댓값이 최신 — "커밋된 것과 같습니다"
python3 Tools/l10n/build.py --check            # 번역 454 / 454
python3 Tools/store/count.py                   # 스토어 칸 글자 수 — 모두 OK
python3 Tools/contrast.py                      # 글자 색 대비 — 모두 OK
```

- **새 작업 브랜치 이름**: 세션마다 `claude/…` 새 이름을 받는다. 워크플로는 `claude/**` 에서 다 돈다 — 그대로 쓰면 된다. CLAUDE.md §5 의 *작업 브랜치* 는 이제 그 새 이름이다. 옛 브랜치 `claude/yeobek-app-design-review-gljamw` 에는 더 푸시하지 않는다 (CI 가 두 브랜치에 갈려 돈다).
- 점검이 끝나면 `docs/roadmap.md` 맨 위 줄에 *계정 이관 (날짜) · 새 작업 브랜치 이름* 을 적고, 옛 줄은 *지난 상태 줄* 맨 위로 옮긴다 (CLAUDE.md §3·7).

---

## 4. 읽는 순서 (CLAUDE.md §0 과 같다)

| 차례 | 문서 | 왜 |
|---|---|---|
| 1 | `CLAUDE.md` | 세션 규약 — 한글로 답 · 시각은 한국 시간 · 빌드 규율 · 코드 경계 · 디자인 기준 |
| 2 | `docs/roadmap.md` 맨 위 줄 | 지금 어디까지 |
| 3 | `docs/08-feedback.md` 맨 위 *지금 열린 것* 표 | 열린 이슈 (번호는 328 까지 썼다 — 다음은 **329**) |
| 4 | `docs/adr/README.md` | 되돌리기 비싼 결정 10개 |
| 5 | `docs/06-ci.md` | 워크플로 여덟 개 · TestFlight · 시크릿 |
| 6 | `docs/12-submission.md` §6 | 업데이트 판 내기 — 매번 이 순서 |
| 필요할 때 | `docs/00-design.md` · `docs/11-store-screenshots.md` · `docs/promo/README.md` · `docs/promo/youtube-shorts.md` · 빌드 문서 `docs/NN-build-NNN.md` | 설계 · 스토어 그림 · 홍보 영상 · 빌드마다의 확인 목록 |

---

## 5. 한 판이 나가는 길 (요약 — 원본은 CLAUDE.md §3 · `docs/12-submission.md` §6)

1. **모으기** — 사용자가 쓰다 찾은 것을 `docs/08-feedback.md` 에 번호 · 🔴🟡🔵🟢🟠 로 적는다. 5개 안팎이면 *착수할까요?* (자료 유실 · 저장 실패만 바로).
2. **만들기** — 경우의 수를 표로 깔고 → **파이썬 쌍둥이 · 사례(JSON)를 먼저** (`Tools/golden/`) → Swift → `generate.py --check` 통과 뒤 푸시. 기댓값을 손으로 적지 않는다.
3. **판 번호** — `project.yml` 의 `MARKETING_VERSION` 을 올린다 (지금 `1.1.28` → 다음 `1.1.29`). 빌드 번호는 TestFlight 실행 번호가 된다.
4. **자동 빌드 검사** — 푸시하면 `core-test.yml`(리눅스 2~4분) · `build.yml`(맥 · 컴파일 뒤 화면 사진 25~35분). 새 글이 있으면 번역 단계는 `l10n.yml` 이 열쇠를 뽑을 때까지 잠깐 빨갛다 (§6).
5. **TestFlight** — 수동. GitHub MCP `actions_run_trigger` → `run_workflow` · `workflow_id: testflight.yml` · `ref: <작업 브랜치>`. 5~10분 + 애플 처리 10~30분.
6. **확인 목록** — `docs/NN-build-NNN.md` 에 **표 하나** (`| # | 확인 (빌드 N) | 어디서 · 조건 |`, 0번 = 판 `설정` 맨 아래). 이름 · 경로 · 조건은 **코드에서 확인**한 것만. 사용자는 *0-n 확인 완료* 로 답한다.
7. **제출 준비** — 새로운 기능 글(한국어 · 영어)을 쓰고 `Tools/store/count.py` 로 센다 → `docs/store/<판>-새로운-기능.txt` · `docs/12-submission.md` 의 울타리 두 곳 · 제출 순서 절.
8. **제출 뒤** — 작업 브랜치를 `main` 에 **병합**(강제 푸시 · 되감기 없이, 화면 사진 충돌은 `-X theirs`) → 두 브랜치의 파일이 같은지 본다 (`git diff --name-only origin/main <작업 브랜치>` 가 비어야 한다).
9. **승인 · 배포 뒤** — 제출 문서 §0 · 로드맵 맨 위 · 이슈 문서 머리를 고친다.

### 자주 쓰는 손놀림

**자동 빌드 검사 상태 보기** (공개 저장소라 토큰 없이 된다):

```python
import json, sys, urllib.request
sha = sys.argv[1]   # git rev-parse HEAD
def get(u):
    return json.load(urllib.request.urlopen(urllib.request.Request(u, headers={"Accept": "application/vnd.github+json"}), timeout=30))
for r in get(f"https://api.github.com/repos/helpnara/MD_Management/actions/runs?head_sha={sha}&per_page=20")["workflow_runs"]:
    print(f"{r['name']}: {r['status']} {r['conclusion']} ({r['id']})")
```

실패하면 GitHub MCP `get_job_logs`(`run_id` · `failed_only: true` · `return_content: true` · `tail_lines: 80`)로 로그를 본다. **기다릴 때 `: completed` 를 줄에서 grep 하지 않는다** — 단계 줄에도 그 글자가 있어 일찍 끝난다. 실행의 `status` 를 본다.

**번역 (새 사용자 글을 넣을 때)** — 소스에 `String(localized: "…")` → `Tools/l10n/en.json` 에 영어 → `Tools/l10n/request.txt` 에 한 줄 → 푸시 → `l10n.yml` 이 `extracted.json` 을 커밋 → `git pull` → `python3 Tools/l10n/build.py` → `--check` → 커밋 · 푸시.

**스토어 그림** — `Tools/store/shots-request.txt` 에 한 줄 더해 푸시 → `store-shots.yml` (40분) → `docs/store/screenshots/{ko,en}/`. 글귀 글꼴 · 색은 `Tools/store/frame.py` 가 앱의 `Palette.swift` 에서 읽는다.

**홍보 영상** — `docs/promo/*-promo.html` + `render.js` (Playwright · ffmpeg — 세션 환경에 이미 있다):
`PROMO_DIR=$(pwd)/docs/promo PROMO_PAGE=<이름>-promo.html FFMPEG=/usr/bin/ffmpeg NODE_PATH=$(npm root -g) node docs/promo/render.js video out.mp4 30`.
유튜브 글 규칙 — 링크는 **설명과 고정 댓글 둘 다**에 (제목 · 태그에는 안 넣는다), 기본 링크 `https://apps.apple.com/app/id6811515067` (`docs/promo/youtube-shorts.md` 머리).

---

## 6. 꼭 지킬 것 (원본은 CLAUDE.md — 어기면 사고가 났던 자리)

- **사용자에게 보이는 글은 전부 한글.** 도구를 부르기 전의 한 줄 알림까지. 코드 이름 · 경로만 `코드 글씨`.
- **시각은 한국 시간(KST, UTC+9)** 으로 알린다 — CI 로그의 `Z` 시각도 바꿔 적는다.
- **파일이 원본 · 편집기 문자열은 마크다운 원문 하나 · 색인은 캐시**(판이 바뀌면 통째로 지우고 다시 — `SearchIndex.version`, 지금 6).
- **`Packages/Core` 는 SwiftUI · UIKit · SQLite3 를 import 하지 않는다** — 리눅스 `swift test` 가 사라진다.
- **같은 것을 재는 곳이 둘이면 갈린다** — 값을 쓰는 자리를 새로 만들기 전에 이미 재는 자리를 찾아 부른다 (최근 예: 327 — 첫 줄 셈과 이름 바꾸기가 다른 줄을 봐서 `<!--` 줄을 덮을 뻔했다 → `FrontMatterParser.titleLine` 하나로).
- **디자인은 늘 고급스럽게** (CLAUDE.md §7 · ADR-0010) — 색은 `Palette` 에서만, 제목은 명조, 목록은 `PaperList`.
- **공개 저장소** — 실제 지원 메일 · 시크릿 · 개인 정보 · 사용자의 노트 글을 문서에 적지 않는다.
- **스토어 · 사용자 글에 다른 앱 이름을 쓰지 않는다** · 없는 기능을 팔지 않는다 · 글자 수는 `count.py` 로.
- **애플 개발자 콘솔의 Description 칸은 영문 · 숫자 · 빈칸만** (App Store Connect 의 스토어 문구 칸은 한글 된다).
- 소스의 안내 문구에 **곧은 따옴표(`"`)를 쓰지 않는다** · 강조는 `**…**`.
- 커밋 메시지에 모델 이름을 적지 않는다. 문서만 고친 커밋은 `[skip ci]`.
- **푸시 전 `git pull --rebase`** — CI 가 `screenshots/` 를 커밋한다.

---

## 7. 함정 — 이미 한 번씩 걸린 것

| 자리 | 무엇 | 어떻게 |
|---|---|---|
| 세션 환경 | Xcode · Swift 가 없고 `download.swift.org` 는 막혀 있다. GitHub Pages(`helpnara.github.io`)도 여기서 못 연다 | 설치하려 하지 않는다. Swift 는 CI 로그가 첫 심판 — 보수적으로 쓴다. 페이지는 사람이 본다 |
| 맥에서만 나는 컴파일 오류 | 시험 함수 이름 `load()` 가 맥의 `NSObject.load` 와 겹쳐 *ambiguous* (빌드 156 첫 푸시 — 리눅스에는 없는 이름) | 시험의 정적 함수에 흔한 Objective-C 이름(`load` · `initialize` · `description`)을 쓰지 않는다 |
| 번역 단계 | 새 글을 넣은 첫 푸시는 `core-test` 의 번역 검사가 빨갛다 | `l10n.yml` 이 열쇠를 뽑은 뒤 `build.py` 로 다시 만들어 푸시하면 초록 (정상 흐름) |
| iOS 27 | SwiftUI 앱은 씬 매니페스트 없이도 뜬다 · iPadOS 27 은 세로 두 칸 · 가로 세 칸이 기본(323) · 자판 초점 테두리는 강조색(324 — 노트 목록만 `inkFaint` 로) | `docs/85-ios27-sdk-review.md` |
| 문서 첨부 창 | iOS 가 마지막 자리를 기억해 지운 폴더(최근 삭제된 항목)에 갇힐 수 있다(325) — 앱이 `directoryURL` 을 줘도 무시 | 앱 밖의 상태를 먼저 의심한다. 사용법에 푸는 길이 있다 |
| 다른 앱이 못 읽는 파일 | 내려받은 PDF 하나가 우리 앱 · 다른 앱 모두에서 안 올라감 — 파일 앱 **복제**본은 됨(328) | 앱이 고칠 수 없다 — 안내 문구로 |
| 확인 목록 | *마땅히 그래야 할 일* 로 적으면 없는 기능을 확인받는다 · 판 확인을 끝에 두면 옛 빌드로 본다 | 코드를 읽고 손가락이 할 동작으로 · 0번은 판 · 창 · 시트는 *열고 닫고 다시 열기* |
| 저장소 공개 상태 | 비공개로 바꾸면 처리방침 페이지가 꺼진다(175). 다시 공개해도 저절로 안 켜진다 | Settings → Pages → Source 를 **GitHub Actions** 로 |

---

## 8. 사람만 가진 것 (이 문서에 값이 없다)

| 무엇 | 어디 |
|---|---|
| 애플 개발자 계정 · App Store Connect 로그인 | 사람 |
| App Store Connect API 키 원본(`.p8`) 보관본 | 사람 (GitHub 시크릿에는 들어가 있다 — 꺼내 볼 수는 없다) |
| 지원 메일 주소 | 사람 · App Store Connect (문서에는 안 적는다) |
| 유튜브 채널 · 블로그 계정 | 사람 |
| 실기기(아이폰 · 아이패드 · 외장 자판) | 사람 — 확인 목록 · 진단 정보(`설정` → `도움` → 진단의 *최근 일* · *진단 정보 복사*) |

---

## 9. 옛 세션에만 있던 것 — 따라오지 않는다

- **예약 알림** — *12-01 프로모션 텍스트 되돌리기* (옛 계정의 세션에 묶여 있다). §2 표대로 새로 예약하거나 직접 챙긴다.
- **임시 폴더의 도우미 스크립트** — 자동 빌드 검사 보기(`runs.py`)는 §5 에 코드를 옮겨 두었다.
- **대화 기억** — 필요한 것은 모두 문서에 있다 (CLAUDE.md §0 *문서가 기억이다*). 빠진 것을 찾으면 이 문서에 더한다.
