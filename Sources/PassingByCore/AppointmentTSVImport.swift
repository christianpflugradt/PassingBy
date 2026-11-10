import Foundation

public struct AppointmentImportRow: Equatable {
    public let line: Int
    public let date: Date
    public let title: String
    public let description: String
}

public struct AppointmentImportIssue: Equatable {
    public let line: Int
    public let reason: String
}

public struct AppointmentTSVImport {
    public let rows: [AppointmentImportRow]
    public let issues: [AppointmentImportIssue]
    public var canImport: Bool { !rows.isEmpty && issues.isEmpty }

    public init(_ source: String, calendar: Calendar = .current) {
        let timeZone = calendar.timeZone
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        var rows: [AppointmentImportRow] = []
        var issues: [AppointmentImportIssue] = []
        let normalized = source.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        for (offset, rawLine) in normalized.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
            let line = offset + 1
            if rawLine.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { continue }
            let columns = rawLine.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            guard columns.count == 2 || columns.count == 3 else {
                issues.append(.init(line: line, reason: "Expected 2 or 3 tab-separated columns"))
                continue
            }
            let dateText = columns[0].trimmingCharacters(in: .whitespaces)
            guard dateText.range(of: #"^[0-9]{2}\.[0-9]{2}\.[0-9]{4}$"#, options: .regularExpression) != nil else {
                issues.append(.init(line: line, reason: "Invalid date: \(dateText)"))
                continue
            }
            let parts = dateText.split(separator: ".").compactMap { Int($0) }
            guard parts.count == 3,
                let date = calendar.date(from: DateComponents(year: parts[2], month: parts[1], day: parts[0])),
                calendar.dateComponents([.day, .month, .year], from: date) == DateComponents(year: parts[2], month: parts[1], day: parts[0])
            else {
                issues.append(.init(line: line, reason: "Invalid date: \(dateText)"))
                continue
            }
            let title = columns[1].trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty else {
                issues.append(.init(line: line, reason: "Missing title"))
                continue
            }
            let description = columns.count == 3 ? columns[2].trimmingCharacters(in: .whitespacesAndNewlines) : ""
            rows.append(.init(line: line, date: calendar.startOfDay(for: date), title: title, description: description))
        }
        self.rows = rows
        self.issues = issues
    }
}
