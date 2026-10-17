import AppKit
import SwiftUI
import PassingByCore

/// Compiled with the production Settings controls by test-settings-navigation.sh.
@main struct SettingsNavigationTests {
    @MainActor static func main() {
        let app = NSApplication.shared
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
        let hosting = NSHostingView(rootView: SettingsView(state: state))
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
        state.flush()
        print("Settings navigation tests passed")
    }
}
