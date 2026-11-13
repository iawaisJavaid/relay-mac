import Foundation

public struct CommandResult: Sendable {
    public let status: Int32
    public let output: String
    public var succeeded: Bool { status == 0 }
}

public enum CommandError: LocalizedError {
    case timedOut
    case failed(String)
    public var errorDescription: String? {
        switch self {
        case .timedOut: return "The device took too long to respond. Check the connection and try again."
        case .failed(let message): return message
        }
    }
}

public enum ProcessRunner {
    public static func run(_ executable: URL, _ arguments: [String], environment: [String: String]? = nil,
                           timeout: TimeInterval = 15, input: String? = nil, binaryOutput: URL? = nil) async throws -> CommandResult {
        // Foundation Process uses the launching thread's run loop. Keep launch,
        // polling, and waitUntilExit on one dedicated worker instead of letting
        // Swift concurrency resume them on different cooperative threads.
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                do { continuation.resume(returning: try execute(executable, arguments, environment: environment, timeout: timeout, input: input, binaryOutput: binaryOutput)) }
                catch { continuation.resume(throwing: error) }
            }
        }
    }

    private static func execute(_ executable: URL, _ arguments: [String], environment: [String: String]?,
                                timeout: TimeInterval, input: String?, binaryOutput: URL?) throws -> CommandResult {
            let process = Process()
            process.executableURL = executable
            process.arguments = arguments
            if let environment { process.environment = environment }
            // Files avoid pipe deadlock when adb emits more than a pipe buffer.
            let temporary = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            FileManager.default.createFile(atPath: temporary.path, contents: nil)
            let output = try FileHandle(forWritingTo: temporary)
            defer { try? output.close(); try? FileManager.default.removeItem(at: temporary) }
            var binaryHandle: FileHandle?
            if let binaryOutput {
                FileManager.default.createFile(atPath: binaryOutput.path, contents: nil)
                binaryHandle = try FileHandle(forWritingTo: binaryOutput)
            }
            defer { try? binaryHandle?.close() }
            process.standardOutput = binaryHandle ?? output
            process.standardError = output
            if let input {
                let pipe = Pipe()
                process.standardInput = pipe
                try process.run()
                try pipe.fileHandleForWriting.write(contentsOf: Data(input.utf8))
                try pipe.fileHandleForWriting.close()
            } else {
                process.standardInput = FileHandle.nullDevice
                try process.run()
            }
            let deadline = Date().addingTimeInterval(timeout)
            var timedOut = false
            while process.isRunning {
                if Date() > deadline {
                    timedOut = true
                    process.terminate()
                    break
                }
                Thread.sleep(forTimeInterval: 0.04)
            }
            if timedOut {
                Thread.sleep(forTimeInterval: 0.15)
                if process.isRunning { kill(process.processIdentifier, SIGKILL) }
            }
            process.waitUntilExit()
            if timedOut { throw CommandError.timedOut }
            let data = try Data(contentsOf: temporary)
            return CommandResult(status: process.terminationStatus, output: String(decoding: data, as: UTF8.self))
    }
}

public struct EnginePaths: Sendable {
    public let adb: URL?
    public let scrcpy: URL?
    public let toolbarLibrary: URL?
    public var isReady: Bool { adb != nil && scrcpy != nil }

    public init(bundleURL: URL = Bundle.main.bundleURL, projectURL: URL? = nil) {
        let fm = FileManager.default
        var roots = [bundleURL.appendingPathComponent("Contents/Resources/runtime")]
        if let projectURL { roots.append(projectURL.appendingPathComponent(".runtime/bin")) }
        roots += [URL(fileURLWithPath: "/opt/homebrew/bin"), URL(fileURLWithPath: "/usr/local/bin"),
                  fm.homeDirectoryForCurrentUser.appendingPathComponent("Library/Android/sdk/platform-tools")]
        func find(_ name: String) -> URL? {
            roots.map { $0.appendingPathComponent(name) }.first { fm.isExecutableFile(atPath: $0.path) }
        }
        adb = find("adb")
        scrcpy = find("scrcpy")
        var libraries = [bundleURL.appendingPathComponent("Contents/Resources/runtime/libRelayToolbar.dylib")]
        if let projectURL { libraries.append(projectURL.appendingPathComponent(".build/libRelayToolbar.dylib")) }
        toolbarLibrary = libraries.first { fm.fileExists(atPath: $0.path) }
    }

    public var environment: [String: String] {
        var env = ProcessInfo.processInfo.environment
        let directories = [adb?.deletingLastPathComponent().path, scrcpy?.deletingLastPathComponent().path].compactMap { $0 }
        env["PATH"] = (directories + ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin", "/usr/sbin", "/sbin"]).joined(separator: ":")
        if let adb { env["ADB"] = adb.path }
        if let scrcpy {
            let server = scrcpy.deletingLastPathComponent().appendingPathComponent("scrcpy-server")
            if FileManager.default.fileExists(atPath: server.path) { env["SCRCPY_SERVER_PATH"] = server.path }
        }
        return env
    }
}
