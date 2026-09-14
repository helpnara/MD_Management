# 마크다운 기록 앱 — 상세 설계서 v0.5

> "내 아이폰에 있는 MD 파일을 열어 보고, 고치고, 찾는다. 이미지와 첨부도 그 자리에서."

| | |
|---|---|
| 작성일 | 2026-09-13 |
| 상태 | v0.5 — v0.4 초안의 사실관계 5건 · 내부 모순 11건을 고치고 ADR 7건으로 확정 |
| 대상 기기 | iPhone · iPad — **하나의 유니버설 앱, 두 벌의 화면 구성** ([ADR-0006](adr/0006-universal-app.md)) |
| 최소 버전 | iOS 17.0 |
| 개발 방식 | Claude Code 가 코드 · 문서를 쓰고, GitHub Actions 가 컴파일 · 스크린샷 · TestFlight 업로드, 사용자가 실기기 확인 |
| 환경 | 맥 없음 · Claude Code 원격(리눅스) + GitHub Actions macOS 러너 + TestFlight |
| 참고 | `Asset-management` 저장소의 `docs/12-lessons-learned.md` — 본문에서 `[L§n]` 으로 인용 |

**v0.4 에서 무엇이 바뀌었는지는 §15 에 있습니다.**

---

## 0. 이름 · 식별자 · 제목 `[L§1]`

| 항목 | 값 | 비고 |
|---|---|---|
| 앱 이름(스토어) | **느린 여백** | 2026-09-13 확정. 단독 `여백` 은 상표 충돌이라 쓰지 않는다 ([roadmap §4](roadmap.md)) |
| 번들 ID | `com.helpnara.markdown` | **이름과 무관하게 고정.** 등록 후 못 바꾸므로 일부러 이름을 안 넣었다. 접두사는 기존 팀 규칙(`com.helpnara`)을 따른다 |
| Xcode 타깃 · 스킴 | `Notebook` | 사용자에게 안 보인다. 이름이 바뀌어도 안 바꾼다 |
| 화면 상단 제목 | **사용자 폴더 이름** (예: `내 기록`) | 앱 이름과 분리. 폴더 이름이 곧 제목 `[L§1]` |
| iCloud 컨테이너 | `iCloud.com.helpnara.markdown` | `Files` 앱에 보이는 폴더 이름은 `NSUbiquitousContainerName` (이름 바뀌면 여기도) |
| 지원 메일 | ☐ 미정 | 스토어 제출 전 확정 (08-feedback 4번) |
| 개인정보 처리방침 URL | `helpnara.github.io/MD_Management/privacy/` | `site.yml` 이 `docs/privacy.md` 한 장만 낸다 `[L§7]` |

---

## 1. 1.0 의 뜻과 끝나는 조건

→ [`docs/roadmap.md`](roadmap.md) §1 · §2 · §3. **안정화 기준 13줄과 가정 표 18줄이 그 문서에 있고, 그것이 이 프로젝트의 기억이다.**

---

## 2. 사용자 시나리오 (이 여섯 가지가 되면 1.0)

1. **열기** — 첫 실행 → "시작하기"(앱 iCloud 폴더) → 파일 목록. 기존 폴더는 설정에서.
2. **보기** — 파일 탭 → 라이브 편집기가 렌더된 모습으로 열린다 → 핀치로 확대하려면 상단 "읽기" 토글.
3. **고치기** — 커서를 줄에 두면 그 줄만 마크다운 원문 → 키보드 위 띠(`#` `**` `-` `[ ]` 링크 · 사진) → 저절로 저장.
4. **사진 넣기** — 띠의 사진 → 사진첩/카메라 → `assets/` 에 복사 → 커서 자리에 `![](assets/2026-09-13-1.jpg)`.
5. **찾기** — 검색 탭 → 단어 입력 → 본문 일치 줄과 파일 이름이 즉시 → 탭하면 그 줄로.
6. **보내기** — 공유 → 첨부가 없으면 `.md` 하나, 있으면 `회의.zip` 하나 → 카톡 · 메일 · AirDrop.

---

## 3. 되돌리기 비싼 결정 — ADR

| ADR | 결정 |
|---|---|
| [0001](adr/0001-file-is-source-of-truth.md) | **파일이 원본.** 사용자 폴더의 `.md` · 이미지가 유일한 진실. 앱 DB 는 없다 |
| [0002](adr/0002-folder-access.md) | 폴더 접근 두 길 — **(a) 앱 iCloud 컨테이너 기본**, (b) 임의 폴더는 설정에서 |
| [0003](adr/0003-search-index.md) | **SQLite FTS5 trigram + 2글자 LIKE 폴백.** external content 안 씀 |
| [0004](adr/0004-rendering.md) | swift-markdown 파싱 → HTML(`Core`) → `WKWebView`. 이미지는 `yb://` 스킴 핸들러 |
| [0005](adr/0005-live-editor.md) | **라이브 편집** — 커서가 있는 문단만 원문, 나머지는 속성으로 렌더 |
| [0006](adr/0006-universal-app.md) | **유니버설 앱 하나.** 아이패드는 같은 코드베이스의 3단 구성 |
| [0007](adr/0007-no-uidocument.md) | `UIDocument` 를 쓰지 않고 `NSFileCoordinator` 를 직접 쓴다 |

### 부속 결정 (ADR 아님)

- 파일 인코딩 UTF-8. 원본에 `\r\n` 이면 **그대로 보존**하고 새 줄만 원본 규칙을 따른다.
- 첨부 폴더 이름 `assets/` (노트 옆). 옵시디언 기본값과 같아 상호 운용된다.
- 이미지 링크는 표준 `![alt](상대경로)`. `[[wikilink]]` 는 2.0 — 있어도 **깨뜨리지 않고 그대로 표시**한다.
- **문자열 인덱스를 저장하지 않는다.** 파일 크기 · 오프셋은 `Int`(바이트) 하나로만 다룬다.
- **한글 파일명 · 링크는 NFC 로 정규화**한다 (`Core/Paths.normalized`). → §7.3, A13.
- 마크다운 링크의 **퍼센트 인코딩을 푼다** (`assets/내%20사진.jpg` 와 `assets/내 사진.jpg` 를 같게 본다).

---

## 4. 아키텍처 `[L§1]`

```
MD_Management/
├─ Packages/Core/            ← Foundation + swift-markdown 만. 리눅스 CI 에서 swift test
│   ├─ Sources/Core/
│   │   ├─ Paths/            ← NFC 정규화 · 상대경로 해석 · 파일명 안전화
│   │   ├─ FrontMatter/      ← YAML 머리말(title · tags · created) 읽기
│   │   ├─ Markdown/         ← swift-markdown 파싱, 링크 추출, HTML 생성
│   │   ├─ Index/            ← 검색 질의 → FTS5 구문 + LIKE 폴백 (SQLite 호출은 App)
│   │   └─ Share/            ← ShareBundle.plan (무엇을 zip 에 넣나)
│   └─ Tests/CoreTests/      ← 기댓값은 Tools/golden 이 파이썬으로 계산한 JSON
├─ App/                      ← SwiftUI + UIKit 래퍼
│   ├─ DesignSystem/         ← Font.scaled · scaledLength · 색 토큰 (첫 화면 전에)
│   ├─ Storage/              ← FolderStore(actor) · 샘플 폴더 · 감시
│   ├─ Search/               ← SQLite FTS5 색인기
│   ├─ Views/                ← §6
│   └─ Diagnostics/          ← 진단 정보 복사 · 색인 재생성 · 문의 메일
├─ Tools/golden/             ← 파이썬 대조 기댓값 생성기 (원격 세션의 유일한 즉시 심판)
├─ Tools/site/               ← 방침 한 장
├─ project.yml               ← XcodeGen. 맥 없이 .xcodeproj 를 만드는 유일한 길
├─ docs/
└─ CLAUDE.md
```

**경계 규칙.** `Core` 는 `import SwiftUI` · `import UIKit` · `import SQLite3` 를 하지
않는다. 검증 사다리의 맨 위 두 칸(파이썬 대조 · `swift test`)이 이 경계에 달려 있다 `[L§2]`.

---

## 5. 자료 모델

### 5.1 파일 규약 (사용자 폴더 — 원본)

```
<사용자 폴더>/
├─ 2026-09-13 회의.md
├─ 아이디어/
│   ├─ 앱 구상.md
│   └─ assets/            ← 그 폴더의 노트가 쓰는 첨부
│       └─ 2026-09-13-1.jpg
└─ .trash/                ← 삭제한 것. 영구 삭제는 설정에서 타이핑 확인
```

- 노트 = `.md` · `.markdown` · `.txt`. **`.txt` 도 편집한다** — 마크다운 렌더만 끄고
  고정폭 원문으로 보여 준다 (편집기가 원문을 그대로 다루므로 추가 비용이 없다).
- 첨부 = 이미지(`jpg png heic gif webp`) · 그 외(`pdf` 등 → QuickLook).
- 숨김 폴더(`.` 로 시작)는 목록에서 제외한다 — 옵시디언 볼트의 `.obsidian/` 때문 (A6).
- 머리말(선택):
  ```yaml
  ---
  title: 앱 구상
  tags: [앱, 기획]
  created: 2026-09-13
  ---
  ```
  머리말이 없으면 제목 = 첫 `# 제목` 또는 파일명.
  **앱은 머리말을 만들어 넣지 않는다** — 사용자가 쓴 파일 그대로.

### 5.2 색인 (앱 사설 — 캐시)

→ [ADR-0003](adr/0003-search-index.md) 에 스키마와 2글자 폴백 규칙이 있다.

### 5.3 기기 편의 (UserDefaults — 자료 아님) `[L§4]`

마지막 연 파일 · 스크롤 위치 · 편집 커서 · 정렬 방식. **iCloud 로 보내지 않는다.**

---

## 6. 화면 설계

| 화면 | 내용 | 규칙 |
|---|---|---|
| **A. 시작** | 폴더 없음 → "시작하기"(앱 iCloud 폴더) 큰 버튼 + 작게 "둘러보기". 둘러보기는 **임시 디렉터리**의 샘플 3개 + 상단 배너 | `[L§5 체험 자료]` — 실제 폴더에 샘플을 뿌리지 않는다 |
| **B. 목록(브라우저)** | 폴더 트리 · 파일 목록(제목 · 첫 줄 · 수정일) · 정렬 · 새 노트 · 새 폴더 | 이름 바꾸기 · 이동 · 삭제는 롱프레스. **모든 삭제 확인** `[L§5]`. **첫 줄 미리보기는 색인에서만** 가져온다 (§7.5) |
| **C. 라이브 편집기 (기본)** | 단일 `UITextView`. 커서 문단만 원문, 나머지는 렌더. 상단 토글 `읽기 ↔ 쓰기`. 키보드 위 띠: `#` `**` `-` `1.` `[ ]` `> ` 링크 · 사진 · 들여쓰기 | 띠는 `.safeAreaInset(edge: .bottom)`, **키보드 툴바 금지** `[L§4]`. 자동 저장 2초 디바운스 + `.background` 즉시. **파일을 열면 쓰기 모드가 기본** |
| **D. 읽기 (뷰어)** | `WKWebView`. 표 · 코드 · 핀치 줌. 시스템 글꼴 `font: -apple-system-body` → Dynamic Type 자동 | **완전한 읽기 전용.** 링크: 상대 `.md` → 앱 안 이동, 이미지 → 전체화면, 외부 URL → Safari, 그 외 첨부 → QuickLook |
| **E. 검색** | 입력 즉시(150ms 디바운스) 결과: 파일명 일치 → 본문 일치(강조 스니펫, 줄 번호). 태그 필터 칩 | 탭 → 그 줄로 스크롤 |
| **F. 공유 시트** | 편집기 · 목록 롱프레스에서. `.md` 하나 또는 `.zip` 하나 (§7.6) | **아이패드 팝오버 앵커 필수** — 없으면 죽는다 |
| **G. 설정 · 진단** | 폴더 바꾸기((b) 임의 폴더가 여기) · 색인 재생성 · 고아 첨부 정리 · 영구 삭제 · 진단 정보 복사 · 문의 메일 · 방침 링크 | `[L§8 복사해 붙일 수 있는 것]` |

**값의 출입구 하나** `[L§4]`: **본문을 고치는 길은 라이브 편집기 하나뿐이다.**
예외는 없다 — 체크박스 토글도 편집기 안에서 한다 ([ADR-0005](adr/0005-live-editor.md) §값의 출입구).

---

## 7. 기능 상세

### 7.1 폴더 접근

→ [ADR-0002](adr/0002-folder-access.md)

### 7.2 편집과 저장 (S2 · S4 · S15)

- 편집 시작 시 `mtime` **과 크기**를 기억한다. 저장 직전 둘 중 하나가 바뀌었으면(다른
  기기가 고침) → **덮어쓰지 않고** `이름 (충돌 2026-09-13 14:02).md` 로 나란히 저장하고
  알린다. iCloud 충돌 판본(`NSFileVersion.unresolvedConflictVersionsOfItem`)도 같은
  화면에서 고르게 한다.
  > `mtime` 만 보면 iCloud 동기화가 시각을 건드릴 때 헛돌 수 있다. 크기를 함께 보고,
  > 그래도 헛돌면 해시로 올린다. → A15
- 자동 저장은 **2초 디바운스** + `.background` 진입 시 즉시. 내용이 안 바뀌었으면 쓰지 않는다.
  (1초는 iCloud 업로드를 매 타자마다 일으킨다.)
- 쓰기는 임시 파일 → `replaceItemAt` (원자적). 절대 원본을 열어 놓고 덮어쓰지 않는다.
  **임시 파일은 원본과 같은 볼륨의 `itemReplacementDirectory` 에.** 조정 옵션은 **파일을 만들 때만
  `.forReplacing`, 있는 파일에는 `.forMerging`** — `.forReplacing` 은 iCloud 에 "새 파일" 이라고
  말하는 것이라 두 기기가 갈라지면 판본 대신 `이름 2` 가 생긴다 (2026-09-15 빌드 20~22, 두 기기 실측).
  디스크가 바뀌었나 검사는 조정 **안**에서 쓰기와 한 덩어리로 (`writeText(expecting:)`).
- 되돌리기: `UITextView.undoManager`. 속성 변경은 undo 에 넣지 않는다.
- 백업 `[L§5]`: 파일이 원본이라 별도 백업이 없다. 대신 **삭제는 폴더 안 `.trash/` 로
  이동**, 영구 삭제는 설정에서 타이핑 확인. → A14

### 7.3 이미지 · 첨부 (S5 · S13)

- 넣기: `PhotosPicker` / 카메라 / 파일 → HEIC 는 JPEG 로 변환(품질 0.85, 긴 변 2048px
  기본, 설정에서 원본 유지) → `assets/YYYY-MM-DD-n.jpg` → 커서에 `![](assets/…)`.
- 보기: `WKURLSchemeHandler` 가 `yb://note/<상대경로>` 요청을 폴더 기준으로 풀어 `Data`
  를 준다. 없으면 회색 상자 + 경로 표시 (S5).
- **경로를 풀 때 세 가지를 한다** (`Core/Paths.resolve`):
  1. **퍼센트 인코딩을 푼다** — `assets/내%20사진.jpg` → `assets/내 사진.jpg`
  2. **NFC 로 정규화한다** — iCloud · Files · 옵시디언이 한글 파일명을 NFD 로 넘긴다.
     이것이 없으면 **한글 이름 첨부가 전부 깨진 링크로 뜬다.** → A13 · S13
  3. **`../` 로 폴더 밖을 가리키면 거부**한다.
- 첨부 미리보기 `QLPreviewController`. 상대 `.md` 링크는 앱 안 이동.
- 고아 첨부(어느 노트도 안 쓰는 `assets/` 파일) 목록 → 설정에서 확인 후 삭제.
  **자동 삭제 없음** `[L§5]`.

### 7.4 라이브 편집

→ [ADR-0005](adr/0005-live-editor.md) 에 세 단계(L1 · L2 · L3) · 버그가 나는 자리 ·
물러설 길이 있다.

**검증 사다리에서의 자리:**

- `LineStyler`(Core): `(문단 문자열, 커서 여부) → [(범위, 토큰)]` 순수 함수.
  리눅스 CI `swift test`, 기댓값은 `Tools/golden` 의 파이썬 `markdown-it-py` 대조.
  마커 위치 · 강조 범위 · 이미지 링크 추출이 여기서 다 잡힌다.
- CI 스크린샷에 **"커서를 3번째 줄에 둔 편집기"** 한 장 — 3번째 줄만 원문인지 눈으로 본다.
- **실기기만 잡는 것**: 한글 조합 · 스크롤 튐 · 타자 지연.
  빌드 체크리스트 고정 항목: **"가나다라 빠르게 치고 `⌘Z`"** · **"세 줄 위아래로 커서 옮기기"**.

### 7.5 검색 (S6)

- 파일 저장 · 감시 이벤트 · 앱 활성화 시 **`mtime` 이 다른 파일만** 재색인. 첫 색인은
  백그라운드, 진행률 표시.
- **목록의 "첫 줄" 미리보기는 색인에서 가져온다.** 목록을 그리려고 파일 300개를 여는
  것은 S1(3초)을 못 맞추고, iCloud 미다운로드 파일은 아예 못 읽는다. 색인 전이면 빈칸.
- 질의 변환(`Core/Index`): 공백 = AND, `"…"` = 구절, `tag:앱`, `path:아이디어/`.
  순수 함수라 CI 리눅스에서 테스트한다.
- **2글자 이하 낱말은 LIKE 폴백**으로 간다 ([ADR-0003](adr/0003-search-index.md)).
- 결과 스니펫은 `snippet()` 으로, 한글 잘림 없이 **줄 단위**로 자른다.

### 7.6 공유 — "첨부가 없으면 .md 하나, 있으면 zip 하나"

**정책 한 줄.** 받는 사람이 **파일 하나**만 받게 한다.

1. 공유 → `Core/Markdown` 의 링크 추출기가 본문의 상대경로 링크를 뽑는다.
   외부 URL · 절대경로는 제외.
2. 참조 파일 **0개** → `.md` 그대로 `ShareLink` 에 넘긴다. 가장 흔하고 가장 가벼워야 한다.
3. **1개 이상** → 임시 폴더(`tmp/share-<uuid>/<노트제목>/`)에 노트와 참조 파일을
   **원래 상대경로 그대로** 복사 → zip → 공유 → 시트가 닫히면 임시 폴더 삭제.
4. **참조했는데 없는 파일**이 있으면 공유 전에 알린다: "사진 2개를 찾을 수 없어 빼고
   보냅니다 · 목록 보기 · 그래도 보내기 / 취소". **조용히 빠뜨리지 않는다.**
5. 상대 `.md` 링크는 **한 단계만** 따라간다 (A 가 B 를 링크하면 B 는 넣되, B 가 링크하는
   C 는 넣지 않는다). 설정에서 끌 수 있다.

**구현 결정**

- **zip 은 OS 가 만든다.** `NSFileCoordinator.coordinate(readingItemAt: 폴더, options: .forUploading)`
  가 디렉터리를 zip 으로 묶어 준다. 외부 라이브러리 없음 `[L§1 외부 의존]`.
  **주의 두 가지:** (1) 그 URL 은 **블록 안에서만 유효**하므로 블록 안에서 최종
  위치로 복사해야 한다. (2) zip 안에는 넘긴 폴더 이름이 최상위로 들어간다 — 그래서
  임시 폴더 이름을 노트 제목으로 만든다.
- **묶는 대상 계산은 Core.** `ShareBundle.plan(...) → (mode, includes, missing)` 순수 함수.
  리눅스 `swift test` 로 mdOnly · zip · missing · 외부 URL 제외 · `../` 차단을 검사한다.
- **`../` 는 넣지 않는다.** zip 안에 상위 경로가 들어가면 받는 쪽에서 풀 때 다른 폴더를 덮는다.
- **파일명** `<노트 제목>.zip`. `Core/Paths.safeFileName` 으로 치환.
- **크기** 합계 50MB 초과 시 "이미지를 긴 변 2048px 로 줄여 보내기" 를 기본 선택으로 제안.
- **아이패드는 공유 시트 앵커 필수.**

**받는 쪽 (1.0 은 "보내기" 만)** — 받은 zip 은 `Files` 앱이 푼다. 풀린 폴더를 (b) 방식으로
열면 그대로 읽힌다. 공유 확장 · PDF 내보내기는 2.0.

---

## 8. 비기능 — 첫 화면 만들기 전에 `[L§4]`

- **Dynamic Type 첫날.** `Font.scaled(_:weight:)` · `Font.scaledLength(_:)` 하나.
  뷰어 CSS 는 `font: -apple-system-body` 만 쓰고 `px` 를 적지 않는다.
  배지 · 라벨은 `lineLimit(1) + fixedSize`.
- **색 토큰 하나** (`Palette.paper · ink · accent`). 뷰어 CSS 도 같은 토큰을 `--yb-*`
  변수로 받아 다크 모드가 같이 간다.
- **접근성 최대 글씨 스크린샷**을 CI 에 첫 주부터.
- **Swift 6 동시성.** 파일 I/O 는 `actor FolderStore`. 화면에는 `Sendable` 구조체만
  건넨다. `@preconcurrency` 금지.
- **핀치 줌은 WKWebView 가 한다.** SwiftUI 로 만들지 않는다 `[L§4]`.
- **아이패드** → [ADR-0006](adr/0006-universal-app.md).

---

## 9. 개발 환경 · CI — 검증 사다리 `[L§2]`

> **원격 세션에는 Swift 툴체인이 없고 `download.swift.org` 는 막혀 있다.**
> 2026-09-13 실측 확인. 자세한 것은 `CLAUDE.md` §2.

| 심판 | 잡는 것 | 어디서 | 비용 |
|---|---|---|---|
| 파이썬 대조 (`markdown-it-py` · `PyYAML`) | 링크 추출 · 머리말 · HTML 기댓값 | **원격 세션에서 직접** | 초 |
| `Core swift test` | 파싱 · 질의 변환 · 경로 규칙 · 공유 계획 | CI 리눅스 러너 | 2~4분 |
| 앱 빌드 | 문법 | CI macOS 러너 | 10분 |
| 시뮬레이터 스크린샷 (빈 화면 재시도 · 크기 가드 · 큰 글씨 · iPad) | 화면 | CI macOS 러너 | 15분 |
| 왕복 검사 (파일 쓰기 → 앱 실행 → 색인 결과 비교) | 파일↔색인 일치 | CI macOS 러너 | 15분 |
| 실기기 TestFlight | iCloud · 문서 피커 · 사진 권한 · **한글 조합** | 사람 | 30분 + 사람 |

### 9.1 워크플로 파일

| 파일 | 트리거 | 하는 일 |
|---|---|---|
| `core-test.yml` | `Packages/Core/**` · `Tools/golden/**` 푸시 | ① ubuntu: 파이썬 골든 검증 ② `swift:6.1-noble` 컨테이너: `swift test` |
| `build.yml` | `App/**` · `Packages/**` · `project.yml` 푸시 | macOS: XcodeGen → 빌드 → 시뮬레이터 스크린샷(iPhone · iPad · 다크 · 큰 글씨) → **아티팩트 먼저** → `screenshots/` 커밋 |
| `testflight.yml` | 수동 — **"착수하자"** | 빌드 번호 = 실행 번호 · 서명 · 업로드 · 릴리스 노트(`\u` 이스케이프) |
| `site.yml` | `docs/privacy.md` 변경 | GitHub Pages 에 방침 **한 장만** |

**시크릿 4개** (지난 앱과 같은 이름 — A9):
`APPLE_TEAM_ID` · `APP_STORE_CONNECT_ISSUER_ID` · `APP_STORE_CONNECT_KEY_ID` ·
`APP_STORE_CONNECT_KEY_P8`. **배포 인증서 P12 는 쓰지 않는다** — API 키로 서명한다.

워크플로 규칙(`paths-ignore` · `cancel-in-progress` · `contents: write` ·
**아티팩트를 커밋보다 앞에** · 곧은 따옴표 금지)은 `CLAUDE.md` §5.

### 9.2 Claude Code 세션 규약

→ `CLAUDE.md`

---

## 10. 일정

→ [`docs/roadmap.md`](roadmap.md) §5

---

## 11. 가정 표

→ [`docs/roadmap.md`](roadmap.md) §3

---

## 12. 스토어 `[L§7]`

- **목표(잴 수 있는 것):** 한국 App Store 검색 "마크다운" · "md 뷰어" 에서 상위 노출,
  평점 4.7 이상, 리뷰 100건. 출시 목표일: 안정화 표가 찬 날 + 1주.
  > 검색 순위는 애플의 알고리즘이라 우리가 통제하지 못한다. **통제할 수 있는 것**(부제 ·
  > 키워드 · 스크린샷 4장 · 첫 문장 · 후기 요청 시점)을 먼저 다 하고, 순위는 결과로 본다.
- **키워드** `마크다운, markdown, md, 메모, 노트, 기록, 일기, 옵시디언, 뷰어, 편집기`
- **감성 한 줄(설명 첫 문장):** "파일은 당신의 것. 이 앱은 그저 보기 좋게, 찾기 쉽게 곁에 있습니다."
- **스크린샷**: iPhone · iPad 13"(2064×2752), **체험 자료로**. 캡션 4장: 보기 · 고치기 · 사진 · 찾기.
  > iPhone 칸이 요구하는 크기는 제출 시점에 App Store Connect 에서 확인한다 — 지난 앱은
  > 6.5"(1284×2778) 를 요구받았는데 워크플로는 6.9"(1320×2868) 로 찍고 있었다.
- **후기 요청**: 검색 성공 뒤 화면을 나올 때 · 90일 1회 · 체험 중 제외.
- **개인정보**: 수집 없음("데이터 수집 안 함"). 사진 · 카메라 권한 문구는 첫날 `Info.plist`.

---

## 13. 첫날 · 첫 주 체크리스트 `[L§9]`

**첫날 (코드 전에)** — ✅ 2026-09-13 완료

- [x] 공유 없음 확인 → 파일 원본 · Core Data 없음 (ADR-0001)
- [x] §0 한 표 · 번들 ID 확정 (이름은 A1 대기)
- [x] 안정화 표 · 가정 표를 `docs/roadmap.md` 에
- [x] ADR 7건 `docs/adr/`
- [x] `Packages/Core` 생성 · `swift-markdown` 의존 (리눅스 빌드는 A7)
- [x] `CLAUDE.md`: 원격 세션 제약 · 빌드 규율 · 기억해 둘 것
- [x] 앱 이름 확정 — `느린 여백` (2026-09-13)

**첫 주**

- [x] CI 빌드 · Core 테스트(리눅스) · 스크린샷(빈 화면 재시도 · 크기 가드 · 큰 글씨 · iPad)
- [x] `paths-ignore` · `cancel-in-progress` · `contents: write` · **아티팩트 먼저**
- [x] TestFlight 워크플로 (빌드 번호 = 실행 번호)
- [x] `Font.scaled` · `scaledLength` · 색 토큰 — 화면 전에
- [x] `Info.plist` 권한 문구 · iCloud Documents 엔타이틀먼트 (A2)
- [x] 체험 = 임시 디렉터리 + 배너
- [x] 공유: `ShareBundle.plan` Core 테스트 먼저, 화면은 3주차
- [x] 방침 한 장 GitHub Pages
- [ ] 시크릿 4개 등록 — 사용자 (08-feedback 2번)
- [ ] Pages 소스를 Actions 로 — 사용자 (08-feedback 3번)
- [ ] 모든 삭제 확인 · `.trash/` · 영구 삭제 타이핑 — 2주차
- [ ] 진단 정보 복사 · 색인 재생성 · 문의 메일 — 3주차
- [ ] 키보드 위 띠 `safeAreaInset` — 2주차

**매 빌드** → `CLAUDE.md` §3

---

## 14. 열린 질문 — 전부 닫혔다

| # | 질문 | 답 (2026-09-13) |
|---|---|---|
| 1 | 기본 폴더를 (a) 로 할지 (b) 를 나란히 둘지 | **(a) 가 기본, (b) 는 설정에서** — ADR-0002 |
| 2 | `.txt` 를 보기만 할지 편집도 할지 | **편집도 한다.** 마크다운 렌더만 끈다 |
| 3 | 1.0 에 `[[wikilink]]` 이동을 넣을지 | **넣지 않는다.** 표시는 깨뜨리지 않는다. 2.0 1순위 |
| 4 | 체크박스 뷰어 토글 | **없앤다.** 라이브 편집기 L3 가 흡수 — 출입구 예외가 사라졌다 |
| 5 | 아이폰 · 아이패드를 앱 하나로? | **앱 하나** — ADR-0006 |
| 6 | 파일을 열면 쓰기가 기본? | **그렇다.** "읽기" 는 토글 |
| 7 | zip 에 참조 첨부만? | **그렇다.** 폴더 전체 옵션은 넣지 않는다 |
| 8 | 최소 iOS 버전 | **17.0** |
| 9 | 일정 | **3주는 목표, 판정은 안정화 표** |

---

## 15. v0.4 → v0.5 검토 기록

착수 전 검토에서 나온 것. **각 줄이 왜 바뀌었는지가 이 프로젝트의 근거다.**

### 사실관계 오류 (5건)

| # | v0.4 | 실제 | 근거 |
|---|---|---|---|
| 1 | "`Core swift test` 를 원격 세션에서 직접 (수 초)" | **불가능.** 리눅스 컨테이너에 Swift 가 없고 `download.swift.org` 가 네트워크 정책으로 막혀 있다 | 2026-09-13 실측(`CONNECT tunnel failed, 403`) · `LESSONS_LEARNED` §2 에 이미 같은 문장이 있었다 |
| 2 | `note_fts ... content='note_body'` 에 `note_body(id, body)` | FTS 가 `SELECT title, body, tags FROM note_body` 를 실행한다 — 두 칼럼이 없어 실패한다. external content 를 버렸다 | SQLite FTS5 external content 규약 |
| 3 | trigram 으로 한글 부분 문자열 검색 | **trigram 은 3글자 미만 질의에 아무것도 반환하지 않는다.** `회의` · `세금` 이 빈 결과를 낸다 → LIKE 폴백 추가, S6 에 2글자 사례 추가 | FTS5 trigram 문서 |
| 4 | 번들 ID `kr.slowrich.yeobaek` | 기존 팀 규칙은 `com.helpnara` (`Asset-management/project.yml`) | 지난 앱 저장소 |
| 5 | 시크릿 `APPSTORE_KEY_ID` · `APPSTORE_ISSUER_ID` · `APPSTORE_P8` · **`DIST_CERT_P12`** | 실제는 `APPLE_TEAM_ID` · `APP_STORE_CONNECT_ISSUER_ID` · `APP_STORE_CONNECT_KEY_ID` · `APP_STORE_CONNECT_KEY_P8`. **P12 배포 인증서는 안 쓴다** | `Asset-management/.github/workflows/testflight.yml` |

### 내부 모순 · 빠진 것 (11건)

| # | 내용 | 처리 |
|---|---|---|
| 6 | §6-C "뷰어 체크박스 = 유일한 예외" vs §14-4 "L3 가 흡수, 예외 사라짐" | §14-4 채택. 뷰어는 **완전한 읽기 전용** |
| 7 | S1(300개 3초) + 목록의 "첫 줄" = 파일 300개를 열어야 함. 미다운로드 파일은 못 읽음 | **첫 줄은 색인에서만.** 색인 전이면 빈칸 (§7.5) |
| 8 | **한글 파일명 NFC/NFD 정규화가 없었다** | `Core/Paths.normalized`. 없으면 한글 이름 첨부가 전부 깨진 링크 → S13 · A13 |
| 9 | 마크다운 링크의 퍼센트 인코딩 처리가 없었다 | `Core/Paths.resolve` 가 푼다 |
| 10 | `UIDocument` 를 왜 안 쓰는지 근거가 없었다 | **ADR-0007** 신설 |
| 11 | `mtime` 만으로 충돌 감지 — iCloud 가 시각을 건드릴 수 있다 | 크기를 함께 본다 → A15 |
| 12 | `.Trash/` 가 iCloud · 보안 범위 폴더에서 되는지 미확인 | 앱이 직접 `.trash/` 로 옮긴다 → A14 |
| 13 | L2 의 0.01pt 마커를 **VoiceOver 가 읽는다** | A10 에 접근성 추가. 안 되면 VoiceOver 중에는 L1 |
| 14 | 3주 일정에 **TestFlight 베타 심사(1~2일)** 와 CI 왕복(15분)이 없었다 | roadmap §5 에 명시. 1주차에 첫 빌드를 미리 올린다 |
| 15 | **XcodeGen 이 설계서에 없었다** — 맥 없이 `.xcodeproj` 를 만드는 유일한 길 | §4 에 `project.yml` 추가 |
| 16 | 색인 크기 가정이 없었다 (trigram 은 원문의 3~5배) | A5b 추가 |

### 그대로 둔 것

- 자동 저장 디바운스만 1초 → **2초** 로 늘렸다 (iCloud 업로드를 매 타자마다 일으키지 않게).
- 스크린샷 크기는 제출 시점에 확인하도록 §12 에 단서만 달았다.
