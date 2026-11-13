import SwiftUI
import AppKit
import RelayCore

struct ContentView: View {
    @EnvironmentObject private var store: AppStore
    var body: some View {
        HStack(spacing: 0) {
            SidebarView()
            Rectangle().fill(Theme.line).frame(width: 1)
            VStack(spacing: 0) {
                pageHeader
                Group {
                    switch store.page {
                    case .devices: DevicesView()
                    case .captures: CapturesView()
                    case .activity: ActivityView()
                    case .settings: SettingsView()
                    }
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
                statusBar
            }.background(Theme.canvas)
        }
        .font(.system(size: 13)).foregroundStyle(Theme.ink).tint(Theme.purple)
        .sheet(isPresented: $store.showSetup) { SetupView().environmentObject(store) }
        .sheet(isPresented: $store.showWireless) { WirelessView().environmentObject(store) }
        .alert("Relay", isPresented: Binding(get: { store.alert != nil }, set: { if !$0 { store.alert = nil } })) {
            Button("OK", role: .cancel) { store.alert = nil }
        } message: { Text(store.alert ?? "") }
    }

    private var pageHeader: some View {
        HStack {
            VStack(alignment: .leading, spacing: 5) {
                Text(store.page.rawValue).font(.system(size: 22, weight: .semibold))
                Text(subtitle).font(.system(size: 11)).foregroundStyle(Theme.muted)
            }
            Spacer()
            if store.page == .devices {
                StatusPill(text: "Local & private")
                Rectangle().fill(Theme.line).frame(width: 1, height: 22).padding(.horizontal, 12)
                Button { store.beginAutomaticWiFi() } label: { Label("Connect via Wi-Fi", systemImage: "wifi") }
                    .buttonStyle(RelayButtonStyle())
                IconButton(symbol: "arrow.clockwise", help: "Refresh devices · ⌘R") { Task { await store.refresh() } }
                    .disabled(store.scanning)
            } else if store.page == .captures {
                Button { store.revealCaptures() } label: { Label("Open folder", systemImage: "folder") }.buttonStyle(RelayButtonStyle())
                IconButton(symbol: "arrow.clockwise", help: "Refresh captures") { store.loadCaptures() }
            }
        }
        .padding(.horizontal, 30).padding(.top, 18).padding(.bottom, 22)
        .background(.white).overlay(alignment: .bottom) { Rectangle().fill(Theme.line).frame(height: 1) }
    }

    private var subtitle: String {
        switch store.page {
        case .devices: "Your phones, right where you work."
        case .captures: "The moments you saved from your phone."
        case .activity: "Connections, sessions, and everything in between."
        case .settings: "Make yourself at home."
        }
    }

    private var statusBar: some View {
        HStack(spacing: 7) {
            Circle().fill(store.engine.isReady ? Theme.green : .orange).frame(width: 5, height: 5)
            Text(store.engine.isReady ? "Android engine ready" : "Android engine needs setup")
            if !store.sessions.isEmpty { Text("·"); Text("\(store.sessions.count) active session\(store.sessions.count == 1 ? "" : "s")") }
            Spacer()
            Image(systemName: "lock.shield").font(.system(size: 10))
            Text("On your devices. Under your control.")
        }
        .font(.system(size: 10)).foregroundStyle(Theme.muted).padding(.horizontal, 30).frame(height: 36)
        .background(.white).overlay(alignment: .top) { Rectangle().fill(Theme.line).frame(height: 1) }
    }
}

struct SidebarView: View {
    @EnvironmentObject private var store: AppStore
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 11).fill(Theme.purple.gradient).frame(width: 36, height: 36)
                    Image(systemName: "rectangle.on.rectangle.angled").font(.system(size: 19, weight: .medium)).foregroundStyle(.white)
                }
                Text("relay").font(.system(size: 27, weight: .semibold, design: .rounded)).tracking(-1.4)
                Spacer()
                Text("MAC").font(.system(size: 8, weight: .bold)).tracking(1).foregroundStyle(Theme.muted)
            }.padding(.top, 44).padding(.bottom, 39).padding(.horizontal, 22)

            Eyebrow(title: "WORKSPACE").padding(.leading, 26).padding(.bottom, 14)
            ForEach(Page.allCases) { page in
                Button {
                    store.page = page
                    if page == .captures { store.loadCaptures() }
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: page.symbol).font(.system(size: 15)).frame(width: 20)
                        Text(page.rawValue).font(.system(size: 12, weight: store.page == page ? .semibold : .medium))
                        Spacer()
                        if page == .devices && store.readyCount > 0 {
                            Text("\(store.readyCount)").font(.system(size: 10, weight: .semibold)).padding(.horizontal, 6).padding(.vertical, 2).background(Theme.purple.opacity(0.1), in: Capsule())
                        }
                    }
                    .foregroundStyle(store.page == page ? Theme.purple : Color(hex: 0x72717E))
                    .padding(.horizontal, 13).frame(height: 42)
                    .background(store.page == page ? Color(hex: 0xEEEAFB) : .clear, in: RoundedRectangle(cornerRadius: 8))
                    .contentShape(Rectangle())
                }.buttonStyle(.plain).padding(.horizontal, 13).padding(.bottom, 5)
            }
            Spacer(minLength: 30)
            VStack(alignment: .leading, spacing: 11) {
                Image(systemName: "cable.connector").font(.system(size: 22)).foregroundStyle(Theme.purple)
                Text("Small setup.\nBigger possibilities.").font(.system(size: 13, weight: .semibold)).lineSpacing(3)
                Text("Get your first phone connected\nin just a few steps.").font(.system(size: 10)).foregroundStyle(Theme.muted).lineSpacing(3)
                Button { store.showSetup = true } label: {
                    HStack { Text("Connection guide"); Spacer(); Image(systemName: "arrow.up.right").font(.system(size: 9)) }
                }.buttonStyle(.plain).font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.purple).padding(.top, 2)
            }
            .padding(17).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(hex: 0xF3F1F9), in: RoundedRectangle(cornerRadius: 12)).padding(.horizontal, 17)
            HStack(spacing: 7) {
                Circle().fill(Theme.green).frame(width: 5, height: 5)
                Text("Made for your Mac").font(.system(size: 10))
                Spacer()
                Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Development")
                    .font(.system(size: 9, design: .monospaced))
            }.foregroundStyle(Theme.muted).padding(.horizontal, 24).padding(.top, 25).padding(.bottom, 21)
        }.frame(width: 218).background(.white)
    }
}

struct DevicesView: View {
    @EnvironmentObject private var store: AppStore
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HeroView()
                HStack {
                    Eyebrow(title: "YOUR DEVICES")
                    Spacer()
                    if store.scanning { ProgressView().controlSize(.mini) }
                    Text(store.scanning ? "Looking for devices…" : "Automatically discovers connected phones")
                        .font(.system(size: 10)).foregroundStyle(Theme.muted)
                }.padding(.top, 2)
                HStack(alignment: .top, spacing: 18) {
                    AndroidCard()
                    IOSCard()
                }
                HStack(spacing: 12) {
                    Image(systemName: "lightbulb").foregroundStyle(Theme.purple).font(.system(size: 15))
                    Text("A little tip").font(.system(size: 11, weight: .semibold))
                    Text("Once mirrored, drag files onto the Android window to send them to your phone.")
                        .font(.system(size: 11)).foregroundStyle(Theme.muted)
                    Spacer(minLength: 0)
                }.padding(16).background(.white, in: RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.line))
                if !store.sessions.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Eyebrow(title: "LIVE SESSIONS")
                        ForEach(Array(store.sessions.values).sorted { $0.started < $1.started }) { session in SessionRow(session: session) }
                    }
                }
            }.padding(30)
        }
    }
}

struct HeroView: View {
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 13) {
                HStack(spacing: 6) {
                    Image(systemName: "sparkle").font(.system(size: 10))
                    Text("LESS REACHING. MORE DOING.").font(.system(size: 9, weight: .semibold)).tracking(1.6)
                }.foregroundStyle(Theme.purple)
                Text("A window to your phone.").font(.system(size: 29, weight: .semibold)).tracking(-0.9).lineLimit(1).minimumScaleFactor(0.8)
                Text("Your apps, messages, and moments.\nRight here, on the screen you’re already using.")
                    .font(.system(size: 12)).foregroundStyle(Color(hex: 0x827993)).lineSpacing(5)
                HStack(spacing: 18) {
                    heroFeature("cable.connector", "USB + Wi-Fi")
                    heroFeature("keyboard", "Full control")
                    heroFeature("person.crop.circle.badge.checkmark", "No account")
                }.padding(.top, 7)
            }
            Spacer(minLength: 6)
            DeviceIllustration().frame(width: 265, height: 190)
        }
        .padding(.horizontal, 28).padding(.vertical, 25)
        .frame(height: 230)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            GeometryReader { geometry in
                ZStack(alignment: .trailing) {
                    Color(hex: 0xF1EDFC)
                    Circle().fill(Color(hex: 0xEAE3FA)).frame(width: 320, height: 320).offset(x: 44, y: 35)
                    Circle().stroke(Color.white.opacity(0.5), lineWidth: 1).frame(width: 390, height: 390).offset(x: 80, y: 35)
                }.frame(width: geometry.size.width, height: geometry.size.height).clipped()
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 15))
        .accessibilityElement(children: .combine)
    }
    private func heroFeature(_ symbol: String, _ title: String) -> some View {
        HStack(spacing: 5) { Image(systemName: symbol).font(.system(size: 10)); Text(title).font(.system(size: 10, weight: .medium)) }
            .foregroundStyle(Color(hex: 0x746388))
    }
}

struct DeviceIllustration: View {
    var body: some View {
        ZStack {
            Ellipse().fill(Theme.purple.opacity(0.08)).frame(width: 230, height: 20).offset(y: 76)
            // An original vector illustration: a phone mirrored on a Mac.
            RoundedRectangle(cornerRadius: 11).fill(Color(hex: 0x9B8CBA)).frame(width: 201, height: 134).rotationEffect(.degrees(-4)).offset(x: -14, y: -4)
            RoundedRectangle(cornerRadius: 9).fill(Color(hex: 0xFDFBFF)).frame(width: 193, height: 126).rotationEffect(.degrees(-4)).offset(x: -14, y: -5)
            VStack(spacing: 0) {
                HStack(spacing: 3) { ForEach(0..<3) { _ in Circle().fill(Color(hex: 0xDDD5EA)).frame(width: 3, height: 3) }; Spacer() }.padding(7)
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 6) {
                        RoundedRectangle(cornerRadius: 2).fill(Color(hex: 0xE6DEF5)).frame(width: 43, height: 5)
                        ForEach(0..<3) { _ in RoundedRectangle(cornerRadius: 2).fill(Color(hex: 0xF0ECF7)).frame(width: 32, height: 4) }
                        Spacer()
                    }.padding(.leading, 8)
                    PhoneArtwork().frame(width: 40, height: 77)
                    Spacer()
                }.padding(.top, 4)
                Spacer()
            }.frame(width: 185, height: 118).rotationEffect(.degrees(-4)).offset(x: -14, y: -5)
            Path { p in p.move(to: CGPoint(x: 11, y: 154)); p.addLine(to: CGPoint(x: 214, y: 140)); p.addLine(to: CGPoint(x: 237, y: 153)); p.addQuadCurve(to: CGPoint(x: 12, y: 171), control: CGPoint(x: 129, y: 174)); p.closeSubpath() }
                .fill(Color(hex: 0xC4B6D9))
            PhoneArtwork().frame(width: 74, height: 145).rotationEffect(.degrees(9)).offset(x: 77, y: 0)
                .shadow(color: Color(hex: 0x584470).opacity(0.18), radius: 10, x: -5, y: 7)
            ZStack {
                RoundedRectangle(cornerRadius: 10).fill(.white).frame(width: 34, height: 34)
                Image(systemName: "arrow.left.arrow.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.purple)
            }.rotationEffect(.degrees(-7)).offset(x: 2, y: 40)
        }
        .accessibilityHidden(true)
    }
}

struct PhoneArtwork: View {
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .top) {
                RoundedRectangle(cornerRadius: geo.size.width * 0.18).fill(Color(hex: 0x554168))
                ZStack {
                    LinearGradient(colors: [Color(hex: 0xF5D7CF), Color(hex: 0xC1A1DA), Color(hex: 0x7564AC)], startPoint: .topLeading, endPoint: .bottomTrailing)
                    Circle().fill(Color(hex: 0xFDE7CD).opacity(0.65)).frame(width: geo.size.width * 1.3).offset(x: -15, y: -20)
                    Ellipse().fill(Color(hex: 0x9C80BB).opacity(0.5)).frame(width: geo.size.width * 1.6, height: geo.size.height * 0.7).rotationEffect(.degrees(-40)).offset(x: 15, y: 45)
                    VStack(spacing: 4) {
                        Spacer()
                        HStack(spacing: 4) { ForEach(0..<4) { index in RoundedRectangle(cornerRadius: 3).fill([Color.white.opacity(0.9), Color(hex: 0xA0C4B1), Color(hex: 0x94ABCE), Color(hex: 0xE4B5B6)][index]).frame(width: geo.size.width * 0.15, height: geo.size.width * 0.15) } }
                    }.padding(.bottom, geo.size.width * 0.2)
                }.clipShape(RoundedRectangle(cornerRadius: geo.size.width * 0.14)).padding(3)
                Capsule().fill(Color(hex: 0x554168)).frame(width: geo.size.width * 0.36, height: 5).padding(.top, 5)
                Capsule().fill(.white.opacity(0.8)).frame(width: geo.size.width * 0.32, height: 2).frame(maxHeight: .infinity, alignment: .bottom).padding(.bottom, 7)
            }
        }
    }
}

struct AndroidCard: View {
    @EnvironmentObject private var store: AppStore
    var body: some View {
        Card {
            VStack(spacing: 0) {
                PlatformHeader(title: "Android", subtitle: "Mirror. Control. Make it yours.", symbol: "apps.iphone", tint: Theme.green, background: Color(hex: 0xEAF6F0), badge: "\(store.devices.count) devices")
                if store.devices.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "iphone.and.arrow.forward").font(.system(size: 29, weight: .ultraLight)).foregroundStyle(Color(hex: 0xB9CCC2)).padding(.top, 24)
                        Text("Your Android belongs here").font(.system(size: 13, weight: .semibold))
                        Text("Connect with a USB cable and enable\nUSB debugging to get started.").font(.system(size: 11)).foregroundStyle(Theme.muted).multilineTextAlignment(.center).lineSpacing(4)
                        Button { store.showSetup = true } label: { Label("Connect Android", systemImage: "plus") }
                            .buttonStyle(RelayButtonStyle(prominent: true, tint: Theme.green)).padding(.top, 5)
                        Button("Need a hand? View setup guide") { store.showSetup = true }
                            .buttonStyle(.plain).font(.system(size: 10)).foregroundStyle(Theme.muted).padding(.top, 2)
                    }.frame(maxWidth: .infinity).padding(.bottom, 23)
                } else {
                    VStack(spacing: 0) { ForEach(store.devices) { device in AndroidDeviceRow(device: device) } }.padding(16)
                }
            }
        }.frame(maxWidth: .infinity)
    }
}

struct PlatformHeader: View {
    let title: String
    let subtitle: String
    let symbol: String
    let tint: Color
    let background: Color
    let badge: String
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol).font(.system(size: 25, weight: .regular)).foregroundStyle(tint).frame(width: 30)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.system(size: 16, weight: .semibold))
                Text(subtitle).font(.system(size: 10)).foregroundStyle(tint.opacity(0.8))
            }
            Spacer(minLength: 4)
            Text(badge).font(.system(size: 9, weight: .medium)).foregroundStyle(tint).padding(.horizontal, 8).padding(.vertical, 5).background(.white.opacity(0.7), in: Capsule())
        }.padding(20).background(background).clipShape(UnevenRoundedRectangle(topLeadingRadius: 14, topTrailingRadius: 14))
    }
}

struct IOSCard: View {
    @EnvironmentObject private var store: AppStore
    var body: some View {
        Card {
            VStack(spacing: 0) {
                PlatformHeader(title: "iPhone", subtitle: "A familiar connection.", symbol: "apple.logo", tint: Theme.blue, background: Color(hex: 0xEDF3FB), badge: "Continuity")
                VStack(spacing: 10) {
                    Image(systemName: "iphone.gen3.radiowaves.left.and.right").font(.system(size: 29, weight: .ultraLight)).foregroundStyle(Color(hex: 0xB6C6DB)).padding(.top, 24)
                    Text("Meet your iPhone, on your Mac").font(.system(size: 13, weight: .semibold))
                    Text("Open Apple’s iPhone Mirroring to view\nand control your nearby iPhone.").font(.system(size: 11)).foregroundStyle(Theme.muted).multilineTextAlignment(.center).lineSpacing(4)
                    Button { store.openIPhoneMirroring() } label: { Label("Open iPhone Mirroring", systemImage: "arrow.up.forward.app") }
                        .buttonStyle(RelayButtonStyle(prominent: true, tint: Theme.blue)).padding(.top, 5)
                    Text("macOS 15+ · iOS 18+ · Same Apple Account").font(.system(size: 9)).foregroundStyle(Theme.muted).padding(.top, 2)
                }.frame(maxWidth: .infinity).padding(.bottom, 23)
            }
        }.frame(maxWidth: .infinity)
    }
}

struct AndroidDeviceRow: View {
    @EnvironmentObject private var store: AppStore
    let device: AndroidDevice
    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(spacing: 12) {
                Image(systemName: "iphone").font(.system(size: 27, weight: .light)).foregroundStyle(Theme.green).frame(width: 38, height: 48).background(Theme.green.opacity(0.07), in: RoundedRectangle(cornerRadius: 9))
                VStack(alignment: .leading, spacing: 5) {
                    Text(device.name).font(.system(size: 13, weight: .semibold))
                    Text(device.statusLabel).font(.system(size: 10)).foregroundStyle(device.isReady ? Theme.green : .orange)
                    Text(device.id).font(.system(size: 9, design: .monospaced)).foregroundStyle(Theme.muted).lineLimit(1).textSelection(.enabled)
                }
                Spacer()
                Image(systemName: device.isWireless ? "wifi" : "cable.connector").foregroundStyle(Theme.muted)
            }
            if device.isReady {
                HStack(spacing: 6) {
                    if let session = store.sessions[device.id] {
                        Button { store.stop(device.id) } label: { Label("Stop", systemImage: "stop.fill") }
                            .buttonStyle(RelayButtonStyle(prominent: true, tint: .red, compact: true)).disabled(session.state == .stopping)
                    } else {
                        Button { store.mirror(device) } label: { Label("Mirror", systemImage: "play.fill") }
                            .buttonStyle(RelayButtonStyle(prominent: true, tint: Theme.green, compact: true))
                        Button { store.mirror(device, record: true) } label: { Image(systemName: "record.circle") }
                            .buttonStyle(RelayButtonStyle(compact: true)).help("Mirror and record to MP4")
                    }
                    Spacer(minLength: 0)
                    IconButton(symbol: "camera", help: "Save screenshot") { Task { await store.screenshot(device) } }
                    IconButton(symbol: "square.and.arrow.up", help: "Send files to phone") { store.sendFiles(device) }
                    if device.isWireless {
                        IconButton(symbol: "wifi.slash", help: "Disconnect Wi-Fi") { Task { await store.disconnect(device) } }
                    }
                }.disabled(store.busyDevices.contains(device.id))
            } else {
                Button("Connection help") { store.showSetup = true }.buttonStyle(.plain).font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.purple)
            }
            if store.busyDevices.contains(device.id) { ProgressView().controlSize(.small) }
        }.padding(.vertical, 10)
    }
}

struct SessionRow: View {
    @EnvironmentObject private var store: AppStore
    @ObservedObject var session: MirrorSession
    var body: some View {
        Card {
            HStack(spacing: 12) {
                Image(systemName: session.recording != nil ? "record.circle.fill" : "rectangle.on.rectangle").foregroundStyle(session.recording != nil ? .red : Theme.purple)
                VStack(alignment: .leading, spacing: 4) {
                    Text(session.device.name).font(.system(size: 12, weight: .semibold))
                    Text(session.lifecycle.startupHint ?? (session.recording != nil ? "Recording to \(session.recording!.lastPathComponent)" : "Your mirror opens in its own window. Close it to end the session."))
                        .font(.system(size: 10)).foregroundStyle(Theme.muted).lineLimit(1)
                    if session.suppressAudioPlayback {
                        Text("Mac audio unavailable. Select a working sound output and click the speaker icon in the mirror to retry.")
                            .font(.system(size: 10)).foregroundStyle(Theme.muted)
                    }
                }
                Spacer()
                StatusPill(text: session.state.rawValue, color: session.state == .running ? Theme.green : .orange)
                Button("Stop") { store.stop(session.id) }.buttonStyle(RelayButtonStyle(compact: true)).disabled(session.state == .stopping)
            }.padding(16)
        }
    }
}
