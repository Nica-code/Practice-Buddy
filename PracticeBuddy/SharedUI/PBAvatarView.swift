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
        PBAvatarStyle(id: "avatar_violin", title: "Noah", subtitle: "Strings", symbolName: "music.quarternote.3", color: .orange, availability: .included),
        PBAvatarStyle(id: "avatar_mic", title: "Luna", subtitle: "Vocalist", symbolName: "mic.fill", color: .pink, availability: .included),
        PBAvatarStyle(id: "avatar_headphones", title: "Milo", subtitle: "Producer", symbolName: "headphones", color: .mint, availability: .included),
        PBAvatarStyle(id: "avatar_star", title: "Skye", subtitle: "Performer", symbolName: "star.fill", color: .yellow, availability: .included),
        PBAvatarStyle(id: "avatar_wave", title: "Kai", subtitle: "Engineer", symbolName: "waveform", color: .purple, availability: .included),
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

struct PBAvatarView: View {
    let avatarID: String
    let displayName: String
    var size: CGFloat = 36

    var body: some View {
        let style = PBAvatarStyle.byID(avatarID)
        if let fullBody = UIImage(named: style.fullBodyAssetName) {
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
}

struct PBLevelBadgeView: View {
    let level: Int
    @Environment(\.pbTypography) private var type

    var body: some View {
        Text(L10n.f("Level %@", "\(max(1, level))"))
            .font(type.fontChoice.headlineFont(size: 11, weight: .semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(Color.primary.opacity(0.12))
            .clipShape(Capsule())
            .accessibilityLabel(Text("Level"))
            .accessibilityValue(Text("\(max(1, level))"))
    }
}
