import Foundation

enum MomentAudience: String, Codable, CaseIterable, Hashable {
    case friends
    case followers
    case `public`
}

enum MomentTag: String, Codable, CaseIterable, Identifiable {
    case breakthrough
    case focusedWork
    case firstRun
    case toughDay
    case consistency
    case performancePrep

    var id: String { rawValue }

    var title: String {
        switch self {
        case .breakthrough: "Breakthrough"
        case .focusedWork: "Focused work"
        case .firstRun: "First run"
        case .toughDay: "Tough day"
        case .consistency: "Consistency"
        case .performancePrep: "Performance prep"
        }
    }
}

enum MomentReactionKind: String, Codable, CaseIterable, Identifiable {
    case bravo
    case inspired
    case strongWork
    case practiceTogether

    var id: String { rawValue }

    var title: String {
        switch self {
        case .bravo: "Bravo"
        case .inspired: "Inspired"
        case .strongWork: "Strong work"
        case .practiceTogether: "Practice together"
        }
    }

    var systemImage: String {
        switch self {
        case .bravo: "hands.clap.fill"
        case .inspired: "sparkles"
        case .strongWork: "music.note"
        case .practiceTogether: "person.2.fill"
        }
    }
}

enum MomentModerationState: String, Codable, Hashable {
    case active
    case hidden
    case reported
    case expired
}

struct PracticeMoment: Identifiable, Codable, Hashable {
    let id: String
    let authorUID: String
    var displayName: String
    var handle: String
    var profilePhotoURL: String
    var instrument: String
    var durationBucket: String
    var practiceCategory: String
    var isVerified: Bool
    var tag: MomentTag
    var audience: MomentAudience
    var avatarLoadout: AvatarLoadout
    var createdAt: Date
    var expiresAt: Date
    var moderationState: MomentModerationState
    var reactions: [MomentReactionKind: Int]

    var isActive: Bool {
        moderationState == .active && expiresAt > .now
    }
}

struct MomentFeedPage: Equatable {
    var moments: [PracticeMoment]
    var nextCursor: String?
    var hasMore: Bool
}

enum SocialRelationshipStatus: String, Codable, Hashable {
    case none
    case requested
    case following
    case friends
    case blocked
}

struct SocialRelationship: Identifiable, Codable, Hashable {
    let id: String
    let fromUID: String
    let toUID: String
    var status: SocialRelationshipStatus
    var createdAt: Date
    var acceptedAt: Date?
}

struct FollowRequest: Identifiable, Codable, Hashable {
    let id: String
    let fromUID: String
    let toUID: String
    let createdAt: Date
}

struct SocialBlock: Identifiable, Codable, Hashable {
    let id: String
    let blockerUID: String
    let blockedUID: String
    let createdAt: Date
}

struct ContentReport: Identifiable, Codable, Hashable {
    let id: String
    let reporterUID: String
    let targetType: String
    let targetID: String
    let reason: String
    let createdAt: Date
}
