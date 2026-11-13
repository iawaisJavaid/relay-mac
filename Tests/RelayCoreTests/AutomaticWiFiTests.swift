import XCTest
@testable import RelayCore

@MainActor
private final class WiFiPhoneStub {
    var calls: [[String]] = []
    var addresses = "3: wlan0 inet 192.168.1.25/24 brd 192.168.1.255 scope global wlan0"
    var routes = "default via 192.168.1.1 dev wlan0 proto dhcp src 192.168.1.25"
    var tlsPort = "-1"
    var tcpPort = "-1"
    var remoteIdentity = "PHONE-123"
    var failuresBeforeConnect = 0
    var neverConnect = false
    var stoppedSessions = 0

    func run(_ arguments: [String], _ timeout: TimeInterval) async throws -> String {
        calls.append(arguments)
        if arguments == ["-s", "USB", "shell", "ip", "-o", "-4", "addr", "show"] { return addresses }
        if arguments == ["-s", "USB", "shell", "ip", "route"] { return routes }
        if arguments == ["-s", "USB", "shell", "getprop", "ro.serialno"] { return "PHONE-123\n" }
        if arguments.last == "service.adb.tls.port" { return tlsPort }
        if arguments.last == "service.adb.tcp.port" { return tcpPort }
        if arguments.first == "connect" {
            if neverConnect { return "failed to connect" }
            if failuresBeforeConnect > 0 { failuresBeforeConnect -= 1; return "failed to connect" }
            return "connected to \(arguments[1])"
        }
        if arguments.last == "get-state" { return "device\n" }
        if arguments.last == "ro.serialno" { return remoteIdentity }
        return "OK"
    }

    var connector: AutomaticWiFiConnector { AutomaticWiFiConnector(run: run, pause: {}) }
}

@MainActor
final class AutomaticWiFiTests: XCTestCase {
    private let phone = AndroidDevice(id: "USB", state: "device", model: "Pixel_9")

    func testAutomaticUSBFlowDiscoversAddressEnablesListenerAndVerifiesIdentity() async throws {
        let stub = WiFiPhoneStub()
        var progress: [String] = []
        let result = try await stub.connector.connect(phone, progress: { progress.append($0) }, beforeRestart: { stub.stoppedSessions += 1 })
        XCTAssertEqual(result.device.id, "192.168.1.25:5555")
        XCTAssertTrue(result.restoreUSB)
        XCTAssertEqual(result.usbID, "USB")
        XCTAssertEqual(stub.stoppedSessions, 1)
        XCTAssertTrue(stub.calls.contains(["-s", "USB", "tcpip", "5555"]))
        XCTAssertTrue(stub.calls.contains(["-s", result.device.id, "shell", "getprop", "ro.serialno"]))
        XCTAssertEqual(progress.count, 3)
        XCTAssertFalse(stub.calls.contains { $0.first == "pair" })
    }

    func testAlreadyPairedTLSIsPreferredWithoutChangingPhoneDebuggingMode() async throws {
        let stub = WiFiPhoneStub(); stub.tlsPort = "37123"
        let result = try await stub.connector.connect(phone, progress: { _ in }, beforeRestart: { XCTFail("TLS must not restart adbd") })
        XCTAssertEqual(result.device.id, "192.168.1.25:37123")
        XCTAssertFalse(result.restoreUSB)
        XCTAssertFalse(stub.calls.contains { $0.contains("tcpip") })
    }

    func testExistingLegacyListenerIsReusedWithoutTakingOwnership() async throws {
        let stub = WiFiPhoneStub(); stub.tcpPort = "5566"
        let result = try await stub.connector.connect(phone, progress: { _ in }, beforeRestart: { XCTFail("Existing mode must not be restarted") })
        XCTAssertEqual(result.device.id, "192.168.1.25:5566")
        XCTAssertFalse(result.restoreUSB)
        XCTAssertFalse(stub.calls.contains { $0.contains("tcpip") })
    }

    func testRetriesWhilePhoneNetworkServiceRestarts() async throws {
        let stub = WiFiPhoneStub(); stub.failuresBeforeConnect = 2
        _ = try await stub.connector.connect(phone, progress: { _ in }, beforeRestart: {})
        XCTAssertEqual(stub.calls.filter { $0.first == "connect" }.count, 3)
    }

    func testFailedConnectionRestoresOriginalUSBTransport() async {
        let stub = WiFiPhoneStub(); stub.neverConnect = true
        do {
            _ = try await stub.connector.connect(phone, progress: { _ in }, beforeRestart: {})
            XCTFail("Expected failure")
        } catch {
            XCTAssertTrue(stub.calls.contains(["-s", "USB", "usb"]))
            XCTAssertTrue(stub.calls.contains(["disconnect", "192.168.1.25:5555"]))
            XCTAssertFalse(stub.calls.contains(["-s", "192.168.1.25:5555", "usb"]))
        }
    }

    func testWrongPhoneIdentityIsRejectedAndNeverControlled() async {
        let stub = WiFiPhoneStub(); stub.remoteIdentity = "A-DIFFERENT-PHONE"
        do {
            _ = try await stub.connector.connect(phone, progress: { _ in }, beforeRestart: {})
            XCTFail("Expected identity mismatch")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("different phone"))
            XCTAssertTrue(stub.calls.contains(["-s", "USB", "usb"]))
            XCTAssertFalse(stub.calls.contains(["-s", "192.168.1.25:5555", "usb"]))
        }
    }

    func testWrongTLSIdentityNeverFallsBackToEnablingLegacyDebugging() async {
        let stub = WiFiPhoneStub(); stub.tlsPort = "37123"; stub.remoteIdentity = "OTHER-PHONE"
        do {
            _ = try await stub.connector.connect(phone, progress: { _ in }, beforeRestart: { XCTFail("Do not interrupt the original mirror") })
            XCTFail("Expected TLS identity mismatch")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("different phone"))
            XCTAssertFalse(stub.calls.contains { $0.contains("tcpip") })
        }
    }

    func testRecordingStopFailureDoesNotChangeOrDisconnectAnyDevice() async {
        let stub = WiFiPhoneStub()
        do {
            _ = try await stub.connector.connect(phone, progress: { _ in }, beforeRestart: { throw CommandError.failed("Recording is still closing") })
            XCTFail("Expected stop failure")
        } catch {
            XCTAssertFalse(stub.calls.contains { $0.contains("tcpip") || $0.first == "disconnect" })
        }
    }

    func testNoWifiFailsBeforeChangingDebuggingOrStoppingRecording() async {
        let stub = WiFiPhoneStub(); stub.addresses = "2: rmnet0 inet 10.0.0.2/24"; stub.routes = "default via 10.0.0.1 dev tun0 src 10.0.0.2"
        do {
            _ = try await stub.connector.connect(phone, progress: { _ in }, beforeRestart: { XCTFail("Must preserve the USB recording") })
            XCTFail("Expected no Wi-Fi address")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("Wi-Fi address"))
            XCTAssertFalse(stub.calls.contains { $0.contains("tcpip") })
        }
    }

    func testRouteFallbackHandlesOlderAndroidIPTools() async throws {
        let stub = WiFiPhoneStub(); stub.addresses = ""; stub.routes = "192.168.1.0/24 dev wlan0 proto kernel scope link src 192.168.1.25"
        let result = try await stub.connector.connect(phone, progress: { _ in }, beforeRestart: {})
        XCTAssertEqual(result.device.id, "192.168.1.25:5555")
    }

    func testNeverSelectsCellularVPNLoopbackOrInvalidIPv4() {
        let text = "2: rmnet0 inet 10.1.2.3/24\n4: tun0 inet 10.5.6.7/24\n1: lo inet 127.0.0.1/8\n3: wlan0 inet 999.0.0.1/24"
        XCTAssertNil(AutomaticWiFiConnector.wifiAddress(in: text))
        XCTAssertEqual(AutomaticWiFiConnector.wifiAddress(in: text + "\n6: wlan1@if2 inet 192.168.3.12/24"), "192.168.3.12")
    }

    func testUnauthorizedPhoneCannotEnableWirelessDebugging() async {
        let stub = WiFiPhoneStub()
        do {
            _ = try await stub.connector.connect(AndroidDevice(id: "USB", state: "unauthorized", model: "Phone"), progress: { _ in }, beforeRestart: {})
            XCTFail("Expected unauthorized failure")
        } catch { XCTAssertTrue(stub.calls.isEmpty) }
    }
}

final class ViewerSettingsTests: XCTestCase {
    func testSettingsProduceExactSupportedRuntimeOptions() {
        let base = MirrorOptions()
        let changed = base.applyingToolbarConfiguration(["bitrate": "32", "resolution": "2560", "fps": "90", "decoder": "videotoolbox", "baseline": "1", "international": "1", "audio": "0"])
        let args = changed.arguments(for: AndroidDevice(id: "USB", state: "device", model: "Phone"))
        for value in ["--video-bit-rate=32M", "--max-size=2560", "--max-fps=90", "--hwdec=videotoolbox", "--video-codec-options=profile=1", "--keyboard=uhid", "--no-audio"] { XCTAssertTrue(args.contains(value), value) }
        XCTAssertEqual(changed.toolbarConfiguration["bitrate"], "32")
    }

    func testUntrustedSettingsCannotInjectArgumentsOrUnsupportedValues() {
        let base = MirrorOptions()
        let changed = base.applyingToolbarConfiguration(["bitrate": "999999", "resolution": "-1", "fps": "0", "decoder": "auto --no-control", "audio": "yes", "baseline": "true"])
        XCTAssertEqual(changed, base)
    }

    func testNativeResolutionAndSoftwareDecode() {
        let changed = MirrorOptions().applyingToolbarConfiguration(["resolution": "0", "decoder": "disabled"])
        let args = changed.arguments(for: AndroidDevice(id: "USB", state: "device", model: "Phone"))
        XCTAssertFalse(args.contains { $0.hasPrefix("--max-size") })
        XCTAssertTrue(args.contains("--hwdec=disabled"))
    }

    func testReadOnlyIgnoresInteractiveKeyboardAndMP4UsesAAC() {
        let options = MirrorOptions(readOnly: true, internationalKeyboard: true)
        let args = options.arguments(for: AndroidDevice(id: "USB", state: "device", model: "Phone"), recording: URL(fileURLWithPath: "/tmp/session.mp4"))
        XCTAssertFalse(args.contains("--keyboard=uhid"))
        XCTAssertTrue(args.contains("--no-control"))
        XCTAssertTrue(args.contains("--audio-codec=aac"))
    }
}
