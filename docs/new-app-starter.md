---
title: 새 앱 시작 안내 — 느린 여백에서 배운 그대로
updated: 2026-10-17
---

# 새 앱 시작 안내

> 2026-10-17 사용자 — *지금 환경으로 새로운 앱을 개발할 예정인데 필요한 설정이나 정보를 md파일로 정리해서 다음에 새로운 앱을 개발할 때 활용할 수 있게 해줘.*
>
> **쓰는 법.** 새 저장소를 만들면 이 파일을 `docs/` 에 복사하고, 첫 세션에 *이 문서대로 시작하자* 고 말한다.
> 느린 여백(`helpnara/MD_Management`)의 파일을 가져다 쓸 곳은 §9 에 모아 두었다.
> **이 문서에는 비밀 값이 없다** — 시크릿 · 메일 주소는 이름만 적었다. 값은 사람이 따로 보관한다.

---

## 1. 전체 그림 — 맥 없이 아이폰 앱을 만든다

| 누가 | 어디서 | 하는 일 |
|---|---|---|
| **세션** (Claude Code 원격) | 리눅스 컨테이너 | 코드 · 문서 · 파이썬 쌍둥이 · 정답표. **Xcode · Swift 가 없다** (`download.swift.org` 는 막혀 있다 — 설치하려 하지 않는다) |
| **GitHub Actions** | 리눅스 · macOS 러너 | Core 테스트(리눅스) · 앱 빌드 · 스크린샷 · TestFlight 업로드 · 번역 열쇠 뽑기 · 처리방침 페이지 |
| **사람** | 실기기 · 애플 콘솔 | 확인 목록 · 콘솔 등록 · 심사 제출 |

**검증 사다리** — 싼 것부터, 여기서 돌릴 수 있는 것은 다 돌린 뒤 푸시한다.

| 심판 | 잡는 것 | 어디서 | 비용 |
|---|---|---|---|
| 파이썬 쌍둥이 (`Tools/golden/`) | 순수 로직의 기댓값 | 세션에서 직접 | 초 |
| `swift test` (Core) | 순수 로직 | 리눅스 러너 | 2~4분 |
| 앱 빌드 | 문법 · 컴파일 | macOS 러너 | 10~35분 |
| 시뮬레이터 스크린샷 | 화면 | macOS 러너 | 15~30분 |
| TestFlight 실기기 | iCloud · 공유 · 권한 · 한글 조합 | 사람 | 30분 + 사람 |

**세션에서 못 여는 주소가 있다** — GitHub Pages(`*.github.io`) · 액션 아티팩트 내려받기 · 앱 스토어 화면.
페이지가 실제로 보이는지, 콘솔 칸이 무엇인지는 **사람이 보고 화면을 보낸다.**

---

## 2. 첫날 순서 — 이 차례를 바꾸면 첫 빌드가 서명에서 막힌다

```
이름 · 번들 ID 정하기 → GitHub 저장소(public) → 개발자 콘솔(컨테이너 · 그룹 → App ID → 기기)
→ App Store Connect 앱 등록 → API 키(있으면 재사용) → 저장소 시크릿 4개 → Pages 켜기 → testflight.yml 을 main 에
```

### 2.1 이름 · 번들 ID
- **번들 ID 는 등록 후 못 바꾼다** (`com.helpnara.<이름>`). 확장은 `<번들 ID>.share` 처럼 뒤에 붙인다.
- 앱 이름은 App Store Connect 에 등록해 보면 **중복이면 거부**된다 — 그것이 이름 검증이다. 남의 상표가 든 이름은 피한다.

### 2.2 GitHub 저장소
- **public** 으로 만든다 — macOS 러너가 무료다. 대신 `docs/` 가 모두 공개되므로 **실제 메일 · 시크릿 · 개인 정보를 문서에 적지 않는다.**
- **private 로 바꾸면 처리방침 페이지(Pages)가 꺼진다** (무료 요금제). 다시 public 으로 돌려도 Settings → Pages → Source 를 **GitHub Actions** 로 다시 켜야 한다.
- 브랜치: 일은 **작업 브랜치**(`claude/…`), `main` 은 **앱 스토어에 낸 판**. 심사에 낼 때 작업 브랜치를 `main` 에 병합(`-X theirs` — CI 가 스크린샷을 커밋하므로)하고 두 브랜치 파일이 같은지 본다.

### 2.3 애플 개발자 콘솔 (developer.apple.com → Identifiers)
> ⚠️ **Description 칸은 한글을 받지 않는다** — 영문 · 숫자 · 빈칸만. 안내를 쓸 때 넣을 값을 영문으로 적는다.

1. **iCloud 컨테이너가 필요하면 먼저** — `iCloud.<번들 ID>` (App ID 화면에서는 고를 수 없어서 먼저 만든다)
2. **App Group 이 필요하면** (공유 확장 등) — `group.<번들 ID>`
3. **App ID** — **Explicit** (Wildcard 는 iCloud 불가) · 필요한 Capabilities 만 켠다 · 등록 뒤 다시 열어 iCloud / App Groups **Configure** 로 1 · 2 를 잇는다
4. 확장도 App ID 를 따로 (Explicit · 같은 App Group)
5. **기기가 하나라도 등록**돼 있어야 한다 — 자동 서명이 개발용 프로파일을 굽는데, 기기 없이는 안 나온다

> 식별자는 `project.yml` 과 `*.entitlements` 에도 박힌다. **한 글자만 틀려도 빌드는 되는데 iCloud 폴더가 안 보인다.**

### 2.4 App Store Connect 앱 등록
앱 → **+** → 신규 앱: 플랫폼 iOS · 이름 · 기본 언어(한국어) · 번들 ID · SKU.

### 2.5 API 키 — **앱마다 만들지 않는다**
- 키는 **팀 단위**다. 지난 앱의 키를 **그대로** 쓴다 (값 넷이 같다).
- `.p8` 파일은 **만들 때 한 번만** 받는다 — 비밀번호 관리자 같은 곳에 보관한다. GitHub 시크릿은 쓰기 전용이라 **옛 저장소에서 꺼낼 수 없다.**
- 새로 만들 때 권한은 **Admin** (App Manager 로는 클라우드 서명이 안 된다 — `Cloud signing permission error`).

### 2.6 저장소 시크릿 4개 (Settings → Secrets and variables → Actions)
| 이름 | 어디서 |
|---|---|
| `APPLE_TEAM_ID` | developer.apple.com → Membership |
| `APP_STORE_CONNECT_KEY_ID` | App Store Connect → 사용자 및 액세스 → 통합 → App Store Connect API |
| `APP_STORE_CONNECT_ISSUER_ID` | 같은 화면 위쪽 |
| `APP_STORE_CONNECT_KEY_P8` | `.p8` 파일 **내용 전체** — 줄바꿈 그대로 (`-----BEGIN PRIVATE KEY-----` 포함) |

배포용 인증서(P12)는 쓰지 않는다 — **자동 서명 + 클라우드 서명**.

### 2.7 GitHub Pages — 처리방침 · 지원 페이지
Settings → Pages → Source **GitHub Actions**. `docs/privacy.md`(한국어) · `docs/privacy.en.md`(영어)를 `Tools/site/build.py` 가 쪽으로 만든다.
심사에 낼 **처리방침 URL · 지원 URL** 이 이 페이지다. 문의 메일은 **페이지에만** 넣고 저장소 문서에는 적지 않는다.

### 2.8 `testflight.yml` 은 **main 에 먼저**
수동 실행(`workflow_dispatch`)만 하는 워크플로는 **기본 브랜치에 있어야** GitHub 이 등록한다 (작업 브랜치에만 있으면 404). 뼈대를 만들면 바로 main 에 병합한다.

---

## 3. 저장소 뼈대

```
project.yml            ← XcodeGen. Xcode 프로젝트 파일은 커밋하지 않는다 (CI 가 만든다)
App/                   ← SwiftUI 앱 (SQLite 는 App/Search 같은 한 곳에만)
Packages/Core/         ← 순수 Swift — import SwiftUI · UIKit · SQLite3 금지 → 리눅스 swift test 가 산다
Shared/                ← 앱 · 확장이 함께 빌드하는 파일
ShareExtension/        ← (필요하면) 공유 확장
Tools/golden/          ← 파이썬 쌍둥이 · 정답표 → Packages/Core/Tests/…/Golden/expected.json
Tools/l10n/            ← 번역: request.txt · extracted.json · en.json · build.py
Tools/store/           ← count.py(글자 수) · fit.py(칸 크기) · frame.py(글귀) · event_art.py(이벤트 그림) · preview/(영상)
Tools/site/            ← 처리방침 · 지원 페이지
docs/                  ← 기억 — roadmap · 08-feedback · adr/ · NN-build-N.md · 12-submission · promo/
CLAUDE.md              ← 세션 규칙 (§5)
```

### 워크플로 여덟 개 (`.github/workflows/`)

| 파일 | 언제 | 하는 일 |
|---|---|---|
| `core-test.yml` | Core · golden 푸시 | 정답표가 최신인지 + `swift build` · `swift test` (리눅스 `swift:6.1` 컨테이너) |
| `build.yml` | 문서 · 도구 말고 모든 푸시 | XcodeGen → 빌드 → 시뮬레이터 스크린샷 → 화소 검사 → `screenshots/` 커밋 |
| `testflight.yml` | **수동** (*착수* 때만) | 아카이브 · 서명 · 검증 · 업로드. **빌드 번호 = 실행 번호** |
| `l10n.yml` | `Tools/l10n/request.txt` 한 줄 더해 푸시 | `xcodebuild -exportLocalizations` 로 번역 열쇠 뽑기 → `extracted.json` 커밋 |
| `store-shots.yml` | `Tools/store/shots-request.txt` 한 줄 더해 푸시 | 견본으로 스토어 스크린샷(언어 둘 · 아이폰 칸 둘 · 아이패드) → 글귀 → 크기 재기 → 커밋 |
| `store-preview.yml` | `Tools/store/preview-request.txt` 한 줄 더해 푸시 | XCUITest 로 화면을 찍어 앱 미리보기 영상(886 × 1920)으로 잇기 |
| `site.yml` | 처리방침 변경 | GitHub Pages |
| `probe.yml` | `Tools/probe/` 고쳐 푸시 | 세션이 못 여는 주소를 맥 러너에서 살펴보기 |

**워크플로 규칙.** `paths-ignore` 로 문서 · 도구만 고친 푸시는 앱 빌드를 건너뛴다 · `concurrency` + `cancel-in-progress` · 커밋하는 흐름은 `permissions: contents: write` · **아티팩트 업로드를 커밋보다 앞에** · 릴리스 노트 한글은 `\u` 이스케이프.

---

## 4. `project.yml` 에 **처음부터** 넣을 것 (나중에 넣느라 판을 더 냈다)

| 넣을 것 | 왜 |
|---|---|
| `CFBundleVersion: $(CURRENT_PROJECT_VERSION)` · `CFBundleShortVersionString: $(MARKETING_VERSION)` | 안 적으면 XcodeGen 이 `1` · `1.0` 을 박아 CI 빌드 번호가 앱에 안 닿는다 |
| `ITSAppUsesNonExemptEncryption: false` (해당하면) | 없으면 빌드를 올릴 때마다 수출 규정 질문에 손으로 답해야 하고, 그 전에는 테스트 준비 완료가 안 된다 |
| **`CFBundleURLTypes` — 앱 주소(`<이름>://`)** | **인앱 이벤트의 바로 가기(딥 링크)가 필수 칸이다.** 느린 여백은 이것 하나 때문에 판을 하나 더 냈다 (1.1.7). 받는 쪽은 **파일이 아닌 주소는 앱만 연다**로 거른다 |
| 권한 문구 (사진 · 카메라 등) | 없으면 실기기에서 조용히 거부된다 |
| `UISupportedInterfaceOrientations` (+ `~ipad` 네 방향) | 아이패드는 네 방향이어야 멀티태스킹에 들어간다 |
| `SWIFT_VERSION 6` · `SWIFT_STRICT_CONCURRENCY: complete` · `SWIFT_EMIT_LOC_STRINGS: YES` | 동시성 · 번역 열쇠 자동 수집 |
| `developmentLanguage` · `CFBundleLocalizations` | 처음부터 두 언어면 문자열 목록(`Localizable.xcstrings`)을 처음부터 쓴다 |
| `ASSETCATALOG_COMPILER_APPICON_NAME: AppIcon` | 없으면 검증이 `CFBundleIconName` 누락으로 막는다 |
| `testflight.yml` 의 `manageAppVersionAndBuildNumber: false` | 켜져 있으면 Xcode 가 빌드 번호를 바꿔 대화의 번호와 폰의 번호가 달라진다 |

**막다른 길 (다시 시도하지 않는다):** 배포용 `CODE_SIGN_IDENTITY` 강제 (자동 서명과 충돌) · `CODE_SIGNING_ALLOWED=NO` 로 아카이브 (entitlements 가 빠진다) · `CODE_SIGN_IDENTITY=-` (SDK 거부).

---

## 5. `CLAUDE.md` 에 그대로 옮길 규칙

- **한글로 답한다** — 진행 설명 · 질문 · 확인 목록 · 요약까지. 코드 이름 · 경로 · 명령만 `코드 글씨`.
- **문서가 기억이다.** 세션 시작 때 `docs/roadmap.md`(지금 어디까지) → `docs/08-feedback.md`(맨 위 *지금 열린 것* 표) → `docs/adr/` 를 읽는다. 세션 끝에 상태 갱신.
- **빌드는 *착수* 에만.** 이슈는 `08-feedback.md` 에 번호로 쌓고 **5개 내외로 묶어** *착수할까요?* 를 묻는다. 자료 유실 · 저장 실패만 예외.
- **빌드마다 두 목록** — (앱 안에서) 확인 0~n · (콘솔에서) 할 일. **0번은 판 확인.** 확인할 것은 **손가락이 할 동작**으로, **그 자리의 코드를 읽고** 적는다 (없는 기능을 확인해 달라고 하지 않게). 우리끼리 쓰는 말을 쓰지 않는다. 사용자는 *0~n 확인 완료* 로 답한다.
- **같은 것을 재는 곳이 둘이면 갈린다** — 값을 쓰는 자리를 만들 때 이미 그 값을 재는 자리가 있는지 먼저 찾는다.
- **같은 자리에서 CI 가 두 번 죽으면 내 코드다.** 사용자가 같은 자리에서 두 번 걸리면 반만 고친 것 — 경우의 수를 표로 깔고 심판에 물린다.
- **Swift 테스트 기댓값을 손으로 적지 않는다** — 파이썬 쌍둥이가 계산한 JSON 만. 쌍둥이는 가능하면 **다른 방법**으로 셈한다 (예: 초성 — Swift 는 음절 번호, 파이썬은 유니코드 글자 이름).
- **푸시 전 `git pull --rebase`** (CI 가 스크린샷을 커밋한다). **빌드가 도는 동안 코드를 푸시하지 않는다** — `cancel-in-progress` 가 그 빌드를 취소한다 (문서만 고친 푸시는 괜찮다).
- **다른 앱 이름을 사용자 글 · 스토어 문구에 쓰지 않는다** — 하는 일로 적는다. 코드 주석은 예외.
- **없는 기능을 팔지 않는다.** *새로운 기능* 은 실제로 바뀐 것만.
- **글자 수는 세어서** (`Tools/store/count.py`) — 손으로 세지 않는다.
- 소스 안 문구 강조는 `**…**` — **곧은 따옴표를 문구 안에 쓰지 않는다** (빌드 시스템이 같은 자리에서 두 번 죽었다).
- 파일 I/O 는 `actor` 안 · 화면에는 `Sendable` 구조체만 · 한글 파일 이름은 읽는 즉시 NFC.

---

## 6. 빌드 · 확인 · 출시 흐름 (한 바퀴)

1. 사용자 이슈 → `docs/08-feedback.md` 에 번호 · 상태(🔴🟡🔵🟢🟠)로 적는다 · 원인을 **코드로** 확인해 적는다
2. *착수* → 고침 · 파이썬 쌍둥이 · 정답표 → `generate.py --check` → 푸시 (Core 테스트 · 앱 빌드)
3. 문구가 바뀌었으면 `Tools/l10n/request.txt` 한 줄 → 번역 열쇠 뽑기 → `en.json` 채우고 `build.py` (빠진 번역 · 자리표시자 검사)
4. 판 번호(`MARKETING_VERSION`) 올리기 → `testflight.yml` 수동 실행 (`gh api -X POST …/workflows/testflight.yml/dispatches -f ref=<브랜치>`)
5. `docs/NN-build-N.md` — 고친 것 표 · 심판 결과 · **확인 목록** · 콘솔 할 일
6. 사용자 *0~n 확인 완료* → 이슈 닫기 → *심사 준비* → *새로운 기능* (한국어 · 영어 · 글자 수) · 제출 순서 · `main` 병합 → 제출 · 출시 기록 (`docs/12-submission.md`)

---

## 7. 앱 스토어 등록 — 배운 것

| 무엇 | 배운 것 |
|---|---|
| **스크린샷 칸** | 콘솔의 미리보기 · 스크린샷 칸 위에 **기기 탭이 줄지어** 있다 (아이폰 대형 · 중형 · iPhone Duo · 아이패드…). **옆으로 밀어 모든 탭을 연다.** 한 탭만 갈면 큰 아이폰에 옛 그림이 남는다 (느린 여백 250). 칸 크기는 **칸에 적힌 숫자**가 최종 — 짐작하지 않는다 |
| 크기 (2026-10 실측) | 아이폰 대형 6.5" **1242 × 2688** · 중형 6.1" **1206 × 2622** · 아이패드 13" **2064 × 2752**(세로) · 미리보기 영상 **886 × 1920** · 30fps · 소리 칸 있음 |
| 스크린샷 만들기 | 실기기로 찍으면 실제 노트 · 회사 이름 · 남의 상표가 들어온다 → **견본 폴더**(`docs/samples/`)로 시뮬레이터가 찍게. 앞 세 장이 *무엇을 하는 앱인지* 말하게 **글귀 한 줄**. 찍은 뒤 **사람 눈이 한 장씩** |
| 처리방침 · 개인정보 설문 | 설문은 처리방침과 **한 글자도 어긋나지 않게**. 데이터를 안 모으면 *수집하지 않음* |
| 첫 심사 | *2.1 정보 요청* 이 올 수 있다 — 답장 · 화면 녹화로 풀었다 (`docs/13-review-reply.md`) |
| 출시 방식 | 자동 출시 · 단계적 출시 끔 · **평점 요약 초기화 고르지 않음** |
| 판 간격 | 1~2주에 한 번 모은다. 예외: 자료 유실 · 저장 실패 · 꺼짐 · (홍보 일정) |
| 콘솔 메모 칸 | 심사자에게 남기는 메모는 영어가 안전하다 |

---

## 8. 홍보 — 배운 것 (`docs/promo/launch-kit.md`)

| 무엇 | 배운 것 |
|---|---|
| 추천 신청 | App Store Connect → **앱 → (사이드바) Featuring → Nominations** → + · 3주 전 · 영어로 · 역할 Admin · App Manager · Marketing 이상 |
| 인앱 이벤트 | **바로 가기(딥 링크) 필수** → §4 의 앱 주소를 처음부터. 그림 카드 **1920 × 1080** · 상세 **1080 × 1920** (글자 없이 — 앱 스토어가 아래쪽에 이름을 얹는다) · 공개는 시작 **14일 전**부터 · 기간 최대 31일 · 앱 판 없이 따로 심사 · **앱이 그 주소를 아는 판이 먼저 나와 있어야** 한다 |
| 캠페인 링크 | 앱 분석 → 캠페인 링크로 글마다 꼬리표(`ct`) — 공급자 번호는 저장소에 적지 않는다 |
| 홍보 주 | 다운로드 속도로 순위가 움직인다 — 흩지 말고 **한 주에 몰아서** |

---

## 9. 느린 여백에서 가져다 쓸 것

| 가져올 것 | 위치 (`helpnara/MD_Management`) | 손볼 곳 |
|---|---|---|
| 워크플로 여덟 개 | `.github/workflows/` | 번들 ID · 스킴 이름 · 시뮬레이터 화면 목록 |
| CI 상세 · 오류 표 | `docs/06-ci.md` | — (§2 · §3 · §4 가 이 문서의 원본) |
| `project.yml` | 루트 | 번들 ID · 이름 · 권한 · 컨테이너 · 그룹 · 앱 주소 |
| 세션 규칙 | `CLAUDE.md` | 앱 고유 규칙(§1 뼈대 · §4 코드 경계)만 새로 |
| 스토어 도구 | `Tools/store/` (`count.py` · `fit.py` · `frame.py` · `event_art.py` · `preview/`) | 칸 이름 · 글귀 · 원본 경로 |
| 번역 도구 | `Tools/l10n/` | 대상 이름 (`App` · 확장) |
| 처리방침 사이트 | `Tools/site/build.py` · `docs/privacy*.md` | 앱이 실제로 하는 일대로 다시 쓴다 |
| 화면 검사 | `Tools/ci/` (`not-blank.py` · `screens.txt`) | 화면 목록 |
| 아이콘 | `Tools/icon/` | 그림 |
| 문서 틀 | `docs/roadmap.md` · `08-feedback.md` · `12-submission.md` · `adr/` · `NN-build-N.md` | 내용은 비우고 형식만 |

**첫 세션에 할 말 (예):** *`docs/new-app-starter.md` 대로 새 앱 뼈대를 만들자. 앱 이름은 ○○, 번들 ID 는 com.helpnara.○○, 쓰는 기능은 (iCloud · 공유 확장 · 사진 …).*
