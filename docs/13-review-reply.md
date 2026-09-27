---
title: 심사 답변 — Guideline 2.1 Information Needed
updated: 2026-09-27
---

# 심사 답변 — 2.1 *Information Needed* (2026-09-27)

## 무엇이 왔나

**반려가 아니라 정보 요청이다.** 앱에 결함을 찾은 것이 아니라 *심사 이력이 적은 개발자 계정*
이라 앱을 더 알아야겠다는 뜻이다 (애플 원문: *submitted by a developer account that has a
limited App Review history*). **새 빌드는 필요 없다** — 빌드 56 그대로, 답장과 화면 녹화 하나.

| 애플이 묻는 것 | 우리 답 | 근거 (코드로 확인 · 2026-09-27) |
|---|---|---|
| 1 실기기 화면 녹화 (앱 켜는 데서 시작) | 아래 **녹화 순서**대로 찍어 붙인다 | — |
| └ 계정 가입 · 로그인 · 계정 삭제 | **없다** | 계정 기능이 없다 |
| └ 사용자 생성 콘텐츠 (신고 · 차단) | **해당 없음** — 남과 나누는 글이 없다 | 공유 · 게시 기능 없음 |
| └ 유료 콘텐츠 | **없다** | 인앱 결제 없음 |
| 2 목적 · 대상 · 푸는 문제 · 가치 | 답장 §2 | 스토어 설명과 같은 말 |
| 3 쓰는 법 · 로그인 정보 · 견본 파일 | 로그인 없음. 첫 실행에 견본 노트 하나 | `FolderSource.seedIfNeeded` → `첫 노트.md` |
| 4 외부 서비스 | **애플 iCloud Drive 뿐.** 서버 · 분석 · 광고 · AI · 결제 없음 | `App/` 에 `URLSession` · `URLRequest` **0건**. 외부 코드는 `swift-markdown`(애플 오픈소스, 기기 안에서 파싱) 하나 |
| 5 지역 차이 | 없다. 화면은 한국어 | `CFBundleDevelopmentRegion: ko` |
| 6 규제 산업 · 제3자 보호 자료 | 해당 없음 | — |

애플은 이 내용을 **App Review Information 의 Notes 칸에도 넣으라**고 했다 — 다음 제출 때
또 묻지 않게. 아래 답장 본문을 **답장과 Notes 칸 두 곳에** 붙인다.

> **Notes 칸은 한국어 화면에서 `앱 심사 정보` → `메모` 다** (2026-09-27 — 사용자가 못 찾았다.
> 영어 이름으로만 적은 탓이다). 절차서 **8번에서 한국어 심사 메모를 넣은 바로 그 칸**이다.
> 휴대폰 브라우저의 App Store Connect 는 줄어든 화면이라 버전 페이지 칸이 안 보일 수 있다 —
> 아이패드 · 컴퓨터 · `데스크톱 웹사이트 요청` 으로 연다. 심사 중에 잠겨 있으면 **답장만
> 먼저** 보내고 메모 칸은 칸이 열릴 때 넣는다 — 애플도 *다음 제출 때 참고* 라고 했다.
>
> **배운 것.** 사람에게 화면의 칸을 가리킬 때는 **그 사람 화면에 보이는 말**로 적는다.
> `Notes` 는 우리가 영어 원문을 읽고 붙인 이름이지 사용자 화면의 이름이 아니었다.

---

## 답장 본문 (App Store Connect → `앱 심사에 회신` 에 붙인다 · Notes 칸에도)

```
Hello App Review team,

Thank you for reviewing our app. Please find the requested information below. A screen recording captured on a physical iPhone running the latest iOS is attached.

1. Screen recording
The recording starts by launching the app from the Home Screen and shows the typical flow: browsing folders, opening and editing a note with the formatting bar, linking notes, adding a photo, reading mode, search, creating a note, and finally the same files visible in the Files app.
The app has no account registration, login or account deletion, no user-generated content shared with other users, and no paid content or in-app purchases.

2. Purpose and target audience
Slow Margin (느린 여백) is a Markdown note-taking app for iPhone and iPad. Notes are saved as plain Markdown (.md) files in the user's own iCloud Drive folder, or in a folder the user chooses, instead of an app-only database.
Target audience: people who write notes, plans and journals and want to keep them as ordinary files they own, including people who already keep a folder of Markdown files.
Problem it solves: in most note apps, notes stay locked inside the app. Here, deleting the app or switching to another app loses nothing. The same files open in the Files app, on a Mac, or in any Markdown editor.
Value: comfortable writing on iPhone and iPad (only the line with the cursor shows raw Markdown, the rest is shown formatted), links between notes, photos stored next to the note, and full-text search.

3. How to access the main features
No login or account is needed, so no credentials are required.
On first launch the app creates its folder in iCloud Drive and adds one sample note. If iCloud Drive is turned off on the device, the app uses a folder on the device and the list starts empty. Tap the pencil button at the top right to create a note.
- Editing: tap a note. The bar at the bottom of the editor has bold, italic, strikethrough, code, link, quote, table and indent.
- Linking notes: type [[ followed by part of a note title, then pick a note from the list that appears.
- Photos: the photo button at the top of the editor offers the photo library or the camera. The image is saved in an assets folder next to the note.
- Reading mode: the book button at the top of the editor.
- Search: the search field at the top of the note list searches titles and text.
- Folders: create one with the folder button. Long-press a folder to rename or delete it. Deleted notes move to a trash folder and can be restored from Settings.
- Settings (gear button): choose a different folder with the system document picker.
No sample files are needed; the included sample note or any .md file is enough.

4. External services
- Apple iCloud Drive, through the system's iCloud document storage, to keep the user's files in sync between their own devices. It is managed by Apple and the developer has no access to it.
- There are no developer-operated servers, no analytics, no advertising, no AI services, and no authentication or payment services. The app makes no network requests of its own.
- The only third-party code is swift-markdown, Apple's open-source Markdown library, used on the device to parse text.

5. Regional differences
The app works the same in every region. The interface is in Korean. There are no region-specific features or content.

6. Regulated industry and third-party material
Not applicable. The app does not operate in a regulated industry and does not include protected third-party material. The notes are the user's own files.

We have also added this information to the Notes field of the App Review Information section.

Thank you.
```

> **글자 수는 `python3 Tools/store/count.py` 가 센다** (심사 메모 칸도 센다 — 아래).
> 곧은 따옴표 없이 적었다. 앱 이름의 영문 `Slow Margin` 은 **설명용**이다 — 스토어 이름은
> `느린 여백` 그대로다.

---

## 화면 녹화 순서 (아이폰 · 2~3분)

**녹화 전에**
- 설정 → 일반 → 소프트웨어 업데이트 — **최신 iOS** 인지 본다 (애플 요구)
- **견본 폴더**로 바꿔 둔다 — 개인 노트가 안 나오게 (스크린샷 때 쓴 `docs/samples/`)
- 방해 금지를 켠다 — 알림이 녹화에 안 들어오게
- 제어 센터에 `화면 기록` 이 없으면: 설정 → 제어 센터 에서 더한다

**녹화 — 반드시 홈 화면에서 시작한다** (*The recording must begin with launching the app*)

| # | 손가락으로 | 보여 주는 것 |
|---|---|---|
| 1 | 제어 센터 → 화면 기록 → **홈 화면**에서 `느린 여백` 아이콘을 누른다 | 앱을 켜는 데서 시작 |
| 2 | 폴더 화면을 잠깐 보여 준다. 폴더 하나를 **길게 눌러** 메뉴가 뜨는 것까지만 보고 닫는다 | 폴더 · 전체 노트 수 · 이름 바꾸기 |
| 3 | `주간 계획` 을 연다. 본문 한 줄을 탭한다 | 커서 줄만 원문, 나머지는 읽는 모습 |
| 4 | 낱말 하나를 골라 **B** → 다시 골라 **`</>`** | 도구 띠 |
| 5 | 맨 아래 줄에서 `[[제주` 를 치고 목록에서 `제주 여행` 을 고른다 | 노트 잇기 |
| 6 | 위의 **사진** 단추 → 사진첩에서 한 장 | 사진이 노트에 들어간다 |
| 7 | 위의 **책** 단추 → 읽기 모드. `제주 여행` 링크를 눌러 넘어간다 (표 · 사진) | 읽기 모드 · 링크 |
| 8 | 목록으로 돌아와 검색칸에 `제주` | 본문 검색 |
| 9 | 연필 단추로 **새 노트** → 제목 한 줄 | 만들기 |
| 10 | 홈으로 나가 **`파일` 앱** → iCloud Drive → `느린 여백` 폴더 → `.md` 파일들을 보여 준다 | **글이 파일로 남는다** — 이 앱의 핵심 |
| 11 | 녹화를 멈춘다 | — |

**올리는 곳.** App Store Connect → 느린 여백 → `앱 심사에 회신` — 답장 본문을 붙이고 녹화 파일을
첨부한다. 첨부 크기 한도는 여기서 확인할 수 없다(애플 문서를 못 연다) — 안 올라가면 알려 달라,
길이를 줄이는 쪽을 먼저 본다.

**녹화는 공개되지 않는다** — 심사팀만 본다. 그래도 견본 폴더로 찍는 편이 안전하다.

---

## 이 일에서 배운 것

- **이것은 결함이 아니라 첫 계정에 오는 절차다.** 앱 문제로 읽고 빌드를 고치러 가면 시간만 든다.
- 애플이 준 질문 여섯은 **다음 제출에도 쓸 수 있는 틀**이다. 그래서 Notes 칸에 영구히 남긴다.
