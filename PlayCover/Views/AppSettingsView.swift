//
//  AppSettingsView.swift
//  PlayCover
//
//  Created by Isaac Marovitz on 14/08/2022.
//

import SwiftUI
import DataCache
import CoreFoundation
@preconcurrency import AVFoundation
import ScreenCaptureKit

enum BlockingTask {
    case none, playTools, introspection, iosFrameworks, applicationCategoryType
}

// swiftlint:disable file_length

enum SettingsSection: String, CaseIterable, Identifiable {
    case keymapping
    case graphics
    case capture
    case bypasses
    case misc
    case info

    var id: Self { self }

    var title: String {
        switch self {
        case .keymapping: return "Keymap"
        case .graphics: return "Graphics"
        case .capture: return "Capture"
        case .bypasses: return "Bypass"
        case .misc: return "Misc"
        case .info: return "Info"
        }
    }

}

struct AppSettingsView: View {
    @Environment(\.dismiss) var dismiss

    @ObservedObject var viewModel: AppSettingsVM

    @Binding var showKeymapSheet: Bool

    @State var resetSettingsCompletedAlert = false
    @State var closeView = false
    @State var appIcon: NSImage?
    @State var hasPlayTools: Bool?
    @State var hasAlias: Bool?

    @State private var currentTask = BlockingTask.none
    @State private var cache = DataCache.instance
    @State private var selectedSection = SettingsSection.keymapping

    var body: some View {
        VStack {
            HStack {
                Group {
                    if let image = appIcon {
                        Image(nsImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                    } else {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .frame(width: 60, height: 60)
                    }
                }
                .cornerRadius(10)
                .shadow(radius: 1)
                .frame(width: 33, height: 33)

                VStack {
                    HStack {
                        Text(String(
                            format:
                                NSLocalizedString("settings.title", comment: ""),
                            viewModel.app.name))
                            .font(.title2).bold()
                            .multilineTextAlignment(.leading)
                        Spacer()
                    }

                    let noPlayToolsWarning = Image(systemName: "exclamationmark.triangle")
                    let warning = NSLocalizedString("settings.noPlayTools", comment: "")

                    if !(hasPlayTools ?? true) {
                        HStack {
                            Text("\(noPlayToolsWarning) \(warning)")
                                .font(.caption)
                                .multilineTextAlignment(.leading)
                            Spacer()
                        }
                    }
                }
            }
            .task(priority: .userInitiated) {
                appIcon = cache.readImage(forKey: viewModel.app.info.bundleIdentifier)
            }

            Picker("Settings section", selection: $selectedSection) {
                ForEach(SettingsSection.allCases) { section in
                    Text(section.title)
                        .tag(section)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: .infinity)

            Group {
                switch selectedSection {
                case .keymapping:
                    KeymappingView(settings: $viewModel.settings)
                        .disabled(!(hasPlayTools ?? true))
                case .graphics:
                    GraphicsView(settings: $viewModel.settings)
                        .disabled(!(hasPlayTools ?? true))
                case .capture:
                    MetalCaptureView(settings: viewModel.settings,
                                     app: viewModel.app,
                                     hasPlayTools: hasPlayTools)
                case .bypasses:
                    BypassesView(settings: $viewModel.settings,
                                 hasPlayTools: $hasPlayTools,
                                 task: $currentTask,
                                 app: viewModel.app)
                        .disabled(!(hasPlayTools ?? true))
                case .misc:
                    MiscView(settings: $viewModel.settings,
                             closeView: $closeView,
                             hasPlayTools: $hasPlayTools,
                             hasAlias: $hasAlias,
                             task: $currentTask,
                             app: viewModel.app,
                             applicationCategoryType: viewModel.app.info.applicationCategoryType)
                case .info:
                    InfoView(info: viewModel.app.info, hasPlayTools: (hasPlayTools ?? true))
                }
            }
            .frame(minWidth: 500, minHeight: 250)
            .opacity(hasPlayTools != nil ? 1 : 0)
            HStack {
                Spacer()
                Button("settings.resetSettings") {
                    resetSettingsCompletedAlert.toggle()
                    viewModel.app.settings.reset()
                    closeView.toggle()
                }
                Button("playapp.keymap") {
                    closeView.toggle()
                    showKeymapSheet.toggle()
                }
                Button("button.OK") {
                    closeView.toggle()
                }
                .tint(.accentColor)
                .keyboardShortcut(.defaultAction)
            }
        }
        .disabled(currentTask != .none)
        .onChange(of: resetSettingsCompletedAlert) { _ in
            ToastVM.shared.showToast(
                toastType: .notice,
                toastDetails: NSLocalizedString("settings.resetSettingsCompleted", comment: ""))
        }
        .onChange(of: closeView) { _ in
            dismiss()
        }
        .task(priority: .background) {
            hasPlayTools = viewModel.app.hasPlayTools()
            hasAlias = viewModel.app.hasAlias()
        }
        .padding()
        .frame(width: 720, height: 560)
    }
}

struct KeymappingView: View {
    @Binding var settings: AppSettings
    @AppStorage("settings.settings.keymapping") private var keymapping = false
    @AppStorage("settings.settings.noKMOnInput") private var noKMOnInput = false
    @AppStorage("settings.settings.enableScrollWheel") private var enableScrollWheel = false
    var body: some View {
        ScrollView {
            VStack {
                HStack {
                    Toggle("settings.toggle.km", isOn: $settings.settings.keymapping)
                        .help("settings.toggle.km.help")
                    Spacer()
                    Toggle("settings.toggle.autoKM", isOn: $settings.settings.noKMOnInput)
                        .help("settings.toggle.autoKM.help")
                }
                HStack {
                    Toggle("settings.toggle.enableScrollWheel", isOn: $settings.settings.enableScrollWheel)
                        .help("settings.toggle.enableScrollWheel.help")
                    Spacer()
                }
                HStack {
                    Toggle("settings.toggle.disableBuiltinMouse", isOn: $settings.settings.disableBuiltinMouse)
                        .help("settings.toggle.disableBuiltinMouse.help")
                    Spacer()
                }
                HStack {
                    Text(String(
                        format: NSLocalizedString("settings.slider.mouseSensitivity", comment: ""),
                        settings.settings.sensitivity))
                    Spacer()
                    Slider(value: $settings.settings.sensitivity, in: 0...100, label: { EmptyView() })
                        .frame(width: 250)
                        .disabled(!settings.settings.keymapping)
                }
                Spacer()
            }
            .padding()
        }
    }
}

private enum MetalCaptureCommand: String {
    case start
    case stop
    case status
}

struct MetalCaptureStatus {
    let phase: String
    let message: String
    let timestamp: TimeInterval
    let outputPath: String?
    let drawableWidth: Int
    let drawableHeight: Int
    let sourceWidth: Int
    let sourceHeight: Int
    let outputWidth: Int
    let outputHeight: Int
    let presented: Int
    let captured: Int
    let encoded: Int
    let droppedPool: Int
    let droppedEncoder: Int
    let droppedLate: Int
    let unsupported: Int
    let skippedRate: Int
    let samplingSkipPerSecond: Double
    let presentFPS: Double
    let captureFPS: Double
    let encodedFPS: Double
    let inFlight: Int
    let pendingWrites: Int
    let bufferCount: Int
    let burstSlotUses: Int
    let codec: String
    let firstVideoHostTimeNs: UInt64
    let displaySync: Int
    let framebufferOnly: Int
    let edr: Int
    let presentHookCount: Int
    let captureEnabled: Bool
    let displaySuppressed: Bool
    let displayPresentSkipped: Bool
    let includeMetalHUDInCapture: Bool
    let metalHUDSuppressed: Bool
    let skippedPresents: Int
    let ownedCaptureCommandBuffers: Int
    let lastOwnedCaptureGPUTimeUs: Int
    let lastOwnedCaptureCompletionUs: Int
    let captureResolutionMode: String
    let memoryPath: String
    let colorSpace: String

    // swiftlint:disable:next function_body_length
    static func read(bundleIdentifier: String) -> MetalCaptureStatus? {
        let url = MetalCapturePaths.statusFile(for: bundleIdentifier)
        guard let data = try? Data(contentsOf: url),
              let object = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil),
              let values = object as? [String: Any] else { return nil }

        func integer(_ key: String) -> Int {
            (values[key] as? NSNumber)?.intValue ?? 0
        }

        return MetalCaptureStatus(
            phase: values["phase"] as? String ?? "unknown",
            message: values["message"] as? String ?? "",
            timestamp: (values["timestamp"] as? NSNumber)?.doubleValue ?? 0,
            outputPath: values["outputPath"] as? String,
            drawableWidth: integer("drawableWidth"),
            drawableHeight: integer("drawableHeight"),
            sourceWidth: integer("sourceWidth"),
            sourceHeight: integer("sourceHeight"),
            outputWidth: integer("width"),
            outputHeight: integer("height"),
            presented: integer("presented"),
            captured: integer("captured"),
            encoded: integer("encoded"),
            droppedPool: integer("droppedPool"),
            droppedEncoder: integer("droppedEncoder"),
            droppedLate: integer("droppedLate"),
            unsupported: integer("unsupported"),
            skippedRate: integer("samplingSkipped"),
            samplingSkipPerSecond: (values["samplingSkipPerSecond"] as? NSNumber)?.doubleValue ?? 0,
            presentFPS: (values["presentFPS"] as? NSNumber)?.doubleValue ?? 0,
            captureFPS: (values["captureFPS"] as? NSNumber)?.doubleValue ?? 0,
            encodedFPS: (values["encodedFPS"] as? NSNumber)?.doubleValue ?? 0,
            inFlight: integer("inFlight"),
            pendingWrites: integer("pendingWrites"),
            bufferCount: integer("bufferCount"),
            burstSlotUses: integer("burstSlotUses"),
            codec: values["codec"] as? String ?? "hevc",
            firstVideoHostTimeNs: (values["firstVideoHostTimeNs"] as? NSNumber)?.uint64Value ?? 0,
            displaySync: integer("displaySync"),
            framebufferOnly: integer("framebufferOnly"),
            edr: integer("edr"),
            presentHookCount: integer("presentHookCount"),
            captureEnabled: (values["captureEnabled"] as? NSNumber)?.boolValue ?? false,
            displaySuppressed: (values["displaySuppressed"] as? NSNumber)?.boolValue ?? false,
            displayPresentSkipped: (values["displayPresentSkipped"] as? NSNumber)?.boolValue ?? false,
            includeMetalHUDInCapture: (values["includeMetalHUDInCapture"] as? NSNumber)?.boolValue ?? false,
            metalHUDSuppressed: (values["metalHUDSuppressed"] as? NSNumber)?.boolValue ?? false,
            skippedPresents: integer("skippedPresents"),
            ownedCaptureCommandBuffers: integer("ownedCaptureCommandBuffers"),
            lastOwnedCaptureGPUTimeUs: integer("lastOwnedCaptureGPUTimeUs"),
            lastOwnedCaptureCompletionUs: integer("lastOwnedCaptureCompletionUs"),
            captureResolutionMode: values["captureResolutionMode"] as? String ?? "source",
            memoryPath: values["memoryPath"] as? String ?? "unknown",
            colorSpace: values["colorSpace"] as? String ?? "unknown"
        )
    }
}
extension MetalCaptureStatus {
    var totalDrops: Int { droppedPool + droppedEncoder + droppedLate + unsupported }
    var requestedMetricsVisible: Bool { presented > 0 || captured > 0 || encoded > 0 || totalDrops > 0 }
}

struct MetalCaptureAudioResult {
    let url: URL
    let firstHostTimeNs: UInt64
    let droppedSamples: Int
    let peakPendingSamples: Int
    let backpressureEvents: Int
    let sourceGapCount: Int
    let sourceGapSeconds: Double
    let pcmZeroRunCount: Int
    let pcmZeroSeconds: Double
    let pcmZeroMaxSeconds: Double
}

private final class MetalCaptureSendableBox<Value>: @unchecked Sendable {
    let value: Value

    init(_ value: Value) {
        self.value = value
    }
}

@available(macOS 13.0, *)
final class MetalCaptureAudioRecorder: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    static let shared = MetalCaptureAudioRecorder()

    private(set) var droppedSamples = 0
    private(set) var peakPendingSamples = 0
    private(set) var backpressureEvents = 0
    private(set) var sourceGapCount = 0
    private(set) var sourceGapSeconds = 0.0

    private let sampleQueue = DispatchQueue(label: "io.playcover.ptmc.audio", qos: .userInitiated)
    private let maxPendingSamples = 512
    private let drainRetryNanoseconds: UInt64 = 4_000_000
    private var stream: SCStream?
    private var writer: AVAssetWriter?
    private var writerInput: AVAssetWriterInput?
    private var outputURL: URL?
    private var firstHostTimeNs: UInt64 = 0
    private var appendedSamples = 0
    private var pendingSamples: [CMSampleBuffer] = []
    private var pendingHead = 0
    private var drainScheduled = false
    private var backpressureActive = false
    private var previousSampleEnd = CMTime.invalid
    private var pcmZeroRunFrames = 0
    private var pcmZeroRunCount = 0
    private var pcmZeroTotalFrames = 0
    private var pcmZeroMaxFrames = 0
    private var pcmZeroSampleRate = 48_000.0

    private var pendingSampleCount: Int {
        max(0, pendingSamples.count - pendingHead)
    }

    func start(bundleIdentifier: String) async throws {
        _ = await stop()
        droppedSamples = 0
        peakPendingSamples = 0
        backpressureEvents = 0
        sourceGapCount = 0
        sourceGapSeconds = 0
        firstHostTimeNs = 0
        appendedSamples = 0
        pendingSamples.removeAll(keepingCapacity: true)
        pendingHead = 0
        drainScheduled = false
        backpressureActive = false
        previousSampleEnd = .invalid
        pcmZeroRunFrames = 0
        pcmZeroRunCount = 0
        pcmZeroTotalFrames = 0
        pcmZeroMaxFrames = 0
        pcmZeroSampleRate = 48_000.0

        let content = try await SCShareableContent.excludingDesktopWindows(
            false,
            onScreenWindowsOnly: false
        )
        guard let application = content.applications.first(where: {
            $0.bundleIdentifier == bundleIdentifier
        }) else {
            throw "PTMC audio: target application is not available to ScreenCaptureKit"
        }
        guard let display = content.displays.first else {
            throw "PTMC audio: no display is available for the application audio filter"
        }

        let filter = SCContentFilter(
            display: display,
            including: [application],
            exceptingWindows: []
        )
        let configuration = makeStreamConfiguration()

        let directory = MetalCapturePaths.captureDirectory(for: bundleIdentifier)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let audioURL = directory.appendingPathComponent("PTMC-Audio-active.m4a")
        try? FileManager.default.removeItem(at: audioURL)

        let captureStream = SCStream(filter: filter, configuration: configuration, delegate: self)
        try captureStream.addStreamOutput(self, type: .audio, sampleHandlerQueue: sampleQueue)

        outputURL = audioURL
        stream = captureStream
        try await captureStream.startCapture()
    }

    func stop() async -> MetalCaptureAudioResult? {
        let activeStream = stream
        stream = nil
        if let activeStream {
            do {
                try await activeStream.stopCapture()
            } catch {
                Log.shared.log("PTMC audio stop failed: \(error.localizedDescription)", isError: true)
            }
        }

        return await withCheckedContinuation { continuation in
            sampleQueue.async {
                self.finishWriterWhenDrained(
                    deadlineNanoseconds: DispatchTime.now().uptimeNanoseconds + 5_000_000_000,
                    continuation: continuation
                )
            }
        }
    }

    func stream(
        _ stream: SCStream,
        didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
        of outputType: SCStreamOutputType
    ) {
        guard outputType == .audio, sampleBuffer.isValid else { return }

        if firstHostTimeNs == 0 {
            firstHostTimeNs = DispatchTime.now().uptimeNanoseconds
        }
        observeSourceTiming(sampleBuffer)
        observePCMZeroRuns(sampleBuffer)
        guard prepareWriterIfNeeded(for: sampleBuffer) else {
            droppedSamples += 1
            return
        }

        guard pendingSampleCount < maxPendingSamples else {
            droppedSamples += 1
            return
        }
        pendingSamples.append(sampleBuffer)
        peakPendingSamples = max(peakPendingSamples, pendingSampleCount)
        drainPendingSamples()
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        Log.shared.log("PTMC audio stream stopped: \(error.localizedDescription)", isError: true)
    }
}

@available(macOS 13.0, *)
private extension MetalCaptureAudioRecorder {
    func makeStreamConfiguration() -> SCStreamConfiguration {
        let configuration = SCStreamConfiguration()
        configuration.capturesAudio = true
        configuration.excludesCurrentProcessAudio = true
        configuration.sampleRate = 48_000
        configuration.channelCount = 2
        // PTMC only subscribes to audio. Keep internal screen work tiny, but do not throttle
        // ScreenCaptureKit's display scheduler to 1 fps: v0.1.10 real-device evidence showed
        // periodic zero-filled PCM while PTS stayed continuous.
        configuration.width = 2
        configuration.height = 2
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: 60)
        configuration.queueDepth = 8
        configuration.showsCursor = false
        return configuration
    }

    func observeSourceTiming(_ sampleBuffer: CMSampleBuffer) {
        let timestamp = sampleBuffer.presentationTimeStamp
        let duration = sampleBuffer.duration
        if previousSampleEnd.isValid, timestamp.isValid {
            let gap = CMTimeSubtract(timestamp, previousSampleEnd)
            let tolerance = CMTime(value: 2, timescale: 1_000)
            if gap.isNumeric, CMTimeCompare(gap, tolerance) > 0 {
                sourceGapCount += 1
                sourceGapSeconds += max(0, CMTimeGetSeconds(gap))
            }
        }
        if timestamp.isValid, duration.isValid, CMTimeCompare(duration, .zero) > 0 {
            previousSampleEnd = CMTimeAdd(timestamp, duration)
        } else if timestamp.isValid {
            previousSampleEnd = timestamp
        }
    }

    func observePCMZeroRuns(_ sampleBuffer: CMSampleBuffer) {
        try? sampleBuffer.withAudioBufferList { audioBufferList, _ in
            guard let formatDescription = sampleBuffer.formatDescription,
                  let description = formatDescription.audioStreamBasicDescription,
                  description.mSampleRate > 0 else { return }
            let format = AVAudioFormat(cmAudioFormatDescription: formatDescription)
            guard format.commonFormat == .pcmFormatFloat32,
                  let pcmBuffer = AVAudioPCMBuffer(
                    pcmFormat: format,
                    bufferListNoCopy: audioBufferList.unsafePointer
                  ),
                  let channelData = pcmBuffer.floatChannelData else { return }

            pcmZeroSampleRate = description.mSampleRate
            let channelCount = Int(pcmBuffer.format.channelCount)
            let frameCount = Int(pcmBuffer.frameLength)
            let threshold: Float = 0.000_001

            for frame in 0..<frameCount {
                let isZero: Bool
                if pcmBuffer.format.isInterleaved {
                    let base = frame * channelCount
                    isZero = (0..<channelCount).allSatisfy {
                        abs(channelData[0][base + $0]) <= threshold
                    }
                } else {
                    isZero = (0..<channelCount).allSatisfy {
                        abs(channelData[$0][frame]) <= threshold
                    }
                }
                if isZero {
                    pcmZeroRunFrames += 1
                } else {
                    finishPCMZeroRunIfNeeded()
                }
            }
        }
    }

    func finishPCMZeroRunIfNeeded() {
        guard pcmZeroRunFrames > 0 else { return }
        let minimumFrames = max(1, Int(pcmZeroSampleRate * 0.010))
        if pcmZeroRunFrames >= minimumFrames {
            pcmZeroRunCount += 1
            pcmZeroTotalFrames += pcmZeroRunFrames
            pcmZeroMaxFrames = max(pcmZeroMaxFrames, pcmZeroRunFrames)
        }
        pcmZeroRunFrames = 0
    }

    func prepareWriterIfNeeded(for sampleBuffer: CMSampleBuffer) -> Bool {
        if writer != nil { return true }
        guard let url = outputURL,
              let formatDescription = sampleBuffer.formatDescription else { return false }

        do {
            // ScreenCaptureKit app-audio buffers are PCM. AVAssetWriter passthrough
            // (`outputSettings = nil`) is for media that is already in a compatible
            // encoded format; using it here caused v0.1.9 to finalize video-only files.
            // Keep the bounded backlog, but restore the known-good AAC writer path.
            let assetWriter = try AVAssetWriter(outputURL: url, fileType: .m4a)
            let selectedInput = AVAssetWriterInput(
                mediaType: .audio,
                outputSettings: [
                    AVFormatIDKey: kAudioFormatMPEG4AAC,
                    AVSampleRateKey: 48_000,
                    AVNumberOfChannelsKey: 2,
                    AVEncoderBitRateKey: 256_000
                ],
                sourceFormatHint: formatDescription
            )
            selectedInput.expectsMediaDataInRealTime = true
            guard assetWriter.canAdd(selectedInput) else { return false }
            assetWriter.add(selectedInput)
            guard assetWriter.startWriting() else {
                Log.shared.log(
                    "PTMC audio writer failed to start: \(assetWriter.error?.localizedDescription ?? "unknown error")",
                    isError: true
                )
                return false
            }
            assetWriter.startSession(atSourceTime: sampleBuffer.presentationTimeStamp)
            writer = assetWriter
            writerInput = selectedInput
            return true
        } catch {
            Log.shared.log("PTMC audio writer setup failed: \(error.localizedDescription)", isError: true)
            return false
        }
    }

    func drainPendingSamples(scheduleRetry: Bool = true) {
        guard let writer, let input = writerInput, writer.status == .writing else { return }

        while pendingHead < pendingSamples.count && input.isReadyForMoreMediaData {
            let sample = pendingSamples[pendingHead]
            pendingHead += 1
            if input.append(sample) {
                appendedSamples += 1
            } else {
                droppedSamples += 1
            }
        }

        compactPendingSamples()
        if pendingSampleCount > 0 {
            if !backpressureActive {
                backpressureActive = true
                backpressureEvents += 1
            }
            if scheduleRetry { scheduleDrain() }
        } else {
            backpressureActive = false
        }
    }

    func scheduleDrain() {
        guard !drainScheduled else { return }
        drainScheduled = true
        sampleQueue.asyncAfter(deadline: .now() + .nanoseconds(Int(drainRetryNanoseconds))) { [weak self] in
            guard let self else { return }
            self.drainScheduled = false
            self.drainPendingSamples()
        }
    }

    func compactPendingSamples() {
        if pendingHead == pendingSamples.count {
            pendingSamples.removeAll(keepingCapacity: true)
            pendingHead = 0
        } else if pendingHead >= 128 && pendingHead * 2 >= pendingSamples.count {
            pendingSamples.removeFirst(pendingHead)
            pendingHead = 0
        }
    }

    func finishWriterWhenDrained(
        deadlineNanoseconds: UInt64,
        continuation: CheckedContinuation<MetalCaptureAudioResult?, Never>
    ) {
        drainPendingSamples(scheduleRetry: false)
        if pendingSampleCount > 0, DispatchTime.now().uptimeNanoseconds < deadlineNanoseconds {
            sampleQueue.asyncAfter(deadline: .now() + .milliseconds(5)) { [weak self] in
                self?.finishWriterWhenDrained(
                    deadlineNanoseconds: deadlineNanoseconds,
                    continuation: continuation
                )
            }
            return
        }

        if pendingSampleCount > 0 {
            droppedSamples += pendingSampleCount
            pendingSamples.removeAll(keepingCapacity: true)
            pendingHead = 0
        }
        finishWriter(continuation: continuation)
    }

    func finishWriter(continuation: CheckedContinuation<MetalCaptureAudioResult?, Never>) {
        guard let writer,
              let input = writerInput,
              let url = outputURL,
              appendedSamples > 0 else {
            if let url = outputURL { try? FileManager.default.removeItem(at: url) }
            clearWriterState()
            continuation.resume(returning: nil)
            return
        }

        finishPCMZeroRunIfNeeded()
        input.markAsFinished()
        let writerBox = MetalCaptureSendableBox(writer)
        let pcmRate = max(1, pcmZeroSampleRate)
        let result = MetalCaptureAudioResult(
            url: url,
            firstHostTimeNs: firstHostTimeNs,
            droppedSamples: droppedSamples,
            peakPendingSamples: peakPendingSamples,
            backpressureEvents: backpressureEvents,
            sourceGapCount: sourceGapCount,
            sourceGapSeconds: sourceGapSeconds,
            pcmZeroRunCount: pcmZeroRunCount,
            pcmZeroSeconds: Double(pcmZeroTotalFrames) / pcmRate,
            pcmZeroMaxSeconds: Double(pcmZeroMaxFrames) / pcmRate
        )
        writer.finishWriting {
            let writer = writerBox.value
            let completed = writer.status == .completed
            if !completed {
                Log.shared.log(
                    "PTMC audio writer failed: \(writer.error?.localizedDescription ?? "unknown error")",
                    isError: true
                )
                try? FileManager.default.removeItem(at: url)
            }
            self.clearWriterState()
            continuation.resume(returning: completed ? result : nil)
        }
    }

    func clearWriterState() {
        writer = nil
        writerInput = nil
        outputURL = nil
        firstHostTimeNs = 0
        appendedSamples = 0
        pendingSamples.removeAll(keepingCapacity: true)
        pendingHead = 0
        drainScheduled = false
        backpressureActive = false
        previousSampleEnd = .invalid
        pcmZeroRunFrames = 0
        pcmZeroRunCount = 0
        pcmZeroTotalFrames = 0
        pcmZeroMaxFrames = 0
        pcmZeroSampleRate = 48_000.0
    }
}

enum MetalCaptureControl {
    static func post(_ command: String, bundleIdentifier: String, settings: AppSettingsData? = nil) {
        guard let typedCommand = MetalCaptureCommand(rawValue: command) else { return }
        if let settings {
            MetalCapturePaths.writeRuntimeConfig(bundleIdentifier: bundleIdentifier, settings: settings)
        }
        let rawName = "io.playcover.ptmc.\(typedCommand.rawValue).\(bundleIdentifier)" as CFString
        let name = CFNotificationName(rawValue: rawName)
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            name,
            nil,
            nil,
            true
        )
    }

    static func revealCaptures(bundleIdentifier: String) {
        let directory = MetalCapturePaths.captureDirectory(for: bundleIdentifier)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        NSWorkspace.shared.open(directory)
    }

    static func exportCompletedCaptures(bundleIdentifier: String, outputDirectory: String) {
        let sourceDirectory = MetalCapturePaths.captureDirectory(for: bundleIdentifier)
        let destinationDirectory = MetalCapturePaths.exportDirectory(from: outputDirectory)
        Task.detached(priority: .utility) {
            let fileManager = FileManager.default
            do {
                try fileManager.createDirectory(at: destinationDirectory, withIntermediateDirectories: true)
                let files = try fileManager.contentsOfDirectory(
                    at: sourceDirectory,
                    includingPropertiesForKeys: nil,
                    options: [.skipsHiddenFiles]
                )
                for source in files where source.pathExtension.lowercased() == "mov" &&
                    !source.lastPathComponent.hasSuffix(".partial.mov") &&
                    !source.lastPathComponent.hasPrefix("PTMC-Audio-") {
                    var destination = destinationDirectory.appendingPathComponent(source.lastPathComponent)
                    var suffix = 1
                    while fileManager.fileExists(atPath: destination.path) {
                        let base = source.deletingPathExtension().lastPathComponent
                        destination = destinationDirectory
                            .appendingPathComponent("\(base)-\(suffix)")
                            .appendingPathExtension("mov")
                        suffix += 1
                    }
                    do {
                        try fileManager.moveItem(at: source, to: destination)
                    } catch {
                        do {
                            try fileManager.copyItem(at: source, to: destination)
                            try fileManager.removeItem(at: source)
                        } catch {
                            Log.shared.log("PTMC export failed: \(error.localizedDescription)", isError: true)
                        }
                    }
                }
            } catch {
                Log.shared.log("PTMC export scan failed: \(error.localizedDescription)", isError: true)
            }
        }
    }

    static func exportAfterFinalization(
        bundleIdentifier: String,
        outputDirectory: String,
        audioResult: MetalCaptureAudioResult? = nil
    ) {
        Task.detached(priority: .utility) {
            for _ in 0..<120 {
                if let status = MetalCaptureStatus.read(bundleIdentifier: bundleIdentifier),
                   status.phase == "finalized" {
                    if let audioResult,
                       let outputPath = status.outputPath {
                        let videoURL = URL(fileURLWithPath: outputPath)
                        let muxed = await muxAudio(
                            videoURL: videoURL,
                            audioResult: audioResult,
                            firstVideoHostTimeNs: status.firstVideoHostTimeNs
                        )
                        if !muxed {
                            Log.shared.log(
                                "PTMC audio mux failed; preserving video-only capture and audio sidecar",
                                isError: true
                            )
                        }
                    }
                    exportCompletedCaptures(
                        bundleIdentifier: bundleIdentifier,
                        outputDirectory: outputDirectory
                    )
                    return
                }
                try? await Task.sleep(nanoseconds: 250_000_000)
            }
            Log.shared.log("PTMC finalize timed out while waiting to export capture", isError: true)
        }
    }

    // swiftlint:disable:next function_body_length cyclomatic_complexity
    private static func muxAudio(
        videoURL: URL,
        audioResult: MetalCaptureAudioResult,
        firstVideoHostTimeNs: UInt64
    ) async -> Bool {
        guard FileManager.default.fileExists(atPath: videoURL.path),
              FileManager.default.fileExists(atPath: audioResult.url.path) else { return false }

        let videoAsset = AVURLAsset(url: videoURL)
        let audioAsset = AVURLAsset(url: audioResult.url)
        guard let sourceVideo = videoAsset.tracks(withMediaType: .video).first,
              let sourceAudio = audioAsset.tracks(withMediaType: .audio).first else { return false }

        let composition = AVMutableComposition()
        guard let videoTrack = composition.addMutableTrack(
            withMediaType: .video,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ), let audioTrack = composition.addMutableTrack(
            withMediaType: .audio,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) else { return false }

        do {
            try videoTrack.insertTimeRange(
                CMTimeRange(start: .zero, duration: videoAsset.duration),
                of: sourceVideo,
                at: .zero
            )

            let videoDuration = videoAsset.duration
            let audioDuration = audioAsset.duration
            let deltaNs: Int64
            if firstVideoHostTimeNs > 0 {
                deltaNs = Int64(clamping: firstVideoHostTimeNs) - Int64(clamping: audioResult.firstHostTimeNs)
            } else {
                deltaNs = 0
            }

            let billion: CMTimeScale = 1_000_000_000
            if deltaNs >= 0 {
                let trim = CMTime(value: deltaNs, timescale: billion)
                let remaining = CMTimeSubtract(audioDuration, trim)
                let duration = minimumTime(remaining, videoDuration)
                if duration > .zero {
                    try audioTrack.insertTimeRange(
                        CMTimeRange(start: trim, duration: duration),
                        of: sourceAudio,
                        at: .zero
                    )
                }
            } else {
                let insertion = CMTime(value: -deltaNs, timescale: billion)
                let availableVideo = CMTimeSubtract(videoDuration, insertion)
                let duration = minimumTime(audioDuration, availableVideo)
                if duration > .zero {
                    try audioTrack.insertTimeRange(
                        CMTimeRange(start: .zero, duration: duration),
                        of: sourceAudio,
                        at: insertion
                    )
                }
            }
        } catch {
            Log.shared.log("PTMC composition failed: \(error.localizedDescription)", isError: true)
            return false
        }

        guard hasSufficientMuxSpace(videoURL: videoURL, audioURL: audioResult.url) else { return false }

        let muxedURL = videoURL.deletingPathExtension().appendingPathExtension("muxed.mov")
        try? FileManager.default.removeItem(at: muxedURL)
        guard let exporter = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetPassthrough) else {
            return false
        }
        exporter.outputURL = muxedURL
        exporter.outputFileType = .mov
        let exporterBox = MetalCaptureSendableBox(exporter)
        let exported = await withCheckedContinuation { continuation in
            exporter.exportAsynchronously {
                continuation.resume(returning: exporterBox.value.status == .completed)
            }
        }
        guard exported else {
            Log.shared.log(
                "PTMC mux export failed: \(exporter.error?.localizedDescription ?? "unknown error")",
                isError: true
            )
            return false
        }
        guard validateMuxedCapture(muxedURL) else {
            try? FileManager.default.removeItem(at: muxedURL)
            Log.shared.log("PTMC mux validation failed; preserving original video and audio sidecar", isError: true)
            return false
        }

        let backupURL = videoURL.deletingPathExtension().appendingPathExtension("video-only.tmp.mov")
        let fileManager = FileManager.default
        do {
            try? fileManager.removeItem(at: backupURL)
            try fileManager.moveItem(at: videoURL, to: backupURL)
            do {
                try fileManager.moveItem(at: muxedURL, to: videoURL)
                try? fileManager.removeItem(at: backupURL)
                try? fileManager.removeItem(at: audioResult.url)
                return true
            } catch {
                try? fileManager.moveItem(at: backupURL, to: videoURL)
                throw error
            }
        } catch {
            Log.shared.log("PTMC mux replace failed: \(error.localizedDescription)", isError: true)
            return false
        }
    }

    private static func hasSufficientMuxSpace(videoURL: URL, audioURL: URL) -> Bool {
        let fileManager = FileManager.default
        let videoAttributes = try? fileManager.attributesOfItem(atPath: videoURL.path)
        let audioAttributes = try? fileManager.attributesOfItem(atPath: audioURL.path)
        guard let videoSize = (videoAttributes?[.size] as? NSNumber)?.int64Value,
              let audioSize = (audioAttributes?[.size] as? NSNumber)?.int64Value,
              let available = (try? fileManager.attributesOfFileSystem(
                forPath: videoURL.deletingLastPathComponent().path
              )[.systemFreeSize] as? NSNumber)?.int64Value else { return true }

        // Passthrough export writes a second copy of the movie before the original is atomically
        // replaced. The backup step is a rename, not another full copy. Reserve 1 GiB beyond the
        // expected muxed size for container/exporter overhead.
        let reserve: Int64 = 1_073_741_824
        let required = videoSize + audioSize + reserve
        guard available >= required else {
            Log.shared.log(
                "PTMC mux skipped: insufficient disk space; required=\(required) available=\(available). " +
                "Preserving video-only capture and audio sidecar.",
                isError: true
            )
            return false
        }
        return true
    }

    private static func validateMuxedCapture(_ url: URL) -> Bool {
        let asset = AVURLAsset(url: url)
        guard asset.tracks(withMediaType: .video).first != nil,
              asset.tracks(withMediaType: .audio).first != nil else { return false }
        let seconds = CMTimeGetSeconds(asset.duration)
        return seconds.isFinite && seconds > 0
    }

    private static func minimumTime(_ lhs: CMTime, _ rhs: CMTime) -> CMTime {
        CMTimeCompare(lhs, rhs) <= 0 ? lhs : rhs
    }

}

// swiftlint:disable:next type_body_length
struct MetalCaptureView: View {
    @ObservedObject var settings: AppSettings
    let app: PlayApp
    let hasPlayTools: Bool?
    @State private var captureStatus: MetalCaptureStatus?
    @State private var commandSentAt: Date?
    @State private var commandLabel = ""
    @State private var pollNow = Date()
    @State private var gameRunning = false
    @State private var partialFiles = 0
    @State private var completedFiles = 0
    @State private var audioState = "idle"

    private var defaultOutputDescription: String {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Movies")
            .path
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Pre-compositor Metal Capture")
                        .font(.headline)
                    Text("Capture the game's Metal output before WindowServer composition.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Toggle("Enabled", isOn: $settings.settings.metalCaptureEnabled)
                    .toggleStyle(.switch)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            if hasPlayTools == false {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                    Text("PlayTools was not detected in this game's executable. " +
                         "Capture settings can still be configured, " +
                         "but recording requires PlayTools to be installed for the game.")
                        .font(.caption)
                    Spacer()
                }
                .foregroundStyle(.secondary)
                .padding(.horizontal, 14)
                .padding(.bottom, 10)
            }

            captureStatusView
                .padding(.horizontal, 14)
                .padding(.bottom, 10)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Toggle("Start recording automatically when the game launches",
                           isOn: $settings.settings.metalCaptureAutostart)

                    HStack {
                        Text("Video codec")
                        Spacer()
                        Picker("", selection: $settings.settings.metalCaptureCodec) {
                            Text("HEVC (hardware)").tag("hevc")
                            Text("ProRes 422 LT").tag("prores422lt")
                            Text("ProRes 422").tag("prores422")
                            Text("ProRes 422 HQ").tag("prores422hq")
                        }
                        .frame(width: 180)
                    }

                    HStack {
                        Text("Capture resolution")
                        Spacer()
                        Picker("", selection: $settings.settings.metalCaptureResolutionMode) {
                            Text("Source / native").tag("source")
                            Text("2160p max").tag("2160p")
                            Text("1440p max").tag("1440p")
                            Text("1080p max").tag("1080p")
                            Text("720p max").tag("720p")
                            Text("Custom max").tag("custom")
                        }
                        .frame(width: 180)
                    }

                    if settings.settings.metalCaptureResolutionMode == "custom" {
                        HStack {
                            Text("Custom maximum size")
                            Spacer()
                            Stepper(
                                value: $settings.settings.metalCaptureCustomWidth,
                                in: 2...16_384,
                                step: 2
                            ) {
                                Text("W \(settings.settings.metalCaptureCustomWidth)")
                                    .monospacedDigit()
                                    .frame(width: 90, alignment: .trailing)
                            }
                            Stepper(
                                value: $settings.settings.metalCaptureCustomHeight,
                                in: 2...16_384,
                                step: 2
                            ) {
                                Text("H \(settings.settings.metalCaptureCustomHeight)")
                                    .monospacedDigit()
                                    .frame(width: 90, alignment: .trailing)
                            }
                        }
                    }

                    Text(
                        "Capture scaling is performed on the GPU directly into IOSurface-backed encoder buffers. " +
                        "PTMC does not read frames back through the CPU or allocate an intermediate full-frame " +
                        "image. It preserves the source aspect ratio and never upscales above the game drawable."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)

                    Toggle("Record game audio", isOn: $settings.settings.metalCaptureAudioEnabled)
                        .help(
                            "Captures only the target game audio with ScreenCaptureKit at 48 kHz stereo AAC. " +
                            "PTMC buffers short AVAssetWriter stalls instead of dropping samples immediately."
                        )

                    Toggle("Include Metal HUD in recording", isOn: $settings.settings.metalCaptureIncludeHUD)
                        .help(
                            "Off by default. PTMC temporarily hides the target CAMetalLayer's Metal Performance HUD " +
                            "while recording, then restores its previous HUD configuration on Stop. " +
                            "Turn this on only when you want HUD diagnostics burned into the captured video."
                        )

                    HStack {
                        Text("Capture frame rate")
                        Spacer()
                        Stepper(value: $settings.settings.metalCaptureFPS, in: 1...240) {
                            Text("\(settings.settings.metalCaptureFPS) fps")
                                .monospacedDigit()
                                .frame(width: 90, alignment: .trailing)
                        }
                    }

                    if settings.settings.metalCaptureCodec == "hevc" {
                        HStack {
                            Text("HEVC bitrate")
                            Spacer()
                            Stepper(value: $settings.settings.metalCaptureBitrateMbps, in: 1...1000, step: 10) {
                                Text("\(settings.settings.metalCaptureBitrateMbps) Mbps")
                                    .monospacedDigit()
                                    .frame(width: 110, alignment: .trailing)
                            }
                        }
                    } else {
                        Text(
                            "ProRes uses VideoToolbox hardware encoding when available and ignores the HEVC bitrate " +
                            "setting. At 4K/120, disk bandwidth can be very high, especially with 422 HQ."
                        )
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    HStack {
                        Text("Capture buffer slots")
                        Spacer()
                        Stepper(value: $settings.settings.metalCaptureBuffers, in: 3...16) {
                            Text("\(settings.settings.metalCaptureBuffers)")
                                .monospacedDigit()
                                .frame(width: 40, alignment: .trailing)
                        }
                    }
                    Text(
                        "3 is recommended for low-latency capture. PTMC also keeps one cooldown-limited emergency " +
                        "slot for isolated encoder latency spikes; increasing the regular ring can raise 4K " +
                        "GPU/unified-memory pressure."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)

                    HStack {
                        Text("Status log interval")
                        Spacer()
                        Stepper(value: $settings.settings.metalCaptureLogInterval, in: 0.25...60, step: 0.25) {
                            Text(String(format: "%.2f s", settings.settings.metalCaptureLogInterval))
                                .monospacedDigit()
                                .frame(width: 80, alignment: .trailing)
                        }
                    }

                    Divider()

                    Toggle("Disable CAMetalLayer display synchronization",
                           isOn: $settings.settings.metalCaptureDisableDisplaySync)
                        .help("Optional frame-pacing diagnostic. Leave off unless the game presents at only 60 fps.")

                    Toggle("Suppress on-screen game output while recording (experimental)",
                           isOn: $settings.settings.metalCaptureSuppressDisplayOutput)
                        .help(
                            "Makes the capture CAMetalLayer transparent while still presenting drawables so they " +
                            "recycle normally. This may let WindowServer cull visible composition work. The original " +
                            "opacity is restored on Stop."
                        )
                    Toggle("Skip display present while recording (unsafe experiment)",
                           isOn: $settings.settings.metalCaptureSkipDisplayPresent)
                        .help(
                            "Stops forwarding CAMetalDrawable present calls after PTMC captures the frame. This can " +
                            "remove compositor work but may starve the drawable pool or freeze some games. Prefer " +
                            "Suppress on-screen output first. Automatically restores normal present on Stop."
                        )

                    Toggle("Force SDR presentation for capture",
                           isOn: $settings.settings.metalCaptureForceSDRDisplay)
                        .help(
                            "While capture is enabled, PTMC forces EDR off and normalizes " +
                            "the Metal layer colorspace to sRGB."
                        )

                    HStack {
                        Text("Spoof UIScreen maximum FPS")
                        Spacer()
                        Picker("", selection: $settings.settings.metalCaptureSpoofMaxFPS) {
                            Text("Off").tag(0)
                            Text("60").tag(60)
                            Text("90").tag(90)
                            Text("120").tag(120)
                            Text("144").tag(144)
                            Text("165").tag(165)
                            Text("240").tag(240)
                        }
                        .frame(width: 130)
                    }

                    Divider()

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Export destination")
                        HStack {
                            TextField("Default: ~/Movies", text: $settings.settings.metalCaptureOutputDirectory)
                            Button("Choose…") {
                                chooseOutputDirectory()
                            }
                            Button("Default") {
                                settings.settings.metalCaptureOutputDirectory = ""
                            }
                        }
                        Text("Finalized recordings are staged inside PlayCover's container first, then exported to " +
                             (settings.settings.metalCaptureOutputDirectory.isEmpty
                              ? defaultOutputDescription
                              : settings.settings.metalCaptureOutputDirectory) + ".")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("This avoids the game sandbox blocking writes to Movies or another user-selected folder.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Divider()

                    HStack {
                        Button("Start Recording") {
                            Task {
                                await startRecording()
                            }
                        }
                        .buttonStyle(.borderedProminent)

                        Button("Stop Recording") {
                            Task {
                                await stopRecording()
                            }
                        }

                        Button("Refresh Status") {
                            MetalCaptureControl.post(
                                "status",
                                bundleIdentifier: app.info.bundleIdentifier,
                                settings: settings.settings
                            )
                            refreshRuntimeState()
                        }
                        Spacer()
                    }

                    HStack {
                        Button("Open Capture Staging") {
                            MetalCaptureControl.revealCaptures(bundleIdentifier: app.info.bundleIdentifier)
                        }
                        Button("Export Completed") {
                            MetalCaptureControl.exportCompletedCaptures(
                                bundleIdentifier: app.info.bundleIdentifier,
                                outputDirectory: settings.settings.metalCaptureOutputDirectory
                            )
                        }
                        Spacer()
                    }

                    Text("Start/Stop/Status target only this game's bundle identifier. " +
                         "The runtime panel above refreshes automatically while this settings window is open.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .disabled(!settings.settings.metalCaptureEnabled)
                .padding(14)
            }
        }
        .task(id: app.info.bundleIdentifier) {
            MetalCapturePaths.writeRuntimeConfig(
                bundleIdentifier: app.info.bundleIdentifier,
                settings: settings.settings
            )
            MetalCaptureControl.exportCompletedCaptures(
                bundleIdentifier: app.info.bundleIdentifier,
                outputDirectory: settings.settings.metalCaptureOutputDirectory
            )
            while !Task.isCancelled {
                pollNow = Date()
                refreshRuntimeState()
                // PlayTools publishes a one-second heartbeat while recording. Reading that file is
                // enough; don't send a Darwin notification and rewrite config every poll.
                try? await Task.sleep(nanoseconds: 500_000_000)
            }
        }
        .onChange(of: settings.settings.metalCaptureEnabled) { enabled in
            syncRuntimeConfiguration(command: enabled ? "status" : "stop")
        }
        .onChange(of: settings.settings.metalCaptureForceSDRDisplay) { _ in
            syncRuntimeConfiguration(command: "status")
        }
        .onChange(of: settings.settings.metalCaptureIncludeHUD) { _ in
            syncRuntimeConfiguration(command: "status")
        }
        .onChange(of: settings.settings.metalCaptureDisableDisplaySync) { _ in
            syncRuntimeConfiguration(command: "status")
        }
        .onChange(of: settings.settings.metalCaptureSpoofMaxFPS) { _ in
            syncRuntimeConfiguration(command: "status")
        }
        .onChange(of: settings.settings.metalCaptureCodec) { _ in
            syncRuntimeConfiguration(command: "status")
        }
        .onChange(of: settings.settings.metalCaptureResolutionMode) { _ in
            syncRuntimeConfiguration(command: "status")
        }
        .onChange(of: settings.settings.metalCaptureCustomWidth) { _ in
            syncRuntimeConfiguration(command: "status")
        }
        .onChange(of: settings.settings.metalCaptureCustomHeight) { _ in
            syncRuntimeConfiguration(command: "status")
        }
        .onChange(of: settings.settings.metalCaptureSuppressDisplayOutput) { _ in
            syncRuntimeConfiguration(command: "status")
        }
        .onChange(of: settings.settings.metalCaptureSkipDisplayPresent) { _ in
            syncRuntimeConfiguration(command: "status")
        }
        .onChange(of: settings.settings.metalCaptureFPS) { _ in
            syncRuntimeConfiguration(command: "status")
        }
        .onChange(of: settings.settings.metalCaptureBitrateMbps) { _ in
            syncRuntimeConfiguration(command: "status")
        }
        .onChange(of: settings.settings.metalCaptureBuffers) { _ in
            syncRuntimeConfiguration(command: "status")
        }
        .onChange(of: settings.settings.metalCaptureLogInterval) { _ in
            syncRuntimeConfiguration(command: "status")
        }
    }

    @ViewBuilder
    private var captureStatusView: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                if isRuntimeBusy {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: captureStatus?.phase == "error"
                          ? "exclamationmark.triangle.fill"
                          : "waveform.path.ecg")
                }
                Text(runtimeTitle)
                    .font(.caption.bold())
                Spacer()
                Text(gameRunning ? "game running" : "game not running")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Text(runtimeMessage)
                .font(.caption)
                .foregroundStyle(captureStatus?.phase == "error" ? .red : .secondary)

            if let status = captureStatus {
                Text(
                    "hooks \(status.presentHookCount) • \(status.codec.uppercased()) • " +
                    "present \(String(format: "%.1f", status.presentFPS)) fps • " +
                    "capture \(String(format: "%.1f", status.captureFPS)) fps • " +
                    "encode \(String(format: "%.1f", status.encodedFPS)) fps"
                )
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                Text(
                    "frames: presented \(status.presented) • captured \(status.captured) • " +
                    "encoded \(status.encoded) • drops \(status.totalDrops) • " +
                    "sampling skips total \(status.skippedRate) " +
                    "(\(String(format: "%.1f", status.samplingSkipPerSecond))/s)"
                )
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                if status.samplingSkipPerSecond > 1,
                   status.presentFPS > Double(settings.settings.metalCaptureFPS) + 5 {
                    Text(
                        "Sampling skips are intentional target-FPS filtering here: the game is presenting faster " +
                        "than the configured capture rate. They do not represent encoder drops."
                    )
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                }
                Text("SDR gate \(status.captureEnabled ? "enabled" : "disabled") • " +
                     "EDR \(status.edr == 1 ? "on" : "off") • colorspace \(status.colorSpace)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                HStack(spacing: 12) {
                    if status.drawableWidth > 0 && status.drawableHeight > 0 {
                        Text("drawable \(status.drawableWidth)×\(status.drawableHeight)")
                    }
                    if status.outputWidth > 0 && status.outputHeight > 0 {
                        Text("capture \(status.outputWidth)×\(status.outputHeight)")
                    }
                    Text("last PTMC update \(statusAgeText(status)) ago")
                    if status.outputPath != nil {
                        Text("output path armed")
                    }
                }
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
                Text(
                    "pipeline: raw in-flight \(status.inFlight)/\(status.bufferCount) regular (+1 burst) • " +
                    "compressed pending \(status.pendingWrites) • burst recoveries \(status.burstSlotUses) • " +
                    "present skips \(status.skippedPresents)"
                )
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
                if status.ownedCaptureCommandBuffers > 0 {
                    let gpuMilliseconds = Double(status.lastOwnedCaptureGPUTimeUs) / 1000.0
                    let completionMilliseconds = Double(status.lastOwnedCaptureCompletionUs) / 1000.0
                    Text(
                        "capture command: GPU \(String(format: "%.2f", gpuMilliseconds)) ms • " +
                        "completion \(String(format: "%.2f", completionMilliseconds)) ms • " +
                        "owned CB \(status.ownedCaptureCommandBuffers)"
                    )
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                }
                Text(
                    status.includeMetalHUDInCapture
                        ? "Metal HUD: included in capture"
                        : (status.metalHUDSuppressed
                            ? "Metal HUD: excluded during recording (restored on Stop)"
                            : "Metal HUD: exclusion armed")
                )
                .font(.caption2)
                .foregroundStyle(.secondary)
                Text(
                    "GPU path: \(status.memoryPath) • display " +
                    (status.displayPresentSkipped ? "present bypass" :
                     (status.displaySuppressed ? "transparent" : "normal"))
                )
                .font(.caption2)
                .foregroundStyle(.secondary)
            }

            HStack(spacing: 6) {
                if audioState == "finalizing" || audioState.hasPrefix("muxing") {
                    ProgressView()
                        .controlSize(.small)
                }
                Text("staging: \(partialFiles) recording • \(completedFiles) completed • audio \(audioState)")
            }
            .font(.caption2.monospacedDigit())
            .foregroundStyle(.secondary)
        }
    }

    private var isRuntimeBusy: Bool {
        guard let phase = captureStatus?.phase else { return commandSentAt != nil && gameRunning }
        return ["requested", "armed", "recording", "active", "stopping"].contains(phase)
    }

    private var runtimeTitle: String {
        guard gameRunning else { return "Runtime: idle" }
        if let status = captureStatus {
            if status.timestamp > 0 && pollNow.timeIntervalSince1970 - status.timestamp > 7 {
                return "Runtime: stale heartbeat"
            }
            return "Runtime: \(status.phase)"
        }
        return "Runtime: waiting for PTMC heartbeat"
    }

    private var runtimeMessage: String {
        if let sent = commandSentAt,
           captureStatus == nil || (captureStatus?.timestamp ?? 0) < sent.timeIntervalSince1970 {
            let elapsed = max(0, pollNow.timeIntervalSince(sent))
            return "\(commandLabel) command sent • waiting " +
                "\(String(format: "%.1f", elapsed)) s for PTMC acknowledgement"
        }
        if let status = captureStatus {
            return status.message
        }
        if gameRunning {
            return "The game process is running, but PTMC has not published a status heartbeat yet."
        }
        return "Launch the game to establish a PTMC runtime heartbeat."
    }

    @MainActor
    private func startRecording() async {
        audioState = settings.settings.metalCaptureAudioEnabled ? "preparing" : "disabled"
        if settings.settings.metalCaptureAudioEnabled {
            if #available(macOS 13.0, *) {
                do {
                    try await MetalCaptureAudioRecorder.shared.start(
                        bundleIdentifier: app.info.bundleIdentifier
                    )
                    audioState = "capturing"
                } catch {
                    audioState = "error"
                    Log.shared.log(
                        "PTMC game-audio capture unavailable: \(error.localizedDescription)",
                        isError: true
                    )
                }
            } else {
                audioState = "unsupported"
            }
        }

        commandSentAt = Date()
        commandLabel = "Start"
        MetalCaptureControl.post(
            "start",
            bundleIdentifier: app.info.bundleIdentifier,
            settings: settings.settings
        )
    }

    @MainActor
    private func stopRecording() async {
        commandSentAt = Date()
        commandLabel = "Stop"
        MetalCaptureControl.post(
            "stop",
            bundleIdentifier: app.info.bundleIdentifier,
            settings: settings.settings
        )

        var audioResult: MetalCaptureAudioResult?
        if #available(macOS 13.0, *) {
            if settings.settings.metalCaptureAudioEnabled {
                audioState = "finalizing"
            }
            audioResult = await MetalCaptureAudioRecorder.shared.stop()
            if let audioResult {
                audioState = "muxing • drop \(audioResult.droppedSamples) • " +
                    "source gaps \(audioResult.sourceGapCount) • zero runs \(audioResult.pcmZeroRunCount)"
                Log.shared.log(
                    "PTMC audio finalized: drops=\(audioResult.droppedSamples) " +
                    "peakQueue=\(audioResult.peakPendingSamples) " +
                    "backpressure=\(audioResult.backpressureEvents) " +
                    "sourceGaps=\(audioResult.sourceGapCount) " +
                    "sourceGapMs=\(String(format: "%.1f", audioResult.sourceGapSeconds * 1000)) " +
                    "pcmZeroRuns=\(audioResult.pcmZeroRunCount) " +
                    "pcmZeroMs=\(String(format: "%.1f", audioResult.pcmZeroSeconds * 1000)) " +
                    "pcmZeroMaxMs=\(String(format: "%.1f", audioResult.pcmZeroMaxSeconds * 1000)) " +
                    "path=AAC 256k"
                )
            } else {
                audioState = settings.settings.metalCaptureAudioEnabled ? "none" : "disabled"
            }
        }
        MetalCaptureControl.exportAfterFinalization(
            bundleIdentifier: app.info.bundleIdentifier,
            outputDirectory: settings.settings.metalCaptureOutputDirectory,
            audioResult: audioResult
        )
        if let audioResult {
            for _ in 0..<120 {
                if !FileManager.default.fileExists(atPath: audioResult.url.path) {
                    audioState = "muxed"
                    break
                }
                try? await Task.sleep(nanoseconds: 250_000_000)
            }
        }
    }

    private func statusAgeText(_ status: MetalCaptureStatus) -> String {
        guard status.timestamp > 0 else { return "unknown" }
        let age = max(0, pollNow.timeIntervalSince1970 - status.timestamp)
        return age < 10 ? String(format: "%.1f s", age) : "\(Int(age)) s"
    }

    private func syncRuntimeConfiguration(command: String) {
        MetalCapturePaths.writeRuntimeConfig(
            bundleIdentifier: app.info.bundleIdentifier,
            settings: settings.settings
        )
        guard gameRunning else { return }
        MetalCaptureControl.post(
            command,
            bundleIdentifier: app.info.bundleIdentifier,
            settings: settings.settings
        )
    }

    private func refreshRuntimeState() {
        captureStatus = MetalCaptureStatus.read(bundleIdentifier: app.info.bundleIdentifier)
        gameRunning = !NSRunningApplication.runningApplications(
            withBundleIdentifier: app.info.bundleIdentifier
        ).isEmpty

        let directory = MetalCapturePaths.captureDirectory(for: app.info.bundleIdentifier)
        let files = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )) ?? []
        partialFiles = files.filter { $0.lastPathComponent.hasSuffix(".partial.mov") }.count
        completedFiles = files.filter {
            $0.pathExtension.lowercased() == "mov" && !$0.lastPathComponent.hasSuffix(".partial.mov")
        }.count
    }

    private func chooseOutputDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.prompt = "Choose"
        if panel.runModal() == .OK, let url = panel.url {
            settings.settings.metalCaptureOutputDirectory = url.path
        }
    }
}

// swiftlint:disable:next type_body_length
struct GraphicsView: View {
    @Binding var settings: AppSettings
    @State var customWidth = 1920
    @State var customHeight = 1080
    @State var showResolutionWarning = false
    @AppStorage("settings.settings.inverseScreenValues") private var inverseScreenValues = false
    @AppStorage("settings.settings.disableTimeout") private var disableTimeout = false
    @AppStorage("settings.toggle.hideTitleBar") private var hideTitleBar = false
    @AppStorage("settings.toggle.floatingWindow") private var floatingWindow = false
    @AppStorage("settings.settings.displayRotation") private var displayRotation = 0
    static var number: NumberFormatter {
        let formatter = NumberFormatter()
        formatter.numberStyle = .none
        return formatter
    }

    @State var customScaler = 2.0
    static var fractionFormatter: NumberFormatter {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 1
        formatter.minimumFractionDigits = 1
        formatter.decimalSeparator = "."
        return formatter
    }

    var body: some View {
        ScrollView {
            VStack {
                HStack {
                    Text("settings.picker.iosDevice")
                    Spacer()
                    Picker("", selection: $settings.settings.iosDeviceModel) {
                        Text("iPad Pro (12.9-inch) (1st gen) | A9X | 4GB").tag("iPad6,7")
                        Text("iPad Pro (12.9-inch) (3rd gen) | A12X | 4GB").tag("iPad8,6")
                        Text("iPad Pro (12.9-inch) (5th gen) | M1 | 8GB").tag("iPad13,8")
                        Text("iPad Pro (12.9-inch) (6th gen) | M2 | 8GB").tag("iPad14,5")
                        Text("iPad Pro (13-inch) (7th gen) | M4 | 8GB").tag("iPad16,6")
                        Text("iPad Pro (13-inch) (M5) | M5 | 16GB").tag("iPad17,3")
                        Divider()
                        Text("iPhone 13 Pro Max | A15 | 6GB").tag("iPhone14,3")
                        Text("iPhone 14 Pro Max | A16 | 6GB").tag("iPhone15,3")
                        Text("iPhone 15 Pro Max | A17 Pro | 8GB").tag("iPhone16,2")
                        Text("iPhone 16 Pro Max | A18 Pro | 8GB").tag("iPhone17,2")
                        Text("iPhone 17 Pro Max | A19 Pro | 12GB").tag("iPhone18,2")
                    }
                    .frame(width: 250)
                }
                HStack {
                    if showResolutionWarning {
                        Spacer()
                        let highResIcon = Image(systemName: "exclamationmark.triangle")
                        let warning = NSLocalizedString("settings.highResolution", comment: "")

                        Text("\(highResIcon) \(warning)")
                            .font(.caption)
                    } else {
                        Spacer()
                    }
                }
                HStack {
                    Text("settings.picker.adaptiveRes")
                    Spacer()
                    Picker("", selection: $settings.settings.resolution) {
                        Text("settings.picker.adaptiveRes.0").tag(0)
                        Text("settings.picker.adaptiveRes.1").tag(1)
                        Text("1080p").tag(2)
                        Text("1440p").tag(3)
                        Text("4K").tag(4)
                        Text("settings.picker.adaptiveRes.5").tag(5)
                        Text("settings.picker.adaptiveRes.6").tag(6)
                    }
                    .frame(width: 250, alignment: .leading)
                    .help("settings.picker.adaptiveRes.help")
                }
                HStack {
                    if settings.settings.resolution == 5 {
                        Text(NSLocalizedString("settings.text.customWidth", comment: "") + ":")
                        Stepper {
                            TextField(
                                "settings.text.customWidth",
                                value: $customWidth,
                                formatter: GraphicsView.number,
                                onCommit: {
                                    Task { @MainActor in
                                        NSApp.keyWindow?.makeFirstResponder(nil)
                                    }
                                })
                                .frame(width: 125)
                        }
                        onIncrement: { customWidth += 1 }
                        onDecrement: { customWidth -= 1 }
                        Spacer()
                        Text(NSLocalizedString("settings.text.customHeight", comment: "") + ":")
                        Stepper {
                            TextField(
                                "settings.text.customHeight",
                                value: $customHeight,
                                formatter: GraphicsView.number,
                                onCommit: {
                                    Task { @MainActor in
                                        NSApp.keyWindow?.makeFirstResponder(nil)
                                    }
                                })
                                .frame(width: 125)
                        } onIncrement: {
                            customHeight += 1
                        } onDecrement: {
                            customHeight -= 1
                        }
                    } else if settings.settings.resolution >= 2 && settings.settings.resolution <= 4 {
                        Text("settings.picker.aspectRatio")
                        Spacer()
                        Picker("", selection: $settings.settings.aspectRatio) {
                            Text("4:3").tag(0)
                            Text("16:9").tag(1)
                            Text("16:10").tag(2)
                        }
                        .pickerStyle(.radioGroup)
                        .horizontalRadioGroupLayout()
                    } else if settings.settings.resolution == 6 {
                        Text("settings.picker.aspectRatio")
                        VStack(alignment: .trailing) {
                            Picker("", selection: $settings.settings.resizableAspectRatioType) {
                                Text("settings.picker.aspectRatio.free").tag(0)
                                Text("settings.picker.aspectRatio.custom").tag(1)
                                Text("4:3").tag(2)
                                Text("16:9").tag(3)
                                Text("16:10").tag(4)
                            }
                            .pickerStyle(.radioGroup)
                            .horizontalRadioGroupLayout()
                            if settings.settings.resizableAspectRatioType == 1 {
                                HStack {
                                    TextField("", value: $settings.settings.resizableAspectRatioWidth,
                                              formatter: GraphicsView.number)
                                    .frame(width: 110)
                                    Text(":")
                                    TextField("", value: $settings.settings.resizableAspectRatioHeight,
                                              formatter: GraphicsView.number)
                                    .frame(width: 110)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .trailing)
                    } else if settings.settings.resolution == 1 {
                        let width = Int(NSScreen.main?.frame.width ?? 1920)
                        let height = getHeightForNotch(width, Int(NSScreen.main?.frame.height ?? 1080))
                        Text("settings.text.detectedResolution")
                        Spacer()
                        Text("\(width) x \(height)")
                    } else {
                        Spacer()
                    }
                }
                HStack {
                    Text("settings.picker.scaler")
                    Spacer()
                    Stepper {
                        TextField(
                            "settings.text.scaler",
                            value: $customScaler,
                            formatter: GraphicsView.fractionFormatter,
                            onCommit: {
                                Task { @MainActor in NSApp.keyWindow?.makeFirstResponder(nil) }
                            })
                            .frame(width: 125)
                    } onIncrement: {
                        customScaler += 0.1
                    } onDecrement: {
                        if customScaler > 0.5 { customScaler -= 0.1 }
                    }
                }
                VStack(alignment: .leading) {
                    if #available(macOS 13.2, *) {
                        HStack {
                            Toggle("settings.picker.windowFix", isOn: $settings.settings.inverseScreenValues)
                                .help("settings.picker.windowFix.help")
                                .onChange(of: settings.settings.inverseScreenValues) { _ in
                                    settings.settings.windowFixMethod = 0
                                }
                            Spacer()
                            // Dropdown to choose fix method
                            Picker("", selection: $settings.settings.windowFixMethod) {
                                Text("settings.picker.windowFixMethod.0").tag(0)
                                Text("settings.picker.windowFixMethod.1").tag(1)
                            }
                            .frame(alignment: .leading)
                            .help("settings.picker.windowFixMethod.help")
                            .disabled(!settings.settings.inverseScreenValues)
                            .disabled(settings.settings.resolution != 0)
                        }
                        Spacer()
                    }
                    HStack {
                        Text("settings.settings.displayRotation")
                        Spacer()
                        Picker("", selection: $settings.settings.displayRotation) {
                            Text("settings.settings.displayRotation.default").tag(0)
                            Text("settings.settings.displayRotation.portrait").tag(1)
                            Text("settings.settings.displayRotation.landscapeRight").tag(2)
                            Text("settings.settings.displayRotation.portraitUpsideDown").tag(3)
                            Text("settings.settings.displayRotation.flipFix").tag(4)
                        }
                        .frame(alignment: .leading)
                    }
                    Spacer()
                    Toggle("settings.toggle.disableDisplaySleep", isOn: $settings.settings.disableTimeout)
                        .help("settings.toggle.disableDisplaySleep.help")
                    Spacer()
                    Toggle("settings.toggle.hideTitleBar", isOn: $settings.settings.hideTitleBar)
                    Spacer()
                    Toggle("settings.toggle.floatingWindow", isOn: $settings.settings.floatingWindow)
                    Spacer()
                }
                Spacer()
            }
            .padding()
            .onAppear {
                customWidth = settings.settings.windowWidth
                customHeight = settings.settings.windowHeight
                customScaler = settings.settings.customScaler
            }
            .onChange(of: settings.settings.resolution) { _ in
                setResolution()
            }
            .onChange(of: settings.settings.aspectRatio) { _ in
                setResolution()
            }
            .onChange(of: customWidth) { _ in
                setResolution()
            }
            .onChange(of: customHeight) { _ in
                setResolution()
            }
            .onChange(of: customScaler) { _ in
                setResolution()
            }
            .onChange(of: settings.settings.resizableAspectRatioType) { _ in
                setAspectRatioForResizableWindow()
            }
        }
    }

    func setResolution() {
        var width: Int
        var height: Int

        switch settings.settings.resolution {
        // Adaptive resolution = Auto
        case 1:
            width = Int(NSScreen.main?.frame.width ?? 1920)
            height = getHeightForNotch(width, Int(NSScreen.main?.frame.height ?? 1080))
        // Adaptive resolution = 1080p
        case 2:
            height = 1080
            width = getWidthFromAspectRatio(height)
        // Adaptive resolution = 1440p
        case 3:
            height = 1440
            width = getWidthFromAspectRatio(height)
        // Adaptive resolution = 4K
        case 4:
            height = 2160
            width = getWidthFromAspectRatio(height)
        // Adaptive resolution = Custom
        case 5:
            width = customWidth
            height = customHeight
        // Adaptive resolution = Off
        default:
            height = 1080
            width = 1920
        }

        settings.settings.windowWidth = width
        settings.settings.windowHeight = height
        settings.settings.customScaler = customScaler

        showResolutionWarning = Double(width * height) * customScaler >= 2621440 * 2.0
        // Tends to crash when the number of pixels exceeds that
    }

    func getWidthFromAspectRatio(_ height: Int) -> Int {
        var widthRatio: Int
        var heightRatio: Int

        switch settings.settings.aspectRatio {
        case 0:
            widthRatio = 4
            heightRatio = 3
        case 1:
            widthRatio = 16
            heightRatio = 9
        case 2:
            widthRatio = 16
            heightRatio = 10
        default:
            widthRatio = 16
            heightRatio = 9
        }
        return (height / heightRatio) * widthRatio
    }
    func getHeightForNotch(_ width: Int, _ height: Int) -> Int {
        let wFloat = Float(width)
        let hFloat = Float(height)
        if NSScreen.hasNotch() && (hFloat/wFloat)*16.0 > 10.3 && (hFloat/wFloat)*16.0 < 10.4 {
            return Int((wFloat / 16) * 10)
        } else {
            return Int(height)
        }
    }

    func setAspectRatioForResizableWindow() {
        var widthRatio = 0
        var heightRatio = 0

        switch settings.settings.resizableAspectRatioType {
        // Aspect ratio = Free
        case 0:
            widthRatio = 0
            heightRatio = 0
        // Aspect ratio = Custom
        case 1:
            widthRatio = settings.settings.resizableAspectRatioWidth
            heightRatio = settings.settings.resizableAspectRatioHeight
        // Aspect ratio = 4:3
        case 2:
            widthRatio = 4
            heightRatio = 3
        // Aspect ratio = 16:9
        case 3:
            widthRatio = 16
            heightRatio = 9
        // Aspect ratio = 16:10
        case 4:
            widthRatio = 16
            heightRatio = 10
        default:
            widthRatio = 16
            heightRatio = 9
        }

        settings.settings.resizableAspectRatioWidth = widthRatio
        settings.settings.resizableAspectRatioHeight = heightRatio
    }
}

struct BypassesView: View {
    @Binding var settings: AppSettings
    @Binding var hasPlayTools: Bool?
    @Binding var task: BlockingTask
    @AppStorage("settings.settings.playChain") private var playChain = false
    @AppStorage("settings.settings.playChainDebugging") private var playChainDebugging = false
    @AppStorage("settings.settings.bypass") private var bypass = false
    @State private var hasIntrospection: Bool
    @State private var hasIosFrameworks: Bool

    var app: PlayApp

    init(settings: Binding<AppSettings>,
         hasPlayTools: Binding<Bool?>,
         task: Binding<BlockingTask>,
         app: PlayApp) {
        self._settings = settings
        self._hasPlayTools = hasPlayTools
        self._task = task
        self.app = app

        let lsEnvironment = app.info.lsEnvironment["DYLD_LIBRARY_PATH"] ?? ""
        self.hasIntrospection = lsEnvironment.contains(PlayApp.introspection)
        self.hasIosFrameworks = lsEnvironment.contains(PlayApp.iosFrameworks)
    }

    var body: some View {
        ScrollView {
            VStack {
                HStack(alignment: .center) {
                    Toggle("settings.playChain.enable", isOn: $settings.settings.playChain)
                        .help("settings.playChain.help")
                        .disabled(!(hasPlayTools ?? true))
                    Spacer()
                    Toggle("settings.playChain.debugging", isOn: $settings.settings.playChainDebugging)
                        .disabled(!settings.settings.playChain)
                }
                Spacer()
                    .frame(height: 20)
                HStack {
                    Toggle("settings.toggle.jbBypass", isOn: $settings.settings.bypass)
                        .help("settings.toggle.jbBypass.help")
                    Spacer()
                }
                Spacer()
                HStack {
                    Toggle("settings.toggle.introspection", isOn: $hasIntrospection)
                        .help("settings.toggle.introspection.help")
                        .toggleStyle(.async($task, role: .introspection))
                    Spacer()
                }
                Spacer()
                HStack {
                    Toggle("settings.toggle.iosFrameworks", isOn: $hasIosFrameworks)
                        .help("settings.toggle.iosFrameworks.help")
                        .toggleStyle(.async($task, role: .iosFrameworks))
                    Spacer()
                }
                Spacer()
                HStack {
                    Toggle("settings.toggle.checkMicPermissionSync", isOn: $settings.settings.checkMicPermissionSync)
                        .help("settings.toggle.checkMicPermissionSync.help")
                    Spacer()
                }
                Spacer()
                HStack {
                    Toggle("settings.toggle.blockSleepSpamming", isOn: $settings.settings.blockSleepSpamming)
                        .help("settings.toggle.blockSleepSpamming.help")
                    Spacer()
                }
            }
            .padding()
        }
        .onChange(of: hasIntrospection) {_ in
            task = .introspection
            Task {
                _ = await app.changeDyldLibraryPath(set: hasIntrospection, path: PlayApp.introspection)
                task = .none
            }
        }
        .onChange(of: hasIosFrameworks) {_ in
            task = .iosFrameworks
            Task {
                _ = await app.changeDyldLibraryPath(set: hasIosFrameworks, path: PlayApp.iosFrameworks)
                task = .none
            }
        }
    }
}

struct MiscView: View {
    @Binding var settings: AppSettings
    @Binding var closeView: Bool
    @Binding var hasPlayTools: Bool?
    @Binding var hasAlias: Bool?
    @Binding var task: BlockingTask
    @AppStorage("settings.settings.discordActivity.enable") private var discordActivity = false
    @AppStorage("settings.settings.metalHUD") private var metalHUD = true
    @AppStorage("settings.openWithLLDB") private var openWithLLDB = false
    @AppStorage("settings.openLLDBWithTerminal") private var openLLDBWithTerminal = false
    @State var showPopover = false
    var app: PlayApp
    @State var applicationCategoryType: LSApplicationCategoryType
    var body: some View {
        ScrollView {
            VStack {
                HStack {
                    Text("settings.applicationCategoryType")
                    Spacer()
                    if task == .applicationCategoryType {
                        ProgressView()
                            .scaleEffect(0.5)
                            .frame(width: 16, height: 16)
                    }
                    Picker("", selection: $applicationCategoryType) {
                        ForEach(LSApplicationCategoryType.allCases, id: \.rawValue) { value in
                            Text(value.localizedName)
                                .tag(value)
                        }
                    }
                    .frame(width: 225)
                    .onChange(of: applicationCategoryType) { _ in
                        task = .applicationCategoryType
                        app.info.applicationCategoryType = applicationCategoryType
                        Task.detached {
                            do {
                                try await Shell.signApp(app.executable)

                                Task { @MainActor in
                                    task = .none
                                }
                            } catch {
                                Log.shared.error(error)
                            }
                        }
                    }
                }
                Spacer()
                    .frame(height: 20)
                HStack {
                    Toggle("settings.toggle.discord", isOn: $settings.settings.discordActivity.enable)
                    Spacer()
                    Button("settings.button.discord") { showPopover = true }
                        .popover(isPresented: $showPopover, arrowEdge: .bottom) {
                            VStack {
                                HStack {
                                    Text("settings.text.applicationID")
                                        .frame(width: 90)
                                    TextField("", text: $settings.settings.discordActivity.applicationID)
                                        .frame(minWidth: 200, maxWidth: 200)
                                }.padding([.horizontal, .top])
                                HStack {
                                    Text("settings.text.details")
                                        .frame(width: 90)
                                        .help("settings.text.details.help")
                                    TextField("", text: $settings.settings.discordActivity.details)
                                        .frame(minWidth: 200, maxWidth: 200)
                                }.padding(.horizontal)
                                HStack {
                                    Text("settings.text.state")
                                        .frame(width: 90)
                                        .help("settings.text.state.help")
                                    TextField("", text: $settings.settings.discordActivity.state)
                                        .frame(minWidth: 200, maxWidth: 200)
                                }.padding(.horizontal)
                                HStack {
                                    Text("settings.text.image")
                                        .help("settings.text.image.help")
                                        .frame(width: 90)
                                    TextField("", text: $settings.settings.discordActivity.image)
                                        .frame(minWidth: 200, maxWidth: 200)
                                }.padding(.horizontal)
                                HStack {
                                    Button("settings.button.clearActivity") {
                                        settings.settings.discordActivity = DiscordActivity()
                                        showPopover = false
                                    }
                                    Button("button.OK") { showPopover = false }
                                }.padding(.bottom)
                            }
                        }
                }.disabled(!(hasPlayTools ?? true))
                Spacer()
                    .frame(height: 20)
                HStack {
                    HStack {
                        Toggle("settings.toggle.hud", isOn: $settings.settings.metalHUD)
                            .disabled(!isVenturaGreater())
                            .help(
                                !isVenturaGreater()
                                    ? "settings.unavailable.hud"
                                    : "Starts Metal HUD in detailed avg/min/max mode and keeps its menu bar available."
                            )
                        Spacer()
                        HStack {
                            Text("settings.text.debugger")
                            VStack(alignment: .leading) {
                                HStack {
                                    Toggle("", isOn: $settings.openWithLLDB)
                                        .labelsHidden()
                                    Text("settings.toggle.lldb")
                                }

                                HStack {
                                    Toggle("", isOn: $settings.openLLDBWithTerminal)
                                        .labelsHidden()
                                        .disabled(!settings.openWithLLDB)
                                    Text("settings.toggle.lldbWithTerminal")
                                }
                            }
                        }
                    }
                }
                Spacer()
                    .frame(height: 20)
                HStack {
                    Button {
                        task = .playTools
                        Task(priority: .userInitiated) {
                            if hasPlayTools ?? true {
                                await PlayTools.removeFromApp(app.executable)
                            } else {
                                do {
                                    try await PlayTools.installInIPA(app.executable)
                                } catch {
                                    Log.shared.error(error)
                                }
                            }

                            Task { @MainActor in
                                AppsVM.shared.filteredApps = []
                                AppsVM.shared.fetchApps()
                            }

                            task = .none
                            closeView.toggle()
                        }
                    } label: {
                        Text((hasPlayTools ?? true) ? "settings.removePlayTools" : "alert.install.injectPlayTools")
                            .opacity(task == .playTools ? 0 : 1)
                            .overlay {
                                if task == .playTools {
                                    ProgressView().scaleEffect(0.5)
                                }
                            }
                    }
                    Spacer()
                }
                Spacer()
                    .frame(height: 20)
                HStack {
                    Toggle("settings.toggle.rootWorkDir", isOn: $settings.settings.rootWorkDir)
                        .disabled(!(hasPlayTools ?? true))
                        .help("settings.toggle.rootWorkDir.help")
                    Spacer()
                }
                Spacer()
                    .frame(height: 20)
                HStack {
                    Toggle("settings.toggle.limitMotionUpdateFrequency",
                           isOn: $settings.settings.limitMotionUpdateFrequency)
                        .disabled(!(hasPlayTools ?? true))
                        .help("settings.toggle.limitMotionUpdateFrequency.help")
                    Spacer()
                }
                Spacer()
                    .frame(height: 20)
                HStack {
                    Toggle("settings.toggle.ignoreUnityKeyboardInitializationError",
                           isOn: $settings.settings.ignoreUnityKeyboardInitializationError)
                        .disabled(!(hasPlayTools ?? true))
                        .help("settings.toggle.ignoreUnityKeyboardInitializationError.help")
                    Spacer()
                }
            }
            .padding()
        }
    }

    func isVenturaGreater() -> Bool {
        if #available(macOS 13.0, *) {
            return true
        } else {
            return false
        }
    }
}

struct InfoView: View {
    @State var info: AppInfo
    @State var hasPlayTools: Bool

    var body: some View {
        List {
            HStack {
                Text("settings.info.displayName")
                Spacer()
                Text("\(info.displayName)")
            }
            HStack {
                Text("settings.info.bundleName")
                Spacer()
                Text("\(info.bundleName)")
            }
            HStack {
                Text("settings.info.bundleIdentifier")
                Spacer()
                Text("\(info.bundleIdentifier)")
            }
            HStack {
                Text("settings.info.bundleVersion")
                Spacer()
                Text("\(info.bundleVersion)")
            }
            HStack {
                Text("settings.applicationCategoryType") + Text(":")
                Spacer()
                Text("\(info.applicationCategoryType.rawValue)")
            }
            HStack {
                Text("settings.info.executableName")
                Spacer()
                Text("\(info.executableName)")
            }
            HStack {
                Text("settings.info.minimumOSVersion")
                Spacer()
                Text("\(info.minimumOSVersion)")
            }
            HStack {
                Text("settings.info.playTools")
                Spacer()
                Text(hasPlayTools ? "button.Yes" : "button.No")
            }
            HStack {
                Text("settings.info.url")
                Spacer()
                Text("\(info.url.relativePath)")
            }
            HStack {
                Text("settings.info.alias")
                Spacer()
                Text("\(PlayApp.aliasDirectory.appendingPathComponent(info.bundleIdentifier))")
            }
        }
        .listStyle(.bordered(alternatesRowBackgrounds: true))
        .padding()
    }
}

struct AsyncToggleStyle: ToggleStyle {
    @Binding var task: BlockingTask

    var role: BlockingTask

    func makeBody(configuration: Configuration) -> some View {
        if task == role {
            return AnyView(
                HStack(spacing: 3) {
                    ProgressView()
                        .scaleEffect(0.5)
                        .frame(width: 16, height: 16)

                    configuration.label
                }
            )
        } else {
            return AnyView(
                Toggle(isOn: configuration.$isOn) { configuration.label }
            )
        }
    }
}

extension ToggleStyle where Self == AsyncToggleStyle {
    static func async(_ task: Binding<BlockingTask>, role: BlockingTask) -> AsyncToggleStyle {
        AsyncToggleStyle(task: task, role: role)
    }
}
