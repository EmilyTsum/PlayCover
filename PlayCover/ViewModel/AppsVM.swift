//
//  AppViewModel.swift
//  PlayCover
//

import Foundation

private struct AppLibraryEntry: Sendable {
    let url: URL
    let bundleIdentifier: String
    let displayName: String
    let searchText: String
}

private enum AppLibraryScanner {
    static func scan(at directory: URL) throws -> [AppLibraryEntry] {
        let urls = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )

        return urls.compactMap(makeEntry(from:)).sorted { lhs, rhs in
            let order = lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName)
            return order == .orderedSame ? lhs.url.path < rhs.url.path : order == .orderedAscending
        }
    }

    private static func makeEntry(from url: URL) -> AppLibraryEntry? {
        guard url.pathExtension.lowercased() == "app",
              (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else {
            return nil
        }
        let infoURL = url.appendingPathComponent("Info.plist")
        guard let data = try? Data(contentsOf: infoURL),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil),
              let values = plist as? [String: Any],
              let bundleIdentifier = values["CFBundleIdentifier"] as? String,
              !bundleIdentifier.isEmpty else {
            return nil
        }
        let bundleName = values["CFBundleName"] as? String ?? ""
        let rawDisplayName = values["CFBundleDisplayName"] as? String ?? bundleName
        let displayName = rawDisplayName.isEmpty ? bundleIdentifier : rawDisplayName
        return AppLibraryEntry(
            url: url,
            bundleIdentifier: bundleIdentifier,
            displayName: displayName,
            searchText: "\(displayName) \(bundleName) \(bundleIdentifier)".lowercased()
        )
    }
}

private enum BundleIDCacheStore {
    static func reconcile(at url: URL, discovered: [String]) {
        let existing = (try? String(contentsOf: url, encoding: .utf8))?
            .split(whereSeparator: \.isNewline)
            .map(String.init) ?? []
        var seen = Set<String>()
        let merged = (existing + discovered).filter { !$0.isEmpty && seen.insert($0).inserted }
        let serialized = merged.map { $0 + "\n" }.joined()
        do {
            try serialized.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            Log.shared.error(error)
        }
    }
}

final class AppsVM: ObservableObject {
    public static let appDirectory = PlayTools.playCoverContainer.appendingPathComponent("Applications")
    static let shared = AppsVM()

    private init() {
        try? AppsVM.ensureBaseDirectoriesExist()
        PlayTools.installOnSystem()
        fetchApps()
    }

    static func ensureBaseDirectoriesExist() throws {
        try FileManager.default.createDirectory(at: appDirectory, withIntermediateDirectories: true)
    }

    @Published var filteredApps: [PlayApp] = []
    @Published var apps: [PlayApp] = []
    @Published var searchText: String = ""
    @Published var updatingApps = true
    private var fetchTask: Task<Void, Never>?

    func fetchApps() {
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.fetchTask?.cancel()
            self.updatingApps = true

            self.fetchTask = Task { @MainActor [weak self] in
                guard let self else { return }
                let entries: [AppLibraryEntry]
                do {
                    entries = try await Task.detached(priority: .userInitiated) {
                        try AppLibraryScanner.scan(at: AppsVM.appDirectory)
                    }.value
                } catch {
                    if !Task.isCancelled { Log.shared.error(error) }
                    if !Task.isCancelled { self.updatingApps = false }
                    return
                }
                guard !Task.isCancelled else { return }

                // PlayApp initialization performs PlayCover bookkeeping; keep that publication on
                // the main actor, but only after the expensive directory/plist scan is complete.
                let loadedApps = entries.map { PlayApp(appUrl: $0.url) }
                self.apps = loadedApps
                let query = self.searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                self.filteredApps = query.isEmpty ? loadedApps : loadedApps.filter { $0.searchText.contains(query) }
                self.filteredApps.sort {
                    $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
                }
                self.updatingApps = false

                let discoveredIDs = entries.map(\.bundleIdentifier)
                Task.detached(priority: .utility) {
                    BundleIDCacheStore.reconcile(at: PlayApp.bundleIDCacheURL, discovered: discoveredIDs)
                }
            }
        }
    }
}
