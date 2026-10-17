import AppKit
import PassingByCore

@MainActor func runSmartSubstitutionNativeTests() {
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 680, height: 570), styleMask: [.titled, .closable], backing: .buffered, defer: false)
    defer { window.orderOut(nil) }
    func check(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else { fatalError("Smart substitutions: " + message) }
    }
    let editor = SubstitutionTextView(frame: window.contentView!.bounds)
    editor.isRichText = false; editor.allowsUndo = true
    editor.substitutionSettings.enabled = true
    window.contentView?.addSubview(editor)
    window.makeKeyAndOrderFront(nil); window.makeFirstResponder(editor)
    // These synthetic keys run inside one NSApplication callback. Explicit groups emulate
    // the event boundaries that NSApplication normally supplies between physical keystrokes.
    editor.undoManager?.groupsByEvent = false
    func reset(_ value: String = "") {
        editor.breakUndoCoalescing()
        RunLoop.current.run(until: Date().addingTimeInterval(0.002))
        editor.string = value; editor.setSelectedRange(NSRange(location: value.utf16.count, length: 0))
        editor.undoManager?.removeAllActions()
    }
    func type(_ value: String, into target: NSTextView? = nil) {
        let target = target ?? editor
        for char in value {
            let chars = String(char)
            let code: UInt16 = chars == "\t" ? 48 : chars == "\r" ? 36 : 0
            let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber, context: nil, characters: chars, charactersIgnoringModifiers: chars, isARepeat: false, keyCode: code)!
            if target.undoManager?.groupingLevel == 0 { target.undoManager?.beginUndoGrouping() }
            target.keyDown(with: event)
            if target.undoManager?.groupingLevel == 1 { target.undoManager?.endUndoGrouping() }
            RunLoop.current.run(until: Date().addingTimeInterval(0.002))
        }
    }
    type("|sqrt|")
    check(editor.string == "√", "physical keys trigger explicit conversion")
    check(editor.selectedRange() == NSRange(location: 1, length: 0), "caret follows replacement")
    check(editor.undoManager?.canUndo == true, "native Undo registration")
    editor.undoManager?.undo()
    check(editor.string == "|sqrt|", "one Undo restores complete explicit sequence, got: \(editor.string.debugDescription), selection \(editor.selectedRange())")
    check(editor.selectedRange() == NSRange(location: 6, length: 0), "Undo restores trigger caret")
    editor.undoManager?.redo()
    check(editor.string == "√", "Redo restores replacement without recursively matching")
    reset("hello "); type(":) ")
    check(editor.string == "hello 🙂 ", "Automatic retains boundary")
    editor.undoManager?.undo()
    check(editor.string == "hello :) ", "one Undo restores Automatic trigger and boundary")
    reset(); editor.substitutionSettings.enabled = false; type("|sqrt| :) ")
    check(editor.string == "|sqrt| :) ", "global off prevents native conversion")
    editor.substitutionSettings.enabled = true
    reset("```swift\n"); type("|sqrt| :) ")
    check(editor.string == "```swift\n|sqrt| :) ", "both syntaxes stay literal in code")
    reset("`code "); type("|sqrt| :) ")
    check(editor.string == "`code |sqrt| :) ", "unclosed inline span is protected")
    reset(); type(#"\|sqrt|"#)
    check(editor.string == #"\|sqrt|"#, "escaped opener stays literal")
    reset(); editor.undoManager?.beginUndoGrouping()
    editor.insertText("|sqrt|", replacementRange: NSRange(location: NSNotFound, length: 0))
    editor.undoManager?.endUndoGrouping()
    check(editor.string == "|sqrt|", "programmatic insertion does not convert")
    // Import from a private pasteboard through AppKit's native paste reader.
    let pasteboard = NSPasteboard(name: .init("PassingBySubstitutionTests-\(UUID())"))
    defer { pasteboard.releaseGlobally() }
    reset(); pasteboard.setString("|sqrt| :) ", forType: .string)
    editor.undoManager?.beginUndoGrouping()
    let didPaste = editor.readSelection(from: pasteboard, type: .string)
    editor.undoManager?.endUndoGrouping()
    check(didPaste && editor.string == "|sqrt| :) ", "paste remains literal")
    reset(); editor.undoManager?.beginUndoGrouping(); editor.setMarkedText("|sqrt", selectedRange: NSRange(location: 5, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0)); editor.undoManager?.endUndoGrouping(); type("|")
    check(!editor.string.contains("√"), "marked-text composition cannot trigger conversion")
    editor.unmarkText()
    reset("before |sqrt| middle |sqrt after |sqrt|")
    let cursor = (editor.string as NSString).range(of: " after").location
    editor.setSelectedRange(NSRange(location: cursor, length: 0)); type("|")
    check(editor.string == "before |sqrt| middle √ after |sqrt|", "only insertion range changes in existing content")
    reset(":)"); type("\t")
    check(editor.string == "🙂\t", "typed tab is a boundary")
    reset(":)"); type("\r")
    check(editor.string == "🙂\n", "typed Return is a boundary")
    reset("```\ncode\n```\n"); type("|sqrt|")
    check(editor.string.hasSuffix("√"), "closed fence allows matching")
    editor.setSelectedRange(NSRange(location: 0, length: 0)); type("`")
    editor.setSelectedRange(NSRange(location: editor.string.utf16.count, length: 0)); type(" |sqrt|")
    check(editor.string.hasSuffix(" |sqrt|"), "editing opening fence invalidates native cache")

    var largeSettings = SmartSubstitutionSettings(); largeSettings.enabled = true
    largeSettings.custom = (0..<300).map { SubstitutionRule(input: "rule\($0)", replacement: "output", automatic: true) }
    editor.substitutionSettings = largeSettings
    let prefix = String(repeating: "Existing |sqrt| prose.\n", count: 30_000)
    let suffix = String(repeating: " Tail |sqrt| prose.\n", count: 30_000)
    reset(prefix + "rule299" + suffix)
    editor.setSelectedRange(NSRange(location: prefix.utf16.count + 7, length: 0))
    let nativeStart = Date(); type(" ")
    check(editor.string == prefix + "output " + suffix, "large-note middle edit changes only the current trigger")
    print("Smart substitutions native: \(editor.string.utf16.count) UTF-16 units, 361 mappings, boundary edit \(Date().timeIntervalSince(nativeStart))s")
    editor.substitutionSettings = SmartSubstitutionSettings(); editor.substitutionSettings.enabled = true
    reset()
    editor.substitutionSettings.custom = [.init(input: "nested", replacement: "|sqrt| 👩🏽‍💻")]
    type("|nested|")
    check(editor.string == "|sqrt| 👩🏽‍💻", "Unicode replacements do not recursively substitute")
    let noteEditor = NoteEditorTextView(frame: window.contentView!.bounds)
    noteEditor.allowsUndo = true; noteEditor.substitutionSettings.enabled = true; noteEditor.indentWidth = 4
    window.contentView?.addSubview(noteEditor); window.makeFirstResponder(noteEditor)
    type(":)\t", into: noteEditor)
    check(noteEditor.string == "🙂    ", "Note Tab preserves indentation spaces and triggers Automatic")
    noteEditor.undoManager?.undo()
    check(noteEditor.string == ":)    ", "Note indentation boundary survives substitution Undo")
    let veto = SubstitutionVetoDelegate()
    reset(); editor.delegate = veto; type("|sqrt|")
    check(editor.string == "|sqrt|" && editor.selectedRange().location == 6, "native delegate veto preserves text and caret")
    veto.denied = "|"; reset("|sqrt|"); type("|")
    check(editor.string == "|sqrt|" && editor.selectedRange().location == 6, "a rejected delimiter cannot transform an existing sequence")
    veto.denied = " "; reset(":) "); type(" ")
    check(editor.string == ":) ", "a rejected boundary cannot transform existing text")
    editor.delegate = nil
    let title = SubstitutionTextField(string: "")
    title.frame = NSRect(x: 0, y: 0, width: 400, height: 28)
    title.substitutionSettings.enabled = true
    window.contentView?.addSubview(title); window.makeFirstResponder(title)
    guard let fieldEditor = title.currentEditor() as? SubstitutionTextView else { fatalError("Title did not receive substitution field editor") }
    fieldEditor.setSelectedRange(NSRange(location: 0, length: fieldEditor.string.utf16.count))
    type("|sqrt|", into: fieldEditor)
    check(fieldEditor.string == "√", "title field uses same native matcher")
    fieldEditor.undoManager?.undo()
    check(fieldEditor.string == "|sqrt|", "title Undo restores explicit delimiters")
    let plain = NSTextField(string: "")
    plain.frame = NSRect(x: 0, y: 40, width: 400, height: 28)
    window.contentView?.addSubview(plain); window.makeFirstResponder(plain)
    check(!(plain.currentEditor() is SubstitutionTextView), "search/settings controls keep standard field editor")
    // Exercise the actual management form, including valid auto-save and invalid drafts.
    var managed = SmartSubstitutionSettings()
    let form = SubstitutionsForm(settings: managed, onChange: { managed = $0 }, onDone: {})
    window.setContentSize(NSSize(width: 680, height: 560)); window.contentView = form
    window.displayIfNeeded(); form.layoutSubtreeIfNeeded()
    RunLoop.current.run(until: Date().addingTimeInterval(0.05))
    func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
    func button(_ title: String) -> NSButton { descendants(form).compactMap { $0 as? NSButton }.first { $0.title == title }! }
    let table = descendants(form).compactMap { $0 as? NSTableView }.first!
    let customInput = descendants(form).compactMap { $0 as? NSTextField }.first { $0.accessibilityLabel() == "Custom input" }!
    let customOutput = descendants(form).compactMap { $0 as? NSTextView }.first { $0.accessibilityLabel() == "Custom replacement" }!
    table.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
    check(!customInput.isEnabled && !customOutput.isEditable && !button("Delete Custom Mapping").isEnabled, "built-in mappings cannot be edited or deleted")
    let space = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil, characters: " ", charactersIgnoringModifiers: " ", isARepeat: false, keyCode: 49)!
    table.keyDown(with: space)
    check(managed.automaticOverrides[":)"] == false, "table Space toggles built-in Automatic")
    button("New Custom Mapping").performClick(nil)
    customInput.stringValue = "abc"; customOutput.string = "multi 👩🏽‍💻 output"
    customInput.delegate?.controlTextDidChange?(Notification(name: NSControl.textDidChangeNotification, object: customInput))
    check(button("Add Custom Mapping").isEnabled, "valid custom draft can be added")
    button("Add Custom Mapping").performClick(nil)
    check(managed.custom.count == 1 && !managed.custom[0].automatic, "custom mappings default to Automatic off")
    customInput.stringValue = "sqrt"
    customInput.delegate?.controlTextDidChange?(Notification(name: NSControl.textDidChangeNotification, object: customInput))
    check(managed.custom[0].input == "abc", "invalid duplicate draft leaves persisted mapping intact")
    customInput.stringValue = "abcd"
    customInput.delegate?.controlTextDidChange?(Notification(name: NSControl.textDidChangeNotification, object: customInput))
    check(managed.custom[0].input == "abcd", "valid custom edits auto-save")
    window.makeFirstResponder(customInput)
    type("\t", into: customInput.currentEditor() as? NSTextView)
    check(window.firstResponder === customOutput, "Tab reaches multi-line Replacement, got \(String(describing: window.firstResponder))")
    customOutput.insertTab(nil)
    check(window.firstResponder === button("Automatic"), "Tab leaves Replacement for Automatic")
    button("Delete Custom Mapping").performClick(nil)
    check(managed.custom.isEmpty && window.firstResponder === customInput.currentEditor(), "deletion restores focus to surviving custom input")
    form.layoutSubtreeIfNeeded()
    for title in ["New Custom Mapping", "Add Custom Mapping", "Delete Custom Mapping", "Done"] {
        let bounds = form.convert(button(title).bounds, from: button(title))
        check(form.bounds.contains(bounds), "management action stays within sheet: " + title)
    }
    if let snapshotPath = ProcessInfo.processInfo.environment["PASSING_BY_SUBSTITUTIONS_SNAPSHOT"], let bitmap = form.bitmapImageRepForCachingDisplay(in: form.bounds) {
        form.cacheDisplay(in: form.bounds, to: bitmap)
        try? bitmap.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: snapshotPath))
    }
    print("Smart substitutions: native typing, boundaries, range edits, Undo/Redo, paste, marked text, fences and title field tests passed")
}

@MainActor private final class SubstitutionVetoDelegate: NSObject, NSTextViewDelegate {
    var denied = "√"
    func textView(_ textView: NSTextView, shouldChangeTextIn affectedCharRange: NSRange, replacementString: String?) -> Bool { replacementString != denied }
}
