import AppKit
import SwiftUI
import PassingByCore
import LocalAuthentication
import Combine
import UniformTypeIdentifiers

private enum Destination: Hashable {
    case dashboard, tasks, appointments, note(UUID), help, settings

    var zoomKey: String? {
        switch self {
        case .dashboard: "dashboard"
        case .tasks: "tasks"
        case .appointments: "appointments"
        case .help: "help"
        case .settings: "settings"
        case .note: nil
        }
    }
}

@MainActor private final class WorkspaceState: ObservableObject {
    @Published private(set) var workspace: Workspace
    @Published var error: String?
    @Published private(set) var isLocked = false
    @Published private(set) var isAuthenticating = false
    private var inactiveSince: Date?
    private var lockTimer: Timer?
    private var authenticationContext: LAContext?
    private var authenticationAttempt = 0
    private var taskDeletionAlert: NSAlert?
    @Published var destination: Destination {
        didSet {
            cancelTaskDeletion()
            switch destination {
            case .dashboard: UserDefaults.standard.set("dashboard", forKey: "area")
            case .tasks: UserDefaults.standard.set("tasks", forKey: "area")
            case .appointments: UserDefaults.standard.set("appointments", forKey: "area")
            case .note(let id):
                UserDefaults.standard.set("note", forKey: "area")
                UserDefaults.standard.set(id.uuidString, forKey: "note")
            case .help: UserDefaults.standard.set("help", forKey: "area")
            case .settings: UserDefaults.standard.set("settings", forKey: "area")
            }
        }
    }
    @Published var labelID: UUID?
    @Published var editingTaskID: UUID?
    @Published var taskDraft: Task?
    @Published var describingTaskID: UUID?
    @Published var editingAppointmentID: UUID?
    @Published var appointmentDraft: DateItem?
    @Published var describingAppointmentID: UUID?
    @Published var deletingAppointmentID: UUID?
    @Published var confirmNoteDeletion = false
    @Published var showReorderNotes = false
    @Published var iconPickerNoteID: UUID?
    @Published var focusNoteTitleID: UUID?
    @Published var titleFocusNonce = 0
    @Published var focusNoteEditorID: UUID?
    @Published var editorFocusNonce = 0
    @Published var selectedTaskID: UUID?
    @Published var selectedAppointmentID: UUID?
    @Published var showCompleted = false
    @Published var showPast = false
    @Published var expanded: Set<String> = []
    @Published private(set) var zoomNotice: String?
    private var zoomNoticeTask: _Concurrency.Task<Void, Never>?
    private var currentDay = Calendar.current.startOfDay(for: Date())
    private let store: AppStore

    init(_ store: AppStore) {
        self.store = store
        workspace = store.workspace
        isLocked = store.workspace.settings.appLockEnabled
        error = store.persistenceError
        let previous = UserDefaults.standard.string(forKey: "area")
        if (previous == "note" || previous == "Notes"),
           let value = UserDefaults.standard.string(forKey: "note"), let id = UUID(uuidString: value) {
            destination = .note(id)
        } else {
            switch previous {
            case "tasks", "Tasks": destination = .tasks
            case "appointments", "Dates": destination = .appointments
            case "help": destination = .help
            case "settings", "Settings": destination = .settings
            default: destination = .dashboard
            }
        }
        reconcile()
    }
    var context: LabelContext { workspace.settings.labelContext == .unlabelled ? .all : workspace.settings.labelContext }
    var contextName: String {
        switch context {
        case .all: "All"
        case .unlabelled: "All"
        case .label(let id): workspace.labels.first { $0.id == id }?.name ?? "All"
        }
    }
    var notes: [Note] { workspace.visibleNotes }
    var tasks: [Task] { workspace.tasks.filter { workspace.matches($0.labelID) && (showCompleted || $0.completedAt == nil) }.sorted { $0.createdAt < $1.createdAt } }
    var appointments: [DateItem] { workspace.matchingDates(showPast: showPast) }
    var label: PassingByCore.Label? { workspace.labels.first { $0.id == labelID } }
    func note(_ id: UUID) -> Note? { workspace.notes.first { $0.id == id } }
    var currentZoom: Int {
        switch destination {
        case .note(let id): note(id)?.zoomPercent ?? 100
        default: workspace.settings.screenZoom[destination.zoomKey ?? ""] ?? 100
        }
    }
    func changeZoom(by delta: Int) {
        guard !isLocked else { return }
        let current = currentZoom
        let next = min(ZoomLevel.maximum, max(ZoomLevel.minimum, current + delta))
        if next == current {
            showZoomNotice(delta > 0 ? "Maximum size · \(ZoomLevel.maximum)%" : "Minimum size · \(ZoomLevel.minimum)%")
            return
        }
        change { workspace in
            switch destination {
            case .note(let id):
                if let index = workspace.notes.firstIndex(where: { $0.id == id }) { workspace.notes[index].zoomPercent = next }
            default:
                if let key = destination.zoomKey { workspace.settings.screenZoom[key] = next }
            }
        }
        if next == ZoomLevel.minimum || next == ZoomLevel.maximum {
            showZoomNotice(next == ZoomLevel.maximum ? "Maximum size · \(next)%" : "Minimum size · \(next)%")
        }
    }
    func resetAllZoom() {
        change { workspace in
            for index in workspace.notes.indices { workspace.notes[index].zoomPercent = 100 }
            workspace.settings.screenZoom.removeAll()
        }
    }
    private func showZoomNotice(_ message: String) {
        zoomNoticeTask?.cancel()
        zoomNotice = message
        zoomNoticeTask = _Concurrency.Task { @MainActor in
            try? await _Concurrency.Task.sleep(for: .seconds(1.5))
            if !_Concurrency.Task.isCancelled { zoomNotice = nil }
        }
    }
    func task(_ id: UUID) -> Task? { taskDraft?.id == id ? taskDraft : workspace.tasks.first { $0.id == id } }
    func appointment(_ id: UUID) -> DateItem? { appointmentDraft?.id == id ? appointmentDraft : workspace.dates.first { $0.id == id } }

    private func reconcile() {
        if workspace.settings.labelContext == .unlabelled {
            store.change { $0.settings.labelContext = .all }
            workspace = store.workspace
        }
        if case .label(let id) = context, !workspace.labels.contains(where: { $0.id == id }) {
            store.change { $0.settings.labelContext = .all }
            workspace = store.workspace
        }
        if case .note(let id) = destination, !notes.contains(where: { $0.id == id }) { destination = .dashboard }
        if !workspace.labels.contains(where: { $0.id == labelID }) { labelID = workspace.labels.first?.id }
    }
    func change(_ edit: (inout Workspace) -> Void) {
        store.change(edit); workspace = store.workspace; error = store.persistenceError; reconcile()
        if !workspace.settings.appLockEnabled {
            cancelPendingLock()
            isLocked = false
        } else if !workspace.settings.lockWhenInactive {
            cancelPendingLock()
        } else if inactiveSince != nil {
            scheduleInactiveLock()
        }
    }
    func lockNow() {
        guard workspace.settings.appLockEnabled else { return }
        authenticationAttempt += 1
        authenticationContext?.invalidate()
        authenticationContext = nil
        isAuthenticating = false
        isLocked = true
        cancelTaskDeletion()
        cancelPendingLock()
    }
    func unlock() {
        guard isLocked, workspace.settings.appLockEnabled, !isAuthenticating else { return }
        let context = LAContext()
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: nil) else { return }
        authenticationAttempt += 1
        let attempt = authenticationAttempt
        authenticationContext = context
        isAuthenticating = true
        context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "Unlock Passing By") { [weak self] success, _ in
            _Concurrency.Task { @MainActor in
                guard let self, self.authenticationAttempt == attempt else { return }
                self.authenticationContext = nil
                self.isAuthenticating = false
                if success && self.workspace.settings.appLockEnabled { self.isLocked = false }
            }
        }
    }
    func becameInactive() {
        guard workspace.settings.appLockEnabled, workspace.settings.lockWhenInactive else { return }
        if inactiveSince == nil { inactiveSince = Date() }
        scheduleInactiveLock()
    }
    func becameActive() {
        if let inactiveSince, workspace.settings.appLockEnabled, workspace.settings.lockWhenInactive,
           Date().timeIntervalSince(inactiveSince) >= TimeInterval(workspace.settings.inactivityMinutes * 60) {
            lockNow()
        }
        cancelPendingLock()
        refresh()
    }
    private func scheduleInactiveLock() {
        lockTimer?.invalidate()
        lockTimer = nil
        guard let inactiveSince, workspace.settings.appLockEnabled, workspace.settings.lockWhenInactive else { return }
        let remaining = TimeInterval(workspace.settings.inactivityMinutes * 60) - Date().timeIntervalSince(inactiveSince)
        if remaining <= 0 { lockNow(); return }
        lockTimer = Timer.scheduledTimer(withTimeInterval: remaining, repeats: false) { [weak self] _ in
            _Concurrency.Task { @MainActor in
                guard let self, self.inactiveSince != nil, !NSApp.isActive else { return }
                self.lockNow()
            }
        }
    }
    private func cancelPendingLock() {
        lockTimer?.invalidate()
        lockTimer = nil
        inactiveSince = nil
    }
    func flush() {
        let needsNormalization =
            workspace.notes.contains { $0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } ||
            workspace.tasks.contains { $0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } ||
            workspace.dates.contains { $0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } ||
            workspace.labels.contains { $0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        if needsNormalization {
            change { w in
                for i in w.notes.indices where w.notes[i].title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { w.notes[i].title = "Untitled Note" }
                for i in w.tasks.indices where w.tasks[i].title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { w.tasks[i].title = "New To-do" }
                for i in w.dates.indices where w.dates[i].title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { w.dates[i].title = "New Appointment" }
                for i in w.labels.indices where w.labels[i].name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { w.labels[i].name = "New Category" }
            }
        }
        _ = store.flush(); error = store.persistenceError
    }
    func refresh() {
        store.cleanUp()
        store.evaluateScheduledTodos()
        workspace = store.workspace
        error = store.persistenceError
        reconcile()
    }
    func refreshIfDayChanged() {
        let today = Calendar.current.startOfDay(for: Date())
        if today != currentDay { currentDay = today; refresh() }
    }
    func createNote() {
        var item: Note!
        change { workspace in
            item = workspace.createNote()
            if case .label(let id) = workspace.settings.labelContext, id != item.labelID { workspace.settings.labelContext = .all }
        }
        destination = .note(item.id)
        focusNoteTitleID = item.id
        titleFocusNonce += 1
    }
    func createTask() -> UUID {
        if let id = editingTaskID { return id }
        let draft = workspace.makeTaskDraft()
        taskDraft = draft
        return draft.id
    }
    func createAppointment() -> UUID {
        if let id = editingAppointmentID { return id }
        let draft = workspace.makeAppointmentDraft()
        appointmentDraft = draft
        return draft.id
    }
    func finishTaskEditing() {
        if let draft = taskDraft {
            change { workspace in
                workspace.addTaskDraft(draft)
                if case .label(let id) = workspace.settings.labelContext, id != draft.labelID { workspace.settings.labelContext = .all }
            }
            selectedTaskID = draft.id
            taskDraft = nil
        }
        flush()
        editingTaskID = nil
    }
    func finishAppointmentEditing() {
        if let draft = appointmentDraft {
            change { workspace in
                workspace.addAppointmentDraft(draft)
                if case .label(let id) = workspace.settings.labelContext, id != draft.labelID { workspace.settings.labelContext = .all }
            }
            selectedAppointmentID = draft.id
            appointmentDraft = nil
        }
        flush()
        editingAppointmentID = nil
    }
    func closeTaskEditing() {
        taskDraft = nil
        flush()
        editingTaskID = nil
    }
    func closeAppointmentEditing() {
        appointmentDraft = nil
        flush()
        editingAppointmentID = nil
    }
    func importAppointments(_ parsed: AppointmentTSVImport, categoryID: UUID?) throws {
        guard !isLocked else { throw AppointmentImportError.locked }
        try store.importAppointments(parsed, categoryID: categoryID)
        workspace = store.workspace
        error = store.persistenceError
    }
    func editNote(_ id: UUID, _ edit: (inout Note) -> Void) { change { w in if let i = w.notes.firstIndex(where: { $0.id == id }) { edit(&w.notes[i]); w.notes[i].updatedAt = Date() } } }
    func editTask(_ id: UUID, _ edit: (inout Task) -> Void) {
        if taskDraft?.id == id { edit(&taskDraft!); return }
        change { w in if let i = w.tasks.firstIndex(where: { $0.id == id }) { edit(&w.tasks[i]) } }
    }
    func editAppointment(_ id: UUID, _ edit: (inout DateItem) -> Void) {
        if appointmentDraft?.id == id { edit(&appointmentDraft!); return }
        change { w in if let i = w.dates.firstIndex(where: { $0.id == id }) { edit(&w.dates[i]) } }
    }
    func createContextualItem() {
        switch destination {
        case .tasks: editingTaskID = createTask()
        case .appointments: editingAppointmentID = createAppointment()
        default: createNote()
        }
    }
    func focusNoteTitle() { if case .note(let id) = destination { focusNoteTitleID = id; titleFocusNonce += 1 } }
    func focusNoteEditor(_ id: UUID) { focusNoteEditorID = id; editorFocusNonce += 1 }
    private func cancelTaskDeletion() {
        guard let alert = taskDeletionAlert else { return }
        taskDeletionAlert = nil
        if let parent = alert.window.sheetParent {
            parent.endSheet(alert.window, returnCode: .alertSecondButtonReturn)
        }
    }
    func confirmTaskDeletion(_ id: UUID, fromCurrentItem: Bool = false) {
        guard !isLocked, taskDeletionAlert == nil,
              let task = workspace.tasks.first(where: { $0.id == id }),
              let window = NSApp.keyWindow, window.attachedSheet == nil else { return }
        let currentResponder = window.firstResponder as? NSView
        // Resolve the deleted row's neighbour even when Cmd+Delete targets a mouse-selected row.
        let visibleTasks = tasks
        let rowIndex = visibleTasks.firstIndex { $0.id == id }
        let neighbourID = rowIndex.flatMap { index in
            index + 1 < visibleTasks.count ? visibleTasks[index + 1].id : (index > 0 ? visibleTasks[index - 1].id : nil)
        }
        func control(_ identifier: String, in view: NSView) -> NSView? {
            if view.identifier?.rawValue == identifier { return view }
            for child in view.subviews {
                if let found = control(identifier, in: child) { return found }
            }
            return nil
        }
        let content = window.sheetParent?.contentView ?? window.contentView
        let rowButton = rowIndex.flatMap { index in content.flatMap { control("todos-\(13 + index * 4)", in: $0) } }
        let source = fromCurrentItem ? currentResponder : rowButton ?? currentResponder
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Delete this To-do?"
        alert.informativeText = "\(task.title.isEmpty ? "New To-do" : task.title)\nThis cannot be undone."
        alert.addButton(withTitle: "Delete To-do")
        alert.addButton(withTitle: "Cancel")
        alert.buttons[0].hasDestructiveAction = true
        taskDeletionAlert = alert
        // NSAlert normally omits button Tab stops when system keyboard navigation is off.
        let keyboardMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak alert] event in
            guard let alert, event.window === alert.window else { return event }
            if event.keyCode == 48 {
                let buttons = alert.buttons
                let current = buttons.firstIndex { alert.window.firstResponder === $0 }
                let reverse = event.modifierFlags.contains(.shift)
                let index = current.map { ($0 + (reverse ? buttons.count - 1 : 1)) % buttons.count } ?? (reverse ? buttons.count - 1 : 0)
                alert.window.makeFirstResponder(buttons[index])
                return nil
            }
            if (event.keyCode == 36 || event.keyCode == 49),
               let button = alert.buttons.first(where: { alert.window.firstResponder === $0 }) {
                if !event.isARepeat { button.performClick(nil) }
                return nil
            }
            if event.isARepeat && event.keyCode == 36 { return nil }
            return event
        }
        alert.beginSheetModal(for: window) { [weak self, weak alert, weak source, weak content] response in
            if let keyboardMonitor { NSEvent.removeMonitor(keyboardMonitor) }
            guard let self, self.taskDeletionAlert === alert else { return }
            self.taskDeletionAlert = nil
            guard !self.isLocked, self.destination == .tasks else { return }
            if response == .alertFirstButtonReturn {
                if self.editingTaskID == id { self.closeTaskEditing() }
                self.change { $0.tasks.removeAll { $0.id == id } }
                if self.selectedTaskID == id { self.selectedTaskID = nil }
            }
            DispatchQueue.main.async { [weak self, weak source, weak content] in
                guard let self, !self.isLocked, self.destination == .tasks else { return }
                let target: NSView?
                if response == .alertFirstButtonReturn, let content {
                    let identifier = self.tasks.firstIndex { $0.id == neighbourID }.map { "todos-\(10 + $0 * 4)" } ?? "todos-1"
                    target = control(identifier, in: content)
                } else { target = source }
                guard let target, let window = target.window else { return }
                target.scrollToVisible(target.bounds.insetBy(dx: 0, dy: -16))
                window.makeFirstResponder(target)
            }
        }
    }
    func deleteCurrentItem() {
        guard taskDraft == nil, appointmentDraft == nil else { return }
        switch destination {
        case .note: confirmNoteDeletion = true
        case .tasks:
            if let id = editingTaskID ?? selectedTaskID, tasks.contains(where: { $0.id == id }) {
                confirmTaskDeletion(id, fromCurrentItem: true)
            }
        case .appointments:
            if let id = editingAppointmentID ?? selectedAppointmentID, appointments.contains(where: { $0.id == id }) {
                editingAppointmentID = nil
                deletingAppointmentID = id
            }
        default: break
        }
    }
}

@MainActor private final class Startup: ObservableObject {
    let state: WorkspaceState?
    let error: String?
    private var stateChanges: AnyCancellable?
    private var lifecycle: [AnyCancellable] = []
    init() {
        do { state = WorkspaceState(try AppStore()); error = nil }
        catch { state = nil; self.error = error.localizedDescription }
        stateChanges = state?.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }
        lifecycle = [
            NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)
                .sink { [weak self] _ in self?.state?.becameInactive() },
            NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)
                .sink { [weak self] _ in self?.state?.becameActive() },
            NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.willSleepNotification)
                .sink { [weak self] _ in self?.state?.lockNow() },
            NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didWakeNotification)
                .sink { [weak self] _ in if !NSApp.isActive { self?.state?.becameInactive() } }
        ]
    }
}

private struct AppShortcut {
    let key: KeyEquivalent
    let modifiers: EventModifiers
    let display: String
    let description: String

    static let dashboard = Self(key: "1", modifiers: .command, display: "⌘1", description: "Dashboard")
    static let tasks = Self(key: "2", modifiers: .command, display: "⌘2", description: "To-dos")
    static let appointments = Self(key: "3", modifiers: .command, display: "⌘3", description: "Appointments")
    static let help = Self(key: "0", modifiers: .command, display: "⌘0", description: "Help")
    static let settings = Self(key: ",", modifiers: .command, display: "⌘,", description: "Settings")
    static let newItem = Self(key: "n", modifiers: .command, display: "⌘N", description: "New item for the current view")
    static let newNote = Self(key: "n", modifiers: [.command, .shift], display: "⇧⌘N", description: "New Note")
    static let reorderNotes = Self(key: "r", modifiers: [.command, .option], display: "⌥⌘R", description: "Reorder Notes")
    static let noteTitle = Self(key: "t", modifiers: [.command, .shift], display: "⇧⌘T", description: "Focus Note Title")
    static let delete = Self(key: .delete, modifiers: .command, display: "⌘⌫", description: "Delete current or selected item")
    static let lock = Self(key: "l", modifiers: [.command, .shift], display: "⇧⌘L", description: "Lock Passing By (when enabled)")
    static let find = Self(key: "f", modifiers: .command, display: "⌘F", description: "Find in open Note")
    static let findNext = Self(key: "g", modifiers: .command, display: "⌘G", description: "Find next")
    static let findPrevious = Self(key: "g", modifiers: [.command, .shift], display: "⇧⌘G", description: "Find previous")
    static let zoomIn = Self(key: "+", modifiers: .command, display: "⌘+", description: "Increase current screen size")
    static let zoomOut = Self(key: "-", modifiers: .command, display: "⌘−", description: "Decrease current screen size")

    static func note(_ index: Int, title: String) -> Self {
        let number = index + 4
        return Self(key: KeyEquivalent(Character(String(number))), modifiers: .command,
                    display: "⌘\(number)", description: title.isEmpty ? "Untitled Note" : title)
    }
}

@main struct PassingByApp: App {
    @StateObject private var startup = Startup()
    private var shortcutNotes: [Note] {
        guard let state = startup.state, !state.isLocked else { return [] }
        return state.workspace.shortcutNotes
    }
    var body: some Scene {
        Window("Passing By", id: "main") { StartupView(startup: startup) }
            .defaultSize(width: 1060, height: 700)
            .commands {
                CommandGroup(replacing: .appInfo) {
                    Button("About Passing By") { showAboutPanel() }
                }
                CommandGroup(replacing: .newItem) {
                    Button("New Item") { startup.state?.createContextualItem() }.keyboardShortcut(AppShortcut.newItem.key, modifiers: AppShortcut.newItem.modifiers).disabled(startup.state?.isLocked ?? true)
                    Button("New Note") { startup.state?.createNote() }.keyboardShortcut(AppShortcut.newNote.key, modifiers: AppShortcut.newNote.modifiers).disabled(startup.state?.isLocked ?? true)
                }
                CommandGroup(replacing: .appSettings) {
                    Button("Settings") { startup.state?.destination = .settings }.keyboardShortcut(AppShortcut.settings.key, modifiers: AppShortcut.settings.modifiers).disabled(startup.state?.isLocked ?? true)
                }
                CommandMenu("Navigate") {
                    Button("Dashboard") { startup.state?.destination = .dashboard }.keyboardShortcut(AppShortcut.dashboard.key, modifiers: AppShortcut.dashboard.modifiers).disabled(startup.state?.isLocked ?? true)
                    Button("To-dos") { startup.state?.destination = .tasks }.keyboardShortcut(AppShortcut.tasks.key, modifiers: AppShortcut.tasks.modifiers).disabled(startup.state?.isLocked ?? true)
                    Button("Appointments") { startup.state?.destination = .appointments }.keyboardShortcut(AppShortcut.appointments.key, modifiers: AppShortcut.appointments.modifiers).disabled(startup.state?.isLocked ?? true)
                    ForEach(Array(shortcutNotes.enumerated()), id: \.element.id) { index, note in
                        Button(note.title.isEmpty ? "Untitled Note" : note.title) { startup.state?.destination = .note(note.id) }
                        .keyboardShortcut(AppShortcut.note(index, title: note.title).key, modifiers: AppShortcut.note(index, title: note.title).modifiers)
                    }
                    Divider()
                    Button("Reorder Notes…") { startup.state?.showReorderNotes = true }
                        .keyboardShortcut(AppShortcut.reorderNotes.key, modifiers: AppShortcut.reorderNotes.modifiers)
                        .disabled((startup.state?.workspace.notes.count ?? 0) < 2 || (startup.state?.isLocked ?? true))
                }
                CommandGroup(replacing: .help) {
                    Button("Passing By Help") { startup.state?.destination = .help }
                        .keyboardShortcut(AppShortcut.help.key, modifiers: AppShortcut.help.modifiers)
                        .disabled(startup.state?.isLocked ?? true)
                }
                CommandMenu("Item") {
                    Button("Focus Note Title") { startup.state?.focusNoteTitle() }.keyboardShortcut(AppShortcut.noteTitle.key, modifiers: AppShortcut.noteTitle.modifiers).disabled(startup.state?.isLocked ?? true)
                    Button("Delete") { startup.state?.deleteCurrentItem() }.keyboardShortcut(AppShortcut.delete.key, modifiers: AppShortcut.delete.modifiers).disabled(startup.state?.isLocked ?? true)
                    Divider()
                    Button("Lock Passing By") { startup.state?.lockNow() }
                        .keyboardShortcut(AppShortcut.lock.key, modifiers: AppShortcut.lock.modifiers)
                        .disabled(!(startup.state?.workspace.settings.appLockEnabled ?? false) || (startup.state?.isLocked ?? true))
                }
                CommandMenu("View") {
                    Button("Increase Size") { startup.state?.changeZoom(by: ZoomLevel.step) }
                        .keyboardShortcut(AppShortcut.zoomIn.key, modifiers: AppShortcut.zoomIn.modifiers)
                        .disabled(startup.state?.isLocked ?? true)
                    Button("Decrease Size") { startup.state?.changeZoom(by: -ZoomLevel.step) }
                        .keyboardShortcut(AppShortcut.zoomOut.key, modifiers: AppShortcut.zoomOut.modifiers)
                        .disabled(startup.state?.isLocked ?? true)
                }
                CommandGroup(after: .textEditing) {
                    Divider()
                    Button("Find…") { performFindAction(1) }.keyboardShortcut(AppShortcut.find.key, modifiers: AppShortcut.find.modifiers).disabled(startup.state?.isLocked ?? true)
                    Button("Find Next") { performFindAction(2) }.keyboardShortcut(AppShortcut.findNext.key, modifiers: AppShortcut.findNext.modifiers).disabled(startup.state?.isLocked ?? true)
                    Button("Find Previous") { performFindAction(3) }.keyboardShortcut(AppShortcut.findPrevious.key, modifiers: AppShortcut.findPrevious.modifiers).disabled(startup.state?.isLocked ?? true)
                }
            }
    }
}

@MainActor private func showAboutPanel() {
    let bundle = Bundle.main
    let version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
    let build = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = .center
    let credits = NSAttributedString(string: """
        A lightweight, local-first macOS app for notes, to-dos, and appointments.

        Created by Christian Pflugradt
        """, attributes: [
            .font: NSFont.systemFont(ofSize: 13),
            .foregroundColor: NSColor.secondaryLabelColor,
            .paragraphStyle: paragraph
        ])
    NSApp.orderFrontStandardAboutPanel(options: [
        .applicationVersion: version == "0.0.0" ? "Development build" : "Version \(version)",
        .version: build == version ? "" : build,
        .credits: credits
    ])
}

@MainActor private func performFindAction(_ tag: Int) {
    let sender = NSMenuItem()
    sender.tag = tag
    NSApp.sendAction(#selector(NSTextView.performFindPanelAction(_:)), to: nil, from: sender)
}

private struct StartupView: View {
    @ObservedObject var startup: Startup
    var body: some View {
        Group {
            if let state = startup.state {
                if state.isLocked { LockedView(state: state) }
                else { WorkspaceView(state: state) }
            } else {
                ContentUnavailableView("Workspace Could Not Open", systemImage: AppSymbol.error, description: Text(startup.error ?? "The workspace could not be loaded."))
            }
        }
        .onAppear { if NSApp.isActive { startup.state?.becameActive() } else { startup.state?.becameInactive() } }
        .onDisappear { startup.state?.flush() }
    }
}

private struct LockedView: View {
    @ObservedObject var state: WorkspaceState
    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: AppSymbol.locked).font(.system(size: 42)).foregroundStyle(.secondary)
            Text("Passing By").font(.title2.weight(.semibold))
            Text("Locked").foregroundStyle(.secondary)
            Button("Unlock") { state.unlock() }.disabled(state.isAuthenticating)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .frame(minWidth: 650, minHeight: 410)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

private struct WorkspaceView: View {
    @ObservedObject var state: WorkspaceState
    @Environment(\.scenePhase) private var scenePhase
    var body: some View {
        HSplitView {
            GeometryReader { geometry in
                VStack(spacing: 0) {
                    ScrollView {
                        VStack(spacing: 5) {
                            sidebarButton("Dashboard", icon: AppSymbol.dashboard, destination: .dashboard)
                            sidebarButton("To-dos", icon: AppSymbol.todos, destination: .tasks)
                            sidebarButton("Appointments", icon: AppSymbol.appointments, destination: .appointments)
                            Divider().padding(.vertical, 11).padding(.horizontal, 13)
                            ForEach(state.notes) { note in
                                sidebarButton(note.title.isEmpty ? "Untitled Note" : note.title, icon: availableNoteIcon(note.iconName), destination: .note(note.id), categoryID: note.labelID)
                            }
                            Button(action: state.createNote) { Image(systemName: AppSymbol.add).font(.system(size: 17)).frame(width: 48, height: 44).contentShape(Rectangle()) }
                                .buttonStyle(.plain).help("New Note").accessibilityLabel("New Note")
                        }
                        .padding(.top, 12)
                    }
                    Spacer(minLength: 0)
                    sidebarButton("Help", icon: AppSymbol.help, destination: .help)
                    sidebarButton("Settings", icon: AppSymbol.settings, destination: .settings).padding(.bottom, 12)
                }
                .frame(width: 68, height: geometry.size.height)
            }
            .frame(width: 68)
            Group {
                switch state.destination {
                case .dashboard: DashboardView(state: state)
                case .tasks: TasksView(state: state)
                case .appointments: AppointmentsView(state: state)
                case .note(let id): NoteView(state: state, id: id)
                case .help: HelpView(state: state, notes: state.workspace.shortcutNotes)
                case .settings: SettingsView(state: state)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay(alignment: .topTrailing) {
                if let notice = state.zoomNotice {
                    Text(notice)
                        .font(.callout)
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 9))
                        .padding(16)
                        .allowsHitTesting(false)
                        .transition(.opacity)
                }
            }
        }
        .frame(minWidth: 650, minHeight: 410)
        .sheet(isPresented: $state.showReorderNotes) { ReorderNotesView(state: state) }
        .alert("Could Not Save Changes", isPresented: Binding(get: { state.error != nil }, set: { if !$0 { state.error = nil } })) {
            Button("Retry") { state.flush() }
            Button("Keep Editing", role: .cancel) { }
        } message: { Text(state.error ?? "Your changes remain in memory. Retry saving before quitting.") }
        .onChange(of: scenePhase) { _, phase in if phase == .active { state.refresh() } else { state.flush() } }
        .onChange(of: state.destination) { _, _ in state.flush() }
        .onDisappear { state.flush() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in state.flush() }
        .onReceive(Timer.publish(every: 60, on: .main, in: .common).autoconnect()) { _ in state.refreshIfDayChanged() }
    }
    private func sidebarButton(_ title: String, icon: String, destination: Destination, categoryID: UUID? = nil) -> some View {
        Button { state.destination = destination } label: {
            ZStack(alignment: .bottomTrailing) {
                Image(systemName: icon).font(.system(size: 19)).frame(width: 48, height: 44)
                if categoryID != nil { categoryDot(categoryID, state.workspace.labels).offset(x: -6, y: -5) }
            }
            .frame(width: 48, height: 44)
            .background(state.destination == destination ? Color.accentColor.opacity(0.2) : .clear, in: RoundedRectangle(cornerRadius: 9))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain).help(title).accessibilityLabel(title)
    }
}

private struct ReorderNotesView: View {
    @ObservedObject var state: WorkspaceState
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Reorder Notes").font(.title2.weight(.semibold))
            List {
                ForEach(state.workspace.notes) { note in
                    HStack(spacing: 12) {
                        VStack(spacing: 3) {
                            ForEach(0..<3, id: \.self) { _ in
                                HStack(spacing: 3) {
                                    Circle().frame(width: 3, height: 3)
                                    Circle().frame(width: 3, height: 3)
                                }
                            }
                        }
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                        Image(systemName: availableNoteIcon(note.iconName))
                            .frame(width: 22)
                        Text(note.title.isEmpty ? "Untitled Note" : note.title)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .draggable(note.id.uuidString)
                    .dropDestination(for: String.self) { identifiers, _ in
                        guard let identifier = identifiers.first, let sourceID = UUID(uuidString: identifier),
                              let source = state.workspace.notes.firstIndex(where: { $0.id == sourceID }),
                              let target = state.workspace.notes.firstIndex(where: { $0.id == note.id }) else { return false }
                        state.change { $0.moveNote(from: source, to: target) }
                        return true
                    }
                }
            }
            .frame(minHeight: 150, maxHeight: 400)
            HStack {
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 360)
    }
}

private struct LabelFilter: View {
    @ObservedObject var state: WorkspaceState
    var keyboardScope = "dashboard"
    private var selection: Binding<LabelContext> {
        Binding(get: { state.context }, set: { value in state.change { $0.settings.labelContext = value } })
    }
    var body: some View {
        KeyboardCategoryFilter(labels: state.workspace.labels, selection: selection, scope: keyboardScope)
            .id((1...4).contains(state.workspace.labels.count))
            .fixedSize()
    }
}

private struct ItemLabelPicker: View {
    let labels: [PassingByCore.Label]
    @Binding var id: UUID?
    var body: some View {
        Picker("Category", selection: $id) {
            Text("Uncategorized").tag(UUID?.none)
            ForEach(labels) { label in Text(label.name).tag(Optional(label.id)) }
        }
    }
}

private struct PageHeader<Trailing: View>: View {
    let title: String
    let scale: CGFloat
    @ViewBuilder let trailing: Trailing
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            Text(title).font(.system(size: 34 * scale, weight: .semibold))
            Spacer()
            trailing
        }
        .padding(.bottom, 12)
    }
}

private struct DashboardView: View {
    @ObservedObject var state: WorkspaceState
    private var scale: CGFloat { CGFloat(state.currentZoom) / 100 }
    private var openTasks: [Task] { Array(state.workspace.tasks.filter { $0.completedAt == nil && state.workspace.matches($0.labelID) }.sorted { $0.createdAt < $1.createdAt }.prefix(state.workspace.settings.maximumDashboardTasks)) }
    private var upcoming: [DateItem] { Array(state.workspace.upcomingDates().prefix(state.workspace.settings.maximumDashboardAppointments)) }
    private var statisticsText: String {
        let days = state.workspace.daysPassed()
        let todos = state.workspace.completedTodoCount
        let appointments = state.workspace.passedAppointmentCount()
        return "\(days.formatted()) \(days == 1 ? "Day" : "Days") Passed · \(todos.formatted()) \(todos == 1 ? "To-do" : "To-dos") Completed · \(appointments.formatted()) \(appointments == 1 ? "Appointment" : "Appointments") Passed"
    }
    var body: some View {
        VStack(spacing: 0) {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                PageHeader(title: "Dashboard", scale: scale) { LabelFilter(state: state) }
                HStack(alignment: .top, spacing: 52) {
                    VStack(alignment: .leading, spacing: 0) {
                        KeyboardButton(title: "To-dos", pointSize: 22 * scale, bold: true, dashboardOrder: 10, accessibilityLabel: "Open To-dos") { state.destination = .tasks }
                            .fixedSize()
                            .padding(.bottom, 20)
                        if openTasks.isEmpty {
                            Text("No open To-dos").foregroundStyle(.secondary).padding(.top, 12)
                        }
                        ForEach(Array(openTasks.enumerated()), id: \.element.id) { index, task in
                            HStack(spacing: 12) {
                                KeyboardButton(symbol: AppSymbol.incomplete, pointSize: 20 * scale, dashboardOrder: 20 + index * 2, advancesFocus: true, completionConfirmation: state.workspace.settings.todoCompletionConfirmation, taskTitle: task.title, accessibilityLabel: "Complete \(task.title)") {
                                    state.editTask(task.id) { $0.completedAt = Date() }
                                }
                                .fixedSize()
                                categoryDot(task.labelID, state.workspace.labels)
                                Text(task.title).font(.system(size: 16 * scale)).frame(maxWidth: .infinity, alignment: .leading)
                                DescriptionInfoButton(description: task.taskDescription, isPresented: Binding(
                                    get: { state.describingTaskID == task.id },
                                    set: { state.describingTaskID = $0 ? task.id : nil }
                                ), dashboardOrder: 21 + index * 2)
                            }
                            .padding(.vertical, 15)
                            Divider()
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    VStack(alignment: .leading, spacing: 0) {
                        KeyboardButton(title: "Appointments", pointSize: 22 * scale, bold: true, dashboardOrder: 100, accessibilityLabel: "Open Appointments") { state.destination = .appointments }
                            .fixedSize()
                            .padding(.bottom, 20)
                        if upcoming.isEmpty {
                            Text("No upcoming Appointments").foregroundStyle(.secondary).padding(.top, 12)
                        }
                        ForEach(Array(upcoming.enumerated()), id: \.element.id) { index, item in
                            HStack(alignment: .top, spacing: 12) {
                                categoryDot(item.labelID, state.workspace.labels)
                                    .padding(.top, 6)
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack(spacing: 5) {
                                        Text(relativeDate(item.date)).fontWeight(.semibold)
                                        Text("·").foregroundStyle(.secondary)
                                        Text(item.date.formatted(.dateTime.day().month(.abbreviated)))
                                            .foregroundStyle(.secondary)
                                    }.font(.system(size: 13 * scale))
                                    Text(item.title).font(.system(size: 16 * scale))
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                DescriptionInfoButton(description: item.itemDescription, isPresented: Binding(
                                    get: { state.describingAppointmentID == item.id },
                                    set: { state.describingAppointmentID = $0 ? item.id : nil }
                                ), dashboardOrder: 110 + index)
                                .padding(.top, 2)
                            }
                            .padding(.vertical, 11)
                            Divider()
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .frame(maxWidth: 900, alignment: .leading)
            .padding(.horizontal, 34).padding(.vertical, 28)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        Text(statisticsText)
            .font(.system(size: 11 * scale))
            .foregroundStyle(.secondary)
            .frame(maxWidth: 900, alignment: .leading)
            .padding(.horizontal, 34)
            .frame(maxWidth: .infinity, alignment: .center)
            .frame(height: 35)
            .overlay(alignment: .top) { Rectangle().fill(Color(nsColor: .separatorColor)).frame(height: 1) }
        }
        .environment(\.font, .system(size: 13 * scale))
        .onAppear { state.refreshIfDayChanged() }
        .background(ScreenKeyLoop(itemIDs: openTasks.map(\.id) + upcoming.map(\.id), descriptionPresence: openTasks.map { !$0.taskDescription.isEmpty } + upcoming.map { !$0.itemDescription.isEmpty }))
    }
}

private struct TasksView: View {
    @ObservedObject var state: WorkspaceState
    private var scale: CGFloat { CGFloat(state.currentZoom) / 100 }
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PageHeader(title: "To-dos", scale: scale) {
                LabelFilter(state: state, keyboardScope: "todos")
                KeyboardButton(symbol: AppSymbol.add, pointSize: 13 * scale, todoOrder: 1, bordered: true, accessibilityLabel: "New To-do") {
                    state.editingTaskID = state.createTask()
                }.fixedSize().help("New To-do")
            }
            KeyboardButton(title: "Show Completed To-dos", pointSize: 13 * scale, todoOrder: 2, checked: state.showCompleted, accessibilityLabel: "Show Completed To-dos") {
                state.showCompleted.toggle()
            }.fixedSize().padding(.bottom, 16)
            if state.tasks.isEmpty {
                EmptyItems(kind: "To-dos", context: state.contextName)
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(Array(state.tasks.enumerated()), id: \.element.id) { index, task in
                            HStack(spacing: 15) {
                                KeyboardButton(
                                    symbol: task.completedAt == nil ? AppSymbol.incomplete : AppSymbol.complete,
                                    pointSize: 20 * scale,
                                    todoOrder: 10 + index * 4,
                                    advancesFocus: !state.showCompleted,
                                    completionConfirmation: state.workspace.settings.todoCompletionConfirmation,
                                    taskTitle: task.completedAt == nil ? task.title : nil,
                                    accessibilityLabel: task.completedAt == nil ? "Complete \(task.title)" : "Restore \(task.title)"
                                ) {
                                    state.editTask(task.id) { $0.completedAt = task.completedAt == nil ? Date() : nil }
                                }.fixedSize()
                                categoryDot(task.labelID, state.workspace.labels)
                                Text(task.title.isEmpty ? "New To-do" : task.title)
                                    .font(.system(size: 16 * scale))
                                    .foregroundStyle(task.completedAt == nil ? .primary : .secondary)
                                    .strikethrough(task.completedAt != nil)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                DescriptionInfoButton(description: task.taskDescription, isPresented: Binding(
                                    get: { state.describingTaskID == task.id },
                                    set: { state.describingTaskID = $0 ? task.id : nil }
                                ), todoOrder: 11 + index * 4)
                                KeyboardButton(symbol: AppSymbol.edit, todoOrder: 12 + index * 4, accessibilityLabel: "Edit To-do") {
                                    state.editingTaskID = task.id
                                }.fixedSize().help("Edit To-do")
                                KeyboardButton(symbol: AppSymbol.delete, todoOrder: 13 + index * 4, accessibilityLabel: "Delete To-do") {
                                    state.confirmTaskDeletion(task.id)
                                }.fixedSize().help("Delete To-do")
                            }
                            .padding(.vertical, 17)
                            .padding(.horizontal, 8)
                            .background(state.selectedTaskID == task.id ? Color.accentColor.opacity(0.10) : .clear, in: RoundedRectangle(cornerRadius: 7))
                            .contentShape(Rectangle())
                            .onTapGesture { state.selectedTaskID = task.id }
                            Divider()
                        }
                    }
                }
            }
        }
        .frame(maxWidth: 850, maxHeight: .infinity, alignment: .topLeading)
        .padding(.horizontal, 34).padding(.top, 28)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .environment(\.font, .system(size: 13 * scale))
        .background(ScreenKeyLoop(scope: "todos", itemIDs: state.tasks.map(\.id), descriptionPresence: state.tasks.map { !$0.taskDescription.isEmpty }))
        .sheet(isPresented: Binding(get: { state.editingTaskID != nil }, set: { if !$0 { state.closeTaskEditing() } })) {
            if let id = state.editingTaskID { TaskEditor(state: state, id: id) }
        }
    }
}

private struct DescriptionInfoButton: View {
    let description: String
    @Binding var isPresented: Bool
    var dashboardOrder: Int? = nil
    var todoOrder: Int? = nil

    private var popoverHeight: CGFloat {
        let text = NSAttributedString(string: description, attributes: [.font: NSFont.systemFont(ofSize: NSFont.systemFontSize)])
        let textHeight = text.boundingRect(
            with: NSSize(width: 328, height: CGFloat.greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading]
        ).height
        return min(max(52, ceil(textHeight) + 32), 400)
    }

    var body: some View {
        if !description.isEmpty {
            KeyboardButton(symbol: AppSymbol.details, dashboardOrder: dashboardOrder, todoOrder: todoOrder, accessibilityLabel: "Show description") { isPresented = true }
                .fixedSize()
                .help("Show description")
                .popover(isPresented: $isPresented) {
                    ScrollView {
                        Text(description)
                            .fixedSize(horizontal: false, vertical: true)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(16)
                    }
                    .frame(width: 360, height: popoverHeight)
                }
        }
    }
}

private struct TaskEditor: View {
    @ObservedObject var state: WorkspaceState
    let id: UUID
    var body: some View {
        NativeItemEditor(
            title: Binding(get: { state.task(id)?.title ?? "" }, set: { value in state.editTask(id) { $0.title = value } }),
            description: Binding(get: { state.task(id)?.taskDescription ?? "" }, set: { value in state.editTask(id) { $0.taskDescription = value } }),
            labels: state.workspace.labels,
            categoryID: Binding(get: { state.task(id)?.labelID }, set: { value in state.editTask(id) { $0.labelID = value } }),
            onDone: state.finishTaskEditing,
            onClose: state.closeTaskEditing
        )
        .frame(width: 440, height: 300)
    }
}

private struct AppointmentsView: View {
    @ObservedObject var state: WorkspaceState
    private var scale: CGFloat { CGFloat(state.currentZoom) / 100 }
    private var groups: [DateGroup] { state.workspace.dateGroups(showPast: state.showPast, expanded: state.expanded) }
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PageHeader(title: "Appointments", scale: scale) {
                LabelFilter(state: state)
                Button { state.editingAppointmentID = state.createAppointment() } label: { Image(systemName: AppSymbol.add) }
                    .help("New Appointment")
            }
            HStack {
                Picker("Display", selection: Binding(get: { state.workspace.settings.dateDisplayMode }, set: { value in state.change { $0.settings.dateDisplayMode = value } })) {
                    Text("Chronological").tag(DateDisplayMode.chronological)
                    Text("By Category").tag(DateDisplayMode.byLabel)
                }.pickerStyle(.segmented).labelsHidden().frame(width: 240)
                Spacer()
                Toggle("Show past", isOn: $state.showPast).toggleStyle(.checkbox)
            }.padding(.bottom, 16)
            if state.appointments.isEmpty || (state.workspace.settings.dateDisplayMode == .byLabel && groups.isEmpty) {
                EmptyItems(kind: "appointments", context: state.contextName)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        if state.workspace.settings.dateDisplayMode == .chronological {
                            ForEach(state.appointments) { item in row(item) }
                        } else {
                            ForEach(groups) { group in
                                HStack(spacing: 10) {
                                    categoryDot(UUID(uuidString: group.id), state.workspace.labels)
                                    Text(group.id == "unlabelled" ? "Uncategorized" : group.name)
                                }
                                .font(.system(size: 22 * scale, weight: .semibold))
                                .padding(.top, 24).padding(.bottom, 10)
                                ForEach(group.items) { item in row(item) }
                                if group.hiddenUpcomingCount > 0 {
                                    Button(state.expanded.contains(group.id) ? "Show fewer" : "Show \(group.hiddenUpcomingCount) more…") {
                                        if state.expanded.contains(group.id) { state.expanded.remove(group.id) }
                                        else { state.expanded.insert(group.id) }
                                    }.buttonStyle(.link).padding(.vertical, 10)
                                }
                            }
                        }
                    }
                }
            }
        }
        .frame(maxWidth: 850, maxHeight: .infinity, alignment: .topLeading)
        .padding(.horizontal, 34).padding(.top, 28)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .environment(\.font, .system(size: 13 * scale))
        .sheet(isPresented: Binding(get: { state.editingAppointmentID != nil }, set: { if !$0 { state.closeAppointmentEditing() } })) {
            if let id = state.editingAppointmentID { AppointmentEditor(state: state, id: id) }
        }
        .confirmationDialog("Delete this appointment?", isPresented: Binding(get: { state.deletingAppointmentID != nil }, set: { if !$0 { state.deletingAppointmentID = nil } })) {
            Button("Delete Appointment", role: .destructive) {
                if let id = state.deletingAppointmentID { state.change { $0.dates.removeAll { $0.id == id } } }
                state.deletingAppointmentID = nil
            }
        } message: { Text("This cannot be undone.") }
    }
    private func row(_ item: DateItem) -> some View {
        VStack(spacing: 0) {
          HStack(spacing: 16) {
            categoryDot(item.labelID, state.workspace.labels)
            VStack(alignment: .leading, spacing: 5) {
                Text(item.title.isEmpty ? "New Appointment" : item.title).font(.system(size: 16 * scale))
                HStack(spacing: 8) {
                    Text(item.date.formatted(date: .abbreviated, time: .omitted))
                    Text("·")
                    Text(relativeDate(item.date))
                    if let label = state.workspace.labels.first(where: { $0.id == item.labelID }) {
                        Text("·"); Text(label.name)
                    }
                }.font(.system(size: 13 * scale)).foregroundStyle(.secondary)
            }
            .foregroundStyle(state.workspace.isPassed(item) ? .secondary : .primary)
            .frame(maxWidth: .infinity, alignment: .leading)
            DescriptionInfoButton(description: item.itemDescription, isPresented: Binding(
                get: { state.describingAppointmentID == item.id },
                set: { state.describingAppointmentID = $0 ? item.id : nil }
            ))
            Button { state.editingAppointmentID = item.id } label: { Image(systemName: AppSymbol.edit) }
                .buttonStyle(.plain).foregroundStyle(.secondary).help("Edit Appointment")
            Button { state.deletingAppointmentID = item.id } label: { Image(systemName: AppSymbol.delete) }
                .buttonStyle(.plain).foregroundStyle(.secondary).help("Delete Appointment")
        }
          .padding(.vertical, 16)
          .padding(.horizontal, 8)
          .background(state.selectedAppointmentID == item.id ? Color.accentColor.opacity(0.10) : .clear, in: RoundedRectangle(cornerRadius: 7))
          .contentShape(Rectangle())
          .onTapGesture { state.selectedAppointmentID = item.id }
          Divider()
        }
    }
}

private struct AppointmentEditor: View {
    @ObservedObject var state: WorkspaceState
    let id: UUID
    var body: some View {
        NativeItemEditor(
            title: Binding(get: { state.appointment(id)?.title ?? "" }, set: { value in state.editAppointment(id) { $0.title = value } }),
            description: Binding(get: { state.appointment(id)?.itemDescription ?? "" }, set: { value in state.editAppointment(id) { $0.itemDescription = value } }),
            labels: state.workspace.labels,
            categoryID: Binding(get: { state.appointment(id)?.labelID }, set: { value in state.editAppointment(id) { $0.labelID = value } }),
            date: Binding(get: { state.appointment(id)?.date ?? Date() }, set: { value in state.editAppointment(id) { $0.date = value } }),
            onDone: state.finishAppointmentEditing,
            onClose: state.closeAppointmentEditing
        )
        .frame(width: 440, height: 340)
    }
}

private struct NoteView: View {
    @ObservedObject var state: WorkspaceState
    let id: UUID
    private var scale: CGFloat { CGFloat(state.note(id)?.zoomPercent ?? 100) / 100 }
    @FocusState private var titleFocused: Bool
    @FocusState private var categoryFocused: Bool
    @StateObject private var editorStatus = NoteEditorStatusModel()
    var body: some View {
        Group {
            if let note = state.note(id) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .center, spacing: 12) {
                        Button { state.iconPickerNoteID = id } label: {
                            Image(systemName: availableNoteIcon(note.iconName)).font(.system(size: 20 * scale)).frame(width: 32 * scale, height: 32 * scale)
                        }
                        .buttonStyle(.plain).help("Choose Note Icon")
                        .focusable(false)
                        .popover(isPresented: Binding(get: { state.iconPickerNoteID == id }, set: { if !$0 { state.iconPickerNoteID = nil } }), arrowEdge: .leading) {
                            LazyVGrid(columns: Array(repeating: GridItem(.fixed(38)), count: 7), spacing: 8) {
                                ForEach(NoteIcon.choices, id: \.self) { name in
                                    Button {
                                        state.editNote(id) { $0.iconName = name }
                                        state.iconPickerNoteID = nil
                                    } label: { Image(systemName: name).font(.system(size: 18)).frame(width: 34, height: 34) }
                                        .buttonStyle(.plain).help(name)
                                        .background(note.iconName == name ? Color.accentColor.opacity(0.2) : .clear, in: RoundedRectangle(cornerRadius: 6))
                                }
                            }.padding(12)
                        }
                        TextField("Title", text: Binding(get: { state.note(id)?.title ?? "" }, set: { value in state.editNote(id) { $0.title = value } }))
                            .font(.system(size: 22 * scale, weight: .semibold)).textFieldStyle(.plain)
                            .frame(minWidth: 120, maxWidth: 400, alignment: .leading)
                            .focused($titleFocused)
                            .onKeyPress(.tab) { categoryFocused = true; return .handled }
                        ItemLabelPicker(labels: state.workspace.labels, id: Binding(get: { state.note(id)?.labelID }, set: { value in state.editNote(id) { $0.labelID = value } }))
                            .labelsHidden().frame(width: 155).focusable(true)
                            .focused($categoryFocused)
                            .onKeyPress(.tab) { state.focusNoteEditor(id); return .handled }
                        Spacer(minLength: 0)
                        Button { state.confirmNoteDeletion = true } label: { Image(systemName: AppSymbol.delete) }
                            .buttonStyle(.plain).foregroundStyle(.secondary).help("Delete Note").focusable(false)
                    }
                    MarkdownTextView(text: Binding(get: { state.note(id)?.contentMarkdown ?? "" }, set: { value in state.editNote(id) { $0.contentMarkdown = value } }), settings: state.workspace.settings, status: editorStatus, focusRequest: state.focusNoteEditorID == id ? state.editorFocusNonce : nil, zoomPercent: note.zoomPercent)
                        .id(id).frame(maxWidth: .infinity, maxHeight: .infinity).clipped()
                    HStack {
                        Text("Ln \(editorStatus.value.line.formatted()), Col \(editorStatus.value.column.formatted())")
                        Spacer()
                        Text("\(editorStatus.value.words.formatted()) \(editorStatus.value.words == 1 ? "word" : "words") · \(editorStatus.value.characters.formatted()) \(editorStatus.value.characters == 1 ? "character" : "characters")")
                    }
                    .font(.system(size: 11 * scale))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .frame(height: 26)
                    .overlay(alignment: .top) { Rectangle().fill(Color(nsColor: .separatorColor)).frame(height: 1) }
                }
                .padding(.horizontal, 34).padding(.top, 28).padding(.bottom, 20)
                .environment(\.font, .system(size: 13 * scale))
                .onAppear { if state.focusNoteTitleID == id { titleFocused = true; state.focusNoteTitleID = nil } }
                .onChange(of: state.titleFocusNonce) { _, _ in if state.focusNoteTitleID == id { titleFocused = true; state.focusNoteTitleID = nil } }
                .confirmationDialog("Delete \(note.title.isEmpty ? "Untitled Note" : note.title)?", isPresented: $state.confirmNoteDeletion) {
                    Button("Delete Note", role: .destructive) { state.change { $0.notes.removeAll { $0.id == id } } }
                } message: { Text("This cannot be undone.") }
            } else {
                ContentUnavailableView("Note Unavailable", systemImage: AppSymbol.unavailableNote)
            }
        }
    }
}

private struct HelpView: View {
    @ObservedObject var state: WorkspaceState
    let notes: [Note]
    private var scale: CGFloat { CGFloat(state.currentZoom) / 100 }
    private var shortcuts: [AppShortcut] {
        [AppShortcut.dashboard, .tasks, .appointments] +
        Array(notes.prefix(6).enumerated()).map { AppShortcut.note($0.offset, title: $0.element.title) } +
        [.help, .settings, .newItem, .newNote, .reorderNotes, .noteTitle, .delete, .lock, .find, .findNext, .findPrevious, .zoomIn, .zoomOut]
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("Help").font(.system(size: 34 * scale, weight: .semibold))
                Text("Passing By keeps everyday notes, to-dos, and appointments close at hand. Your information stays locally on this Mac, and changes are saved automatically.")
                section("Categories", "Create Categories in Settings to organize To-dos, Appointments, and Notes. Work, Personal, and Sports are examples you might create. A Default Category applies to new items; a Scheduled Default can use another Category on selected weekdays and times.")
                section("To-dos", "Create To-dos and assign them to Categories. Mark one complete to remove it from the open list. Turn on Show Completed To-dos to see completed items and restore one if you checked it off by mistake. Deleting a To-do always requires confirmation.")
                section("Appointments", "Create Appointments and assign them to Categories. Upcoming Appointments appear on the Dashboard alongside open To-dos. The Appointments view can also show past items.")
                VStack(alignment: .leading, spacing: 8) {
                    Text("Bulk Import").font(.system(size: 22 * scale, weight: .semibold))
                    Text("Settings → Appointments → Bulk Import adds multiple Appointments at once, such as a training plan, schedule, or list of planned dates. Use one tab-separated line per Appointment:")
                    Text("DD.MM.YYYY<TAB>Title<TAB>Description")
                        .font(.system(size: 13 * scale, design: .monospaced))
                        .textSelection(.enabled)
                    Text("Description is optional.").foregroundStyle(.secondary)
                }
                section("Notes", "Create individual Notes and assign them to Categories. Edit Markdown source with syntax highlighting, optional line numbers, word and character counts, Find, Undo and Redo, spell checking, and space-based indentation. Standard Cut, Copy, Paste, and Select All also work. Each Note remembers its own text size.")
                section("Dashboard", "See a compact view of open To-dos and upcoming Appointments. The Category filter narrows the view to one context.")
                section("App Lock", "Enable App Lock in Settings to prevent casual access through Passing By. Unlock with macOS authentication, including Touch ID when available. You can also set the app to lock after it becomes inactive. App Lock does not encrypt the workspace file on disk.")
                VStack(alignment: .leading, spacing: 12) {
                    Text("Keyboard Shortcuts").font(.system(size: 22 * scale, weight: .semibold))
                    Text("⌘N creates a To-do or Appointment in those views, and a Note elsewhere. Note shortcuts follow the first six Notes currently shown in the sidebar.")
                        .foregroundStyle(.secondary)
                    Text("In To-do and Appointment dialogs, Tab and Shift-Tab move between fields, including Category. Return in the title or ⌘Return activates Done; Return in the description adds a new line. Escape discards a new item, or closes an existing item while keeping its changes.")
                        .foregroundStyle(.secondary)
                    Text("On Dashboard, Tab follows the Category filter, To-dos, then Appointments. Left and Right switch categories in the segmented filter; Space opens a category menu. Return or Space activates a focused action. Escape closes a description.")
                        .foregroundStyle(.secondary)
                    Text("On To-dos, Tab follows Category, New To-do, Show Completed To-dos, then each row’s Complete or Restore, Description when present, Edit, and Delete actions. Shift-Tab reverses this order.")
                        .foregroundStyle(.secondary)
                    Grid(alignment: .leading, horizontalSpacing: 30, verticalSpacing: 7) {
                        ForEach(shortcuts.indices, id: \.self) { index in
                            let shortcut = shortcuts[index]
                            GridRow {
                                Text(shortcut.display)
                                    .font(.system(size: 13 * scale, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                    .frame(minWidth: 80, alignment: .leading)
                                Text(shortcut.description)
                            }
                        }
                        GridRow {
                            Text("⌘Z / ⇧⌘Z").font(.system(size: 13 * scale, design: .monospaced)).foregroundStyle(.secondary)
                            Text("Undo / Redo in the Note editor")
                        }
                    }
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text("More").font(.system(size: 22 * scale, weight: .semibold))
                    Text("Passing By is open source. Visit the project on GitHub for source code, issues, and further information.")
                    Link("Open GitHub Repository", destination: URL(string: "https://github.com/christianpflugradt/PassingBy")!)
                }
            }
            .frame(maxWidth: 680, alignment: .leading)
            .padding(.horizontal, 34).padding(.vertical, 28)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .environment(\.font, .system(size: 13 * scale))
    }
    private func section(_ heading: String, _ copy: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(heading).font(.system(size: 22 * scale, weight: .semibold))
            Text(copy)
        }
    }
}

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

private struct SettingsView: View {
    private enum ScheduledChoice: Hashable { case unconfigured, uncategorized, label(UUID) }
    @ObservedObject var state: WorkspaceState
    private var scale: CGFloat { CGFloat(state.currentZoom) / 100 }
    @StateObject private var importFlow = AppointmentImportFlow()
    private let weekdays: [(Int, String)] = [(2, "Mon"), (3, "Tue"), (4, "Wed"), (5, "Thu"), (6, "Fri"), (7, "Sat"), (1, "Sun")]
    private var settings: AppSettings { state.workspace.settings }
    private var minuteFormatter: NumberFormatter {
        let formatter = NumberFormatter()
        formatter.numberStyle = .none
        formatter.allowsFloats = false
        formatter.minimum = 1
        formatter.maximum = 120
        formatter.isLenient = false
        return formatter
    }
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
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                Text("Settings").font(.system(size: 34 * scale, weight: .semibold))
                VStack(alignment: .leading, spacing: 12) {
                    sectionHeading("Display")
                    Button("Reset All Zoom Levels") { state.resetAllZoom() }
                    Text("Restores the default size for every Note and screen.").foregroundStyle(.secondary)
                }
                VStack(alignment: .leading, spacing: 12) {
                    sectionHeading("Dashboard")
                    HStack(spacing: 12) {
                        Text("Maximum To-dos shown")
                        Text("\(settings.maximumDashboardTasks)").monospacedDigit()
                        Stepper("Maximum To-dos shown", value: setting(\.maximumDashboardTasks), in: 1...10).labelsHidden()
                    }
                    HStack(spacing: 12) {
                        Text("Maximum Appointments shown")
                        Text("\(settings.maximumDashboardAppointments)").monospacedDigit()
                        Stepper("Maximum Appointments shown", value: setting(\.maximumDashboardAppointments), in: 1...10).labelsHidden()
                    }
                }
                VStack(alignment: .leading, spacing: 15) {
                    sectionHeading("Categories")
                    HStack(alignment: .top, spacing: 24) {
                        VStack(alignment: .leading, spacing: 10) {
                            List(selection: $state.labelID) {
                                ForEach(state.workspace.labels) { label in
                                    HStack(spacing: 10) { categoryDot(label.id, state.workspace.labels); Text(label.name) }
                                        .tag(label.id)
                                }
                            }
                            .frame(width: 210, height: 168)
                            Button("Add Category") {
                                let label = PassingByCore.Label(name: "New Category")
                                state.change { $0.labels.append(label) }
                                state.labelID = label.id
                            }
                        }
                        VStack(alignment: .leading, spacing: 12) {
                            if let label = state.label {
                                Text("Selected Category").font(.headline)
                                TextField("Name", text: Binding(get: { state.label?.name ?? "" }, set: { value in state.change { w in if let i = w.labels.firstIndex(where: { $0.id == label.id }) { w.labels[i].name = value } } }))
                                Picker("Color", selection: Binding(get: { state.label?.color ?? .blue }, set: { value in state.change { w in if let i = w.labels.firstIndex(where: { $0.id == label.id }) { w.labels[i].color = value } } })) {
                                    ForEach(LabelColor.allCases) { color in Text(color.rawValue.capitalized).tag(color) }
                                }
                                Button("Delete Category", role: .destructive) { state.change { $0.deleteLabel(label.id) } }
                            } else {
                                Text("Select a Category to edit it.").foregroundStyle(.secondary)
                            }
                        }
                        .frame(width: 260, alignment: .leading)
                    }
                    Divider()
                    categoryPicker("Default Category", keyPath: \.defaultLabelID)
                    Toggle("Scheduled Default", isOn: setting(\.scheduledDefaultEnabled)).toggleStyle(.checkbox)
                    if settings.scheduledDefaultEnabled {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Days").font(.subheadline.weight(.medium))
                            HStack(spacing: 12) {
                                ForEach(weekdays, id: \.0) { day in
                                    Toggle(day.1, isOn: Binding(get: { settings.scheduledWeekdays.contains(day.0) }, set: { selected in
                                        state.change { if selected { $0.settings.scheduledWeekdays.insert(day.0) } else { $0.settings.scheduledWeekdays.remove(day.0) } }
                                    })).toggleStyle(.checkbox)
                                }
                            }
                            HStack(spacing: 24) {
                                DatePicker("From", selection: scheduleTime(\.scheduledStartMinute), displayedComponents: .hourAndMinute)
                                DatePicker("Until", selection: scheduleTime(\.scheduledEndMinute), displayedComponents: .hourAndMinute)
                            }
                            Picker("Category", selection: scheduledChoice) {
                                Text("Choose Category…").tag(ScheduledChoice.unconfigured)
                                Text("Uncategorized").tag(ScheduledChoice.uncategorized)
                                ForEach(state.workspace.labels) { label in Text(label.name).tag(ScheduledChoice.label(label.id)) }
                            }
                            if validSchedule {
                                Text("Outside this schedule, \(fallbackName) will be used.").foregroundStyle(.secondary)
                            } else {
                                Text("Choose a Category and at least one day, with Until later than From. The schedule is inactive until then.")
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.leading, 20)
                    }
                }
                VStack(alignment: .leading, spacing: 12) {
                    sectionHeading("To-dos")
                    Picker("Confirm completion", selection: setting(\.todoCompletionConfirmation)) {
                        ForEach(TodoCompletionConfirmation.allCases, id: \.self) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    Text("Applies to Dashboard and To-dos. Keyboard only confirms Return and Space; All interactions also confirms mouse clicks. Restoring a To-do never requires confirmation.")
                        .font(.caption).foregroundStyle(.secondary)
                    Picker("Keep completed To-dos", selection: setting(\.taskRetention)) {
                        ForEach(RetentionPeriod.allCases) { period in Text(period.title).tag(period) }
                    }
                    ScheduledTodoSettings(state: state)
                }
                VStack(alignment: .leading, spacing: 12) {
                    sectionHeading("Appointments")
                    Picker("Keep passed Appointments", selection: setting(\.dateRetention)) {
                        ForEach(RetentionPeriod.allCases) { period in Text(period.title).tag(period) }
                    }
                    Stepper("Upcoming per Category: \(settings.maximumUpcomingDatesPerLabel)", value: setting(\.maximumUpcomingDatesPerLabel), in: 1...50)
                    HStack {
                        Text("Show upcoming within")
                        Stepper("Days", value: setting(\.upcomingHorizonDays), in: 1...365)
                            .labelsHidden()
                        Text("\(settings.upcomingHorizonDays) days")
                    }
                    Text("Bulk Import").font(.subheadline.weight(.semibold)).padding(.top, 4)
                    Button("Import TSV…") { importFlow.selectingFile = true }
                }
                VStack(alignment: .leading, spacing: 12) {
                    sectionHeading("Notes")
                    Toggle("Show line numbers", isOn: setting(\.showLineNumbers)).toggleStyle(.checkbox)
                    Picker("Indent width", selection: setting(\.indentWidth)) {
                        ForEach([2, 4, 8], id: \.self) { width in Text("\(width) spaces").tag(width) }
                    }
                    Text("Text behavior").font(.subheadline.weight(.semibold)).padding(.top, 4)
                    Toggle("Check spelling", isOn: setting(\.checkSpelling)).toggleStyle(.checkbox)
                    Toggle("Automatic correction", isOn: setting(\.automaticCorrection)).toggleStyle(.checkbox)
                    Toggle("Smart quotes", isOn: setting(\.smartQuotes)).toggleStyle(.checkbox)
                    Toggle("Smart dashes", isOn: setting(\.smartDashes)).toggleStyle(.checkbox)
                }
                VStack(alignment: .leading, spacing: 12) {
                    sectionHeading("Security")
                    Toggle("App Lock", isOn: setting(\.appLockEnabled)).toggleStyle(.checkbox)
                    if settings.appLockEnabled {
                        Toggle("Lock when app becomes inactive", isOn: setting(\.lockWhenInactive)).toggleStyle(.checkbox)
                        if settings.lockWhenInactive {
                            HStack {
                                Text("After")
                                TextField("Minutes", value: setting(\.inactivityMinutes), formatter: minuteFormatter)
                                    .frame(width: 48)
                                Text("minutes")
                            }
                            .padding(.leading, 20)
                        }
                        Button("Lock Now") { state.lockNow() }
                    }
                }
            }
            .frame(maxWidth: 650, alignment: .leading)
            .padding(.horizontal, 34).padding(.vertical, 28)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .environment(\.font, .system(size: 13 * scale))
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
    private func sectionHeading(_ title: String) -> some View { Text(title).font(.system(size: 22 * scale, weight: .semibold)) }
    private func setting<Value>(_ keyPath: WritableKeyPath<AppSettings, Value>) -> Binding<Value> {
        Binding(get: { state.workspace.settings[keyPath: keyPath] }, set: { value in state.change { $0.settings[keyPath: keyPath] = value } })
    }
    private func categoryPicker(_ title: String, keyPath: WritableKeyPath<AppSettings, UUID?>) -> some View {
        Picker(title, selection: setting(keyPath)) {
            Text("Uncategorized").tag(UUID?.none)
            ForEach(state.workspace.labels) { label in Text(label.name).tag(Optional(label.id)) }
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
            ForEach(state.workspace.scheduledTodos) { schedule in
                HStack(spacing: 10) {
                    Text(schedule.title).frame(maxWidth: .infinity, alignment: .leading)
                    Button { draft.infoID = schedule.id } label: { Image(systemName: AppSymbol.details) }
                        .buttonStyle(.plain).foregroundStyle(.secondary).help("Schedule details")
                        .accessibilityLabel("Details for \(schedule.title)")
                        .popover(isPresented: Binding(get: { draft.infoID == schedule.id }, set: { if !$0 { draft.infoID = nil } })) {
                            scheduleInfo(schedule).padding(16).frame(width: 260, alignment: .leading)
                        }
                    Button { draft.deleteID = schedule.id } label: { Image(systemName: AppSymbol.delete) }
                        .buttonStyle(.plain).foregroundStyle(.secondary).help("Delete schedule")
                        .accessibilityLabel("Delete schedule for \(schedule.title)")
                }
                .padding(.vertical, 4)
                Divider()
            }
            if draft.showingForm {
                VStack(alignment: .leading, spacing: 10) {
                    TextField("To-do title", text: $draft.title)
                    Picker("Category", selection: $draft.category) {
                        Text("Choose Category…").tag(ScheduledTodoCategoryChoice.unselected)
                        Text("Uncategorized").tag(ScheduledTodoCategoryChoice.uncategorized)
                        ForEach(state.workspace.labels) { label in Text(label.name).tag(ScheduledTodoCategoryChoice.category(label.id)) }
                    }
                    Picker("Schedule", selection: $draft.kind) {
                        ForEach(ScheduledTodoKind.allCases, id: \.self) { value in Text(value.rawValue).tag(value) }
                    }
                    if draft.kind == .weekly {
                        Picker("Interval", selection: $draft.interval) {
                            Text("Every week").tag(ScheduleWeekInterval.everyWeek)
                            Text("Every 2 weeks").tag(ScheduleWeekInterval.everyTwoWeeks)
                        }
                        Picker("Weekday", selection: $draft.weekday) {
                            Text("Choose weekday…").tag(ScheduleWeekday?.none)
                            ForEach(weekdays) { day in Text(day.name).tag(Optional(day)) }
                        }
                    } else {
                        Picker("Occurrence", selection: $draft.monthOccurrence) {
                            Text("Choose occurrence…").tag(ScheduleMonthOccurrence?.none)
                            ForEach(ScheduleMonthOccurrence.allCases) { choice in Text(choice.name).tag(Optional(choice)) }
                        }
                    }
                    HStack {
                        Button("Create Schedule") { create() }.disabled(!canCreate)
                        Button("Cancel") { resetForm() }
                    }
                }
                .frame(maxWidth: 420, alignment: .leading)
            } else {
                Button("Add Scheduled To-do") { draft.showingForm = true }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .confirmationDialog("Delete Scheduled To-do?", isPresented: Binding(get: { draft.deleteID != nil }, set: { if !$0 { draft.deleteID = nil } })) {
            Button("Delete Schedule", role: .destructive) {
                if let deleteID = draft.deleteID { state.change { $0.scheduledTodos.removeAll { $0.id == deleteID } } }
                draft.deleteID = nil
            }
        } message: { Text("To-dos already created by this schedule will remain.") }
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

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Import Appointments").font(.title2.weight(.semibold))
            LabeledContent("File", value: filename)
            ItemLabelPicker(labels: state.workspace.labels, id: $importFlow.categoryID)
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
                Button("Cancel") { dismiss() }
                Button("Import") {
                    do {
                        try state.importAppointments(parsed, categoryID: importFlow.categoryID)
                        dismiss()
                    } catch { importFlow.importError = error.localizedDescription }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!parsed.canImport || state.isLocked)
            }
        }
        .padding(24)
        .frame(width: 520)
        .alert("Could Not Import Appointments", isPresented: Binding(get: { importFlow.importError != nil }, set: { if !$0 { importFlow.importError = nil } })) {
            Button("OK") { importFlow.importError = nil }
        } message: { Text(importFlow.importError ?? "The import could not be saved.") }
    }
}

private struct EmptyItems: View {
    let kind: String
    let context: String
    var body: some View {
        Text(context == "All" ? "No \(kind) here" : "No \(kind) under \(context)")
            .foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

@ViewBuilder private func categoryDot(_ id: UUID?, _ labels: [PassingByCore.Label]) -> some View {
    if let label = labels.first(where: { $0.id == id }) {
        Circle().fill(labelColor(label.color)).frame(width: 8, height: 8).accessibilityLabel(label.name)
    }
}
private func labelColor(_ value: LabelColor) -> Color {
    switch value { case .blue: .blue; case .purple: .purple; case .pink: .pink; case .red: .red; case .orange: .orange; case .yellow: .yellow; case .green: .green; case .gray: .gray }
}

private func relativeDate(_ date: Date) -> String {
    let calendar = Calendar.current
    let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: Date()), to: calendar.startOfDay(for: date)).day ?? 0
    return switch days { case 0: "Today"; case 1: "Tomorrow"; case -1: "Yesterday"; default: days < 0 ? "\(-days) days ago" : "in \(days) days" }
}

private func availableNoteIcon(_ name: String) -> String {
    let safe = NoteIcon.safeName(name)
    return NSImage(systemSymbolName: safe, accessibilityDescription: nil) == nil ? NoteIcon.defaultName : safe
}

private struct MarkdownTextView: NSViewRepresentable {
    @Binding var text: String
    let settings: AppSettings
    let status: NoteEditorStatusModel
    let focusRequest: Int?
    let zoomPercent: Int
    private var fontSize: CGFloat { 13 * CGFloat(zoomPercent) / 100 }
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        let editor = NoteEditorTextView(frame: .zero)
        editor.isRichText = false
        editor.allowsUndo = true
        editor.usesFindBar = true
        editor.isIncrementalSearchingEnabled = true
        editor.isContinuousSpellCheckingEnabled = settings.checkSpelling
        editor.isAutomaticSpellingCorrectionEnabled = settings.automaticCorrection
        editor.isAutomaticQuoteSubstitutionEnabled = settings.smartQuotes
        editor.isAutomaticDashSubstitutionEnabled = settings.smartDashes
        editor.isAutomaticTextReplacementEnabled = false
        editor.indentWidth = settings.indentWidth
        editor.isVerticallyResizable = true
        editor.isHorizontallyResizable = false
        editor.autoresizingMask = [.width]
        editor.textContainer?.widthTracksTextView = true
        editor.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        editor.textContainerInset = NSSize(width: 8, height: 8)
        editor.font = .monospacedSystemFont(ofSize: fontSize, weight: .regular)
        editor.zoomPercent = zoomPercent
        editor.linkTextAttributes = [:]
        editor.delegate = context.coordinator
        editor.string = text
        scroll.documentView = editor
        let ruler = NoteLineNumberRuler(scrollView: scroll, orientation: .verticalRuler)
        ruler.clientView = editor
        scroll.verticalRulerView = ruler
        scroll.hasVerticalRuler = true
        scroll.rulersVisible = settings.showLineNumbers
        ruler.noteTextDidChange()
        context.coordinator.highlight(editor)
        context.coordinator.updateStatus(editor)
        return scroll
    }
    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let editor = scroll.documentView as? NSTextView else { return }
        editor.isContinuousSpellCheckingEnabled = settings.checkSpelling
        editor.isAutomaticSpellingCorrectionEnabled = settings.automaticCorrection
        editor.isAutomaticQuoteSubstitutionEnabled = settings.smartQuotes
        editor.isAutomaticDashSubstitutionEnabled = settings.smartDashes
        (editor as? NoteEditorTextView)?.indentWidth = settings.indentWidth
        scroll.rulersVisible = settings.showLineNumbers
        if let noteEditor = editor as? NoteEditorTextView, noteEditor.zoomPercent != zoomPercent {
            noteEditor.zoomPercent = zoomPercent
            context.coordinator.highlight(editor)
            (scroll.verticalRulerView as? NoteLineNumberRuler)?.noteTextDidChange()
        }
        // AppKit owns provisional text while a dead key or input method is composing.
        // Replacing the string here ends composition and moves the insertion point.
        if editor.string != text && !editor.hasMarkedText() {
            let selection = editor.selectedRange()
            editor.string = text
            let length = (text as NSString).length
            let location = min(selection.location, length)
            editor.setSelectedRange(NSRange(location: location, length: min(selection.length, length - location)))
            context.coordinator.highlight(editor)
            context.coordinator.updateStatus(editor)
            (scroll.verticalRulerView as? NoteLineNumberRuler)?.noteTextDidChange()
        }
        if let focusRequest, context.coordinator.lastFocusRequest != focusRequest {
            context.coordinator.lastFocusRequest = focusRequest
            DispatchQueue.main.async { editor.window?.makeFirstResponder(editor) }
        }
    }
    @MainActor final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: MarkdownTextView
        var lastFocusRequest: Int?
        init(_ parent: MarkdownTextView) { self.parent = parent }
        func textDidChange(_ notification: Notification) {
            guard let editor = notification.object as? NSTextView else { return }
            parent.text = editor.string
            if !editor.hasMarkedText() { highlight(editor) }
            updateStatus(editor)
            (editor.enclosingScrollView?.verticalRulerView as? NoteLineNumberRuler)?.noteTextDidChange()
        }
        func textViewDidChangeSelection(_ notification: Notification) {
            guard let editor = notification.object as? NSTextView else { return }
            updateStatus(editor)
        }
        func updateStatus(_ editor: NSTextView) {
            let value = NoteEditorStatus(source: editor.string, caretUTF16Offset: editor.selectedRange().location)
            if parent.status.value != value { parent.status.value = value }
        }
        func highlight(_ editor: NSTextView) {
            guard let storage = editor.textStorage else { return }
            let source = editor.string
            let range = NSRange(location: 0, length: (source as NSString).length)
            let parsed = MarkdownHighlight.parse(source)
            let selection = editor.selectedRanges
            let undo = editor.undoManager
            undo?.disableUndoRegistration()
            defer { undo?.enableUndoRegistration() }
            storage.beginEditing()
            let fontSize = parent.fontSize
            storage.setAttributes([.font: NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular), .foregroundColor: NSColor.labelColor], range: range)
            for span in parsed.spans where NSMaxRange(span.range) <= range.length {
                switch span.style {
                case .heading(let level):
                    storage.addAttribute(.foregroundColor, value: NSColor.systemOrange, range: span.range)
                    if level <= 2 { addTrait(.boldFontMask, to: span.range, storage: storage) }
                case .syntax: storage.addAttribute(.foregroundColor, value: NSColor.secondaryLabelColor, range: span.range)
                case .code: storage.addAttribute(.foregroundColor, value: NSColor.systemGreen, range: span.range)
                case .linkText: storage.addAttribute(.foregroundColor, value: NSColor.linkColor, range: span.range)
                case .linkURL: storage.addAttribute(.foregroundColor, value: NSColor.systemTeal, range: span.range)
                case .quote: storage.addAttribute(.foregroundColor, value: NSColor.secondaryLabelColor, range: span.range)
                case .bold: addTrait(.boldFontMask, to: span.range, storage: storage)
                case .italic: addTrait(.italicFontMask, to: span.range, storage: storage)
                case .strike: storage.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: span.range)
                }
            }
            for checkbox in parsed.checkboxes {
                storage.addAttribute(.foregroundColor, value: NSColor.clear, range: checkbox.range)
            }
            storage.endEditing()
            if editor.selectedRanges != selection { editor.selectedRanges = selection }
            editor.typingAttributes = [.font: NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular), .foregroundColor: NSColor.labelColor]
            if let noteEditor = editor as? NoteEditorTextView {
                noteEditor.markdownLinks = parsed.links
                noteEditor.markdownCheckboxes = parsed.checkboxes
            }
        }
        private func addTrait(_ trait: NSFontTraitMask, to range: NSRange, storage: NSTextStorage) {
            var changes: [(NSFont, NSRange)] = []
            storage.enumerateAttribute(.font, in: range) { value, part, _ in
                let font = (value as? NSFont) ?? .monospacedSystemFont(ofSize: parent.fontSize, weight: .regular)
                changes.append((NSFontManager.shared.convert(font, toHaveTrait: trait), part))
            }
            for (font, part) in changes { storage.addAttribute(.font, value: font, range: part) }
        }
    }
}

@MainActor private final class NoteEditorStatusModel: ObservableObject {
    @Published var value = NoteEditorStatus(source: "", caretUTF16Offset: 0)
}

private final class NoteLineNumberRuler: NSRulerView {
    var showsLineNumbers = true

    override init(scrollView: NSScrollView?, orientation: NSRulerView.Orientation) {
        super.init(scrollView: scrollView, orientation: orientation)
        ruleThickness = 42
    }

    required init(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func noteTextDidChange() {
        guard let editor = clientView as? NSTextView else { return }
        let lineCount = editor.string.reduce(1) { $0 + ($1.isNewline ? 1 : 0) }
        let digits = String(lineCount).count
        let scale = CGFloat((editor as? NoteEditorTextView)?.zoomPercent ?? 100) / 100
        ruleThickness = max(42, CGFloat(digits) * 8 * scale + 18)
        needsDisplay = true
    }

    override func drawHashMarksAndLabels(in rect: NSRect) {
        guard showsLineNumbers, let editor = clientView as? NSTextView,
              let manager = editor.layoutManager, let container = editor.textContainer else { return }
        let source = editor.string as NSString
        let origin = editor.textContainerOrigin
        let visible = editor.convert(bounds, from: self).offsetBy(dx: -origin.x, dy: -origin.y)
        let glyphs = manager.glyphRange(forBoundingRect: visible, in: container)
        let firstCharacter = manager.numberOfGlyphs > 0 && glyphs.location < manager.numberOfGlyphs
            ? manager.characterIndexForGlyph(at: glyphs.location) : 0
        var lineStart = 0
        var lineNumber = 1
        while lineStart < firstCharacter {
            var start = 0, end = 0, contentsEnd = 0
            source.getLineStart(&start, end: &end, contentsEnd: &contentsEnd,
                                for: NSRange(location: lineStart, length: 0))
            if end <= lineStart || contentsEnd == end { break }
            lineStart = end
            lineNumber += 1
        }
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 11 * CGFloat((editor as? NoteEditorTextView)?.zoomPercent ?? 100) / 100, weight: .regular),
            .foregroundColor: NSColor.secondaryLabelColor
        ]
        while lineStart <= source.length {
            let fragment: NSRect
            if lineStart == source.length {
                fragment = manager.extraLineFragmentRect
            } else {
                let glyph = manager.glyphIndexForCharacter(at: lineStart)
                fragment = manager.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
            }
            let editorRect = fragment.offsetBy(dx: origin.x, dy: origin.y)
            let rulerRect = convert(editorRect, from: editor)
            if rulerRect.intersects(rect) {
                let label = String(lineNumber) as NSString
                let size = label.size(withAttributes: attributes)
                label.draw(at: NSPoint(x: bounds.maxX - size.width - 9,
                                       y: rulerRect.minY + (rulerRect.height - size.height) / 2),
                           withAttributes: attributes)
            }
            if rulerRect.minY > rect.maxY && isFlipped { break }
            if lineStart == source.length { break }
            var start = 0, end = 0, contentsEnd = 0
            source.getLineStart(&start, end: &end, contentsEnd: &contentsEnd,
                                for: NSRange(location: lineStart, length: 0))
            if end <= lineStart || contentsEnd == end { break }
            lineStart = end
            lineNumber += 1
        }
    }
}

private final class NoteEditorTextView: NSTextView {
    var zoomPercent = 100
    var markdownLinks: [MarkdownHighlight.Link] = []
    var markdownCheckboxes: [MarkdownHighlight.Checkbox] = [] {
        didSet {
            needsDisplay = true
            window?.invalidateCursorRects(for: self)
        }
    }
    var indentWidth = 4
    override func resetCursorRects() {
        super.resetCursorRects()
        for checkbox in markdownCheckboxes {
            if let rect = checkboxRect(for: checkbox) { addCursorRect(rect, cursor: .pointingHand) }
        }
    }
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        for checkbox in markdownCheckboxes {
            guard let rect = checkboxRect(for: checkbox), rect.intersects(dirtyRect) else { continue }
            let scale = CGFloat(zoomPercent) / 100
            let size: CGFloat = 13 * scale
            let square = NSRect(x: rect.midX - size / 2, y: rect.midY - size / 2, width: size, height: size)
            let outline = NSBezierPath(roundedRect: square, xRadius: 3 * scale, yRadius: 3 * scale)
            (checkbox.checked ? NSColor.controlAccentColor : NSColor.secondaryLabelColor).setStroke()
            outline.lineWidth = 1.5 * scale
            if checkbox.checked {
                NSColor.controlAccentColor.setFill()
                outline.fill()
            }
            outline.stroke()
            if checkbox.checked {
                let check = NSBezierPath()
                let bottom = isFlipped ? square.maxY - 3 * scale : square.minY + 3 * scale
                let top = isFlipped ? square.minY + 3 * scale : square.maxY - 3 * scale
                check.move(to: NSPoint(x: square.minX + 3 * scale, y: square.midY))
                check.line(to: NSPoint(x: square.minX + 5.5 * scale, y: bottom))
                check.line(to: NSPoint(x: square.maxX - 2.5 * scale, y: top))
                check.lineWidth = 1.5 * scale
                check.lineCapStyle = .round
                check.lineJoinStyle = .round
                NSColor.selectedControlTextColor.setStroke()
                check.stroke()
            }
        }
    }
    private func checkboxRect(for checkbox: MarkdownHighlight.Checkbox) -> NSRect? {
        guard let manager = layoutManager, let container = textContainer,
              let storage = textStorage, NSMaxRange(checkbox.range) <= storage.length else { return nil }
        let glyphs = manager.glyphRange(forCharacterRange: checkbox.range, actualCharacterRange: nil)
        let rect = manager.boundingRect(forGlyphRange: glyphs, in: container)
        return rect.offsetBy(dx: textContainerOrigin.x, dy: textContainerOrigin.y)
    }
    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if !event.modifierFlags.contains(.command), event.clickCount == 1,
           let checkbox = markdownCheckboxes.first(where: { checkboxRect(for: $0)?.contains(point) == true }) {
            let valueRange = NSRange(location: checkbox.range.location + 1, length: 1)
            let replacement = checkbox.checked ? " " : "x"
            window?.makeFirstResponder(self)
            let selection = selectedRanges
            insertText(replacement, replacementRange: valueRange)
            if selectedRanges != selection { selectedRanges = selection }
            return
        }
        if event.modifierFlags.contains(.command), event.clickCount == 1,
           let manager = layoutManager, let container = textContainer, manager.numberOfGlyphs > 0 {
            let point = convert(event.locationInWindow, from: nil)
            let origin = textContainerOrigin
            let containerPoint = NSPoint(x: point.x - origin.x, y: point.y - origin.y)
            let glyph = manager.glyphIndex(for: containerPoint, in: container)
            guard glyph < manager.numberOfGlyphs else { super.mouseDown(with: event); return }
            let glyphBounds = manager.boundingRect(forGlyphRange: NSRange(location: glyph, length: 1), in: container)
            let index = manager.characterIndexForGlyph(at: glyph)
            if glyphBounds.contains(containerPoint),
               let link = markdownLinks.first(where: { NSLocationInRange(index, $0.range) }) {
                NSWorkspace.shared.open(link.url)
                return
            }
        }
        super.mouseDown(with: event)
    }
    override func insertTab(_ sender: Any?) {
        if selectedRange().length > 0 { changeLineIndents(outdent: false); return }
        insertText(String(repeating: " ", count: indentWidth), replacementRange: selectedRange())
    }
    override func insertBacktab(_ sender: Any?) {
        changeLineIndents(outdent: true)
    }
    private func changeLineIndents(outdent: Bool) {
        let source = string as NSString
        let selection = selectedRange()
        guard selection.location <= source.length else { return }
        let selectedEnd = selection.location + selection.length
        let lastSelected = selection.length > 0 ? max(selection.location, selectedEnd - 1) : selection.location
        let fullRange = source.lineRange(for: NSRange(location: selection.location, length: lastSelected - selection.location))
        let original = source.substring(with: fullRange)
        let lines = original.components(separatedBy: "\n")
        var firstChange = 0
        var totalChange = 0
        let replacement = lines.enumerated().map { index, line -> String in
            if index == lines.count - 1 && line.isEmpty { return line }
            let changed: String
            if outdent {
                let count = line.hasPrefix("\t") ? 1 : line.prefix(indentWidth).prefix(while: { $0 == " " }).count
                changed = String(line.dropFirst(count))
            } else {
                changed = String(repeating: " ", count: indentWidth) + line
            }
            let difference = (changed as NSString).length - (line as NSString).length
            if index == 0 { firstChange = difference }
            totalChange += difference
            return changed
        }.joined(separator: "\n")
        guard replacement != original, shouldChangeText(in: fullRange, replacementString: replacement) else { return }
        textStorage?.replaceCharacters(in: fullRange, with: replacement)
        didChangeText()
        if selection.length == 0 {
            setSelectedRange(NSRange(location: max(fullRange.location, selection.location + firstChange), length: 0))
        } else {
            let start = max(fullRange.location, selection.location + firstChange)
            let end = max(start, selectedEnd + totalChange)
            setSelectedRange(NSRange(location: start, length: end - start))
        }
    }
}
