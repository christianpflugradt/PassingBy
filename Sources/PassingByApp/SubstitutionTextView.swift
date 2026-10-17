import AppKit
import PassingByCore

/// Only physical key handling arms this control. Paste, programmatic insertions, IME commits,
/// accessibility updates, and Undo/Redo cannot accidentally run the matcher.
@MainActor class SubstitutionTextView: NSTextView {
    var substitutionSettings = SmartSubstitutionSettings() {
        didSet {
            if substitutionSettings != oldValue { matcher = SmartSubstitutionMatcher(settings: substitutionSettings) }
        }
    }
    private var matcher = SmartSubstitutionMatcher(settings: SmartSubstitutionSettings())
    private let markdownContext = SubstitutionMarkdownContext()
    private var typing = false
    private var commandInsertion = false
    private var pendingTrigger: (String, Int?)?
    private var lastTypedInsertion: String?
    private weak var observedStorage: NSTextStorage?

    override func keyDown(with event: NSEvent) {
        let previous = typing
        typing = !hasMarkedText() && !event.modifierFlags.contains(.command) && !event.modifierFlags.contains(.control)
        defer { typing = previous }
        pendingTrigger = nil; lastTypedInsertion = nil
        super.keyDown(with: event)
        if let (typed, caret) = pendingTrigger { substituteAfterTyping(typed, caret: caret) }
        pendingTrigger = nil; lastTypedInsertion = nil
    }
    override func insertText(_ insertString: Any, replacementRange: NSRange) {
        observeStorageIfNeeded()
        let selection = selectedRange(), previousLength = textStorage?.length ?? 0
        let typed = typing && !hasMarkedText() && selection.length == 0
        let eligible = typed && replacementRange.location == NSNotFound
        let inserted = (insertString as? String) ?? (insertString as? NSAttributedString)?.string ?? ""
        super.insertText(insertString, replacementRange: replacementRange)
        if typed && !hasMarkedText() && insertionSucceeded(inserted, at: selection, previousLength: previousLength) {
            lastTypedInsertion = inserted
            if eligible && !commandInsertion { pendingTrigger = (inserted, nil) }
        }
    }
    override func insertNewline(_ sender: Any?) {
        observeStorageIfNeeded()
        let selection = selectedRange(), previousLength = textStorage?.length ?? 0
        let eligible = typing && !hasMarkedText() && selection.length == 0
        commandInsertion = true
        super.insertNewline(sender)
        commandInsertion = false
        if eligible && insertionSucceeded("\n", at: selection, previousLength: previousLength) { pendingTrigger = ("\n", nil) }
    }
    override func insertTab(_ sender: Any?) {
        observeStorageIfNeeded()
        let selection = selectedRange(), previousLength = textStorage?.length ?? 0
        let eligible = typing && !hasMarkedText() && selection.length == 0
        commandInsertion = true
        super.insertTab(sender)
        commandInsertion = false
        if eligible && insertionSucceeded("\t", at: selection, previousLength: previousLength) { pendingTrigger = ("\t", nil) }
    }
    /// Notes insert spaces for Tab. Preserve the full indentation while treating the first space as a boundary.
    func substituteAfterIndentation(width: Int) {
        if typing && !hasMarkedText() && lastTypedInsertion == String(repeating: " ", count: width) {
            pendingTrigger = (" ", selectedRange().location - width + 1)
        }
    }
    private func insertionSucceeded(_ inserted: String, at selection: NSRange, previousLength: Int) -> Bool {
        selection.length == 0 && textStorage?.length == previousLength + inserted.utf16.count &&
            selectedRange() == NSRange(location: selection.location + inserted.utf16.count, length: 0)
    }
    private func observeStorageIfNeeded() {
        guard let textStorage, observedStorage !== textStorage else { return }
        if let observedStorage { NotificationCenter.default.removeObserver(self, name: NSTextStorage.didProcessEditingNotification, object: observedStorage) }
        observedStorage = textStorage
        NotificationCenter.default.addObserver(self, selector: #selector(storageEdited(_:)), name: NSTextStorage.didProcessEditingNotification, object: textStorage)
        markdownContext.invalidate(from: 0)
    }
    @objc private func storageEdited(_ note: Notification) {
        guard let storage = note.object as? NSTextStorage, storage.editedMask.contains(.editedCharacters) else { return }
        markdownContext.invalidate(from: storage.editedRange.location)
    }
    private func substituteAfterTyping(_ typed: String, caret: Int? = nil) {
        guard substitutionSettings.enabled, !hasMarkedText(), undoManager?.isUndoing != true, undoManager?.isRedoing != true else { return }
        let source = string as NSString
        let caret = caret ?? selectedRange().location
        guard let match = matcher.match(in: source, caret: caret, typed: typed),
              markdownContext.allows(source, range: match.range) else { return }
        // Close the typing group so one Undo restores the entire trigger, including its typed delimiter/boundary.
        breakUndoCoalescing()
        let manager = undoManager
        if manager?.groupingLevel == 1 { manager?.endUndoGrouping() }
        manager?.beginUndoGrouping()
        defer { manager?.endUndoGrouping() }
        let selection = selectedRange()
        let expectedLength = source.length + match.replacement.utf16.count - match.range.length
        super.insertText(match.replacement, replacementRange: match.range)
        // A native delegate may veto the change. Leave its selection untouched in that case.
        guard let storage = textStorage, storage.length == expectedLength,
              (storage.string as NSString).substring(with: NSRange(location: match.range.location, length: match.replacement.utf16.count)) == match.replacement else { return }
        setSelectedRange(NSRange(location: selection.location + match.replacement.utf16.count - match.range.length, length: 0))
        undoManager?.setActionName("Smart Substitution")
        breakUndoCoalescing()
    }
}

/// Each eligible title owns its field editor; settings and search retain the standard field editor.
@MainActor final class SubstitutionTextField: NSTextField {
    var substitutionSettings = SmartSubstitutionSettings() {
        didSet { (cell as? SubstitutionFieldCell)?.editor.substitutionSettings = substitutionSettings }
    }
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        cell = SubstitutionFieldCell(textCell: "")
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

@MainActor private final class SubstitutionFieldCell: NSTextFieldCell {
    let editor: SubstitutionTextView = {
        let editor = SubstitutionTextView()
        editor.isFieldEditor = true
        editor.isRichText = false
        editor.allowsUndo = true
        editor.isAutomaticTextReplacementEnabled = false
        return editor
    }()
    override func fieldEditor(for controlView: NSView) -> NSTextView? { editor }
}
