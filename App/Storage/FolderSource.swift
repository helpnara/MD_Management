import Foundation
import Core

/// 어느 폴더를 쓸지 고른다 (ADR-0002).
///
/// 순서: (b) 사용자가 고른 폴더 → (a) 앱 iCloud 컨테이너 → 이 기기의 Documents.
enum FolderSource {

    private static let bookmarkKey = "folder.bookmark"
    private static let seededKey = "folder.seeded"

    // MARK: - (a) 앱 iCloud Drive 컨테이너

    /// 앱 iCloud Drive 컨테이너의 `Documents`.
    ///
    /// **메인 스레드에서 부르면 안 된다.** 애플 문서가 명시한다 — 컨테이너를 처음
    /// 잡을 때 iCloud 설정이 필요해 시간이 걸린다. 메인에서 부르면 `nil` 이 오고,
    /// 그러면 조용히 기기 안 폴더로 물러나 **`Files` 앱에 아무것도 안 생긴다**
    /// (2026-09-13 실기기, 가정 A2 반증).
    ///
    /// `Documents` 를 **만들어 둬야** `Files` 앱이 그 폴더를 보여 준다.
    static func iCloudDocuments() async -> URL? {
        await Task.detached(priority: .userInitiated) { () -> URL? in
            guard let container = FileManager.default.url(forUbiquityContainerIdentifier: nil) else {
                return nil
            }
            let documents = container.appendingPathComponent("Documents", isDirectory: true)
            try? FileManager.default.createDirectory(at: documents, withIntermediateDirectories: true)
            seedIfNeeded(documents)
            return documents
        }.value
    }

    /// 설치 직후 첫 실행에서는 컨테이너가 아직 준비되지 않아 `nil` 이 오는 일이 있다.
    /// 몇 번 더 물어본다 — 그래도 없으면 기기 안 폴더로 간다.
    static func iCloudDocuments(attempts: Int, gap: Duration = .milliseconds(700)) async -> URL? {
        for attempt in 1...max(1, attempts) {
            if let url = await iCloudDocuments() { return url }
            if attempt < attempts { try? await Task.sleep(for: gap) }
        }
        return nil
    }

    /// 갓 만든 iCloud 폴더가 비어 있으면 첫 노트를 하나 둔다.
    ///
    /// **왜 하나.** `Files` 앱이 **빈 폴더를 안 보여 준다** (2026-09-13 실기기 —
    /// 앱은 컨테이너를 제대로 잡았는데 `Files` 에는 아무것도 없었다). 파일이
    /// 하나 있으면 폴더가 나타난다. 덤으로 처음 연 사람에게 볼 것이 생긴다.
    ///
    /// **딱 한 번만 한다.** 사용자가 지우면 다시 만들지 않는다 — 이미 쓰던
    /// 폴더(파일이 있는 폴더)에는 아무것도 안 넣는다. 만든 파일은 그냥 `.md` 라
    /// 사용자가 고치거나 지우면 그만이다 (ADR-0001 을 어기지 않는다).
    static func seedIfNeeded(_ documents: URL, defaults: UserDefaults = .standard) {
        guard !defaults.bool(forKey: seededKey) else { return }
        defaults.set(true, forKey: seededKey)

        let names = (try? FileManager.default.contentsOfDirectory(atPath: documents.path)) ?? []
        guard names.allSatisfy({ $0.hasPrefix(".") }) else { return }  // 이미 쓰던 폴더

        let note = documents.appendingPathComponent("첫 노트.md")
        guard !FileManager.default.fileExists(atPath: note.path) else { return }
        try? firstNote.write(to: note, atomically: true, encoding: .utf8)
    }

    /// `Files` 앱에 보이는 폴더 이름. `project.yml` 의 `NSUbiquitousContainerName`
    /// 을 읽으므로 **이름이 사는 곳이 늘지 않는다** (docs/roadmap.md §4).
    static var iCloudFolderName: String? {
        guard let containers = Bundle.main.object(forInfoDictionaryKey: "NSUbiquitousContainers")
                as? [String: Any] else { return nil }
        for value in containers.values {
            if let dictionary = value as? [String: Any],
               let name = dictionary["NSUbiquitousContainerName"] as? String,
               !name.isEmpty {
                return name
            }
        }
        return nil
    }

    // 곧은 따옴표를 문구 안에 쓰지 않는다 (CLAUDE.md §5).
    private static let firstNote = """
    # 첫 노트

    이 폴더가 **느린 여백**이 쓰는 곳입니다. `파일` 앱의 iCloud Drive 에서도
    같은 폴더가 보입니다 — 거기에 `.md` 파일을 넣으면 여기 목록에 뜹니다.

    ## 해 볼 것

    - [ ] 이 줄을 고쳐 보기
    - [ ] 위 오른쪽 책 아이콘을 눌러 **읽기** 모드로 보기
    - [ ] `파일` 앱에서 이 폴더에 `.md` 를 하나 더 넣어 보기

    ## 사진 넣기

    이 폴더 안에 `assets` 폴더를 만들고 사진을 넣은 뒤, 본문에 이렇게 씁니다:

    ```
    ![](assets/사진.jpg)
    ```

    이름에 **공백이 있으면 꺾쇠로 감쌉니다** — `![](<assets/내 사진.jpg>)`.

    > 파일은 당신의 것입니다. 앱을 지워도 이 폴더는 그대로 남습니다.
    """

    // MARK: - 그 밖의 폴더

    /// 기기 안 폴더. `Files` 앱의 **이 iPhone 안에** 보인다 (`UIFileSharingEnabled`).
    static func localDocuments() -> URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    /// 저장해 둔 (b) 임의 폴더 북마크의 상태.
    enum Bookmark: Sendable {
        /// 고른 폴더가 없다 — (a) 로 간다.
        case none
        /// 있었는데 **낡았다** (폴더가 옮겨졌거나 지워졌거나 권한이 끊겼다). 지웠다 — 다시 고르게 한다.
        case stale
        case folder(URL)
    }

    /// 저장해 둔 (b) 임의 폴더 북마크를 푼다. 낡았으면 지우고 `.stale` — **조용히 넘어가지 않는다.**
    static func bookmarkedFolder(defaults: UserDefaults = .standard) -> Bookmark {
        guard let data = defaults.data(forKey: bookmarkKey) else { return .none }
        var isStale = false
        guard let url = try? URL(resolvingBookmarkData: data,
                                 options: [],
                                 relativeTo: nil,
                                 bookmarkDataIsStale: &isStale),
              !isStale else {
            defaults.removeObject(forKey: bookmarkKey)
            return .stale
        }
        // **휴지통에 들어갔거나 사라진 폴더는 낡은 것으로 본다.** `파일` 앱의 삭제는 폴더를
        // `최근 삭제된 항목`(.Trash)으로 옮기는 것이라 북마크가 그대로 따라간다 — 그 안을
        // 조용히 쓰면 안 된다 (빌드 24 · 8번).
        guard FileManager.default.fileExists(atPath: url.path), !Self.isInTrash(url) else {
            defaults.removeObject(forKey: bookmarkKey)
            return .stale
        }
        return .folder(url)
    }

    /// `.Trash` 안인가 — iCloud Drive · 기기 안 둘 다 그 이름을 쓴다.
    static func isInTrash(_ url: URL) -> Bool {
        url.pathComponents.contains { $0 == ".Trash" || $0 == ".Trash-1000" }
    }

    static func remember(_ url: URL, defaults: UserDefaults = .standard) throws {
        let data = try url.bookmarkData(options: [.minimalBookmark],
                                        includingResourceValuesForKeys: nil,
                                        relativeTo: nil)
        defaults.set(data, forKey: bookmarkKey)
    }

    static func forget(defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: bookmarkKey)
    }

    // MARK: - 고르기

    /// 앱을 켤 때 쓸 폴더를 고른다.
    ///
    /// `async` 인 이유가 위 `iCloudDocuments()` 다 — 이 함수를 `@MainActor` 로
    /// 못 박아 두었던 것이 A2 반증의 원인이었다.
    static func current(
        launch: LaunchOptions,
        defaults: UserDefaults = .standard,
        attempts: Int = 3
    ) async -> FolderChoice {
        if launch.useSampleFolder {
            let url = await MainActor.run { SampleFolder.make() }
            // CI 가 **고른 폴더 상태의 설정 화면**을 찍으려고 쓴다 — 폴더 고르기 창은 시뮬레이터
            // 스크립트로 못 누른다. 임시 폴더를 (b) 인 척 쓴다. 보안 범위 열기는 실패해도
            // 그냥 지나가므로(일반 폴더) 화면만 다르고 동작은 같다.
            let kind: FolderKind = launch.pretendChosenFolder ? .userChosen : .sample
            return FolderChoice(url: url, kind: kind, iCloudAvailable: false, attempts: 0)
        }
        var staleBookmark = false
        switch bookmarkedFolder(defaults: defaults) {
        case .folder(let chosen):
            return FolderChoice(url: chosen, kind: .userChosen, iCloudAvailable: false, attempts: 0)
        case .stale:
            staleBookmark = true
        case .none:
            break
        }
        if launch.localFolderOnly {
            return FolderChoice(url: localDocuments(), kind: .localDocuments,
                                iCloudAvailable: false, attempts: 0, staleBookmark: staleBookmark)
        }
        if let cloud = await iCloudDocuments(attempts: attempts) {
            return FolderChoice(url: cloud, kind: .iCloudContainer, iCloudAvailable: true,
                                attempts: attempts, staleBookmark: staleBookmark)
        }
        // **조용히 물러나지 않는다.** 진단 화면이 이것을 보여 준다.
        return FolderChoice(url: localDocuments(), kind: .localDocuments,
                            iCloudAvailable: false, attempts: attempts, staleBookmark: staleBookmark)
    }

    /// 사용자가 문서 선택 창에서 고른 폴더를 (b) 로 기억한다. 북마크는 **보안 범위를 연 채**
    /// 만들어야 한다 — 그래서 여기서 열고 닫는다. 기억한 뒤 **북마크를 다시 풀어** 돌려준다:
    /// 앱을 켤 때 쓰는 것과 같은 URL 이어야 첫 사용과 다음 사용이 같은 길을 간다.
    static func adopt(_ picked: URL, defaults: UserDefaults = .standard) throws -> URL {
        let scoped = picked.startAccessingSecurityScopedResource()
        defer { if scoped { picked.stopAccessingSecurityScopedResource() } }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: picked.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            throw CocoaError(.fileReadUnknown)
        }
        try remember(picked, defaults: defaults)
        guard case .folder(let url) = bookmarkedFolder(defaults: defaults) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        return url
    }
}

/// 고른 결과. 왜 그 폴더가 됐는지까지 담는다 — 진단 화면이 쓴다.
struct FolderChoice: Sendable {
    let url: URL
    let kind: FolderKind
    /// iCloud 컨테이너를 잡을 수 있었나. `false` 인데 kind 가 `.localDocuments` 면
    /// **물러난 것**이다 (A2 가 안 되는 상태).
    let iCloudAvailable: Bool
    let attempts: Int
    /// 고른 폴더(b)의 북마크가 낡아 버리고 (a) 로 왔다. 화면이 알려야 한다.
    var staleBookmark: Bool = false
}

/// 실행 인자. CI 스크린샷이 화면을 지정해 찍을 때 쓴다.
struct LaunchOptions: Sendable {
    var useSampleFolder = false
    var localFolderOnly = false
    var skipOnboarding = false
    /// 아이폰에서도 첫 노트를 열고 시작한다 — **CI 가 상세 화면을 찍으려고** 쓴다.
    var openFirstNote = false
    /// 읽기 모드로 시작한다 — CI 가 뷰어(ADR-0004)를 찍으려고 쓴다.
    var readingMode = false
    /// 진단 화면을 열고 시작한다 — CI 가 그 화면을 찍으려고 쓴다.
    var showDiagnostics = false
    /// 첨부 시험 파일을 만들고 읽기 모드로 연다 — CI 가 **사진 셋이 다 그려지는지**
    /// 찍으려고 쓴다. 실기기로 내려보내기 전에 스크린샷 심판을 지난다.
    var attachmentTest = false
    /// 설정 화면을 열고 시작한다 — CI 가 그 화면을 찍으려고 쓴다.
    ///
    /// **선언 순서가 곧 초기화 인자 순서다.** 아래 `fromProcess` 와 맞춰 둔다.
    /// 빌드 7 직전에 `attachmentTest` 를 넣으면서 이 순서가 어긋나 한 번 잡혔다.
    var showSettings = false
    /// 새 노트를 만들고 열고 시작한다 — CI 가 만들기 → 열기 흐름을 찍으려고 쓴다.
    var newNote = false
    /// 설정 → 휴지통까지 열고 시작한다 — CI 가 그 화면을 찍으려고 쓴다. `-settings` 와 같이 준다.
    var showTrash = false
    /// 견본 폴더를 **고른 폴더(b)인 척** 연다 — CI 가 그 상태의 설정 화면을 찍으려고 쓴다.
    var pretendChosenFolder = false
    /// 검색 칸에 이 말을 넣고 시작한다 — CI 가 검색 결과를 찍으려고 쓴다 (`-search 회의`).
    var searchTerm: String?

    static func fromProcess(_ arguments: [String] = ProcessInfo.processInfo.arguments) -> LaunchOptions {
        LaunchOptions(
            useSampleFolder: arguments.contains("-sampleFolder"),
            localFolderOnly: arguments.contains("-localFolderOnly"),
            skipOnboarding: arguments.contains("-skipOnboarding") || arguments.contains("-sampleFolder"),
            openFirstNote: arguments.contains("-openFirstNote") || arguments.contains("-readingMode"),
            readingMode: arguments.contains("-readingMode"),
            showDiagnostics: arguments.contains("-diagnostics"),
            attachmentTest: arguments.contains("-attachmentTest"),
            showSettings: arguments.contains("-settings"),
            newNote: arguments.contains("-newNote"),
            showTrash: arguments.contains("-trash"),
            pretendChosenFolder: arguments.contains("-chosenFolder"),
            searchTerm: arguments.firstIndex(of: "-search").flatMap { index in
                index + 1 < arguments.count ? arguments[index + 1] : nil
            }
        )
    }
}
