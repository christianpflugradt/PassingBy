import AppKit
import SwiftUI
import PassingByCore

@MainActor private final class SettingsTestApplication: NSApplication {
    override func reportException(_ exception: NSException) {
        fatalError("Native test exception: " + (exception.reason ?? exception.name.rawValue))
    }
}

@MainActor private struct SettingsSurfaceTestView: View {
    @ObservedObject var state: WorkspaceState
    var body: some View { SettingsSurface(state: state, visible: state.destination == .settings) }
}

/// Compiled with the production Settings controls by test-settings-navigation.sh.
@main struct SettingsNavigationTests {
    @MainActor static func main() {
        let app = SettingsTestApplication.shared
        app.setActivationPolicy(.regular)
        RunLoop.main.perform {
            MainActor.assumeIsolated {
                runTests()
                app.stop(nil)
            }
        }
        app.run()
    }
    @MainActor static func runTests() {
        runSmartSubstitutionNativeTests()
        let app = NSApplication.shared
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 640, height: 360), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        let root = NSView(frame: window.contentView!.bounds)
        window.contentView = root
        let anchor = NSView()
        root.addSubview(anchor)
        let loop = SettingsKeyLoop.Coordinator()
        loop.anchor = anchor
        defer {
            if let monitor = loop.monitor { NSEvent.removeMonitor(monitor) }
            window.orderOut(nil)
        }
        func check(_ condition: @autoclosure () -> Bool, _ message: String) {
            guard condition() else { fatalError(message) }
        }
        func add<T: NSView>(_ view: T, _ id: String) -> T {
            view.identifier = .init(id)
            view.frame = NSRect(x: 20, y: 20, width: 120, height: 28)
            root.addSubview(view)
            return view
        }
        let last = add(SettingsNativeButton(title: "Last", target: nil, action: nil), "settings-900-last")
        let field = add(NSTextField(string: "Keep this selection"), "settings-120-name")
        let first = add(SettingsNativeStepper(), "settings-010-first")
        first.minValue = 1; first.maxValue = 10; first.integerValue = 4
        let picker = add(SettingsNativePicker(frame: .zero, pullsDown: false), "settings-130-color")
        picker.addItems(withTitles: ["Blue", "Green"])
        let time = add(SettingsNativeTimePicker(), "settings-180-time")
        time.datePickerElements = .hourMinute
        let disabled = add(SettingsNativeButton(title: "Disabled", target: nil, action: nil), "settings-125-disabled")
        disabled.isEnabled = false
        let hidden = add(SettingsNativeButton(title: "Hidden", target: nil, action: nil), "settings-126-hidden")
        hidden.isHidden = true
        let sidebar = add(SettingsNativeButton(title: "Sidebar", target: nil, action: nil), "sidebar-settings")
        app.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        RunLoop.current.run(until: Date().addingTimeInterval(0.15))
        check(loop.controls.map { $0.identifier!.rawValue } == ["settings-010-first", "settings-120-name", "settings-130-color", "settings-180-time", "settings-900-last"], "Reading order excludes hidden, disabled, and sidebar controls")
        func tab(_ backwards: Bool = false, modifiers: NSEvent.ModifierFlags = []) -> NSEvent {
            NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: backwards ? modifiers.union(.shift) : modifiers, timestamp: 0, windowNumber: window.windowNumber, context: nil, characters: "\t", charactersIgnoringModifiers: "\t", isARepeat: false, keyCode: 48)!
        }
        for control in loop.controls {
            loop.select(control)
            check(loop.currentControl() === control, "Every native setting accepts focus without Full Keyboard Access")
        }
        loop.select(last)
        check(loop.handle(tab()) == nil && loop.currentControl() === first, "Forward traversal wraps")
        check(loop.handle(tab(true)) == nil && loop.currentControl() === last, "Reverse traversal wraps")
        loop.select(field)
        let editor = field.currentEditor() as! NSTextView
        editor.setSelectedRange(NSRange(location: 5, length: 4))
        loop.refresh(request: 0, id: nil)
        check(editor.selectedRange() == NSRange(location: 5, length: 4), "Routine refresh preserves field selection")
        check(loop.handle(tab()) == nil && loop.currentControl() === picker, "Tab leaves the native field editor")
        check(loop.handle(tab(true)) == nil && loop.currentControl() === field, "Shift-Tab enters text field")
        loop.select(sidebar)
        check(loop.handle(tab()) != nil && window.firstResponder === sidebar, "Settings does not intercept sidebar traversal")
        loop.select(first)
        check(loop.handle(tab(modifiers: .control)) != nil && loop.currentControl() === first, "Modified Tab is not intercepted")
        loop.refresh(request: 1, id: "settings-120-name")
        check(loop.currentControl() === field, "Explicit focus request enters new form field")
        field.removeFromSuperview()
        loop.refresh(request: 1, id: nil)
        check(loop.currentControl() === first, "Removing focused field restores nearby focus")
        loop.select(first)
        let up = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil, characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: 126)!
        first.keyDown(with: up)
        check(first.integerValue == 5, "Arrow keys adjust numeric settings")
        first.integerValue = 10; first.keyDown(with: up)
        check(first.integerValue == 10, "Stepper honors upper bound")
        let sheet = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 200, height: 100), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.beginSheet(sheet)
        check(loop.handle(tab()) != nil, "Parent focus loop yields to dialogs")
        window.endSheet(sheet)
        var minutes = 5
        let numeric = SettingsNumberField(title: "Minutes", id: "settings-620-minutes", value: Binding(get: { minutes }, set: { minutes = $0 }), range: 1...120)
        let delegate = SettingsNumberField.Coordinator(numeric)
        let input = NSTextField(string: "60")
        let notification = Notification(name: NSControl.textDidChangeNotification, object: input)
        delegate.controlTextDidChange(notification)
        check(minutes == 60, "Valid numeric edits persist immediately")
        for invalid in ["", "0", "121", "abc"] {
            input.stringValue = invalid
            delegate.controlTextDidChange(notification)
            check(minutes == 60, "Invalid or incomplete numeric edits preserve saved value")
        }
        delegate.controlTextDidEndEditing(notification)
        check(input.stringValue == "60", "Leaving invalid input restores valid saved value")
        // Exercise the actual SwiftUI screen and its dynamic native controls with isolated storage.
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try! FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try! AppStore(persistence: WorkspacePersistence(url: directory.appendingPathComponent("workspace.json")))
        let state = WorkspaceState(store)
        state.change { workspace in
            workspace.labels = [PassingByCore.Label(name: "Personal"), PassingByCore.Label(name: "Work", color: .green)]
            workspace.scheduledTodos = [ScheduledTodo(title: "Weekly review", categoryID: nil, recurrence: .weekly(interval: .everyWeek, weekday: .monday), startingOn: Date().addingTimeInterval(7 * 86_400))]
        }
        state.destination = .settings
        let hosting = NSHostingView(rootView: SettingsSurfaceTestView(state: state))
        window.setContentSize(NSSize(width: 780, height: 700))
        window.contentView = hosting
        func settle() {
            hosting.layoutSubtreeIfNeeded()
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
            hosting.layoutSubtreeIfNeeded()
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
        func control(_ id: String) -> NSView {
            guard let view = descendants(hosting).first(where: { $0.identifier?.rawValue == id }) else { fatalError("Missing control: " + id) }
            return view
        }
        func activate(_ id: String) {
            let button = control(id) as! NSButton
            window.makeFirstResponder(button)
            button.performClick(nil)
            settle()
        }
        func focused(_ id: String) -> Bool {
            let view = control(id)
            return window.firstResponder === view || (view as? NSControl)?.currentEditor() === window.firstResponder
        }
        settle()
        let sectionButtons = SettingsSection.allCases.map { control($0.navigationID) as! NSButton }
        check(sectionButtons.map(\.title) == SettingsSection.allCases.map(\.title), "Every top-level section has navigation in content order")
        let probes = descendants(hosting).compactMap { $0 as? SettingsAnchorView }
        check(probes.count == SettingsSection.allCases.count, "Content and navigation share the complete section list")
        let navigation = probes.first!.navigation!
        let contentScroll = probes.first!.enclosingScrollView!
        let document = contentScroll.documentView!
        func top(_ section: SettingsSection) -> CGFloat {
            let probe = probes.first { $0.identifier?.rawValue == "section-" + section.rawValue }!
            let frame = probe.convert(probe.bounds, to: document)
            return document.isFlipped ? frame.minY : document.bounds.height - frame.maxY
        }
        func scrollTop() -> CGFloat {
            document.isFlipped ? contentScroll.contentView.bounds.minY : document.bounds.height - contentScroll.contentView.bounds.maxY
        }
        func manuallyScroll(to offset: CGFloat) {
            let maximum = max(0, document.bounds.height - contentScroll.contentView.bounds.height)
            contentScroll.contentView.scroll(to: NSPoint(x: 0, y: document.isFlipped ? offset : maximum - offset))
            contentScroll.reflectScrolledClipView(contentScroll.contentView)
            settle()
        }
        for section in SettingsSection.allCases {
            activate(section.navigationID)
            check(navigation.active == section, "Section activation stays selected after scrolling: " + section.title)
            check(abs(scrollTop() - max(0, top(section) - 12)) < 2, "Navigation aligns the requested heading: " + section.title)
            check((control(section.navigationID) as! NSButton).accessibilityValue() as? String == "Current section", "Navigation exposes the active state to accessibility")
        }
        activate(SettingsSection.todos.navigationID)
        let focusedNavigation = window.firstResponder
        manuallyScroll(to: top(.appointments) + 10)
        check(navigation.active == .appointments, "Manual scrolling updates the active section")
        check(window.firstResponder === focusedNavigation, "Manual scrolling never steals keyboard focus")
        for delta: CGFloat in [-2, 1, -1, 2] {
            manuallyScroll(to: top(.appointments) - 20 + delta)
            check(navigation.active == .appointments, "Small boundary jitter does not flicker selection")
        }
        manuallyScroll(to: top(.appointments) - 30)
        check(navigation.active == .todos, "Scrolling clearly above a boundary selects the preceding section")
        let starts: [(SettingsSection, CGFloat)] = [(.dashboard, 0), (.todos, 100), (.appointments, 200)]
        check(SettingsNavigationState.section(at: 79, starts: starts, current: .dashboard) == .dashboard, "Reference line holds within the forward dead band")
        check(SettingsNavigationState.section(at: 85, starts: starts, current: .dashboard) == .todos, "Reference line advances outside the dead band")
        let suiteName = "PassingBy.SettingsTests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.set("data", forKey: "settings.section")
        check(SettingsNavigationState(defaults: defaults).active == .data, "Saved section restores by identity")
        defaults.set("removed-section", forKey: "settings.section")
        check(SettingsNavigationState(defaults: defaults).active == .dashboard, "Unknown saved sections fall back safely")
        defaults.removePersistentDomain(forName: suiteName)
        window.makeFirstResponder(sectionButtons[0])
        sectionButtons[0].keyDown(with: up)
        check(window.firstResponder === sectionButtons.last!, "Arrow keys move between local section entries")
        activate(SettingsSection.dashboard.navigationID)
        let categoryField = control("settings-120-name")
        let list = control("settings-100-list") as! NSTableView
        check(list.numberOfRows == 2, "Category list shows persisted Categories")
        window.makeFirstResponder(list)
        list.selectRowIndexes(IndexSet(integer: 1), byExtendingSelection: false)
        settle()
        check(state.labelID == state.workspace.labels[1].id, "Native category selection updates editor")
        check(control("settings-120-name") === categoryField, "Category selection retains native editor identity")
        activate("settings-110-add")
        check(state.workspace.labels.count == 3 && focused("settings-120-name"), "Adding Category focuses its name")
        activate("settings-140-delete")
        check(state.workspace.labels.count == 2 && focused("settings-100-list"), "Deleting Category returns focus to list")
        activate("settings-160-enabled")
        check(state.workspace.settings.scheduledDefaultEnabled, "Scheduled default enables inline controls")
        _ = control("settings-180-start")
        _ = control("settings-190-end")
        activate(SettingsSection.data.navigationID)
        check(navigation.active == .data && abs(scrollTop() - top(.data) + 12) < 2, "Expanded Category controls update section positions")
        activate("settings-360-add")
        check(focused("settings-360-title"), "Opening schedule form focuses title")
        check(!(control("settings-366-create") as! NSButton).isEnabled, "Incomplete schedule cannot be created")
        let kind = control("settings-362-kind") as! NSPopUpButton
        kind.selectItem(at: 1)
        kind.sendAction(kind.action, to: kind.target)
        settle()
        _ = control("settings-365-occurrence")
        check(!descendants(hosting).contains { $0.identifier?.rawValue == "settings-364-weekday" }, "Monthly form removes weekly fields")
        activate("settings-367-cancel")
        check(focused("settings-360-add"), "Cancel returns focus to Add Scheduled To-do")
        activate("settings-600-lock")
        activate("settings-610-inactive")
        _ = control("settings-620-minutes")
        let finalLoop = SettingsKeyLoop.Coordinator()
        finalLoop.anchor = control("settings-010-todos")
        defer { if let monitor = finalLoop.monitor { NSEvent.removeMonitor(monitor) } }
        for control in finalLoop.controls {
            finalLoop.select(control)
            check(finalLoop.currentControl() === control, "Every visible control on actual Settings is reachable")
        }
        let readingOrder = finalLoop.controls
        finalLoop.select(readingOrder.first!)
        for index in readingOrder.indices {
            check(finalLoop.handle(tab()) == nil && finalLoop.currentControl() === readingOrder[(index + 1) % readingOrder.count], "Full Settings traverses forward in reading order")
        }
        for index in readingOrder.indices {
            check(finalLoop.handle(tab(true)) == nil && finalLoop.currentControl() === readingOrder[(readingOrder.count - index - 1) % readingOrder.count], "Full Settings traverses backward in reading order")
        }
        if let monitor = finalLoop.monitor { NSEvent.removeMonitor(monitor); finalLoop.monitor = nil }
        finalLoop.select(control("settings-610-inactive"))
        check(finalLoop.handle(tab()) == nil && focused("settings-620-minutes"), "Tab enters inactivity minutes")
        state.change { $0.settings.lockWhenInactive = false }
        settle()
        finalLoop.refresh(request: 0, id: nil)
        check(focused("settings-610-inactive"), "Removing inactivity field preserves nearby focus")
        // Recovery uses isolated data and the real native sheet, including keyboard focus.
        let recoveryNote = Note(title: "Working notes", contentMarkdown: "# Research\n\n- [x] Preserve this Markdown\n\n```swift\nlet value = 42\n```", labelID: state.workspace.labels[0].id, iconName: "book")
        let recoveryTask = Task(title: "Completed task", taskDescription: "Keep completion state", completedAt: Date())
        let recoveryAppointment = DateItem(title: "Past meeting", date: Date().addingTimeInterval(-86_400), itemDescription: "Original details")
        state.change { workspace in
            workspace.notes.append(recoveryNote)
            workspace.tasks.append(recoveryTask)
            workspace.dates.append(recoveryAppointment)
            workspace.deleteTask(recoveryTask.id, at: Date().addingTimeInterval(-100))
            workspace.deleteAppointment(recoveryAppointment.id, at: Date().addingTimeInterval(-50))
            workspace.settings.labelContext = .label(workspace.labels[1].id)
        }
        state.change { $0.deleteNote(recoveryNote.id) }
        settle()
        check(state.workspace.notes.isEmpty && state.workspace.recentlyDeleted.count == 3, "Deletion preserves the complete Note for recovery")
        state.destination = .settings
        activate("settings-700-deleted")
        guard let recoverySheet = window.attachedSheet else { fatalError("Recently Deleted opens a native sheet") }
        func recoveryControl(_ id: String) -> NSView {
            guard let view = descendants(recoverySheet.contentView!).first(where: { $0.identifier?.rawValue == id }) else { fatalError("Missing recovery control: " + id) }
            return view
        }
        let recoveryList = recoveryControl("settings-010-deleted-list") as! NSTableView
        let preview = recoveryControl("settings-020-deleted-preview") as! NSTextView
        check(recoveryList.numberOfRows == 3 && recoverySheet.firstResponder === recoveryList, "Recovery ignores the global Category filter and initially focuses its list")
        check(preview.string == recoveryNote.contentMarkdown && !preview.isEditable && preview.isSelectable, "Newest deletion is selected with complete, selectable, read-only raw Markdown")
        recoveryList.selectRowIndexes(IndexSet(integer: 1), byExtendingSelection: false)
        settle()
        check(recoveryControl("settings-010-deleted-list") === recoveryList && recoveryControl("settings-020-deleted-preview") === preview, "Selection preserves native list and preview identity")
        check(preview.string == recoveryAppointment.itemDescription, "Selection updates the preview incrementally")
        recoveryList.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        settle()
        let recoveryLoop = SettingsKeyLoop.Coordinator()
        recoveryLoop.anchor = recoveryList
        for view in recoveryLoop.controls {
            recoveryLoop.select(view)
            check(recoveryLoop.currentControl() === view, "Every recovery control is keyboard reachable")
        }
        recoveryLoop.select(preview)
        preview.setSelectedRange(NSRange(location: 2, length: 8))
        recoveryLoop.refresh(request: 0, id: nil)
        check(preview.selectedRange() == NSRange(location: 2, length: 8), "Routine recovery refresh preserves preview text selection")
        if let monitor = recoveryLoop.monitor { NSEvent.removeMonitor(monitor); recoveryLoop.monitor = nil }
        if let destination = ProcessInfo.processInfo.environment["SETTINGS_TEST_SCREENSHOT_DIR"] {
            let output = URL(fileURLWithPath: destination)
            try! FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
            for (name, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
                window.appearance = NSAppearance(named: appearance)
                recoverySheet.appearance = NSAppearance(named: appearance)
                settle()
                let capture = Process()
                capture.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
                capture.arguments = ["-x", "-l", String(recoverySheet.windowNumber), output.appendingPathComponent("recently-deleted-" + name + ".png").path]
                try! capture.run()
                capture.waitUntilExit()
                check(capture.terminationStatus == 0, "Recovery screenshot succeeds")
            }
        }
        for _ in 0..<3 {
            (recoveryControl("settings-030-deleted-restore") as! NSButton).performClick(nil)
            settle()
        }
        check(state.workspace.recentlyDeleted.isEmpty && state.workspace.notes == [recoveryNote], "Restore returns full Note content without duplicates")
        check(state.workspace.tasks.last?.completedAt == recoveryTask.completedAt && state.workspace.dates.last?.date == recoveryAppointment.date, "Recovery preserves completion and passed dates through the actual save path")
        check(!(recoveryControl("settings-030-deleted-restore") as! NSButton).isEnabled && recoverySheet.firstResponder === recoveryControl("settings-040-deleted-done"), "Empty recovery disables Restore and moves focus to Done")
        (recoveryControl("settings-040-deleted-done") as! NSButton).performClick(nil)
        settle()
        check(window.attachedSheet == nil && focused("settings-700-deleted"), "Closing recovery restores focus to its Settings action")
        state.change { $0.deleteNote(recoveryNote.id) }
        activate("settings-700-deleted")
        let reopenedSheet = window.attachedSheet!
        let escape = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: reopenedSheet.windowNumber, context: nil, characters: "\u{1b}", charactersIgnoringModifiers: "\u{1b}", isARepeat: false, keyCode: 53)!
        app.sendEvent(escape)
        settle()
        check(window.attachedSheet == nil && focused("settings-700-deleted"), "Escape closes recovery and restores Settings focus")
        activate("settings-700-deleted")
        state.lockNow()
        settle()
        check(!state.showRecentlyDeleted && window.attachedSheet == nil, "App Lock dismisses recovery so private content cannot remain visible")
        if let destination = ProcessInfo.processInfo.environment["SETTINGS_TEST_SCREENSHOT_DIR"] {
            let output = URL(fileURLWithPath: destination)
            try! FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
            for (name, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
                window.appearance = NSAppearance(named: appearance)
                for (section, id) in [("top", "settings-010-todos"), ("middle", "settings-300-confirmation"), ("bottom", "settings-900-zoom")] {
                    let target = control(id)
                    if section != "middle", let scroll = target.enclosingScrollView, let document = scroll.documentView {
                        let maximum = max(0, document.bounds.height - scroll.contentView.bounds.height)
                        let y = (section == "top") == document.isFlipped ? 0 : maximum
                        scroll.contentView.scroll(to: NSPoint(x: 0, y: y))
                        scroll.reflectScrolledClipView(scroll.contentView)
                    } else { target.scrollToVisible(target.bounds) }
                    settle()
                    let capture = Process()
                    capture.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
                    capture.arguments = ["-x", "-l", String(window.windowNumber), output.appendingPathComponent("settings-" + name + "-" + section + ".png").path]
                    try! capture.run()
                    capture.waitUntilExit()
                    check(capture.terminationStatus == 0, "Window screenshot succeeds")
                }
            }
        }
        // Compact layouts keep the same native controls and make every control reachable.
        let preservedControl = control("settings-010-todos")
        for (width, zoom) in [(582.0, 100), (582.0, 180), (1060.0, 70)] {
            state.change { $0.settings.screenZoom["settings"] = zoom }
            window.setContentSize(NSSize(width: width, height: 410))
            settle()
            check(control("settings-010-todos") === preservedControl, "Resize and zoom preserve native control identity")
            for section in SettingsSection.allCases {
                activate(section.navigationID)
                check(navigation.active == section, "Navigation works at width \(width), zoom \(zoom), section \(section), active \(navigation.active), offset \(scrollTop()), heading \(top(section))")
            }
            if let directory = ProcessInfo.processInfo.environment["SETTINGS_TEST_SCREENSHOT_DIR"] {
                activate(SettingsSection.categories.navigationID)
                let capture = Process()
                capture.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
                capture.arguments = ["-x", "-l", String(window.windowNumber), directory + "/settings-width-" + String(Int(width)) + "-zoom-" + String(zoom) + ".png"]
                try! capture.run()
                capture.waitUntilExit()
                check(capture.terminationStatus == 0, "Compact layout screenshot succeeds")
            }
            for view in finalLoop.controls {
                finalLoop.select(view)
                check(finalLoop.currentControl() === view, "Narrow layouts retain all keyboard-accessible controls")
            }
        }
        state.change { $0.settings.screenZoom["settings"] = 100 }
        window.setContentSize(NSSize(width: 900, height: 700))
        state.labelID = state.workspace.labels.first!.id
        settle()
        activate(SettingsSection.categories.navigationID)
        let nameField = control("settings-120-name") as! NSTextField
        window.makeFirstResponder(nameField)
        let nameEditor = nameField.currentEditor() as! NSTextView
        nameEditor.undoManager?.removeAllActions()
        let originalName = nameField.stringValue
        nameEditor.insertText("X", replacementRange: NSRange(location: 0, length: 0))
        settle()
        check(nameEditor.undoManager?.canUndo == true, "Category typing creates native Undo history")
        nameEditor.setSelectedRange(NSRange(location: 1, length: 2))
        let savedScroll = scrollTop()
        let configurationBeforeNavigation = state.workspace.settings
        state.destination = .help
        settle()
        check(nameField.isHiddenOrHasHiddenAncestor, "Leaving Settings hides its native tree")
        check(finalLoop.controls.isEmpty, "Hidden Settings controls are excluded from keyboard traversal")
        state.destination = .settings
        settle()
        check(control("settings-120-name") === nameField, "Returning preserves the editor instance and Undo context")
        check(focused("settings-120-name") && (nameField.currentEditor() as! NSTextView).selectedRange() == NSRange(location: 1, length: 2), "Returning restores focus and text selection")
        check(abs(scrollTop() - savedScroll) < 2 && navigation.active == .categories, "Returning preserves scroll and active section")
        check(state.workspace.settings == configurationBeforeNavigation, "Navigation never changes saved configuration")
        let returnedEditor = nameField.currentEditor() as! NSTextView
        check(returnedEditor.undoManager?.canUndo == true, "Native Undo history survives Settings navigation")
        check(returnedEditor.tryToPerform(Selector(("undo:")), with: nil), "Native Undo command is available")
        settle()
        check(nameField.stringValue == originalName && state.label?.name == originalName, "Undo after returning restores and persists the Category name")
        check(returnedEditor.tryToPerform(Selector(("redo:")), with: nil), "Native Redo command is available")
        settle()
        check(nameField.stringValue == "X" + originalName && state.label?.name == "X" + originalName, "Redo after returning reapplies and persists the Category edit")
        let editedCategory = state.labelID!
        let otherCategory = state.workspace.labels.first { $0.id != editedCategory }!
        state.labelID = otherCategory.id
        settle()
        check(nameField.stringValue == otherCategory.name, "Category selection loads the correct editing session")
        state.labelID = editedCategory
        settle()
        window.makeFirstResponder(nameField)
        let originalEditor = nameField.currentEditor() as! NSTextView
        check(originalEditor.undoManager?.canUndo == true, "Each Category retains its own in-memory editing history")
        check(originalEditor.tryToPerform(Selector(("undo:")), with: nil), "Undo remains available in the original Category")
        settle()
        check(state.label?.name == originalName && state.workspace.labels.first { $0.id == otherCategory.id }?.name == otherCategory.name, "Undo stays bound to the edited Category: field=\(nameField.stringValue), model=\(state.label?.name ?? "nil"), original=\(originalName), other=\(state.workspace.labels.first { $0.id == otherCategory.id }?.name ?? "nil"), expectedOther=\(otherCategory.name)")
        activate(SettingsSection.todos.navigationID)
        let persistedOffset = scrollTop()
        state.flush()
        let reloadedState = WorkspaceState(try! AppStore(persistence: WorkspacePersistence(url: directory.appendingPathComponent("workspace.json"))))
        reloadedState.destination = .settings
        let replacementHost = NSHostingView(rootView: SettingsSurfaceTestView(state: reloadedState))
        window.contentView = replacementHost
        replacementHost.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.4))
        let restoredProbe = descendants(replacementHost).compactMap { $0 as? SettingsAnchorView }.first!
        let restoredScroll = restoredProbe.enclosingScrollView!
        let restoredDocument = restoredScroll.documentView!
        let restoredOffset = restoredDocument.isFlipped ? restoredScroll.contentView.bounds.minY : restoredDocument.bounds.height - restoredScroll.contentView.bounds.maxY
        check(abs(restoredOffset - persistedOffset) < 2 && restoredProbe.navigation!.active == .todos, "Reloading Settings restores persisted scroll and section")
        check(reloadedState.labelID == editedCategory, "Reloading restores the selected Category by identity")
        let freshField = descendants(replacementHost).first { $0.identifier?.rawValue == "settings-120-name" } as! NSTextField
        window.makeFirstResponder(freshField)
        check((freshField.currentEditor() as? NSTextView)?.undoManager?.canUndo != true, "Undo history is never persisted across restarts")
        state.flush()
        print("Settings navigation tests passed")
    }
}
