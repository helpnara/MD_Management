# ADR-0004 — 렌더링은 swift-markdown 파싱 → HTML → WKWebView

**상태** 확정 (2026-09-13)

## 결정

- **파싱**: `swift-markdown`(Apple, Foundation 만 씀) 으로 마크다운을 AST 로 읽는다.
- **HTML 생성**: `Packages/Core/Markdown` 에서. 순수 함수이므로 리눅스 `swift test` 와
  파이썬 대조(`markdown-it-py`)로 검증한다.
- **표시**: `WKWebView`.
- **이미지**: `WKURLSchemeHandler` 가 `yb://note/<상대경로>` 요청을 폴더 기준으로 풀어
  `Data` 를 준다. 보안 범위 폴더 안이므로 `loadFileURL` 의 접근 범위 제약을 피한다.
- **글꼴**: 뷰어 CSS 는 `font: -apple-system-body` 만 쓰고 `px` 를 적지 않는다 →
  Dynamic Type 이 저절로 따라온다. 색은 `--yb-*` CSS 변수로 앱의 색 토큰을 받는다.

## 버린 대안

**순수 SwiftUI 렌더러.** 표 · 코드 블록 · 핀치 줌 · 텍스트 선택 · 링크를 전부 다시
만들어야 한다. 지난 앱에서 핀치 줌 하나로 세 바퀴를 돌았다
(`LESSONS_LEARNED` §4 "핀치 줌은 UIKit 으로"). `WKWebView` 는 줌 · 링크 · 선택 ·
찾기가 공짜다.

## 결과

- 뷰어의 HTML 기댓값은 **파이썬으로 대조한 것만** 테스트에 적는다.
- 링크 처리 규칙: 상대 `.md` → 앱 안 이동 · 이미지 → 전체화면 · 외부 URL → Safari ·
  그 외 첨부 → `QLPreviewController`.
- **읽기 모드 전용이다.** 쓰기는 라이브 편집기(ADR-0005) 하나뿐이다.
