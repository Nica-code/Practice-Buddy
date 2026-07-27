import SwiftUI
import UIKit

struct PBAvatarStyle: Equatable, Identifiable {
    enum Availability: Equatable {
        case included
        case token(costTokens: Int)

        var label: String {
            switch self {
            case .included:
                return "Free"
            case .token(let costTokens):
                return "\(costTokens) tokens"
            }
        }
    }

    let id: String
    let title: String
    let subtitle: String
    let symbolName: String
    let color: Color
    let availability: Availability

    var isFree: Bool {
        if case .included = availability { return true }
        return false
    }

    var tokenCost: Int? {
        if case .token(let costTokens) = availability { return max(0, costTokens) }
        return nil
    }

    static let all: [PBAvatarStyle] = [
        PBAvatarStyle(id: "avatar_note", title: "Ari", subtitle: "Violinist", symbolName: "music.note", color: .blue, availability: .included),
        PBAvatarStyle(id: "avatar_violin", title: "Noah", subtitle: "Cellist", symbolName: "music.quarternote.3", color: .orange, availability: .included),
        PBAvatarStyle(id: "avatar_mic", title: "Luna", subtitle: "Vocalist", symbolName: "mic.fill", color: .pink, availability: .included),
        PBAvatarStyle(id: "avatar_headphones", title: "Milo", subtitle: "Producer", symbolName: "headphones", color: .mint, availability: .included),
        PBAvatarStyle(id: "avatar_star", title: "Skye", subtitle: "Flutist", symbolName: "star.fill", color: .yellow, availability: .included),
        PBAvatarStyle(id: "avatar_wave", title: "Kai", subtitle: "Guitarist", symbolName: "waveform", color: .purple, availability: .included),
        PBAvatarStyle(id: "avatar_bolt", title: "Nova", subtitle: "Virtuoso", symbolName: "bolt.fill", color: .red, availability: .included),
        PBAvatarStyle(id: "avatar_leaf", title: "Leo", subtitle: "Studio", symbolName: "leaf.fill", color: .green, availability: .included),
        PBAvatarStyle(id: "avatar_f_piano", title: "Celeste", subtitle: "Concert Pianist", symbolName: "pianokeys.inverse", color: .indigo, availability: .token(costTokens: 120)),
        PBAvatarStyle(id: "avatar_m_guitar", title: "Orion", subtitle: "Arena Guitar", symbolName: "guitars", color: .purple, availability: .token(costTokens: 140)),
        PBAvatarStyle(id: "avatar_f_teacher", title: "Vesper", subtitle: "Maestro", symbolName: "graduationcap.fill", color: .orange, availability: .token(costTokens: 180)),
        PBAvatarStyle(id: "avatar_m_coach", title: "Titan", subtitle: "Grandmaster", symbolName: "figure.run", color: .mint, availability: .token(costTokens: 200))
    ]

    static var freeStyles: [PBAvatarStyle] {
        all.filter(\.isFree)
    }

    static var tokenStyles: [PBAvatarStyle] {
        all.filter { !$0.isFree }
    }

    static func byID(_ id: String?) -> PBAvatarStyle {
        guard let id, let found = all.first(where: { $0.id == id }) else {
            return all[0]
        }
        return found
    }

    var fullBodyAssetName: String {
        id.replacingOccurrences(of: "avatar_", with: "avatar_full_")
    }
}

struct StudioQuestAvatarRenderer: View {
    let loadout: AvatarLoadout
    let displayName: String
    var size: CGFloat = 140

    var body: some View {
        ZStack {
            if let base = UIImage(named: PBAvatarStyle.byID(loadout.baseID).fullBodyAssetName) {
                Image(uiImage: base)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
            } else {
                PBAvatarView(
                    avatarID: loadout.baseID,
                    displayName: displayName,
                    size: size
                )
            }

            optionalLayer(named: "avatar_layer_\(loadout.skinToneID)")
            optionalLayer(named: "avatar_layer_\(loadout.hairID)")
            optionalLayer(named: "avatar_layer_\(loadout.outfitID)")
            optionalLayer(named: "avatar_layer_\(loadout.instrumentID)")
            if let accessoryID = loadout.accessoryID {
                optionalLayer(named: "avatar_layer_\(accessoryID)")
            }
            optionalLayer(named: "avatar_layer_\(loadout.poseID)")
        }
        .frame(width: size, height: size)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(displayName) musician avatar")
        .accessibilityValue(avatarDescription)
    }

    @ViewBuilder
    private func optionalLayer(named name: String) -> some View {
        if let layer = UIImage(named: name) {
            Image(uiImage: layer)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
        }
    }

    private var avatarDescription: String {
        [
            PBAvatarStyle.byID(loadout.baseID).title,
            loadout.instrumentID.replacingOccurrences(of: "instrument_", with: ""),
            loadout.poseID.replacingOccurrences(of: "pose_", with: "")
        ]
        .joined(separator: ", ")
    }
}

struct PBAvatarView: View {
    let avatarID: String
    let displayName: String
    var profilePhotoURL: String? = nil
    var size: CGFloat = 36

    var body: some View {
        let style = PBAvatarStyle.byID(avatarID)
        if let profilePhotoURL, let url = URL(string: profilePhotoURL) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                default:
                    fallbackAvatar(style: style)
                }
            }
            .frame(width: size, height: size)
            .clipShape(Circle())
            .contentShape(Circle())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("\(displayName) profile photo"))
        } else if let fullBody = UIImage(named: style.fullBodyAssetName) {
            ZStack {
                RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                    .fill(style.color.opacity(0.12))

                Image(uiImage: fullBody)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .padding(size * 0.08)
            }
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: size * 0.28, style: .continuous))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("\(displayName) avatar"))
            .accessibilityValue(Text("\(style.title), \(style.subtitle)"))
        } else {
            fallbackAvatar(style: style)
        }
    }

    @ViewBuilder
    private func fallbackAvatar(style: PBAvatarStyle) -> some View {
        ZStack {
            Circle()
                .fill(style.color.opacity(0.2))

            Image(systemName: style.symbolName)
                .font(.system(size: size * 0.44, weight: .semibold))
                .foregroundStyle(style.color)
        }
        .frame(width: size, height: size)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(displayName) avatar"))
        .accessibilityValue(Text("\(style.title), \(style.subtitle)"))
    }
}

struct PBLevelBadgeView: View {
    let level: Int

    var body: some View {
        Text(L10n.f("Level %@", "\(max(1, level))"))
            .font(.system(size: 11, weight: .semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(Color.primary.opacity(0.12))
            .clipShape(Capsule())
            .accessibilityLabel(Text("Level"))
            .accessibilityValue(Text("\(max(1, level))"))
    }
}
