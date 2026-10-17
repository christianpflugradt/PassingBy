import AppKit
import SwiftUI
import PassingByCore

struct SubstitutionsView: View {
    @ObservedObject var state: WorkspaceState
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        SubstitutionsFormView(settings: state.workspace.settings.smartSubstitutions, onChange: { value in
            state.change { $0.settings.smartSubstitutions = value }
        }, onDone: { dismiss() })
        .frame(width: 680, height: 560)
    }
}

private struct SubstitutionsFormView: NSViewRepresentable {
    let settings: SmartSubstitutionSettings
    let onChange: (SmartSubstitutionSettings) -> Void
    let onDone: () -> Void
    func makeNSView(context: Context) -> SubstitutionsForm { SubstitutionsForm(settings: settings, onChange: onChange, onDone: onDone) }
    func updateNSView(_ view: SubstitutionsForm, context: Context) {
        view.onChange = onChange; view.onDone = onDone
        view.receive(settings)
    }
}

@MainActor final class SubstitutionsForm: NSView, NSTableViewDataSource, NSTableViewDelegate, NSTextFieldDelegate, NSTextViewDelegate {
    private var settings: SmartSubstitutionSettings
    var onChange: (SmartSubstitutionSettings) -> Void
    var onDone: () -> Void
    private let table = SubstitutionsTable()
    private let input = NSTextField(string: "")
    private let output = SubstitutionDraftOutput()
    private let automatic = SettingsNativeButton(checkboxWithTitle: "Automatic", target: nil, action: nil)
    private let message = NSTextField(wrappingLabelWithString: "")
    private let syntax = NSTextField(wrappingLabelWithString: "")
    private let add = SettingsNativeButton(title: "Add Custom Mapping", target: nil, action: nil)
    private let new = SettingsNativeButton(title: "New Custom Mapping", target: nil, action: nil)
    private let delete = SettingsNativeButton(title: "Delete Custom Mapping", target: nil, action: nil)
    private let done = SettingsNativeButton(title: "Done", target: nil, action: nil)
    private var editingCustom: Int?
    private var loading = false
    private var initialFocus = false
    private var rules: [SubstitutionRule] { settings.rules }

    init(settings: SmartSubstitutionSettings, onChange: @escaping (SmartSubstitutionSettings) -> Void, onDone: @escaping () -> Void) {
        self.settings = settings; self.onChange = onChange; self.onDone = onDone
        super.init(frame: .zero)
        let title = NSTextField(labelWithString: "Smart Substitutions")
        title.font = .boldSystemFont(ofSize: 17)
        let help = NSTextField(wrappingLabelWithString: #"Type |sqrt| to insert √. Escape a literal sequence as \|sqrt|; the backslash stays. Within a rule, type \| for a pipe and \\ for a backslash. Undo restores the typed sequence. Automatic uses Space, Tab or Return after a whole token. Select a row and press Space to toggle Automatic. Code fences and inline code are protected."#)
        help.font = .systemFont(ofSize: 11)
        for (name, width) in [("Input", 140.0), ("Replacement", 350.0), ("Automatic", 110.0)] {
            let column = NSTableColumn(identifier: .init(name)); column.title = name; column.width = width
            table.addTableColumn(column)
        }
        table.delegate = self; table.dataSource = self
        table.toggleAutomatic = { [weak self] in
            guard let self, self.rules.indices.contains(self.table.selectedRow) else { return }
            let button = NSButton(); button.tag = self.table.selectedRow
            button.state = self.rules[button.tag].automatic ? .off : .on
            self.toggleRow(button); self.table.reloadData()
        }
        table.rowHeight = 26
        table.setAccessibilityLabel("Substitution mappings; built-ins first, custom mappings below")
        let scroll = NSScrollView(); scroll.hasVerticalScroller = true; scroll.borderType = .bezelBorder; scroll.documentView = table
        scroll.heightAnchor.constraint(equalToConstant: 210).isActive = true
        input.delegate = self; output.delegate = self
        input.setAccessibilityLabel("Custom input")
        output.setAccessibilityLabel("Custom replacement")
        output.isRichText = false; output.allowsUndo = true; output.font = .systemFont(ofSize: 13)
        output.isAutomaticTextReplacementEnabled = false
        output.isAutomaticQuoteSubstitutionEnabled = false
        output.isAutomaticDashSubstitutionEnabled = false
        output.isAutomaticSpellingCorrectionEnabled = false
        output.isVerticallyResizable = true; output.autoresizingMask = [.width]; output.textContainer?.widthTracksTextView = true
        let outputScroll = NSScrollView(); outputScroll.hasVerticalScroller = true; outputScroll.borderType = .bezelBorder; outputScroll.documentView = output
        outputScroll.heightAnchor.constraint(equalToConstant: 50).isActive = true
        let grid = NSGridView(views: [[NSTextField(labelWithString: "Input"), input], [NSTextField(labelWithString: "Replacement"), outputScroll]])
        grid.column(at: 1).xPlacement = .fill; grid.columnSpacing = 12; grid.rowSpacing = 8
        message.font = .systemFont(ofSize: 11); message.textColor = .secondaryLabelColor
        syntax.font = .systemFont(ofSize: 11); syntax.textColor = .secondaryLabelColor
        for (button, action) in [(automatic, #selector(toggleDraft)), (add, #selector(addCustom)), (new, #selector(newCustom)), (delete, #selector(deleteCustom)), (done, #selector(close))] {
            button.target = self; button.action = action
            if button !== automatic { button.bezelStyle = .rounded }
        }
        done.keyEquivalent = "\r"
        let actions = NSStackView(views: [new, add, delete, done]); actions.spacing = 8; actions.distribution = .fillProportionally
        let stack = NSStackView(views: [title, help, scroll, syntax, grid, automatic, message, actions])
        stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false; addSubview(stack)
        NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20), stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20), stack.topAnchor.constraint(equalTo: topAnchor, constant: 20)])
        for view in [help, scroll, syntax, grid, message, actions] { view.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true }
        configureKeyLoop()
        loadSelection()
    }
    private func configureKeyLoop() {
        table.nextKeyView = input; input.nextKeyView = output; output.nextKeyView = automatic
        automatic.nextKeyView = new; new.nextKeyView = add; add.nextKeyView = delete; delete.nextKeyView = done; done.nextKeyView = table
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let window, !initialFocus else { return }
        initialFocus = true
        DispatchQueue.main.async { [weak window, weak self] in
            guard let self, let window else { return }
            window.autorecalculatesKeyViewLoop = false
            self.configureKeyLoop()
            window.makeFirstResponder(self.table)
        }
    }
    override func cancelOperation(_ sender: Any?) { onDone() }
    func receive(_ value: SmartSubstitutionSettings) {
        guard settings != value else { return }
        settings = value; table.reloadData(); loadSelection()
    }
    func numberOfRows(in tableView: NSTableView) -> Int { rules.count }
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let rule = rules[row]
        switch tableColumn?.identifier.rawValue {
        case "Automatic":
            let button = SettingsNativeButton(checkboxWithTitle: "", target: self, action: #selector(toggleRow(_:)))
            button.tag = row; button.state = rule.automatic ? .on : .off
            button.setAccessibilityLabel("Automatic for " + rule.input)
            return button
        default:
            let field = NSTextField(labelWithString: tableColumn?.identifier.rawValue == "Input" ? rule.input : rule.replacement.replacingOccurrences(of: "\n", with: " ↵ "))
            field.lineBreakMode = .byTruncatingTail
            field.toolTip = rule.replacement
            return field
        }
    }
    func tableViewSelectionDidChange(_ notification: Notification) { loadSelection() }
    private func loadSelection() {
        loading = true; defer { loading = false }
        let row = table.selectedRow
        let builtIn = row >= 0 && row < SmartSubstitutionSettings.builtIns.count
        editingCustom = row >= SmartSubstitutionSettings.builtIns.count ? row - SmartSubstitutionSettings.builtIns.count : nil
        let rule = rules.indices.contains(row) ? rules[row] : nil
        input.stringValue = rule?.input ?? ""; output.string = rule?.replacement ?? ""
        automatic.state = rule?.automatic == true ? .on : .off
        input.isEnabled = !builtIn; output.isEditable = !builtIn; automatic.isEnabled = !builtIn
        delete.isEnabled = editingCustom != nil; add.isEnabled = rule == nil
        syntax.stringValue = rule.map { (builtIn ? "Built-in (input and replacement are fixed). " : "Custom mapping. ") + "Explicit: " + $0.explicitSequence } ?? "New custom mapping; Automatic defaults off."
        validateAndPersist()
    }
    private func validateAndPersist() {
        let builtIn = table.selectedRow >= 0 && table.selectedRow < SmartSubstitutionSettings.builtIns.count
        guard !builtIn else { message.stringValue = "Toggle Automatic in the table. Explicit syntax remains available while the global switch is on."; return }
        let others = SmartSubstitutionSettings.builtIns.map(\.input) + settings.custom.enumerated().filter { $0.offset != editingCustom }.map { $0.element.input }
        let error = SmartSubstitutionSettings.validation(input: input.stringValue, replacement: output.string, otherInputs: others)
        message.stringValue = error.map { $0 + " Changes are not saved until valid." } ?? "1–10 input characters; no pipes, backticks, edge whitespace, tabs or line breaks. Replacement: up to 16,384 UTF-16 units."
        add.isEnabled = editingCustom == nil && error == nil
        guard !loading, error == nil, let index = editingCustom else { return }
        settings.custom[index] = draft
        onChange(settings); table.reloadData()
        syntax.stringValue = "Custom mapping. Explicit: " + draft.explicitSequence
    }
    private var draft: SubstitutionRule { .init(input: input.stringValue, replacement: output.string, automatic: automatic.state == .on) }
    func control(_ control: NSControl, textView: NSTextView, doCommandBy command: Selector) -> Bool {
        let target: NSView?
        if command == #selector(NSResponder.insertTab(_:)) { target = output }
        else if command == #selector(NSResponder.insertBacktab(_:)) { target = table }
        else { return false }
        if let target { window?.makeFirstResponder(target) }
        return true
    }
    func controlTextDidBeginEditing(_ obj: Notification) {
        guard let editor = input.currentEditor() as? NSTextView else { return }
        editor.isAutomaticTextReplacementEnabled = false
        editor.isAutomaticQuoteSubstitutionEnabled = false
        editor.isAutomaticDashSubstitutionEnabled = false
        editor.isAutomaticSpellingCorrectionEnabled = false
    }
    func controlTextDidChange(_ obj: Notification) { validateAndPersist() }
    func textDidChange(_ notification: Notification) { validateAndPersist() }
    @objc private func toggleDraft() { validateAndPersist() }
    @objc private func toggleRow(_ sender: NSButton) {
        let row = sender.tag
        if row < SmartSubstitutionSettings.builtIns.count { settings.automaticOverrides[rules[row].input] = sender.state == .on }
        else { settings.custom[row - SmartSubstitutionSettings.builtIns.count].automatic = sender.state == .on }
        onChange(settings)
        if table.selectedRow == row { automatic.state = sender.state }
    }
    @objc private func newCustom() { table.deselectAll(nil); loadSelection(); window?.makeFirstResponder(input) }
    @objc private func addCustom() {
        guard add.isEnabled else { return }
        settings.custom.append(draft); onChange(settings); table.reloadData()
        table.selectRowIndexes(IndexSet(integer: rules.count - 1), byExtendingSelection: false)
        table.scrollRowToVisible(rules.count - 1)
        loadSelection()
    }
    @objc private func deleteCustom() {
        guard let index = editingCustom else { return }
        settings.custom.remove(at: index); onChange(settings); table.reloadData(); newCustom()
    }
    @objc private func close() { onDone() }
}

@MainActor private final class SubstitutionsTable: NSTableView {
    var toggleAutomatic: (() -> Void)?
    override func keyDown(with event: NSEvent) {
        if event.charactersIgnoringModifiers == " ", event.modifierFlags.intersection([.command, .control, .option]).isEmpty { toggleAutomatic?() }
        else { super.keyDown(with: event) }
    }
}

@MainActor private final class SubstitutionDraftOutput: NSTextView {
    override func insertTab(_ sender: Any?) { if let nextKeyView { window?.makeFirstResponder(nextKeyView) } }
    override func insertBacktab(_ sender: Any?) { if let previousValidKeyView { window?.makeFirstResponder(previousValidKeyView) } }
}
