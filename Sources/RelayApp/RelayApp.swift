import SwiftUI
import AppKit

@main
struct RelayApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var store = AppStore()

    var body: some Scene {
        WindowGroup("Relay") {
            ContentView()
                .environmentObject(store)
                .preferredColorScheme(.light)
                .frame(minWidth: 1050, minHeight: 730)
                .onAppear { delegate.store = store; store.start() }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1200, height: 830)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandGroup(after: .sidebar) {
                Button("Devices") { store.page = .devices }.keyboardShortcut("1")
                Button("Captures") { store.page = .captures; store.loadCaptures() }.keyboardShortcut("2")
                Button("Activity") { store.page = .activity }.keyboardShortcut("3")
                Divider()
                Button("Refresh Devices") { Task { await store.refresh() } }.keyboardShortcut("r")
                Button("Connect over Wi-Fi") { store.beginAutomaticWiFi() }.keyboardShortcut("k")
            }
            CommandGroup(replacing: .appSettings) {
                Button("Settings…") { store.page = .settings }.keyboardShortcut(",")
            }
            CommandGroup(replacing: .help) {
                Button("Connection Help") { store.showSetup = true }
            }
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var store: AppStore?

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let store else { return .terminateNow }
        let sessions = Array(store.sessions.values)
        store.shutdown()
        Task { @MainActor in
            // Wait for recording trailers before quitting the manager.
            for _ in 0..<50 {
                if !sessions.contains(where: { $0.process.isRunning }) { break }
                try? await Task.sleep(for: .milliseconds(100))
            }
            for session in sessions where session.process.isRunning { session.process.terminate() }
            await store.finishShutdown()
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
}
