import SwiftUI
import UIKit

/// Centralized spacing + corner radius tokens so the UI feels consistent everywhere.
enum PBLayout {
    // Corner radii
    static let radiusControl: Double = 14
    static let radiusCard: Double = 18
    static let radiusSheet: Double = 22

    // Padding scale
    static let padXS: Double = 8
    static let padSM: Double = 12
    static let padMD: Double = 16
    static let padLG: Double = 18
    static let padXL: Double = 24

    // Surface depth tokens
    static let borderWidth: Double = 1.0
    static let cardShadowY: Double = 3.0
    static let cardShadowRadius: Double = 9.0
    static let cardShadowOpacity: Double = 0.085
    static let cardAmbientOpacity: Double = 0.035
    static let glassTintOpacity: Double = 0.28
    static let glassHighlightOpacity: Double = 0.36

    // Motion tokens
    static let quickAnimation = Animation.snappy(duration: 0.22, extraBounce: 0.02)
    static let springAnimation = Animation.spring(response: 0.34, dampingFraction: 0.86)
}

struct PBBackdropView: View {
    let palette: PBTheme.Palette

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    palette.background.opacity(0.98),
                    palette.surface.opacity(0.90),
                    palette.background.opacity(0.98)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            RoundedRectangle(cornerRadius: 140, style: .continuous)
                .fill(palette.accent.opacity(0.14))
                .frame(width: 320, height: 220)
                .blur(radius: 30)
                .offset(x: 145, y: -260)

            RoundedRectangle(cornerRadius: 120, style: .continuous)
                .fill(palette.textSecondary.opacity(0.12))
                .frame(width: 280, height: 200)
                .blur(radius: 34)
                .offset(x: -150, y: 260)

            LinearGradient(
                colors: [
                    .white.opacity(0.08),
                    .clear,
                    palette.accent.opacity(0.08)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .blendMode(.plusLighter)
            .ignoresSafeArea()
        }
        .ignoresSafeArea()
    }
}

private struct PBGlassSurface: View {
    let palette: PBTheme.Palette
    let cornerRadius: Double
    let tintOpacity: Double
    let strokeOpacity: Double

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(.ultraThinMaterial)
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                palette.surface.opacity(max(0.12, tintOpacity)),
                                palette.surfaceAlt.opacity(max(0.10, tintOpacity * 0.76)),
                                palette.accent.opacity(max(0.05, tintOpacity * 0.40))
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [
                                .white.opacity(PBLayout.glassHighlightOpacity),
                                palette.accent.opacity(strokeOpacity),
                                .white.opacity(0.06)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: PBLayout.borderWidth
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: max(0, cornerRadius - 0.5), style: .continuous)
                    .stroke(.white.opacity(0.12), lineWidth: 0.6)
                    .blendMode(.screen)
            )
    }
}

private struct PBModernCardModifier: ViewModifier {
    let palette: PBTheme.Palette

    func body(content: Content) -> some View {
        content
            .clipShape(RoundedRectangle(cornerRadius: PBLayout.radiusCard, style: .continuous))
            .background(
                PBGlassSurface(
                    palette: palette,
                    cornerRadius: PBLayout.radiusCard,
                    tintOpacity: PBLayout.glassTintOpacity,
                    strokeOpacity: 0.24
                )
            )
    }
}

private struct PBFlatCardModifier: ViewModifier {
    let palette: PBTheme.Palette
    let cornerRadius: Double

    func body(content: Content) -> some View {
        content
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .background(
                PBGlassSurface(
                    palette: palette,
                    cornerRadius: cornerRadius,
                    tintOpacity: PBLayout.glassTintOpacity * 0.78,
                    strokeOpacity: 0.18
                )
            )
    }
}

private struct PBSurfaceCardModifier: ViewModifier {
    let palette: PBTheme.Palette
    let cornerRadius: Double

    func body(content: Content) -> some View {
        content
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .background(
                PBGlassSurface(
                    palette: palette,
                    cornerRadius: cornerRadius,
                    tintOpacity: PBLayout.glassTintOpacity * 0.62,
                    strokeOpacity: 0.16
                )
            )
    }
}

extension View {
    func pbModernCard(palette: PBTheme.Palette) -> some View {
        modifier(PBModernCardModifier(palette: palette))
    }

    func pbFlatCard(palette: PBTheme.Palette, cornerRadius: Double = PBLayout.radiusCard) -> some View {
        modifier(PBFlatCardModifier(palette: palette, cornerRadius: cornerRadius))
    }

    func pbSurfaceCard(palette: PBTheme.Palette, cornerRadius: Double = 12) -> some View {
        modifier(PBSurfaceCardModifier(palette: palette, cornerRadius: cornerRadius))
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
            .shadow(
                color: variant == .primary ?
                    Color.black.opacity(PBLayout.cardShadowOpacity) :
                    Color.black.opacity(PBLayout.cardAmbientOpacity),
                radius: PBLayout.cardShadowRadius * 0.75,
                x: 0,
                y: 2
            )
            .animation(PBLayout.quickAnimation, value: pressed)
    }
}

struct PBSectionHeaderLabel: View {
    let title: LocalizedStringKey
    var detail: LocalizedStringKey? = nil
    @Environment(\.pbTypography) private var type
    @Environment(\.pbTheme) private var theme
    @Environment(\.colorScheme) private var colorScheme

    private var palette: PBTheme.Palette { theme.resolvedPalette(for: colorScheme) }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(type.footnote.weight(.semibold))
                .foregroundStyle(palette.textPrimary.opacity(0.92))
                .textCase(.uppercase)
                .tracking(0.45)
            if let detail {
                Text(detail)
                    .font(type.footnote)
                    .foregroundStyle(palette.textSecondary)
            }
        }
    }
}

struct PBSkeletonCard: View {
    var lines: Int = 3
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(0..<max(1, lines), id: \.self) { index in
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.white.opacity(0.35))
                    .frame(
                        height: index == 0 ? 14 : 10
                    )
                    .frame(maxWidth: index == lines - 1 ? 180 : .infinity, alignment: .leading)
            }
        }
        .redacted(reason: .placeholder)
    }
}

enum PBHaptics {
    static func tap() {
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred(intensity: 0.75)
    }

    static func success() {
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
    }
}
