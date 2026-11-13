import SwiftUI

struct SetupView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var tab = "Android"
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Let’s get you connected.").font(.system(size: 24, weight: .semibold))
                    Text("One small setup. Your whole phone, on your Mac.").font(.system(size: 12)).foregroundStyle(Theme.muted)
                }
                Spacer()
                IconButton(symbol: "xmark", help: "Close guide") { dismiss() }
            }
            Picker("Platform", selection: $tab) { Text("Android").tag("Android"); Text("iPhone").tag("iPhone") }.pickerStyle(.segmented)
            if tab == "Android" {
                VStack(alignment: .leading, spacing: 22) {
                    guideStep(1, "Turn on Developer options", "On your phone, open Settings → About phone. Tap Build number seven times. On Samsung, look under Software information.")
                    guideStep(2, "Enable USB debugging", "Open Settings → Developer options and switch on USB debugging. Some Xiaomi phones also need USB debugging (Security settings) for mouse control.")
                    guideStep(3, "Plug in. Unlock. Allow.", "Use a USB data cable. Unlock your phone and approve “Allow USB debugging” for this Mac. Your phone will appear automatically in Relay.")
                    guideStep(4, "Make yourself comfortable", "Click Mirror. Use your keyboard and mouse in the new window. Drag to swipe, scroll to navigate, and drop files to send them to your phone.")
                }
                HStack(spacing: 20) {
                    shortcut("⌘ H", "Home"); shortcut("⌘ B", "Back"); shortcut("⌘ S", "App switcher"); shortcut("⌘ F", "Fullscreen")
                }.padding(15).frame(maxWidth: .infinity).background(Theme.purple.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))
                if !store.engine.isReady {
                    VStack(alignment: .leading, spacing: 7) {
                        Text("Android engine not found").font(.system(size: 12, weight: .semibold))
                        Text("Use the bundled Relay.app built with scripts/build-app.sh, or install the tools with Homebrew:").font(.system(size: 11))
                        Text("brew install scrcpy\nbrew install --cask android-platform-tools").font(.system(size: 11, design: .monospaced)).textSelection(.enabled)
                    }.padding(15).frame(maxWidth: .infinity, alignment: .leading).background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                }
                Text("No device appearing? Try another data cable, choose File Transfer in the phone’s USB options, and check for an authorization prompt. Android 5+ is supported; audio needs Android 11+.")
                    .font(.system(size: 10)).foregroundStyle(Theme.muted).lineSpacing(4)
            } else {
                VStack(alignment: .leading, spacing: 22) {
                    guideStep(1, "Check your devices", "You need macOS 15 or later on an Apple silicon or T2 Mac, and an iPhone running iOS 18 or later with a passcode.")
                    guideStep(2, "Use the same Apple Account", "Sign in on both devices with two-factor authentication. Turn on Wi-Fi and Bluetooth, and keep your locked iPhone nearby.")
                    guideStep(3, "Open iPhone Mirroring", "Relay opens Apple’s built-in iPhone Mirroring app. Complete Apple’s first-time setup to control your iPhone with your Mac’s mouse and keyboard.")
                }
                Text("iPhone sessions are handled by Apple’s app. Relay’s Android recording, file transfer, and quality settings do not apply to iPhone. Availability depends on Apple’s device and regional requirements.")
                    .font(.system(size: 11)).foregroundStyle(Theme.muted).lineSpacing(5).padding(16)
                    .background(Theme.blue.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
                Link("Read Apple’s iPhone Mirroring requirements ↗", destination: URL(string: "https://support.apple.com/en-us/120421")!)
                    .font(.system(size: 11)).foregroundStyle(Theme.blue)
                Spacer(minLength: 30)
            }
            HStack {
                if tab == "Android" {
                    Button { dismiss(); store.beginAutomaticWiFi() } label: { Label("Prefer Wi-Fi?", systemImage: "wifi") }.buttonStyle(RelayButtonStyle())
                }
                Spacer()
                Button(tab == "Android" ? "Got it" : "Open iPhone Mirroring") {
                    dismiss()
                    if tab == "iPhone" { store.openIPhoneMirroring() }
                    else { Task { await store.refresh() } }
                }.buttonStyle(RelayButtonStyle(prominent: true)).keyboardShortcut(.defaultAction)
            }
        }.padding(30).frame(width: 590).background(Theme.canvas)
    }
    private func guideStep(_ number: Int, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Text("\(number)").font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.purple).frame(width: 25, height: 25).background(Theme.purple.opacity(0.08), in: Circle())
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(.system(size: 12, weight: .semibold))
                Text(detail).font(.system(size: 11)).foregroundStyle(Theme.muted).lineSpacing(4).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
    private func shortcut(_ key: String, _ title: String) -> some View {
        VStack(spacing: 6) {
            Text(key).font(.system(size: 11, weight: .medium, design: .monospaced)).foregroundStyle(Theme.purple)
            Text(title).font(.system(size: 9)).foregroundStyle(Theme.muted)
        }.frame(maxWidth: .infinity)
    }
}

struct WirelessView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack(spacing: 14) {
                Image(systemName: store.wifiFailed ? "wifi.exclamationmark" : "wifi")
                    .font(.system(size: 25)).foregroundStyle(Theme.purple)
                    .frame(width: 52, height: 52).background(Theme.purple.opacity(0.07), in: RoundedRectangle(cornerRadius: 13))
                VStack(alignment: .leading, spacing: 6) {
                    Text(store.wifiWorking ? "Going wireless…" : store.wifiFailed ? "One more step on your phone" : "You’re wireless.")
                        .font(.system(size: 22, weight: .semibold))
                    Text("No addresses. No ports. No pairing codes.").font(.system(size: 11)).foregroundStyle(Theme.muted)
                }
            }
            HStack(alignment: .top, spacing: 14) {
                if store.wifiWorking { ProgressView().controlSize(.small) }
                else { Image(systemName: store.wifiFailed ? "info.circle" : "checkmark.circle.fill").foregroundStyle(store.wifiFailed ? .orange : Theme.green) }
                Text(store.wifiMessage).font(.system(size: 12)).lineSpacing(5).fixedSize(horizontal: false, vertical: true)
            }.padding(20).frame(maxWidth: .infinity, alignment: .leading)
                .background(.white, in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.line))
            Text("Use a trusted Wi-Fi network. Disconnect or quit restores USB-only mode when the phone is reachable. Android’s first USB debugging approval must be accepted on your phone.")
                .font(.system(size: 10)).foregroundStyle(Theme.muted).lineSpacing(4)
            HStack {
                Spacer()
                if store.wifiFailed && !store.wifiWorking {
                    Button("Retry automatically") { store.beginAutomaticWiFi() }.buttonStyle(RelayButtonStyle())
                }
                Button(store.wifiWorking ? "Connecting…" : "Done") { dismiss() }
                    .buttonStyle(RelayButtonStyle(prominent: true)).disabled(store.wifiWorking).keyboardShortcut(.defaultAction)
            }
        }.padding(30).frame(width: 520).background(Theme.canvas).interactiveDismissDisabled(store.wifiWorking)
    }
}
