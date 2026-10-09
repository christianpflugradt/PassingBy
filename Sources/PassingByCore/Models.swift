import Foundation

public enum LabelContext: Codable, Hashable, Identifiable {
    case all
    // Retained so workspaces saved with the former filter still decode.
    case unlabelled
    case label(UUID)

    public var id: String {
        switch self { case .all: "all"; case .unlabelled: "unlabelled"; case .label(let id): id.uuidString }
    }
}

public enum DateDisplayMode: String, Codable, CaseIterable, Identifiable {
    case chronological = "Chronological"
    case byLabel = "By Label"
    public var id: String { rawValue }
}

public enum ZoomLevel {
    public static let minimum = 70
    public static let maximum = 180
    public static let step = 10

    public static func validated(_ percent: Int) -> Int {
        guard (minimum...maximum).contains(percent), percent.isMultiple(of: step) else { return 100 }
        return percent
    }
}

public enum NoteIcon {
    public static let defaultName = "doc.text"
    // Ordered for the seven-column picker. Move removed choices to legacyNames to preserve saved Notes.
    public static let choices = [
        "doc.text", "text.alignleft", "lightbulb", "star", "bookmark", "folder", "briefcase",
        "person", "person.2", "bubble.left", "heart", "house", "flag", "link",
        "book.closed", "book", "graduationcap", "terminal", "chevron.left.forwardslash.chevron.right", "chart.line.uptrend.xyaxis", "clock",
        "bag", "cart", "gift", "fork.knife", "cup.and.saucer", "birthday.cake", "banknote",
        "car", "bicycle", "airplane", "map", "suitcase", "globe", "building.2",
        "figure.run", "dumbbell", "cross.case", "pills", "pawprint", "leaf", "hammer",
        "wrench.and.screwdriver", "washer", "creditcard", "gamecontroller", "tv", "music.note", "camera"
    ]
    public static let legacyNames: Set<String> = ["checklist", "pencil"]
    public static func safeName(_ name: String) -> String {
        choices.contains(name) || legacyNames.contains(name) ? name : defaultName
    }
}

// Symbols deliberately used for Passing By navigation, commands, and application states.
public enum AppSymbol {
    public static let dashboard = "square.grid.2x2"
    public static let todos = "checklist"
    public static let appointments = "calendar"
    public static let help = "questionmark.circle"
    public static let settings = "gearshape"
    public static let locked = "lock.fill"
    public static let add = "plus"
    public static let delete = "trash"
    public static let edit = "pencil"
    public static let incomplete = "circle"
    public static let complete = "checkmark.circle.fill"
    public static let details = "info.circle"
    public static let more = "ellipsis"
    public static let error = "exclamationmark.triangle"
    public static let unavailableNote = "note.text"
    public static let reserved: Set<String> = [
        dashboard, todos, appointments, help, settings, locked, add, delete, edit,
        incomplete, complete, details, more, error, unavailableNote
    ]
}

public enum RetentionPeriod: Int, Codable, CaseIterable, Identifiable {
    case seven = 7, fourteen = 14, thirty = 30, ninety = 90, never = -1
    public var id: Int { rawValue }
    public var title: String { self == .never ? "Never" : "\(rawValue) days" }
}

public enum LabelColor: String, Codable, CaseIterable, Identifiable {
    case blue, purple, pink, red, orange, yellow, green, gray
    public var id: String { rawValue }
}

public struct Label: Codable, Identifiable, Hashable {
    public var id = UUID()
    public var name: String
    public var color: LabelColor = .blue
    public init(id: UUID = UUID(), name: String, color: LabelColor = .blue) { self.id = id; self.name = name; self.color = color }
}

public struct Note: Codable, Identifiable, Hashable {
    public var id = UUID()
    public var title: String
    public var contentMarkdown: String = ""
    public var labelID: UUID?
    public var createdAt = Date()
    public var updatedAt = Date()
    public var iconName: String = NoteIcon.defaultName
    public var zoomPercent = 100
    public init(id: UUID = UUID(), title: String, contentMarkdown: String = "", labelID: UUID? = nil, createdAt: Date = Date(), updatedAt: Date = Date(), iconName: String = NoteIcon.defaultName) { self.id = id; self.title = title; self.contentMarkdown = contentMarkdown; self.labelID = labelID; self.createdAt = createdAt; self.updatedAt = updatedAt; self.iconName = NoteIcon.safeName(iconName) }
    private enum CodingKeys: String, CodingKey { case id, title, contentMarkdown, labelID, createdAt, updatedAt, iconName, zoomPercent }
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        title = try values.decode(String.self, forKey: .title)
        contentMarkdown = try values.decode(String.self, forKey: .contentMarkdown)
        labelID = try values.decodeIfPresent(UUID.self, forKey: .labelID)
        createdAt = try values.decode(Date.self, forKey: .createdAt)
        updatedAt = try values.decode(Date.self, forKey: .updatedAt)
        iconName = NoteIcon.safeName(try values.decodeIfPresent(String.self, forKey: .iconName) ?? NoteIcon.defaultName)
        zoomPercent = ZoomLevel.validated(try values.decodeIfPresent(Int.self, forKey: .zoomPercent) ?? 100)
    }
}

public struct Task: Codable, Identifiable, Hashable {
    public var id = UUID()
    public var title: String
    public var taskDescription: String = ""
    public var labelID: UUID?
    public var createdAt = Date()
    public var completedAt: Date?
    public init(id: UUID = UUID(), title: String, taskDescription: String = "", labelID: UUID? = nil, createdAt: Date = Date(), completedAt: Date? = nil) { self.id = id; self.title = title; self.taskDescription = taskDescription; self.labelID = labelID; self.createdAt = createdAt; self.completedAt = completedAt }
}

public struct DateItem: Codable, Identifiable, Hashable {
    public var id = UUID()
    public var title: String
    public var date: Date
    public var itemDescription: String = ""
    public var labelID: UUID?
    public var createdAt = Date()
    public init(id: UUID = UUID(), title: String, date: Date, itemDescription: String = "", labelID: UUID? = nil, createdAt: Date = Date()) { self.id = id; self.title = title; self.date = date; self.itemDescription = itemDescription; self.labelID = labelID; self.createdAt = createdAt }
}

public struct DateGroup: Identifiable {
    public let id: String
    public let name: String
    public let items: [DateItem]
    public let hiddenUpcomingCount: Int
}

public struct AppSettings: Codable, Hashable {
    public var labelContext: LabelContext = .all
    public var dateDisplayMode: DateDisplayMode = .chronological
    public var taskRetention: RetentionPeriod = .thirty
    public var dateRetention: RetentionPeriod = .thirty
    public var maximumDashboardTasks = 4 {
        didSet { if !(1...10).contains(maximumDashboardTasks) { maximumDashboardTasks = 4 } }
    }
    public var maximumDashboardAppointments = 4 {
        didSet { if !(1...10).contains(maximumDashboardAppointments) { maximumDashboardAppointments = 4 } }
    }
    public var maximumUpcomingDatesPerLabel = 5
    public var upcomingHorizonDays = 14 {
        didSet { if !(1...365).contains(upcomingHorizonDays) { upcomingHorizonDays = 14 } }
    }
    public var defaultLabelID: UUID?
    public var scheduledDefaultEnabled = false
    public var scheduledCategoryConfigured = false
    public var scheduledLabelID: UUID?
    public var scheduledWeekdays: Set<Int> = [2, 3, 4, 5, 6] // Calendar: Sunday = 1.
    public var scheduledStartMinute = 8 * 60
    public var scheduledEndMinute = 17 * 60
    public var showLineNumbers = true
    public var indentWidth = 4
    public var checkSpelling = true
    public var automaticCorrection = false
    public var smartQuotes = false
    public var smartDashes = false
    public var screenZoom: [String: Int] = [:]
    public var appLockEnabled = false
    public var lockWhenInactive = false
    public var inactivityMinutes = 5
    public init(labelContext: LabelContext = .all, dateDisplayMode: DateDisplayMode = .chronological, taskRetention: RetentionPeriod = .thirty, dateRetention: RetentionPeriod = .thirty, maximumUpcomingDatesPerLabel: Int = 5, upcomingHorizonDays: Int = 14, maximumDashboardTasks: Int = 4, maximumDashboardAppointments: Int = 4) {
        self.labelContext = labelContext; self.dateDisplayMode = dateDisplayMode; self.taskRetention = taskRetention; self.dateRetention = dateRetention
        self.maximumUpcomingDatesPerLabel = maximumUpcomingDatesPerLabel
        self.upcomingHorizonDays = (1...365).contains(upcomingHorizonDays) ? upcomingHorizonDays : 14
        self.maximumDashboardTasks = (1...10).contains(maximumDashboardTasks) ? maximumDashboardTasks : 4
        self.maximumDashboardAppointments = (1...10).contains(maximumDashboardAppointments) ? maximumDashboardAppointments : 4
    }
    private enum CodingKeys: String, CodingKey {
        case labelContext, dateDisplayMode, taskRetention, dateRetention, maximumUpcomingDatesPerLabel, upcomingHorizonDays
        case maximumDashboardTasks, maximumDashboardAppointments
        case defaultLabelID, scheduledDefaultEnabled, scheduledCategoryConfigured, scheduledLabelID, scheduledWeekdays, scheduledStartMinute, scheduledEndMinute
        case showLineNumbers, indentWidth, checkSpelling, automaticCorrection, smartQuotes, smartDashes, screenZoom
        case appLockEnabled, lockWhenInactive, inactivityMinutes
    }
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        labelContext = try values.decodeIfPresent(LabelContext.self, forKey: .labelContext) ?? .all
        dateDisplayMode = try values.decodeIfPresent(DateDisplayMode.self, forKey: .dateDisplayMode) ?? .chronological
        taskRetention = try values.decodeIfPresent(RetentionPeriod.self, forKey: .taskRetention) ?? .thirty
        dateRetention = try values.decodeIfPresent(RetentionPeriod.self, forKey: .dateRetention) ?? .thirty
        let dashboardTasks = try values.decodeIfPresent(Int.self, forKey: .maximumDashboardTasks) ?? 4
        maximumDashboardTasks = (1...10).contains(dashboardTasks) ? dashboardTasks : 4
        let dashboardAppointments = try values.decodeIfPresent(Int.self, forKey: .maximumDashboardAppointments) ?? 4
        maximumDashboardAppointments = (1...10).contains(dashboardAppointments) ? dashboardAppointments : 4
        maximumUpcomingDatesPerLabel = try values.decodeIfPresent(Int.self, forKey: .maximumUpcomingDatesPerLabel) ?? 5
        let horizon = try values.decodeIfPresent(Int.self, forKey: .upcomingHorizonDays) ?? 14
        upcomingHorizonDays = (1...365).contains(horizon) ? horizon : 14
        defaultLabelID = try values.decodeIfPresent(UUID.self, forKey: .defaultLabelID)
        scheduledDefaultEnabled = try values.decodeIfPresent(Bool.self, forKey: .scheduledDefaultEnabled) ?? false
        scheduledCategoryConfigured = try values.decodeIfPresent(Bool.self, forKey: .scheduledCategoryConfigured) ?? false
        scheduledLabelID = try values.decodeIfPresent(UUID.self, forKey: .scheduledLabelID)
        scheduledWeekdays = try values.decodeIfPresent(Set<Int>.self, forKey: .scheduledWeekdays) ?? [2, 3, 4, 5, 6]
        scheduledStartMinute = try values.decodeIfPresent(Int.self, forKey: .scheduledStartMinute) ?? 8 * 60
        scheduledEndMinute = try values.decodeIfPresent(Int.self, forKey: .scheduledEndMinute) ?? 17 * 60
        showLineNumbers = try values.decodeIfPresent(Bool.self, forKey: .showLineNumbers) ?? true
        let width = try values.decodeIfPresent(Int.self, forKey: .indentWidth) ?? 4
        indentWidth = [2, 4, 8].contains(width) ? width : 4
        checkSpelling = try values.decodeIfPresent(Bool.self, forKey: .checkSpelling) ?? true
        automaticCorrection = try values.decodeIfPresent(Bool.self, forKey: .automaticCorrection) ?? false
        smartQuotes = try values.decodeIfPresent(Bool.self, forKey: .smartQuotes) ?? false
        smartDashes = try values.decodeIfPresent(Bool.self, forKey: .smartDashes) ?? false
        screenZoom = (try values.decodeIfPresent([String: Int].self, forKey: .screenZoom) ?? [:]).mapValues(ZoomLevel.validated)
        appLockEnabled = try values.decodeIfPresent(Bool.self, forKey: .appLockEnabled) ?? false
        lockWhenInactive = try values.decodeIfPresent(Bool.self, forKey: .lockWhenInactive) ?? false
        let minutes = try values.decodeIfPresent(Int.self, forKey: .inactivityMinutes) ?? 5
        inactivityMinutes = (1...120).contains(minutes) ? minutes : 5
    }

    public func resolvedDefaultLabelID(at date: Date = Date(), calendar: Calendar = .current, validLabels: [Label]) -> UUID? {
        let fallback = validLabels.contains { $0.id == defaultLabelID } ? defaultLabelID : nil
        guard scheduledDefaultEnabled, scheduledCategoryConfigured,
              scheduledStartMinute >= 0, scheduledEndMinute <= 24 * 60,
              scheduledStartMinute < scheduledEndMinute,
              scheduledWeekdays.contains(calendar.component(.weekday, from: date)) else { return fallback }
        let components = calendar.dateComponents([.hour, .minute], from: date)
        let minute = (components.hour ?? 0) * 60 + (components.minute ?? 0)
        guard scheduledStartMinute <= minute && minute < scheduledEndMinute else { return fallback }
        if let scheduledLabelID, !validLabels.contains(where: { $0.id == scheduledLabelID }) { return fallback }
        return scheduledLabelID
    }
}

public struct Workspace: Codable, Equatable {
    public var labels: [Label] = []
    public var notes: [Note] = []
    public var tasks: [Task] = []
    public var scheduledTodos: [ScheduledTodo] = []
    public var dates: [DateItem] = []
    public var settings = AppSettings()
    public var statisticsStartedAt: Date?
    public var historicalCompletedTodoCount = 0
    public var historicalPassedAppointmentCount = 0
    // Version 1 stores the user-defined order directly in `notes`. Older files
    // displayed Notes by creation time, regardless of their array order.
    private var noteOrderVersion = 1
    public init(labels: [Label] = [], notes: [Note] = [], tasks: [Task] = [], scheduledTodos: [ScheduledTodo] = [], dates: [DateItem] = [], settings: AppSettings = AppSettings(), statisticsStartedAt: Date? = nil, historicalCompletedTodoCount: Int = 0, historicalPassedAppointmentCount: Int = 0) {
        self.labels = labels; self.notes = notes; self.tasks = tasks; self.scheduledTodos = scheduledTodos; self.dates = dates; self.settings = settings
        self.statisticsStartedAt = statisticsStartedAt
        self.historicalCompletedTodoCount = historicalCompletedTodoCount
        self.historicalPassedAppointmentCount = historicalPassedAppointmentCount
    }

    private enum CodingKeys: String, CodingKey { case labels, notes, tasks, scheduledTodos, dates, settings, noteOrderVersion, statisticsStartedAt, historicalCompletedTodoCount, historicalPassedAppointmentCount }
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        labels = try values.decode([Label].self, forKey: .labels)
        notes = try values.decode([Note].self, forKey: .notes)
        tasks = try values.decode([Task].self, forKey: .tasks)
        scheduledTodos = try values.decodeIfPresent([ScheduledTodo].self, forKey: .scheduledTodos) ?? []
        dates = try values.decode([DateItem].self, forKey: .dates)
        settings = try values.decode(AppSettings.self, forKey: .settings)
        statisticsStartedAt = try values.decodeIfPresent(Date.self, forKey: .statisticsStartedAt)
        historicalCompletedTodoCount = try values.decodeIfPresent(Int.self, forKey: .historicalCompletedTodoCount) ?? 0
        historicalPassedAppointmentCount = try values.decodeIfPresent(Int.self, forKey: .historicalPassedAppointmentCount) ?? 0
        if try values.decodeIfPresent(Int.self, forKey: .noteOrderVersion) == nil {
            notes = notes.enumerated().sorted {
                $0.element.createdAt == $1.element.createdAt ? $0.offset < $1.offset : $0.element.createdAt < $1.element.createdAt
            }.map(\.element)
        }
    }

    public mutating func moveNote(from source: Int, to destination: Int) {
        guard notes.indices.contains(source), (0..<notes.count).contains(destination), source != destination else { return }
        let note = notes.remove(at: source)
        notes.insert(note, at: destination)
    }

    public var visibleNotes: [Note] { notes.filter { matches($0.labelID) } }
    public var shortcutNotes: [Note] { Array(visibleNotes.prefix(6)) }

    public mutating func deleteLabel(_ id: UUID) {
        labels.removeAll { $0.id == id }
        notes.indices.forEach { if notes[$0].labelID == id { notes[$0].labelID = nil } }
        tasks.indices.forEach { if tasks[$0].labelID == id { tasks[$0].labelID = nil } }
        scheduledTodos.indices.forEach { if scheduledTodos[$0].categoryID == id { scheduledTodos[$0].categoryID = nil } }
        dates.indices.forEach { if dates[$0].labelID == id { dates[$0].labelID = nil } }
        if settings.labelContext == .label(id) { settings.labelContext = .all }
        if settings.defaultLabelID == id { settings.defaultLabelID = nil }
        if settings.scheduledLabelID == id { settings.scheduledLabelID = nil; settings.scheduledCategoryConfigured = false; settings.scheduledDefaultEnabled = false }
    }

    public mutating func createNote(at now: Date = Date(), calendar: Calendar = .current) -> Note {
        let note = Note(title: "Untitled Note", labelID: settings.resolvedDefaultLabelID(at: now, calendar: calendar, validLabels: labels), createdAt: now, updatedAt: now)
        notes.append(note)
        return note
    }

    public func makeTaskDraft(at now: Date = Date(), calendar: Calendar = .current) -> Task {
        Task(title: "New To-do", labelID: settings.resolvedDefaultLabelID(at: now, calendar: calendar, validLabels: labels), createdAt: now)
    }

    public mutating func addTaskDraft(_ draft: Task) {
        guard !tasks.contains(where: { $0.id == draft.id }) else { return }
        var task = draft
        if task.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { task.title = "New To-do" }
        if !labels.contains(where: { $0.id == task.labelID }) { task.labelID = nil }
        tasks.append(task)
    }

    public mutating func createTask(at now: Date = Date(), calendar: Calendar = .current) -> Task {
        let task = makeTaskDraft(at: now, calendar: calendar)
        addTaskDraft(task)
        return task
    }

    @discardableResult public mutating func evaluateScheduledTodos(at now: Date = Date(), calendar: Calendar = .current) -> Int {
        let today = calendar.startOfDay(for: now)
        var created = 0
        for index in scheduledTodos.indices {
            var occurrence = calendar.startOfDay(for: scheduledTodos[index].nextOccurrence)
            guard occurrence <= today else { continue }
            var latestDue = occurrence
            repeat {
                latestDue = occurrence
                occurrence = scheduledTodos[index].recurrence.occurrence(after: occurrence, calendar: calendar)
            } while occurrence <= today
            scheduledTodos[index].nextOccurrence = occurrence
            guard scheduledTodos[index].lastGeneratedOccurrence != latestDue else { continue }
            let schedule = scheduledTodos[index]
            let categoryID = labels.contains { $0.id == schedule.categoryID } ? schedule.categoryID : nil
            tasks.append(Task(title: schedule.title, labelID: categoryID, createdAt: now))
            scheduledTodos[index].lastGeneratedOccurrence = latestDue
            created += 1
        }
        return created
    }

    public func makeAppointmentDraft(at now: Date = Date(), calendar: Calendar = .current) -> DateItem {
        DateItem(title: "New Appointment", date: calendar.startOfDay(for: now), labelID: settings.resolvedDefaultLabelID(at: now, calendar: calendar, validLabels: labels), createdAt: now)
    }

    public mutating func addAppointmentDraft(_ draft: DateItem) {
        guard !dates.contains(where: { $0.id == draft.id }) else { return }
        var appointment = draft
        if appointment.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { appointment.title = "New Appointment" }
        if !labels.contains(where: { $0.id == appointment.labelID }) { appointment.labelID = nil }
        dates.append(appointment)
    }

    public mutating func createAppointment(at now: Date = Date(), calendar: Calendar = .current) -> DateItem {
        let appointment = makeAppointmentDraft(at: now, calendar: calendar)
        addAppointmentDraft(appointment)
        return appointment
    }

    public func matches(_ labelID: UUID?, context: LabelContext? = nil) -> Bool {
        switch context ?? settings.labelContext {
        case .all: true
        case .unlabelled: true
        case .label(let id): labelID == id
        }
    }

    public func isPassed(_ item: DateItem, calendar: Calendar = .current, now: Date = Date()) -> Bool {
        item.date < calendar.startOfDay(for: now)
    }

    public func daysPassed(now: Date = Date(), calendar: Calendar = .current) -> Int {
        guard let statisticsStartedAt else { return 0 }
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: statisticsStartedAt), to: calendar.startOfDay(for: now)).day ?? 0
        return max(1, days + 1)
    }

    public var completedTodoCount: Int {
        historicalCompletedTodoCount + tasks.count { $0.completedAt != nil }
    }

    public func passedAppointmentCount(now: Date = Date(), calendar: Calendar = .current) -> Int {
        historicalPassedAppointmentCount + dates.count { isPassed($0, calendar: calendar, now: now) }
    }

    public func matchingDates(showPast: Bool, calendar: Calendar = .current, now: Date = Date()) -> [DateItem] {
        dates.filter { matches($0.labelID) && (showPast || !isPassed($0, calendar: calendar, now: now)) }
            .sorted { $0.date < $1.date }
    }

    public func upcomingDates(calendar: Calendar = .current, now: Date = Date()) -> [DateItem] {
        let today = calendar.startOfDay(for: now)
        guard let lastDay = calendar.date(byAdding: .day, value: settings.upcomingHorizonDays, to: today) else { return [] }
        var counts: [UUID?: Int] = [:]
        return dates.filter { item in
            let day = calendar.startOfDay(for: item.date)
            return matches(item.labelID) && day >= today && day <= lastDay
        }.sorted { $0.date < $1.date }.filter { item in
            let count = counts[item.labelID, default: 0]
            guard count < max(1, settings.maximumUpcomingDatesPerLabel) else { return false }
            counts[item.labelID] = count + 1
            return true
        }
    }

    public func dateGroups(showPast: Bool, expanded: Set<String> = [], calendar: Calendar = .current, now: Date = Date()) -> [DateGroup] {
        let today = calendar.startOfDay(for: now)
        let lastDay = calendar.date(byAdding: .day, value: settings.upcomingHorizonDays, to: today) ?? today
        let matching = matchingDates(showPast: showPast, calendar: calendar, now: now).filter {
            isPassed($0, calendar: calendar, now: now) || calendar.startOfDay(for: $0.date) <= lastDay
        }
        let limit = max(1, settings.maximumUpcomingDatesPerLabel)
        return Set(matching.map(\.labelID)).map { labelID in
            let key = labelID?.uuidString ?? "unlabelled"
            let name = labels.first(where: { $0.id == labelID })?.name ?? "Uncategorized"
            let group = matching.filter { $0.labelID == labelID }
            let passed = group.filter { isPassed($0, calendar: calendar, now: now) }
            let upcoming = group.filter { !isPassed($0, calendar: calendar, now: now) }
            let shown = passed + (expanded.contains(key) ? upcoming : Array(upcoming.prefix(limit)))
            return DateGroup(id: key, name: name, items: shown, hiddenUpcomingCount: max(0, upcoming.count - limit))
        }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    public mutating func purgeExpired(now: Date = Date(), calendar: Calendar = .current) {
        let today = calendar.startOfDay(for: now)
        if settings.taskRetention != .never {
            let days = settings.taskRetention.rawValue
            var removed = 0
            tasks.removeAll { task in
                guard let completed = task.completedAt,
                      let expiry = calendar.date(byAdding: .day, value: days, to: completed) else { return false }
                if now > expiry { removed += 1; return true }
                return false
            }
            historicalCompletedTodoCount += removed
        }
        if settings.dateRetention != .never {
            let days = settings.dateRetention.rawValue
            var removed = 0
            dates.removeAll { item in
                guard item.date < today,
                      let expiry = calendar.date(byAdding: .day, value: days, to: calendar.startOfDay(for: item.date)) else { return false }
                if today > expiry { removed += 1; return true }
                return false
            }
            historicalPassedAppointmentCount += removed
        }
    }
}
