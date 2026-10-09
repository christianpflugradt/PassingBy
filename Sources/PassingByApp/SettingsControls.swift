import AppKit
import SwiftUI
import PassingByCore

private struct SettingsPointSizeKey: EnvironmentKey { static let defaultValue: CGFloat = 13 }
extension EnvironmentValues {
    var settingsPointSize: CGFloat {
        get { self[SettingsPointSizeKey.self] }
        set { self[SettingsPointSizeKey.self] = newValue }
    }
}

@MainActor final class SettingsFocus: ObservableObject {
    @Published var request = 0
    var requestedID: String?
    func focus(_ id: String) { requestedID = id; request += 1 }
}

/// Settings has a single explicit reading order. Native controls keep their identity as values change.
struct SettingsKeyLoop: NSViewRepresentable {
    var request = 0
    var requestedID: String? = nil
    var settings: AppSettings? = nil
    var categoryID: UUID? = nil
    var scheduleIDs: [UUID] = []
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeNSView(context: Context) -> NSView { NSView() }
    func updateNSView(_ view: NSView, context: Context) {
        context.coordinator.anchor = view
        let request = request
        let id = requestedID
        DispatchQueue.main.async { [weak coordinator = context.coordinator] in
            coordinator?.refresh(request: request, id: id)
        }
    }
    static func dismantleNSView(_ view: NSView, coordinator: Coordinator) {
        if let monitor = coordinator.monitor { NSEvent.removeMonitor(monitor) }
    }
    @MainActor final class Coordinator {
        weak var anchor: NSView?
        weak var focused: NSView?
        var focusedID: String?
        var lastRequest = 0
        var monitor: Any?
        init() {
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .leftMouseUp]) { [weak self] event in
                guard let self else { return event }
                return self.handle(event)
            }
        }
        var controls: [NSView] {
            guard let root = anchor?.window?.contentView else { return [] }
            func collect(_ view: NSView) -> [NSView] {
                if view.identifier?.rawValue.hasPrefix("settings-") == true {
                    guard !view.isHiddenOrHasHiddenAncestor, (view as? NSControl)?.isEnabled != false else { return [] }
                    return [view]
                }
                return view.subviews.flatMap(collect)
            }
            return collect(root).sorted { $0.identifier!.rawValue < $1.identifier!.rawValue }
        }
        func currentControl() -> NSView? {
            guard let responder = anchor?.window?.firstResponder else { return nil }
            return controls.first { control in
                if responder === control { return true }
                if let field = control as? NSControl, field.currentEditor() === responder { return true }
                if let view = responder as? NSView { return view.isDescendant(of: control) }
                return false
            }
        }
        func select(_ control: NSView) {
            control.scrollToVisible(control.bounds.insetBy(dx: 0, dy: -16))
            if control.window?.makeFirstResponder(control) == true {
                focused = control
                focusedID = control.identifier?.rawValue
            }
        }
        func refresh(request: Int, id: String?) {
            guard let window = anchor?.window, window.attachedSheet == nil else { return }
            if lastRequest != request, let target = controls.first(where: { $0.identifier?.rawValue == id }) {
                lastRequest = request
                select(target)
            } else if let current = currentControl() {
                focused = current; focusedID = current.identifier?.rawValue
            } else if let focusedID,
                      focused?.window == nil || window.firstResponder === focused || (focused as? NSControl)?.currentEditor() === window.firstResponder {
                if let id = (window.firstResponder as? NSView)?.identifier?.rawValue, id.hasPrefix("sidebar-") { return }
                // Prefer the preceding control when a conditional form or selected row disappears.
                if let target = controls.last(where: { $0.identifier!.rawValue < focusedID }) ?? controls.first { select(target) }
            }
        }
        func handle(_ event: NSEvent) -> NSEvent? {
            guard let window = anchor?.window, event.window === window,
                  window.attachedSheet == nil else { return event }
            if event.type == .leftMouseUp {
                DispatchQueue.main.async { [weak self] in self?.refresh(request: self?.lastRequest ?? 0, id: nil) }
                return event
            }
            guard event.keyCode == 48, event.modifierFlags.intersection([.command, .option, .control]).isEmpty else { return event }
            let ordered = controls
            guard !ordered.isEmpty else { return event }
            let backwards = event.modifierFlags.contains(.shift)
            if let current = currentControl(), let index = ordered.firstIndex(where: { $0 === current }) {
                select(ordered[(index + (backwards ? ordered.count - 1 : 1)) % ordered.count])
                return nil
            }
            // The workspace content anchor is the entry point after activating Settings in the sidebar.
            if window.firstResponder === anchor || (window.firstResponder as? NSView)?.identifier == nil {
                select(backwards ? ordered.last! : ordered.first!)
                return nil
            }
            return event
        }
    }
}

@MainActor final class SettingsNativeButton: NSButton {
    override var acceptsFirstResponder: Bool { true }
    override func keyDown(with event: NSEvent) {
        if event.charactersIgnoringModifiers == " " || event.charactersIgnoringModifiers == "\r" {
            if !event.isARepeat { performClick(nil) }
        } else { super.keyDown(with: event) }
    }
}

struct SettingsButton: NSViewRepresentable {
    @Environment(\.settingsPointSize) var pointSize
    var title: String
    var id: String
    var symbol: String? = nil
    var enabled = true
    var checked: Bool? = nil
    var isDefault = false
    var action: () -> Void
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeNSView(context: Context) -> SettingsNativeButton {
        let button: SettingsNativeButton
        if checked != nil {
            button = SettingsNativeButton(checkboxWithTitle: title, target: context.coordinator, action: #selector(Coordinator.activate))
        } else {
            button = SettingsNativeButton(title: title, target: context.coordinator, action: #selector(Coordinator.activate))
            button.bezelStyle = .rounded
            button.isBordered = symbol == nil
        }
        button.setContentHuggingPriority(.required, for: .horizontal)
        return button
    }
    func updateNSView(_ button: SettingsNativeButton, context: Context) {
        context.coordinator.action = action
        button.identifier = .init(id)
        button.font = .systemFont(ofSize: pointSize)
        button.title = symbol == nil ? title : ""
        button.setAccessibilityLabel(title)
        if checked == nil {
            button.image = symbol.flatMap { NSImage(systemSymbolName: $0, accessibilityDescription: title) }
            button.imagePosition = symbol == nil ? .noImage : .imageOnly
        }
        button.isEnabled = enabled
        button.keyEquivalent = isDefault ? "\r" : ""
        if let checked { button.state = checked ? .on : .off }
    }
    @MainActor final class Coordinator: NSObject {
        var action: () -> Void = {}
        @objc func activate() { action() }
    }
}

struct SettingsToggle: View {
    var title: String
    var id: String
    @Binding var value: Bool
    var body: some View {
        SettingsButton(title: title, id: id, checked: value) { value.toggle() }
    }
}

@MainActor final class SettingsNativePicker: NSPopUpButton {
    override var acceptsFirstResponder: Bool { true }
    override func keyDown(with event: NSEvent) {
        if event.charactersIgnoringModifiers == " " || event.charactersIgnoringModifiers == "\r" { performClick(nil) }
        else { super.keyDown(with: event) }
    }
}

@MainActor final class SettingsNativeStepper: NSStepper {
    override var acceptsFirstResponder: Bool { true }
    override func keyDown(with event: NSEvent) {
        if [123, 124, 125, 126].contains(event.keyCode) {
            let delta = (event.keyCode == 124 || event.keyCode == 126) ? increment : -increment
            doubleValue = min(maxValue, max(minValue, doubleValue + delta))
            sendAction(action, to: target)
        } else { super.keyDown(with: event) }
    }
}

@MainActor final class SettingsNativeTimePicker: NSDatePicker {
    override var acceptsFirstResponder: Bool { true }
}

struct SettingsPicker<Value: Hashable>: NSViewRepresentable {
    @Environment(\.settingsPointSize) var pointSize
    var title: String
    var id: String
    @Binding var value: Value
    var choices: [(Value, String)]
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> NSPopUpButton {
        let picker = SettingsNativePicker(frame: .zero, pullsDown: false)
        picker.target = context.coordinator
        picker.action = #selector(Coordinator.changed(_:))
        return picker
    }
    func updateNSView(_ picker: NSPopUpButton, context: Context) {
        context.coordinator.parent = self
        picker.identifier = .init(id)
        picker.font = .systemFont(ofSize: pointSize)
        picker.setAccessibilityLabel(title)
        let titles = choices.map(\.1)
        if picker.itemTitles != titles { picker.removeAllItems(); picker.addItems(withTitles: titles) }
        picker.selectItem(at: choices.firstIndex { $0.0 == value } ?? 0)
    }
    @MainActor final class Coordinator: NSObject {
        var parent: SettingsPicker
        init(_ parent: SettingsPicker) { self.parent = parent }
        @objc func changed(_ picker: NSPopUpButton) {
            guard parent.choices.indices.contains(picker.indexOfSelectedItem) else { return }
            parent.value = parent.choices[picker.indexOfSelectedItem].0
        }
    }
}

struct SettingsTextField: NSViewRepresentable {
    @Environment(\.settingsPointSize) var pointSize
    var title: String
    var id: String
    @Binding var text: String
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField(string: text)
        field.delegate = context.coordinator
        return field
    }
    func updateNSView(_ field: NSTextField, context: Context) {
        context.coordinator.parent = self
        field.identifier = .init(id)
        field.font = .systemFont(ofSize: pointSize)
        field.placeholderString = title
        field.setAccessibilityLabel(title)
        if field.stringValue != text { field.stringValue = text }
    }
    @MainActor final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: SettingsTextField
        init(_ parent: SettingsTextField) { self.parent = parent }
        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            parent.text = field.stringValue
        }
    }
}

/// One focus stop per numeric setting; arrow keys adjust the native stepper.
struct SettingsStepper: NSViewRepresentable {
    @Environment(\.settingsPointSize) var pointSize
    var title: String
    var id: String
    @Binding var value: Int
    var range: ClosedRange<Int>
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> NSStepper {
        let stepper = SettingsNativeStepper()
        stepper.target = context.coordinator
        stepper.action = #selector(Coordinator.changed(_:))
        stepper.valueWraps = false
        stepper.autorepeat = true
        return stepper
    }
    func updateNSView(_ stepper: NSStepper, context: Context) {
        context.coordinator.parent = self
        stepper.identifier = .init(id)
        stepper.font = .systemFont(ofSize: pointSize)
        stepper.setAccessibilityLabel(title)
        stepper.minValue = Double(range.lowerBound)
        stepper.maxValue = Double(range.upperBound)
        stepper.integerValue = value
    }
    @MainActor final class Coordinator: NSObject {
        var parent: SettingsStepper
        init(_ parent: SettingsStepper) { self.parent = parent }
        @objc func changed(_ stepper: NSStepper) { parent.value = stepper.integerValue }
    }
}

struct SettingsNumberField: NSViewRepresentable {
    @Environment(\.settingsPointSize) var pointSize
    var title: String
    var id: String
    @Binding var value: Int
    var range: ClosedRange<Int>
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField(string: String(value))
        field.delegate = context.coordinator
        return field
    }
    func updateNSView(_ field: NSTextField, context: Context) {
        context.coordinator.parent = self
        field.identifier = .init(id)
        field.font = .systemFont(ofSize: pointSize)
        field.setAccessibilityLabel(title)
        // Do not replace an unfinished numeric edit during another setting's update.
        if field.currentEditor() == nil { field.stringValue = String(value) }
    }
    @MainActor final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: SettingsNumberField
        init(_ parent: SettingsNumberField) { self.parent = parent }
        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField,
                  let number = Int(field.stringValue), parent.range.contains(number) else { return }
            parent.value = number
        }
        func controlTextDidEndEditing(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            field.stringValue = String(parent.value)
        }
    }
}

struct SettingsTimePicker: NSViewRepresentable {
    @Environment(\.settingsPointSize) var pointSize
    var title: String
    var id: String
    @Binding var date: Date
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> NSDatePicker {
        let picker = SettingsNativeTimePicker()
        picker.datePickerStyle = .textFieldAndStepper
        picker.datePickerElements = .hourMinute
        picker.target = context.coordinator
        picker.action = #selector(Coordinator.changed(_:))
        return picker
    }
    func updateNSView(_ picker: NSDatePicker, context: Context) {
        context.coordinator.parent = self
        picker.identifier = .init(id)
        picker.font = .systemFont(ofSize: pointSize)
        picker.setAccessibilityLabel(title)
        if picker.dateValue != date { picker.dateValue = date }
    }
    @MainActor final class Coordinator: NSObject {
        var parent: SettingsTimePicker
        init(_ parent: SettingsTimePicker) { self.parent = parent }
        @objc func changed(_ picker: NSDatePicker) { parent.date = picker.dateValue }
    }
}

struct SettingsCategoryList: NSViewRepresentable {
    @Environment(\.settingsPointSize) var pointSize
    var labels: [PassingByCore.Label]
    @Binding var selection: UUID?
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> NSScrollView {
        let table = NSTableView()
        table.identifier = .init("settings-100-list")
        table.setAccessibilityLabel("Categories")
        table.headerView = nil
        table.rowHeight = 26
        table.addTableColumn(NSTableColumn(identifier: .init("category")))
        table.delegate = context.coordinator
        table.dataSource = context.coordinator
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        scroll.documentView = table
        return scroll
    }
    func updateNSView(_ scroll: NSScrollView, context: Context) {
        let coordinator = context.coordinator
        let changed = coordinator.parent.labels != labels
        coordinator.parent = self
        guard let table = scroll.documentView as? NSTableView else { return }
        table.rowHeight = 26 * pointSize / 13
        coordinator.updating = true
        defer { coordinator.updating = false }
        if changed || table.numberOfRows != labels.count { table.reloadData() }
        let index = labels.firstIndex { $0.id == selection }
        if let index, table.selectedRow != index { table.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false) }
        else if index == nil { table.deselectAll(nil) }
    }
    @MainActor final class Coordinator: NSObject, NSTableViewDelegate, NSTableViewDataSource {
        var parent: SettingsCategoryList
        var updating = false
        init(_ parent: SettingsCategoryList) { self.parent = parent }
        func numberOfRows(in tableView: NSTableView) -> Int { parent.labels.count }
        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            let label = parent.labels[row]
            let field = NSTextField(labelWithString: "●  " + label.name)
            let colors: [LabelColor: NSColor] = [.blue: .systemBlue, .purple: .systemPurple, .pink: .systemPink, .red: .systemRed, .orange: .systemOrange, .yellow: .systemYellow, .green: .systemGreen, .gray: .systemGray]
            field.font = .systemFont(ofSize: parent.pointSize)
            let text = NSMutableAttributedString(string: field.stringValue, attributes: [.font: field.font!])
            text.addAttribute(.foregroundColor, value: colors[label.color] ?? .labelColor, range: NSRange(location: 0, length: 1))
            field.attributedStringValue = text
            return field
        }
        func tableViewSelectionDidChange(_ notification: Notification) {
            guard !updating, let table = notification.object as? NSTableView else { return }
            parent.selection = parent.labels.indices.contains(table.selectedRow) ? parent.labels[table.selectedRow].id : nil
        }
    }
}
