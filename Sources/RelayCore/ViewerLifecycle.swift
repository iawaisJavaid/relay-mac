import Foundation

/// Readiness evidence is scoped to one viewer process, including across restarts
/// of the same phone. A slow start can produce a hint, never a failure verdict.
public struct ViewerLifecycle: Sendable {
    public enum Phase: String, Sendable {
        case starting = "Connecting", running = "Mirroring", stopping = "Stopping", ended = "Ended"
    }

    public let instanceID: String
    public private(set) var phase: Phase = .starting
    public private(set) var startupHint: String?
    private var logTail = ""

    public init(instanceID: String = UUID().uuidString) { self.instanceID = instanceID }

    @discardableResult
    public mutating func viewerOpened(instanceID: String) -> Bool {
        guard instanceID == self.instanceID, phase == .starting else { return false }
        phase = .running; startupHint = nil
        return true
    }

    @discardableResult
    public mutating func receiveLog(_ chunk: String) -> Bool {
        guard phase == .starting else { return false }
        logTail = String((logTail + chunk).suffix(4096))
        guard logTail.contains("Renderer:") || logTail.contains("Texture:") else { return false }
        return viewerOpened(instanceID: instanceID)
    }

    @discardableResult
    public mutating func noteSlowStart(elapsed: TimeInterval) -> Bool {
        guard phase == .starting, elapsed >= 25, startupHint == nil else { return false }
        startupHint = "Waiting for the phone. Check for a permission prompt on its screen, or stop and retry."
        return true
    }

    public mutating func stop() { phase = .stopping; startupHint = nil }
    public mutating func finish() { phase = .ended; startupHint = nil }

    public static func hasAudioPlaybackFailure(in log: String) -> Bool {
        log.split(whereSeparator: \.isNewline).contains { line in
            // scrcpy reports Mac output failures from its client audio player.
            // The subsequent demuxer error alone also occurs for unrelated failures.
            line.hasPrefix("ERROR: Could not open audio device:") ||
            line.hasPrefix("ERROR: Could not resume audio device:") ||
            line.hasPrefix("ERROR: Could not initialize SDL audio:")
        }
    }
}
