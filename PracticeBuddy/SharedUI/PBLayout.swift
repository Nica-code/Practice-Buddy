import SwiftUI

/// Centralized spacing + corner radius tokens so the UI feels consistent everywhere.
enum PBLayout {
    // Corner radii (match your existing style direction: 14 / 18 / 22)
    static let radiusControl: Double = 14
    static let radiusCard: Double = 18
    static let radiusSheet: Double = 22

    // Padding
    static let padXS: Double = 8
    static let padSM: Double = 12
    static let padMD: Double = 16
    static let padLG: Double = 18
    static let padXL: Double = 24
}

struct PBBackdropView: View {
    let palette: PBTheme.Palette

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    palette.background,
                    palette.surface.opacity(0.94),
                    palette.background
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Circle()
                .fill(palette.accent.opacity(0.10))
                .frame(width: 260, height: 260)
                .blur(radius: 10)
                .offset(x: 130, y: -220)

            Circle()
                .fill(palette.accent.opacity(0.08))
                .frame(width: 220, height: 220)
                .blur(radius: 12)
                .offset(x: -140, y: 260)
        }
        .ignoresSafeArea()
    }
}

private struct PBModernCardModifier: ViewModifier {
    let palette: PBTheme.Palette

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: PBLayout.radiusCard, style: .continuous)
                    .fill(palette.surface.opacity(0.94))
                    .overlay(
                        RoundedRectangle(cornerRadius: PBLayout.radiusCard, style: .continuous)
                            .stroke(palette.accent.opacity(0.16), lineWidth: 1)
                    )
                    .shadow(color: Color.black.opacity(0.10), radius: 14, x: 0, y: 8)
            )
    }
}

extension View {
    func pbModernCard(palette: PBTheme.Palette) -> some View {
        modifier(PBModernCardModifier(palette: palette))
    }
}

struct PBActionButtonStyle: ButtonStyle {
    enum Variant {
        case primary
        case secondary
    }

    let variant: Variant
    let palette: PBTheme.Palette

    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed
        let backgroundColor: Color = {
            switch variant {
            case .primary:
                return palette.accent.opacity(pressed ? 0.84 : 1.0)
            case .secondary:
                return palette.surfaceAlt.opacity(pressed ? 0.85 : 1.0)
            }
        }()
        let foregroundColor: Color = {
            switch variant {
            case .primary:
                return Color.white
            case .secondary:
                return palette.textPrimary
            }
        }()

        return configuration.label
            .foregroundStyle(foregroundColor)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: PBLayout.radiusControl, style: .continuous)
                    .fill(backgroundColor)
                    .overlay(
                        RoundedRectangle(cornerRadius: PBLayout.radiusControl, style: .continuous)
                            .stroke(variant == .secondary ? palette.accent.opacity(0.20) : Color.clear, lineWidth: 1)
                    )
            )
            .scaleEffect(pressed ? 0.98 : 1.0)
            .shadow(color: variant == .primary ? Color.black.opacity(0.12) : Color.black.opacity(0.05), radius: 8, x: 0, y: 4)
            .animation(.interactiveSpring(response: 0.24, dampingFraction: 0.82), value: pressed)
    }
}
