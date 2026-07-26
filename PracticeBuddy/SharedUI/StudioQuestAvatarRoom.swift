import SwiftUI

/// A stable, resolution-independent location inside an avatar room.
/// Values are clamped by the room zone before persistence so a layout adapts to
/// every iPhone width without allowing an item to drift outside its scene.
struct StudioQuestRoomPoint: Codable, Hashable {
    var x: Double
    var y: Double
}

enum StudioQuestRoomZone: String, Codable, CaseIterable, Hashable {
    case floor
    case wall
    case surface

    func clamped(_ point: StudioQuestRoomPoint) -> StudioQuestRoomPoint {
        let x = min(max(point.x, 0.06), 0.94)
        let yRange: ClosedRange<Double>
        switch self {
        case .floor: yRange = 0.54...0.92
        case .wall: yRange = 0.14...0.60
        case .surface: yRange = 0.32...0.74
        }
        return StudioQuestRoomPoint(x: x, y: min(max(point.y, yRange.lowerBound), yRange.upperBound))
    }
}

struct StudioQuestRoomPlacement: Identifiable, Codable, Hashable {
    var id: String
    var decorationID: String
    var position: StudioQuestRoomPoint
    var scale: Double
    var rotationDegrees: Double
    var depth: Int

    init(
        id: String = UUID().uuidString,
        decorationID: String,
        position: StudioQuestRoomPoint,
        scale: Double = 1,
        rotationDegrees: Double = 0,
        depth: Int = 0
    ) {
        self.id = id
        self.decorationID = decorationID
        self.position = position
        self.scale = min(max(scale, 0.7), 1.4)
        self.rotationDegrees = min(max(rotationDegrees, -8), 8)
        self.depth = max(-10, min(depth, 10))
    }
}

struct StudioQuestRoomLayout: Codable, Hashable {
    var roomID: String
    var placements: [StudioQuestRoomPlacement]
    var updatedAt: Date

    init(roomID: String, placements: [StudioQuestRoomPlacement] = [], updatedAt: Date = .now) {
        self.roomID = roomID
        self.placements = placements
        self.updatedAt = updatedAt
    }
}

struct StudioQuestAvatarRoom: Identifiable, Hashable {
    let id: String
    let title: String
    let backgroundAsset: String
    let avatarAnchor: StudioQuestRoomPoint
    let subtitle: String

    static let catalog: [StudioQuestAvatarRoom] = [
        .init(
            id: "room_daylight_studio",
            title: "Daylight studio",
            backgroundAsset: "StudioQuestRoomDaylight",
            avatarAnchor: .init(x: 0.52, y: 0.77),
            subtitle: "A warm, open room ready for your first pieces."
        ),
        .init(
            id: "room_midnight_stage",
            title: "Midnight room",
            backgroundAsset: "StudioQuestRoomMidnight",
            avatarAnchor: .init(x: 0.54, y: 0.77),
            subtitle: "A focused space for late-night rehearsal."
        ),
        .init(
            id: "room_creative_loft",
            title: "Creative loft",
            backgroundAsset: "StudioQuestRoomLoft",
            avatarAnchor: .init(x: 0.53, y: 0.78),
            subtitle: "A bright blank canvas for your collection."
        )
    ]

    static func room(for id: String) -> StudioQuestAvatarRoom {
        catalog.first(where: { $0.id == id }) ?? catalog[0]
    }
}

struct StudioQuestRoomDecoration: Identifiable, Hashable {
    let id: String
    let title: String
    let subtitle: String
    let assetName: String
    let systemImage: String
    let zone: StudioQuestRoomZone
    let defaultWidth: Double
    let costTokens: Int
    let isStarter: Bool

    static let catalog: [StudioQuestRoomDecoration] = [
        .init(
            id: "room_decoration_plant",
            title: "Cobalt plant",
            subtitle: "A calm floor companion.",
            assetName: "StudioQuestDecorationPlant",
            systemImage: "leaf.fill",
            zone: .floor,
            defaultWidth: 0.23,
            costTokens: 0,
            isStarter: true
        ),
        .init(
            id: "room_decoration_rug",
            title: "Practice rug",
            subtitle: "A woven place for focused work.",
            assetName: "StudioQuestDecorationRug",
            systemImage: "rectangle.portrait.on.rectangle.portrait",
            zone: .floor,
            defaultWidth: 0.42,
            costTokens: 35,
            isStarter: false
        ),
        .init(
            id: "room_decoration_lamp",
            title: "Violet floor lamp",
            subtitle: "A warm after-hours glow.",
            assetName: "StudioQuestDecorationLamp",
            systemImage: "lamp.floor.fill",
            zone: .floor,
            defaultWidth: 0.18,
            costTokens: 65,
            isStarter: false
        ),
        .init(
            id: "room_decoration_art",
            title: "Motion study",
            subtitle: "A small framed path in cobalt and gold.",
            assetName: "StudioQuestDecorationArt",
            systemImage: "photo.artframe",
            zone: .wall,
            defaultWidth: 0.24,
            costTokens: 55,
            isStarter: false
        ),
        .init(
            id: "room_decoration_shelf",
            title: "Open shelf",
            subtitle: "A deliberately quiet wall piece.",
            assetName: "StudioQuestDecorationShelf",
            systemImage: "shelf.fill",
            zone: .wall,
            defaultWidth: 0.34,
            costTokens: 80,
            isStarter: false
        )
    ]

    static func decoration(for id: String) -> StudioQuestRoomDecoration? {
        catalog.first(where: { $0.id == id })
    }
}

/// The room scene is deliberately composed at runtime. The room background has
/// no person or optional decoration; avatar and inventory live in independent
/// layers and remain portable across scenes and future content packs.
struct StudioQuestAvatarScene: View {
    /// How the scene is framed. `.card` is the inset 3:2 tile used in feeds and
    /// pickers. `.hero` fills whatever frame it is given and drops the rounded
    /// clip, so the room can run edge to edge behind a profile header — and
    /// renders the musician larger, because at card scale the avatar reads as a
    /// speck in an empty room.
    enum Presentation {
        case card
        case hero

        var avatarWidthRatio: CGFloat {
            switch self {
            case .card: 0.46
            case .hero: 0.66
            }
        }

        var avatarHeightRatio: CGFloat {
            switch self {
            case .card: 0.88
            case .hero: 0.80
            }
        }
    }

    let loadout: AvatarLoadout
    let layout: StudioQuestRoomLayout
    let displayName: String
    var presentation: Presentation = .card
    var isEditing = false
    var onMove: ((StudioQuestRoomPlacement, StudioQuestRoomPoint) -> Void)?
    var onRemove: ((StudioQuestRoomPlacement) -> Void)?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selectedPlacementID: String?
    @State private var dragPlacementID: String?
    @State private var dragTranslation: CGSize = .zero

    private var room: StudioQuestAvatarRoom { .room(for: loadout.roomID) }

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            ZStack {
                Image(room.backgroundAsset)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size.width, height: size.height)
                    .clipped()

                decorationLayer(depth: { $0.depth < 0 }, size: size)

                StudioQuestAvatarRenderer(
                    loadout: loadout,
                    displayName: displayName,
                    size: min(
                        size.width * presentation.avatarWidthRatio,
                        size.height * presentation.avatarHeightRatio
                    )
                )
                .position(
                    x: size.width * room.avatarAnchor.x,
                    y: size.height * room.avatarAnchor.y
                )
                .accessibilityHidden(isEditing)

                decorationLayer(depth: { $0.depth >= 0 }, size: size)
            }
            .clipped()
            .contentShape(Rectangle())
        }
        .modifier(SceneFraming(presentation: presentation, isEditing: isEditing))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(displayName)'s \(room.title)")
    }

    private struct SceneFraming: ViewModifier {
        let presentation: Presentation
        let isEditing: Bool

        @ViewBuilder
        func body(content: Content) -> some View {
            switch presentation {
            case .card:
                content
                    .aspectRatio(3 / 2, contentMode: .fit)
                    .clipShape(
                        RoundedRectangle(cornerRadius: StudioQuestTokens.Radius.hero, style: .continuous)
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: StudioQuestTokens.Radius.hero, style: .continuous)
                            .stroke(
                                isEditing ? StudioQuestTokens.ColorRole.cobalt.opacity(0.7) : .clear,
                                lineWidth: 1.5
                            )
                    }
            case .hero:
                content.clipped()
            }
        }
    }

    @ViewBuilder
    private func decorationLayer(
        depth: @escaping (StudioQuestRoomPlacement) -> Bool,
        size: CGSize
    ) -> some View {
        ForEach(layout.placements.filter(depth).sorted(by: { $0.depth < $1.depth })) { placement in
            if let decoration = StudioQuestRoomDecoration.decoration(for: placement.decorationID) {
                let isDragging = dragPlacementID == placement.id
                let x = size.width * placement.position.x + (isDragging ? dragTranslation.width : 0)
                let y = size.height * placement.position.y + (isDragging ? dragTranslation.height : 0)
                Image(decoration.assetName)
                    .resizable()
                    .scaledToFit()
                    .frame(width: size.width * decoration.defaultWidth * placement.scale)
                    .rotationEffect(.degrees(placement.rotationDegrees))
                    .position(x: x, y: y)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        guard isEditing else { return }
                        selectedPlacementID = placement.id
                    }
                    .gesture(editDrag(for: placement, in: size))
                    .overlay(alignment: .topTrailing) {
                        if isEditing, selectedPlacementID == placement.id {
                            Button {
                                onRemove?(placement)
                                selectedPlacementID = nil
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.title3)
                                    .foregroundStyle(StudioQuestTokens.ColorRole.coral, .white)
                            }
                            .buttonStyle(.plain)
                            .offset(x: 10, y: -10)
                            .accessibilityLabel("Remove \(decoration.title)")
                        }
                    }
                    .accessibilityLabel("\(decoration.title), \(decoration.zone.rawValue) decoration")
                    .accessibilityHint(isEditing ? "Double tap and drag to move. Use the studio controls for precise placement." : "Open Edit studio to move this decoration.")
            }
        }
    }

    private func editDrag(for placement: StudioQuestRoomPlacement, in size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: isEditing ? 1 : .infinity)
            .onChanged { value in
                guard isEditing else { return }
                dragPlacementID = placement.id
                dragTranslation = value.translation
            }
            .onEnded { value in
                defer {
                    dragPlacementID = nil
                    dragTranslation = .zero
                }
                guard isEditing,
                      let decoration = StudioQuestRoomDecoration.decoration(for: placement.decorationID) else {
                    return
                }
                let next = StudioQuestRoomPoint(
                    x: placement.position.x + value.translation.width / max(1, size.width),
                    y: placement.position.y + value.translation.height / max(1, size.height)
                )
                let normalized = decoration.zone.clamped(next)
                if reduceMotion {
                    onMove?(placement, normalized)
                } else {
                    withAnimation(StudioQuestTokens.Motion.gentle) {
                        onMove?(placement, normalized)
                    }
                }
            }
    }
}

struct StudioQuestRoomPlacementControls: View {
    let placement: StudioQuestRoomPlacement
    let decoration: StudioQuestRoomDecoration
    let onMove: (StudioQuestRoomPoint) -> Void
    let onRemove: () -> Void

    var body: some View {
        StudioQuestRowSurface {
            VStack(alignment: .leading, spacing: StudioQuestTokens.Spacing.sm) {
                HStack(spacing: StudioQuestTokens.Spacing.sm) {
                    Image(decoration.assetName)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 44, height: 44)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(decoration.title).font(.headline)
                        Text("\(decoration.zone.rawValue.capitalized) placement")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(role: .destructive, action: onRemove) {
                        Image(systemName: "trash")
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Remove \(decoration.title)")
                }

                HStack(spacing: 8) {
                    moveButton("arrow.left") { move(x: -0.04, y: 0) }
                    moveButton("arrow.up") { move(x: 0, y: -0.04) }
                    moveButton("arrow.down") { move(x: 0, y: 0.04) }
                    moveButton("arrow.right") { move(x: 0.04, y: 0) }
                }
            }
        }
    }

    private func moveButton(_ systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .frame(minWidth: 44, minHeight: 44)
                .background(StudioQuestTokens.ColorRole.cobalt.opacity(0.10), in: Circle())
        }
        .buttonStyle(.plain)
    }

    private func move(x: Double, y: Double) {
        onMove(decoration.zone.clamped(.init(
            x: placement.position.x + x,
            y: placement.position.y + y
        )))
    }
}
