# 행간 (가칭) — 아이폰 · 아이패드 마크다운 기록 앱

> 내 아이폰에 있는 `.md` 파일을 열어 보고, 고치고, 찾는다. 이미지와 첨부도 그 자리에서.

**파일이 원본입니다.** 앱은 사용자 폴더의 `.md` 와 이미지를 그대로 읽고 씁니다.
자체 데이터베이스도, 자체 파일 형식도 없습니다. 앱을 지워도 자료는 그대로입니다.

| | |
|---|---|
| 상태 | 1주차 뼈대 |
| 대상 | iPhone · iPad 유니버설 앱 (iOS 17+) |
| 개발 | Claude Code 원격(리눅스) + GitHub Actions macOS 러너 + TestFlight |

## 문서

| 문서 | 내용 |
|---|---|
| [docs/00-design.md](docs/00-design.md) | 상세 설계서 (v0.5) |
| [docs/roadmap.md](docs/roadmap.md) | 안정화 판단 기준 · 가정 표 — **세션 시작 시 첫 번째로 읽습니다** |
| [docs/08-feedback.md](docs/08-feedback.md) | 열린 이슈 |
| [docs/06-ci.md](docs/06-ci.md) | CI · TestFlight 절차 |
| [docs/adr/](docs/adr/) | 되돌리기 비싼 결정 7건 |
| [CLAUDE.md](CLAUDE.md) | 세션 규약 |

## 구조

```
Packages/Core/   Foundation 만 쓰는 순수 로직 — 리눅스 CI 에서 swift test
App/             SwiftUI + UIKit
Tools/golden/    파이썬 대조 기댓값 생성기
Tools/site/      개인정보 처리방침 한 장
```
