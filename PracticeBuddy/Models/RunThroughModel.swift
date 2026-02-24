import Foundation
import SwiftData

struct RunThroughMarker: Codable, Identifiable, Equatable {
    let id: UUID
    let second: Int
    let label: String

    init(id: UUID = UUID(), second: Int, label: String) {
        self.id = id
        self.second = max(0, second)
        self.label = label
    }
}

@Model
final class RunThroughModel {
    @Attribute(.unique) var id: UUID
    var date: Date
    var durationSeconds: Int
    var audioFilePath: String
    var notes: String
    var selfRating: Int
    var noPauseMode: Bool
    var usedMetronome: Bool
    var markerJSON: String
    var pieceName: String

    init(
        id: UUID = UUID(),
        date: Date = Date(),
        durationSeconds: Int,
        audioFilePath: String,
        notes: String,
        selfRating: Int,
        noPauseMode: Bool,
        usedMetronome: Bool,
        markerJSON: String = "",
        pieceName: String = ""
    ) {
        self.id = id
        self.date = date
        self.durationSeconds = max(0, durationSeconds)
        self.audioFilePath = audioFilePath
        self.notes = notes
        self.selfRating = min(max(selfRating, 1), 5)
        self.noPauseMode = noPauseMode
        self.usedMetronome = usedMetronome
        self.markerJSON = markerJSON
        self.pieceName = pieceName
    }
}

extension RunThroughModel {
    var markers: [RunThroughMarker] {
        let raw = markerJSON.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty,
              let data = raw.data(using: .utf8),
              let rows = try? JSONDecoder().decode([RunThroughMarker].self, from: data) else {
            return []
        }
        return rows.sorted(by: { $0.second < $1.second })
    }
}
