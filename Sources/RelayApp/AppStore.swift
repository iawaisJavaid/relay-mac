import AppKit
import Combine
import CoreGraphics
import RelayCore

enum Page: String, CaseIterable, Identifiable {
    case devices = "Devices", captures = "Captures", activity = "Activity", settings = "Settings"
    var id: String { rawValue }
    var symbol: String {
        switch self { case .devices: "rectangle.on.rectangle"; case .captures: "photo.on.rectangle.angled"; case .activity: "waveform.path"; case .settings: "slider.horizontal.3" }
    }
}

struct ActivityItem: Identifiable {
    let id = UUID()
    let date = Date()
    let message: String
    let isError: Bool
}

struct CaptureItem: Identifiable {
    let url: URL
    let date: Date
    var id: String { url.path }
    var isVideo: Bool { ["mp4", "mkv", "mov"].contains(url.pathExtension.lowercased()) }
}

@MainActor
final class MirrorSession: Identifiable, ObservableObject {
    let id: String
    let device: AndroidDevice
    let process: Process
    let recording: URL?
    let options: MirrorOptions
    let suppressAudioPlayback: Bool
    let logReader: FileHandle
    let started = Date()
    @Published var lifecycle = ViewerLifecycle()
    var state: ViewerLifecycle.Phase { lifecycle.phase }
    var startupTask: Task<Void, Never>?

    init(device: AndroidDevice, process: Process, recording: URL?, options: MirrorOptions,
         suppressAudioPlayback: Bool, logReader: FileHandle) {
        self.id = device.id; self.device = device; self.process = process; self.recording = recording
        self.options = options
        self.suppressAudioPlayback = suppressAudioPlayback
        self.logReader = logReader
    }

    func recentLog() -> String {
        guard let end = try? logReader.seekToEnd() else { return "" }
        let start = end > 48_000 ? end - 48_000 : 0
        guard (try? logReader.seek(toOffset: start)) != nil,
              let data = try? logReader.read(upToCount: Int(end - start)) else { return "" }
        return String(decoding: data, as: UTF8.self)
    }

    func markViewerOpened() {
        guard process.isRunning else { return }
        if lifecycle.viewerOpened(instanceID: lifecycle.instanceID) { startupTask?.cancel() }
    }

    var hasViewerWindow: Bool {
        guard process.isRunning,
              let windows = CGWindowListCopyWindowInfo(.optionAll, kCGNullWindowID) as? [[String: Any]] else { return false }
        return windows.contains { window in
            guard let pid = window[kCGWindowOwnerPID as String] as? NSNumber,
                  pid.int32Value == process.processIdentifier,
                  (window[kCGWindowLayer as String] as? NSNumber)?.intValue == 0,
                  let bounds = window[kCGWindowBounds as String] as? [String: Any],
                  let width = bounds["Width"] as? NSNumber, let height = bounds["Height"] as? NSNumber,
                  width.doubleValue > 100, height.doubleValue > 100 else { return false }
            // Window names may be withheld without screen-recording permission.
            // PID and bounds remain sufficient; no screen image is captured.
            if let title = window[kCGWindowName as String] as? String, !title.isEmpty {
                return title == "\(device.name) — Relay"
            }
            return true
        }
    }
}

@MainActor
final class AppStore: ObservableObject {
    @Published var page: Page = .devices
    @Published var devices: [AndroidDevice] = []
    @Published var sessions: [String: MirrorSession] = [:]
    @Published var activity: [ActivityItem] = []
    @Published var captures: [CaptureItem] = []
    @Published var scanning = false
    @Published var lastScan: Date?
    @Published var alert: String?
    @Published var showSetup = false
    @Published var showWireless = false
    @Published var wifiWorking = false
    @Published var wifiMessage = ""
    @Published var wifiFailed = false
    @Published var busyDevices: Set<String> = []
    @Published var engine: EnginePaths
    @Published var quality: VideoQuality { didSet { defaults.set(quality.rawValue, forKey: "quality") } }
    @Published var fps: Int { didSet { defaults.set(fps, forKey: "fps") } }
    @Published var audio: Bool { didSet { defaults.set(audio, forKey: "audio") } }
    @Published var stayAwake: Bool { didSet { defaults.set(stayAwake, forKey: "stayAwake") } }
    @Published var turnScreenOff: Bool { didSet { defaults.set(turnScreenOff, forKey: "turnScreenOff") } }
    @Published var alwaysOnTop: Bool { didSet { defaults.set(alwaysOnTop, forKey: "alwaysOnTop") } }
    @Published var readOnly: Bool { didSet { defaults.set(readOnly, forKey: "readOnly") } }
    private let defaults: UserDefaults
    private var scanTask: Task<Void, Never>?
    private var stopped = false
    private let controlToken = UUID().uuidString
    private var viewerObserver: NSObjectProtocol?
    private var wifiTask: Task<Void, Never>?
    private var managedWiFi: [String: String] = [:]

    var options: MirrorOptions { MirrorOptions(quality: quality, fps: fps, audio: audio, stayAwake: stayAwake,
                                              turnScreenOff: turnScreenOff, alwaysOnTop: alwaysOnTop, readOnly: readOnly) }
    var readyCount: Int { devices.filter(\.isReady).count }
    var captureDirectory: URL {
        if let path = defaults.string(forKey: "captureDirectory") { return URL(fileURLWithPath: path, isDirectory: true) }
        return FileManager.default.urls(for: .moviesDirectory, in: .userDomainMask)[0].appendingPathComponent("Relay", isDirectory: true)
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: ["quality": VideoQuality.high.rawValue, "fps": 60, "audio": true, "stayAwake": true])
        quality = VideoQuality(rawValue: defaults.string(forKey: "quality") ?? "") ?? .high
        fps = [30, 60, 90, 120].contains(defaults.integer(forKey: "fps")) ? defaults.integer(forKey: "fps") : 60
        audio = defaults.bool(forKey: "audio"); stayAwake = defaults.bool(forKey: "stayAwake")
        turnScreenOff = defaults.bool(forKey: "turnScreenOff"); alwaysOnTop = defaults.bool(forKey: "alwaysOnTop")
        readOnly = defaults.bool(forKey: "readOnly")
        engine = EnginePaths(projectURL: URL(fileURLWithPath: FileManager.default.currentDirectoryPath))
        log("Welcome to Relay. Your devices stay on your Mac.")
        loadCaptures()
        viewerObserver = DistributedNotificationCenter.default().addObserver(forName: .init("local.relay.viewer.action"), object: controlToken, queue: .main) { [weak self] note in
            guard let values = note.userInfo as? [String: String], let id = values["session"], let action = values["action"] else { return }
            Task { @MainActor in await self?.handleViewerAction(action, id: id, values: values) }
        }
    }

    func start() {
        guard scanTask == nil else { return }
        scanTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self, !self.stopped else { return }
                await self.refresh()
                try? await Task.sleep(for: .seconds(4))
            }
        }
    }

    func refresh() async {
        guard !scanning, !wifiWorking else { return }
        engine = EnginePaths(projectURL: URL(fileURLWithPath: FileManager.default.currentDirectoryPath))
        guard let adb = engine.adb else { return }
        scanning = true
        defer { scanning = false }
        do {
            let result = try await ProcessRunner.run(adb, ["devices", "-l"], environment: engine.environment)
            guard !stopped else { return }
            guard result.succeeded else { throw CommandError.failed(result.output) }
            let found = AndroidDevice.parse(result.output)
            for device in found where !devices.contains(where: { $0.id == device.id && $0.state == device.state }) {
                log("\(device.name): \(device.statusLabel)")
            }
            devices = found
            lastScan = Date()
        } catch {
            // A transient scan failure must not falsely disconnect a running session.
            let message = error.localizedDescription
            if activity.first?.message != message { log(message, error: true) }
        }
    }

    func mirror(_ device: AndroidDevice, record: Bool = false, options override: MirrorOptions? = nil,
                suppressAudioPlayback: Bool = false) {
        guard !stopped, device.isReady, sessions[device.id] == nil else { return }
        guard let scrcpy = engine.scrcpy, engine.adb != nil else {
            alert = "The Android engine is missing. Open Connection help for setup instructions."; return
        }
        var recording: URL?
        if record {
            do { recording = try newCapture(extension: "mp4", prefix: device.name) }
            catch { report(error); return }
        }
        let process = Process()
        let saved = defaults.dictionary(forKey: "viewerProfile.\(device.id)") as? [String: String] ?? [:]
        let configuration = override ?? options.applyingToolbarConfiguration(saved)
        let suppressAudioPlayback = suppressAudioPlayback && configuration.audio
        let output: (reader: FileHandle, writer: FileHandle)
        do { output = try openViewerLog() }
        catch { report(error); return }
        defer { try? output.writer.close() }
        let session = MirrorSession(device: device, process: process, recording: recording, options: configuration,
                                    suppressAudioPlayback: suppressAudioPlayback, logReader: output.reader)
        // The per-launch identifier rejects delayed signals from a closed viewer.
        process.executableURL = scrcpy
        process.arguments = configuration.arguments(for: device, recording: recording, suppressAudioPlayback: suppressAudioPlayback)
        var environment = engine.environment
        if let library = engine.toolbarLibrary {
            environment["DYLD_INSERT_LIBRARIES"] = library.path
            environment["RELAY_CONTROL_TOKEN"] = controlToken
            environment["RELAY_SESSION_ID"] = device.id
            environment["RELAY_VIEWER_INSTANCE"] = session.lifecycle.instanceID
            environment["RELAY_DEVICE_NAME"] = device.name
            environment["RELAY_WINDOW_TITLE"] = "\(device.name) — Relay"
            environment["RELAY_RECORDING"] = record ? "1" : "0"
            environment["RELAY_AUDIO_PLAYBACK_FALLBACK"] = suppressAudioPlayback ? "1" : "0"
            environment["RELAY_READ_ONLY"] = configuration.readOnly ? "1" : "0"
            if let data = try? JSONSerialization.data(withJSONObject: configuration.toolbarConfiguration) {
                environment["RELAY_VIEWER_OPTIONS"] = String(decoding: data, as: UTF8.self)
            }
        }
        process.environment = environment
        process.currentDirectoryURL = scrcpy.deletingLastPathComponent()
        process.standardOutput = output.writer; process.standardError = output.writer
        process.standardInput = FileHandle.nullDevice
        sessions[device.id] = session
        process.terminationHandler = { [weak self, weak session] process in
            Task { @MainActor in
                guard let self, let session, self.sessions[device.id] === session else { return }
                session.startupTask?.cancel()
                let requested = session.state == .stopping || self.stopped
                let output = session.recentLog()
                try? session.logReader.close()
                session.lifecycle.finish()
                self.sessions.removeValue(forKey: device.id)
                if process.terminationStatus != 0 && !requested {
                    if process.terminationReason == .exit, configuration.audio, !suppressAudioPlayback,
                       ViewerLifecycle.hasAudioPlaybackFailure(in: output) {
                        if let recording, (try? recording.resourceValues(forKeys: [.fileSizeKey]).fileSize) == 0 {
                            try? FileManager.default.removeItem(at: recording)
                        }
                        self.log("Mac audio output couldn’t start · \(device.name). Reopening without Mac playback.")
                        self.mirror(device, record: record, options: configuration, suppressAudioPlayback: true)
                        self.loadCaptures()
                        return
                    }
                    let reason = output.split(whereSeparator: \.isNewline).filter { $0.contains("ERROR") }.suffix(3).joined(separator: "\n")
                    let detail = reason.isEmpty ? "Check USB debugging and reconnect your phone. You can also try disabling audio in Settings for older Android versions." : reason
                    self.alert = "Couldn’t mirror \(device.name).\n\n\(detail)"
                    self.log("Mirroring failed for \(device.name): \(detail)", error: true)
                } else {
                    self.log("Session ended · \(device.name)")
                    if let recording, FileManager.default.fileExists(atPath: recording.path) {
                        self.log("Recording saved · \(recording.lastPathComponent)")
                        if ((try? recording.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) > 0 {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.writeObjects([recording as NSURL])
                        }
                    }
                }
                self.loadCaptures()
            }
        }
        do {
            try process.run()
            log("Starting \(record ? "recording" : "mirroring") · \(device.name)")
            session.startupTask = Task { [weak self, weak session] in
                while !Task.isCancelled {
                    do { try await Task.sleep(for: .milliseconds(500)) } catch { return }
                    guard let self, let session, !self.stopped, self.sessions[device.id] === session,
                          session.process.isRunning, session.state == .starting else { return }
                    if session.hasViewerWindow {
                        session.markViewerOpened(); self.objectWillChange.send(); return
                    }
                    if session.lifecycle.receiveLog(session.recentLog()) {
                        self.objectWillChange.send(); return
                    }
                    if session.lifecycle.noteSlowStart(elapsed: Date().timeIntervalSince(session.started)) {
                        self.log("Still opening the viewer · \(device.name). Waiting for the phone’s response.")
                        self.objectWillChange.send()
                    }
                }
            }
        } catch {
            try? output.reader.close()
            sessions.removeValue(forKey: device.id)
            report(error)
        }
    }

    private func openViewerLog() throws -> (reader: FileHandle, writer: FileHandle) {
        // Give scrcpy an unlinked log file so even errors written immediately
        // before exit are available without racing a pipe callback or waiting
        // for an ADB child that may still hold a stdout/stderr descriptor.
        let path = FileManager.default.temporaryDirectory.appendingPathComponent("Relay-viewer.XXXXXX").path
        var template = Array(path.utf8CString)
        let fd = mkstemp(&template)
        guard fd >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        let url = URL(fileURLWithPath: String(cString: template))
        let writer = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        defer { try? FileManager.default.removeItem(at: url) }
        return (try FileHandle(forReadingFrom: url), writer)
    }

    func stop(_ deviceID: String) {
        guard let session = sessions[deviceID], session.state != .stopping else { return }
        session.lifecycle.stop()
        session.startupTask?.cancel()
        objectWillChange.send()
        // SIGINT lets scrcpy finalize MP4 recordings and restore device settings.
        if session.process.isRunning { session.process.interrupt() }
        Task { [weak session] in
            try? await Task.sleep(for: .seconds(5))
            if let session, session.process.isRunning { session.process.terminate() }
        }
    }

    func adb(_ arguments: [String], input: String? = nil, timeout: TimeInterval = 15) async throws -> String {
        guard let adb = engine.adb else { throw CommandError.failed("Android engine is not installed.") }
        let result = try await ProcessRunner.run(adb, arguments, environment: engine.environment, timeout: timeout, input: input)
        guard result.succeeded else { throw CommandError.failed(result.output.trimmingCharacters(in: .whitespacesAndNewlines)) }
        return result.output
    }

    func screenshot(_ device: AndroidDevice) async {
        guard !busyDevices.contains(device.id), let adb = engine.adb else { return }
        busyDevices.insert(device.id)
        defer { busyDevices.remove(device.id) }
        do {
            let url = try newCapture(extension: "png", prefix: device.name)
            // Keep binary stdout separate from diagnostic stderr; apply the
            // same timeout and forced-exit handling used for other ADB commands.
            do {
                let result = try await ProcessRunner.run(adb, ["-s", device.id, "exec-out", "screencap", "-p"],
                                                         environment: engine.environment, timeout: 12, binaryOutput: url)
                guard result.succeeded else { throw CommandError.failed(result.output) }
                let data = try Data(contentsOf: url)
                guard data.starts(with: [137, 80, 78, 71, 13, 10, 26, 10]) else {
                    throw CommandError.failed("The phone did not return a valid screenshot. Unlock it and try again.")
                }
            } catch {
                try? FileManager.default.removeItem(at: url)
                throw error
            }
            log("Screenshot saved · \(url.lastPathComponent)")
            guard let image = NSImage(contentsOf: url) else { throw CommandError.failed("Couldn’t copy the screenshot image.") }
            NSPasteboard.general.clearContents()
            let copiedImage = NSPasteboard.general.writeObjects([image])
            let copiedPNG = NSPasteboard.general.setData(try Data(contentsOf: url), forType: .png)
            guard copiedImage || copiedPNG else { throw CommandError.failed("The screenshot was saved, but couldn’t be copied to the clipboard.") }
            NSSound(named: "Pop")?.play()
            viewerFeedback(device.id, status: "Screenshot copied", screenshot: url)
            loadCaptures()
        } catch { report(error) }
    }

    func sendFiles(_ device: AndroidDevice) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true; panel.canChooseDirectories = false; panel.allowsMultipleSelection = true
        panel.message = "Files will be copied to Download on \(device.name). APKs can be installed from the mirror window."
        panel.prompt = "Send to phone"
        guard panel.runModal() == .OK else { return }
        let files = panel.urls
        Task {
            busyDevices.insert(device.id)
            defer { busyDevices.remove(device.id) }
            do {
                for file in files {
                    _ = try await adb(["-s", device.id, "push", file.path, "/sdcard/Download/"], timeout: 300)
                }
                log("Sent \(files.count) file\(files.count == 1 ? "" : "s") to \(device.name) / Download")
            } catch { report(error) }
        }
    }

    func beginAutomaticWiFi(for requested: AndroidDevice? = nil) {
        showWireless = true
        guard !wifiWorking, !stopped else { return }
        wifiWorking = true; wifiFailed = false; wifiMessage = "Finding your connected phone…"
        wifiTask = Task { [weak self] in await self?.connectAutomatically(requested) }
    }

    private func connectAutomatically(_ requested: AndroidDevice?) async {
        defer { wifiWorking = false }
        do {
            let discovered = AndroidDevice.parse(try await adb(["devices", "-l"]))
            devices = discovered
            let usb = discovered.filter { $0.isReady && !$0.isWireless && !$0.id.hasPrefix("emulator-") && (requested == nil || $0.id == requested?.id) }.sorted { $0.id < $1.id }
            if usb.isEmpty {
                let wireless = discovered.filter { $0.isReady && $0.isWireless && (requested == nil || $0.id == requested?.id) }
                guard !wireless.isEmpty else {
                    let unauthorized = discovered.contains { $0.state == "unauthorized" }
                    throw CommandError.failed(unauthorized
                        ? "Unlock your Android phone and approve its USB debugging prompt, then retry. Android requires this first approval on the phone."
                        : "Connect your Android phone by USB once and enable USB debugging. Keep your phone and Mac on the same Wi-Fi, then retry. Relay fills in all connection details automatically.")
                }
                for device in wireless where !stopped { mirror(device) }
                wifiMessage = "Connected over Wi-Fi. Your wireless mirror is ready."
                return
            }
            var connected = 0
            var failures: [String] = []
            for device in usb {
                guard !stopped else { break }
                let previous = sessions[device.id]
                let configuration = previous?.options ?? options
                let wasRecording = previous?.recording != nil
                let connector = AutomaticWiFiConnector(run: { [self] arguments, timeout in try await adb(arguments, timeout: timeout) })
                do {
                    let connection = try await connector.connect(device, progress: { [self] in wifiMessage = $0 }, beforeRestart: { [self] in try await finishSession(device.id) })
                    if connection.restoreUSB { managedWiFi[connection.device.id] = connection.usbID }
                    try await finishSession(device.id)
                    if stopped { continue }
                    if !devices.contains(where: { $0.id == connection.device.id }) { devices.append(connection.device) }
                    mirror(connection.device, record: wasRecording, options: configuration,
                           suppressAudioPlayback: previous?.suppressAudioPlayback ?? false)
                    log("Wireless connection verified · \(device.name)")
                    connected += 1
                } catch {
                    failures.append("\(device.name): \(error.localizedDescription)")
                    log(error.localizedDescription, error: true)
                    if previous != nil, sessions[device.id] == nil, !stopped {
                        let state = try? await adb(["-s", device.id, "get-state"], timeout: 4)
                        if state?.trimmingCharacters(in: .whitespacesAndNewlines) == "device" {
                            mirror(device, record: wasRecording, options: configuration,
                                   suppressAudioPlayback: previous?.suppressAudioPlayback ?? false)
                        }
                    }
                }
            }
            wifiFailed = !failures.isEmpty
            if connected > 0 {
                wifiMessage = "\(connected == 1 ? "Your phone is" : "Your phones are") connected over Wi-Fi. You can unplug USB now."
                if !failures.isEmpty { wifiMessage += "\n\n" + failures.joined(separator: "\n") }
            } else { wifiMessage = failures.joined(separator: "\n") }
        } catch {
            wifiFailed = true; wifiMessage = error.localizedDescription
            log(error.localizedDescription, error: true)
        }
    }

    private func finishSession(_ id: String) async throws {
        guard let session = sessions[id] else { return }
        stop(id)
        let deadline = Date().addingTimeInterval(8)
        while session.process.isRunning || sessions[id] === session {
            guard Date() < deadline else { throw CommandError.failed("The current mirror is still closing. Try again after its recording finishes.") }
            try await Task.sleep(for: .milliseconds(80))
        }
    }

    private func viewerFeedback(_ id: String, status: String? = nil, busy: Bool? = nil, screenshot: URL? = nil) {
        var values = ["session": id]
        if let status { values["status"] = status }
        if let busy { values["busy"] = busy ? "1" : "0" }
        if let screenshot { values["screenshotPath"] = screenshot.path }
        DistributedNotificationCenter.default().postNotificationName(.init("local.relay.viewer.state"), object: controlToken, userInfo: values, deliverImmediately: true)
    }

    private func handleViewerAction(_ action: String, id: String, values: [String: String]) async {
        if action == "ready" {
            guard let session = sessions[id], session.state == .starting, !stopped,
                  values["instance"] == session.lifecycle.instanceID else { return }
            session.markViewerOpened(); objectWillChange.send()
            return
        }
        guard let session = sessions[id], values["instance"] == session.lifecycle.instanceID,
              session.state != .stopping, !busyDevices.contains(id), !stopped else { return }
        if action == "screenshot" { await screenshot(session.device); return }
        if action == "wireless" { beginAutomaticWiFi(for: session.device); return }
        busyDevices.insert(id); viewerFeedback(id, busy: true)
        defer { busyDevices.remove(id); viewerFeedback(id, busy: false) }
        do {
            switch action {
            case "logcat":
                let output = try await adb(["-s", id, "logcat", "-d", "-t", "2000"], timeout: 20)
                NSPasteboard.general.clearContents(); NSPasteboard.general.setString(output, forType: .string)
                viewerFeedback(id, status: "Logcat copied"); log("Device logcat copied · \(session.device.name)")
            case "record", "audio", "settings":
                var configuration = session.options
                var record = session.recording != nil
                if action == "record" { record.toggle() }
                if action == "audio" && !session.suppressAudioPlayback { configuration.audio.toggle() }
                if action == "settings" {
                    configuration = configuration.applyingToolbarConfiguration(values)
                    defaults.set(configuration.toolbarConfiguration, forKey: "viewerProfile.\(id)")
                }
                try await finishSession(id)
                guard !stopped else { return }
                mirror(session.device, record: record, options: configuration,
                       suppressAudioPlayback: action != "audio" && session.suppressAudioPlayback)
            default: break
            }
        } catch { report(error) }
    }

    func disconnect(_ device: AndroidDevice) async {
        do {
            try await finishSession(device.id)
            if managedWiFi[device.id] != nil {
                _ = try await adb(["-s", device.id, "usb"], timeout: 6)
                managedWiFi.removeValue(forKey: device.id)
                log("Restored USB-only debugging · \(device.name)")
            }
            _ = try await adb(["disconnect", device.id]); await refresh()
        }
        catch { report(error) }
    }

    func openIPhoneMirroring() {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.ScreenContinuity") else {
            alert = "Apple’s iPhone Mirroring app requires macOS 15 or later and a compatible Mac. See Connection help for the full requirements."
            return
        }
        NSWorkspace.shared.openApplication(at: url, configuration: .init()) { _, error in
            if let error { Task { @MainActor in self.report(error) } }
        }
        log("Opened Apple iPhone Mirroring")
    }

    func chooseCaptureDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false; panel.canChooseDirectories = true; panel.canCreateDirectories = true
        panel.prompt = "Choose folder"; panel.directoryURL = captureDirectory
        if panel.runModal() == .OK, let url = panel.url {
            defaults.set(url.path, forKey: "captureDirectory"); objectWillChange.send(); loadCaptures()
        }
    }

    func newCapture(extension ext: String, prefix: String) throws -> URL {
        try FileManager.default.createDirectory(at: captureDirectory, withIntermediateDirectories: true)
        let formatter = DateFormatter(); formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let safe = prefix.unicodeScalars.map { CharacterSet.alphanumerics.contains($0) ? String($0) : "-" }.joined()
        return captureDirectory.appendingPathComponent("\(safe)_\(formatter.string(from: Date()))_\(UUID().uuidString.prefix(4)).\(ext)")
    }

    func loadCaptures() {
        let urls = (try? FileManager.default.contentsOfDirectory(at: captureDirectory, includingPropertiesForKeys: [.creationDateKey, .fileSizeKey], options: .skipsHiddenFiles)) ?? []
        let activeFiles = Set(sessions.values.compactMap { $0.recording?.path })
        captures = urls.filter { ["png", "mp4", "mkv", "mov"].contains($0.pathExtension.lowercased()) && !activeFiles.contains($0.path) }.compactMap { url in
            guard let values = try? url.resourceValues(forKeys: [.creationDateKey, .fileSizeKey]), (values.fileSize ?? 0) > 0 else { return nil }
            return CaptureItem(url: url, date: values.creationDate ?? .distantPast)
        }.sorted { $0.date > $1.date }
    }

    func revealCaptures() {
        do {
            try FileManager.default.createDirectory(at: captureDirectory, withIntermediateDirectories: true)
            NSWorkspace.shared.open(captureDirectory)
        } catch { report(error) }
    }

    func log(_ message: String, error: Bool = false) {
        activity.insert(ActivityItem(message: message, isError: error), at: 0)
        if activity.count > 200 { activity.removeLast(activity.count - 200) }
    }

    func report(_ error: Error) { alert = error.localizedDescription; log(error.localizedDescription, error: true) }

    func shutdown() {
        stopped = true; scanTask?.cancel()
        for session in sessions.values {
            session.startupTask?.cancel()
            if session.process.isRunning { session.process.interrupt() }
        }
    }

    func finishShutdown() async {
        await wifiTask?.value
        for (endpoint, usbID) in managedWiFi {
            // Fall back to the original USB transport if Wi-Fi has disappeared.
            do { _ = try await adb(["-s", endpoint, "usb"], timeout: 4) }
            catch { _ = try? await adb(["-s", usbID, "usb"], timeout: 4) }
            _ = try? await adb(["disconnect", endpoint], timeout: 3)
        }
        managedWiFi.removeAll()
        if let viewerObserver { DistributedNotificationCenter.default().removeObserver(viewerObserver) }
    }
}
