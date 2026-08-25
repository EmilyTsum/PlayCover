//
//  PlayCoverApp.swift
//  PlayCover
//

import SwiftUI
import Carbon.HIToolbox

// swiftlint:disable file_length

private let ptmcHotKeySignature = OSType(0x50544D43) // 'PTMC'
private let ptmcToggleHotKeyID: UInt32 = 1
private let ptmcStopHotKeyID: UInt32 = 2

private func ptmcHotKeyHandler(
    _ nextHandler: EventHandlerCallRef?,
    _ event: EventRef?,
    _ userData: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let event else { return OSStatus(eventNotHandledErr) }
    var hotKeyID = EventHotKeyID()
    let status = GetEventParameter(
        event,
        EventParamName(kEventParamDirectObject),
        EventParamType(typeEventHotKeyID),
        nil,
        MemoryLayout<EventHotKeyID>.size,
        nil,
        &hotKeyID
    )
    guard status == noErr, hotKeyID.signature == ptmcHotKeySignature else { return status }
    Task { @MainActor in
        PTMCGlobalHotKeyManager.shared.handleHotKey(id: hotKeyID.id)
    }
    return noErr
}

@MainActor
// swiftlint:disable:next type_body_length
final class PTMCGlobalHotKeyManager {
    static let shared = PTMCGlobalHotKeyManager()

    private var toggleHotKey: EventHotKeyRef?
    private var stopHotKey: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private var workspaceObservers: [NSObjectProtocol] = []
    private var operationInProgress = false
    private(set) var activeBundleIdentifier: String?

    private init() {}

    func install() {
        guard eventHandler == nil else { return }
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let handlerStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            ptmcHotKeyHandler,
            1,
            &eventType,
            nil,
            &eventHandler
        )
        guard handlerStatus == noErr else {
            Log.shared.log("PTMC global hotkey handler registration failed: \(handlerStatus)", isError: true)
            return
        }

        installWorkspaceObservers()
        refreshRegistration()
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            self.refreshRegistration()
        }
    }

    func uninstall() {
        unregisterHotKeys()
        if let eventHandler { RemoveEventHandler(eventHandler) }
        eventHandler = nil
        let center = NSWorkspace.shared.notificationCenter
        for observer in workspaceObservers { center.removeObserver(observer) }
        workspaceObservers.removeAll()
    }

    func refreshRegistration() {
        if eligibleRunningApps().isEmpty {
            unregisterHotKeys()
        } else {
            registerHotKeys()
        }
    }

    func hasActiveCapture() -> Bool {
        activeCaptureApp() != nil
    }

    func handleHotKey(id: UInt32) {
        switch id {
        case ptmcToggleHotKeyID:
            Task { @MainActor in await toggleRecordingFromHotKey() }
        case ptmcStopHotKeyID:
            Task { @MainActor in await stopRecordingFromHotKey() }
        default:
            break
        }
    }

    func start(app: PlayApp, source: MetalCaptureInvocationSource) async -> MetalCaptureHostStartResult {
        guard !operationInProgress else {
            return MetalCaptureHostStartResult(requested: false, audioState: "busy")
        }
        if isCaptureActive(app) || activeBundleIdentifier == app.info.bundleIdentifier {
            return MetalCaptureHostStartResult(requested: false, audioState: "already recording")
        }
        if let active = activeCaptureApp(), active.info.bundleIdentifier != app.info.bundleIdentifier {
            if app.settings.settings.metalCaptureFeedbackSounds { MetalCaptureFeedback.playError() }
            Log.shared.log(
                "PTMC start ignored because another capture is active: \(active.info.bundleIdentifier)",
                isError: true
            )
            return MetalCaptureHostStartResult(requested: false, audioState: "another game recording")
        }

        operationInProgress = true
        defer { operationInProgress = false }
        let result = await MetalCaptureHostWorkflow.start(app: app, source: source)
        if result.requested {
            activeBundleIdentifier = app.info.bundleIdentifier
            NSApp.dockTile.badgeLabel = "REC"
        }
        return result
    }

    func stop(app: PlayApp, source: MetalCaptureInvocationSource) async -> MetalCaptureHostStopResult {
        guard !operationInProgress else {
            return MetalCaptureHostStopResult(requested: false, audioState: "busy", audioResult: nil)
        }
        guard isCaptureActive(app) || activeBundleIdentifier == app.info.bundleIdentifier else {
            return MetalCaptureHostStopResult(requested: false, audioState: "idle", audioResult: nil)
        }

        operationInProgress = true
        defer { operationInProgress = false }
        let result = await MetalCaptureHostWorkflow.stop(app: app, source: source)
        if result.requested {
            activeBundleIdentifier = nil
            NSApp.dockTile.badgeLabel = nil
        }
        return result
    }

    func finalizeBeforeQuit() async {
        guard let app = activeCaptureApp() else { return }
        let result = await stop(app: app, source: .quit)
        guard let audioURL = result.audioResult?.url else {
            await waitForVideoFinalization(bundleIdentifier: app.info.bundleIdentifier)
            return
        }
        for _ in 0..<160 where FileManager.default.fileExists(atPath: audioURL.path) {
            try? await Task.sleep(nanoseconds: 250_000_000)
        }
    }

    private func registerHotKeys() {
        guard toggleHotKey == nil, stopHotKey == nil else { return }
        let baseModifiers = UInt32(cmdKey | optionKey)
        let toggleID = EventHotKeyID(signature: ptmcHotKeySignature, id: ptmcToggleHotKeyID)
        let stopID = EventHotKeyID(signature: ptmcHotKeySignature, id: ptmcStopHotKeyID)

        let toggleStatus = RegisterEventHotKey(
            UInt32(kVK_ANSI_R),
            baseModifiers,
            toggleID,
            GetApplicationEventTarget(),
            0,
            &toggleHotKey
        )
        let stopStatus = RegisterEventHotKey(
            UInt32(kVK_ANSI_R),
            baseModifiers | UInt32(shiftKey),
            stopID,
            GetApplicationEventTarget(),
            0,
            &stopHotKey
        )
        if toggleStatus != noErr || stopStatus != noErr {
            unregisterHotKeys()
            Log.shared.log(
                "PTMC global hotkey registration incomplete: toggle=\(toggleStatus) stop=\(stopStatus)",
                isError: true
            )
        }
    }

    private func unregisterHotKeys() {
        if let toggleHotKey { UnregisterEventHotKey(toggleHotKey) }
        if let stopHotKey { UnregisterEventHotKey(stopHotKey) }
        toggleHotKey = nil
        stopHotKey = nil
    }

    private func installWorkspaceObservers() {
        let center = NSWorkspace.shared.notificationCenter
        let launched = center.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification,
            object: nil,
            queue: .main
        ) { notification in
            guard let running = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  let bundleIdentifier = running.bundleIdentifier else { return }
            Task { @MainActor in
                await PTMCGlobalHotKeyManager.shared.handleApplicationLaunch(bundleIdentifier: bundleIdentifier)
            }
        }
        workspaceObservers.append(launched)
        let terminated = center.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification,
            object: nil,
            queue: .main
        ) { notification in
            guard let running = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  let bundleIdentifier = running.bundleIdentifier else { return }
            Task { @MainActor in
                await PTMCGlobalHotKeyManager.shared.handleApplicationTermination(
                    bundleIdentifier: bundleIdentifier
                )
            }
        }
        workspaceObservers.append(terminated)
    }

    // swiftlint:disable:next cyclomatic_complexity
    private func handleApplicationLaunch(bundleIdentifier: String) async {
        refreshRegistration()
        guard !operationInProgress,
              let app = AppsVM.shared.apps.first(where: {
                $0.info.bundleIdentifier == bundleIdentifier
              }) else { return }
        let capture = app.settings.settings
        guard capture.metalCaptureEnabled, capture.metalCaptureAutostart else { return }
        if let active = activeCaptureApp(), active.info.bundleIdentifier != bundleIdentifier {
            Log.shared.log(
                "PTMC autostart audio skipped because another capture is active: " +
                    active.info.bundleIdentifier,
                isError: true
            )
            return
        }

        activeBundleIdentifier = bundleIdentifier
        NSApp.dockTile.badgeLabel = "REC"
        if !capture.metalCaptureAudioEnabled {
            if capture.metalCaptureFeedbackSounds { MetalCaptureFeedback.playStart() }
            return
        }

        // The in-game runtime owns video autostart. The host attaches target-app audio as soon as
        // ScreenCaptureKit can see the newly launched process, without resetting the video session.
        operationInProgress = true
        defer { operationInProgress = false }
        for attempt in 0..<12 {
            do {
                if #available(macOS 13.0, *) {
                    try await MetalCaptureAudioRecorder.shared.start(
                        bundleIdentifier: bundleIdentifier,
                        audioFormat: capture.metalCaptureAudioFormat
                    )
                    if capture.metalCaptureFeedbackSounds { MetalCaptureFeedback.playStart() }
                    Log.shared.log("PTMC autostart audio attached: \(bundleIdentifier)")
                    return
                }
            } catch {
                if attempt == 11 {
                    if capture.metalCaptureFeedbackSounds { MetalCaptureFeedback.playError() }
                    Log.shared.log(
                        "PTMC autostart audio attach failed: \(error.localizedDescription)",
                        isError: true
                    )
                    return
                }
            }
            try? await Task.sleep(nanoseconds: 250_000_000)
        }
    }

    private func handleApplicationTermination(bundleIdentifier: String) async {
        defer { refreshRegistration() }
        guard activeBundleIdentifier == bundleIdentifier,
              let app = AppsVM.shared.apps.first(where: {
                $0.info.bundleIdentifier == bundleIdentifier
              }) else { return }
        _ = await stop(app: app, source: .gameExit)
    }

    private func toggleRecordingFromHotKey() async {
        guard let app = hotKeyTargetApp() else {
            Log.shared.log("PTMC hotkey ignored: no unique running capture-enabled PlayCover game", isError: true)
            MetalCaptureFeedback.playError()
            return
        }
        let settings = app.settings.settings
        guard settings.metalCaptureGlobalHotkeysEnabled else { return }
        if isCaptureActive(app) || activeBundleIdentifier == app.info.bundleIdentifier {
            _ = await stop(app: app, source: .hotkey)
        } else {
            _ = await start(app: app, source: .hotkey)
        }
    }

    private func stopRecordingFromHotKey() async {
        guard let app = activeCaptureApp() ?? hotKeyTargetApp() else {
            Log.shared.log("PTMC stop hotkey ignored: no active capture", isError: true)
            MetalCaptureFeedback.playError()
            return
        }
        guard app.settings.settings.metalCaptureGlobalHotkeysEnabled else { return }
        _ = await stop(app: app, source: .hotkey)
    }

    private func hotKeyTargetApp() -> PlayApp? {
        let candidates = eligibleRunningApps()
        if let frontmost = NSWorkspace.shared.frontmostApplication?.bundleIdentifier,
           let app = candidates.first(where: { $0.info.bundleIdentifier == frontmost }) {
            return app
        }
        return candidates.count == 1 ? candidates[0] : nil
    }

    private func eligibleRunningApps() -> [PlayApp] {
        AppsVM.shared.apps.filter { app in
            let settings = app.settings.settings
            return settings.metalCaptureEnabled &&
                settings.metalCaptureGlobalHotkeysEnabled &&
                !NSRunningApplication.runningApplications(withBundleIdentifier: app.info.bundleIdentifier).isEmpty
        }
    }

    private func activeCaptureApp() -> PlayApp? {
        if let activeBundleIdentifier,
           let app = AppsVM.shared.apps.first(where: { $0.info.bundleIdentifier == activeBundleIdentifier }) {
            return app
        }
        return AppsVM.shared.apps.first(where: { app in
            !NSRunningApplication.runningApplications(withBundleIdentifier: app.info.bundleIdentifier).isEmpty &&
                isCaptureActive(app)
        })
    }

    private func isCaptureActive(_ app: PlayApp) -> Bool {
        guard let phase = MetalCaptureStatus.read(
            bundleIdentifier: app.info.bundleIdentifier
        )?.phase else { return false }
        return ["requested", "armed", "recording", "stopping"].contains(phase)
    }

    private func waitForVideoFinalization(bundleIdentifier: String) async {
        for _ in 0..<80 {
            if let phase = MetalCaptureStatus.read(bundleIdentifier: bundleIdentifier)?.phase,
               phase == "finalized" || phase == "stopped" || phase == "error" {
                return
            }
            try? await Task.sleep(nanoseconds: 250_000_000)
        }
    }
}

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    @AppStorage("ShowLowPowerModeAlert") var showLowPowerModeAlert = true
    private var terminationInProgress = false

    func application(_ application: NSApplication, open urls: [URL]) {
        if let url = urls.first {
            URLHandler.shared.processURL(url: url)
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        UpdateScheme.checkForUpdate()

        UserDefaults.standard.register(
            defaults: ["NSApplicationCrashOnExceptions": true]
        )

        NotificationCenter.default.addObserver(self,
                                               selector: #selector(powerStateChanged),
                                               name: Notification.Name.NSProcessInfoPowerStateDidChange,
                                               object: nil)
        if ProcessInfo.processInfo.isLowPowerModeEnabled {
            powerModal()
        }
        URLCache.iconCache.removeAllCachedResponses()
        PTMCGlobalHotKeyManager.shared.install()

        // Code that run once on first launch
        let launchedBefore = UserDefaults.standard.bool(forKey: "launchedBefore")
        if !launchedBefore {
            UserDefaults.standard.set(true, forKey: "launchedBefore")

            // Initialize KeyCover with an automatically generated key
            let keyCoverPassword = KeyCoverPassword.shared.generateVerySecurePassword()
            KeyCoverPassword.shared.setKeyCoverPassword(keyCoverPassword)
            KeyCoverPreferences.shared.keyCoverEnabled = .selfGeneratedPassword
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard PTMCGlobalHotKeyManager.shared.hasActiveCapture() else {
            PTMCGlobalHotKeyManager.shared.uninstall()
            return .terminateNow
        }
        guard !terminationInProgress else { return .terminateLater }
        terminationInProgress = true
        Task { @MainActor in
            await PTMCGlobalHotKeyManager.shared.finalizeBeforeQuit()
            PTMCGlobalHotKeyManager.shared.uninstall()
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    @objc func powerStateChanged(_ notification: Notification) {
        if ProcessInfo.processInfo.isLowPowerModeEnabled {
            Task { @MainActor in
                self.powerModal()
            }
        }
    }

    func powerModal() {
        if showLowPowerModeAlert {
            let alert = NSAlert()
            alert.messageText = NSLocalizedString("alert.power.title", comment: "")
            alert.informativeText = NSLocalizedString("alert.power.subtitle", comment: "")
            alert.addButton(withTitle: NSLocalizedString("button.OK", comment: ""))
            alert.showsSuppressionButton = true
            alert.alertStyle = .critical

            if alert.runModal() == .alertFirstButtonReturn {
                showLowPowerModeAlert = alert.suppressionButton?.state == .off
            }
        }
    }
}

@main
struct PlayCoverApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject var updaterViewModel = UpdaterViewModel()
    var storeVM = StoreVM.shared

    @State var isSigningSetupShown = false

    var body: some Scene {
        WindowGroup {
            MainView(isSigningSetupShown: $isSigningSetupShown)
                .environmentObject(InstallVM.shared)
                .environmentObject(DownloadVM.shared)
                .environmentObject(AppsVM.shared)
                .environmentObject(storeVM)
                .environmentObject(AppIntegrity())
                .onAppear {
                    NSWindow.allowsAutomaticWindowTabbing = false
                    SoundDeviceService.shared.prepareSoundDevice()
                    NotifyService.shared.allowNotify()
                }
        }
        .handlesExternalEvents(matching: ["{same path of URL?}"]) // create new window if doesn't exist
        .commands {
            SidebarCommands()
            PlayCoverMenuView(isSigningSetupShown: $isSigningSetupShown)
            PlayCoverHelpMenuView(updaterViewModel: updaterViewModel)
            PlayCoverViewMenuView()
        }

        Settings {
            PlayCoverSettingsView(updaterViewModel: updaterViewModel)
                .environmentObject(storeVM)
        }
    }
}
