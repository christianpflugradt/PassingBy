import AppKit
import SwiftUI
import PassingByCore
import UniformTypeIdentifiers

private struct ImportPreview: Identifiable {
    let id = UUID()
    let filename: String
    let parsed: AppointmentTSVImport
}

@MainActor private final class AppointmentImportFlow: ObservableObject {
    @Published var selectingFile = false
    @Published var preview: ImportPreview?
    @Published var fileError: String?
    @Published var categoryID: UUID?
    @Published var importError: String?
}

struct SettingsView: View {
    private enum ScheduledChoice: Hashable { case unconfigured, uncategorized, label(UUID) }
    @ObservedObject var state: WorkspaceState
    private var scale: CGFloat { CGFloat(state.currentZoom) / 100 }
    @StateObject private var importFlow = AppointmentImportFlow()
    private let weekdays: [(Int, String)] = [(2, "Mon"), (3, "Tue"), (4, "Wed"), (5, "Thu"), (6, "Fri"), (7, "Sat"), (1, "Sun")]
    private var settings: AppSettings { state.workspace.settings }
    private var fallbackName: String { state.workspace.labels.first { $0.id == settings.defaultLabelID }?.name ?? "Uncategorized" }
    private var validSchedule: Bool { settings.scheduledCategoryConfigured && settings.scheduledStartMinute < settings.scheduledEndMinute && !settings.scheduledWeekdays.isEmpty }
    private var scheduledChoice: Binding<ScheduledChoice> {
        Binding(get: {
            guard settings.scheduledCategoryConfigured else { return .unconfigured }
            return settings.scheduledLabelID.map(ScheduledChoice.label) ?? .uncategorized
        }, set: { choice in
            state.change { workspace in
                switch choice {
                case .unconfigured: workspace.settings.scheduledCategoryConfigured = false; workspace.settings.scheduledLabelID = nil
                case .uncategorized: workspace.settings.scheduledCategoryConfigured = true; workspace.settings.scheduledLabelID = nil
                case .label(let id): workspace.settings.scheduledCategoryConfigured = true; workspace.settings.scheduledLabelID = id
                }
            }
        })
    }
    @StateObject private var focus = SettingsFocus()
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                Text("Settings").font(.system(size: 34 * scale, weight: .semibold))
                dashboardSection
                categoriesSection
                todosSection
                appointmentsSection
                notesSection
                securitySection
                Divider()
                VStack(alignment: .leading, spacing: 6) {
                    SettingsButton(title: "Reset All Zoom Levels", id: "settings-900-zoom") { state.resetAllZoom() }
                    explanation("Restores the default size for every Note and screen.")
                }
            }
            .frame(maxWidth: 650, alignment: .leading)
            .padding(.horizontal, 34).padding(.vertical, 28)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .background(SettingsKeyLoop(request: focus.request, requestedID: focus.requestedID, settings: settings, categoryID: state.labelID, scheduleIDs: state.workspace.scheduledTodos.map(\.id)))
        .environment(\.font, .system(size: 13 * scale))
        .environment(\.settingsPointSize, 13 * scale)
        .fileImporter(isPresented: $importFlow.selectingFile, allowedContentTypes: [.plainText, UTType(filenameExtension: "tsv") ?? .plainText]) { result in
            switch result {
            case .success(let url):
                let access = url.startAccessingSecurityScopedResource()
                defer { if access { url.stopAccessingSecurityScopedResource() } }
                do {
                    let source = try String(contentsOf: url, encoding: .utf8)
                    importFlow.preview = ImportPreview(filename: url.lastPathComponent, parsed: AppointmentTSVImport(source))
                } catch { importFlow.fileError = "Could not read \(url.lastPathComponent): \(error.localizedDescription)" }
            case .failure(let error): importFlow.fileError = error.localizedDescription
            }
        }
        .sheet(item: $importFlow.preview) { preview in
            AppointmentImportPreviewView(state: state, filename: preview.filename, parsed: preview.parsed)
        }
        .alert("Could Not Open TSV", isPresented: Binding(get: { importFlow.fileError != nil }, set: { if !$0 { importFlow.fileError = nil } })) {
            Button("OK") { importFlow.fileError = nil }
        } message: { Text(importFlow.fileError ?? "The selected file could not be read.") }
    }
    private var dashboardSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeading("Dashboard")
            numberRow("Maximum To-dos shown", id: "settings-010-todos", value: setting(\.maximumDashboardTasks), range: 1...10)
            numberRow("Maximum Appointments shown", id: "settings-020-appointments", value: setting(\.maximumDashboardAppointments), range: 1...10)
        }
    }
    private var categoriesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeading("Categories")
            subheading("Manage Categories")
            HStack(alignment: .top, spacing: 24) {
                VStack(alignment: .leading, spacing: 10) {
                    SettingsCategoryList(labels: state.workspace.labels, selection: $state.labelID)
                        .frame(width: 210, height: 168)
                    SettingsButton(title: "Add Category", id: "settings-110-add") {
                        let label = PassingByCore.Label(name: "New Category")
                        state.change { $0.labels.append(label) }
                        state.labelID = label.id
                        focus.focus("settings-120-name")
                    }
                }
                VStack(alignment: .leading, spacing: 12) {
                    if let label = state.label {
                        Text("Selected Category").font(.subheadline.weight(.medium))
                        HStack(spacing: 10) {
                            Text("Name").frame(width: 50, alignment: .leading)
                            SettingsTextField(title: "Category name", id: "settings-120-name", text: Binding(get: { state.label?.name ?? "" }, set: { value in
                                state.change { w in if let i = w.labels.firstIndex(where: { $0.id == label.id }) { w.labels[i].name = value } }
                            }))
                        }
                        HStack(spacing: 10) {
                            Text("Color").frame(width: 50, alignment: .leading)
                            SettingsPicker(title: "Color", id: "settings-130-color", value: Binding(get: { state.label?.color ?? .blue }, set: { value in
                                state.change { w in if let i = w.labels.firstIndex(where: { $0.id == label.id }) { w.labels[i].color = value } }
                            }), choices: LabelColor.allCases.map { ($0, $0.rawValue.capitalized) })
                        }
                        SettingsButton(title: "Delete Category", id: "settings-140-delete") {
                            state.change { $0.deleteLabel(label.id) }
                            state.labelID = nil
                            focus.focus("settings-100-list")
                        }
                    } else {
                        explanation("Select a Category to edit it.")
                    }
                }
                .frame(width: 260, alignment: .leading)
            }
            subheading("Default Category")
            categoryPicker("New items", id: "settings-150-default", keyPath: \.defaultLabelID)
            subheading("Scheduled Default")
            SettingsToggle(title: "Use a scheduled default", id: "settings-160-enabled", value: setting(\.scheduledDefaultEnabled))
            if settings.scheduledDefaultEnabled {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 12) {
                        ForEach(Array(weekdays.enumerated()), id: \.element.0) { index, day in
                            SettingsToggle(title: day.1, id: "settings-170-\(index)", value: Binding(get: { settings.scheduledWeekdays.contains(day.0) }, set: { selected in
                                state.change { if selected { $0.settings.scheduledWeekdays.insert(day.0) } else { $0.settings.scheduledWeekdays.remove(day.0) } }
                            }))
                        }
                    }
                    row("From") { SettingsTimePicker(title: "Scheduled default start time", id: "settings-180-start", date: scheduleTime(\.scheduledStartMinute)).fixedSize() }
                    row("Until") { SettingsTimePicker(title: "Scheduled default end time", id: "settings-190-end", date: scheduleTime(\.scheduledEndMinute)).fixedSize() }
                    row("Category") {
                        SettingsPicker(title: "Scheduled default Category", id: "settings-200-category", value: scheduledChoice,
                            choices: [(.unconfigured, "Choose Category…"), (.uncategorized, "Uncategorized")] + state.workspace.labels.map { (.label($0.id), $0.name) })
                    }
                    explanation(validSchedule ? "Outside this schedule, \(fallbackName) will be used." : "Choose a Category and at least one day, with Until later than From. The schedule is inactive until then.")
                }
                .padding(.leading, 20)
            }
        }
    }
    private var todosSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeading("To-dos")
            subheading("Completion")
            row("Confirm completion") {
                SettingsPicker(title: "Confirm completion", id: "settings-300-confirmation", value: setting(\.todoCompletionConfirmation), choices: TodoCompletionConfirmation.allCases.map { ($0, $0.title) })
            }
            explanation("Applies to Dashboard and To-dos. Keyboard only confirms Return and Space; All interactions also confirms mouse clicks. Restoring a To-do never requires confirmation.")
            subheading("Retention")
            row("Keep completed To-dos") {
                SettingsPicker(title: "Keep completed To-dos", id: "settings-310-retention", value: setting(\.taskRetention), choices: RetentionPeriod.allCases.map { ($0, $0.title) })
            }
            ScheduledTodoSettings(state: state, focus: focus)
        }
    }
    private var appointmentsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeading("Appointments")
            subheading("Retention")
            row("Keep passed Appointments") {
                SettingsPicker(title: "Keep passed Appointments", id: "settings-400-retention", value: setting(\.dateRetention), choices: RetentionPeriod.allCases.map { ($0, $0.title) })
            }
            subheading("Upcoming display")
            numberRow("Upcoming per Category", id: "settings-410-maximum", value: setting(\.maximumUpcomingDatesPerLabel), range: 1...50)
            numberRow("Show upcoming within", id: "settings-420-horizon", value: setting(\.upcomingHorizonDays), range: 1...365, suffix: "days")
            subheading("Import")
            SettingsButton(title: "Import TSV…", id: "settings-430-import") { importFlow.selectingFile = true }
        }
    }
    private var notesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeading("Notes")
            subheading("Editor")
            SettingsToggle(title: "Show line numbers", id: "settings-500-lines", value: setting(\.showLineNumbers))
            row("Indent width") {
                SettingsPicker(title: "Indent width", id: "settings-510-indent", value: setting(\.indentWidth), choices: [2, 4, 8].map { ($0, "\($0) spaces") })
            }
            subheading("Text behavior")
            SettingsToggle(title: "Check spelling", id: "settings-520-spelling", value: setting(\.checkSpelling))
            SettingsToggle(title: "Automatic correction", id: "settings-530-correction", value: setting(\.automaticCorrection))
            SettingsToggle(title: "Smart quotes", id: "settings-540-quotes", value: setting(\.smartQuotes))
            SettingsToggle(title: "Smart dashes", id: "settings-550-dashes", value: setting(\.smartDashes))
        }
    }
    private var securitySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeading("Security")
            SettingsToggle(title: "App Lock", id: "settings-600-lock", value: setting(\.appLockEnabled))
            if settings.appLockEnabled {
                SettingsToggle(title: "Lock when app becomes inactive", id: "settings-610-inactive", value: setting(\.lockWhenInactive))
                if settings.lockWhenInactive {
                    row("After") {
                        HStack(spacing: 10) {
                            SettingsNumberField(title: "Inactivity minutes", id: "settings-620-minutes", value: setting(\.inactivityMinutes), range: 1...120).frame(width: 48)
                            Text("minutes")
                        }
                    }
                        .padding(.leading, 20)
                }
                SettingsButton(title: "Lock Now", id: "settings-630-now") { state.lockNow() }
            }
        }
    }
    private func subheading(_ title: String) -> some View {
        Text(title).font(.subheadline.weight(.semibold)).padding(.top, 4)
    }
    private func explanation(_ text: String) -> some View {
        Text(text).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
    }
    private func row<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 16) {
            Text(title).frame(width: 220, alignment: .leading)
            content().frame(maxWidth: 260, alignment: .leading)
        }
    }
    private func numberRow(_ title: String, id: String, value: Binding<Int>, range: ClosedRange<Int>, suffix: String = "") -> some View {
        row(title) {
            HStack(spacing: 10) {
                Text("\(value.wrappedValue)\(suffix.isEmpty ? "" : " " + suffix)").monospacedDigit().frame(minWidth: 74, alignment: .leading)
                SettingsStepper(title: title, id: id, value: value, range: range).fixedSize()
            }
        }
    }
    private func sectionHeading(_ title: String) -> some View { Text(title).font(.system(size: 22 * scale, weight: .semibold)) }
    private func setting<Value>(_ keyPath: WritableKeyPath<AppSettings, Value>) -> Binding<Value> {
        Binding(get: { state.workspace.settings[keyPath: keyPath] }, set: { value in state.change { $0.settings[keyPath: keyPath] = value } })
    }
    private func categoryPicker(_ title: String, id: String, keyPath: WritableKeyPath<AppSettings, UUID?>) -> some View {
        row(title) {
            SettingsPicker(title: title, id: id, value: setting(keyPath), choices: [(UUID?.none, "Uncategorized")] + state.workspace.labels.map { (Optional($0.id), $0.name) })
        }
    }
    private func scheduleTime(_ keyPath: WritableKeyPath<AppSettings, Int>) -> Binding<Date> {
        Binding(get: {
            let minute = state.workspace.settings[keyPath: keyPath]
            return Calendar.current.startOfDay(for: Date()).addingTimeInterval(TimeInterval(minute * 60))
        }, set: { date in
            let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
            state.change { $0.settings[keyPath: keyPath] = (parts.hour ?? 0) * 60 + (parts.minute ?? 0) }
        })
    }
}

private enum ScheduledTodoKind: String, CaseIterable { case weekly = "Weekly", monthly = "Monthly" }
private enum ScheduledTodoCategoryChoice: Hashable { case unselected, uncategorized, category(UUID) }

@MainActor private final class ScheduledTodoDraft: ObservableObject {
    @Published var showingForm = false
    @Published var title = ""
    @Published var kind: ScheduledTodoKind = .weekly
    @Published var interval: ScheduleWeekInterval = .everyWeek
    @Published var weekday: ScheduleWeekday?
    @Published var monthOccurrence: ScheduleMonthOccurrence?
    @Published var category: ScheduledTodoCategoryChoice = .unselected
    @Published var infoID: UUID?
    @Published var deleteID: UUID?
}

private struct ScheduledTodoSettings: View {

    @ObservedObject var state: WorkspaceState
    @StateObject private var draft = ScheduledTodoDraft()
    @ObservedObject var focus: SettingsFocus

    private let weekdays: [ScheduleWeekday] = [.monday, .tuesday, .wednesday, .thursday, .friday, .saturday, .sunday]
    private var canCreate: Bool {
        guard !draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        switch draft.category {
        case .unselected: return false
        case .category(let id) where !state.workspace.labels.contains(where: { $0.id == id }): return false
        default: break
        }
        return draft.kind == .weekly ? draft.weekday != nil : draft.monthOccurrence != nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Scheduled To-dos").font(.subheadline.weight(.semibold)).padding(.top, 4)
            ForEach(Array(state.workspace.scheduledTodos.enumerated()), id: \.element.id) { index, schedule in
                HStack(spacing: 10) {
                    Text(schedule.title).frame(maxWidth: .infinity, alignment: .leading)
                    SettingsButton(title: "Details for \(schedule.title)", id: scheduleControlID(index, "info"), symbol: AppSymbol.details) { draft.infoID = schedule.id }
                        .help("Schedule details")
                        .popover(isPresented: Binding(get: { draft.infoID == schedule.id }, set: { if !$0 { draft.infoID = nil } })) {
                            scheduleInfo(schedule).padding(16).frame(width: 260, alignment: .leading)
                        }
                    SettingsButton(title: "Delete schedule for \(schedule.title)", id: scheduleControlID(index, "remove"), symbol: AppSymbol.delete) { draft.deleteID = schedule.id }
                        .help("Delete schedule")
                }
                .padding(.vertical, 4)
                Divider()
            }
            if draft.showingForm {
                VStack(alignment: .leading, spacing: 10) {
                    SettingsTextField(title: "To-do title", id: "settings-360-title", text: $draft.title)
                    formPicker("Category", id: "settings-361-category", value: $draft.category,
                        choices: [(.unselected, "Choose Category…"), (.uncategorized, "Uncategorized")] + state.workspace.labels.map { (.category($0.id), $0.name) })
                    formPicker("Schedule", id: "settings-362-kind", value: $draft.kind,
                        choices: ScheduledTodoKind.allCases.map { ($0, $0.rawValue) })
                    if draft.kind == .weekly {
                        formPicker("Interval", id: "settings-363-interval", value: $draft.interval,
                            choices: [(.everyWeek, "Every week"), (.everyTwoWeeks, "Every 2 weeks")])
                        formPicker("Weekday", id: "settings-364-weekday", value: $draft.weekday,
                            choices: [(ScheduleWeekday?.none, "Choose weekday…")] + weekdays.map { (Optional($0), $0.name) })
                    } else {
                        formPicker("Occurrence", id: "settings-365-occurrence", value: $draft.monthOccurrence,
                            choices: [(ScheduleMonthOccurrence?.none, "Choose occurrence…")] + ScheduleMonthOccurrence.allCases.map { (Optional($0), $0.name) })
                    }
                    HStack {
                        SettingsButton(title: "Create Schedule", id: "settings-366-create", enabled: canCreate) { create() }
                        SettingsButton(title: "Cancel", id: "settings-367-cancel") { resetForm() }
                    }
                }
                .frame(maxWidth: 420, alignment: .leading)
            } else {
                SettingsButton(title: "Add Scheduled To-do", id: "settings-360-add") {
                    draft.showingForm = true
                    focus.focus("settings-360-title")
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .confirmationDialog("Delete Scheduled To-do?", isPresented: Binding(get: { draft.deleteID != nil }, set: { if !$0 { draft.deleteID = nil } })) {
            Button("Delete Schedule", role: .destructive) {
                if let deleteID = draft.deleteID { state.change { $0.scheduledTodos.removeAll { $0.id == deleteID } } }
                draft.deleteID = nil
                focus.focus(draft.showingForm ? "settings-360-title" : "settings-360-add")
            }
        } message: { Text("To-dos already created by this schedule will remain.") }
    }

    private func scheduleControlID(_ index: Int, _ action: String) -> String {
        "settings-350-" + String(format: "%06d", index) + "-" + action
    }
    private func formPicker<Value: Hashable>(_ title: String, id: String, value: Binding<Value>, choices: [(Value, String)]) -> some View {
        HStack(spacing: 16) {
            Text(title).frame(width: 100, alignment: .leading)
            SettingsPicker(title: title, id: id, value: value, choices: choices)
        }
    }
    private func scheduleInfo(_ schedule: ScheduledTodo) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(schedule.title).font(.headline)
            Text("Category: \(state.workspace.labels.first { $0.id == schedule.categoryID }?.name ?? "Uncategorized")")
            switch schedule.recurrence {
            case .weekly(let interval, let weekday):
                Text("Type: Weekly")
                Text("Interval: \(interval == .everyWeek ? "Every week" : "Every 2 weeks")")
                Text("Weekday: \(weekday.name)")
            case .monthly(let occurrence):
                Text("Type: Monthly")
                Text("Occurrence: \(occurrence.name)")
            }
            Text("Next: \(schedule.nextOccurrence.formatted(date: .abbreviated, time: .omitted))")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func create() {
        guard canCreate else { return }
        let recurrence: ScheduleRecurrence
        switch draft.kind {
        case .weekly: recurrence = .weekly(interval: draft.interval, weekday: draft.weekday!)
        case .monthly: recurrence = .monthly(draft.monthOccurrence!)
        }
        let categoryID: UUID?
        switch draft.category {
        case .category(let id): categoryID = id
        case .uncategorized: categoryID = nil
        case .unselected: return
        }
        let schedule = ScheduledTodo(title: draft.title.trimmingCharacters(in: .whitespacesAndNewlines), categoryID: categoryID, recurrence: recurrence)
        state.change { $0.scheduledTodos.append(schedule) }
        state.refresh()
        resetForm()
    }

    private func resetForm() {
        focus.focus("settings-360-add")
        draft.showingForm = false
        draft.title = ""
        draft.kind = .weekly
        draft.interval = .everyWeek
        draft.weekday = nil
        draft.monthOccurrence = nil
        draft.category = .unselected
    }
}

private extension ScheduleWeekday {
    var name: String {
        switch self {
        case .monday: "Monday"
        case .tuesday: "Tuesday"
        case .wednesday: "Wednesday"
        case .thursday: "Thursday"
        case .friday: "Friday"
        case .saturday: "Saturday"
        case .sunday: "Sunday"
        }
    }
}

private extension ScheduleMonthOccurrence {
    var name: String {
        switch self {
        case .firstDay: "First day of month"
        case .firstWeekday: "First weekday of month"
        case .lastDay: "Last day of month"
        case .lastWeekday: "Last weekday of month"
        }
    }
}

private struct AppointmentImportPreviewView: View {
    @ObservedObject var state: WorkspaceState
    let filename: String
    let parsed: AppointmentTSVImport
    @StateObject private var importFlow = AppointmentImportFlow()
    @Environment(\.dismiss) private var dismiss
    @StateObject private var focus = SettingsFocus()

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Import Appointments").font(.title2.weight(.semibold))
            LabeledContent("File", value: filename)
            HStack {
                Text("Category")
                SettingsPicker(title: "Import Category", id: "settings-010-import-category", value: $importFlow.categoryID,
                    choices: [(UUID?.none, "Uncategorized")] + state.workspace.labels.map { (Optional($0.id), $0.name) })
            }
            Text("\(parsed.rows.count) valid Appointments · \(parsed.issues.count) invalid rows")
                .foregroundStyle(parsed.issues.isEmpty ? Color.secondary : Color.red)
            if parsed.rows.isEmpty && parsed.issues.isEmpty {
                Text("The file contains no Appointments.").foregroundStyle(.secondary)
            }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    ForEach(parsed.rows, id: \.line) { row in
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Line \(row.line) · \(row.date.formatted(.dateTime.day().month().year())) · \(row.title)")
                            if !row.description.isEmpty { Text(row.description).foregroundStyle(.secondary) }
                        }
                    }
                    ForEach(parsed.issues, id: \.line) { issue in
                        Text("Line \(issue.line) — \(issue.reason)").foregroundStyle(.red)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(minHeight: 120, maxHeight: 300)
            HStack {
                Spacer()
                SettingsButton(title: "Cancel", id: "settings-020-import-cancel") { dismiss() }
                SettingsButton(title: "Import", id: "settings-030-import-confirm", enabled: parsed.canImport && !state.isLocked, isDefault: true) {
                    do {
                        try state.importAppointments(parsed, categoryID: importFlow.categoryID)
                        dismiss()
                    } catch { importFlow.importError = error.localizedDescription }
                }

            }
        }
        .padding(24)
        .frame(width: 520)
        .background(SettingsKeyLoop(request: focus.request, requestedID: focus.requestedID))
        .onAppear { focus.focus("settings-010-import-category") }
        .onExitCommand { dismiss() }
        .alert("Could Not Import Appointments", isPresented: Binding(get: { importFlow.importError != nil }, set: { if !$0 { importFlow.importError = nil } })) {
            Button("OK") { importFlow.importError = nil }
        } message: { Text(importFlow.importError ?? "The import could not be saved.") }
    }
}
