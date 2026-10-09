import AppKit

struct ContextHelpRow: Equatable {
    let key: String
    let action: String
    init(_ key: String, _ action: String) { self.key = key; self.action = action }
}

struct ContextHelpSection: Equatable {
    let title: String
    let rows: [ContextHelpRow]
}

struct ContextHelpDocument: Equatable {
    let title: String
    let sections: [ContextHelpSection]
}

/// A separate utility panel can show help above a sheet without closing or nesting that sheet.
@MainActor final class ContextHelpController: NSObject, NSWindowDelegate {
    private(set) var panel: NSPanel?
    private weak var sourceWindow: NSWindow?
    private weak var sourceResponder: NSResponder?
    private var sourceSelection: NSRange?
    private var restoreOnClose = true

    func toggle(_ document: ContextHelpDocument, from window: NSWindow) {
        if panel != nil { close(); return }
        sourceWindow = window
        sourceResponder = window.firstResponder
        sourceSelection = nil
        if let editor = window.firstResponder as? NSTextView, editor.isFieldEditor,
           let root = window.contentView {
            func field(in view: NSView) -> NSTextField? {
                if let field = view as? NSTextField, field.currentEditor() === editor { return field }
                return view.subviews.lazy.compactMap { field(in: $0) }.first
            }
            if let field = field(in: root) {
                sourceResponder = field
                sourceSelection = editor.selectedRange()
            }
        }
        restoreOnClose = true
        let panel = HelpPanel(contentRect: NSRect(x: 0, y: 0, width: 520, height: 560),
                              styleMask: [.titled, .closable, .resizable, .utilityWindow], backing: .buffered, defer: false)
        panel.title = document.title
        panel.isReleasedWhenClosed = false
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = true
        panel.worksWhenModal = true
        panel.minSize = NSSize(width: 440, height: 300)
        panel.maxSize = NSSize(width: 760, height: 900)
        panel.delegate = self
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false
        let content = NSStackView()
        content.orientation = .vertical
        content.alignment = .leading
        content.spacing = 18
        content.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
        let introduction = NSTextField(wrappingLabelWithString: "F1 or Escape closes this help and returns to your previous control. Close help before using the commands below. Use Up/Down or Page Up/Page Down to scroll. Some Mac keyboards require Fn+F1.")
        introduction.textColor = .secondaryLabelColor
        content.addArrangedSubview(introduction)
        for section in document.sections {
            let heading = NSTextField(labelWithString: section.title)
            heading.font = .systemFont(ofSize: 15, weight: .semibold)
            content.addArrangedSubview(heading)
            let grid = NSGridView(views: section.rows.map { row in
                let key = NSTextField(wrappingLabelWithString: row.key)
                key.font = .monospacedSystemFont(ofSize: 12, weight: .medium)
                let action = NSTextField(wrappingLabelWithString: row.action)
                return [key, action]
            })
            grid.columnSpacing = 18
            grid.rowSpacing = 9
            grid.column(at: 0).width = 110
            grid.column(at: 0).xPlacement = .leading
            grid.column(at: 1).xPlacement = .fill
            for index in section.rows.indices { grid.row(at: index).yPlacement = .top }
            content.addArrangedSubview(grid)
        }
        scroll.documentView = content
        panel.contentView = scroll
        content.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            content.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor),
            introduction.widthAnchor.constraint(equalTo: content.widthAnchor, constant: -40)
        ])
        for view in content.arrangedSubviews where view is NSGridView {
            view.widthAnchor.constraint(equalTo: content.widthAnchor, constant: -40).isActive = true
        }
        panel.scroll = scroll
        self.panel = panel
        window.addChildWindow(panel, ordered: .above)
        let screen = window.screen?.visibleFrame ?? window.frame
        let origin = NSPoint(x: min(max(screen.minX, window.frame.midX - panel.frame.width / 2), screen.maxX - panel.frame.width),
                             y: min(max(screen.minY, window.frame.midY - panel.frame.height / 2), screen.maxY - panel.frame.height))
        panel.setFrameOrigin(origin)
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(panel)
        content.layoutSubtreeIfNeeded()
        scroll.contentView.scroll(to: NSPoint(x: 0, y: content.isFlipped ? 0 : max(0, content.frame.height - scroll.contentView.bounds.height)))
    }
    func close(restoringFocus: Bool = true) {
        restoreOnClose = restoringFocus
        panel?.close()
    }
    func windowWillClose(_ notification: Notification) {
        guard let panel, notification.object as? NSWindow === panel else { return }
        panel.parent?.removeChildWindow(panel)
        self.panel = nil
        guard restoreOnClose, let window = sourceWindow, window.isVisible else { return }
        let responder = sourceResponder
        let selection = sourceSelection
        DispatchQueue.main.async { [weak window, weak responder] in
            guard let window, window.isVisible else { return }
            if let view = responder as? NSView, view.window !== window { return }
            window.makeKeyAndOrderFront(nil)
            if let responder { window.makeFirstResponder(responder) }
            if let field = responder as? NSTextField, let selection,
               let editor = field.currentEditor() as? NSTextView { editor.setSelectedRange(selection) }
        }
    }
    func handle(_ event: NSEvent) -> NSEvent? {
        guard event.window === panel, panel != nil else { return event }
        if event.keyCode == 53 || event.keyCode == 122 ||
            (event.charactersIgnoringModifiers == "w" && event.modifierFlags.contains(.command)) {
            if !event.isARepeat { close() }
            return nil
        }
        // Reading help must not execute an item command in the underlying editor or dialog.
        if event.keyCode == 36 || event.keyCode == 76 { return nil }
        if event.modifierFlags.contains(.command), event.characters != "?", event.charactersIgnoringModifiers != "q" { return nil }
        if event.modifierFlags.intersection([.command, .option, .control]).isEmpty,
           (panel as? HelpPanel)?.scrollKey(event) == true { return nil }
        return event
    }
    private final class HelpPanel: NSPanel {
        weak var scroll: NSScrollView?
        override var canBecomeKey: Bool { true }
        override var canBecomeMain: Bool { false }
        override func cancelOperation(_ sender: Any?) { close() }
        override func keyDown(with event: NSEvent) {
            if !scrollKey(event) { super.keyDown(with: event) }
        }
        func scrollKey(_ event: NSEvent) -> Bool {
            guard let scroll, let document = scroll.documentView else { return false }
            let clip = scroll.contentView
            let maximum = max(0, document.bounds.height - clip.bounds.height)
            let direction: CGFloat = document.isFlipped ? 1 : -1
            var point = clip.bounds.origin
            switch event.keyCode {
            case 125: point.y += 40 * direction
            case 126: point.y -= 40 * direction
            case 121, 49: point.y += clip.bounds.height * direction
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
    }
}
