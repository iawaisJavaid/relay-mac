import Foundation

public struct WiFiConnection: Equatable, Sendable {
    public let device: AndroidDevice
    public let usbID: String
    public let restoreUSB: Bool
}

private enum AutomaticWiFiError: LocalizedError {
    case identityMismatch
    var errorDescription: String? { "The wireless address belongs to a different phone. The connection was closed." }
}

@MainActor
public struct AutomaticWiFiConnector {
    public typealias Command = ([String], TimeInterval) async throws -> String
    private let run: Command
    private let pause: () async throws -> Void

    public init(run: @escaping Command, pause: @escaping () async throws -> Void = { try await Task.sleep(for: .milliseconds(650)) }) {
        self.run = run; self.pause = pause
    }

    /// Read only Wi-Fi interface addresses: never choose cellular, VPN, loopback,
    /// or an emulator address just because it happens to be the first IPv4.
    public static func wifiAddress(in output: String) -> String? {
        for line in output.split(whereSeparator: \.isNewline) {
            let fields = line.split(whereSeparator: \.isWhitespace).map(String.init)
            let wifi = fields.contains { value in
                let name = value.split(separator: "@")[0].trimmingCharacters(in: CharacterSet(charactersIn: ":"))
                return name.range(of: "^(wlan|wifi)[0-9]+$", options: .regularExpression) != nil
            }
            guard wifi else { continue }
            for keyword in ["inet", "src"] {
                guard let index = fields.firstIndex(of: keyword), index + 1 < fields.count else { continue }
                let address = String(fields[index + 1].split(separator: "/")[0])
                guard WirelessAddress.validated(address + ":5555") != nil,
                      let first = address.split(separator: ".").first.flatMap({ Int($0) }),
                      (1..<224).contains(first), first != 127, !address.hasPrefix("169.254.") else { continue }
                return address
            }
        }
        return nil
    }

    public func connect(_ device: AndroidDevice, progress: (String) -> Void,
                        beforeRestart: () async throws -> Void) async throws -> WiFiConnection {
        guard device.isReady, !device.isWireless, !device.id.hasPrefix("emulator-") else {
            throw CommandError.failed("Connect and authorize a physical Android phone over USB first.")
        }
        progress("Finding \(device.name) on Wi-Fi…")
        var addresses = (try? await run(["-s", device.id, "shell", "ip", "-o", "-4", "addr", "show"], 6)) ?? ""
        if Self.wifiAddress(in: addresses) == nil {
            addresses = try await run(["-s", device.id, "shell", "ip", "route"], 6)
        }
        guard let ip = Self.wifiAddress(in: addresses) else {
            throw CommandError.failed("Connect \(device.name) and your Mac to the same Wi-Fi network, then try again. No Wi-Fi address was found on the phone.")
        }
        let identity = try await run(["-s", device.id, "shell", "getprop", "ro.serialno"], 6).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !identity.isEmpty else { throw CommandError.failed("Couldn’t verify the phone’s identity. Reconnect USB and try again.") }

        // Prefer an already enabled, paired TLS endpoint, without requesting codes.
        let tls = (try? await run(["-s", device.id, "shell", "getprop", "service.adb.tls.port"], 6)) ?? ""
        if let port = Int(tls.trimmingCharacters(in: .whitespacesAndNewlines)), (1...65535).contains(port) {
            let endpoint = "\(ip):\(port)"
            if try await establish(endpoint, identity: identity, attempts: 1) {
                return WiFiConnection(device: AndroidDevice(id: endpoint, state: "device", model: device.model, product: device.product), usbID: device.id, restoreUSB: false)
            }
            _ = try? await run(["disconnect", endpoint], 4)
        }
        let configured = (try? await run(["-s", device.id, "shell", "getprop", "service.adb.tcp.port"], 6)) ?? ""
        let existingPort = Int(configured.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
        let port = (1...65535).contains(existingPort) ? existingPort : 5555
        let endpoint = "\(ip):\(port)"
        let needsListener = !(1...65535).contains(existingPort)
        var listenerChanged = false
        var connectionAttempted = false
        do {
            if needsListener {
                try await beforeRestart()
                progress("Preparing \(device.name) for wireless mirroring…")
                listenerChanged = true
                _ = try await run(["-s", device.id, "tcpip", String(port)], 10)
            }
            progress("Connecting and verifying \(device.name)…")
            connectionAttempted = true
            guard try await establish(endpoint, identity: identity, attempts: 4) else {
                throw CommandError.failed("Couldn’t reach \(device.name) over Wi-Fi. Keep USB attached and check that both devices use the same network.")
            }
            return WiFiConnection(device: AndroidDevice(id: endpoint, state: "device", model: device.model, product: device.product), usbID: device.id, restoreUSB: needsListener)
        } catch {
            // Only change the original USB phone on a failed/unverified connection.
            if listenerChanged {
                _ = try? await run(["-s", device.id, "wait-for-device"], 4)
                _ = try? await run(["-s", device.id, "usb"], 4)
            }
            if connectionAttempted { _ = try? await run(["disconnect", endpoint], 4) }
            throw error
        }
    }

    private func establish(_ endpoint: String, identity: String, attempts: Int) async throws -> Bool {
        for attempt in 0..<attempts {
            if attempt > 0 { try await pause() }
            do {
                let response = try await run(["connect", endpoint], 4)
                guard response.contains("connected to"), !response.contains("failed") else { continue }
                let state = try await run(["-s", endpoint, "get-state"], 4).trimmingCharacters(in: .whitespacesAndNewlines)
                guard state == "device" else { continue }
                let found = try await run(["-s", endpoint, "shell", "getprop", "ro.serialno"], 4).trimmingCharacters(in: .whitespacesAndNewlines)
                guard found == identity else {
                    _ = try? await run(["disconnect", endpoint], 4)
                    throw AutomaticWiFiError.identityMismatch
                }
                return true
            } catch let error as AutomaticWiFiError {
                throw error
            } catch { continue }
        }
        return false
    }
}
