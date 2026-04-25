import SwiftUI
import UIKit

/// Centralized spacing + corner radius tokens so the UI feels consistent everywhere.
enum PBLayout {
    // Soft glass silhouette tokens used across the whole app.
    static let radiusControl: Double = 18
    static let radiusCard: Double = 24
    static let radiusSheet: Double = 30

    // Padding scale
    static let padXS: Double = 8
    static let padSM: Double = 12
    static let padMD: Double = 16
    static let padLG: Double = 18
    static let padXL: Double = 24

    // Surface depth tokens — tuned for the liquid-glass refresh.
    static let borderWidth: Double = 1.15
    static let cardShadowY: Double = 10.0
    static let cardShadowRadius: Double = 26.0
    static let cardShadowOpacity: Double = 0.20
    static let cardAmbientOpacity: Double = 0.08
    static let glassTintOpacity: Double = 0.40
    static let glassHighlightOpacity: Double = 0.72

    // Motion tokens
    static let quickAnimation = Animation.snappy(duration: 0.22, extraBounce: 0.04)
    static let springAnimation = Animation.spring(response: 0.34, dampingFraction: 0.84)
}

/// Animated, vibrant backdrop with flowing stage-light bands. It keeps every
/// screen connected without adding per-screen decorative code.
struct PBBackdropView: View {
    let palette: PBTheme.Palette

    @State private var driftPhase: Double = 0

    var body: some View {
        ZStack {
            Rectangle().fill(
                RadialGradient(
                    colors: [
                        palette.surfaceAlt.opacity(0.72),
                        palette.background.opacity(0.98),
                        palette.background
                    ],
                    center: .topLeading,
                    startRadius: 0,
                    endRadius: 760
                )
            )

            Rectangle().fill(
                LinearGradient(
                    colors: [
                        palette.accent.opacity(0.38),
                        palette.surface.opacity(0.10),
                        palette.surfaceAlt.opacity(0.24),
                        Color.white.opacity(0.14),
                        palette.background.opacity(0.0)
                    ],
                    startPoint: UnitPoint(x: 0.05 + sin(driftPhase) * 0.06, y: 0.04),
                    endPoint: UnitPoint(x: 0.92, y: 1.0 + cos(driftPhase) * 0.05)
                )
            )
            .blendMode(.plusLighter)
            .opacity(0.92)

            Rectangle().fill(
                AngularGradient(
                    colors: [
                        palette.accent.opacity(0.0),
                        palette.accent.opacity(0.16),
                        Color.white.opacity(0.20),
                        palette.surfaceAlt.opacity(0.18),
                        palette.accent.opacity(0.0)
                    ],
                    center: UnitPoint(x: 0.58 + sin(driftPhase * 0.45) * 0.08, y: 0.34)
                )
            )
            .blur(radius: 44)
            .opacity(0.78)
            .blendMode(.screen)

            Rectangle().fill(
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.22),
                        .clear,
                        palette.accent.opacity(0.12),
                        .clear
                    ],
                    startPoint: UnitPoint(x: 0.0, y: 0.16 + cos(driftPhase * 0.7) * 0.05),
                    endPoint: UnitPoint(x: 1.0, y: 0.86)
                )
            )
            .mask(
                LinearGradient(
                    colors: [.clear, .white.opacity(0.9), .clear],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .blendMode(.plusLighter)

            LinearGradient(
                colors: [
                    .clear,
                    Color.black.opacity(0.045)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .blendMode(.multiply)

            Rectangle()
                .fill(Color.white.opacity(0.035))
                .background(.ultraThinMaterial.opacity(0.14))
                .mask(
                    LinearGradient(
                        colors: [.white.opacity(0.35), .clear],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .blendMode(.plusLighter)
        }
        .ignoresSafeArea()
        .onAppear {
            withAnimation(.easeInOut(duration: 18).repeatForever(autoreverses: true)) {
                driftPhase = .pi * 2
            }
        }
    }
}

/// The star of the makeover: a layered liquid-glass surface.
/// Material base → tinted gradient sheen → bright bevel stroke → inner top highlight.
private struct PBGlassSurface: View {
    let palette: PBTheme.Palette
    let cornerRadius: Double
    let tintOpacity: Double
    let strokeOpacity: Double

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        ZStack {
            shape.fill(.ultraThinMaterial)

            shape.fill(
                LinearGradient(
                    colors: [
                        Color.white.opacity(min(0.56, tintOpacity * 1.22)),
                        palette.surface.opacity(max(0.12, tintOpacity * 0.62)),
                        palette.surfaceAlt.opacity(max(0.10, tintOpacity * 0.48)),
                        palette.accent.opacity(max(0.08, tintOpacity * 0.40))
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .blendMode(.plusLighter)

            shape.fill(
                LinearGradient(
                    colors: [
                        .clear,
                        Color.white.opacity(0.16),
                        .clear
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .blendMode(.screen)

            shape.stroke(
                LinearGradient(
                    colors: [
                        Color.white.opacity(PBLayout.glassHighlightOpacity),
                        palette.accent.opacity(strokeOpacity * 1.25),
                        Color.white.opacity(0.18),
                        palette.accent.opacity(strokeOpacity * 0.75)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                lineWidth: PBLayout.borderWidth
            )

            shape
                .inset(by: 0.5)
                .stroke(
                    LinearGradient(
                        colors: [Color.white.opacity(0.70), .clear],
                        startPoint: .top,
                        endPoint: .center
                    ),
                    lineWidth: 0.8
                )
                .blendMode(.screen)
                .allowsHitTesting(false)
        }
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
                    strokeOpacity: 0.42
                )
            )
            .shadow(
                color: palette.accent.opacity(PBLayout.cardShadowOpacity),
                radius: PBLayout.cardShadowRadius,
                x: 0,
                y: PBLayout.cardShadowY
            )
            .shadow(
                color: Color.white.opacity(0.10),
                radius: 3,
                x: 0,
                y: -1
            )
            .shadow(
                color: Color.black.opacity(PBLayout.cardAmbientOpacity),
                radius: 4,
                x: 0,
                y: 3
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
                    tintOpacity: PBLayout.glassTintOpacity * 0.88,
                    strokeOpacity: 0.28
                )
            )
            .shadow(
                color: palette.accent.opacity(0.10),
                radius: 10,
                x: 0,
                y: 4
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
                    tintOpacity: PBLayout.glassTintOpacity * 0.72,
                    strokeOpacity: 0.24
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
        let foregroundColor: Color = {
            switch variant {
            case .primary:   return Color.white
            case .secondary: return palette.textPrimary
            }
        }()

        return configuration.label
            .foregroundStyle(foregroundColor)
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .background(
                ZStack {
                    let shape = RoundedRectangle(cornerRadius: PBLayout.radiusControl, style: .continuous)
                    switch variant {
                    case .primary:
                        shape.fill(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.18),
                                    palette.accent.opacity(pressed ? 0.92 : 1.0),
                                    palette.accent.opacity(pressed ? 0.66 : 0.76),
                                    Color.black.opacity(0.10)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        shape
                            .inset(by: 0.5)
                            .stroke(
                                LinearGradient(
                                    colors: [Color.white.opacity(0.65), .clear],
                                    startPoint: .top,
                                    endPoint: .center
                                ),
                                lineWidth: 0.9
                            )
                            .blendMode(.screen)
                    case .secondary:
                        shape.fill(.ultraThinMaterial)
                        shape.fill(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.24),
                                    palette.surfaceAlt.opacity(pressed ? 0.60 : 0.46),
                                    palette.accent.opacity(pressed ? 0.18 : 0.11)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                            .blendMode(.plusLighter)
                        shape.stroke(palette.accent.opacity(0.42), lineWidth: 1)
                    }
                }
            )
            .scaleEffect(pressed ? 0.97 : 1.0)
            .shadow(
                color: variant == .primary ?
                    palette.accent.opacity(pressed ? 0.18 : 0.34) :
                    Color.black.opacity(PBLayout.cardAmbientOpacity),
                radius: variant == .primary ? 18 : 8,
                x: 0,
                y: variant == .primary ? 9 : 3
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
                .font(type.footnote.weight(.bold))
                .foregroundStyle(palette.textPrimary.opacity(0.95))
                .textCase(.uppercase)
                .tracking(0.9)
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
