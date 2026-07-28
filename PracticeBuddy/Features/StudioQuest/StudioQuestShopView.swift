import SwiftUI

/// The token economy's storefront.
///
/// The shop used to exist only as the fourth segment of a picker inside Avatar
/// Studio, and `AppRoute.avatarStudio(section: .shop)` was never constructed
/// anywhere, so nothing in the app could actually route to it. It is now a
/// destination in its own right, reachable from the token chip in the Today and
/// Quest headers.
struct StudioQuestShopView: View {
    @EnvironmentObject private var journey: JourneyProgressManager
    @EnvironmentObject private var purchaseManager: PurchaseManager
    @EnvironmentObject private var router: AppRouter
    @Environment(\.colorScheme) private var colorScheme

    @State private var statusMessage: String?
    @State private var statusIsError = false

    var body: some View {
        StudioQuestScrollPage {
            VStack(alignment: .leading, spacing: StudioQuestTokens.Spacing.lg) {
                StudioQuestPageTitle(title: "Shop", subtitle: "Spend what your practice earned.")

                balanceCard

                if let statusMessage {
                    StudioQuestInlineStatus(
                        text: statusMessage,
                        kind: statusIsError ? .warning : .success
                    )
                    .transition(.opacity)
                }

                if let featured {
                    featuredSection(featured)
                }

                decorationsSection

                ForEach(JourneyRewardCategory.allCases) { category in
                    rewardSection(category)
                }

                if !purchaseManager.isPro {
                    proUpsell
                }
            }
            .padding(.top, StudioQuestTokens.Spacing.sm)
            .animation(StudioQuestTokens.Motion.gentle, value: statusMessage)
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Balance

    private var balanceCard: some View {
        HStack(spacing: StudioQuestTokens.Spacing.md) {
            ZStack {
                Circle().fill(StudioQuestTokens.ColorRole.cobalt.opacity(0.12))
                Image(systemName: "diamond.fill")
                    .font(.title3)
                    .foregroundStyle(StudioQuestTokens.ColorRole.cobalt)
            }
            .frame(width: 52, height: 52)

            VStack(alignment: .leading, spacing: 2) {
                Text("\(journey.tokenBalance)")
                    .font(StudioQuestTokens.Typography.heroTitle)
                    .contentTransition(.numericText())
                    .accessibilityLabel("\(journey.tokenBalance) tokens")
                Text("Tokens available")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            Button {
                router.popToRoot()
                router.selectedDestination = .quest
            } label: {
                Text("Earn more")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(StudioQuestTokens.ColorRole.cobalt)
            }
            .buttonStyle(.plain)
            .accessibilityHint("Goes to the Journey tab")
            .accessibilityIdentifier("shop.earnMore")
        }
        .padding(StudioQuestTokens.Spacing.md)
        .studioQuestSurface(.lifted)
        .animation(StudioQuestTokens.Motion.gentle, value: journey.tokenBalance)
    }

    // MARK: - Featured

    /// The cheapest thing the musician can afford but doesn't own yet — the item
    /// most likely to convert, rather than an arbitrary first entry.
    private var featured: StudioQuestRoomDecoration? {
        StudioQuestRoomDecoration.catalog
            .filter { !$0.isStarter && !journey.isRoomDecorationOwned(id: $0.id) }
            .sorted { $0.costTokens < $1.costTokens }
            .first { $0.costTokens <= journey.tokenBalance }
            ?? StudioQuestRoomDecoration.catalog
                .filter { !$0.isStarter && !journey.isRoomDecorationOwned(id: $0.id) }
                .min { $0.costTokens < $1.costTokens }
    }

    private func featuredSection(_ decoration: StudioQuestRoomDecoration) -> some View {
        VStack(alignment: .leading, spacing: StudioQuestTokens.Spacing.sm) {
            StudioQuestEyebrow("Featured")

            VStack(alignment: .leading, spacing: 0) {
                ZStack {
                    LinearGradient(
                        colors: [
                            StudioQuestTokens.ColorRole.cobalt.opacity(0.18),
                            StudioQuestTokens.ColorRole.violet.opacity(0.16)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    Image(decoration.assetName)
                        .resizable()
                        .scaledToFit()
                        .padding(StudioQuestTokens.Spacing.lg)
                }
                .frame(height: 190)
                .frame(maxWidth: .infinity)

                VStack(alignment: .leading, spacing: 10) {
                    Text(decoration.title)
                        .font(StudioQuestTokens.Typography.sectionTitle)
                    Text(decoration.subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    purchaseButton(for: decoration, prominent: true)
                }
                .padding(StudioQuestTokens.Spacing.md)
            }
            .studioQuestSurface(.lifted)
            .clipShape(
                RoundedRectangle(cornerRadius: StudioQuestTokens.Radius.surface, style: .continuous)
            )
        }
    }

    // MARK: - Decorations

    private var decorationsSection: some View {
        VStack(alignment: .leading, spacing: StudioQuestTokens.Spacing.sm) {
            StudioQuestEyebrow("Studio decorations")
            Text("Everything you place in your room.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            LazyVGrid(
                columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)],
                spacing: 12
            ) {
                ForEach(StudioQuestRoomDecoration.catalog) { decoration in
                    decorationTile(decoration)
                }
            }
        }
    }

    private func decorationTile(_ decoration: StudioQuestRoomDecoration) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack {
                StudioQuestTokens.ColorRole.raisedSurface(colorScheme)
                Image(decoration.assetName)
                    .resizable()
                    .scaledToFit()
                    .padding(14)
            }
            .frame(height: 108)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

            Text(decoration.title)
                .font(StudioQuestTokens.Typography.cardTitle)
                .lineLimit(1)

            purchaseButton(for: decoration, prominent: false)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .studioQuestSurface()
    }

    @ViewBuilder
    private func purchaseButton(for decoration: StudioQuestRoomDecoration, prominent: Bool) -> some View {
        let owned = decoration.isStarter || journey.isRoomDecorationOwned(id: decoration.id)
        let affordable = journey.tokenBalance >= decoration.costTokens

        if owned {
            Label("In your collection", systemImage: "checkmark.circle.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(StudioQuestTokens.ColorRole.mint)
                .frame(maxWidth: prominent ? .infinity : nil, alignment: .leading)
        } else {
            Button {
                purchase(decoration)
            } label: {
                if prominent {
                    Label("Unlock · \(decoration.costTokens)", systemImage: "diamond.fill")
                } else {
                    Label("\(decoration.costTokens)", systemImage: "diamond.fill")
                        .font(.caption.weight(.bold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 7)
                }
            }
            .buttonStyle(ShopBuyButtonStyle(prominent: prominent, enabled: affordable))
            .disabled(!affordable || journey.isEconomyOperationInProgress)
            .accessibilityLabel("Unlock \(decoration.title) for \(decoration.costTokens) tokens")
            .accessibilityHint(affordable ? "" : "You need more tokens")
            .accessibilityIdentifier("shop.decoration.\(decoration.id)")
        }
    }

    private func purchase(_ decoration: StudioQuestRoomDecoration) {
        Task {
            let success = await journey.purchaseRoomDecoration(id: decoration.id)
            statusIsError = !success
            statusMessage = success
                ? "\(decoration.title) is now in your collection."
                : "You need more tokens to unlock \(decoration.title)."
        }
    }

    // MARK: - Reward items

    @ViewBuilder
    private func rewardSection(_ category: JourneyRewardCategory) -> some View {
        let items = journey.rewards.filter { $0.category == category }
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: StudioQuestTokens.Spacing.sm) {
                StudioQuestEyebrow(LocalizedStringKey(category.title))
                ForEach(items) { item in
                    rewardRow(item)
                }
            }
        }
    }

    private func rewardRow(_ item: JourneyRewardItem) -> some View {
        HStack(spacing: StudioQuestTokens.Spacing.sm) {
            VStack(alignment: .leading, spacing: 3) {
                Text(item.title).font(StudioQuestTokens.Typography.cardTitle)
                Text(item.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            if item.isOwned {
                Label(item.isEquipped ? "Equipped" : "Owned", systemImage: "checkmark.circle.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(StudioQuestTokens.ColorRole.mint)
            } else {
                Button {
                    Task {
                        let success = await journey.claimRewardItem(id: item.id)
                        statusIsError = !success
                        statusMessage = success
                            ? "\(item.title) unlocked."
                            : "You need more tokens to unlock \(item.title)."
                    }
                } label: {
                    Label("\(item.costTokens)", systemImage: "diamond.fill")
                        .font(.caption.weight(.bold))
                }
                .buttonStyle(
                    ShopBuyButtonStyle(
                        prominent: false,
                        enabled: journey.tokenBalance >= item.costTokens
                    )
                )
                .disabled(journey.tokenBalance < item.costTokens || journey.isEconomyOperationInProgress)
                .accessibilityLabel("Unlock \(item.title) for \(item.costTokens) tokens")
            }
        }
        .padding(StudioQuestTokens.Spacing.md)
        .studioQuestSurface()
    }

    // MARK: - Pro

    private var proUpsell: some View {
        NavigationLink(value: AppRoute.pro(source: .avatarShop)) {
            HStack(spacing: StudioQuestTokens.Spacing.sm) {
                Image(systemName: "sparkles")
                    .font(.title3)
                    .foregroundStyle(StudioQuestTokens.ColorRole.gold)
                VStack(alignment: .leading, spacing: 2) {
                    Text("PractiQuest Pro")
                        .font(StudioQuestTokens.Typography.cardTitle)
                    Text("A monthly token allowance and premium collections.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
            }
            .foregroundStyle(.primary)
            .padding(StudioQuestTokens.Spacing.md)
            .studioQuestSurface()
        }
        .buttonStyle(.plain)
    }
}

private struct ShopBuyButtonStyle: ButtonStyle {
    let prominent: Bool
    let enabled: Bool

    @Environment(\.colorScheme) private var colorScheme

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(prominent ? .headline.weight(.semibold) : .caption.weight(.bold))
            .foregroundStyle(enabled ? .white : Color.secondary)
            .frame(maxWidth: prominent ? .infinity : nil)
            .padding(.vertical, prominent ? 14 : 7)
            .padding(.horizontal, prominent ? 0 : 12)
            .background {
                let shape = RoundedRectangle(
                    cornerRadius: prominent ? StudioQuestTokens.Radius.control : 9,
                    style: .continuous
                )
                if enabled {
                    shape.fill(
                        LinearGradient(
                            colors: [
                                StudioQuestTokens.ColorRole.cobalt,
                                StudioQuestTokens.ColorRole.violet
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                } else {
                    shape.fill(StudioQuestTokens.ColorRole.raisedSurface(colorScheme))
                }
            }
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(StudioQuestTokens.Motion.quick, value: configuration.isPressed)
    }
}

/// The always-visible currency affordance. Duolingo keeps its gem count in the
/// header of every screen precisely because a balance you can see is a balance
/// you want to spend; the balance here was previously buried three levels deep.
struct StudioQuestTokenChip: View {
    @EnvironmentObject private var journey: JourneyProgressManager
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        NavigationLink(value: AppRoute.shop) {
            HStack(spacing: 5) {
                Image(systemName: "diamond.fill")
                    .font(.caption.weight(.bold))
                    // Earning tokens elsewhere in the app should register here.
                    .symbolEffect(.bounce, value: journey.tokenBalance)
                Text("\(journey.tokenBalance)")
                    .font(.subheadline.weight(.bold))
                    .contentTransition(.numericText())
                    .monospacedDigit()
            }
            .foregroundStyle(StudioQuestTokens.ColorRole.cobalt)
            .padding(.horizontal, 11)
            .frame(height: 32)
            .background(
                StudioQuestTokens.ColorRole.cobalt.opacity(colorScheme == .dark ? 0.18 : 0.10),
                in: Capsule()
            )
        }
        .buttonStyle(.plain)
        .animation(StudioQuestTokens.Motion.gentle, value: journey.tokenBalance)
        .accessibilityLabel("\(journey.tokenBalance) tokens")
        .accessibilityHint("Opens the shop")
    }
}
