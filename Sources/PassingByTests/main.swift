import AppKit
import Foundation
import PassingByCore

func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() { fputs("FAIL: \(message)\n", stderr); exit(1) }
}

func testDeletingLabelUnlabelsEveryItemAndResetsFilter() {
        let label = Label(name: "Private")
        let note = Note(title: "N", labelID: label.id)
        let task = Task(title: "T", labelID: label.id)
        let item = DateItem(title: "D", date: Date(), labelID: label.id)
        var workspace = Workspace(labels: [label], notes: [note], tasks: [task], dates: [item], settings: AppSettings(labelContext: .label(label.id)))
        workspace.deleteLabel(label.id)
        expect(workspace.labels.isEmpty, "label is deleted")
        expect(workspace.notes[0].labelID == nil && workspace.tasks[0].labelID == nil && workspace.dates[0].labelID == nil, "items become unlabelled")
        expect(workspace.settings.labelContext == .all, "deleted filter resets")
}

func testRetentionNeverDeletesOpenTasksOrFutureDates() {
        let calendar = Calendar(identifier: .gregorian)
        let now = Date(timeIntervalSinceReferenceDate: 10_000_000)
        let open = Task(title: "Open")
        let future = DateItem(title: "Future", date: calendar.date(byAdding: .day, value: 10, to: now)!)
        var workspace = Workspace(tasks: [open], dates: [future])
        workspace.purgeExpired(now: now, calendar: calendar)
        expect(workspace.tasks.map(\.id) == [open.id] && workspace.dates.map(\.id) == [future.id], "active content survives retention")
}

func testRetentionRemovesOnlyExpiredCompletedAndPassedItems() {
        let calendar = Calendar(identifier: .gregorian)
        let now = Date(timeIntervalSinceReferenceDate: 20_000_000)
        let oldTask = Task(title: "old", completedAt: calendar.date(byAdding: .day, value: -31, to: now))
        let recentTask = Task(title: "recent", completedAt: calendar.date(byAdding: .day, value: -2, to: now))
        let oldDate = DateItem(title: "old", date: calendar.date(byAdding: .day, value: -31, to: now)!)
        var workspace = Workspace(tasks: [oldTask, recentTask], dates: [oldDate])
        workspace.purgeExpired(now: now, calendar: calendar)
        expect(workspace.tasks.map(\.id) == [recentTask.id] && workspace.dates.isEmpty, "only expired inactive content is removed")
}

func testGlobalContextMatchesAllAndOneLabel() {
        let label = Label(name: "Work")
        let workspace = Workspace(labels: [label])
        expect(workspace.matches(nil, context: .all) && workspace.matches(label.id, context: .all), "All includes categorized and uncategorized items")
        expect(!workspace.matches(nil, context: .label(label.id)) && workspace.matches(label.id, context: .label(label.id)), "a category excludes uncategorized items")
        expect(workspace.matches(label.id, context: .unlabelled), "legacy uncategorized filter no longer hides categorized items")
}

func testPersistenceRoundTrip() throws {
        let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("PassingByTests-\(UUID().uuidString).json")
        let persistence = WorkspacePersistence(url: url)
        let workspace = Workspace(notes: [Note(title: "Persisted", contentMarkdown: "# Hi")])
        try persistence.save(workspace)
        let loaded = try persistence.load()
        expect(loaded == workspace, "persistence round trip")
        try? FileManager.default.removeItem(at: url)
}

func testZoomPersistenceAndLegacyDefaults() throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("PassingByZoom-\(UUID().uuidString).json")
    defer { try? FileManager.default.removeItem(at: url) }
    let persistence = WorkspacePersistence(url: url)
    var first = Note(title: "First")
    first.zoomPercent = 150
    let second = Note(title: "Second")
    var workspace = Workspace(notes: [first, second], tasks: [Task(title: "Existing To-do")], dates: [DateItem(title: "Existing Appointment", date: Date())])
    workspace.settings.screenZoom = ["dashboard": 120, "tasks": 80]
    try persistence.save(workspace)
    let loaded = try persistence.load()
    expect(loaded.notes.map(\.zoomPercent) == [150, 100], "Notes keep independent zoom, and new Notes start at default")
    expect(loaded.settings.screenZoom == ["dashboard": 120, "tasks": 80], "screen zoom persists independently")

    var encoded = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: Any]
    encoded["futureWorkspaceField"] = "ignored"
    var notes = encoded["notes"] as! [[String: Any]]
    notes[0].removeValue(forKey: "zoomPercent")
    notes[0]["futureNoteField"] = "ignored"
    encoded["notes"] = notes
    var settings = encoded["settings"] as! [String: Any]
    settings.removeValue(forKey: "screenZoom")
    settings["futureSettingsField"] = "ignored"
    encoded["settings"] = settings
    var tasks = encoded["tasks"] as! [[String: Any]]
    tasks[0]["futureTaskField"] = "ignored"
    encoded["tasks"] = tasks
    var dates = encoded["dates"] as! [[String: Any]]
    dates[0]["futureAppointmentField"] = "ignored"
    encoded["dates"] = dates
    try JSONSerialization.data(withJSONObject: encoded).write(to: url)
    let legacy = try persistence.load()
    expect(legacy.notes[0].zoomPercent == 100 && legacy.settings.screenZoom.isEmpty, "older workspaces use default zoom")
    expect(legacy.notes.map(\.title) == ["First", "Second"] && legacy.tasks[0].title == "Existing To-do" && legacy.dates[0].title == "Existing Appointment", "unknown fields do not discard existing items")
    var updated = legacy
    updated.notes[0].zoomPercent = 130
    updated.settings.screenZoom["dashboard"] = 110
    try persistence.save(updated)
    let reloaded = try persistence.load()
    expect(reloaded.notes[0].zoomPercent == 130 && reloaded.settings.screenZoom["dashboard"] == 110, "new zoom values persist after loading older data")
    expect(reloaded.notes.map(\.title) == ["First", "Second"] && reloaded.tasks[0].title == "Existing To-do" && reloaded.dates[0].title == "Existing Appointment", "older content survives subsequent saves")
    expect(ZoomLevel.validated(20) == 100 && ZoomLevel.validated(105) == 100, "invalid saved zoom uses default")
}

func testWorkspaceDirectoryMigration() throws {
    let files = FileManager.default
    let root = files.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? files.removeItem(at: root) }
    let canonical = root.appendingPathComponent("Passing By", isDirectory: true)
    let legacy = root.appendingPathComponent("Passing by", isDirectory: true)
    let current = canonical.appendingPathComponent("workspace.json")
    let old = legacy.appendingPathComponent("workspace.json")
    let oldWorkspace = Workspace(notes: [Note(title: "Legacy")])

    let empty = try WorkspacePersistence.standard(applicationSupportDirectory: root)
    let initialWorkspace = try empty.load()
    expect(empty.url == current && initialWorkspace == Workspace(), "no legacy data uses canonical path")
    expect(!files.fileExists(atPath: canonical.path), "path lookup does not create an empty destination")

    try WorkspacePersistence(url: old).save(oldWorkspace)
    try Data("previous backup".utf8).write(to: old.appendingPathExtension("backup"))
    try Data("other data".utf8).write(to: legacy.appendingPathComponent("settings.dat"))
    let migrated = try WorkspacePersistence.standard(applicationSupportDirectory: root)
    let loaded = try migrated.load()
    let backupContents = try String(contentsOf: current.appendingPathExtension("backup"), encoding: .utf8)
    let otherContents = try String(contentsOf: canonical.appendingPathComponent("settings.dat"), encoding: .utf8)
    expect(migrated.url == current && loaded == oldWorkspace, "legacy workspace migrates to canonical path")
    expect(backupContents == "previous backup", "migration preserves backup")
    expect(otherContents == "other data", "migration preserves other persistence files")
    let migratedEntries = try files.contentsOfDirectory(atPath: root.path)
    expect(migratedEntries.contains("Passing By") && !migratedEntries.contains("Passing by"), "successful directory migration records canonical name")

    let canonicalWorkspace = Workspace(notes: [Note(title: "Canonical")])
    try migrated.save(canonicalWorkspace)
    let selected = try WorkspacePersistence.standard(applicationSupportDirectory: root)
    let selectedWorkspace = try selected.load()
    expect(selectedWorkspace == canonicalWorkspace, "existing canonical workspace wins")
}

func testWorkspaceMigrationFailureKeepsLegacyData() throws {
    let files = FileManager.default
    let root = files.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? files.removeItem(at: root) }
    let legacy = root.appendingPathComponent("Passing by", isDirectory: true)
    let old = legacy.appendingPathComponent("workspace.json")
    try files.createDirectory(at: legacy, withIntermediateDirectories: true)
    try Data("legacy backup".utf8).write(to: old.appendingPathExtension("backup"))
    do {
        _ = try WorkspacePersistence.standard(applicationSupportDirectory: root)
        expect(false, "backup without primary workspace must stop migration")
    } catch { }
    let preservedBackup = try String(contentsOf: old.appendingPathExtension("backup"), encoding: .utf8)
    expect(preservedBackup == "legacy backup", "failed migration leaves legacy backup intact")
    let remainingEntries = try files.contentsOfDirectory(atPath: root.path)
    expect(remainingEntries.contains("Passing by") && !remainingEntries.contains("Passing By"), "failed migration does not publish a canonical directory")
}

func testNoteIconPersistenceAndLegacyFallback() throws {
    let note = Note(title: "Icon", iconName: "lightbulb")
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let persistence = WorkspacePersistence(url: directory.appendingPathComponent("workspace.json"))
    try persistence.save(Workspace(notes: [note]))
    let saved = try persistence.load()
    expect(saved.notes[0].iconName == "lightbulb", "selected Note icon survives reload")
    var legacy = try JSONSerialization.jsonObject(with: Data(contentsOf: persistence.url)) as! [String: Any]
    var notes = legacy["notes"] as! [[String: Any]]
    notes[0].removeValue(forKey: "iconName")
    legacy["notes"] = notes
    try JSONSerialization.data(withJSONObject: legacy).write(to: persistence.url)
    let loadedLegacy = try persistence.load()
    expect(loadedLegacy.notes[0].iconName == NoteIcon.defaultName, "old Note without icon gets the default")
    notes[0]["iconName"] = "unknown.symbol"
    legacy["notes"] = notes
    try JSONSerialization.data(withJSONObject: legacy).write(to: persistence.url)
    let loadedUnknown = try persistence.load()
    expect(loadedUnknown.notes[0].iconName == NoteIcon.defaultName, "unknown icon falls back safely")

    for oldName in NoteIcon.legacyNames {
        notes[0]["iconName"] = oldName
        legacy["notes"] = notes
        try JSONSerialization.data(withJSONObject: legacy).write(to: persistence.url)
        let loaded = try persistence.load()
        expect(loaded.notes[0].iconName == oldName, "removed Note icon survives reload")
    }
}

func testCuratedNoteIcons() {
    expect(NoteIcon.choices.count == 49, "Note picker contains exactly 49 icons")
    expect(Set(NoteIcon.choices).count == NoteIcon.choices.count, "Note icons are unique")
    expect(Set(NoteIcon.choices).isDisjoint(with: AppSymbol.reserved), "Note icons avoid application symbols")
    expect(NoteIcon.choices.contains(NoteIcon.defaultName), "default Note icon remains selectable")
    expect(NoteIcon.choices.contains("bag"), "shopping bag is selectable")
    for name in NoteIcon.choices {
        expect(NSImage(systemSymbolName: name, accessibilityDescription: nil) != nil, "Note icon \(name) renders")
    }
}

func testManualNoteOrderAndPersistence() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let persistence = WorkspacePersistence(url: directory.appendingPathComponent("workspace.json"))
    let notes = (0..<7).map { Note(title: "Note \($0)") }
    let store = try AppStore(persistence: persistence)
    store.change { $0.notes = notes }
    store.change { $0.moveNote(from: 6, to: 0) }
    expect(store.workspace.notes.map(\.id) == [notes[6].id] + notes.prefix(6).map(\.id), "moving changes canonical order")
    expect(store.workspace.shortcutNotes.map(\.id) == [notes[6].id] + notes.prefix(5).map(\.id), "first six shortcuts follow canonical order")
    let movedReload = try persistence.load()
    expect(movedReload.notes.map(\.id) == store.workspace.notes.map(\.id), "manual order survives JSON persistence")

    store.change { $0.notes[0].title = "Renamed" }
    expect(store.workspace.notes[0].id == notes[6].id && store.workspace.shortcutNotes[0].title == "Renamed", "rename keeps position and updates shortcut title")
    store.change { $0.notes.removeAll { $0.id == notes[1].id } }
    expect(store.workspace.notes.map(\.id) == [notes[6].id, notes[0].id] + notes[2..<6].map(\.id), "deletion preserves remaining order")
    expect(store.workspace.shortcutNotes.count == 6 && store.workspace.shortcutNotes.last?.id == notes[5].id, "shortcut gap closes after deletion")
    store.change { _ = $0.createNote() }
    expect(store.workspace.notes.last?.title == "Untitled Note", "creation appends Note")
    let appendedReload = try persistence.load()
    expect(store.workspace.notes.last?.id == appendedReload.notes.last?.id, "appended Note persists at end")
}

func testLegacyNoteOrderMatchesPreviousDisplay() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let persistence = WorkspacePersistence(url: directory.appendingPathComponent("workspace.json"))
    let old = Note(title: "Old", createdAt: Date(timeIntervalSinceReferenceDate: 1))
    let recent = Note(title: "Recent", createdAt: Date(timeIntervalSinceReferenceDate: 2))
    try persistence.save(Workspace(notes: [recent, old]))
    var json = try JSONSerialization.jsonObject(with: Data(contentsOf: persistence.url)) as! [String: Any]
    json.removeValue(forKey: "noteOrderVersion")
    try JSONSerialization.data(withJSONObject: json).write(to: persistence.url)
    let loaded = try persistence.load()
    expect(loaded.notes.map(\.id) == [old.id, recent.id], "legacy workspace keeps previous creation-time display order")
    try persistence.save(loaded)
    let savedReload = try persistence.load()
    expect(savedReload.notes.map(\.id) == [old.id, recent.id], "legacy order stays canonical after save")
}

func testMissingFileIsOnlyEmptyWorkspaceCase() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    let url = directory.appendingPathComponent("workspace.json")
    defer { try? FileManager.default.removeItem(at: directory) }
    let persistence = WorkspacePersistence(url: url)
    let empty = try persistence.load()
    expect(empty == Workspace(), "missing file starts empty")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    try Data("{broken".utf8).write(to: url)
    do {
        _ = try persistence.load()
        expect(false, "corrupt data must throw")
    } catch { }
    do {
        try persistence.save(Workspace(notes: [Note(title: "New")]))
        expect(false, "corrupt source must not be overwritten")
    } catch { }
    let original = try String(contentsOf: url, encoding: .utf8)
    expect(original == "{broken", "corrupt original is preserved")
}

func testFailedWriteKeepsInMemoryChanges() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let persistence = WorkspacePersistence(url: directory) // A directory is not a writable workspace file.
    do {
        _ = try AppStore(persistence: persistence)
        expect(false, "unreadable existing path must fail at startup")
    } catch { }
    let blocked = directory.appendingPathComponent("read-only", isDirectory: true)
    try FileManager.default.createDirectory(at: blocked, withIntermediateDirectories: true)
    try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: blocked.path)
    defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: blocked.path) }
    let unwritable = try AppStore(persistence: WorkspacePersistence(url: blocked.appendingPathComponent("workspace.json")))
    unwritable.change { $0.notes.append(Note(title: "Still in memory")) }
    expect(unwritable.workspace.notes.count == 1, "failed write retains in-memory edit")
    expect(unwritable.persistenceError != nil, "failed write is reported")
    let url = directory.appendingPathComponent("workspace.json")
    let store = try AppStore(persistence: WorkspacePersistence(url: url))
    let note = Note(title: "Kept")
    store.change { $0.notes.append(note) }
    let saved = try WorkspacePersistence(url: url).load()
    expect(saved.notes.contains(note), "change is saved synchronously")
    let backup = url.appendingPathExtension("backup")
    store.change { $0.notes[0].contentMarkdown = "Edited" }
    expect(FileManager.default.fileExists(atPath: backup.path), "last good snapshot exists")
    let prior = try WorkspacePersistence(url: backup).load()
    expect(prior.notes[0].contentMarkdown == "", "backup holds prior content")
}

func testStoreEditAndRestoreSurviveReload() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let persistence = WorkspacePersistence(url: directory.appendingPathComponent("workspace.json"))
    let store = try AppStore(persistence: persistence)
    let label = Label(name: "Work")
    let note = Note(title: "Draft", labelID: label.id)
    let task = Task(title: "Call", labelID: label.id)
    store.change { w in w.labels.append(label); w.notes.append(note); w.tasks.append(task); w.settings.labelContext = .label(label.id) }
    store.change { w in w.notes[0].contentMarkdown = "# Work\n\n```swift\nlet x = 1\n```"; w.tasks[0].completedAt = Date() }
    store.change { $0.tasks[0].completedAt = nil }
    let reloaded = try AppStore(persistence: persistence).workspace
    expect(reloaded.notes[0].contentMarkdown.contains("let x = 1"), "ordinary edits persist through reload")
    expect(reloaded.tasks[0].completedAt == nil, "restored task stays open")
    expect(reloaded.settings.labelContext == .label(label.id), "global context persists")
}

func testDateGroupsAndChronologicalAccess() {
    let calendar = Calendar(identifier: .gregorian)
    let now = Date(timeIntervalSinceReferenceDate: 30_000_000)
    let work = Label(name: "Work")
    let today = calendar.startOfDay(for: now)
    let dates = [
        DateItem(title: "Later", date: calendar.date(byAdding: .day, value: 3, to: today)!, labelID: work.id),
        DateItem(title: "Soon", date: calendar.date(byAdding: .day, value: 1, to: today)!, labelID: work.id),
        DateItem(title: "Unlabelled", date: today),
        DateItem(title: "Past", date: calendar.date(byAdding: .day, value: -1, to: today)!, labelID: work.id)
    ]
    let workspace = Workspace(labels: [work], dates: dates, settings: AppSettings(maximumUpcomingDatesPerLabel: 1))
    let groups = workspace.dateGroups(showPast: false, calendar: calendar, now: now)
    expect(groups.count == 2, "real groups include labelled and unlabelled Dates")
    let workGroup = groups.first { $0.name == "Work" }!
    expect(workGroup.items.map(\.title) == ["Soon"] && workGroup.hiddenUpcomingCount == 1, "group sorts and limits upcoming Dates")
    expect(workspace.matchingDates(showPast: false, calendar: calendar, now: now).map(\.title) == ["Unlabelled", "Soon", "Later"], "chronological mode exposes all upcoming Dates")
    let expanded = workspace.dateGroups(showPast: true, expanded: [work.id.uuidString], calendar: calendar, now: now).first { $0.name == "Work" }!
    expect(expanded.items.map(\.title) == ["Past", "Soon", "Later"], "expansion and past toggle expose all Dates")
}

func testUpcomingHorizonAndCategoryLimit() {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    let today = calendar.date(from: DateComponents(year: 2026, month: 9, day: 27))!
    let training = Label(name: "Training")
    let other = Label(name: "Other")
    func item(_ title: String, _ offset: Int, _ label: UUID?) -> DateItem {
        DateItem(title: title, date: calendar.date(byAdding: .day, value: offset, to: today)!, labelID: label)
    }
    let items = [item("Today", 0, training.id), item("Soon", 1, training.id), item("Later", 14, training.id), item("Outside", 15, training.id), item("Other", 2, other.id)]
    var workspace = Workspace(labels: [training, other], dates: items, settings: AppSettings(maximumUpcomingDatesPerLabel: 2))
    expect(workspace.settings.upcomingHorizonDays == 14, "default horizon is 14 days")
    expect(workspace.upcomingDates(calendar: calendar, now: today).map(\.title) == ["Today", "Soon", "Other"], "horizon and category maximum both apply")
    let groups = workspace.dateGroups(showPast: false, calendar: calendar, now: today)
    expect(groups.first { $0.name == "Training" }?.hiddenUpcomingCount == 1, "group count includes only in-horizon hidden items")
    expect(workspace.matchingDates(showPast: false, calendar: calendar, now: today).count == 5, "chronological collection remains complete")
    workspace.settings.maximumUpcomingDatesPerLabel = 5
    expect(workspace.upcomingDates(calendar: calendar, now: today).map(\.title) == ["Today", "Soon", "Other", "Later"], "14th day is included and 15th excluded")
    workspace.settings.upcomingHorizonDays = 1
    expect(workspace.upcomingDates(calendar: calendar, now: today).map(\.title) == ["Today", "Soon"], "one-day lower boundary applies")
    workspace.settings.upcomingHorizonDays = 365
    expect(workspace.upcomingDates(calendar: calendar, now: today).count == 5, "365-day upper boundary applies")
    workspace.settings.upcomingHorizonDays = 366
    expect(workspace.settings.upcomingHorizonDays == 14, "invalid in-memory horizon resets safely")
}

func testTSVImportAndAtomicPersistence() throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    let source = "27.09.2026\tLong Run\t18 km easy\n30.09.2026\tIntervals\t\n03.10.2026\tEasy Run\n\n"
    let parsed = AppointmentTSVImport(source, calendar: calendar)
    expect(parsed.canImport && parsed.rows.count == 3 && parsed.issues.isEmpty, "three valid rows and empty lines")
    expect(parsed.rows.map(\.description) == ["18 km easy", "", ""], "trailing tab and two-column rows have empty descriptions")
    expect(parsed.rows[0].date == calendar.date(from: DateComponents(year: 2026, month: 9, day: 27)), "imported date is date-only at start of day")
    let invalid = AppointmentTSVImport("31.02.2027\tBad\t\n1.1.2027\tBad\t\n02.01.2027\t  \t\n02.01.2027\tGood\tDesc\textra\n04.10.2026\tValid\t\n", calendar: calendar)
    expect(!invalid.canImport && invalid.rows.count == 1 && invalid.issues.map(\.line) == [1, 2, 3, 4], "a valid row cannot bypass other line errors")
    expect(!AppointmentTSVImport("\n \n").canImport, "empty file cannot import")
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let persistence = WorkspacePersistence(url: directory.appendingPathComponent("workspace.json"))
    let category = Label(name: "Training")
    try persistence.save(Workspace(labels: [category]))
    let store = try AppStore(persistence: persistence)
    do { try store.importAppointments(invalid, categoryID: category.id); expect(false, "invalid report must fail") } catch { }
    let afterInvalid = try persistence.load()
    expect(store.workspace.dates.isEmpty && afterInvalid.dates.isEmpty, "complete validation precedes mutation")
    try store.importAppointments(parsed, categoryID: category.id)
    expect(store.workspace.dates.count == 3 && store.workspace.dates.allSatisfy { $0.labelID == category.id }, "one selected Category applies to the batch")
    expect(store.workspace.dates.map(\.itemDescription) == ["18 km easy", "", ""], "imported descriptions remain available on Appointments")
    let afterImport = try persistence.load()
    expect(afterImport.dates == store.workspace.dates, "import survives persistence round trip")
    try store.importAppointments(parsed, categoryID: nil)
    expect(store.workspace.dates.count == 6 && store.workspace.dates.suffix(3).allSatisfy { $0.labelID == nil }, "Uncategorized import appends without merging")
    let beforeFailure = store.workspace
    let backup = persistence.url.appendingPathExtension("backup")
    try FileManager.default.removeItem(at: backup)
    try FileManager.default.createDirectory(at: backup, withIntermediateDirectories: true)
    do { try store.importAppointments(parsed, categoryID: category.id); expect(false, "failed save must throw") } catch { }
    let afterFailure = try persistence.load()
    expect(store.workspace == beforeFailure && afterFailure == beforeFailure, "failed import preserves memory and saved workspace")
}

func testHorizonPersistenceAndMigration() throws {
    var settings = AppSettings(upcomingHorizonDays: 365)
    let encoded = try JSONEncoder().encode(settings)
    let upper = try JSONDecoder().decode(AppSettings.self, from: encoded)
    expect(upper.upcomingHorizonDays == 365, "custom upper-bound horizon persists")
    settings.upcomingHorizonDays = 1
    let lower = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(settings))
    expect(lower.upcomingHorizonDays == 1, "lower-bound horizon persists")
    var object = try JSONSerialization.jsonObject(with: encoded) as! [String: Any]
    object.removeValue(forKey: "upcomingHorizonDays")
    object["maximumUpcomingDatesPerLabel"] = 7
    let legacy = try JSONDecoder().decode(AppSettings.self, from: JSONSerialization.data(withJSONObject: object))
    expect(legacy.upcomingHorizonDays == 14 && legacy.maximumUpcomingDatesPerLabel == 7, "legacy maximum is preserved and horizon defaults")
    for value in [0, -1, 366] {
        object["upcomingHorizonDays"] = value
        let decoded = try JSONDecoder().decode(AppSettings.self, from: JSONSerialization.data(withJSONObject: object))
        expect(decoded.upcomingHorizonDays == 14, "invalid persisted horizon resets to default")
    }
}

func testMarkdownSourceHighlighting() {
    let source = #"""
    # Heading 1
    ## Heading 2
    ### Heading 3
    #### Heading 4
    ##### Heading 5
    ###### Heading 6

    Normal text
    **bold** __bold__ *italic* _italic_ ***bold italic*** ___bold italic___ ~~strikethrough~~
    - unordered list
    * unordered list
    + unordered list
    1. ordered list
    2. second item
    - [ ] open task
    - [x] completed task
    - [X] completed task
    > blockquote
    >> nested blockquote
    [OpenAI](https://openai.com)
    <https://openai.com>
    `inline code`
    ```text
    code block
    multiple lines
    ```
    Prose after the fence.
    ---
    ***
    ___
    Escaped \*not italic\* and \\*also not italic*
    Some **bold**, *italic*, `code`, and [link](https://example.com) inside ordinary text.
    """#
    let parsed = MarkdownHighlight.parse(source)
    let ns = source as NSString
    func range(_ text: String, after offset: Int = 0) -> NSRange {
        ns.range(of: text, options: [], range: NSRange(location: offset, length: ns.length - offset))
    }
    func has(_ style: MarkdownHighlight.Style, _ text: String, after offset: Int = 0) -> Bool {
        parsed.spans.contains { $0.style == style && $0.range == range(text, after: offset) }
    }
    for level in 1...6 { expect(has(.heading(level), String(repeating: "#", count: level) + " Heading \(level)"), "heading \(level)") }
    expect(has(.syntax, "**") && has(.bold, "bold"), "bold markers and content differ")
    expect(has(.syntax, "__") && parsed.spans.contains { $0.style == .bold && ns.substring(with: $0.range) == "bold" }, "underscore bold")
    expect(has(.italic, "italic") && has(.syntax, "*", after: range("**bold**").location + 8), "italic markers stay visible")
    let combination = range("bold italic")
    expect(parsed.spans.contains { $0.style == .bold && $0.range == combination } && parsed.spans.contains { $0.style == .italic && $0.range == combination }, "triple emphasis has both traits")
    expect(has(.strike, "strikethrough"), "strikethrough content")
    for marker in ["- ", "* ", "+ ", "1. ", "2. ", "- [ ] ", "- [x] ", "- [X] ", "> ", ">> "] {
        expect(parsed.spans.contains { $0.style == .syntax && ns.substring(with: $0.range) == marker }, "structural marker \(marker)")
    }
    expect(parsed.checkboxes.map { ns.substring(with: $0.range) } == ["[ ]", "[x]", "[X]"], "task markers have exact source ranges")
    expect(parsed.checkboxes.map(\.checked) == [false, true, true], "task marker state is preserved")
    let emptyTask = MarkdownHighlight.parse("- [ ]\n1. [x]")
    expect(emptyTask.checkboxes.map(\.checked) == [false, true], "tasks without descriptions are checkboxes")
    let ordinaryBrackets = MarkdownHighlight.parse("[ ] plain text\n- [x]task\n```\n- [ ] code\n```")
    expect(ordinaryBrackets.checkboxes.isEmpty, "only complete list task markers outside code become checkboxes")
    expect(has(.linkText, "OpenAI") && has(.linkURL, "https://openai.com") && parsed.links.count == 3, "links retain visible text and URL")
    expect(has(.code, "inline code") && has(.code, "code block"), "inline and fenced code")
    expect(!parsed.spans.contains { $0.style == .code && NSLocationInRange(range("Prose after").location, $0.range) }, "closing fence ends code")
    expect(!parsed.spans.contains { $0.style == .italic && NSLocationInRange(range("not italic").location, $0.range) }, "escaped marker is not italic")
    expect(parsed.spans.contains { $0.style == .linkText && ns.substring(with: $0.range) == "link" }, "mixed inline styling")
    expect(String(decoding: source.utf16, as: UTF16.self) == source, "parsing never changes source")
    for span in parsed.spans { expect(span.range.location >= 0 && NSMaxRange(span.range) <= ns.length, "all styles stay within source offsets") }
}

func testIncompleteMarkdownWhileTyping() {
    for source in ["", "*", "**unfinished", "[link](", "<https://", "`code", "```swift\nunfinished", "\\*escaped*", "- ["] {
        let result = MarkdownHighlight.parse(source)
        let length = (source as NSString).length
        expect(result.spans.allSatisfy { NSMaxRange($0.range) <= length }, "incomplete syntax stays in bounds")
    }
    let unclosed = MarkdownHighlight.parse("```\ncode\nmore")
    expect(unclosed.spans.contains { $0.style == .code }, "unclosed fence highlights remaining source")
    let crossing = MarkdownHighlight.parse("*before `code` after* and *good*")
    let crossingSource = "*before `code` after* and *good*" as NSString
    expect(!crossing.spans.contains { $0.style == .italic && crossingSource.substring(with: $0.range).contains("code") }, "emphasis does not cross protected code")
    expect(crossing.spans.contains { $0.style == .italic && crossingSource.substring(with: $0.range) == "good" }, "formatting after protected code still works")
    let invalid = MarkdownHighlight.parse("[text](not-a-url) <javascript:alert(1)>")
    expect(invalid.links.isEmpty, "only valid web links open")
    expect(invalid.spans.contains { $0.style == .linkText && ("[text](not-a-url) <javascript:alert(1)>" as NSString).substring(with: $0.range) == "text" }, "relative links still receive source highlighting")
    let unicode = "🙂 **bold** [link](https://example.com)"
    let unicodeResult = MarkdownHighlight.parse(unicode)
    let unicodeSource = unicode as NSString
    expect(unicodeResult.spans.contains { $0.style == .bold && unicodeSource.substring(with: $0.range) == "bold" }, "style offsets use UTF-16 after emoji")
    expect(unicodeResult.links.count == 1 && unicodeSource.substring(with: unicodeResult.links[0].range) == "https://example.com", "link offsets use UTF-16 after emoji")
}

func testNoteEditorStatus() {
    let empty = NoteEditorStatus(source: "", caretUTF16Offset: 0)
    expect(empty.line == 1 && empty.column == 1 && empty.words == 0 && empty.characters == 0, "empty Note status")

    let source = "# Heading\n**hello** world\n🙂 café\n"
    let ns = source as NSString
    let second = ns.range(of: "world")
    let middle = NoteEditorStatus(source: source, caretUTF16Offset: second.location)
    expect(middle.line == 2 && middle.column == 11, "logical line and one-based column")
    expect(middle.words == 4 && middle.characters == source.count, "native words and literal Markdown characters")
    let emoji = ns.range(of: "🙂")
    let afterEmoji = NoteEditorStatus(source: source, caretUTF16Offset: NSMaxRange(emoji))
    expect(afterEmoji.line == 3 && afterEmoji.column == 2, "emoji occupies one displayed column")
    let final = NoteEditorStatus(source: source, caretUTF16Offset: ns.length)
    expect(final.line == 4 && final.column == 1, "trailing newline opens an empty logical line")

    let wrapped = String(repeating: "long ", count: 80)
    expect(NoteEditorStatus(source: wrapped, caretUTF16Offset: (wrapped as NSString).length).line == 1,
           "visual wrapping does not add logical lines")
    let inserted = NoteEditorStatus(source: "one\ntwo\nthree", caretUTF16Offset: ("one\ntwo\nthree" as NSString).length)
    let deleted = NoteEditorStatus(source: "one\nthree", caretUTF16Offset: ("one\nthree" as NSString).length)
    expect(inserted.line == 3 && deleted.line == 2, "line insertion and deletion update numbering")
    expect(NoteEditorStatus(source: "**hello** \n", caretUTF16Offset: 0).characters == 11,
           "Markdown markers and whitespace count as source characters")
}

func testDefaultCategoryAndScheduleAtCreation() {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    func date(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 9, day: day, hour: hour, minute: minute))!
    }
    let personal = Label(name: "Personal")
    let work = Label(name: "Work")
    var workspace = Workspace(labels: [personal, work])
    expect(workspace.settings.resolvedDefaultLabelID(at: date(28, 10), calendar: calendar, validLabels: workspace.labels) == nil, "Uncategorized is initial default")
    workspace.settings.defaultLabelID = personal.id
    workspace.settings.scheduledDefaultEnabled = true
    workspace.settings.scheduledLabelID = work.id
    expect(workspace.settings.resolvedDefaultLabelID(at: date(29, 10), calendar: calendar, validLabels: workspace.labels) == personal.id, "unconfigured schedule uses fallback")
    workspace.settings.scheduledCategoryConfigured = true
    expect(workspace.settings.resolvedDefaultLabelID(at: date(29, 8), calendar: calendar, validLabels: workspace.labels) == work.id, "weekday schedule includes start")
    expect(workspace.settings.resolvedDefaultLabelID(at: date(29, 16, 59), calendar: calendar, validLabels: workspace.labels) == work.id, "weekday schedule applies inside hours")
    expect(workspace.settings.resolvedDefaultLabelID(at: date(29, 17), calendar: calendar, validLabels: workspace.labels) == personal.id, "weekday schedule excludes end")
    expect(workspace.settings.resolvedDefaultLabelID(at: date(27, 10), calendar: calendar, validLabels: workspace.labels) == personal.id, "Sunday uses fallback")
    workspace.settings.scheduledLabelID = nil
    expect(workspace.settings.resolvedDefaultLabelID(at: date(29, 10), calendar: calendar, validLabels: workspace.labels) == nil, "Uncategorized can be an explicit scheduled choice")
    workspace.settings.scheduledLabelID = work.id
    let task = workspace.createTask(at: date(29, 10), calendar: calendar)
    let note = workspace.createNote(at: date(29, 10), calendar: calendar)
    let appointment = workspace.createAppointment(at: date(27, 19), calendar: calendar)
    expect(task.labelID == work.id && note.labelID == work.id, "To-do and Note use scheduled default")
    expect(appointment.labelID == personal.id, "Appointment uses creation time")
    workspace.dates[0].date = date(29, 10)
    workspace.settings.scheduledDefaultEnabled = false
    expect(workspace.tasks[0].labelID == work.id && workspace.notes[0].labelID == work.id && workspace.dates[0].labelID == personal.id, "settings and Appointment date changes do not recategorize items")
    workspace.settings.scheduledDefaultEnabled = true
    workspace.settings.scheduledStartMinute = workspace.settings.scheduledEndMinute
    expect(workspace.settings.resolvedDefaultLabelID(at: date(29, 10), calendar: calendar, validLabels: workspace.labels) == personal.id, "equal schedule times are inactive")
    workspace.settings.scheduledStartMinute = 22 * 60
    workspace.settings.scheduledEndMinute = 6 * 60
    expect(workspace.settings.resolvedDefaultLabelID(at: date(29, 23), calendar: calendar, validLabels: workspace.labels) == personal.id, "overnight schedule is inactive")
    workspace.deleteLabel(personal.id)
    expect(workspace.settings.defaultLabelID == nil && workspace.dates[0].labelID == nil, "deleting fallback clears reference and uncategorizes item")
    workspace.deleteLabel(work.id)
    expect(workspace.settings.scheduledLabelID == nil && !workspace.settings.scheduledCategoryConfigured && !workspace.settings.scheduledDefaultEnabled, "deleting scheduled Category disables override")
}

func testSettingsPersistenceAndLegacyDefaults() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let persistence = WorkspacePersistence(url: directory.appendingPathComponent("workspace.json"))
    let label = Label(name: "Personal")
    var workspace = Workspace(labels: [label])
    workspace.settings.defaultLabelID = label.id
    workspace.settings.scheduledDefaultEnabled = true
    workspace.settings.scheduledCategoryConfigured = true
    workspace.settings.scheduledLabelID = label.id
    workspace.settings.scheduledWeekdays = [2, 4]
    workspace.settings.scheduledStartMinute = 9 * 60
    workspace.settings.scheduledEndMinute = 18 * 60
    workspace.settings.showLineNumbers = false
    workspace.settings.indentWidth = 8
    workspace.settings.checkSpelling = false
    workspace.settings.automaticCorrection = true
    workspace.settings.smartQuotes = true
    workspace.settings.smartDashes = true
    workspace.settings.maximumDashboardTasks = 1
    workspace.settings.maximumDashboardAppointments = 10
    try persistence.save(workspace)
    let roundTrip = try persistence.load()
    expect(roundTrip == workspace, "new Settings persist round trip")
    var legacy = try JSONSerialization.jsonObject(with: Data(contentsOf: persistence.url)) as! [String: Any]
    var oldSettings = legacy["settings"] as! [String: Any]
    for key in ["defaultLabelID", "scheduledDefaultEnabled", "scheduledCategoryConfigured", "scheduledLabelID", "scheduledWeekdays", "scheduledStartMinute", "scheduledEndMinute", "showLineNumbers", "indentWidth", "checkSpelling", "automaticCorrection", "smartQuotes", "smartDashes", "appLockEnabled", "lockWhenInactive", "inactivityMinutes", "maximumDashboardTasks", "maximumDashboardAppointments"] { oldSettings.removeValue(forKey: key) }
    legacy["settings"] = oldSettings
    try JSONSerialization.data(withJSONObject: legacy).write(to: persistence.url)
    let loaded = try persistence.load()
    let defaults = loaded.settings
    expect(loaded.labels == [label], "legacy migration preserves existing Categories")
    expect(defaults.defaultLabelID == nil && !defaults.scheduledDefaultEnabled && !defaults.scheduledCategoryConfigured && defaults.scheduledLabelID == nil, "old workspace has safe Category defaults")
    expect(defaults.scheduledWeekdays == [2, 3, 4, 5, 6] && defaults.scheduledStartMinute == 480 && defaults.scheduledEndMinute == 1020, "old workspace has suggested schedule values")
    expect(defaults.showLineNumbers && defaults.indentWidth == 4 && defaults.checkSpelling, "old workspace has Note editor defaults")
    expect(!defaults.automaticCorrection && !defaults.smartQuotes && !defaults.smartDashes, "old workspace preserves Markdown source defaults")
    expect(!defaults.appLockEnabled && !defaults.lockWhenInactive && defaults.inactivityMinutes == 5, "old workspace has App Lock off and a five minute default")
    expect(defaults.maximumDashboardTasks == 4 && defaults.maximumDashboardAppointments == 4, "old workspace has four-item Dashboard defaults")
    for limit in [1, 10] {
        let settings = AppSettings(maximumDashboardTasks: limit, maximumDashboardAppointments: limit)
        let decoded = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(settings))
        expect(decoded.maximumDashboardTasks == limit && decoded.maximumDashboardAppointments == limit, "supported Dashboard limit \(limit) persists")
    }
    for invalidLimit in [-1, 0, 11] {
        oldSettings["maximumDashboardTasks"] = invalidLimit
        oldSettings["maximumDashboardAppointments"] = invalidLimit
        legacy["settings"] = oldSettings
        let invalid = try JSONDecoder().decode(Workspace.self, from: JSONSerialization.data(withJSONObject: legacy))
        expect(invalid.settings.maximumDashboardTasks == 4 && invalid.settings.maximumDashboardAppointments == 4, "invalid Dashboard limit falls back to four")
    }
    oldSettings.removeValue(forKey: "maximumDashboardTasks")
    oldSettings.removeValue(forKey: "maximumDashboardAppointments")
    for width in [2, 4, 8] {
        var settings = defaults
        settings.indentWidth = width
        let decoded = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(settings))
        expect(decoded.indentWidth == width, "supported indent width \(width) persists")
    }
    oldSettings["indentWidth"] = 3
    legacy["settings"] = oldSettings
    let invalid = try JSONDecoder().decode(Workspace.self, from: JSONSerialization.data(withJSONObject: legacy))
    expect(invalid.settings.indentWidth == 4, "unsupported persisted indent width falls back to four spaces")
}

func testSecuritySettingsPersistenceAndValidation() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let persistence = WorkspacePersistence(url: directory.appendingPathComponent("workspace.json"))
    var workspace = Workspace()
    expect(!workspace.settings.appLockEnabled && !workspace.settings.lockWhenInactive && workspace.settings.inactivityMinutes == 5, "App Lock defaults off")
    workspace.settings.appLockEnabled = true
    workspace.settings.lockWhenInactive = true
    workspace.settings.inactivityMinutes = 120
    try persistence.save(workspace)
    let saved = try persistence.load()
    expect(saved == workspace, "Security settings persist")
    var encoded = try JSONSerialization.jsonObject(with: Data(contentsOf: persistence.url)) as! [String: Any]
    for invalid in [0, -1, 121] {
        var settings = encoded["settings"] as! [String: Any]
        settings["inactivityMinutes"] = invalid
        encoded["settings"] = settings
        let loaded = try JSONDecoder().decode(Workspace.self, from: JSONSerialization.data(withJSONObject: encoded))
        expect(loaded.settings.inactivityMinutes == 5, "invalid saved inactivity delay uses safe default")
    }
}

func testLifetimeStatistics() {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
    let start = calendar.date(from: DateComponents(year: 2026, month: 9, day: 28, hour: 23, minute: 50))!
    let nextDay = calendar.date(from: DateComponents(year: 2026, month: 9, day: 29, hour: 0, minute: 10))!
    var workspace = Workspace(statisticsStartedAt: start)
    expect(workspace.daysPassed(now: start, calendar: calendar) == 1, "first calendar day counts as one")
    expect(workspace.daysPassed(now: nextDay, calendar: calendar) == 2, "next calendar day counts as two even before 24 hours")

    workspace.tasks = [Task(title: "Complete")]
    workspace.tasks[0].completedAt = start
    expect(workspace.completedTodoCount == 1, "completion contributes")
    workspace.tasks[0].completedAt = nil
    expect(workspace.completedTodoCount == 0, "restoration removes contribution")
    workspace.tasks[0].completedAt = start
    expect(workspace.completedTodoCount == 1, "recompletion contributes once")

    let today = calendar.startOfDay(for: nextDay)
    let yesterday = calendar.date(byAdding: .day, value: -1, to: today)!
    let tomorrow = calendar.date(byAdding: .day, value: 1, to: today)!
    workspace.dates = [DateItem(title: "Passed", date: yesterday), DateItem(title: "Today", date: today), DateItem(title: "Future", date: tomorrow)]
    expect(workspace.passedAppointmentCount(now: nextDay, calendar: calendar) == 1, "only passed Appointment contributes")
    workspace.dates[0].date = tomorrow
    expect(workspace.passedAppointmentCount(now: nextDay, calendar: calendar) == 0, "rescheduling a retained Appointment to the future removes its contribution")
    workspace.dates[0].date = yesterday

    var manuallyDeleted = workspace
    manuallyDeleted.tasks.removeAll()
    manuallyDeleted.dates.removeAll()
    expect(manuallyDeleted.completedTodoCount == 0 && manuallyDeleted.passedAppointmentCount(now: nextDay, calendar: calendar) == 0, "explicit deletion removes retained contributions")

    workspace.settings.taskRetention = .seven
    workspace.settings.dateRetention = .seven
    let purgeDay = calendar.date(byAdding: .day, value: 10, to: nextDay)!
    let completedBeforePurge = workspace.completedTodoCount
    let passedBeforePurge = workspace.passedAppointmentCount(now: purgeDay, calendar: calendar)
    workspace.purgeExpired(now: purgeDay, calendar: calendar)
    expect(workspace.tasks.isEmpty && workspace.dates.isEmpty, "expired items are purged")
    expect(workspace.completedTodoCount == completedBeforePurge, "To-do purge preserves total")
    expect(workspace.passedAppointmentCount(now: purgeDay, calendar: calendar) == passedBeforePurge, "Appointment purge preserves total")
    workspace.purgeExpired(now: purgeDay, calendar: calendar)
    expect(workspace.completedTodoCount == completedBeforePurge && workspace.passedAppointmentCount(now: purgeDay, calendar: calendar) == passedBeforePurge, "repeated purge does not double-count")
}

func testLifetimeStatisticsPersistenceAndLegacyDefaults() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let persistence = WorkspacePersistence(url: directory.appendingPathComponent("workspace.json"))
    var old = Workspace(tasks: [Task(title: "Retained", completedAt: Date(timeIntervalSinceReferenceDate: 100))])
    try persistence.save(old)
    var encoded = try JSONSerialization.jsonObject(with: Data(contentsOf: persistence.url)) as! [String: Any]
    encoded.removeValue(forKey: "statisticsStartedAt")
    encoded.removeValue(forKey: "historicalCompletedTodoCount")
    encoded.removeValue(forKey: "historicalPassedAppointmentCount")
    try JSONSerialization.data(withJSONObject: encoded).write(to: persistence.url)
    let legacy = try persistence.load()
    expect(legacy.statisticsStartedAt == nil && legacy.historicalCompletedTodoCount == 0 && legacy.historicalPassedAppointmentCount == 0, "old Workspace gets safe statistics defaults")
    expect(legacy.completedTodoCount == 1, "retained completion contributes to legacy Workspace")

    old = legacy
    let started = Date(timeIntervalSinceReferenceDate: 1_000_000)
    old.statisticsStartedAt = started
    old.historicalCompletedTodoCount = 12
    old.historicalPassedAppointmentCount = 7
    try persistence.save(old)
    let loaded = try persistence.load()
    expect(loaded.statisticsStartedAt == started && loaded.historicalCompletedTodoCount == 12 && loaded.historicalPassedAppointmentCount == 7, "statistics fields round trip")

    // Startup initializes a missing date once and persists it with the Workspace.
    encoded = try JSONSerialization.jsonObject(with: Data(contentsOf: persistence.url)) as! [String: Any]
    encoded.removeValue(forKey: "statisticsStartedAt")
    try JSONSerialization.data(withJSONObject: encoded).write(to: persistence.url)
    let firstStore = try AppStore(persistence: persistence)
    let firstStart = firstStore.workspace.statisticsStartedAt
    expect(firstStart != nil, "startup sets statistics start date")
    let secondStore = try AppStore(persistence: persistence)
    expect(secondStore.workspace.statisticsStartedAt == firstStart, "startup never resets persisted statistics start date")
}

func testCreationDraftsOnlyPersistWhenAccepted() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let persistence = WorkspacePersistence(url: directory.appendingPathComponent("workspace.json"))
    let category = Label(name: "Work")
    let existingTask = Task(title: "Existing")
    let existingAppointment = DateItem(title: "Existing", date: Date())
    var workspace = Workspace(labels: [category], tasks: [existingTask], dates: [existingAppointment])
    workspace.settings.defaultLabelID = category.id
    workspace.settings.labelContext = .label(category.id)
    let before = workspace
    var task = workspace.makeTaskDraft()
    var appointment = workspace.makeAppointmentDraft()
    expect(workspace == before, "opening creation leaves content and filter unchanged")
    expect(task.labelID == category.id && appointment.labelID == category.id, "drafts inherit the default Category")
    task.title = "Typed To-do"
    task.taskDescription = "Line one\nLine two"
    appointment.title = "Typed Appointment"
    appointment.itemDescription = "Details"
    appointment.date = Date(timeIntervalSinceReferenceDate: 123456)
    try persistence.save(workspace)
    let cancelled = try persistence.load()
    expect(cancelled == before, "draft edits and cancellation do not persist new items")
    workspace.addTaskDraft(task)
    workspace.addAppointmentDraft(appointment)
    workspace.addTaskDraft(task)
    workspace.addAppointmentDraft(appointment)
    try persistence.save(workspace)
    let loaded = try persistence.load()
    expect(loaded.tasks == [existingTask, task] && loaded.dates == [existingAppointment, appointment], "Done persists every draft field exactly once and preserves existing content")

    var blankTask = workspace.makeTaskDraft()
    var blankAppointment = workspace.makeAppointmentDraft()
    blankTask.title = "  \n"
    blankAppointment.title = "\t"
    workspace.deleteLabel(category.id)
    workspace.addTaskDraft(blankTask)
    workspace.addAppointmentDraft(blankAppointment)
    expect(workspace.tasks.last?.title == "New To-do" && workspace.dates.last?.title == "New Appointment", "accepted empty titles get valid defaults")
    expect(workspace.tasks.last?.labelID == nil && workspace.dates.last?.labelID == nil, "accepting drafts cannot retain a removed Category")
}

func testTodoCompletionConfirmationPolicy() {
    expect(!TodoCompletionConfirmation.off.requiresConfirmation(isKeyboard: false), "Off keeps mouse completion immediate")
    expect(!TodoCompletionConfirmation.off.requiresConfirmation(isKeyboard: true), "Off keeps keyboard completion immediate")
    expect(!TodoCompletionConfirmation.keyboardOnly.requiresConfirmation(isKeyboard: false), "Keyboard only does not confirm mouse completion")
    expect(TodoCompletionConfirmation.keyboardOnly.requiresConfirmation(isKeyboard: true), "Keyboard only confirms keyboard completion")
    expect(TodoCompletionConfirmation.allInteractions.requiresConfirmation(isKeyboard: false), "All interactions confirms mouse completion")
    expect(TodoCompletionConfirmation.allInteractions.requiresConfirmation(isKeyboard: true), "All interactions confirms keyboard completion")
}

func testTodoCompletionConfirmationPersistenceAndLegacyDefaults() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let persistence = WorkspacePersistence(url: directory.appendingPathComponent("workspace.json"))
    let label = Label(name: "Personal")
    var workspace = Workspace(
        labels: [label],
        notes: [Note(title: "Existing Note", contentMarkdown: "# Keep this", labelID: label.id)],
        tasks: [Task(title: "Open", labelID: label.id), Task(title: "Completed", completedAt: Date())],
        dates: [DateItem(title: "Appointment", date: Date(), itemDescription: "Details", labelID: label.id)]
    )
    workspace.settings.labelContext = .label(label.id)
    workspace.settings.taskRetention = .ninety
    expect(workspace.settings.todoCompletionConfirmation == .off, "new workspaces default to immediate completion")
    for mode in TodoCompletionConfirmation.allCases {
        workspace.settings.todoCompletionConfirmation = mode
        try persistence.save(workspace)
        let loaded = try persistence.load()
        expect(loaded == workspace, "completion confirmation mode \(mode) persists without changing other content or settings")
    }
    var legacy = try JSONSerialization.jsonObject(with: Data(contentsOf: persistence.url)) as! [String: Any]
    var settings = legacy["settings"] as! [String: Any]
    settings.removeValue(forKey: "todoCompletionConfirmation")
    settings["futureSetting"] = true
    legacy["settings"] = settings
    try JSONSerialization.data(withJSONObject: legacy).write(to: persistence.url)
    var loaded = try persistence.load()
    workspace.settings.todoCompletionConfirmation = .off
    expect(loaded == workspace, "older workspaces default to Off and preserve all existing items and settings")
    loaded.settings.todoCompletionConfirmation = .keyboardOnly
    try persistence.save(loaded)
    let reloaded = try persistence.load()
    expect(reloaded == loaded, "older workspace retains its content after saving the new preference and reopening")
}

testTodoCompletionConfirmationPolicy()
try testTodoCompletionConfirmationPersistenceAndLegacyDefaults()
try testCreationDraftsOnlyPersistWhenAccepted()
testDeletingLabelUnlabelsEveryItemAndResetsFilter()
testRetentionNeverDeletesOpenTasksOrFutureDates()
testRetentionRemovesOnlyExpiredCompletedAndPassedItems()
testGlobalContextMatchesAllAndOneLabel()
try testPersistenceRoundTrip()
try testZoomPersistenceAndLegacyDefaults()
try testWorkspaceDirectoryMigration()
try testWorkspaceMigrationFailureKeepsLegacyData()
try testNoteIconPersistenceAndLegacyFallback()
testCuratedNoteIcons()
try testManualNoteOrderAndPersistence()
try testLegacyNoteOrderMatchesPreviousDisplay()
try testMissingFileIsOnlyEmptyWorkspaceCase()
try testFailedWriteKeepsInMemoryChanges()
try testStoreEditAndRestoreSurviveReload()
testDateGroupsAndChronologicalAccess()
testUpcomingHorizonAndCategoryLimit()
try testTSVImportAndAtomicPersistence()
try testHorizonPersistenceAndMigration()
testMarkdownSourceHighlighting()
testIncompleteMarkdownWhileTyping()
testNoteEditorStatus()
testDefaultCategoryAndScheduleAtCreation()
try testSettingsPersistenceAndLegacyDefaults()
try testSecuritySettingsPersistenceAndValidation()
testLifetimeStatistics()
try testLifetimeStatisticsPersistenceAndLegacyDefaults()
try testScheduledTodoDatesAndCompatibility()
try testScheduledTodoGenerationAndAtomicPersistence()
print("PassingByTests: all tests passed")
