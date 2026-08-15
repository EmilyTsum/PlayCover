//
//  Sparkle.swift
//  PlayCover
//
//  Created by Andrew Glaze on 7/17/22.
//  Copied from https://sparkle-project.org/documentation/programmatic-setup/
//

import Sparkle
import SwiftUI

// This view model class manages Sparkle's updater and publishes when new updates are allowed to be checked
final class UpdaterViewModel: ObservableObject {
    private let updaterController: SPUStandardUpdaterController

    @Published var canCheckForUpdates = false

    var automaticallyCheckForUpdates: Bool {
        get { false }
        set { _ = newValue }
    }

    init() {
        // PTMC builds are distributed separately from the official Sparkle feed. Do not
        // let an official update silently replace the bundled capture-enabled PlayTools.
        updaterController = SPUStandardUpdaterController(
            startingUpdater: false,
            updaterDelegate: nil,
            userDriverDelegate: nil)
    }

    func checkForUpdates() {
        // Updates are supplied by the PTMC GitHub release/Homebrew tap instead.
    }
}

// This additional view is needed for the disabled state on the menu item to work properly before Monterey.
// See https://stackoverflow.com/questions/68553092/menu-not-updating-swiftui-bug for more information
struct CheckForUpdatesView: View {
    @ObservedObject var updaterViewModel: UpdaterViewModel

    var body: some View {
        Button(NSLocalizedString("menubar.checkForUpdates", comment: ""),
               systemImage: "arrow.trianglehead.2.clockwise.rotate.90",
               action: updaterViewModel.checkForUpdates)
            .disabled(!updaterViewModel.canCheckForUpdates)
    }
}
