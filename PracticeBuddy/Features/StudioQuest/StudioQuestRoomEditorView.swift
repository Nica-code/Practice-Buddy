import SwiftUI

/// Full-screen studio editor.
///
/// Room editing used to live inside a scrolling settings-style page: a small
/// inset 3:2 preview, then a list of decoration rows, then a second list of
/// four-arrow nudge controls. You could not see the room you were arranging
/// while you arranged it. Here the scene is the screen, items are placed by
/// tapping the tray, and everything else is direct manipulation.
struct StudioQuestRoomEditorView: View {
    @EnvironmentObject private var journey: JourneyProgressManager
    @EnvironmentObject private var buddies: BuddiesViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("practiquest.avatar.loadout") private var loadoutData = Data()

    @State private var loadout = AvatarLoadout.starter(for: nil)
    @State private var selection: String?
    @State private var didLoad = false

    private var layout: StudioQuestRoomLayout { loadout.layout() }

    private var selectedPlacement: StudioQuestRoomPlacement? {
        guard let selection else { return nil }
        return layout.placements.first { $0.id == selection }
    }

    var body: some View {
        VStack(spacing: 0) {
            // The scene takes the space above the tray rather than the whole
            // screen, so the musician — anchored near the bottom of the room —
            // is never hidden behind the controls.
            StudioQuestAvatarScene(
                loadout: loadout,
                layout: layout,
                displayName: buddies.myProfile?.displayName ?? "Your musician",
                presentation: .hero,
                isEditing: true,
                externalSelection: $selection,
                onMove: { placement, point in move(placement, to: point) },
                onRemove: { remove($0) }
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay(alignment: .top) {
                LinearGradient(
                    colors: [.black.opacity(0.35), .clear],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 120)
                .allowsHitTesting(false)
            }
            .overlay(alignment: .top) { topBar }

            tray
        }
        .background(Color.black)
        .ignoresSafeArea(edges: .bottom)
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .onAppear {
            guard !didLoad else { return }
            didLoad = true
            loadout = (try? JSONDecoder().decode(AvatarLoadout.self, from: loadoutData))
                ?? .starter(for: buddies.myProfile?.avatarID)
        }
    }

    // MARK: - Chrome

    private var topBar: some View {
        HStack {
            Button {
                dismiss()
            } label: {
                Label("Done", systemImage: "checkmark")
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 14)
                    .frame(height: 38)
                    .background(.regularMaterial, in: Capsule())
            }
            .buttonStyle(.plain)

            Spacer()

            Menu {
                Picker("Room", selection: roomBinding) {
                    ForEach(StudioQuestAvatarRoom.catalog) { room in
                        Text(room.title).tag(room.id)
                    }
                }
            } label: {
                Label(StudioQuestAvatarRoom.room(for: loadout.roomID).title, systemImage: "photo")
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 14)
                    .frame(height: 38)
                    .background(.regularMaterial, in: Capsule())
            }
            .accessibilityLabel("Change room")
        }
        .padding(.horizontal, StudioQuestTokens.Spacing.md)
        .padding(.top, StudioQuestTokens.Spacing.sm)
        .padding(.bottom, StudioQuestTokens.Spacing.sm)
    }

    private var roomBinding: Binding<String> {
        Binding(
            get: { loadout.roomID },
            set: { newValue in
                selection = nil
                setLoadout { $0.roomID = newValue }
            }
        )
    }

    // MARK: - Tray

    @ViewBuilder
    private var tray: some View {
        VStack(spacing: 10) {
            if let placement = selectedPlacement,
               let decoration = StudioQuestRoomDecoration.decoration(for: placement.decorationID) {
                selectedControls(placement, decoration)
            } else {
                catalogStrip
            }
        }
        .padding(.horizontal, StudioQuestTokens.Spacing.md)
        .padding(.top, 12)
        .padding(.bottom, StudioQuestTokens.Spacing.md)
        .frame(maxWidth: .infinity)
        .background(.regularMaterial)
        .clipShape(
            UnevenRoundedRectangle(topLeadingRadius: 26, topTrailingRadius: 26, style: .continuous)
        )
        .animation(StudioQuestTokens.Motion.gentle, value: selection)
    }

    private var catalogStrip: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Place a decoration")
                    .font(StudioQuestTokens.Typography.cardTitle)
                Spacer()
                Label("\(journey.tokenBalance)", systemImage: "diamond.fill")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(StudioQuestTokens.ColorRole.cobalt)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(StudioQuestRoomDecoration.catalog) { decoration in
                        catalogTile(decoration)
                    }
                }
                .padding(.horizontal, 2)
                .padding(.bottom, 2)
            }

            Text("Tap to place, then drag it anywhere in its zone.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func catalogTile(_ decoration: StudioQuestRoomDecoration) -> some View {
        let owned = decoration.isStarter || journey.isRoomDecorationOwned(id: decoration.id)
        return Button {
            if owned {
                place(decoration)
            } else {
                Task { _ = await journey.purchaseRoomDecoration(id: decoration.id) }
            }
        } label: {
            VStack(spacing: 6) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(StudioQuestTokens.ColorRole.raisedSurface(colorScheme))
                    Image(decoration.assetName)
                        .resizable()
                        .scaledToFit()
                        .padding(10)
                        .opacity(owned ? 1 : 0.45)
                    if !owned {
                        Image(systemName: "lock.fill")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.secondary)
                            .padding(5)
                            .background(.thinMaterial, in: Circle())
                            .offset(x: 22, y: -22)
                    }
                }
                .frame(width: 72, height: 72)

                if owned {
                    Text(decoration.title)
                        .font(.caption2)
                        .lineLimit(1)
                        .foregroundStyle(.secondary)
                } else {
                    Label("\(decoration.costTokens)", systemImage: "diamond.fill")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(StudioQuestTokens.ColorRole.cobalt)
                }
            }
            .frame(width: 80)
        }
        .buttonStyle(.plain)
        .disabled(!owned && journey.tokenBalance < decoration.costTokens)
        .accessibilityLabel(
            owned
                ? "Place \(decoration.title)"
                : "Unlock \(decoration.title) for \(decoration.costTokens) tokens"
        )
    }

    private func selectedControls(
        _ placement: StudioQuestRoomPlacement,
        _ decoration: StudioQuestRoomDecoration
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(decoration.assetName)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 38, height: 38)
                VStack(alignment: .leading, spacing: 1) {
                    Text(decoration.title).font(StudioQuestTokens.Typography.cardTitle)
                    Text("\(decoration.zone.rawValue.capitalized) zone")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(role: .destructive) {
                    remove(placement)
                } label: {
                    Image(systemName: "trash")
                        .font(.headline)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Remove \(decoration.title)")
            }

            HStack(spacing: 12) {
                Image(systemName: "minus.magnifyingglass")
                    .foregroundStyle(.secondary)
                Slider(
                    value: scaleBinding(for: placement),
                    in: 0.7...1.4
                )
                .tint(StudioQuestTokens.ColorRole.cobalt)
                Image(systemName: "plus.magnifyingglass")
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Size")

            Button("Done editing this item") { selection = nil }
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
        }
    }

    private func scaleBinding(for placement: StudioQuestRoomPlacement) -> Binding<Double> {
        Binding(
            get: { placement.scale },
            set: { newValue in
                var next = layout
                guard let index = next.placements.firstIndex(where: { $0.id == placement.id }) else { return }
                next.placements[index].scale = min(max(newValue, 0.7), 1.4)
                next.updatedAt = .now
                setLoadout { $0.setLayout(next) }
            }
        )
    }

    // MARK: - Mutations

    private func place(_ decoration: StudioQuestRoomDecoration) {
        var next = layout
        let seed = Double(next.placements.count % 3) * 0.07
        let point = decoration.zone.clamped(
            .init(x: 0.27 + seed, y: decoration.zone == .wall ? 0.34 : 0.76)
        )
        let placement = StudioQuestRoomPlacement(
            decorationID: decoration.id,
            position: point,
            depth: decoration.zone == .floor ? -1 : 1
        )
        next.placements.append(placement)
        next.updatedAt = .now
        setLoadout { $0.setLayout(next) }
        selection = placement.id
    }

    private func move(_ placement: StudioQuestRoomPlacement, to point: StudioQuestRoomPoint) {
        guard let decoration = StudioQuestRoomDecoration.decoration(for: placement.decorationID) else { return }
        var next = layout
        guard let index = next.placements.firstIndex(where: { $0.id == placement.id }) else { return }
        next.placements[index].position = decoration.zone.clamped(point)
        next.updatedAt = .now
        setLoadout { $0.setLayout(next) }
    }

    private func remove(_ placement: StudioQuestRoomPlacement) {
        var next = layout
        next.placements.removeAll { $0.id == placement.id }
        next.updatedAt = .now
        selection = nil
        setLoadout { $0.setLayout(next) }
    }

    private func setLoadout(_ mutation: (inout AvatarLoadout) -> Void) {
        var next = loadout
        mutation(&next)
        next.version = AvatarLoadout.currentVersion
        let editedRoom = next.roomLayouts != loadout.roomLayouts
        loadout = next
        if let data = try? JSONEncoder().encode(next) {
            loadoutData = data
        }
        Task { await buddies.updateAvatarLoadout(next) }
        if editedRoom {
            PracticeAnalytics.record(.avatarRoomEdited)
        }
    }
}
