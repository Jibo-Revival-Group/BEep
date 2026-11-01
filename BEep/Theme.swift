import SwiftUI

/// 5x1 colours (5x1.com) and Liquid Glass, with a material fallback before iOS 26.
enum Theme {
    static let green = Color("AccentColor")
    static let background = Color("LaunchBackground")
    static let glow = Color(red: 0x1C / 255, green: 0x30 / 255, blue: 0x23 / 255)
    static let backdrop = RadialGradient(colors: [glow, background], center: .top, startRadius: 0, endRadius: 650)
}

extension View {
    @ViewBuilder
    func glass<S: Shape>(in shape: S, interactive: Bool = false) -> some View {
        if #available(iOS 26, *) {
            glassEffect(interactive ? .regular.interactive() : .regular, in: shape)
        } else {
            background(.ultraThinMaterial, in: shape)
        }
    }

    @ViewBuilder
    func prominentGlassButton() -> some View {
        if #available(iOS 26, *) {
            buttonStyle(.glassProminent)
        } else {
            buttonStyle(.borderedProminent)
        }
    }

    @ViewBuilder
    func subtitle(_ text: String) -> some View {
        if #available(iOS 26, *) {
            navigationSubtitle(text)
        } else {
            self
        }
    }
}
