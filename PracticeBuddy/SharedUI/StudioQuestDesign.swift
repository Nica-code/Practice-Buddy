import SwiftUI

enum StudioQuestTokens {
    enum ColorRole {
        static let cobalt = Color(red: 0.12, green: 0.31, blue: 0.98)
        static let violet = Color(red: 0.42, green: 0.25, blue: 0.92)
        static let mint = Color(red: 0.10, green: 0.66, blue: 0.43)
        static let coral = Color(red: 0.95, green: 0.35, blue: 0.27)
        static let gold = Color(red: 0.86, green: 0.61, blue: 0.17)

        static func background(_ scheme: ColorScheme) -> Color {
            scheme == .dark
                ? Color(red: 0.035, green: 0.052, blue: 0.075)
                : Color(red: 0.985, green: 0.975, blue: 0.945)
        }

        static func surface(_ scheme: ColorScheme) -> Color {
            scheme == .dark
                ? Color(red: 0.060, green: 0.084, blue: 0.112)
                : Color(red: 1.0, green: 0.995, blue: 0.975)
        }

        static func raisedSurface(_ scheme: ColorScheme) -> Color {
            scheme == .dark
                ? Color(red: 0.085, green: 0.112, blue: 0.145)
                : Color(red: 0.965, green: 0.950, blue: 0.905)
        }

        static func separator(_ scheme: ColorScheme) -> Color {
            scheme == .dark ? .white.opacity(0.10) : .black.opacity(0.09)
        }
    }

    enum Spacing {
        static let xs: CGFloat = 6
        static let sm: CGFloat = 10
        static let md: CGFloat = 16
        static let lg: CGFloat = 24
        static let xl: CGFloat = 32
        static let pageMaxWidth: CGFloat = 680

        static func pageMargin(for width: CGFloat) -> CGFloat {
            width >= 430 ? 20 : 16
        }
    }

    enum Radius {
        static let control: CGFloat = 14
        static let surface: CGFloat = 20
        static let dock: CGFloat = 22
        static let hero: CGFloat = 26
    }

    enum Motion {
        static let quick = Animation.snappy(duration: 0.22, extraBounce: 0.03)
        static let gentle = Animation.spring(response: 0.42, dampingFraction: 0.88)
    }

    /// How far a surface sits off the page.
    ///
    /// Light and dark need different mechanisms for the same perception: a cast
    /// shadow reads as lift on a light canvas but disappears on a dark one,
    /// where lift instead comes from the surface being lighter than what's
    /// behind it plus a hairline catching the "light" along the top edge.
    enum Elevation {
        case flat
        /// Cards, list surfaces, anything sitting directly on the page.
        case resting
        /// Floating chrome: the practice dock, popovers, sheets.
        case lifted

        func shadowColor(_ scheme: ColorScheme) -> Color {
            guard scheme == .light else { return .clear }
            switch self {
            case .flat: return .clear
            case .resting: return .black.opacity(0.06)
            case .lifted: return .black.opacity(0.11)
            }
        }

        var shadowRadius: CGFloat {
            switch self {
            case .flat: 0
            case .resting: 10
            case .lifted: 22
            }
        }

        var shadowY: CGFloat {
            switch self {
            case .flat: 0
            case .resting: 3
            case .lifted: 8
            }
        }

        /// In dark mode the border carries the lift, so it strengthens with
        /// elevation instead of staying a uniform hairline.
        func borderColor(_ scheme: ColorScheme) -> Color {
            guard scheme == .dark else { return ColorRole.separator(scheme) }
            switch self {
            case .flat: return .white.opacity(0.06)
            case .resting: return .white.opacity(0.10)
            case .lifted: return .white.opacity(0.16)
            }
        }
    }

    enum Typography {
        /// Space Grotesk ships as four separately drawn files. Asking for a
        /// weight the loaded face does not contain makes CoreText synthesize it
        /// by smearing the outline, so every display role names the file that is
        /// genuinely cut at that weight instead of calling `.weight()`.
        enum Face: String {
            case regular = "SpaceGrotesk-Regular"
            case medium = "SpaceGrotesk-Medium"
            case semibold = "SpaceGrotesk-SemiBold"
            case bold = "SpaceGrotesk-Bold"
        }

        /// Display type only. Body copy stays on the system font: Space Grotesk
        /// has no Hangul, and PractiQuest ships Korean.
        static func display(
            _ size: CGFloat,
            _ face: Face = .bold,
            relativeTo style: Font.TextStyle = .body
        ) -> Font {
            .custom(face.rawValue, size: size, relativeTo: style)
        }

        static let pageTitle = display(34, .bold, relativeTo: .largeTitle)
        static let heroTitle = display(28, .bold, relativeTo: .title)
        static let sectionTitle = display(20, .semibold, relativeTo: .title3)
        static let cardTitle = display(17, .semibold, relativeTo: .headline)
        static let statValue = display(22, .medium, relativeTo: .title2)
        static let timer = Font.system(size: 62, weight: .medium, design: .monospaced)
        static let measurement = Font.system(.body, design: .monospaced)

        /// Uppercase eyebrow above a section. Tracking is applied at the call
        /// site via `studioQuestEyebrow()`.
        static let eyebrow = Font.system(.caption, design: .default).weight(.semibold)
    }
}

private struct StudioQuestDockClearanceKey: EnvironmentKey {
    static let defaultValue: CGFloat = 104
}

extension EnvironmentValues {
    var studioQuestDockClearance: CGFloat {
        get { self[StudioQuestDockClearanceKey.self] }
        set { self[StudioQuestDockClearanceKey.self] = newValue }
    }
}

struct StudioQuestScrollPage<Content: View>: View {
    @Environment(\.studioQuestDockClearance) private var dockClearance
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private let showsIndicators: Bool
    private let content: Content

    init(
        showsIndicators: Bool = false,
        @ViewBuilder content: () -> Content
    ) {
        self.showsIndicators = showsIndicators
        self.content = content()
    }

    var body: some View {
        GeometryReader { proxy in
            let margin = horizontalSizeClass == .regular
                ? 20
                : StudioQuestTokens.Spacing.pageMargin(for: proxy.size.width)
            let availableWidth = max(
                0,
                min(
                    StudioQuestTokens.Spacing.pageMaxWidth,
                    proxy.size.width - (margin * 2)
                )
            )

            ZStack {
                StudioQuestBackground()
                ScrollView(.vertical, showsIndicators: showsIndicators) {
                    content
                        .frame(width: availableWidth, alignment: .leading)
                        .padding(.horizontal, margin)
                        .padding(.bottom, dockClearance + StudioQuestTokens.Spacing.lg)
                }
                .scrollClipDisabled(false)
            }
        }
    }
}

struct StudioQuestPageTitle: View {
    let title: LocalizedStringKey
    var subtitle: LocalizedStringKey?

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(StudioQuestTokens.Typography.pageTitle)
                .tracking(-1)
            if let subtitle {
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(StudioQuestTokens.ColorRole.violet)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// Gives a view the standard card treatment: surface fill, continuous corner,
/// elevation-aware border and shadow. Replaces the fill-plus-hairline that was
/// repeated inline across the destinations, which is why cards read as flat
/// tinted rectangles rather than as surfaces.
struct StudioQuestSurfaceModifier: ViewModifier {
    var elevation: StudioQuestTokens.Elevation = .resting
    var cornerRadius: CGFloat = StudioQuestTokens.Radius.surface

    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        content
            .background(StudioQuestTokens.ColorRole.surface(colorScheme), in: shape)
            .overlay {
                shape.stroke(elevation.borderColor(colorScheme), lineWidth: 0.75)
            }
            .shadow(
                color: elevation.shadowColor(colorScheme),
                radius: elevation.shadowRadius,
                y: elevation.shadowY
            )
    }
}

extension View {
    func studioQuestSurface(
        _ elevation: StudioQuestTokens.Elevation = .resting,
        cornerRadius: CGFloat = StudioQuestTokens.Radius.surface
    ) -> some View {
        modifier(StudioQuestSurfaceModifier(elevation: elevation, cornerRadius: cornerRadius))
    }
}

/// The small uppercase label that introduces a section. Previously each
/// destination re-declared its own `sectionLabel`, which let the tracking and
/// colour drift apart between tabs.
struct StudioQuestEyebrow: View {
    let text: LocalizedStringKey

    init(_ text: LocalizedStringKey) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(StudioQuestTokens.Typography.eyebrow)
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
            .tracking(0.6)
            .accessibilityAddTraits(.isHeader)
    }
}

struct StudioQuestRowSurface<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .studioQuestSurface()
    }
}

struct StudioQuestBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        StudioQuestTokens.ColorRole.background(colorScheme)
            .ignoresSafeArea()
    }
}

struct StudioQuestDockMaterial: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorScheme) private var colorScheme

    @ViewBuilder
    func body(content: Content) -> some View {
        let shape = RoundedRectangle(
            cornerRadius: StudioQuestTokens.Radius.dock,
            style: .continuous
        )

        if reduceTransparency {
            content.background(StudioQuestTokens.ColorRole.surface(colorScheme), in: shape)
        } else if #available(iOS 26.0, *) {
            content.glassEffect(.regular.interactive(), in: .rect(cornerRadius: StudioQuestTokens.Radius.dock))
        } else {
            content.background(.regularMaterial, in: shape)
        }
    }
}

/// Applies the Studio Quest canvas and accent to utility views that manage
/// their own scrolling, including the compact Metronome and Tuner tools.
struct StudioQuestToolChrome: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content
            .scrollContentBackground(.hidden)
            .background(StudioQuestTokens.ColorRole.background(colorScheme).ignoresSafeArea())
            .tint(StudioQuestTokens.ColorRole.cobalt)
    }
}

#if DEBUG
struct StudioQuestQAStateOverlay: View {
    let state: String

    var body: some View {
        switch state {
        case "loading":
            ZStack {
                StudioQuestBackground()
                ProgressView("Loading your practice world…")
                    .controlSize(.large)
            }
        case "offline":
            VStack {
                StudioQuestInlineStatus(
                    text: "Offline — saved practice remains available.",
                    kind: .warning
                )
                .padding(.horizontal, StudioQuestTokens.Spacing.md)
                .padding(.top, StudioQuestTokens.Spacing.sm)
                Spacer()
            }
            .allowsHitTesting(false)
        case "error":
            VStack {
                StudioQuestInlineStatus(
                    text: "We couldn’t refresh this screen. Pull to try again.",
                    kind: .error
                )
                .padding(.horizontal, StudioQuestTokens.Spacing.md)
                .padding(.top, StudioQuestTokens.Spacing.sm)
                Spacer()
            }
            .allowsHitTesting(false)
        default:
            EmptyView()
        }
    }
}
#endif

struct StudioQuestSection<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        content
            .padding(StudioQuestTokens.Spacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .studioQuestSurface()
    }
}

struct StudioQuestInteractiveSurface<Content: View>: View {
    let isEnabled: Bool
    let action: () -> Void
    let content: Content

    init(
        isEnabled: Bool = true,
        action: @escaping () -> Void,
        @ViewBuilder content: () -> Content
    ) {
        self.isEnabled = isEnabled
        self.action = action
        self.content = content()
    }

    var body: some View {
        Button(action: action) {
            content
                .contentShape(RoundedRectangle(cornerRadius: StudioQuestTokens.Radius.surface, style: .continuous))
        }
        .buttonStyle(StudioQuestSurfaceButtonStyle())
        .disabled(!isEnabled)
    }
}

private struct StudioQuestSurfaceButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.88 : 1)
            .scaleEffect(configuration.isPressed ? 0.988 : 1)
            .animation(StudioQuestTokens.Motion.quick, value: configuration.isPressed)
    }
}

struct StudioQuestLoadingState: View {
    let title: LocalizedStringKey
    var body: some View {
        VStack(spacing: 12) {
            ProgressView().controlSize(.large)
            Text(title).font(.subheadline).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 180)
        .accessibilityElement(children: .combine)
    }
}

struct StudioQuestEmptyState: View {
    let title: LocalizedStringKey
    let message: LocalizedStringKey
    let systemImage: String
    var actionTitle: LocalizedStringKey = "Explore community"
    let action: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(StudioQuestTokens.ColorRole.cobalt)
            Text(title).font(.headline)
            Text(message).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
            Button(actionTitle, action: action)
                .buttonStyle(StudioQuestSecondaryButtonStyle())
                .frame(maxWidth: 260)
        }
        .padding(StudioQuestTokens.Spacing.xl)
        .frame(maxWidth: .infinity)
        .studioQuestSurface()
        .accessibilityElement(children: .combine)
    }
}

struct StudioQuestPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline.weight(.semibold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .background(
                LinearGradient(
                    colors: [
                        StudioQuestTokens.ColorRole.cobalt,
                        StudioQuestTokens.ColorRole.violet
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                ),
                in: RoundedRectangle(cornerRadius: StudioQuestTokens.Radius.control, style: .continuous)
            )
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .opacity(configuration.isPressed ? 0.9 : 1)
            .animation(StudioQuestTokens.Motion.quick, value: configuration.isPressed)
    }
}

struct StudioQuestSecondaryButtonStyle: ButtonStyle {
    @Environment(\.colorScheme) private var colorScheme

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline.weight(.semibold))
            .foregroundStyle(StudioQuestTokens.ColorRole.cobalt)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                StudioQuestTokens.ColorRole.surface(colorScheme),
                in: RoundedRectangle(cornerRadius: StudioQuestTokens.Radius.control, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: StudioQuestTokens.Radius.control, style: .continuous)
                    .stroke(StudioQuestTokens.ColorRole.cobalt.opacity(0.28), lineWidth: 1)
            }
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .opacity(configuration.isPressed ? 0.88 : 1)
            .animation(StudioQuestTokens.Motion.quick, value: configuration.isPressed)
    }
}

struct StudioQuestInlineStatus: View {
    enum Kind {
        case success
        case warning
        case error
        case information

        var color: Color {
            switch self {
            case .success: StudioQuestTokens.ColorRole.mint
            case .warning: StudioQuestTokens.ColorRole.gold
            case .error: StudioQuestTokens.ColorRole.coral
            case .information: StudioQuestTokens.ColorRole.cobalt
            }
        }

        var systemImage: String {
            switch self {
            case .success: "checkmark.circle.fill"
            case .warning: "exclamationmark.triangle.fill"
            case .error: "xmark.octagon.fill"
            case .information: "info.circle.fill"
            }
        }
    }

    let text: String
    var kind: Kind = .information
    private var overrideSystemImage: String?
    private var overrideTint: Color?

    init(text: String, kind: Kind = .information) {
        self.text = text
        self.kind = kind
        self.overrideSystemImage = nil
        self.overrideTint = nil
    }

    init(title: String, systemImage: String, tint: Color) {
        self.text = title
        self.kind = .information
        self.overrideSystemImage = systemImage
        self.overrideTint = tint
    }

    var body: some View {
        let tint = overrideTint ?? kind.color
        Label(text, systemImage: overrideSystemImage ?? kind.systemImage)
            .font(.subheadline)
            .foregroundStyle(tint)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(tint.opacity(0.10), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .accessibilityElement(children: .combine)
    }
}

struct StudioQuestVerifiedLabel: View {
    let isVerified: Bool

    var body: some View {
        Label(isVerified ? "Verified" : "Standard", systemImage: isVerified ? "checkmark.shield.fill" : "shield")
            .font(.caption.weight(.semibold))
            .foregroundStyle(isVerified ? StudioQuestTokens.ColorRole.mint : .secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.thinMaterial, in: Capsule())
            .accessibilityLabel(isVerified ? "Practice verification active" : "Practice verification inactive")
    }
}

struct StudioQuestWordmark: View {
    var compact = false

    var body: some View {
        HStack(spacing: 9) {
            ZStack {
                Circle()
                    .trim(from: 0.08, to: 0.86)
                    .stroke(
                        LinearGradient(
                            colors: [StudioQuestTokens.ColorRole.cobalt, StudioQuestTokens.ColorRole.violet],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        style: StrokeStyle(lineWidth: compact ? 3 : 4, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-35))
                Image(systemName: "music.note")
                    .font(.system(size: compact ? 10 : 13, weight: .bold))
                    .foregroundStyle(StudioQuestTokens.ColorRole.cobalt)
            }
            .frame(width: compact ? 24 : 30, height: compact ? 24 : 30)

            if !compact {
                Text("PractiQuest")
                    .font(.title3.weight(.bold))
                    .tracking(-0.4)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("PractiQuest")
    }
}
