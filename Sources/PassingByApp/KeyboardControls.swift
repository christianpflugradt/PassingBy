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
    var advancesFocus = false
    var accessibilityLabel: String
    var action: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(action) }
    func makeNSView(context: Context) -> KeyboardActionButton {
        let button = KeyboardActionButton(title: title, target: context.coordinator, action: #selector(Coordinator.activate(_:)))
        button.isBordered = false
        button.setContentHuggingPriority(.required, for: .horizontal)
        return button
    }
    func updateNSView(_ button: KeyboardActionButton, context: Context) {
        context.coordinator.action = action
        button.title = title
        button.identifier = dashboardOrder.map { NSUserInterfaceItemIdentifier("dashboard-\($0)") }
        button.advancesFocus = advancesFocus
        button.font = .systemFont(ofSize: pointSize, weight: bold ? .semibold : .regular)
        button.image = symbol.flatMap { NSImage(systemSymbolName: $0, accessibilityDescription: nil) }?.withSymbolConfiguration(.init(pointSize: pointSize, weight: .regular))
        button.imagePosition = symbol == nil ? .noImage : .imageOnly
        button.contentTintColor = symbol == nil ? .labelColor : .secondaryLabelColor
        button.setAccessibilityLabel(accessibilityLabel)
    }
    @MainActor final class Coordinator: NSObject {
        var action: () -> Void
        init(_ action: @escaping () -> Void) { self.action = action }
        @objc func activate(_ sender: KeyboardActionButton) {
            let next = sender.advancesFocus && sender.window?.firstResponder === sender ? sender.focusAfterActivation : nil
            action()
            if let next {
                DispatchQueue.main.async { [weak next] in
                    guard let next, let window = next.window else { return }
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
    override var acceptsFirstResponder: Bool { true }
    override var needsPanelToBecomeKey: Bool { true }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 48, let target = event.modifierFlags.contains(.shift) ? orderedPrevious : orderedNext {
            window?.makeFirstResponder(target)
        } else if event.charactersIgnoringModifiers == "\r" { if !event.isARepeat { performClick(nil) } }
        else { super.keyDown(with: event) }
    }
}

struct KeyboardCategoryFilter: NSViewRepresentable {
    let labels: [PassingByCore.Label]
    @Binding var selection: LabelContext

    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> NSView {
        let control: NSControl
        if (1...4).contains(labels.count) {
            let segments = KeyboardCategorySegments()
            segments.trackingMode = .selectOne
            control = segments
        } else {
            control = KeyboardCategoryMenu()
        }
        control.target = context.coordinator
        control.action = #selector(Coordinator.changed(_:))
        control.identifier = NSUserInterfaceItemIdentifier("dashboard-0")
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

@MainActor private final class KeyboardCategorySegments: NSSegmentedControl {
    override var acceptsFirstResponder: Bool { true }
    override var needsPanelToBecomeKey: Bool { true }
    weak var orderedNext: NSView?
    weak var orderedPrevious: NSView?
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 48, let target = event.modifierFlags.contains(.shift) ? orderedPrevious : orderedNext {
            window?.makeFirstResponder(target)
            return
        }
        switch event.keyCode {
        case 123, 124: // Left and Right switch categories within this one native filter.
            selectedSegment = min(segmentCount - 1, max(0, selectedSegment + (event.keyCode == 123 ? -1 : 1)))
            sendAction(action, to: target)
        case 36, 49:
            sendAction(action, to: target)
        default: super.keyDown(with: event)
        }
    }
}

@MainActor private final class KeyboardCategoryMenu: NSPopUpButton {
    weak var orderedNext: NSView?
    weak var orderedPrevious: NSView?
    override var acceptsFirstResponder: Bool { true }
    override var needsPanelToBecomeKey: Bool { true }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 48, let target = event.modifierFlags.contains(.shift) ? orderedPrevious : orderedNext {
            window?.makeFirstResponder(target)
        } else { super.keyDown(with: event) }
    }
}

/// Dashboard follows its two columns in reading order rather than jumping across rows.
struct DashboardKeyLoop: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { NSView() }
    func updateNSView(_ view: NSView, context: Context) {
        DispatchQueue.main.async { [weak view] in
            guard let root = view?.window?.contentView else { return }
            @MainActor func controls(in parent: NSView) -> [NSView] {
                var result: [NSView] = []
                if parent.identifier?.rawValue.hasPrefix("dashboard-") == true { result.append(parent) }
                for child in parent.subviews { result += controls(in: child) }
                return result
            }
            @MainActor func order(_ control: NSView) -> Int { Int(control.identifier!.rawValue.dropFirst("dashboard-".count))! }
            let ordered = controls(in: root).sorted { order($0) < order($1) }
            guard !ordered.isEmpty else { return }
            for (index, control) in ordered.enumerated() {
                let next = ordered[(index + 1) % ordered.count]
                let previous = ordered[(index + ordered.count - 1) % ordered.count]
                if let button = control as? KeyboardActionButton {
                    button.orderedNext = next
                    button.orderedPrevious = previous
                    if button.advancesFocus {
                        button.focusAfterActivation = ordered.dropFirst(index + 1).first { ($0 as? KeyboardActionButton)?.advancesFocus == true } ?? ordered.first { order($0) == 100 }
                    }
                } else if let segments = control as? KeyboardCategorySegments {
                    segments.orderedNext = next
                    segments.orderedPrevious = previous
                } else if let menu = control as? KeyboardCategoryMenu {
                    menu.orderedNext = next
                    menu.orderedPrevious = previous
                }
            }
        }
    }
}
