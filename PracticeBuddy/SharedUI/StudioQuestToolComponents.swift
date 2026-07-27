import SwiftUI

struct StudioQuestToolPage<Content: View>: View {
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey
    let systemImage: String
    let content: Content

    init(
        title: LocalizedStringKey,
        subtitle: LocalizedStringKey,
        systemImage: String,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.content = content()
    }

    var body: some View {
        StudioQuestScrollPage {
            VStack(alignment: .leading, spacing: StudioQuestTokens.Spacing.lg) {
                StudioQuestToolHero(
                    title: title,
                    subtitle: subtitle,
                    systemImage: systemImage
                )
                content
            }
            .padding(.top, StudioQuestTokens.Spacing.md)
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct StudioQuestToolHero: View {
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey
    let systemImage: String

    var body: some View {
        HStack(alignment: .top, spacing: StudioQuestTokens.Spacing.md) {
            Image(systemName: systemImage)
                .font(.system(size: 21, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 48, height: 48)
                .background(StudioQuestTokens.ColorRole.cobalt, in: RoundedRectangle(cornerRadius: 15, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(StudioQuestTokens.Typography.heroTitle)
                    .tracking(-0.6)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

struct StudioQuestToolSetupPanel<Content: View>: View {
    let title: LocalizedStringKey
    let content: Content

    init(
        title: LocalizedStringKey = "Setup",
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: StudioQuestTokens.Spacing.md) {
            StudioQuestEyebrow(title)
            content
        }
        .padding(StudioQuestTokens.Spacing.md)
        .studioQuestSurface()
    }
}

struct StudioQuestToolLivePanel<Content: View>: View {
    let eyebrow: LocalizedStringKey
    let content: Content

    init(
        eyebrow: LocalizedStringKey = "Now",
        @ViewBuilder content: () -> Content
    ) {
        self.eyebrow = eyebrow
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: StudioQuestTokens.Spacing.md) {
            StudioQuestEyebrow(eyebrow)
            content
        }
        .padding(StudioQuestTokens.Spacing.md)
        .studioQuestSurface(.lifted)
    }
}

struct StudioQuestToolResultPanel<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: StudioQuestTokens.Spacing.md) {
            StudioQuestEyebrow("Result")
            content
        }
        .padding(StudioQuestTokens.Spacing.md)
        .studioQuestSurface()
    }
}

struct StudioQuestToolControlShelf<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .frame(maxWidth: .infinity)
            .padding(StudioQuestTokens.Spacing.sm)
            .modifier(StudioQuestDockMaterial())
    }
}

struct StudioQuestMetric: View {
    let title: LocalizedStringKey
    let value: String
    var detail: LocalizedStringKey?
    var tint: Color = StudioQuestTokens.ColorRole.cobalt

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(StudioQuestTokens.Typography.statValue)
                .foregroundStyle(tint)
                .monospacedDigit()
            if let detail {
                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

struct StudioQuestProgressVisualization: View {
    let progress: Double
    let accessibilityLabel: String

    var body: some View {
        ProgressView(value: min(max(progress, 0), 1))
            .tint(StudioQuestTokens.ColorRole.cobalt)
            .accessibilityLabel(accessibilityLabel)
            .accessibilityValue("\(Int(min(max(progress, 0), 1) * 100)) percent")
    }
}

struct StudioQuestPermissionState: View {
    let title: LocalizedStringKey
    let message: LocalizedStringKey
    let systemImage: String
    let actionTitle: LocalizedStringKey
    let action: () -> Void

    var body: some View {
        VStack(spacing: StudioQuestTokens.Spacing.md) {
            Image(systemName: systemImage)
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(StudioQuestTokens.ColorRole.cobalt)
            Text(title)
                .font(StudioQuestTokens.Typography.cardTitle)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button(actionTitle, action: action)
                .buttonStyle(StudioQuestPrimaryButtonStyle())
        }
        .padding(StudioQuestTokens.Spacing.lg)
        .frame(maxWidth: .infinity)
        .studioQuestSurface()
    }
}

struct StudioQuestRecoveryBanner: View {
    let message: String
    let resume: () -> Void
    let discard: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: StudioQuestTokens.Spacing.sm) {
            Label("Practice ready to resume", systemImage: "arrow.counterclockwise.circle.fill")
                .font(StudioQuestTokens.Typography.cardTitle)
                .foregroundStyle(StudioQuestTokens.ColorRole.cobalt)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            HStack {
                Button("Discard", role: .destructive, action: discard)
                    .buttonStyle(StudioQuestSecondaryButtonStyle())
                Button("Resume", action: resume)
                    .buttonStyle(StudioQuestPrimaryButtonStyle())
            }
        }
        .padding(StudioQuestTokens.Spacing.md)
        .studioQuestSurface()
    }
}

struct StudioQuestChoiceChip: View {
    let title: LocalizedStringKey
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(isSelected ? .white : .primary)
                .padding(.horizontal, 13)
                .frame(minHeight: 44)
                .background(
                    isSelected
                        ? StudioQuestTokens.ColorRole.cobalt
                        : Color.clear,
                    in: Capsule()
                )
                .overlay {
                    if !isSelected {
                        Capsule()
                            .stroke(StudioQuestTokens.ColorRole.cobalt.opacity(0.24), lineWidth: 1)
                    }
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// A real wrapping layout for chips and marker controls. The prior `FlowRow`
/// was a VStack, which made every tag consume a full row.
struct StudioQuestFlowLayout: Layout {
    var spacing: CGFloat = StudioQuestTokens.Spacing.sm

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        let width = proposal.width ?? 0
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + (x == 0 ? 0 : spacing)
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: width, height: y + rowHeight)
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(
                at: CGPoint(x: x, y: y),
                anchor: .topLeading,
                proposal: ProposedViewSize(size)
            )
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
