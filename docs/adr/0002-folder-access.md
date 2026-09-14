# ADR-0002 — 폴더 접근은 두 길, 기본은 앱 iCloud 컨테이너

**상태** 확정 (2026-09-13, 사용자 결정)

## 맥락

파일이 원본(ADR-0001)이므로 "어느 폴더인가" 가 첫 질문이다. 두 부류의 사용자가 있다:

1. 아무것도 없는 사람 — 앱이 폴더를 만들어 줘야 한다.
2. 이미 옵시디언 볼트나 iCloud Drive 폴더가 있는 사람 — 그것을 열어야 한다.

## 결정

**두 길을 다 만들되, (a) 를 기본으로 하고 (b) 는 설정에서 들어간다.**

### (a) 앱 iCloud Drive 컨테이너 — 기본

- 엔타이틀먼트: iCloud Documents (`CloudDocuments`)
- `Info.plist` 의 `NSUbiquitousContainers` → `NSUbiquitousContainerIsDocumentScopePublic = YES`
- `Files` 앱의 iCloud Drive 에 앱 이름 폴더가 보인다.
- **CloudKit 스키마도 Production 배포도 없다** — 레코드 타입을 쓰지 않으므로 지난 앱의
  함정(`LESSONS_LEARNED` §3)이 통째로 사라진다.
- 첫 실행이 버튼 한 번이다. 이것이 (a) 를 기본으로 하는 이유다.

### (b) 사용자가 고른 임의 폴더 — 설정 → 폴더 바꾸기

- `fileImporter(allowedContentTypes: [.folder])`
- `url.bookmarkData(options: .minimalBookmark)` 를 저장, 실행마다
  `startAccessingSecurityScopedResource()`
- 북마크가 `isStale` 이면 다시 고르게 한다.

### 두 길에 공통

- 모든 읽기 · 쓰기는 `NSFileCoordinator` 로 (ADR-0007).
- 쓰기는 **임시 파일 → `replaceItemAt`** (원자적). 원본을 열어 놓고 덮어쓰지 않는다.
- 변경 감시: iCloud 는 `NSMetadataQuery`(`NSMetadataQueryUbiquitousDocumentsScope`),
  로컬 북마크 폴더는 `DispatchSource.makeFileSystemObjectSource`.
  **감시가 놓쳐도 앱 활성화 시 전체 `mtime` 대조가 그물이다.**
- 미다운로드 파일(`.icloud`)은 목록에 구름 아이콘 → 탭하면 `startDownloadingUbiquitousItem`.
- **파일명은 읽는 즉시 NFC 로 정규화**한다 (`Core/Paths.normalized`). iCloud · Files ·
  옵시디언 사이에서 한글 파일명이 NFD 로 오간다 (A13).

## 버린 대안

| 대안 | 버린 이유 |
|---|---|
| (a) 와 (b) 를 첫 화면에 나란히 | 첫 화면에서 사용자가 결정을 내려야 한다. 대부분은 (a) 로 충분하고, 옵시디언 사용자는 설정을 찾아갈 줄 안다 |
| (b) 만 | 첫 실행이 무겁고, 북마크 `isStale` 문제를 초반부터 안고 간다 |
| (a) 만 | 기존 폴더(옵시디언 볼트)를 못 연다 — 목표 사용자의 절반을 버린다 |

## (a) 를 `Files` 앱에 보이게 하는 데 필요했던 것 — 값을 치렀다

2026-09-13, 실기기에서 폴더가 안 보였다. **원인이 둘이었다.**

1. **컨테이너를 메인 스레드에서 찾았다.** `FileManager.url(forUbiquityContainerIdentifier:)`
   는 애플 문서가 메인에서 부르지 말라고 명시한 API다 — 처음 잡을 때 시간이 걸려
   `nil` 이 온다. 그러면 앱은 조용히 기기 안 폴더로 물러나고, **앱은 멀쩡히 도는데
   `Files` 에만 아무것도 안 생긴다.**
2. **빈 컨테이너는 `Files` 에 안 나타난다.** 엔타이틀먼트 · `NSUbiquitousContainers` ·
   앱별 토글이 전부 정상이어도, `Documents` 가 비어 있으면 목록에도 검색에도 안 나온다.
   **파일이 하나 생기자 폴더가 나타났다.**

   > 사용자가 `Files` 에서 **빈 폴더를 만들면 보이는** 것으로 이 가설을 반증했다고
   > 여겼는데, 그것은 다른 것이었다. iCloud Drive 최상위의 일반 폴더와, 앱 컨테이너가
   > 공개하는 폴더는 `Files` 에서 다른 길로 나타난다.

**그래서 갓 만든 폴더가 비어 있으면 첫 노트를 하나 둔다** (`FolderSource.seedIfNeeded`).
딱 한 번만, 이미 파일이 있는 폴더에는 넣지 않는다. 만든 것은 그냥 `.md` 라 사용자가
고치거나 지우면 그만이므로 ADR-0001 을 어기지 않는다.

**세운 심판:** 앱 안 진단 화면(폴더 종류 · iCloud 를 잡았나 · 경로 · 파일 수)과
CI 의 번들 검사(`NSUbiquitousContainers` 가 정말 박혔는지). 둘 다 이 사건에서 나왔다.

## 미확인
- **A3** — `WKURLSchemeHandler` 가 보안 범위 북마크 폴더의 이미지를 읽는가. 1주차 실기기.
- **A6** — 옵시디언 볼트의 `.obsidian/` 이 목록을 어지럽히지 않는가.

## 덧붙임 (2026-09-15) — (b) 의 화면을 만들었다 (빌드 23)

설정 → 폴더 → **다른 폴더 고르기** (`fileImporter`) · **기본 iCloud 폴더로 돌아가기**.
북마크는 보안 범위를 연 채 만들고, 기억한 뒤 **다시 풀어** 그 URL 을 쓴다 — 첫 사용과 다음 실행이
같은 길을 가게. 낡은 북마크는 조용히 버리지 않고 띠와 최근 일에 적는다.

**쓰기 방식은 위 "두 길에 공통" 에서 하나 고쳤다:** 조정 옵션은 파일을 만들 때만 `.forReplacing`,
있는 파일에는 `.forMerging` (설계서 §7.2, 2026-09-15 두 기기 실측). 감시는 `NSMetadataQuery` 대신
**3초마다 도장(시각 · 크기) 보기**로 갔다 — 두 길에 같은 코드가 통하고, 실기기에서 배터리로 드러나지 않았다.

