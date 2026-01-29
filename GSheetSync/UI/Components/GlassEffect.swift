import SwiftUI

// MARK: - Liquid Glass Effect Extensions
// Based on Apple's iOS/macOS 26 Liquid Glass API
// Reference: https://github.com/conorluddy/LiquidGlassReference

extension View {
    /// Applies the Liquid Glass effect with a capsule shape (default)
    func liquidGlass() -> some View {
        self.glassEffect(.regular, in: .capsule)
    }

    /// Applies the Liquid Glass effect with a rounded rectangle shape
    func liquidGlassRounded(_ cornerRadius: CGFloat = 16) -> some View {
        self.glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
    }

    /// Applies the Liquid Glass effect with a circle shape
    func liquidGlassCircle() -> some View {
        self.glassEffect(.regular, in: .circle)
    }

    /// Applies a clear variant for media-rich backgrounds
    func liquidGlassClear(cornerRadius: CGFloat = 16) -> some View {
        self.glassEffect(.clear, in: .rect(cornerRadius: cornerRadius))
    }
}

// MARK: - Glass Card Component

struct GlassCard<Content: View>: View {
    var cornerRadius: CGFloat = 16
    var tint: Color? = nil
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
            .tint(tint)
    }
}

// MARK: - Custom Glass Button Styles (prefixed to avoid SwiftUI conflicts)

struct AppGlassButtonStyle: ButtonStyle {
    var tint: Color? = nil

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial, in: Capsule())
            .tint(tint)
            .contentShape(Capsule())
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.spring(response: 0.2, dampingFraction: 0.8), value: configuration.isPressed)
    }
}

struct AppGlassPillButtonStyle: ButtonStyle {
    var tint: Color? = nil

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(.ultraThinMaterial, in: Capsule())
            .tint(tint)
            .contentShape(Capsule())
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

struct AppGlassIconButtonStyle: ButtonStyle {
    var size: CGFloat = 36

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(width: size, height: size)
            .background(.ultraThinMaterial, in: Circle())
            .clipShape(Circle())
            .contentShape(Circle())
            .scaleEffect(configuration.isPressed ? 0.92 : 1.0)
            .animation(.spring(response: 0.2, dampingFraction: 0.75), value: configuration.isPressed)
    }
}

// MARK: - Button Style Extensions

extension ButtonStyle where Self == AppGlassButtonStyle {
    static var appGlass: AppGlassButtonStyle { AppGlassButtonStyle() }

    static func appGlass(tint: Color) -> AppGlassButtonStyle {
        AppGlassButtonStyle(tint: tint)
    }
}

extension ButtonStyle where Self == AppGlassPillButtonStyle {
    static var glassPill: AppGlassPillButtonStyle { AppGlassPillButtonStyle() }

    static func glassPill(tint: Color) -> AppGlassPillButtonStyle {
        AppGlassPillButtonStyle(tint: tint)
    }
}

extension ButtonStyle where Self == AppGlassIconButtonStyle {
    static var glassIcon: AppGlassIconButtonStyle { AppGlassIconButtonStyle() }

    static func glassIcon(size: CGFloat) -> AppGlassIconButtonStyle {
        AppGlassIconButtonStyle(size: size)
    }
}
