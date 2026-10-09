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
            target.scrollToVisible(target.bounds.insetBy(dx: 0, dy: -16))
            window?.makeFirstResponder(target)
        } else if event.charactersIgnoringModifiers == "\r" || event.charactersIgnoringModifiers == " " {
            guard !event.isARepeat else { return }
            isKeyboardActivation = true
            defer { isKeyboardActivation = false }
            performClick(nil)
        } else { super.keyDown(with: event) }
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
        control.identifier = NSUserInterfaceItemIdentifier("\(scope)-0")
        control.setAccessibilityLabel("Category")
        control.toolTip = "Filter by category"
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
            target.scrollToVisible(target.bounds.insetBy(dx: 0, dy: -16))
            window?.makeFirstResponder(target)
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
            target.scrollToVisible(target.bounds.insetBy(dx: 0, dy: -16))
            window?.makeFirstResponder(target)
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
            if (scope == "todos" || scope == "appointments"), !coordinator.didSetInitialFocus {
                coordinator.didSetInitialFocus = true
                if root.window?.attachedSheet == nil { root.window?.makeFirstResponder(ordered.first) }
            }
            if let focused = coordinator.focused as? KeyboardActionButton, focused.window != nil {
                coordinator.fallback = focused.focusAfterActivation
            }
            if scope == "appointments", coordinator.lastFocusRequest != focusRequest, root.window?.attachedSheet == nil {
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
        var lastFocusRequest = 0
        func recordFocus(_ view: NSView?, isRow: Bool, fallback: NSView?) {
            focused = view
            self.fallback = fallback
            rowWasFocused = isRow
        }
    }
}
