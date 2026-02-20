import Foundation

enum PracticeNoteMood: String, CaseIterable, Codable, Identifiable {
    case great
    case good
    case okay
    case tough

    var id: String { rawValue }

    var title: String {
        switch self {
        case .great: return "Great"
        case .good: return "Good"
        case .okay: return "Okay"
        case .tough: return "Tough"
        }
    }
}

struct PracticeSessionJournalPiece: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var title: String
    var tempo: String
    var wentWell: String
    var needsWork: String
    var nextAction: String
}

struct PracticeSessionJournal: Codable, Equatable {
    var pieces: [PracticeSessionJournalPiece]
    var reflection: String
}
