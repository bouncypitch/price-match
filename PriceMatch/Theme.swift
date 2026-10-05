import SwiftUI

/// One place for the app's look: minimal, rounded, one bright accent.
enum Theme {
    /// Electric blue → violet. Used for the main button, the scan frame and highlights.
    static let accentColors = [Color(hex: 0x3B82F6), Color(hex: 0x8B5CF6)]
    static let accent = LinearGradient(colors: accentColors, startPoint: .topLeading, endPoint: .bottomTrailing)
    static let accentColor = Color(hex: 0x6366F1)

    /// Emerald: "a lower price was found".
    static let good = LinearGradient(colors: [Color(hex: 0x059669), Color(hex: 0x10B981)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing)
    /// Slate: "nothing lower".
    static let neutral = LinearGradient(colors: [Color(hex: 0x475569), Color(hex: 0x64748B)],
                                        startPoint: .topLeading, endPoint: .bottomTrailing)

    static let radius: CGFloat = 22
}

extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255)
    }
}

extension Font {
    /// Rounded system font that still grows with the phone's text-size setting.
    static func rounded(_ style: Font.TextStyle, _ weight: Font.Weight = .regular) -> Font {
        .system(style, design: .rounded, weight: weight)
    }
}

/// Large, full-width button used everywhere.
struct BigButton: View {
    enum Style {
        case primary     // bright gradient
        case secondary   // quiet grey, for light screens
        case glass       // frosted, for use over the camera
    }

    let title: String
    var systemImage: String?
    var style: Style = .primary
    let action: () -> Void

    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                if let systemImage { Image(systemName: systemImage) }
                Text(title)
            }
            .font(.rounded(.title2, .bold))
            .frame(maxWidth: .infinity, minHeight: 72)
            .foregroundStyle(style == .secondary ? Color.primary : Color.white)
            .background { background }
            .clipShape(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
            .shadow(color: style == .primary ? Theme.accentColor.opacity(0.35) : .clear, radius: 14, y: 6)
            .opacity(isEnabled ? 1 : 0.4)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder private var background: some View {
        switch style {
        case .primary: Theme.accent
        case .secondary: Color(.tertiarySystemFill)
        case .glass: Rectangle().fill(.ultraThinMaterial).environment(\.colorScheme, .dark)
        }
    }
}
