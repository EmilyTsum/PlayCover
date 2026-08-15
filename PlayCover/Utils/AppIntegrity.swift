//
//  AppIntegrity.swift
//  PlayCover
//

import Foundation

class AppIntegrity: ObservableObject {

    @Published var integrityOff: Bool = !AppIntegrity.insideAppsFolder

    func verifyAppIntegrity() {
        integrityOff = !AppIntegrity.insideAppsFolder
    }

    func moveToApps() {
        do {
            if let url = AppIntegrity.appUrl {
                FileManager.default.delete(at: AppIntegrity.expectedUrl)
                try FileManager.default.copyItem(at: url, to: AppIntegrity.expectedUrl)
                URL(fileURLWithPath: AppIntegrity.expectedUrl.path).openInFinder()
                FileManager.default.delete(at: url)
                    exit(0)
                }
            } catch {
                Log.shared.error(error)
        }
    }

    private static var appUrl: URL? {
        Bundle.main.resourceURL?.deletingLastPathComponent().deletingLastPathComponent()
    }

    private static var expectedUrl = URL(fileURLWithPath: "/Applications/PlayCover.app")

    private static var insideAppsFolder: Bool {
        guard let url = appUrl else { return false }

        let appURL = url.standardizedFileURL
        let applicationsURL = expectedUrl.standardizedFileURL

        // Homebrew casks expose apps through /Applications with a symlink whose target lives in
        // the Caskroom. Bundle.main can report that resolved Caskroom path, so a string-only
        // /Applications check incorrectly treats a valid Homebrew install as misplaced and can
        // present the move-app alert before the main SwiftUI hierarchy has rendered.
        let resolvedAppURL = appURL.resolvingSymlinksInPath()
        let resolvedApplicationsURL = applicationsURL.resolvingSymlinksInPath()

        return appURL.path.contains("Xcode") ||
            appURL == applicationsURL ||
            resolvedAppURL == resolvedApplicationsURL
    }

}
