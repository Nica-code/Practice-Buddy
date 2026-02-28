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
            .clipShape(RoundedRectangle(cornerRadius: PBLayout.radiusCard, style: .continuous))
            .background(
                RoundedRectangle(cornerRadius: PBLayout.radiusCard, style: .continuous)
                    .fill(palette.surface.opacity(0.96))
                    .overlay(
                        RoundedRectangle(cornerRadius: PBLayout.radiusCard, style: .continuous)
                            .stroke(palette.accent.opacity(0.15), lineWidth: PBLayout.borderWidth)
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
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(palette.surface.opacity(0.96))
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .stroke(palette.accent.opacity(0.15), lineWidth: PBLayout.borderWidth)
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
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(palette.surfaceAlt.opacity(0.94))
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .stroke(palette.accent.opacity(0.12), lineWidth: PBLayout.borderWidth)
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
