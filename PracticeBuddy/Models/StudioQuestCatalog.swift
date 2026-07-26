import SwiftUI

/// The single source of truth for featured quest content.
///
/// Quests used to be built inline in the view bodies — the full list inside
/// `StudioQuestQuestView`, and a second hand-written copy of "Dynamic control"
/// inside `StudioQuestTodayView`. The two copies had already drifted: Today
/// described it as "Shape one phrase across three dynamics" while Quest said
/// "Practice a deliberate dynamic arc for 20 minutes", and they launched
/// different practice tasks for the same quest ID.
///
/// Content, map placement and colour now live together here, so a quest is
/// described once. This is also the seam a remote or bundled quest feed would
/// plug into later — nothing above this type constructs quest content.
struct StudioQuestDefinition: Identifiable, Hashable {
    let id: String
    let title: String
    let subtitle: String
    let target: Int
    let rewardTokens: Int
    let systemImage: String
    /// Normalised position on the quest-path artwork (0…1 in both axes).
    let nodePosition: CGPoint
    let nodeColor: Color
    let action: QuestAction

    func presentation(progress: Int) -> QuestPresentation {
        QuestPresentation(
            id: id,
            title: title,
            subtitle: subtitle,
            progress: progress,
            target: target,
            rewardTokens: rewardTokens,
            systemImage: systemImage,
            period: .featured,
            action: action
        )
    }
}

enum StudioQuestCatalog {
    static let featured: [StudioQuestDefinition] = [
        StudioQuestDefinition(
            id: "warm-up-warrior",
            title: "Warm-up warrior",
            subtitle: "Complete a focused warm-up routine.",
            target: 1,
            rewardTokens: 15,
            systemImage: "figure.cooldown",
            nodePosition: CGPoint(x: 0.30, y: 0.80),
            nodeColor: StudioQuestTokens.ColorRole.cobalt,
            action: .route(.warmUp)
        ),
        StudioQuestDefinition(
            id: "rhythm-clarity",
            title: "Rhythm clarity",
            subtitle: "Capture one accurate rhythm take.",
            target: 1,
            rewardTokens: 20,
            systemImage: "metronome",
            nodePosition: CGPoint(x: 0.70, y: 0.58),
            nodeColor: StudioQuestTokens.ColorRole.violet,
            action: .route(.rhythm)
        ),
        StudioQuestDefinition(
            id: "dynamic-control",
            title: "Dynamic control",
            subtitle: "Shape one phrase across three dynamics.",
            target: 1,
            rewardTokens: 25,
            systemImage: "waveform",
            nodePosition: CGPoint(x: 0.35, y: 0.36),
            nodeColor: StudioQuestTokens.ColorRole.gold,
            action: .practice(
                PracticePreset(
                    piece: "",
                    task: "Shape one phrase across three dynamics",
                    durationMinutes: 20,
                    verified: true,
                    launchContext: PracticeLaunchContext(source: "quest", questID: "dynamic-control")
                )
            )
        ),
        StudioQuestDefinition(
            id: "expression-mastery",
            title: "Expression mastery",
            subtitle: "Complete a distraction-free run-through.",
            target: 1,
            rewardTokens: 30,
            systemImage: "sparkles",
            nodePosition: CGPoint(x: 0.72, y: 0.15),
            nodeColor: StudioQuestTokens.ColorRole.violet,
            action: .route(.runThrough)
        )
    ]

    static func definition(id: String) -> StudioQuestDefinition? {
        featured.first { $0.id == id }
    }

    static func presentations(progress: (String) -> Int) -> [QuestPresentation] {
        featured.map { $0.presentation(progress: progress($0.id)) }
    }

    /// What Today should surface: the first quest still outstanding, falling
    /// back to the last one once everything is complete. Today previously
    /// hard-coded "Dynamic control" regardless of whether it was already done.
    static func next(progress: (String) -> Int) -> QuestPresentation? {
        let all = presentations(progress: progress)
        return all.first { !$0.isComplete } ?? all.last
    }
}
