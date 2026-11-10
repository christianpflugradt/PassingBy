import Foundation

public enum ScheduleWeekday: Int, Codable, CaseIterable, Hashable, Identifiable {
    case sunday = 1, monday, tuesday, wednesday, thursday, friday, saturday
    public var id: Int { rawValue }
}

public enum ScheduleWeekInterval: Int, Codable, CaseIterable, Hashable, Identifiable {
    case everyWeek = 1, everyTwoWeeks = 2
    public var id: Int { rawValue }
}

public enum ScheduleMonthOccurrence: String, Codable, CaseIterable, Hashable, Identifiable {
    case firstDay, firstWeekday, lastDay, lastWeekday
    public var id: String { rawValue }
}

public enum ScheduleRecurrence: Codable, Hashable {
    case weekly(interval: ScheduleWeekInterval, weekday: ScheduleWeekday)
    case monthly(ScheduleMonthOccurrence)

    public func firstOccurrence(onOrAfter date: Date, calendar: Calendar = .current) -> Date {
        let today = calendar.startOfDay(for: date)
        switch self {
        case .weekly(_, let weekday):
            let days = (weekday.rawValue - calendar.component(.weekday, from: today) + 7) % 7
            return calendar.date(byAdding: .day, value: days, to: today)!
        case .monthly(let occurrence):
            let candidate = monthlyDate(inMonthContaining: today, occurrence: occurrence, calendar: calendar)
            if candidate >= today { return candidate }
            let monthStart = calendar.dateInterval(of: .month, for: today)!.start
            let nextMonth = calendar.date(byAdding: .month, value: 1, to: monthStart)!
            return monthlyDate(inMonthContaining: nextMonth, occurrence: occurrence, calendar: calendar)
        }
    }

    public func occurrence(after date: Date, calendar: Calendar = .current) -> Date {
        let day = calendar.startOfDay(for: date)
        switch self {
        case .weekly(let interval, _):
            return calendar.date(byAdding: .day, value: interval.rawValue * 7, to: day)!
        case .monthly(let occurrence):
            let monthStart = calendar.dateInterval(of: .month, for: day)!.start
            let nextMonth = calendar.date(byAdding: .month, value: 1, to: monthStart)!
            return monthlyDate(inMonthContaining: nextMonth, occurrence: occurrence, calendar: calendar)
        }
    }

    private func monthlyDate(inMonthContaining date: Date, occurrence: ScheduleMonthOccurrence, calendar: Calendar) -> Date {
        let month = calendar.dateInterval(of: .month, for: date)!
        let first = month.start
        let last = calendar.date(byAdding: .day, value: -1, to: month.end)!
        let base = occurrence == .firstDay || occurrence == .firstWeekday ? first : last
        guard occurrence == .firstWeekday || occurrence == .lastWeekday else { return base }
        let weekday = calendar.component(.weekday, from: base)
        let adjustment: Int
        switch (occurrence, weekday) {
        case (.firstWeekday, 1): adjustment = 1
        case (.firstWeekday, 7): adjustment = 2
        case (.lastWeekday, 1): adjustment = -2
        case (.lastWeekday, 7): adjustment = -1
        default: adjustment = 0
        }
        return calendar.date(byAdding: .day, value: adjustment, to: base)!
    }
}

public struct ScheduledTodo: Codable, Equatable, Identifiable {
    public let id: UUID
    public let title: String
    public var categoryID: UUID?
    public let recurrence: ScheduleRecurrence
    public var nextOccurrence: Date
    public var lastGeneratedOccurrence: Date? = nil

    public init(
        id: UUID = UUID(), title: String, categoryID: UUID?, recurrence: ScheduleRecurrence, startingOn date: Date = Date(),
        calendar: Calendar = .current
    ) {
        self.id = id
        self.title = title
        self.categoryID = categoryID
        self.recurrence = recurrence
        self.nextOccurrence = recurrence.firstOccurrence(onOrAfter: date, calendar: calendar)
    }

    private enum CodingKeys: String, CodingKey { case id, title, categoryID, recurrence, nextOccurrence, lastGeneratedOccurrence }
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        title = try values.decode(String.self, forKey: .title)
        categoryID = try values.decodeIfPresent(UUID.self, forKey: .categoryID)
        recurrence = try values.decode(ScheduleRecurrence.self, forKey: .recurrence)
        nextOccurrence = try values.decode(Date.self, forKey: .nextOccurrence)
        lastGeneratedOccurrence = try values.decodeIfPresent(Date.self, forKey: .lastGeneratedOccurrence)
    }
}
