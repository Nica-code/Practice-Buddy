import Foundation

enum SessionExportService {

    enum ExportFormat {
        case csv
        case json

        var fileExtension: String {
            switch self {
            case .csv: return "csv"
            case .json: return "json"
            }
        }
    }

    struct ExportError: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    static func export(sessions: [PracticeSessionModel], format: ExportFormat) throws -> URL {
        let timestamp = makeTimestamp()
        let filename = "PracticeBuddy-Export-\(timestamp).\(format.fileExtension)"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)

        switch format {
        case .csv:
            let csv = makeCSV(sessions: sessions)
            guard let data = csv.data(using: .utf8) else {
                throw ExportError(message: "Could not encode CSV as UTF-8.")
            }
            try data.write(to: url, options: .atomic)

        case .json:
            let data = try makeJSONData(sessions: sessions)
            try data.write(to: url, options: .atomic)
        }

        return url
    }

    private static func makeTimestamp() -> String {
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.dateFormat = "yyyyMMdd-HHmmss"
        return df.string(from: Date())
    }

    // MARK: CSV

    private static func makeCSV(sessions: [PracticeSessionModel]) -> String {
        var lines: [String] = ["date_iso,duration_seconds,notes"]

        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        for s in sessions {
            let date = iso.string(from: s.date)
            let duration = max(0, s.durationSeconds)
            let notes = csvEscape(s.notes)
            lines.append("\(date),\(duration),\(notes)")
        }

        return lines.joined(separator: "\n")
    }

    private static func csvEscape(_ value: String) -> String {
        let needsQuotes = value.contains(",") || value.contains("\"") || value.contains("\n") || value.contains("\r")
        var v = value.replacingOccurrences(of: "\"", with: "\"\"")
        if needsQuotes {
            v = "\"\(v)\""
        }
        return v
    }

    // MARK: JSON

    private static func makeJSONData(sessions: [PracticeSessionModel]) throws -> Data {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        let objects: [[String: Any]] = sessions.map { s in
            [
                "id": s.id.uuidString,
                "date": iso.string(from: s.date),
                "durationSeconds": max(0, s.durationSeconds),
                "notes": s.notes
            ]
        }

        guard JSONSerialization.isValidJSONObject(objects) else {
            throw ExportError(message: "Could not serialize JSON.")
        }

        return try JSONSerialization.data(withJSONObject: objects, options: [.prettyPrinted, .sortedKeys])
    }
}
