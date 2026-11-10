import Foundation
import PassingByCore

func testHistoricalWorkspaceFixtures() throws {
    for name in ["initial-workspace", "legacy-filter-workspace"] {
        let source = Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures")!
        let originalData = try Data(contentsOf: source)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("workspace.json")
        try originalData.write(to: url)
        let persistence = WorkspacePersistence(url: url)
        let loaded = try persistence.load()
        expect(loaded.labels.map(\.name) == ["Example"], "historical Category survives loading")
        expect(loaded.notes.map(\.title) == ["Older Note", "Newer Note"], "historical Notes use creation order")
        expect(loaded.notes[0].contentMarkdown == "# Keep me\nSynthetic legacy content: ä, √, 🐦.", "historical Markdown survives exactly")
        expect(loaded.notes[0].iconName == "pencil", "legacy Note icon remains valid")
        expect(
            loaded.tasks.map(\.title) == ["Existing To-do"] && loaded.tasks[0].taskDescription == "Do not discard",
            "historical To-do survives")
        expect(
            loaded.dates.map(\.title) == ["Existing Appointment"] && loaded.dates[0].itemDescription == "Retain description",
            "historical Appointment survives")
        expect(
            loaded.settings.taskRetention == .never && loaded.settings.dateRetention == .never && loaded.settings.upcomingHorizonDays == 60
                && loaded.settings.indentWidth == 2, "nondefault historical Settings survive")
        let expectedFilter: LabelContext = name == "initial-workspace" ? .label(loaded.labels[0].id) : .unlabelled
        expect(loaded.settings.labelContext == expectedFilter, "historical filter decodes without discarding content")
        expect(
            loaded.scheduledTodos.isEmpty && loaded.recentlyDeleted.isEmpty && loaded.notes.allSatisfy { $0.zoomPercent == 100 },
            "missing newer fields receive defaults")
        var updated = loaded
        updated.notes[0].contentMarkdown += "\nEdited after migration"
        updated.notes[0].zoomPercent = 130
        updated.settings.screenZoom["dashboard"] = 120
        try persistence.save(updated)
        let reloaded = try persistence.load()
        expect(reloaded == updated, "all old content and new values survive save and reload")
        let backup = try Data(contentsOf: url.appendingPathExtension("backup"))
        expect(backup == originalData, "the first updated save preserves the original historical file as backup")
        try persistence.save(reloaded)
        let reopened = try persistence.load()
        expect(reopened == updated, "a subsequent save remains readable without duplication or loss")
    }
}
