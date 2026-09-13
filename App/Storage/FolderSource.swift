import Foundation
import Core

/// 어느 폴더를 쓸지 고른다 (ADR-0002).
///
/// 순서: (b) 사용자가 고른 폴더 → (a) 앱 iCloud 컨테이너 → 이 기기의 Documents.
enum FolderSource {

    private static let bookmarkKey = "folder.bookmark"

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

    // MARK: - 그 밖의 폴더

    /// 기기 안 폴더. `Files` 앱의 **이 iPhone 안에** 보인다 (`UIFileSharingEnabled`).
    static func localDocuments() -> URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    /// 저장해 둔 (b) 임의 폴더 북마크를 푼다. 낡았으면 `nil` — 다시 고르게 한다.
    static func bookmarkedFolder(defaults: UserDefaults = .standard) -> URL? {
        guard let data = defaults.data(forKey: bookmarkKey) else { return nil }
        var isStale = false
        guard let url = try? URL(resolvingBookmarkData: data,
                                 options: [],
                                 relativeTo: nil,
                                 bookmarkDataIsStale: &isStale),
              !isStale else {
            defaults.removeObject(forKey: bookmarkKey)
            return nil
        }
        return url
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
            return FolderChoice(url: url, kind: .sample, iCloudAvailable: false, attempts: 0)
        }
        if let chosen = bookmarkedFolder(defaults: defaults) {
            return FolderChoice(url: chosen, kind: .userChosen, iCloudAvailable: false, attempts: 0)
        }
        if launch.localFolderOnly {
            return FolderChoice(url: localDocuments(), kind: .localDocuments,
                                iCloudAvailable: false, attempts: 0)
        }
        if let cloud = await iCloudDocuments(attempts: attempts) {
            return FolderChoice(url: cloud, kind: .iCloudContainer, iCloudAvailable: true, attempts: attempts)
        }
        // **조용히 물러나지 않는다.** 진단 화면이 이것을 보여 준다.
        return FolderChoice(url: localDocuments(), kind: .localDocuments,
                            iCloudAvailable: false, attempts: attempts)
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

    static func fromProcess(_ arguments: [String] = ProcessInfo.processInfo.arguments) -> LaunchOptions {
        LaunchOptions(
            useSampleFolder: arguments.contains("-sampleFolder"),
            localFolderOnly: arguments.contains("-localFolderOnly"),
            skipOnboarding: arguments.contains("-skipOnboarding") || arguments.contains("-sampleFolder"),
            openFirstNote: arguments.contains("-openFirstNote") || arguments.contains("-readingMode"),
            readingMode: arguments.contains("-readingMode"),
            showDiagnostics: arguments.contains("-diagnostics")
        )
    }
}
