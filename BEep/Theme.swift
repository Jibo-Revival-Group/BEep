import SwiftUI

/// Liquid Glass, with a material fallback before iOS 26. (5x1 colours are in Shared.)
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

    /// A screen that fits doesn't move at all (iOS 16.4+; earlier iOS always bounces).
    @ViewBuilder
    func bounceOnlyWhenTaller() -> some View {
        if #available(iOS 16.4, *) {
            scrollBounceBehavior(.basedOnSize, axes: .vertical)
        } else {
            self
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
