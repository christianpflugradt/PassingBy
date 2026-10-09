import AppKit
import SwiftUI
import PassingByCore

/// Native controls that remain in the key loop even when macOS limits Tab to text inputs.
struct KeyboardButton: NSViewRepresentable {
    var title: String = ""
    var symbol: String? = nil
    var pointSize: CGFloat = 13
    var bold = false
    var dashboardOrder: Int? = nil
    var todoOrder: Int? = nil
    var keyLoopID: String? = nil
    var checked: Bool? = nil
    var bordered = false
    var advancesFocus = false
    var completionConfirmation: TodoCompletionConfirmation = .off
    var taskTitle: String? = nil
    var accessibilityLabel: String
    var action: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(action) }
    func makeNSView(context: Context) -> KeyboardActionButton {
        let button = KeyboardActionButton(title: title, target: context.coordinator, action: #selector(Coordinator.activate(_:)))
        button.setButtonType(checked == nil ? .momentaryPushIn : .switch)
        button.isBordered = bordered
        button.bezelStyle = .rounded
        button.setContentHuggingPriority(.required, for: .horizontal)
        return button
    }
    static func dismantleNSView(_ button: KeyboardActionButton, coordinator: Coordinator) {
        coordinator.cancelConfirmation()
    }
    func updateNSView(_ button: KeyboardActionButton, context: Context) {
        context.coordinator.action = action
        context.coordinator.completionConfirmation = completionConfirmation
        context.coordinator.taskTitle = taskTitle
        button.title = title
        if let checked { button.state = checked ? .on : .off }
        button.identifier = keyLoopID.map { NSUserInterfaceItemIdentifier($0) } ?? todoOrder.map { NSUserInterfaceItemIdentifier("todos-\($0)") } ?? dashboardOrder.map { NSUserInterfaceItemIdentifier("dashboard-\($0)") }
        button.advancesFocus = advancesFocus
        button.font = .systemFont(ofSize: pointSize, weight: bold ? .semibold : .regular)
        if checked != nil {
            button.attributedTitle = NSAttributedString(string: title, attributes: [.font: button.font!, .foregroundColor: NSColor.secondaryLabelColor])
        }
        if checked == nil {
            button.image = symbol.flatMap { NSImage(systemSymbolName: $0, accessibilityDescription: nil) }?.withSymbolConfiguration(.init(pointSize: pointSize, weight: .regular))
            button.imagePosition = symbol == nil ? .noImage : .imageOnly
        }
        button.contentTintColor = symbol == nil ? .labelColor : .secondaryLabelColor
        button.setAccessibilityLabel(accessibilityLabel)
    }
    @MainActor final class Coordinator: NSObject {
        var action: () -> Void
        init(_ action: @escaping () -> Void) { self.action = action }
        var completionConfirmation: TodoCompletionConfirmation = .off
        var taskTitle: String?
        private weak var confirmationAlert: NSAlert?
        private var isActive = true
        func cancelConfirmation() {
            isActive = false
            if let alert = confirmationAlert, let window = alert.window.sheetParent {
                window.endSheet(alert.window, returnCode: .alertSecondButtonReturn)
            }
            confirmationAlert = nil
        }
        @objc func activate(_ sender: KeyboardActionButton) {
            let next = sender.advancesFocus && sender.window?.firstResponder === sender ? sender.focusAfterActivation : nil
            guard let taskTitle, completionConfirmation.requiresConfirmation(isKeyboard: sender.isKeyboardActivation), let window = sender.window else {
                performAction(focusing: next)
                return
            }
            guard window.attachedSheet == nil else { return }
            let alert = NSAlert()
            alert.messageText = "Complete this To-do?"
            alert.informativeText = taskTitle.isEmpty ? "New To-do" : taskTitle
            alert.addButton(withTitle: "Complete")
            alert.addButton(withTitle: "Cancel")
            confirmationAlert = alert
            alert.beginSheetModal(for: window) { [self, weak sender, weak next] response in
                confirmationAlert = nil
                guard isActive else { return }
                if response == .alertFirstButtonReturn {
                    performAction(focusing: next)
                } else if let sender {
                    DispatchQueue.main.async { [weak sender] in
                        guard let sender, let window = sender.window else { return }
                        window.makeFirstResponder(sender)
                    }
                }
            }
        }
        private func performAction(focusing next: NSView?) {
            action()
            if let next {
                DispatchQueue.main.async { [weak next] in
                    guard let next, let window = next.window else { return }
                    next.scrollToVisible(next.bounds.insetBy(dx: 0, dy: -16))
                    window.makeFirstResponder(next)
                }
            }
        }
    }
}

@MainActor final class KeyboardActionButton: NSButton {
    weak var orderedNext: NSView?
    weak var orderedPrevious: NSView?
    weak var focusAfterActivation: NSView?
    var advancesFocus = false
    var onFocus: ((NSView) -> Void)?
    override func becomeFirstResponder() -> Bool {
        let accepted = super.becomeFirstResponder()
        if accepted { onFocus?(self) }
        return accepted
    }
    private(set) var isKeyboardActivation = false
    override var acceptsFirstResponder: Bool { true }
    override var needsPanelToBecomeKey: Bool { true }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 48, let target = event.modifierFlags.contains(.shift) ? orderedPrevious : orderedNext {
            focusKeyboardControl(target)
        } else if event.charactersIgnoringModifiers == "\r" || event.charactersIgnoringModifiers == " " {
            guard !event.isARepeat else { return }
            isKeyboardActivation = true
            defer { isKeyboardActivation = false }
            performClick(nil)
        } else { super.keyDown(with: event) }
    }
}

@MainActor func focusKeyboardControl(_ view: NSView) {
    // Entering the document must not scroll away from the user's caret or selection.
    if !(view is NSTextView) { view.scrollToVisible(view.bounds.insetBy(dx: 0, dy: -16)) }
    view.window?.makeFirstResponder(view)
}

struct KeyboardNoteTitle: NSViewRepresentable {
    @Binding var title: String
    var pointSize: CGFloat
    var focusRequest: Int?
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField(string: title)
        field.isBordered = false
        field.drawsBackground = false
        field.identifier = NSUserInterfaceItemIdentifier("note-title")
        field.setAccessibilityLabel("Note title")
        field.delegate = context.coordinator
        return field
    }
    func updateNSView(_ field: NSTextField, context: Context) {
        context.coordinator.parent = self
        field.font = .systemFont(ofSize: pointSize, weight: .semibold)
        if field.stringValue != title { field.stringValue = title }
        if let focusRequest, context.coordinator.lastFocusRequest != focusRequest {
            context.coordinator.lastFocusRequest = focusRequest
            DispatchQueue.main.async { [weak field] in
                guard let field else { return }
                field.window?.makeFirstResponder(field)
            }
        }
    }
    @MainActor final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: KeyboardNoteTitle
        var lastFocusRequest: Int?
        init(_ parent: KeyboardNoteTitle) { self.parent = parent }
        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            parent.title = field.stringValue
        }
        func control(_ control: NSControl, textView: NSTextView, doCommandBy command: Selector) -> Bool {
            let target: NSView?
            if command == #selector(NSResponder.insertTab(_:)) { target = control.nextKeyView }
            else if command == #selector(NSResponder.insertBacktab(_:)) { target = control.previousKeyView }
            else { return false }
            guard let target else { return false }
            focusKeyboardControl(target)
            return true
        }
    }
}

struct KeyboardNoteCategory: NSViewRepresentable {
    let labels: [PassingByCore.Label]
    @Binding var categoryID: UUID?
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> NSPopUpButton {
        let picker = KeyboardCategoryMenu()
        picker.identifier = NSUserInterfaceItemIdentifier("note-category")
        picker.setAccessibilityLabel("Note category")
        picker.target = context.coordinator
        picker.action = #selector(Coordinator.changed(_:))
        return picker
    }
    func updateNSView(_ picker: NSPopUpButton, context: Context) {
        context.coordinator.parent = self
        let titles = ["Uncategorized"] + labels.map(\.name)
        if context.coordinator.titles != titles {
            picker.removeAllItems()
            picker.addItems(withTitles: titles)
            context.coordinator.titles = titles
        }
        picker.selectItem(at: labels.firstIndex { $0.id == categoryID }.map { $0 + 1 } ?? 0)
    }
    @MainActor final class Coordinator: NSObject {
        var parent: KeyboardNoteCategory
        var titles: [String] = []
        init(_ parent: KeyboardNoteCategory) { self.parent = parent }
        @objc func changed(_ picker: NSPopUpButton) {
            let index = picker.indexOfSelectedItem - 1
            parent.categoryID = parent.labels.indices.contains(index) ? parent.labels[index].id : nil
        }
    }
}

struct KeyboardCategoryFilter: NSViewRepresentable {
    let labels: [PassingByCore.Label]
    @Binding var selection: LabelContext
    var scope = "dashboard"

    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> NSView {
        let control: NSControl
        if (1...4).contains(labels.count) {
            let segments = KeyboardSegments()
            segments.trackingMode = .selectOne
            control = segments
        } else {
            control = KeyboardCategoryMenu()
        }
        control.target = context.coordinator
        control.action = #selector(Coordinator.changed(_:))
        control.identifier = NSUserInterfaceItemIdentifier("global-category-filter")
        control.setAccessibilityLabel("Category")
        control.toolTip = "Filter by category · ⌥⌘F"
        control.setContentHuggingPriority(.required, for: .horizontal)
        return control
    }
    func updateNSView(_ view: NSView, context: Context) {
        context.coordinator.parent = self
        let titles = ["All"] + labels.map(\.name)
        let index: Int
        if case .label(let id) = selection { index = labels.firstIndex(where: { $0.id == id }).map { $0 + 1 } ?? 0 }
        else { index = 0 }
        if let segments = view as? NSSegmentedControl {
            if context.coordinator.titles != titles {
                segments.segmentCount = titles.count
                for (index, title) in titles.enumerated() { segments.setLabel(title, forSegment: index) }
            }
            segments.selectedSegment = index
        } else if let menu = view as? NSPopUpButton {
            if context.coordinator.titles != titles {
                menu.removeAllItems()
                menu.addItems(withTitles: titles)
            }
            menu.selectItem(at: index)
        }
        context.coordinator.titles = titles
    }
    @MainActor final class Coordinator: NSObject {
        var parent: KeyboardCategoryFilter
        var titles: [String] = []
        init(_ parent: KeyboardCategoryFilter) { self.parent = parent }
        @objc func changed(_ sender: NSControl) {
            let index = (sender as? NSSegmentedControl)?.selectedSegment ?? (sender as? NSPopUpButton)?.indexOfSelectedItem ?? 0
            parent.selection = index > 0 && parent.labels.indices.contains(index - 1) ? .label(parent.labels[index - 1].id) : .all
        }
    }
}

struct KeyboardAppointmentDisplay: NSViewRepresentable {
    @Binding var selection: DateDisplayMode
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> NSSegmentedControl {
        let control = KeyboardSegments()
        control.segmentCount = 2
        control.setLabel("Chronological", forSegment: 0)
        control.setLabel("By Category", forSegment: 1)
        control.trackingMode = .selectOne
        control.identifier = NSUserInterfaceItemIdentifier("appointments-2")
        control.setAccessibilityLabel("Appointment display mode")
        control.target = context.coordinator
        control.action = #selector(Coordinator.changed(_:))
        return control
    }
    func updateNSView(_ control: NSSegmentedControl, context: Context) {
        context.coordinator.parent = self
        control.selectedSegment = selection == .chronological ? 0 : 1
    }
    @MainActor final class Coordinator: NSObject {
        var parent: KeyboardAppointmentDisplay
        init(_ parent: KeyboardAppointmentDisplay) { self.parent = parent }
        @objc func changed(_ sender: NSSegmentedControl) {
            parent.selection = sender.selectedSegment == 0 ? .chronological : .byLabel
        }
    }
}

@MainActor private final class KeyboardSegments: NSSegmentedControl {
    var onFocus: ((NSView) -> Void)?
    override func becomeFirstResponder() -> Bool {
        let accepted = super.becomeFirstResponder()
        if accepted { onFocus?(self) }
        return accepted
    }
    override var acceptsFirstResponder: Bool { true }
    override var needsPanelToBecomeKey: Bool { true }
    weak var orderedNext: NSView?
    weak var orderedPrevious: NSView?
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 48, let target = event.modifierFlags.contains(.shift) ? orderedPrevious : orderedNext {
            focusKeyboardControl(target)
            return
        }
        switch event.keyCode {
        case 123, 124: // Left and Right change the selection within this one Tab stop.
            selectedSegment = min(segmentCount - 1, max(0, selectedSegment + (event.keyCode == 123 ? -1 : 1)))
            sendAction(action, to: target)
        case 36, 49:
            sendAction(action, to: target)
        default: super.keyDown(with: event)
        }
    }
}

@MainActor private final class KeyboardCategoryMenu: NSPopUpButton {
    var onFocus: ((NSView) -> Void)?
    override func becomeFirstResponder() -> Bool {
        let accepted = super.becomeFirstResponder()
        if accepted { onFocus?(self) }
        return accepted
    }
    weak var orderedNext: NSView?
    weak var orderedPrevious: NSView?
    override var acceptsFirstResponder: Bool { true }
    override var needsPanelToBecomeKey: Bool { true }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 48, let target = event.modifierFlags.contains(.shift) ? orderedPrevious : orderedNext {
            focusKeyboardControl(target)
        } else { super.keyDown(with: event) }
    }
}

/// Each screen supplies a reading order without rebuilding its native controls.
struct ScreenKeyLoop: NSViewRepresentable {
    var scope = "dashboard"
    // Explicit inputs ensure SwiftUI refreshes this otherwise constant representable as rows change.
    var itemIDs: [UUID] = []
    var descriptionPresence: [Bool] = []
    var controlIDs: [String] = []
    var requestedFocusID: String? = nil
    var focusRequest = 0
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeNSView(context: Context) -> NSView { NSView() }
    func updateNSView(_ view: NSView, context: Context) {
        let coordinator = context.coordinator
        DispatchQueue.main.async { [weak view, coordinator] in
            guard let root = view?.window?.contentView else { return }
            let prefix = "\(scope)-"
            @MainActor func controls(in parent: NSView) -> [NSView] {
                var result: [NSView] = []
                if let id = parent.identifier?.rawValue, id.hasPrefix(prefix), controlIDs.isEmpty || controlIDs.contains(id) { result.append(parent) }
                for child in parent.subviews { result += controls(in: child) }
                return result
            }
            @MainActor func order(_ control: NSView) -> Int { controlIDs.isEmpty ? Int(control.identifier!.rawValue.dropFirst(prefix.count))! : controlIDs.firstIndex(of: control.identifier!.rawValue)! }
            let ordered = controls(in: root).sorted { order($0) < order($1) }
            guard !ordered.isEmpty else { return }
            let completions = ordered.filter { scope == "todos" && order($0) >= 10 && (order($0) - 10).isMultiple(of: 4) }
            for (index, control) in ordered.enumerated() {
                let next = ordered[(index + 1) % ordered.count]
                let previous = ordered[(index + ordered.count - 1) % ordered.count]
                control.nextKeyView = next
                if let button = control as? KeyboardActionButton {
                    button.orderedNext = next
                    button.orderedPrevious = previous
                    if scope == "todos" {
                        let rowStart = 10 + max(0, (order(control) - 10) / 4) * 4
                        button.focusAfterActivation = completions.first { order($0) > rowStart } ?? completions.last { order($0) < rowStart } ?? ordered.first { order($0) == 1 }
                        let isRow = order(control) >= 10
                        button.onFocus = { [weak coordinator, weak button] _ in
                            coordinator?.recordFocus(button, isRow: isRow, fallback: button?.focusAfterActivation)
                        }
                    } else if scope == "appointments" {
                        let edits = ordered.filter { $0.identifier?.rawValue.hasSuffix("-edit") == true }
                        let rowID = control.identifier!.rawValue.components(separatedBy: "-").dropLast().joined(separator: "-")
                        let rowEdit = edits.first { $0.identifier?.rawValue == rowID + "-edit" }
                        let rowOrder = rowEdit.map(order) ?? order(control)
                        button.focusAfterActivation = edits.first { order($0) > rowOrder } ?? edits.last { order($0) < rowOrder } ?? ordered.first { $0.identifier?.rawValue == "appointments-1" }
                        let isRow = control.identifier!.rawValue.hasSuffix("-edit") || control.identifier!.rawValue.hasSuffix("-delete") || control.identifier!.rawValue.hasSuffix("-description")
                        button.onFocus = { [weak coordinator, weak button] _ in
                            coordinator?.recordFocus(button, isRow: isRow, fallback: button?.focusAfterActivation)
                        }
                    } else if button.advancesFocus {
                        button.focusAfterActivation = ordered.dropFirst(index + 1).first { ($0 as? KeyboardActionButton)?.advancesFocus == true } ?? ordered.first { order($0) == 100 }
                    }
                } else if let segments = control as? KeyboardSegments {
                    segments.orderedNext = next
                    segments.orderedPrevious = previous
                    segments.onFocus = { [weak coordinator] view in coordinator?.recordFocus(view, isRow: false, fallback: nil) }
                } else if let menu = control as? KeyboardCategoryMenu {
                    menu.orderedNext = next
                    menu.orderedPrevious = previous
                    menu.onFocus = { [weak coordinator] view in coordinator?.recordFocus(view, isRow: false, fallback: nil) }
                }
            }
            if scope == "note", coordinator.noteID != itemIDs.first {
                coordinator.noteID = itemIDs.first
                coordinator.didSetInitialFocus = false
            }
            if (scope == "dashboard" || scope == "todos" || scope == "appointments" || scope == "note"), !coordinator.didSetInitialFocus {
                coordinator.didSetInitialFocus = true
                if root.window?.attachedSheet == nil { root.window?.makeFirstResponder(ordered.first) }
            }
            if let focused = coordinator.focused as? KeyboardActionButton, focused.window != nil {
                coordinator.fallback = focused.focusAfterActivation
            }
            if (scope == "appointments" || scope == "note-icons"), coordinator.lastFocusRequest != focusRequest, root.window?.attachedSheet == nil {
                if let target = ordered.first(where: { $0.identifier?.rawValue == requestedFocusID }) {
                    coordinator.lastFocusRequest = focusRequest
                    target.scrollToVisible(target.bounds.insetBy(dx: 0, dy: -16))
                    target.window?.makeFirstResponder(target)
                }
            }
            if (scope == "todos" || scope == "appointments"), root.window?.attachedSheet == nil, coordinator.rowWasFocused, coordinator.focused?.window == nil {
                let target = coordinator.fallback?.window != nil ? coordinator.fallback : ordered.first { $0.identifier?.rawValue == "\(scope)-1" }
                if let target {
                    target.scrollToVisible(target.bounds.insetBy(dx: 0, dy: -16))
                    target.window?.makeFirstResponder(target)
                }
            }
        }
    }

    @MainActor final class Coordinator {
        weak var focused: NSView?
        weak var fallback: NSView?
        var rowWasFocused = false
        var didSetInitialFocus = false
        var noteID: UUID?
        var lastFocusRequest = 0
        func recordFocus(_ view: NSView?, isRow: Bool, fallback: NSView?) {
            focused = view
            self.fallback = fallback
            rowWasFocused = isRow
        }
    }
}

/// Keeps region navigation separate from the main content's Tab loop.
@MainActor final class WorkspaceKeyboardNavigation: NSObject {
    weak var window: NSWindow?
    weak var contentAnchor: NSView?
    private weak var returnResponder: NSResponder?
    private var returnSelection: NSRange?
    private var chosenCategory: Int?

    private func views(in parent: NSView) -> [NSView] {
        [parent] + parent.subviews.flatMap { views(in: $0) }
    }
    private var sidebar: [NSView] {
        guard let root = window?.contentView else { return [] }
        return views(in: root).filter { $0.identifier?.rawValue.hasPrefix("sidebar-") == true }
    }
    private func captureFocus() -> (NSResponder?, NSRange?) {
        guard let window, let root = window.contentView else { return (nil, nil) }
        if let editor = window.firstResponder as? NSTextView, editor.isFieldEditor,
           let field = views(in: root).compactMap({ $0 as? NSTextField }).first(where: { $0.currentEditor() === editor }) {
            return (field, editor.selectedRange())
        }
        return (window.firstResponder, nil)
    }
    private func restoreFocus(_ responder: NSResponder?, selection: NSRange?) {
        guard let window else { return }
        if let view = responder as? NSView, view.window !== window { focusContent(); return }
        guard let responder, window.makeFirstResponder(responder) else { focusContent(); return }
        if let field = responder as? NSTextField, let selection,
           let editor = field.currentEditor() as? NSTextView { editor.setSelectedRange(selection) }
    }
    func focusSidebar(id: String) {
        guard let window, window.attachedSheet == nil,
              let target = sidebar.first(where: { $0.identifier?.rawValue == id }) else { return }
        if !sidebar.contains(where: { $0 === window.firstResponder }) {
            (returnResponder, returnSelection) = captureFocus()
        }
        focusKeyboardControl(target)
    }
    func handle(_ event: NSEvent) -> NSEvent? {
        guard event.window === window, window?.attachedSheet == nil,
              let index = sidebar.firstIndex(where: { $0 === window?.firstResponder }),
              event.modifierFlags.intersection([.command, .option, .control]).isEmpty else { return event }
        let entries = sidebar
        switch event.keyCode {
        case 125, 126, 48:
            let backwards = event.keyCode == 126 || (event.keyCode == 48 && event.modifierFlags.contains(.shift))
            focusKeyboardControl(entries[(index + (backwards ? entries.count - 1 : 1)) % entries.count])
            return nil
        case 53:
            restoreFocus(returnResponder, selection: returnSelection)
            return nil
        default: return event
        }
    }
    func focusContent() {
        DispatchQueue.main.async { [weak self] in
            guard let self, let window = self.window, window.attachedSheet == nil,
                  let root = window.contentView else { return }
            let all = self.views(in: root)
            let first = all.first { view in
                guard let id = view.identifier?.rawValue else { return false }
                return ["dashboard-10", "todos-1", "appointments-1", "note-title", "settings-010-todos"].contains(id)
            }
            if let first { focusKeyboardControl(first) }
            else { window.makeFirstResponder(self.contentAnchor) }
        }
    }
    func scrollContent(keyCode: UInt16) -> Bool {
        guard let root = window?.contentView,
              let scroll = views(in: root).compactMap({ $0 as? NSScrollView }).first(where: { scroll in
                  !views(in: scroll).contains { $0.identifier?.rawValue.hasPrefix("sidebar-") == true }
              }), let document = scroll.documentView else { return false }
        let clip = scroll.contentView
        let maximum = max(0, document.bounds.height - clip.bounds.height)
        let direction: CGFloat = document.isFlipped ? 1 : -1
        var point = clip.bounds.origin
        switch keyCode {
        case 125: point.y += 40 * direction
        case 126: point.y -= 40 * direction
        case 121: point.y += clip.bounds.height * direction
        case 116: point.y -= clip.bounds.height * direction
        case 115: point.y = document.isFlipped ? 0 : maximum
        case 119: point.y = document.isFlipped ? maximum : 0
        default: return false
        }
        point.y = min(maximum, max(0, point.y))
        clip.scroll(to: point)
        scroll.reflectScrolledClipView(clip)
        return true
    }
    func chooseCategory(labels: [PassingByCore.Label], selection: LabelContext, apply: (LabelContext) -> Void) {
        guard let window, window.attachedSheet == nil, let root = window.contentView else { return }
        let (previous, previousSelection) = captureFocus()
        let menu = NSMenu(title: "Category Filter")
        menu.autoenablesItems = false
        let selected: Int
        if case .label(let id) = selection { selected = labels.firstIndex { $0.id == id }.map { $0 + 1 } ?? 0 }
        else { selected = 0 }
        for (index, title) in (["All"] + labels.map(\.name)).enumerated() {
            let item = NSMenuItem(title: title, action: #selector(selectCategory(_:)), keyEquivalent: "")
            item.target = self
            item.tag = index
            item.state = index == selected ? .on : .off
            menu.addItem(item)
        }
        chosenCategory = nil
        // The contextual header is the anchor when present; Notes use the top of the content area.
        let anchor = views(in: root).first { $0.identifier?.rawValue == "global-category-filter" }
        let point = anchor.map { root.convert(NSPoint(x: 0, y: $0.bounds.maxY), from: $0) }
            ?? NSPoint(x: 90, y: root.isFlipped ? 30 : root.bounds.height - 30)
        menu.popUp(positioning: menu.item(at: selected), at: point, in: root)
        if let index = chosenCategory {
            apply(index > 0 ? .label(labels[index - 1].id) : .all)
        }
        DispatchQueue.main.async { [weak self, weak previous] in
            guard let self, self.window === window, window.attachedSheet == nil else { return }
            self.restoreFocus(previous, selection: previousSelection)
        }
    }
    @objc private func selectCategory(_ item: NSMenuItem) { chosenCategory = item.tag }
}

struct WorkspaceKeyboardBridge: NSViewRepresentable {
    let navigation: WorkspaceKeyboardNavigation
    let contextHelp: ContextHelpController
    var onHelp: () -> Void
    func makeCoordinator() -> Coordinator { Coordinator(navigation, contextHelp: contextHelp, onHelp: onHelp) }
    func makeNSView(context: Context) -> NSView {
        let view = ContentAnchor()
        view.navigation = navigation
        return view
    }
    func updateNSView(_ view: NSView, context: Context) {
        context.coordinator.onHelp = onHelp
        DispatchQueue.main.async { [weak view, navigation] in
            navigation.window = view?.window
            navigation.contentAnchor = view
            if let helpMenu = NSApp.mainMenu?.items.first(where: { $0.title == "Help" })?.submenu,
               NSApp.helpMenu !== helpMenu { NSApp.helpMenu = helpMenu }
        }
    }
    static func dismantleNSView(_ view: NSView, coordinator: Coordinator) {
        if let monitor = coordinator.monitor { NSEvent.removeMonitor(monitor) }
        coordinator.contextHelp.close(restoringFocus: false)
        coordinator.navigation.window = nil
    }
    @MainActor final class ContentAnchor: NSView {
        weak var navigation: WorkspaceKeyboardNavigation?
        override var acceptsFirstResponder: Bool { true }
        override func keyDown(with event: NSEvent) {
            if event.modifierFlags.intersection([.command, .option, .control]).isEmpty,
               navigation?.scrollContent(keyCode: event.keyCode) == true { return }
            super.keyDown(with: event)
        }
    }
    @MainActor final class Coordinator {
        let navigation: WorkspaceKeyboardNavigation
        let contextHelp: ContextHelpController
        var onHelp: () -> Void
        var monitor: Any?
        init(_ navigation: WorkspaceKeyboardNavigation, contextHelp: ContextHelpController, onHelp: @escaping () -> Void) {
            self.navigation = navigation
            self.contextHelp = contextHelp
            self.onHelp = onHelp
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self else { return event }
                if event.keyCode == 122, event.modifierFlags.intersection([.command, .option, .control, .shift]).isEmpty {
                    if !event.isARepeat { self.onHelp() }
                    return nil
                }
                guard let event = self.contextHelp.handle(event) else { return nil }
                return self.navigation.handle(event)
            }
        }
    }
}
