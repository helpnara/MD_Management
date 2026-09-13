import Foundation
import Core

/// 어느 폴더를 쓸지 고른다 (ADR-0002).
///
/// 순서: (a) 앱 iCloud 컨테이너 → 없으면 이 기기의 Documents.
/// (b) 사용자가 고른 폴더는 설정에서 북마크로 들어온다.
enum FolderSource {

    private static let bookmarkKey = "folder.bookmark"

    /// 앱 iCloud Drive 컨테이너. iCloud 를 못 쓰면 `nil`
    /// (시뮬레이터 · CI · iCloud 로그아웃 — 그래서 fallback 이 필요하다).
    static func iCloudDocuments() -> URL? {
        guard let container = FileManager.default.url(forUbiquityContainerIdentifier: nil) else {
            return nil
        }
        let documents = container.appendingPathComponent("Documents", isDirectory: true)
        try? FileManager.default.createDirectory(at: documents, withIntermediateDirectories: true)
        return documents
    }

    /// 기기 안 폴더. `Files` 앱에서도 보인다 (`UIFileSharingEnabled`).
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
        let data = try url.bookmarkData(options: [.minimalBookmark], includingResourceValuesForKeys: nil, relativeTo: nil)
        defaults.set(data, forKey: bookmarkKey)
    }

    static func forget(defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: bookmarkKey)
    }

    /// 앱을 켤 때 쓸 폴더를 고른다.
    @MainActor
    static func current(launch: LaunchOptions, defaults: UserDefaults = .standard) -> (URL, FolderKind) {
        if launch.useSampleFolder {
            return (SampleFolder.make(), .sample)
        }
        if let chosen = bookmarkedFolder(defaults: defaults) {
            return (chosen, .userChosen)
        }
        if !launch.localFolderOnly, let cloud = iCloudDocuments() {
            return (cloud, .iCloudContainer)
        }
        return (localDocuments(), .localDocuments)
    }
}

/// 실행 인자. CI 스크린샷이 화면을 지정해 찍을 때 쓴다.
struct LaunchOptions: Sendable {
    var useSampleFolder = false
    var localFolderOnly = false
    var skipOnboarding = false
    /// 아이폰에서도 첫 노트를 열고 시작한다 — **CI 가 상세 화면을 찍으려고** 쓴다.
    /// 화면을 지정해 찍지 않으면 목록 한 장밖에 못 본다.
    var openFirstNote = false

    static func fromProcess(_ arguments: [String] = ProcessInfo.processInfo.arguments) -> LaunchOptions {
        LaunchOptions(
            useSampleFolder: arguments.contains("-sampleFolder"),
            localFolderOnly: arguments.contains("-localFolderOnly"),
            skipOnboarding: arguments.contains("-skipOnboarding") || arguments.contains("-sampleFolder"),
            openFirstNote: arguments.contains("-openFirstNote")
        )
    }
}
