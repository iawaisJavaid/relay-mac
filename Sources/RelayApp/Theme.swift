import SwiftUI

enum Theme {
    static let purple = Color(hex: 0x7054D6)
    static let ink = Color(hex: 0x242332)
    static let muted = Color(hex: 0x82818E)
    static let line = Color(hex: 0xEAE9EF)
    static let canvas = Color(hex: 0xFAFAFC)
    static let green = Color(hex: 0x269B71)
    static let blue = Color(hex: 0x4386CD)
}

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB, red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255, opacity: 1)
    }
}

struct RelayButtonStyle: ButtonStyle {
    var prominent = false
    var tint: Color = Theme.purple
    var compact = false
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: compact ? 11 : 12, weight: .semibold))
            .padding(.horizontal, compact ? 12 : 16)
            .frame(height: compact ? 30 : 36)
            .foregroundStyle(prominent ? .white : Theme.ink)
            .background(prominent ? tint : Color.white, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(prominent ? .clear : Theme.line, lineWidth: 1))
            .opacity(!enabled ? 0.4 : configuration.isPressed ? 0.75 : 1)
            .contentShape(RoundedRectangle(cornerRadius: 8))
    }
}

struct IconButton: View {
    let symbol: String
    let help: String
    var tint: Color = Theme.muted
    let action: () -> Void
    var body: some View {
        Button(action: action) { Image(systemName: symbol).font(.system(size: 13)).frame(width: 30, height: 30) }
            .buttonStyle(.plain).foregroundStyle(tint).help(help).accessibilityLabel(help)
    }
}

struct Eyebrow: View {
    let title: String
    var body: some View { Text(title).font(.system(size: 10, weight: .semibold)).tracking(1.6).foregroundStyle(Theme.muted) }
}

struct StatusPill: View {
    let text: String
    var color: Color = Theme.green
    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 5, height: 5)
            Text(text).font(.system(size: 10, weight: .medium))
        }
        .foregroundStyle(color).padding(.horizontal, 10).padding(.vertical, 6)
        .background(color.opacity(0.08), in: Capsule())
    }
}

struct Card<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        content.background(.white, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Theme.line, lineWidth: 1))
    }
}
