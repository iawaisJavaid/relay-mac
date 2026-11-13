import Foundation

public struct AndroidDevice: Identifiable, Equatable, Sendable {
    public let id: String
    public let state: String
    public let model: String
    public let product: String

    public init(id: String, state: String, model: String, product: String = "") {
        self.id = id
        self.state = state
        self.model = model
        self.product = product
    }

    public var name: String { model.replacingOccurrences(of: "_", with: " ") }
    public var isReady: Bool { state == "device" }
    public var isWireless: Bool { id.contains(":") || id.contains("._tcp") }
    public var statusLabel: String {
        switch state {
        case "device": return isWireless ? "Wi-Fi connected" : "USB connected"
        case "unauthorized": return "Allow USB debugging on your phone"
        case "offline": return "Offline · reconnect your cable"
        case "no permissions": return "Device access denied"
        default: return state
        }
    }

    public static func parse(_ output: String) -> [AndroidDevice] {
        output.split(whereSeparator: \.isNewline).compactMap { line in
            let fields = line.split(whereSeparator: \.isWhitespace).map(String.init)
            guard fields.count >= 2, !line.hasPrefix("List of devices"),
                  !line.hasPrefix("*"), !line.hasPrefix("adb:"),
                  ["device", "unauthorized", "offline", "recovery", "sideload", "bootloader", "no"].contains(fields[1]) else { return nil }
            let properties = fields.dropFirst(2).reduce(into: [String: String]()) { result, field in
                let pair = field.split(separator: ":", maxSplits: 1).map(String.init)
                if pair.count == 2 { result[pair[0]] = pair[1] }
            }
            return AndroidDevice(id: fields[0], state: fields[1] == "no" ? "no permissions" : fields[1],
                                 model: properties["model"] ?? "Android device", product: properties["product"] ?? "")
        }
    }
}

public enum VideoQuality: String, CaseIterable, Identifiable, Sendable {
    case balanced = "Balanced", high = "High quality", native = "Native resolution"
    public var id: String { rawValue }
    public var maxSize: Int { switch self { case .balanced: 1280; case .high: 1920; case .native: 0 } }
    public var bitRate: String { switch self { case .balanced: "8M"; case .high: "16M"; case .native: "24M" } }
    public var detail: String { switch self { case .balanced: "1280 px · 8 Mbps"; case .high: "1920 px · 16 Mbps"; case .native: "Full resolution · 24 Mbps" } }
}

public struct MirrorOptions: Equatable, Sendable {
    public var quality: VideoQuality
    public var fps: Int
    public var audio: Bool
    public var stayAwake: Bool
    public var turnScreenOff: Bool
    public var alwaysOnTop: Bool
    public var readOnly: Bool
    public var customBitRate: Int?
    public var customMaxSize: Int?
    public var decoder: String
    public var baseline: Bool
    public var internationalKeyboard: Bool

    public init(quality: VideoQuality = .high, fps: Int = 60, audio: Bool = true,
                stayAwake: Bool = true, turnScreenOff: Bool = false, alwaysOnTop: Bool = false, readOnly: Bool = false,
                customBitRate: Int? = nil, customMaxSize: Int? = nil, decoder: String = "auto",
                baseline: Bool = false, internationalKeyboard: Bool = false) {
        self.quality = quality; self.fps = fps; self.audio = audio
        self.stayAwake = stayAwake; self.turnScreenOff = turnScreenOff
        self.alwaysOnTop = alwaysOnTop; self.readOnly = readOnly
        self.customBitRate = customBitRate; self.customMaxSize = customMaxSize
        self.decoder = decoder; self.baseline = baseline; self.internationalKeyboard = internationalKeyboard
    }

    public func arguments(for device: AndroidDevice, recording: URL? = nil, suppressAudioPlayback: Bool = false) -> [String] {
        var args = ["--serial=\(device.id)", "--window-title=\(device.name) — Relay",
                    "--max-fps=\(fps)", "--video-bit-rate=\(customBitRate.map { "\($0)M" } ?? quality.bitRate)",
                    "--video-codec=h264", "--shortcut-mod=lsuper", "--window-width=420"]
        let size = customMaxSize ?? quality.maxSize
        if size > 0 { args.append("--max-size=\(size)") }
        if decoder != "auto" { args.append("--hwdec=\(decoder)") }
        if baseline { args.append("--video-codec-options=profile=1") }
        if internationalKeyboard && !readOnly { args.append("--keyboard=uhid") }
        if !audio { args.append("--no-audio") }
        else if suppressAudioPlayback { args.append("--no-audio-playback") }
        if stayAwake && !readOnly { args.append("--stay-awake") }
        if turnScreenOff && !readOnly { args.append("--turn-screen-off") }
        if alwaysOnTop { args.append("--always-on-top") }
        if readOnly { args.append("--no-control") }
        if let recording {
            args.append("--record=\(recording.path)")
            if audio { args.append("--audio-codec=aac") }
        }
        return args
    }

    public var toolbarConfiguration: [String: String] {
        ["bitrate": String(customBitRate ?? Int(quality.bitRate.dropLast()) ?? 16),
         "resolution": String(customMaxSize ?? quality.maxSize), "fps": String(fps), "decoder": decoder,
         "audio": audio ? "1" : "0", "baseline": baseline ? "1" : "0",
         "international": internationalKeyboard ? "1" : "0", "screenOff": turnScreenOff ? "1" : "0",
         "stayAwake": stayAwake ? "1" : "0", "alwaysOnTop": alwaysOnTop ? "1" : "0"]
    }

    /// Distributed toolbar messages are untrusted; admit only known settings.
    public func applyingToolbarConfiguration(_ values: [String: String]) -> MirrorOptions {
        var result = self
        if let bitrate = values["bitrate"].flatMap(Int.init), [2, 4, 8, 16, 24, 32, 64].contains(bitrate) { result.customBitRate = bitrate }
        if let size = values["resolution"].flatMap(Int.init), [0, 720, 1280, 1920, 2560].contains(size) { result.customMaxSize = size }
        if let fps = values["fps"].flatMap(Int.init), [30, 60, 90, 120].contains(fps) { result.fps = fps }
        if let decoder = values["decoder"], ["auto", "videotoolbox", "disabled"].contains(decoder) { result.decoder = decoder }
        for key in ["audio", "baseline", "international", "screenOff", "stayAwake", "alwaysOnTop"] {
            guard let value = values[key], ["0", "1"].contains(value) else { continue }
            switch key {
            case "audio": result.audio = value == "1"
            case "baseline": result.baseline = value == "1"
            case "international": result.internationalKeyboard = value == "1"
            case "screenOff": result.turnScreenOff = value == "1"
            case "stayAwake": result.stayAwake = value == "1"
            case "alwaysOnTop": result.alwaysOnTop = value == "1"
            default: break
            }
        }
        return result
    }
}

public enum WirelessAddress {
    /// Accept a host and port, never shell fragments, paths, or adb option strings.
    public static func validated(_ raw: String) -> String? {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = value.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2, let port = Int(parts[1]), (1...65535).contains(port),
              !parts[0].isEmpty, parts[0].count <= 253 else { return nil }
        let host = String(parts[0])
        guard host.first != "-", host.first != ".", host.last != ".",
              host.unicodeScalars.allSatisfy({ CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.-").contains($0) }) else { return nil }
        // Reject malformed dotted numeric IPv4 addresses rather than letting adb guess.
        if host.allSatisfy({ $0.isNumber || $0 == "." }) {
            let octets = host.split(separator: ".", omittingEmptySubsequences: false)
            guard octets.count == 4, octets.allSatisfy({ Int($0).map { (0...255).contains($0) } ?? false }) else { return nil }
        }
        return "\(host):\(port)"
    }

    public static func validPairingCode(_ raw: String) -> Bool {
        raw.count == 6 && raw.utf8.allSatisfy { (48...57).contains($0) }
    }
}
