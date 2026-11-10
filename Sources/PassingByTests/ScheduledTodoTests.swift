import Foundation
import PassingByCore

func testScheduledTodoDatesAndCompatibility() throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    func day(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }
    func first(_ recurrence: ScheduleRecurrence, _ year: Int, _ month: Int, _ date: Int) -> Date {
        recurrence.firstOccurrence(onOrAfter: day(year, month, date), calendar: calendar)
    }
    func next(_ recurrence: ScheduleRecurrence, _ date: Date) -> Date {
        recurrence.occurrence(after: date, calendar: calendar)
    }

    let weekly = ScheduleRecurrence.weekly(interval: .everyWeek, weekday: .monday)
    expect(first(weekly, 2026, 10, 3) == day(2026, 10, 5), "weekly picks the next selected weekday")
    expect(first(weekly, 2026, 10, 5) == day(2026, 10, 5), "weekly includes today when selected")
    expect(next(weekly, day(2026, 10, 5)) == day(2026, 10, 12), "weekly advances seven days")
    expect(next(weekly, day(2026, 12, 28)) == day(2027, 1, 4), "weekly crosses the year boundary")

    let biweekly = ScheduleRecurrence.weekly(interval: .everyTwoWeeks, weekday: .friday)
    let anchor = first(biweekly, 2026, 10, 3)
    expect(anchor == day(2026, 10, 9), "biweekly starts on the next selected weekday")
    expect(next(biweekly, anchor) == day(2026, 10, 23), "biweekly advances fourteen days")
    expect(next(biweekly, next(biweekly, anchor)) == day(2026, 11, 6), "biweekly crosses month boundary from its original anchor")
    expect(next(biweekly, day(2026, 12, 25)) == day(2027, 1, 8), "biweekly crosses the year boundary")

    let firstDay = ScheduleRecurrence.monthly(.firstDay)
    expect(first(firstDay, 2026, 10, 1) == day(2026, 10, 1), "first day includes today")
    expect(first(firstDay, 2026, 10, 3) == day(2026, 11, 1), "first day selects next month once passed")
    expect(next(firstDay, day(2026, 12, 1)) == day(2027, 1, 1), "monthly crosses December to January")

    let firstWeekday = ScheduleRecurrence.monthly(.firstWeekday)
    expect(first(firstWeekday, 2026, 6, 1) == day(2026, 6, 1), "weekday on the first remains the first")
    expect(first(firstWeekday, 2026, 8, 1) == day(2026, 8, 3), "Saturday on the first becomes Monday the third")
    expect(first(firstWeekday, 2026, 11, 1) == day(2026, 11, 2), "Sunday on the first becomes Monday the second")

    let lastDay = ScheduleRecurrence.monthly(.lastDay)
    expect(first(lastDay, 2026, 10, 3) == day(2026, 10, 31), "last day picks month end")
    expect(first(lastDay, 2026, 10, 31) == day(2026, 10, 31), "last day includes today")
    expect(next(lastDay, day(2026, 1, 31)) == day(2026, 2, 28), "monthly advancement from the thirty-first reaches February")
    expect(next(lastDay, day(2024, 1, 31)) == day(2024, 2, 29), "monthly advancement handles leap February")

    let lastWeekday = ScheduleRecurrence.monthly(.lastWeekday)
    expect(first(lastWeekday, 2026, 7, 1) == day(2026, 7, 31), "weekday on the last remains the last")
    expect(first(lastWeekday, 2026, 10, 1) == day(2026, 10, 30), "Saturday at month end becomes Friday")
    expect(first(lastWeekday, 2026, 5, 1) == day(2026, 5, 29), "Sunday at month end becomes Friday")
    expect(next(lastWeekday, day(2024, 2, 29)) == day(2024, 3, 29), "last weekday advances after leap February")

    let category = Label(name: "Work")
    let schedule = ScheduledTodo(
        title: "Review", categoryID: category.id, recurrence: biweekly, startingOn: day(2026, 10, 3), calendar: calendar)
    var workspace = Workspace(labels: [category], scheduledTodos: [schedule])
    let persisted = try JSONEncoder().encode(workspace)
    let reloaded = try JSONDecoder().decode(Workspace.self, from: persisted)
    expect(reloaded == workspace, "schedule and selected Category round trip")
    var legacy = try JSONSerialization.jsonObject(with: persisted) as! [String: Any]
    legacy.removeValue(forKey: "scheduledTodos")
    let oldData = try JSONSerialization.data(withJSONObject: legacy)
    let loadedLegacy = try JSONDecoder().decode(Workspace.self, from: oldData)
    expect(loadedLegacy.scheduledTodos.isEmpty, "older workspace without schedule data loads")
    workspace.deleteLabel(category.id)
    expect(workspace.scheduledTodos[0].categoryID == nil, "deleting a selected Category makes the schedule Uncategorized")
}

func testScheduledTodoGenerationAndAtomicPersistence() throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    func day(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }
    let category = Label(name: "Finances")
    let fallback = Label(name: "Default")
    let monthly = ScheduledTodo(
        title: "Finances previous month", categoryID: category.id, recurrence: .monthly(.firstDay), startingOn: day(2030, 7, 1),
        calendar: calendar)
    var settings = AppSettings()
    settings.defaultLabelID = fallback.id
    var workspace = Workspace(labels: [category, fallback], scheduledTodos: [monthly], settings: settings)

    expect(
        workspace.evaluateScheduledTodos(at: day(2030, 6, 30), calendar: calendar) == 0 && workspace.tasks.isEmpty,
        "future occurrence generates nothing")
    expect(workspace.evaluateScheduledTodos(at: day(2030, 7, 1), calendar: calendar) == 1, "occurrence due today generates a To-do")
    expect(
        workspace.tasks[0].title == monthly.title && workspace.tasks[0].labelID == category.id,
        "generated To-do uses static title and selected Category instead of Default Category")
    expect(workspace.scheduledTodos[0].lastGeneratedOccurrence == day(2030, 7, 1), "generated identity records its due date")
    expect(workspace.scheduledTodos[0].nextOccurrence == day(2030, 8, 1), "next occurrence advances after generation")
    expect(
        workspace.evaluateScheduledTodos(at: day(2030, 7, 1), calendar: calendar) == 0 && workspace.tasks.count == 1,
        "repeated evaluation is idempotent")
    expect(
        workspace.evaluateScheduledTodos(at: day(2030, 7, 31), calendar: calendar) == 0, "subsequent evaluation waits for next occurrence")
    expect(
        workspace.evaluateScheduledTodos(at: day(2030, 10, 3), calendar: calendar) == 1 && workspace.tasks.count == 2,
        "several missed monthly dates create one To-do")
    expect(workspace.scheduledTodos[0].lastGeneratedOccurrence == day(2030, 10, 1), "monthly catch-up uses latest due occurrence")
    expect(workspace.scheduledTodos[0].nextOccurrence == day(2030, 11, 1), "monthly catch-up advances to first future occurrence")

    workspace.tasks[0].completedAt = day(2030, 10, 3)
    expect(
        workspace.evaluateScheduledTodos(at: day(2030, 11, 1), calendar: calendar) == 1,
        "completed previous To-do does not suppress generation")
    workspace.tasks.removeLast()
    expect(
        workspace.evaluateScheduledTodos(at: day(2030, 12, 1), calendar: calendar) == 1,
        "deleted previous To-do does not suppress generation")
    let remaining = workspace.tasks
    workspace.scheduledTodos.removeAll()
    expect(
        workspace.tasks == remaining && workspace.evaluateScheduledTodos(at: day(2031, 1, 1), calendar: calendar) == 0,
        "deleting schedule leaves generated To-dos untouched")

    let weekly = ScheduledTodo(
        title: "Weekly", categoryID: nil, recurrence: .weekly(interval: .everyWeek, weekday: .monday), startingOn: day(2030, 9, 2),
        calendar: calendar)
    var weeklyWorkspace = Workspace(labels: [fallback], tasks: [Task(title: "Weekly")], scheduledTodos: [weekly], settings: settings)
    expect(
        weeklyWorkspace.evaluateScheduledTodos(at: day(2030, 10, 3), calendar: calendar) == 1 && weeklyWorkspace.tasks.count == 2,
        "several missed weekly dates create one To-do even with an open item of the same title")
    expect(weeklyWorkspace.tasks[1].labelID == nil, "explicit Uncategorized schedule does not use Default Category")
    expect(weeklyWorkspace.scheduledTodos[0].lastGeneratedOccurrence == day(2030, 9, 30), "weekly catch-up uses latest due Monday")
    expect(weeklyWorkspace.scheduledTodos[0].nextOccurrence == day(2030, 10, 7), "weekly catch-up advances to first future Monday")
    expect(weeklyWorkspace.evaluateScheduledTodos(at: day(2030, 10, 3), calendar: calendar) == 0, "weekly catch-up is idempotent")

    let biweekly = ScheduledTodo(
        title: "Biweekly", categoryID: nil, recurrence: .weekly(interval: .everyTwoWeeks, weekday: .friday), startingOn: day(2030, 9, 6),
        calendar: calendar)
    var biweeklyWorkspace = Workspace(scheduledTodos: [biweekly])
    expect(biweeklyWorkspace.evaluateScheduledTodos(at: day(2030, 10, 3), calendar: calendar) == 1, "biweekly catch-up creates one To-do")
    expect(biweeklyWorkspace.scheduledTodos[0].lastGeneratedOccurrence == day(2030, 9, 20), "biweekly catch-up retains original anchor")
    expect(biweeklyWorkspace.scheduledTodos[0].nextOccurrence == day(2030, 10, 4), "biweekly next date follows anchored cadence")

    let files = FileManager.default
    let directory = files.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? files.removeItem(at: directory) }
    let persistence = WorkspacePersistence(url: directory.appendingPathComponent("workspace.json"))
    let stored = Workspace(scheduledTodos: [monthly], statisticsStartedAt: day(2029, 1, 1))
    try persistence.save(stored)
    let store = try AppStore(persistence: persistence)
    let blockedBackup = persistence.url.appendingPathExtension("backup")
    try files.createDirectory(at: blockedBackup, withIntermediateDirectories: false)
    expect(store.evaluateScheduledTodos(at: day(2030, 10, 3), calendar: calendar) == 0, "failed save does not publish generated To-do")
    expect(
        store.workspace.tasks.isEmpty && store.workspace.scheduledTodos[0].nextOccurrence == day(2030, 7, 1),
        "failed save retains old cursor and task list")
    let unchanged = try persistence.load()
    expect(unchanged == stored, "failed save leaves persisted workspace unchanged")
    try files.removeItem(at: blockedBackup)
    expect(store.evaluateScheduledTodos(at: day(2030, 10, 3), calendar: calendar) == 1, "retry persists one latest due To-do")
    let reloaded = try AppStore(persistence: persistence)
    expect(
        reloaded.workspace.tasks.count == 1 && reloaded.workspace.scheduledTodos[0].lastGeneratedOccurrence == day(2030, 10, 1),
        "restart preserves generated occurrence identity")
    expect(reloaded.evaluateScheduledTodos(at: day(2030, 10, 3), calendar: calendar) == 0, "restart does not duplicate occurrence")
}
