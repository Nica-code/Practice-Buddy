import Foundation

enum AgeBand: String, Codable, CaseIterable, Hashable {
    case under13
    case teen
    case adult

    static func derive(from dateOfBirth: Date, now: Date = .now, calendar: Calendar = .current) -> AgeBand {
        let years = max(0, calendar.dateComponents([.year], from: dateOfBirth, to: now).year ?? 0)
        if years < 13 { return .under13 }
        if years < 18 { return .teen }
        return .adult
    }
}

struct ProfilePrivacy: Codable, Equatable, Hashable {
    var isPrivate: Bool
    var showBio: Bool
    var showInstrument: Bool
    var showPracticeTotals: Bool
    var showMomentsToFollowers: Bool

    static let `default` = ProfilePrivacy(
        isPrivate: true,
        showBio: true,
        showInstrument: true,
        showPracticeTotals: false,
        showMomentsToFollowers: true
    )
}

struct IdentityProfile: Codable, Equatable, Hashable {
    let uid: String
    var displayName: String
    var handle: String
    var dateOfBirth: Date
    var instrument: String
    var privacy: ProfilePrivacy
    var profileSchemaVersion: Int
    var handleChangedAt: Date?

    var ageBand: AgeBand { .derive(from: dateOfBirth) }
}

struct PublicProfile: Identifiable, Codable, Equatable, Hashable {
    let id: String
    var displayName: String
    var handle: String
    var profilePhotoURL: String
    var instrument: String
    var bio: String
    var publicLevel: Int
    var avatarID: String
    var isPrivate: Bool
    var allowsMoments: Bool
}

enum ProfileUpgradeState: Equatable {
    case loading
    case notRequired
    case required
    case offlineRestricted
    case complete
    case failed(String)
}

struct HandleReservation: Codable, Equatable, Hashable {
    let handle: String
    let ownerUID: String
    let expiresAt: Date?
}

enum IdentityValidationResult: Equatable {
    case valid
    case invalid(String)

    var isValid: Bool {
        if case .valid = self { return true }
        return false
    }

    var message: String? {
        if case .invalid(let message) = self { return message }
        return nil
    }
}

enum StudioQuestIdentityValidator {
    private static let reservedWords: Set<String> = [
        "admin", "support", "practiquest", "official", "moderator", "system", "staff", "explore", "settings", "you"
    ]

    static func normalizedDisplayName(_ raw: String) -> String {
        raw
            .precomposedStringWithCanonicalMapping
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
    }

    static func normalizedHandle(_ raw: String) -> String {
        raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    static func validateDisplayName(_ raw: String) -> IdentityValidationResult {
        let value = normalizedDisplayName(raw)
        guard (2...30).contains(value.count) else {
            return .invalid("Use 2–30 characters for your display name.")
        }
        guard value.rangeOfCharacter(from: .controlCharacters) == nil,
              value.unicodeScalars.allSatisfy({ !$0.properties.isBidiControl }) else {
            return .invalid("That display name contains unsupported characters.")
        }
        guard value.unicodeScalars.contains(where: { CharacterSet.letters.contains($0) || CharacterSet.decimalDigits.contains($0) }) else {
            return .invalid("Include at least one letter or number.")
        }
        let allowed = CharacterSet.letters
            .union(.decimalDigits)
            .union(CharacterSet(charactersIn: " ._-'"))
        guard value.unicodeScalars.allSatisfy({ allowed.contains($0) }) else {
            return .invalid("Use letters, numbers, spaces, apostrophes, periods, underscores, or hyphens.")
        }
        guard !isReservedOrProfane(value) else {
            return .invalid("Choose a different display name.")
        }
        return .valid
    }

    static func validateHandle(_ raw: String) -> IdentityValidationResult {
        let value = normalizedHandle(raw)
        guard (3...20).contains(value.count) else {
            return .invalid("Use 3–20 characters for your handle.")
        }
        guard value.range(of: "^[a-z0-9](?:[a-z0-9._]*[a-z0-9])?$", options: .regularExpression) != nil else {
            return .invalid("Handles use lowercase letters, numbers, periods, and underscores.")
        }
        guard !value.contains(".."), !value.contains("__"), !value.contains("._"), !value.contains("_.") else {
            return .invalid("Do not use consecutive separators in your handle.")
        }
        guard !isReservedOrProfane(value) else {
            return .invalid("That handle is unavailable.")
        }
        return .valid
    }

    static func validateDateOfBirth(_ date: Date, now: Date = .now) -> IdentityValidationResult {
        guard date <= now else { return .invalid("Enter a date of birth in the past.") }
        guard Calendar.current.dateComponents([.year], from: date, to: now).year ?? 0 <= 120 else {
            return .invalid("Enter a valid date of birth.")
        }
        return .valid
    }

    static func isGeneratedLegacyName(_ name: String) -> Bool {
        normalizedDisplayName(name).range(of: "^player[0-9]{3,}$", options: [.regularExpression, .caseInsensitive]) != nil
    }

    private static func isReservedOrProfane(_ value: String) -> Bool {
        let canonical = value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        if reservedWords.contains(canonical) { return true }
        let blocked = ["fuck", "shit", "bitch", "cunt", "nazi"]
        return blocked.contains(where: { canonical.contains($0) })
    }
}
