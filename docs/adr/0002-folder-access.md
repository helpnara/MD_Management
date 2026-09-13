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

## 미확인

- **A2** — iCloud Documents 컨테이너가 CloudKit 스키마 배포 없이 `Files` 에 보이는가. 1주차 실기기.
- **A3** — `WKURLSchemeHandler` 가 보안 범위 북마크 폴더의 이미지를 읽는가. 1주차 실기기.
- **A6** — 옵시디언 볼트의 `.obsidian/` 이 목록을 어지럽히지 않는가.
