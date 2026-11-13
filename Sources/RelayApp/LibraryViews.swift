import SwiftUI
import AppKit
import RelayCore

struct CapturesView: View {
    @EnvironmentObject private var store: AppStore
    @State private var filter = "All"
    @State private var search = ""
    private var filtered: [CaptureItem] {
        store.captures.filter { capture in
            (filter == "All" || (filter == "Recordings" ? capture.isVideo : !capture.isVideo)) &&
            (search.isEmpty || capture.url.lastPathComponent.localizedCaseInsensitiveContains(search))
        }
    }

    var body: some View {
        VStack(spacing: 22) {
            HStack {
                Picker("Capture type", selection: $filter) {
                    Text("All").tag("All"); Text("Screenshots").tag("Screenshots"); Text("Recordings").tag("Recordings")
                }.pickerStyle(.segmented).frame(width: 290)
                Spacer()
                HStack {
                    Image(systemName: "magnifyingglass").foregroundStyle(Theme.muted)
                    TextField("Search captures", text: $search).textFieldStyle(.plain)
                }.padding(9).frame(width: 210).background(.white, in: RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.line))
            }
            if filtered.isEmpty {
                EmptyState(symbol: "photo.on.rectangle.angled", title: store.captures.isEmpty ? "Good moments deserve a place." : "No matching captures",
                           message: store.captures.isEmpty ? "Save a screenshot or record a mirroring session.\nYour captures will be waiting right here." : "Try another search or switch the capture type.") {
                    if store.captures.isEmpty {
                        Button("Go to devices") { store.page = .devices }.buttonStyle(RelayButtonStyle(prominent: true))
                    } else {
                        Button("Clear filters") { search = ""; filter = "All" }.buttonStyle(RelayButtonStyle())
                    }
                }
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 210), spacing: 18)], spacing: 18) {
                        ForEach(filtered) { capture in CaptureTile(capture: capture) }
                    }
                }
            }
        }.padding(30).onAppear { store.loadCaptures() }
    }
}

struct CaptureTile: View {
    let capture: CaptureItem
    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 0) {
                Button { NSWorkspace.shared.open(capture.url) } label: {
                    ZStack {
                        Color(hex: 0xF0EDF7)
                        if !capture.isVideo, let image = NSImage(contentsOf: capture.url) {
                            Image(nsImage: image).resizable().scaledToFit().padding(12)
                        } else {
                            VStack(spacing: 10) {
                                Image(systemName: "play.circle.fill").font(.system(size: 38, weight: .light)).foregroundStyle(Theme.purple)
                                Text("SCREEN RECORDING").font(.system(size: 8, weight: .semibold)).tracking(1.3).foregroundStyle(Theme.muted)
                            }
                        }
                    }.frame(height: 170).clipShape(UnevenRoundedRectangle(topLeadingRadius: 14, topTrailingRadius: 14))
                }.buttonStyle(.plain).help("Open \(capture.url.lastPathComponent)")
                VStack(alignment: .leading, spacing: 7) {
                    Text(capture.url.deletingPathExtension().lastPathComponent).font(.system(size: 11, weight: .medium)).lineLimit(1).truncationMode(.middle)
                    HStack {
                        Text(capture.date, format: .dateTime.month(.abbreviated).day().hour().minute()).font(.system(size: 10)).foregroundStyle(Theme.muted)
                        Spacer()
                        IconButton(symbol: "folder", help: "Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([capture.url]) }
                    }
                }.padding(.horizontal, 13).padding(.top, 12).padding(.bottom, 6)
            }
        }
    }
}

struct ActivityView: View {
    @EnvironmentObject private var store: AppStore
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Eyebrow(title: "THIS APP SESSION")
                Spacer()
                Button {
                    let formatter = ISO8601DateFormatter()
                    let text = store.activity.reversed().map { "\(formatter.string(from: $0.date)) \($0.message)" }.joined(separator: "\n")
                    NSPasteboard.general.clearContents(); NSPasteboard.general.setString(text, forType: .string)
                } label: { Label("Copy log", systemImage: "doc.on.doc") }.buttonStyle(RelayButtonStyle(compact: true))
                Button("Clear") { store.activity.removeAll() }.buttonStyle(RelayButtonStyle(compact: true))
            }
            if store.activity.isEmpty {
                EmptyState(symbol: "waveform.path", title: "All quiet here.", message: "Device connections and mirroring activity\nwill appear as they happen.") { EmptyView() }
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(store.activity) { item in
                            HStack(alignment: .top, spacing: 14) {
                                Image(systemName: item.isError ? "exclamationmark.circle" : "checkmark.circle").foregroundStyle(item.isError ? .orange : Theme.green).padding(.top, 1)
                                Text(item.message).font(.system(size: 12)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                                Text(item.date, format: .dateTime.hour().minute().second()).font(.system(size: 10, design: .monospaced)).foregroundStyle(Theme.muted)
                            }.padding(17).background(.white)
                            Rectangle().fill(Theme.line).frame(height: 1)
                        }
                    }.clipShape(RoundedRectangle(cornerRadius: 12)).overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.line))
                }
            }
            Text("Logs are kept in memory for this app session. Pairing codes are never logged.").font(.system(size: 10)).foregroundStyle(Theme.muted)
        }.padding(30)
    }
}

struct EmptyState<Action: View>: View {
    let symbol: String
    let title: String
    let message: String
    @ViewBuilder let action: Action
    var body: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: symbol).font(.system(size: 40, weight: .ultraLight)).foregroundStyle(Theme.purple.opacity(0.55))
                .frame(width: 88, height: 88).background(Theme.purple.opacity(0.05), in: RoundedRectangle(cornerRadius: 24))
            Text(title).font(.system(size: 21, weight: .semibold)).padding(.top, 5)
            Text(message).font(.system(size: 12)).foregroundStyle(Theme.muted).multilineTextAlignment(.center).lineSpacing(5)
            action.padding(.top, 7)
            Spacer(); Spacer().frame(height: 40)
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct SettingsView: View {
    @EnvironmentObject private var store: AppStore
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack(spacing: 10) {
                    Image(systemName: "info.circle").foregroundStyle(Theme.purple)
                    Text("Defaults for new devices. Use the mirror’s gear menu to adjust its saved settings.").font(.system(size: 11)).foregroundStyle(Theme.muted)
                }
                settingsSection("PICTURE & PERFORMANCE") {
                    settingRow("Video quality", detail: store.quality.detail) {
                        Picker("Video quality", selection: $store.quality) { ForEach(VideoQuality.allCases) { Text($0.rawValue).tag($0) } }.labelsHidden().frame(width: 180)
                    }
                    Divider().overlay(Theme.line)
                    settingRow("Frame rate", detail: "Higher rates depend on your phone and connection.") {
                        Picker("Frame rate", selection: $store.fps) { ForEach([30, 60, 90, 120], id: \.self) { Text("\($0) fps").tag($0) } }.labelsHidden().frame(width: 120)
                    }
                    Divider().overlay(Theme.line)
                    settingToggle("Phone audio", detail: "Play your phone’s audio through your Mac. Requires Android 11+.", value: $store.audio)
                }
                settingsSection("YOUR MIRROR WINDOW") {
                    settingToggle("Keep phone awake", detail: "Prevents sleep while connected. Requires phone control.", value: $store.stayAwake).disabled(store.readOnly)
                    Divider().overlay(Theme.line)
                    settingToggle("Turn phone display off", detail: "Keep mirroring while the physical screen is off. Requires phone control.", value: $store.turnScreenOff).disabled(store.readOnly)
                    Divider().overlay(Theme.line)
                    settingToggle("Always on top", detail: "Keep the mirror above other windows.", value: $store.alwaysOnTop)
                    Divider().overlay(Theme.line)
                    settingToggle("View only", detail: "Disable mouse, keyboard, clipboard sync, and file drop in the mirror.", value: $store.readOnly)
                }
                settingsSection("CAPTURES") {
                    settingRow("Save location", detail: store.captureDirectory.path) {
                        Button("Choose folder…") { store.chooseCaptureDirectory() }.buttonStyle(RelayButtonStyle(compact: true))
                    }
                }
                settingsSection("ENGINE") {
                    HStack {
                        VStack(alignment: .leading, spacing: 7) {
                            Text("Powered by scrcpy").font(.system(size: 12, weight: .medium))
                            Text("Native H.264 mirroring · Android Debug Bridge").font(.system(size: 10)).foregroundStyle(Theme.muted)
                        }
                        Spacer()
                        StatusPill(text: store.engine.isReady ? "Ready" : "Setup needed", color: store.engine.isReady ? Theme.green : .orange)
                    }.padding(18)
                    Divider().overlay(Theme.line)
                    VStack(alignment: .leading, spacing: 7) {
                        Text("ADB: \(store.engine.adb?.path ?? "Not found")")
                        Text("scrcpy: \(store.engine.scrcpy?.path ?? "Not found")")
                    }.font(.system(size: 9, design: .monospaced)).foregroundStyle(Theme.muted).textSelection(.enabled).padding(18)
                }
            }.padding(30)
        }
    }

    private func settingsSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) { Eyebrow(title: title); Card { VStack(spacing: 0, content: content) } }
    }
    private func settingRow<Control: View>(_ title: String, detail: String, @ViewBuilder control: () -> Control) -> some View {
        HStack(spacing: 20) {
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.system(size: 12, weight: .medium))
                Text(detail).font(.system(size: 10)).foregroundStyle(Theme.muted).textSelection(.enabled)
            }
            Spacer()
            control()
        }.padding(18)
    }
    private func settingToggle(_ title: String, detail: String, value: Binding<Bool>) -> some View {
        settingRow(title, detail: detail) { Toggle(title, isOn: value).toggleStyle(.switch).controlSize(.small).labelsHidden() }
    }
}
