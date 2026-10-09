import AppKit
import SwiftUI
import PassingByCore

/// A stable native form with an explicit key loop, independent of system button tabbing preferences.
struct NativeItemEditor: NSViewRepresentable {
    @Binding var title: String
    @Binding var description: String
    let labels: [PassingByCore.Label]
    @Binding var categoryID: UUID?
    var date: Binding<Date>? = nil
    let onDone: () -> Void
    let onClose: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> ItemEditorForm {
        let form = ItemEditorForm(hasDate: date != nil)
        context.coordinator.form = form
        form.titleField.delegate = context.coordinator
        form.descriptionView.delegate = context.coordinator
        form.categoryPicker.target = context.coordinator
        form.categoryPicker.action = #selector(Coordinator.categoryChanged)
        form.datePicker.target = context.coordinator
        form.datePicker.action = #selector(Coordinator.dateChanged)
        form.doneButton.target = context.coordinator
        form.doneButton.action = #selector(Coordinator.done)
        form.onDone = { context.coordinator.done() }
        form.onClose = { context.coordinator.close() }
        updateNSView(form, context: context)
        return form
    }

    func updateNSView(_ form: ItemEditorForm, context: Context) {
        context.coordinator.parent = self
        // Do not replace text during ordinary typing: preserve selection and native Undo.
        if form.titleField.stringValue != title { form.titleField.stringValue = title }
        if form.descriptionView.string != description { form.descriptionView.string = description }
        if let date, form.datePicker.dateValue != date.wrappedValue { form.datePicker.dateValue = date.wrappedValue }
        if context.coordinator.labels != labels {
            context.coordinator.labels = labels
            form.categoryPicker.removeAllItems()
            form.categoryPicker.addItems(withTitles: ["Uncategorized"] + labels.map(\.name))
        }
        let index = labels.firstIndex(where: { $0.id == categoryID }).map { $0 + 1 } ?? 0
        if form.categoryPicker.indexOfSelectedItem != index { form.categoryPicker.selectItem(at: index) }
    }

    @MainActor final class Coordinator: NSObject, NSTextFieldDelegate, NSTextViewDelegate {
        var parent: NativeItemEditor
        weak var form: ItemEditorForm?
        var labels: [PassingByCore.Label]? = nil
        init(_ parent: NativeItemEditor) { self.parent = parent }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            parent.title = field.stringValue
        }
        func textDidChange(_ notification: Notification) {
            guard let text = notification.object as? NSTextView else { return }
            parent.description = text.string
        }
        func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            if selector == #selector(NSResponder.insertNewline(_:)) { done(); return true }
            if selector == #selector(NSResponder.cancelOperation(_:)) { close(); return true }
            return false
        }
        @objc func categoryChanged() {
            guard let form else { return }
            let index = form.categoryPicker.indexOfSelectedItem - 1
            parent.categoryID = parent.labels.indices.contains(index) ? parent.labels[index].id : nil
        }
        @objc func dateChanged() {
            guard let form else { return }
            parent.date?.wrappedValue = form.datePicker.dateValue
        }
        func close() {
            commitFields()
            parent.onClose()
        }
        @objc func done() {
            commitFields()
            parent.onDone()
        }
        private func commitFields() {
            // Commit the field editor before reading bindings, including a just-typed date component.
            form?.window?.makeFirstResponder(form?.doneButton)
            if let form {
                parent.title = form.titleField.stringValue
                parent.description = form.descriptionView.string
                parent.date?.wrappedValue = form.datePicker.dateValue
            }
        }
    }
}

@MainActor final class ItemEditorForm: NSView {
    let titleField = NSTextField(string: "")
    fileprivate let descriptionView = ItemDescriptionTextView()
    fileprivate let categoryPicker = ItemCategoryPopUpButton()
    let datePicker = NSDatePicker()
    fileprivate let doneButton = ItemDoneButton(title: "Done", target: nil, action: nil)
    var onDone: (() -> Void)?
    var onClose: (() -> Void)?
    private var focusedInitially = false
    private weak var previousResponder: NSResponder?
    private weak var presentingWindow: NSWindow?

    init(hasDate: Bool) {
        super.init(frame: .zero)
        titleField.setAccessibilityLabel("Title")
        descriptionView.setAccessibilityLabel("Description")
        categoryPicker.setAccessibilityLabel("Category")
        datePicker.setAccessibilityLabel("Date")
        datePicker.datePickerStyle = .textFieldAndStepper
        datePicker.datePickerElements = .yearMonthDay
        datePicker.datePickerMode = .single
        descriptionView.isRichText = false
        descriptionView.allowsUndo = true
        descriptionView.font = .systemFont(ofSize: NSFont.systemFontSize)
        descriptionView.isVerticallyResizable = true
        descriptionView.isHorizontallyResizable = false
        descriptionView.autoresizingMask = [.width]
        descriptionView.textContainer?.widthTracksTextView = true
        descriptionView.textContainerInset = NSSize(width: 5, height: 5)
        let scroll = NSScrollView()
        scroll.borderType = .bezelBorder
        scroll.hasVerticalScroller = true
        scroll.documentView = descriptionView
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.heightAnchor.constraint(equalToConstant: 104).isActive = true
        titleField.translatesAutoresizingMaskIntoConstraints = false
        titleField.widthAnchor.constraint(greaterThanOrEqualToConstant: 260).isActive = true

        var rows: [[NSView]] = [[NSTextField(labelWithString: "Title"), titleField]]
        if hasDate { rows.append([NSTextField(labelWithString: "Date"), datePicker]) }
        rows.append([NSTextField(labelWithString: "Description"), scroll])
        rows.append([NSTextField(labelWithString: "Category"), categoryPicker])
        let grid = NSGridView(views: rows)
        grid.rowSpacing = 16
        grid.columnSpacing = 16
        grid.column(at: 0).xPlacement = .leading
        grid.column(at: 1).xPlacement = .fill
        for index in rows.indices { grid.cell(atColumnIndex: 0, rowIndex: index).yPlacement = .top }
        grid.translatesAutoresizingMaskIntoConstraints = false
        doneButton.translatesAutoresizingMaskIntoConstraints = false
        doneButton.bezelStyle = .rounded
        addSubview(grid)
        addSubview(doneButton)
        NSLayoutConstraint.activate([
            grid.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 24),
            grid.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -24),
            grid.topAnchor.constraint(equalTo: topAnchor, constant: 24),
            doneButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -24),
            doneButton.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -16)
        ])
        titleField.nextKeyView = hasDate ? datePicker : descriptionView
        if hasDate { datePicker.nextKeyView = descriptionView }
        descriptionView.nextKeyView = categoryPicker
        categoryPicker.nextKeyView = doneButton
        doneButton.nextKeyView = titleField
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let window, !focusedInitially else { return }
        focusedInitially = true
        presentingWindow = window.sheetParent
        previousResponder = presentingWindow?.firstResponder
        // SwiftUI attaches the sheet before establishing its initial responder.
        DispatchQueue.main.async { [weak self, weak window] in
            guard let self, let window, self.window === window else { return }
            window.autorecalculatesKeyViewLoop = false
            window.initialFirstResponder = self.titleField
            window.makeFirstResponder(self.titleField)
            self.titleField.selectText(nil)
        }
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow == nil, let presentingWindow, let previousResponder {
            DispatchQueue.main.async { [weak presentingWindow, weak previousResponder] in
                guard let presentingWindow, presentingWindow.attachedSheet == nil else { return }
                presentingWindow.makeFirstResponder(previousResponder)
            }
        }
        super.viewWillMove(toWindow: newWindow)
    }

    override func cancelOperation(_ sender: Any?) { onClose?() }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.charactersIgnoringModifiers == "\r", event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command {
            onDone?()
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
}

@MainActor private final class ItemDescriptionTextView: NSTextView {
    override func insertTab(_ sender: Any?) { window?.selectNextKeyView(self) }
    override func insertBacktab(_ sender: Any?) { window?.selectPreviousKeyView(self) }
}

@MainActor private final class ItemCategoryPopUpButton: NSPopUpButton {
    override var acceptsFirstResponder: Bool { true }
    override var needsPanelToBecomeKey: Bool { true }
}

@MainActor private final class ItemDoneButton: NSButton {
    override var acceptsFirstResponder: Bool { true }
    override var needsPanelToBecomeKey: Bool { true }
    override func keyDown(with event: NSEvent) {
        if event.charactersIgnoringModifiers == "\r" { performClick(nil) }
        else { super.keyDown(with: event) }
    }
}
