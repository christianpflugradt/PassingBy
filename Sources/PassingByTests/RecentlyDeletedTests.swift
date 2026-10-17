import Foundation
import PassingByCore

func testRecentlyDeletedRoundTripAndRestoration() throws {
    let now = Date()
    let category = Label(name: "Work")
    var note = Note(title: "Research", contentMarkdown: "# Notes\n\n- [x] Keep `literal` text 🐝\n", labelID: category.id, iconName: "book")
    note.zoomPercent = 140
    let otherNote = Note(title: "Other")
    let task = Task(title: "Done", taskDescription: "Details", labelID: category.id, completedAt: now)
    let appointment = DateItem(title: "Meeting", date: now, itemDescription: "18:00", labelID: category.id)
    var workspace = Workspace(labels: [category], notes: [note, otherNote], tasks: [task], dates: [appointment])
    workspace.settings.labelContext = .label(category.id)
    workspace.deleteNote(note.id, at: now)
    workspace.deleteTask(task.id, at: now)
    workspace.deleteAppointment(appointment.id, at: now)
    workspace.deleteNote(note.id, at: now)
    expect(workspace.recentlyDeleted.count == 3, "repeated deletion cannot duplicate recovery entries")
    expect(workspace.visibleNotes.isEmpty && workspace.tasks.isEmpty && workspace.dates.isEmpty, "deleted content leaves normal collections and filters")
    expect(workspace.completedTodoCount == 0, "deleted completed To-do is excluded from statistics")
    let reloaded = try JSONDecoder().decode(Workspace.self, from: JSONEncoder().encode(workspace))
    expect(reloaded == workspace, "all deleted payload types persist completely")
    workspace = reloaded
    for item in workspace.recentlyDeleted {
        expect(workspace.restoreDeletedItem(item.id, at: now), "each deleted item can be restored")
        expect(!workspace.restoreDeletedItem(item.id, at: now), "restore cannot run twice")
    }
    expect(workspace.notes == [note, otherNote], "Note content, identity, timestamps, icon, zoom and position are preserved")
    expect(workspace.tasks[0].id == task.id && workspace.tasks[0].completedAt == task.completedAt && workspace.tasks[0].taskDescription == task.taskDescription, "restoring deletion keeps completion state and all To-do content")
    expect(workspace.dates[0].id == appointment.id && workspace.dates[0].date == appointment.date && workspace.dates[0].itemDescription == appointment.itemDescription, "Appointment identity, date and description survive")
    expect(workspace.completedTodoCount == 1 && workspace.recentlyDeleted.isEmpty, "restoration adds statistics exactly once and removes recovery entries")
    expect(workspace.settings.labelContext == .label(category.id), "restore preserves the global filter")
    workspace.deleteNote(note.id, at: now)
    workspace.deleteTask(task.id, at: now)
    workspace.deleteAppointment(appointment.id, at: now)
    workspace.deleteLabel(category.id)
    for item in workspace.recentlyDeleted { workspace.restoreDeletedItem(item.id, at: now) }
    expect(workspace.notes[0].labelID == nil && workspace.tasks[0].labelID == nil && workspace.dates[0].labelID == nil, "missing Categories restore as Uncategorized for every item type")
}

func testRecentlyDeletedExpiryAndRetention() throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
    let now = calendar.date(from: DateComponents(year: 2026, month: 10, day: 17, hour: 12))!
    func day(_ offset: Int) -> Date { calendar.date(byAdding: .day, value: offset, to: now)! }
    let note = Note(title: "Expired")
    let task = Task(title: "Completed", completedAt: day(-100))
    let appointment = DateItem(title: "Passed", date: day(-100))
    var workspace = Workspace(notes: [note], tasks: [task], dates: [appointment])
    workspace.deleteNote(note.id, at: now)
    let deletedNote = workspace.recentlyDeleted[0]
    expect(!deletedNote.hasExpired(at: day(30).addingTimeInterval(-1), calendar: calendar), "recovery remains available until its expiry, including daylight saving changes")
    expect(deletedNote.hasExpired(at: day(30), calendar: calendar), "recovery ends at exactly 30 calendar days")
    expect(!workspace.restoreDeletedItem(deletedNote.id, at: day(30), calendar: calendar), "expired items cannot be restored before cleanup")
    workspace.deleteTask(task.id, at: now)
    workspace.deleteAppointment(appointment.id, at: now)
    let expiredData = workspace
    for item in workspace.recentlyDeleted { workspace.restoreDeletedItem(item.id, at: day(1), calendar: calendar) }
    workspace.settings.taskRetention = .seven
    workspace.settings.dateRetention = .seven
    workspace.purgeExpired(now: day(1), calendar: calendar)
    expect(workspace.tasks.count == 1 && workspace.dates.count == 1, "old completed/passed restored items survive immediate cleanup")
    expect(workspace.tasks[0].completedAt == task.completedAt && workspace.dates[0].date == appointment.date, "retention protection does not rewrite original dates")
    workspace = try JSONDecoder().decode(Workspace.self, from: JSONEncoder().encode(workspace))
    workspace.purgeExpired(now: day(8), calendar: calendar)
    expect(workspace.tasks.count == 1 && workspace.dates.count == 1, "restoration retention protection survives restart and the configured window")
    workspace.purgeExpired(now: day(9), calendar: calendar)
    expect(workspace.tasks.isEmpty && workspace.dates.isEmpty && workspace.recentlyDeleted.isEmpty, "ordinary cleanup resumes after restoration without entering Recently Deleted")
    expect(workspace.completedTodoCount == 1 && workspace.passedAppointmentCount(now: day(9), calendar: calendar) == 1, "retention after restoration preserves lifetime totals exactly once")
    expect(workspace.notes == [note], "restored Notes have no automatic retention")
    var expired = expiredData
    expired.purgeExpired(now: day(30), calendar: calendar)
    expect(expired.recentlyDeleted.isEmpty && expired.completedTodoCount == 0 && expired.passedAppointmentCount(now: day(30), calendar: calendar) == 0, "expired deleted items are purged without contributing statistics")

    var later = Workspace(tasks: [task], dates: [appointment])
    later.deleteTask(task.id, at: now)
    later.deleteAppointment(appointment.id, at: now)
    for item in later.recentlyDeleted { later.restoreDeletedItem(item.id, at: now, calendar: calendar) }
    later.tasks[0].completedAt = day(10)
    later.dates[0].date = day(10)
    later.purgeExpired(now: day(35), calendar: calendar)
    expect(later.tasks.count == 1 && later.dates.count == 1, "later completion or Appointment dates take precedence over the restoration date")
    later.settings.taskRetention = .never
    later.settings.dateRetention = .never
    later.purgeExpired(now: day(1000), calendar: calendar)
    expect(later.tasks.count == 1 && later.dates.count == 1, "Never retention is respected after recovery")
}

func testRecentlyDeletedMigrationAndAtomicPersistence() throws {
    let files = FileManager.default
    let directory = files.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? files.removeItem(at: directory) }
    let persistence = WorkspacePersistence(url: directory.appendingPathComponent("workspace.json"))
    let now = Date()
    let note = Note(title: "Keep", contentMarkdown: "Unsaved-looking but persisted")
    var old = Workspace(notes: [note], tasks: [Task(title: "Done", completedAt: now)], dates: [DateItem(title: "Date", date: now)], statisticsStartedAt: now)
    old.settings.taskRetention = .ninety
    old.settings.dateRetention = .ninety
    var legacy = try JSONSerialization.jsonObject(with: JSONEncoder().encode(old)) as! [String: Any]
    legacy.removeValue(forKey: "recentlyDeleted")
    legacy["futureField"] = true
    let legacyData = try JSONSerialization.data(withJSONObject: legacy)
    let migrated = try JSONDecoder().decode(Workspace.self, from: legacyData)
    expect(migrated == old && migrated.recentlyDeleted.isEmpty, "older files have an empty recovery list and optional restoration timestamps without losing content or settings")
    try persistence.save(migrated)
    let store = try AppStore(persistence: persistence)
    store.change { $0.deleteNote(note.id, at: now) }
    let restarted = try AppStore(persistence: persistence)
    expect(restarted.workspace.notes.isEmpty && restarted.workspace.recentlyDeleted.count == 1, "deletion and recovery entry survive restart together")
    let recoveryID = restarted.workspace.recentlyDeleted[0].id
    let before = restarted.workspace
    let backup = persistence.url.appendingPathExtension("backup")
    try files.removeItem(at: backup)
    try files.createDirectory(at: backup, withIntermediateDirectories: false)
    do {
        _ = try restarted.restoreDeletedItem(recoveryID, at: now)
        expect(false, "restoration must report a failed write")
    } catch { }
    expect(restarted.persistenceError != nil && restarted.workspace == before, "failed restoration preserves the entry and state for retry")
    let unchanged = try persistence.load()
    expect(unchanged == before, "failed restore does not alter saved data")
    try files.removeItem(at: backup)
    let restored = try restarted.restoreDeletedItem(recoveryID, at: now)
    expect(restored && restarted.persistenceError == nil, "restoration succeeds on retry")
    let reopened = try AppStore(persistence: persistence)
    expect(reopened.workspace.notes == [note] && reopened.workspace.recentlyDeleted.isEmpty, "successful restore survives restart without a duplicate recovery entry")
    expect(reopened.workspace.tasks == old.tasks && reopened.workspace.dates == old.dates && reopened.workspace.settings == old.settings, "migration and recovery preserve unrelated data")
    try files.removeItem(at: backup)
    try files.createDirectory(at: backup, withIntermediateDirectories: false)
    reopened.change { $0.deleteNote(note.id, at: now) }
    expect(reopened.persistenceError != nil && reopened.workspace.recentlyDeleted.count == 1, "failed deletion save keeps the recovery payload in memory")
    let savedBeforeFailure = try persistence.load()
    expect(savedBeforeFailure.notes == [note], "failed deletion save keeps the original Note on disk")
    try files.removeItem(at: backup)
    expect(reopened.flush(), "failed deletion can be safely retried")
    let afterRetry = try AppStore(persistence: persistence)
    expect(afterRetry.workspace.notes.isEmpty && afterRetry.workspace.recentlyDeleted.count == 1, "retry persists deletion and its recovery entry together")
}
