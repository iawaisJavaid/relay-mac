import XCTest
@testable import RelayCore

final class DeviceTests: XCTestCase {
    func testParsesMultipleDevicesAndAuthorizationStates() {
        let output = """
        * daemon not running; starting now at tcp:5037
        * daemon started successfully
        List of devices attached
        R58M123ABC device usb:336592896X product:panther model:Pixel_7 device:panther transport_id:1
        192.168.1.25:37123 device product:cheetah model:Pixel_7_Pro device:cheetah transport_id:2
        SERIAL2 unauthorized usb:123 transport_id:3
        SERIAL3 offline transport_id:4
        """
        let devices = AndroidDevice.parse(output)
        XCTAssertEqual(devices.count, 4)
        XCTAssertEqual(devices[0].name, "Pixel 7")
        XCTAssertEqual(devices[0].product, "panther")
        XCTAssertTrue(devices[0].isReady)
        XCTAssertFalse(devices[0].isWireless)
        XCTAssertTrue(devices[1].isWireless)
        XCTAssertFalse(devices[2].isReady)
        XCTAssertEqual(devices[2].statusLabel, "Allow USB debugging on your phone")
        XCTAssertEqual(devices[3].state, "offline")
    }

    func testIgnoresNoiseAndEmptyLists() {
        XCTAssertEqual(AndroidDevice.parse("List of devices attached\n\nadb: failed to start daemon\n"), [])
        XCTAssertEqual(AndroidDevice.parse("random noise\nnot-a-device\n"), [])
    }

    func testMDNSDevicesAreWireless() {
        let device = AndroidDevice.parse("adb-ABC-code._adb-tls-connect._tcp device model:SM_S928B transport_id:1").first!
        XCTAssertTrue(device.isWireless)
        XCTAssertEqual(device.name, "SM S928B")
    }

    func testNoPermissionsStateAndMissingModel() {
        let device = AndroidDevice.parse("SERIAL no permissions (user in plugdev group); see [http://developer.android.com/tools/device.html]").first!
        XCTAssertFalse(device.isReady)
        XCTAssertEqual(device.statusLabel, "Device access denied")
        XCTAssertEqual(device.name, "Android device")
    }
}

final class MirrorOptionsTests: XCTestCase {
    let phone = AndroidDevice(id: "SERIAL", state: "device", model: "Pixel_9")

    func testHighQualityDefaults() {
        let args = MirrorOptions().arguments(for: phone)
        XCTAssertTrue(args.contains("--serial=SERIAL"))
        XCTAssertTrue(args.contains("--max-size=1920"))
        XCTAssertTrue(args.contains("--max-fps=60"))
        XCTAssertTrue(args.contains("--video-bit-rate=16M"))
        XCTAssertTrue(args.contains("--stay-awake"))
        XCTAssertFalse(args.contains("--no-audio"))
        XCTAssertFalse(args.contains("--turn-screen-off"))
    }

    func testNativeQualityHasNoResolutionCapAndPreservesRecordingPath() {
        let options = MirrorOptions(quality: .native, fps: 120, audio: false, stayAwake: false,
                                    turnScreenOff: true, alwaysOnTop: true, readOnly: true)
        let recording = URL(fileURLWithPath: "/tmp/My Captures/session $(literal).mp4")
        let args = options.arguments(for: phone, recording: recording)
        XCTAssertFalse(args.contains { $0.hasPrefix("--max-size") })
        XCTAssertTrue(args.contains("--max-fps=120"))
        XCTAssertTrue(args.contains("--no-audio"))
        XCTAssertFalse(args.contains("--turn-screen-off"))
        XCTAssertTrue(args.contains("--always-on-top"))
        XCTAssertTrue(args.contains("--no-control"))
        XCTAssertTrue(args.contains("--record=/tmp/My Captures/session $(literal).mp4"))
        XCTAssertFalse(args.contains("--stay-awake"))
    }

    func testSerialAndWindowTitleRemainSingleArguments() {
        let device = AndroidDevice(id: "serial;echo test", state: "device", model: "Phone_with_spaces")
        let args = MirrorOptions().arguments(for: device)
        XCTAssertEqual(args[0], "--serial=serial;echo test")
        XCTAssertEqual(args[1], "--window-title=Phone with spaces — Relay")
    }

    func testScreenControlsAreIncludedOnlyWhenControlIsEnabled() {
        var options = MirrorOptions(stayAwake: true, turnScreenOff: true)
        XCTAssertTrue(options.arguments(for: phone).contains("--turn-screen-off"))
        XCTAssertTrue(options.arguments(for: phone).contains("--stay-awake"))
        options.readOnly = true
        XCTAssertFalse(options.arguments(for: phone).contains("--turn-screen-off"))
        XCTAssertFalse(options.arguments(for: phone).contains("--stay-awake"))
        XCTAssertTrue(options.arguments(for: phone).contains("--no-control"))
    }
}

final class WirelessTests: XCTestCase {
    func testAcceptsIPAndMDNSHosts() {
        XCTAssertEqual(WirelessAddress.validated(" 192.168.1.25:37123 \n"), "192.168.1.25:37123")
        XCTAssertEqual(WirelessAddress.validated("android-phone.local:5555"), "android-phone.local:5555")
    }

    func testRejectsMalformedAndOptionLikeEndpoints() {
        for address in ["", "192.168.1.1", "192.168.1.1:0", "192.168.1.1:65536", "999.1.1.1:5555", "1.2.3:5555", "-s:5555", "host;ls:5555", "host/path:5555", "host:abc", "host:1:2", ".:5555", "host\nname:5555"] {
            XCTAssertNil(WirelessAddress.validated(address), address)
        }
    }

    func testPairingCodeUsesExactlySixASCIIDigits() {
        XCTAssertTrue(WirelessAddress.validPairingCode("012345"))
        for code in ["12345", "1234567", "12 456", "abcdef", "١٢٣٤٥٦", "12345\n"] {
            XCTAssertFalse(WirelessAddress.validPairingCode(code), code)
        }
    }
}

final class ProcessRunnerTests: XCTestCase {
    func testBinaryOutputIsNotDecodedOrMixedWithDiagnostics() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        let result = try await ProcessRunner.run(URL(fileURLWithPath: "/usr/bin/printf"), ["\\211PNG\\r\\n\\032\\n"], binaryOutput: url)
        XCTAssertTrue(result.succeeded)
        XCTAssertEqual(result.output, "")
        XCTAssertEqual(try Data(contentsOf: url), Data([137, 80, 78, 71, 13, 10, 26, 10]))
    }

    func testPreservesLargeOutputWithoutPipeDeadlock() async throws {
        let expected = String(repeating: "x", count: 100_000)
        let result = try await ProcessRunner.run(URL(fileURLWithPath: "/usr/bin/printf"), ["%s", expected])
        XCTAssertTrue(result.succeeded)
        XCTAssertEqual(result.output, expected)
    }

    func testReportsNonzeroExitAndCapturesStderr() async throws {
        let result = try await ProcessRunner.run(URL(fileURLWithPath: "/usr/bin/env"), ["/nonexistent-relay-test-command"])
        XCTAssertFalse(result.succeeded)
        XCTAssertTrue(result.output.contains("nonexistent-relay-test-command"))
    }

    func testTimeoutTerminatesCommand() async throws {
        let started = Date()
        do {
            _ = try await ProcessRunner.run(URL(fileURLWithPath: "/bin/sleep"), ["10"], timeout: 0.1)
            XCTFail("Expected timeout")
        } catch CommandError.timedOut {
            XCTAssertLessThan(Date().timeIntervalSince(started), 3)
        }
    }

    func testInvalidExecutableThrows() async {
        do {
            _ = try await ProcessRunner.run(URL(fileURLWithPath: "/nonexistent-relay-test-command"), [])
            XCTFail("Expected process launch failure")
        } catch { XCTAssertFalse(error.localizedDescription.isEmpty) }
    }
}
