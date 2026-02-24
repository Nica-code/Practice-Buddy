import SwiftUI

struct PBAvatarStyle: Equatable {
    let id: String
    let title: String
    let symbolName: String
    let color: Color

    static let all: [PBAvatarStyle] = [
        PBAvatarStyle(id: "avatar_note", title: "Note", symbolName: "music.note", color: .blue),
        PBAvatarStyle(id: "avatar_violin", title: "Strings", symbolName: "music.quarternote.3", color: .orange),
        PBAvatarStyle(id: "avatar_mic", title: "Mic", symbolName: "mic.fill", color: .pink),
        PBAvatarStyle(id: "avatar_headphones", title: "Headphones", symbolName: "headphones", color: .mint),
        PBAvatarStyle(id: "avatar_star", title: "Star", symbolName: "star.fill", color: .yellow),
        PBAvatarStyle(id: "avatar_wave", title: "Wave", symbolName: "waveform", color: .purple),
        PBAvatarStyle(id: "avatar_bolt", title: "Focus", symbolName: "bolt.fill", color: .red),
        PBAvatarStyle(id: "avatar_leaf", title: "Calm", symbolName: "leaf.fill", color: .green)
    ]

    static func byID(_ id: String?) -> PBAvatarStyle {
        guard let id, let found = all.first(where: { $0.id == id }) else {
            return all[0]
        }
        return found
    }
}

struct PBAvatarView: View {
    let avatarID: String
    let displayName: String
    var size: CGFloat = 36

    var body: some View {
        let style = PBAvatarStyle.byID(avatarID)
        ZStack {
            Circle()
                .fill(style.color.opacity(0.2))

            Image(systemName: style.symbolName)
                .font(.system(size: size * 0.44, weight: .semibold))
                .foregroundStyle(style.color)

            if style.id == "avatar_note" {
                let initial = displayName.trimmingCharacters(in: .whitespacesAndNewlines).first.map { String($0).uppercased() } ?? "P"
                Text(initial)
                    .font(.system(size: size * 0.28, weight: .bold))
                    .foregroundStyle(.primary)
                    .offset(y: size * 0.14)
            }
        }
        .frame(width: size, height: size)
    }
}

struct PBLevelBadgeView: View {
    let level: Int

    var body: some View {
        Text(L10n.f("Lv %@", "\(max(1, level))"))
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(Color.primary.opacity(0.12))
            .clipShape(Capsule())
    }
}
