# 노트가 수천 개일 때 — 속도 전수 조사 (2026-10-19)

> 2026-10-19 사용자 — *노트 수가 많아지면서 노트 열기, 목록 읽기 등의 속도 측면에서 개선이 가능한 부분이 있는지 전수조사해서 검토해줘.*
> 코드를 읽어 **노트 수(N) · 파일 수(M) · 폴더 수(F)에 비례해 커지는 일**을 전부 찾았다. 실기기 측정은 300개(규모 시험)까지만 있다 —
> 아래 시간은 코드에서 센 횟수에 흔한 단가를 곱한 **어림**이다. 실측은 착수하면 진단 화면에 자리를 만들어 잰다.

기호: N = 금고 전체 노트 수 · n = 보고 있는 폴더의 노트 수 · M = 금고 전체 파일 수(첨부 포함) · F = 폴더 수 · L = 노트 길이.

## 한눈에 — 영향이 큰 순서

| # | 어디서 | 무엇이 N 에 비례하나 | 얼마나 자주 | 1,000개 어림 | 3,000개 어림 |
|---|---|---|---|---|---|
| **①** | **노트를 열 때** | *이 노트를 가리키는 노트*(212)를 세려고 **금고의 모든 노트 본문을 읽는다** (`attachmentCensus` — 휴지통 안까지). 쓰기 모드로 열어도 · 읽기로 넘길 때마다. 그동안 파일 담당(actor)이 묶여 **저장 · 목록 · 사진이 줄을 선다** | 노트를 열 때마다 · 휴지통에 보낼 때마다 · 영구 삭제마다 | 본문 20MB 읽기 — **1~3초** | 60MB — **3~10초** |
| **②** | **저장할 때 (2초마다)** | 색인 갱신이 **금고 전체 폴더를 다시 훑고**(디렉터리 목록 2(F+1)번 · 파일마다 자원값) 색인 표 전체를 두 번 읽고(N행 SELECT · `firstLines`) 전체 정렬(최근 고친 순) · 목록을 통째로 다시 넣는다. 디바운스 없음 · 취소 검사 없음 | 치다 멈출 때마다 (자동 저장) | 0.2~0.5초 CPU · I/O — 치는 동안 계속 | 0.5~1.5초 |
| **③** | **색인 만들기 (처음 · 판 바꿀 때)** | SQLite 에 **트랜잭션이 없다** — 노트마다 문장 3개 = 커밋(fsync) 3번. `note_fts` 지우기가 **색인 없는 열**(`rel_path UNINDEXED`)이라 노트마다 FTS 표 전체를 훑는다 → **O(N²)** | 처음 · 색인 다시 만들기 · 판을 올릴 때 | 300개 10초(실측 A5) → **1~2분** | **10분 넘을 수 있음** (N²) |
| **④** | **15초마다 · 목록 다시 읽을 때** | `folders()` 가 폴더마다 디렉터리 목록을 **두 번**(훑기 + 세기) · `allNotes` 도 두 번 · 금고 전체 열거(`linkableFiles`, 2000개 한도)가 `reloadNotes` 한 번에 **두 번** 붙고 15초마다 또 | 앞에 있는 동안 15초마다 · 폴더 바꿀 때 · 만들기 · 지우기 … | 0.1~0.3초 × 3 | 0.3~1초 × 3 |
| **⑤** | **화면 그리기** | 모델의 `@Published` 78개 중 무엇이 바뀌든(저장 시각 · 색인 중 · 최근 일 …) 목록 · 사이드바 · 상세 body 가 다시 돈다. body 한 번에 `pinnedNotes` · `looseNotes` 를 **4번** 거르고(O(n)), `selectedNote` O(n), `sidebarFolders` O(F²), 줄마다 `pinned.contains` O(P) | 저장 · 색인 · 알림마다 | 몇 ms — 체감 작음 | 수십 ms — 스크롤 중이면 끊김 |
| ⑥ | 검색 | 초성 검색은 제목 N줄을 **다 받아** 매번 초성을 다시 셈 · 결과 제한 없음. 2글자 검색은 설계상 본문 전체 LIKE. 결과 200개의 **본문 전체**를 받아 줄을 고른다 | 검색마다 (150ms 디바운스) | 0.1~0.3초 (S6 실측 300개 0.5초 안) | 0.3~1초 |
| ⑦ | 편집기 (글자마다) | N 이 아니라 **L** 에 비례 — 글자마다 글 전체 복사 · 비교(`onEdit(text)`), `[[` 방아쇠 찾기에 글 전체를 UTF-16 배열로 **두 번**, 서식 단추 상태도 전체, 머리말 길이 셈이 전체를 줄로 쪼갬. **칠하기 자체는 범위만** (S11 실측 20KB 문제없음) | 글자마다 | 20KB 노트: 문제없음 | 200KB 노트부터 체감 |

**잘 되어 있는 것 (손댈 필요 없음).** 보고 있는 폴더 하나의 목록 읽기(`notes(in:)`) — 디렉터리 목록 한 번 · 자원값은 미리 읽음(S1 실측 300개 1초 안). 색인 갱신은 **도장이 바뀐 노트만** 본문을 읽는다. 읽기 화면 HTML 은 N 과 무관(이 노트의 링크만 확인). 3초 지켜보기는 도장 셋뿐. 목록 미리보기는 색인에 캐시. 편집기 칠하기는 고친 문단 언저리만.

## 자리마다

### ① 노트 열기 — 역링크 세기 (`LibraryModel.refreshBacklinks` → `FolderStore.backlinks` → `attachmentCensus`)

- `loadSelectedText` (2884) 가 모드와 상관없이 `renderReading` 을 부르고, 그 끝(2934)에서 경로가 바뀌었으면 `refreshBacklinks`. 주석(841)은 *노트가 바뀌거나 읽기로 넘어갈 때만* 이라 했지만 **쓰기 모드로 열 때도** 센다.
- `attachmentCensus` (FolderStore 633) 는 금고를 재귀로 훑고 **내려와 있는 모든 노트를 `readText`** — 노트마다 `NSFileCoordinator` 하나. 휴지통(`.trash/`) 노트까지. actor 의 동기 함수라 끝날 때까지 **다른 호출(저장 `writeText` · `stamp` · 웹뷰 사진 `data(forRelativePath:)`)이 기다린다.**
- `backlinksTask?.cancel()` 은 이미 actor 에 들어간 census 를 멈추지 못한다 — 노트 k개를 빨리 넘기면 **k번 직렬로** 돈다.
- 같은 census 를 쓰는 다른 자리: 노트를 **휴지통에 보낼 때**(`trash` → `exclusiveAttachments`), 영구 삭제, 폴더 이름 바꾸기 · 옮기기 · 지우기 확인창(`incomingLinkCount`), 안 쓰는 첨부 세기. 지우기는 흔한 동작이다.

**고칠 길.** 색인이 이미 모든 본문을 읽는다(도장이 바뀐 것만) — **그때 링크 목표를 함께 적어 둔다** (`note` 표에 `links` 열, Core 의 `AttachmentLedger.linkTargets` 그대로 — 셈은 하나). 역링크는 `SELECT rel_path FROM note WHERE links LIKE '% 경로 %'` 한 줄. 못 읽은 노트는 지금처럼 못 센다(같은 한계). 휴지통 보내기의 *이 노트만 쓰는 첨부* 셈도 같은 열(참조 경로)로 — 첨부 셈 셋(172 · 173 · 174)이 한 표를 본다. 덤: 쓰기 모드로 열 때는 HTML 을 그리지 않고 `pageIsStale` 만 켠다(저장 쪽 229 와 같게).

### ② 저장마다 — 색인 갱신 (`write` 2424 → `scheduleIndexRefresh` 2023)

- 한 바퀴: `store.allNotes()` (폴더마다 디렉터리 목록 **두 번** — `notes(in:)` 한 번, 하위 폴더 찾기 한 번 · 파일마다 자원값 5개) → `noteRecentTargets` (N 전체 정렬) → `index.refresh` (`SELECT … FROM note` N행을 사전으로 · 도장 비교 · 바뀐 것만 읽기 · `COUNT(*)` 두 번 — `mtime` 에 색인 없음) → `changed > 0` 이면 `firstLines()` N행 → `withPreviews` → **`self.notes = …` 무조건** (목록 diff).
- `indexTask?.cancel()` 뿐 — `refresh` 루프 안에 취소 검사가 없고 `await reader` 에서 actor 가 다시 들어올 수 있어 **앞 바퀴와 새 바퀴가 섞인다.**
- 제목만 넣은 줄(`mtime = -1`, 245)은 도장이 늘 어긋나 — 안 받은 노트가 500개 이하면 **저장마다 그 노트들에 `startDownloading` · 자원값 조회**를 다시 한다.
- 저장 끝의 목록 갱신(2407-2415): `firstIndex` O(n) + **`notes.sort` 전체** O(n log n).
- `finishMove` 는 `reloadNotes`(안에서 한 번) 뒤 **또 한 번** 부른다 (1502-1503).

**고칠 길.** 저장 길에는 `index.refresh(only: path, summary)` — 그 노트 하나만 읽고 그 경로의 `first_line` 만 바꾼다. 전체 바퀴는 `reloadNotes` 에만. 전체 바퀴에 300~500ms 디바운스 + 루프 안 `Task.isCancelled`. `allNotes` 는 한 번 읽어 노트와 하위 폴더를 같이 거른다. 저장 뒤 목록은 **그 줄만 맨 앞으로** (목록은 최근 고친 순이라 정렬이 필요 없다). 받기를 시킨 경로는 기억해 두고 다시 시키지 않는다.

### ③ 색인 쓰기 — SQLite (`SearchIndex.refresh` 137-203)

- `BEGIN` · `COMMIT` · `PRAGMA` 가 하나도 없다 → `run()` 마다 자동 커밋(fsync). 노트마다 3번 → 처음 색인 3N 커밋.
- `note_fts(rel_path UNINDEXED, …)` 인데 `DELETE FROM note_fts WHERE rel_path = ?` → FTS 표 **전체 훑기**. 노트마다 한 번 → 처음 색인 **O(N²)**.
- 문장마다 `sqlite3_prepare_v2` 를 새로 한다.

**고칠 길.** 바퀴 전체를 `BEGIN IMMEDIATE … COMMIT` 하나로. `note_fts` 의 `rowid` 를 `note.id` 로 맞춰(`INSERT INTO note_fts(rowid, …)`) 지우기는 `WHERE rowid = ?`. 자주 쓰는 문장 셋은 한 번 준비해 재사용. 색인 판 v4 (캐시라 지우고 새로 만든다 — ADR-0003). **처음 색인이 가장 큰 이득** — 1,000개면 분 단위가 초 단위로.

### ④ 15초 훑기 · 목록 다시 읽기 (`checkForExternalChanges` 2222 · `reloadNotes` 2755 · `reloadFolders` 2551)

- `folders()` (158): DFS 로 폴더마다 목록 한 번 → 끝나고 **폴더마다 `noteCount(in:)` 로 또 한 번** → 2F+1 번 · `NSFileCoordinator` 2F+1 개.
- `reloadNotes` 한 번에 금고 전체 열거가 **세 번** — `allNotes`(색인) 1 · `linkableFiles`(`refreshVaultPaths`) 2 (2774 와 `loadSelectedText` 2793). `linkableFiles` 는 파일마다 root 경로까지 NFC · split 을 다시 하고 끝에 `localizedStandardCompare` 정렬. **2000개에서 잘린다** — 정렬 **전에** 잘려 남는 2000개가 정해져 있지 않다 → 파일이 2000개를 넘으면 붙여넣기 링크 고치기(144) · 안 열리는 링크 찾기 · 붙여넣은 첨부 이름 겹침 피하기가 일부 파일을 못 본다 (**속도가 아니라 정확성** 문제 — 따로 올린다).
- 15초마다: `reloadPins` + `reloadFolders`(위 2F+1 + 금고 열거) + `notes(in:)` + `fingerprint`(양쪽 정렬).
- `notes(in:)` 는 이름 하나를 **NFC 세 번** (`normalized` · `countsAsNote` 안 · `baseName` 안) — 상수지만 N 배.

**고칠 길.** `folders()` 의 DFS 에서 항목을 볼 때 노트 수를 함께 센다 (F+1 번). `refreshVaultPaths` 는 `loadSelectedText` 에서 빼고(붙여넣기 직전에 낡았으면 그때 읽는다) 15초 훑기에서도 뺀다 — 폴더 · 최상위 도장이 바뀌었을 때만. `linkableFiles` 는 root 조각을 한 번만 셈. `allNotes` 는 한 번 읽기. 2000 한도는 정렬 뒤가 아니라 **노트 먼저 · 첨부 나중**으로 채우거나 한도를 올린다.

### ⑤ 화면 (`RootView` · `LibraryModel` 계산 속성)

- `NoteList` · `FolderSidebar` · `NoteDetail` 이 `@EnvironmentObject` 로 **모델 전체**를 본다 — `lastSaved`(저장마다) · `isIndexing` · `indexStatus`(색인마다) · `events`(`log` 마다 — 100개 넘는 목록은 읽을 때마다 적는다) · `listSeconds` 가 바뀌어도 세 body 가 다시 돈다.
- body 한 번에 `pinnedNotes` 3번 + `looseNotes` 1번 (각각 `Set(pinned)` + `notes.filter`). `selectedNote` 는 `notes.first` O(n) — 상세 body 에서 여러 번. `sidebarFolders` 는 `FolderTree.sidebar` 가 단계마다 전체를 다시 훑어 O(F²). 줄마다 `pinned.contains` 가 배열 검색.
- 저장마다 `notes` 를 통째로 다시 넣는다(② · 2040) → List 가 n개 id 를 diff.

**고칠 길.** `pinnedNotes` · `looseNotes` · `sidebarFolders` · `pinnedSet` 을 **저장 속성**으로 — `notes` · `pinned` · `folders` 의 `didSet` 에서 한 번 계산. `selectedNote` 는 사전. `notes` 는 값이 같으면 넣지 않는다. (모델을 쪼개는 것은 큰 일 — 지금은 안 한다.)

### ⑥ 검색 (`SearchIndex.search` 260)

- 초성(246): `SELECT rel_path, title, first_line FROM note` **N줄 전부** → 줄마다 `HangulInitials.matches`(제목 NFC + 초성 다시 셈) · 결과 제한 없음.
- 2글자: `body LIKE '%..%'` — FTS 본문 전체 훑기 (설계 · A5c 실측 300개 0.5초 안). `LIMIT 200` 에 `ORDER BY` 없음 — 제목 일치가 200개 밖으로 밀릴 수 있다.
- 결과마다 `body` **전체**를 Swift 로 받아 `matchingLine`(머리말 파싱 · 줄마다 소문자).

**고칠 길 (나중).** `note` 표에 `initials` 열(색인할 때 `HangulInitials.initials(of:)` — 셈은 하나) → `LIKE` + `LIMIT`. 결과는 본문 대신 앞 4KB 만. 지금 규모(수백)에서는 괜찮다.

### ⑦ 편집기 — 글자마다 L (`MarkdownEditor` · `MarkdownStyler` · Core)

- `textViewDidChange` 끝의 `onEdit(textView.text)` — 글 전체 복사 → `noteEdited` 에서 `text != draft` 전체 비교.
- `reportLinkQuery` → `NoteLinking.query` 가 `Array(text.utf16)` **글 전체** (커서 줄만 쓰는데) — `didChange` · `didChangeSelection` 에서 글자마다 **두 번**. `reportActiveFormats` → `Formatting.active` 도 전체.
- `MarkdownStyler.restyle` 마다 `FrontMatterParser.headerLength` 가 첫 줄이 `---` 가 아니어도 **전체를 줄로 쪼갠다**. `countFences` 는 전체 검색 (`fences:` 를 안 받는 자리에서도 셈).
- 칠하기 범위는 고친 문단 + 목록 덩이 + 위아래 한 줄 — **범위만** (좋다). 긴 목록 · 빈 줄 없는 노트는 덩이가 커진다.

**고칠 길 (나중).** 커서 줄(`paragraphRange`)만 잘라 넘기기 · `headerLength` 는 첫 줄 먼저 보기 · `onEdit` 은 신호만. L 은 사람이 쓰는 노트에서 수십 KB 가 보통이라 지금은 체감이 없다 (S11).

## 재는 자리

지금 앱이 재는 것: `listSeconds`(폴더 하나 목록 — 앞에 줄 선 일을 기다린 시간이 섞인다) · `indexStatus.lastRefreshSeconds` · `searchSeconds`. **노트 열기 · 역링크 세기 · 폴더 훑기는 안 잰다.** 착수하면 진단에 **열기 시간**(읽기 → 렌더 → 역링크까지 단계별)을 두고, 규모 시험을 300개 고정이 아니라 **개수를 고르게**(300 · 1,000 · 3,000) 한다 — 고치기 전후를 같은 자로 잰다.

## 착수 묶음 (제안)

| # | 무엇 | 이득 | 크기 |
|---|---|---|---|
| **253** | 역링크 · 첨부 참조를 **색인에서** (① — `note.links` 열 · 휴지통 셈도) · 쓰기 모드로 열 때 HTML 안 그림 | 노트 열기가 N 과 무관 · 지우기도 | 중 |
| **254** | 저장은 **그 노트 하나만** 색인 (②) · 전체 바퀴 디바운스 + 취소 · 목록은 한 줄만 옮김 · `finishMove` 중복 제거 | 치는 동안 금고 훑기 없음 | 소 |
| **255** | 색인 쓰기 **트랜잭션 · rowid · 준비된 문장** (③ · 판 v4) | 처음 색인 분 → 초 | 소 |
| **256** | 폴더 훑기 한 번에 세기 · `allNotes` 한 번 읽기 · 금고 열거는 도장이 바뀔 때만 · NFC 한 번 (④) | 15초 훑기 · 목록 읽기 절반 이하 | 소 |
| **257** | 화면 계산 캐시 — `pinnedNotes` · `looseNotes` · `sidebarFolders` · `selectedNote` · 고정 Set (⑤) | 다시 그리기 가벼움 | 소 |
| + | 진단에 **열기 시간** · 규모 시험 **개수 고르기** | 전후를 같은 자로 | 소 |

따로: **258 🔵** `linkableFiles` 2000 한도가 정렬 전에 잘려 큰 금고에서 링크 고치기가 일부를 못 본다 (정확성). ⑥ 검색 · ⑦ 편집기는 규모가 거기 이르면.
