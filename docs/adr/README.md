# ADR — 되돌리기 비싼 결정

저장 계층 · 검색 방식 · 렌더링 · 편집 방식처럼 **나중에 바꾸려면 코드를 다시 쓰는
결정**만 여기 남긴다. 나머지는 `docs/08-feedback.md` 같은 작업 기록으로 충분하다.

세션이 바뀌어도 "왜 이렇게 했더라" 를 다시 묻지 않게 하는 것이 목적이다.

| # | 결정 | 상태 |
|---|---|---|
| [0001](0001-file-is-source-of-truth.md) | 파일이 원본 — 앱 DB 없음 | 확정 |
| [0002](0002-folder-access.md) | 폴더 접근 두 길 — (a) 앱 iCloud 컨테이너 기본, (b) 임의 폴더 | 확정 |
| [0003](0003-search-index.md) | SQLite FTS5 trigram + 2글자 LIKE 폴백 | 확정 |
| [0004](0004-rendering.md) | swift-markdown 파싱 → HTML → WKWebView | 확정 |
| [0005](0005-live-editor.md) | 라이브 편집 — 커서 줄만 원문 | 확정 |
| [0006](0006-universal-app.md) | 유니버설 앱 하나 (아이폰 · 아이패드) | 확정 |
| [0007](0007-no-uidocument.md) | `UIDocument` 를 쓰지 않고 `NSFileCoordinator` 를 직접 쓴다 | 확정 |
