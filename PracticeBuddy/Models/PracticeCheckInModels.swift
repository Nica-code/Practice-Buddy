import Foundation

struct PracticeCheckInEvent: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var timestamp: Date
    var responded: Bool
    var responseSeconds: Int
    var focusTag: String
}
