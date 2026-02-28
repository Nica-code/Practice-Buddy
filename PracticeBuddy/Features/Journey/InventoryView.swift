import SwiftUI

struct InventoryView: View {
    @EnvironmentObject private var journey: JourneyProgressManager
    @Environment(\.dismiss) private var dismiss
    @Environment(\.pbTheme) private var theme
    @Environment(\.pbTypography) private var type
    @Environment(\.colorScheme) private var colorScheme

    @State private var selectedCategory: JourneyRewardCategory = .cosmetics
    @State private var statusMessage: String?

    private var palette: PBTheme.Palette { theme.resolvedPalette(for: colorScheme) }
    private var ownedItems: [JourneyRewardItem] { journey.ownedRewards(in: selectedCategory) }

    var body: some View {
        List {
            Section {
                Picker("Category", selection: $selectedCategory) {
                    ForEach(JourneyRewardCategory.allCases) { category in
                        Text(category.title).tag(category)
                    }
                }
                .pickerStyle(.segmented)
            }
            .listRowBackground(Color.clear)

            if ownedItems.isEmpty {
                Section {
                    Text("No unlocked items in this category yet.")
                        .font(type.footnote)
                        .foregroundStyle(palette.textSecondary)
                }
                .listRowBackground(Color.clear)
            } else {
                Section {
                    ForEach(ownedItems) { item in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text(item.title)
                                    .font(type.body)
                                    .foregroundStyle(palette.textPrimary)
                                Spacer()
                                if item.isEquipped {
                                    Label("Equipped", systemImage: "checkmark.circle.fill")
                                        .font(type.footnote)
                                        .foregroundStyle(palette.accent)
                                }
                            }

                            Text(item.subtitle)
                                .font(type.footnote)
                                .foregroundStyle(palette.textSecondary)

                            Text(slotUsageLabel(for: item.slot))
                                .font(.caption)
                                .foregroundStyle(palette.textSecondary)

                            HStack(spacing: 10) {
                                if item.isEquipped {
                                    Button("Unequip") {
                                        Task {
                                            if await journey.unequipReward(slot: item.slot) {
                                                statusMessage = "Item unequipped."
                                            }
                                        }
                                    }
                                    .buttonStyle(.bordered)
                                    .disabled(journey.isEconomyOperationInProgress)
                                } else {
                                    Button("Equip") {
                                        Task {
                                            if await journey.equipRewardItem(id: item.id) {
                                                statusMessage = "Item equipped."
                                            }
                                        }
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .tint(palette.accent)
                                    .disabled(journey.isEconomyOperationInProgress)
                                }
                            }

                            if journey.isEconomyOperationInProgress {
                                HStack(spacing: 6) {
                                    ProgressView()
                                        .scaleEffect(0.8)
                                    Text("Updating...")
                                        .font(type.footnote)
                                }
                                .foregroundStyle(palette.textSecondary)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
                .listRowBackground(Color.clear)
            }

            if let statusMessage, !statusMessage.isEmpty {
                Section {
                    Text(statusMessage)
                        .font(type.footnote)
                        .foregroundStyle(palette.textSecondary)
                }
                .listRowBackground(Color.clear)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(PBBackdropView(palette: palette))
        .navigationTitle("Inventory")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Done") { dismiss() }
            }
        }
    }

    private func slotUsageLabel(for slot: JourneyRewardSlot) -> String {
        switch slot {
        case .profileFrame:
            return "Applies to: Profile top card frame"
        case .profileBanner:
            return "Applies to: Profile top card banner"
        case .profileGlow:
            return "Applies to: Profile top card glow"
        case .confettiStyle:
            return "Applies to: Reward claim celebrations"
        case .duelIntroCard:
            return "Applies to: Duel entry header"
        case .duelFinisherFX:
            return "Applies to: Duel completion effect"
        case .sessionCardSkin:
            return "Applies to: Play reward/result cards"
        case .metronomePack:
            return "Applies to: Metronome sound style"
        }
    }
}
