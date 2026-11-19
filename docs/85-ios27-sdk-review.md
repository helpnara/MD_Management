# iOS 27 SDK 전환 검토 (321 · 2026-11-19)

> 2026-11-19 사용자 — *iOS 27 SDK 전환 검토해줘.* 이 문서는 **검토**다 — 아직 아무것도 바꾸지 않았다. 착수는 사용자가 정한다 (CLAUDE.md §3).

## 지금 어디서 빌드하나 (실측 — 빌드 152 테스트플라이트 로그)

| | 값 |
|---|---|
| 러너 | `macos-26` → 이미지 `macos-26-arm64` (20261102) |
| Xcode | **26.6 (17F113)** — iOS 26 SDK |
| Xcode 고르는 규칙 | 기본 Xcode 가 **26 이상이면 그대로** (`build.yml` · `testflight.yml` · `l10n.yml` · `store-*.yml` 의 *Xcode 26 이상 선택*). 그래서 이미지에 27 이 있어도 안 고른다 |
| 배포 대상 | iOS 17.0 (`project.yml`) · Swift 6.0 · `swift-markdown` 0.8.x |

## 바깥 사실 (2026-11-19 웹 — 애플 공식 글을 여기서 못 열어 2차 출처. 날짜는 애플 *Upcoming Requirements* 에서 다시 본다)

- **2027 년 4월부터** App Store Connect 에 올리는 iOS · iPadOS 앱은 **iOS 27 SDK (Xcode 27) 이상**으로 빌드해야 한다 — **테스트플라이트 올림도 포함**. 이미 스토어에 있는 판은 내려가지 않는다. 같은 때 배포 대상 하한이 iOS 15 로 오른다고 한다(우리는 17 — 상관없다).
- Xcode 27 은 macOS 26.6 이상이 필요하다. 깃허브는 **`xcode-27` 러너 이미지**(macOS 27 · Apple Silicon)를 2026-10-15 에 정식으로 냈다 — `macos-26` 이미지에 27 이 기본으로 들어 있다는 글은 못 찾았다.
- iOS 27 SDK 로 빌드하면 달라진다고 알려진 것: ① **장면(scene) 생애 주기 필수** — 장면 없는 UIKit 앱은 켜자마자 꺼진다 ② **시작 화면 키 필수** ③ `UIDesignRequiresCompatibility`(리퀴드 글래스 끄기) 무시 ④ SwiftUI `@State` 가 매크로가 되고 결과 빌더가 `ContentBuilder` 로 합쳐져 **새 모호함 오류**가 날 수 있음 ⑤ 몇몇 API 사용 중단(`statusBarHidden` · `supportedInterfaceOrientations` 등).

## 이 앱에 맞춰 본 것

| 걸리는 자리 | 이 앱 | 판단 |
|---|---|---|
| ① 장면 생애 주기 | SwiftUI `App` + `WindowGroup` — SwiftUI 앱 생애 주기는 처음부터 장면 기반. 앱 대리자(`@UIApplicationDelegateAdaptor`)는 `buildMenu` · 시작 때 모양(appearance)만 | **안전할 것** — 다만 `Info.plist` 에 `UIApplicationSceneManifest` 를 적지 않았다(XcodeGen 이 만든다). iOS 27 시뮬레이터에서 **켜지는지**를 화면 사진 단계가 바로 본다 |
| ② 시작 화면 | `UILaunchScreen` (`LaunchPaper` 색 · 316) | 있음 |
| ③ 호환 모드 키 | 안 씀 — 이미 리퀴드 글래스로 빌드 중 | 상관없음. 다만 **iOS 27 의 막대 · 시트 유리 모양이 달라지면** 종이 바탕(320)과의 어울림을 화면 사진으로 다시 본다 |
| ④ `@State` · 결과 빌더 | SwiftUI 화면이 크다(`RootView` 2,500 줄 남짓) | **컴파일러가 첫 심판** — 맥 빌드 단계에서만 안다 |
| ⑤ 사용 중단 API | `statusBarHidden` · `supportedInterfaceOrientations` · `CADisplayLink` · `UIAccelerometer` · `ImageCreator` 안 씀. `application(_:didFinishLaunchingWithOptions:)` 는 씀 (316 의 막대 글꼴 · 경고창 강조색) | 사용 중단이면 **경고**일 뿐 — 필요하면 그 몇 줄을 `RootView` 의 `.onAppear` 로 옮긴다 |
| 공유 확장 | UIKit `ShareViewController` | 확장은 장면 규칙 밖 — 실기기에서 한 번 본다 |
| 의존 패키지 | `swift-markdown` 0.8.x (`swift-cmark` C 코드) | Xcode 27 에서 컴파일되는지 맥 빌드가 본다 |
| 자동 빌드 검사 | 시뮬레이터 고르기는 **이름을 안 박는다** (가장 새 iOS 의 기종) — 그대로 돈다. 스토어 사진만 `iPhone 17 Pro` 를 이름으로 찾는다(6.1" 칸 1206 × 2622) | 27 이미지에 그 기종이 있는지 첫 실행에서 본다 |
| 리눅스 Core 시험 | Xcode 와 무관 | 상관없음 |

## 권하는 순서

1. **탐색 빌드 (출시 아님)** — `xcode-27` 러너에서 앱 빌드 + 화면 사진만 도는 흐름을 따로 하나 둔다(지금 흐름은 그대로). 컴파일 오류 · 경고 목록과 iOS 27 시뮬레이터 화면 사진을 받는다. 테스트플라이트에는 안 올린다 — 사용자 빌드 규칙(§3)을 건드리지 않는다.
2. **고칠 것이 나오면** 번호로 적고 고친다. 걸리는 것이 없으면 흐름 다섯(`build` · `testflight` · `l10n` · `store-shots` · `store-preview`)의 `runs-on` 을 `xcode-27` 로, *26 이상* 검사를 *27 이상* 으로.
3. **전환 첫 빌드는 기능을 섞지 않는다** — 문제가 나면 SDK 탓인지 기능 탓인지 갈려야 한다. 확인 목록은 켜기 · 쓰기(한글 조합) · 찾기 막대 · 아이패드 메뉴 막대 · 공유 확장 · 문서 첨부 창 · 사진 넣기 · 어두운 모드 — 그리고 *껐다 켜서 그대로인가* 를 번호로 다시 올린다(큰 변경 뒤 첫 빌드 · §3·3).
4. **때** — 기한은 2027 년 4월이라 급하지 않다. 다만 지금 사용자 기기는 이미 iOS 27 이고, 26 SDK 앱은 iOS 27 에서 **옛 동작**으로 돈다. 다음 기능 묶음 **앞에** 전환 빌드를 하나 끼우면 1 ~ 2 월에 몰리지 않는다.

## 출처 (2026-11-19 검색 — 2차 출처 포함)

- [Xcode 27 runner image generally available — GitHub Changelog (2026-10-15)](https://github.blog/changelog/2026-10-15-xcode-27-runner-image-generally-available/)
- [actions/runner-images — Xcode 27 public preview #14404](https://github.com/actions/runner-images/issues/14404) · [macos-26 Readme](https://github.com/actions/runner-images/blob/main/images/macos/macos-26-Readme.md)
- [April 2027 App Store requirements: Xcode 27 and iOS 27 SDK — VibeView](https://vibeview.io/checklists/app-store-april-2027-requirements/) · [iOS 27 SDK Requirement from April 2027 — pull.house](https://pull.house/blog/april-2027-ios-27-sdk-requirement/) · [Xcode 27 Is Out — Blake Crosley](https://blakecrosley.com/blog/xcode-27-release)
- [iOS 27.0 Release Notes: Deprecations, Breaks, and Fixes — Blake Crosley](https://blakecrosley.com/blog/ios-27-release-notes) · [What's New in UIKit in iOS 27 — Kyle Howells](https://ikyle.me/blog/2026/whats-new-in-uikit-ios-27) · [What's new in SwiftUI — iOS 27 SDK](https://miniswift.run/whats-new/swiftui/)
