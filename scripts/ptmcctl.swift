#!/usr/bin/env swift

import Foundation
import CoreFoundation
import AVFoundation
import CoreMedia

private let fm = FileManager.default
private let home = fm.homeDirectoryForCurrentUser
private let root = home.appendingPathComponent("Library/Containers/io.playcover.PlayCover", isDirectory: true)

private func statusURL(_ bundle: String) -> URL {
    root.appendingPathComponent("PTMC Status", isDirectory: true)
        .appendingPathComponent(bundle).appendingPathExtension("plist")
}

private func configURL(_ bundle: String) -> URL {
    root.appendingPathComponent("PTMC Config", isDirectory: true)
        .appendingPathComponent(bundle).appendingPathExtension("plist")
}

private func appSettingsURL(_ bundle: String) -> URL {
    root.appendingPathComponent("App Settings", isDirectory: true)
        .appendingPathComponent(bundle).appendingPathExtension("plist")
}

private func captureDirectory(_ bundle: String) -> URL {
    root.appendingPathComponent("Captures", isDirectory: true)
        .appendingPathComponent(bundle, isDirectory: true)
}

private func readPlist(_ url: URL) -> [String: Any] {
    guard let data = try? Data(contentsOf: url),
          let object = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil),
          let dictionary = object as? [String: Any] else { return [:] }
    return dictionary
}

private func writePlist(_ dictionary: [String: Any], to url: URL) throws {
    try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    let data = try PropertyListSerialization.data(fromPropertyList: dictionary, format: .binary, options: 0)
    try data.write(to: url, options: .atomic)
}

private func int(_ dictionary: [String: Any], _ key: String) -> Int64 {
    (dictionary[key] as? NSNumber)?.int64Value ?? 0
}

private func string(_ dictionary: [String: Any], _ key: String, default fallback: String = "-") -> String {
    dictionary[key] as? String ?? fallback
}

private func status(_ bundle: String, compact: Bool = false) -> [String: Any] {
    let values = readPlist(statusURL(bundle))
    if values.isEmpty {
        print("PTMC status: missing (\(statusURL(bundle).path))")
        return values
    }
    let drops = int(values, "droppedPool") + int(values, "droppedEncoder") +
        int(values, "droppedLate") + int(values, "unsupported")
    if compact {
        print(
            "phase=\(string(values, "phase")) codec=\(string(values, "codec")) " +
            "presented=\(int(values, "presented")) captured=\(int(values, "captured")) " +
            "encoded=\(int(values, "encoded")) drops=\(drops) rateSkip=\(int(values, "skippedRate"))"
        )
        return values
    }
    print("phase:        \(string(values, "phase"))")
    print("message:      \(string(values, "message"))")
    print("codec:        \(string(values, "codec"))")
    print("fps target:   \(int(values, "fps"))")
    print("drawable:     \(int(values, "drawableWidth"))x\(int(values, "drawableHeight"))")
    print("pixel format: \(int(values, "pixelFormat"))")
    print("hooks:        \(int(values, "presentHookCount"))")
    print("presented:    \(int(values, "presented"))")
    print("captured:     \(int(values, "captured"))")
    print("encoded:      \(int(values, "encoded"))")
    print("rate skipped: \(int(values, "skippedRate"))")
    print("drops:        \(drops) [pool \(int(values, "droppedPool")), encoder \(int(values, "droppedEncoder")), late \(int(values, "droppedLate")), unsupported \(int(values, "unsupported"))]")
    print("EDR:          \(int(values, "edr"))")
    print("colorspace:   \(string(values, "colorSpace"))")
    print("displaySync:  \(int(values, "displaySync"))")
    print("framebuffer:  \(int(values, "framebufferOnly"))")
    print("output:       \(string(values, "outputPath"))")
    if let timestamp = values["timestamp"] as? NSNumber {
        let date = Date(timeIntervalSince1970: timestamp.doubleValue)
        print("updated:      \(ISO8601DateFormatter().string(from: date))")
    }
    return values
}

private func post(_ command: String, bundle: String) {
    let name = CFNotificationName("io.playcover.ptmc.\(command).\(bundle)" as CFString)
    CFNotificationCenterPostNotification(
        CFNotificationCenterGetDarwinNotifyCenter(),
        name,
        nil,
        nil,
        true
    )
}

private func boolValue(_ raw: String) -> Bool? {
    switch raw.lowercased() {
    case "1", "true", "yes", "on": return true
    case "0", "false", "no", "off": return false
    default: return nil
    }
}

private func configure(_ bundle: String, options: ArraySlice<String>) throws {
    var runtime = readPlist(configURL(bundle))
    var app = readPlist(appSettingsURL(bundle))
    if options.isEmpty {
        print("runtime config: \(configURL(bundle).path)")
        for key in runtime.keys.sorted() { print("  \(key)=\(runtime[key]!)") }
        return
    }
    for option in options {
        let pair = option.split(separator: "=", maxSplits: 1).map(String.init)
        guard pair.count == 2 else { throw "config option must be key=value: \(option)" }
        let key = pair[0]
        let value = pair[1]
        switch key {
        case "fps":
            guard let number = Int(value), (1...240).contains(number) else { throw "fps must be 1...240" }
            runtime["fps"] = number
            app["metalCaptureFPS"] = number
        case "bitrate", "bitrateMbps":
            guard let number = Int(value), (1...1000).contains(number) else { throw "bitrateMbps must be 1...1000" }
            runtime["bitrate"] = number * 1_000_000
            app["metalCaptureBitrateMbps"] = number
        case "buffers":
            guard let number = Int(value), (3...16).contains(number) else { throw "buffers must be 3...16" }
            runtime["buffers"] = number
            app["metalCaptureBuffers"] = number
        case "forceSDR":
            guard let flag = boolValue(value) else { throw "forceSDR must be true/false" }
            runtime["forceSDRDisplay"] = flag
            app["metalCaptureForceSDRDisplay"] = flag
        case "disableSync":
            guard let flag = boolValue(value) else { throw "disableSync must be true/false" }
            runtime["disableDisplaySync"] = flag
            app["metalCaptureDisableDisplaySync"] = flag
        case "codec":
            let allowed = ["hevc", "prores422lt", "prores422", "prores422hq"]
            guard allowed.contains(value.lowercased()) else { throw "codec: \(allowed.joined(separator: ", "))" }
            runtime["codec"] = value.lowercased()
            app["metalCaptureCodec"] = value.lowercased()
        default:
            throw "unknown config key: \(key)"
        }
    }
    try writePlist(runtime, to: configURL(bundle))
    if !app.isEmpty { try writePlist(app, to: appSettingsURL(bundle)) }
    post("status", bundle: bundle)
    print("PTMC config updated for \(bundle)")
}

private func newestMovie(_ bundle: String) -> URL? {
    let directory = captureDirectory(bundle)
    guard let files = try? fm.contentsOfDirectory(
        at: directory,
        includingPropertiesForKeys: [.contentModificationDateKey],
        options: [.skipsHiddenFiles]
    ) else { return nil }
    return files.filter { $0.pathExtension.lowercased() == "mov" && !$0.lastPathComponent.hasSuffix(".partial.mov") }
        .max { lhs, rhs in
            let l = (try? lhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let r = (try? rhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return l < r
        }
}

private func fourCC(_ code: FourCharCode) -> String {
    let bytes: [UInt8] = [
        UInt8((code >> 24) & 0xff), UInt8((code >> 16) & 0xff),
        UInt8((code >> 8) & 0xff), UInt8(code & 0xff)
    ]
    return String(bytes: bytes, encoding: .ascii) ?? String(format: "0x%08x", code)
}

private func inspect(_ bundle: String) {
    guard let url = newestMovie(bundle) else {
        print("No finalized MOV in \(captureDirectory(bundle).path)")
        return
    }
    let asset = AVURLAsset(url: url)
    print("file:     \(url.path)")
    print("duration: \(String(format: "%.3f", CMTimeGetSeconds(asset.duration))) s")
    if let video = asset.tracks(withMediaType: .video).first {
        print("video:    \(Int(video.naturalSize.width))x\(Int(video.naturalSize.height)) @ \(String(format: "%.3f", video.nominalFrameRate)) fps")
        if let desc = video.formatDescriptions.first as? CMFormatDescription {
            print("codec:    \(fourCC(CMFormatDescriptionGetMediaSubType(desc)))")
        }
        print("bitrate:  \(Int(video.estimatedDataRate / 1_000_000)) Mbps estimated")
    }
    if let audio = asset.tracks(withMediaType: .audio).first {
        print("audio:    present, \(Int(audio.estimatedDataRate / 1000)) kbps estimated")
    } else {
        print("audio:    none")
    }
}

private func usage() -> Never {
    fputs("""
    usage: ptmcctl.swift <command> <bundle-id> [args]

      status  <bundle-id>
      start   <bundle-id>
      stop    <bundle-id>
      record  <bundle-id> [seconds]
      config  <bundle-id> [fps=120 bitrateMbps=120 buffers=6 codec=hevc forceSDR=true disableSync=false]
      inspect <bundle-id>

    `record` controls the in-game PTMC video runtime. Game-audio capture is owned by the PlayCover UI
    because ScreenCaptureKit permission and application filtering belong to the host process.
    """ + "\n", stderr)
    exit(64)
}

let args = CommandLine.arguments
if args.count < 3 { usage() }
let command = args[1]
let bundle = args[2]

do {
    switch command {
    case "status":
        _ = status(bundle)
    case "start":
        post("start", bundle: bundle)
        Thread.sleep(forTimeInterval: 0.25)
        _ = status(bundle)
    case "stop":
        post("stop", bundle: bundle)
        Thread.sleep(forTimeInterval: 0.25)
        _ = status(bundle)
    case "record":
        let seconds = args.count > 3 ? max(1, Double(args[3]) ?? 10) : 10
        post("start", bundle: bundle)
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            Thread.sleep(forTimeInterval: 1)
            _ = status(bundle, compact: true)
        }
        post("stop", bundle: bundle)
        for _ in 0..<80 {
            Thread.sleep(forTimeInterval: 0.25)
            let current = readPlist(statusURL(bundle))
            if string(current, "phase") == "finalized" || string(current, "phase") == "stopped" { break }
        }
        _ = status(bundle)
        inspect(bundle)
    case "config":
        try configure(bundle, options: args.dropFirst(3))
    case "inspect":
        inspect(bundle)
    default:
        usage()
    }
} catch {
    fputs("ptmcctl: \(error.localizedDescription)\n", stderr)
    exit(1)
}
