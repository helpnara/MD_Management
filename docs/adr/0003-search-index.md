# ADR-0003 — 검색은 SQLite FTS5 trigram, 2글자는 LIKE 폴백

**상태** 확정 (2026-09-13, 사용자 결정)

## 맥락

한글은 부분 문자열 검색이 필요하다. `노후자` 로 `노후자금` 을 찾아야 하는데, 공백
단위로 토큰을 나누는 보통의 전문 검색기는 이것을 못 한다. FTS5 의 `trigram`
토크나이저가 정확히 이 문제를 푼다.

**그런데 trigram 에는 문서에 적힌 한계가 있다: 3글자 미만의 질의에는 아무것도
반환하지 않는다.** 한국어에서 `회의` · `세금` · `일기` · `기획` 같은 2글자 검색어는
드문 것이 아니라 가장 흔하다. v0.4 설계서의 안정화 기준 S6 이 `노후자`(3글자)였던
탓에 이 구멍이 보이지 않았다.

## 결정

**FTS5 trigram 을 쓰되, 2글자 이하 질의는 FTS 를 건너뛰고 `LIKE` 로 폴백한다.**

```sql
CREATE TABLE note(
  id       INTEGER PRIMARY KEY,
  rel_path TEXT UNIQUE NOT NULL,   -- 폴더 기준 상대경로 (NFC 정규화)
  title    TEXT NOT NULL,
  mtime    INTEGER NOT NULL,       -- 초 단위, 재색인 판단
  size     INTEGER NOT NULL,
  tags     TEXT NOT NULL DEFAULT ''
);

-- external content 를 쓰지 않는다. 색인은 캐시이므로 본문 사본을 FTS 안에 둔다.
CREATE VIRTUAL TABLE note_fts USING fts5(
  rel_path UNINDEXED, title, body, tags,
  tokenize='trigram'
);
```

- **`content=` external content 를 쓰지 않는다.** v0.4 초안은 `content='note_body'` 에
  `note_body(id, body)` 를 뒀는데, FTS 가 `SELECT title, body, tags FROM note_body`
  를 실행하므로 `title` · `tags` 칼럼이 없어 재구축 · `snippet()` 시점에 실패한다.
  게다가 external content 는 트리거로 손수 동기화해야 한다. 색인이 캐시인 이상 얻을
  것이 없다.
- **질의 길이에 따른 두 경로** (`Core/Index/SearchQuery.swift` 가 순수 함수로 가른다):
  - 모든 낱말이 3글자 이상 → `note_fts MATCH ?`
  - 하나라도 2글자 이하 → 그 낱말은 `note.rel_path` 를 훑는 `body LIKE '%…%'` 폴백
  - 두 결과를 AND 로 교차한다.
- 색인 버전 번호를 파일에 적어 두고, 다르면 **통째로 지우고 다시** 만든다.
  마이그레이션을 쓰지 않는다.
- 설정에 **"색인 다시 만들기"** 버튼 — "검색이 이상해요" 를 한 바퀴에 끝낸다.
- 색인은 `Application Support` 에 둔다. **iCloud 로 보내지 않는다.**

## 버린 대안

| 대안 | 버린 이유 |
|---|---|
| trigram 만 쓰고 2글자는 포기 | `회의` 검색이 빈 결과를 낸다. 사용자는 앱이 고장 났다고 느낀다 |
| 자소 단위 2-gram 색인을 직접 만든다 | 2글자는 물론 초성 검색까지 된다. 대신 색인기가 복잡해지고 Core/App 경계 설계가 늘어 1.0 3주 일정에 부담이다. **2.0 후보** |
| Spotlight(`CSSearchableIndex`) 만 | 앱 안에서 즉시 검색이 안 된다 |
| GRDB · SQLite.swift | 외부 의존 하나가 심사 · 빌드 · 리눅스 테스트를 다 끌고 온다. 시스템 `libsqlite3` 를 C API 로 직접 부른다 |

## 미확인

- **A4** — FTS5 trigram 이 iOS 내장 SQLite 에 있는가 (SQLite 3.34+ = iOS 15+).
- **A5** — 300개 · 20MB 첫 색인이 10초 안인가.
- **A5b** — 색인 파일 크기. trigram 인덱스 + 본문 사본은 원문의 3~5배다. 20MB → 100MB 안팎.
- **A5c** — 2글자 LIKE 폴백이 0.5초 안인가. **이것이 이 결정의 유일한 약점이다.**
  파일이 수천 개로 늘면 먼저 느려지는 자리다.

## 덧붙임 (2026-09-15) — 만들었다 (빌드 23)

`App/Search/SearchIndex.swift` 하나에 SQLite 호출을 다 모았다. 스키마는 위 그대로에 `note.first_line`
(목록 미리보기)만 더했다. 여는 순간 trigram 을 **probe** 해서(A4) 없으면 `unicode61` 로 만들고 모든 낱말을
LIKE 로 보낸다. 스니펫은 `snippet()` 대신 본문에서 **낱말이 든 첫 줄**을 스위프트로 고른다 — 한글이 안 잘린다.
색인은 `Application Support/Index/<폴더>-v1.sqlite`, 폴더를 바꾸면 다른 파일이다.

