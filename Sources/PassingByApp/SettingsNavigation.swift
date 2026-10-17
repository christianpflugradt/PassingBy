import AppKit
import SwiftUI

/// One order drives both the local navigation and the content.
enum SettingsSection: String, CaseIterable, Identifiable {
    case dashboard, todos, appointments, notes, categories, textEditing, data, security, maintenance
    var id: String { rawValue }
    var title: String {
        switch self {
        case .dashboard: "Dashboard"
        case .todos: "To-dos"
        case .appointments: "Appointments"
        case .notes: "Notes"
        case .categories: "Categories"
        case .textEditing: "Text Editing"
        case .data: "Data"
        case .security: "Security"
        case .maintenance: "Maintenance"
        }
    }
    var navigationID: String { "settings-000-section-" + String(SettingsSection.allCases.firstIndex(of: self)!) }
    static func containing(_ id: String) -> SettingsSection? {
        guard id.hasPrefix("settings-"), let number = Int(id.split(separator: "-").dropFirst().first ?? "") else { return nil }
        switch number {
        case 10..<100: return .dashboard
        case 100..<300: return .categories
        case 300..<400: return .todos
        case 400..<500: return .appointments
        case 500..<560: return .notes
        case 560..<600: return .textEditing
        case 600..<700: return .security
        case 700..<900: return .data
        case 900...: return .maintenance
        default: return nil
        }
    }
}

// Tokens are mutated on the main actor; NotificationCenter permits removal during destruction on any thread.
private final class SettingsObservationTokens: @unchecked Sendable {
    var values: [NSObjectProtocol] = []
    deinit { for token in values { NotificationCenter.default.removeObserver(token) } }
}

@MainActor final class SettingsNavigationState: ObservableObject {
    @Published var availableWidth: CGFloat = 650
    @Published private(set) var active: SettingsSection
    private let defaults: UserDefaults
    private var anchors: [SettingsSection: SettingsAnchorView] = [:]
    private weak var scroll: NSScrollView?
    private let observations = SettingsObservationTokens()
    private var pending = false
    private var restored = false
    private var jumping = false
    private var jumpTarget: SettingsSection?
    private var lastStarts: [CGFloat] = []
    private var lastOffset: CGFloat = 0

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        active = defaults.string(forKey: "settings.section").flatMap(SettingsSection.init(rawValue:)) ?? .dashboard
    }
    // Reference line plus a small dead band prevents trackpad jitter at a heading.
    static func section(at offset: CGFloat, starts: [(SettingsSection, CGFloat)], current: SettingsSection) -> SettingsSection {
        let reference = offset + 20
        let candidate = starts.last(where: { $0.1 <= reference })?.0 ?? starts.first?.0 ?? current
        if candidate != current,
           let candidateIndex = starts.firstIndex(where: { $0.0 == candidate }),
           let currentIndex = starts.firstIndex(where: { $0.0 == current }) {
            let boundary = starts[max(candidateIndex, currentIndex)].1
            if abs(reference - boundary) < 4 { return current }
        }
        return candidate
    }
    func register(_ view: SettingsAnchorView, section: SettingsSection) {
        anchors[section] = view
        scheduleUpdate()
    }
    func scheduleUpdate() {
        guard !pending else { return }
        pending = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.pending = false
            self.update()
        }
    }
    private func observe(_ scroll: NSScrollView) {
        guard self.scroll !== scroll else { return }
        for observer in observations.values { NotificationCenter.default.removeObserver(observer) }
        observations.values.removeAll()
        self.scroll = scroll
        scroll.contentView.postsBoundsChangedNotifications = true
        scroll.documentView?.postsFrameChangedNotifications = true
        for (name, object) in [(NSView.boundsDidChangeNotification, scroll.contentView), (NSView.frameDidChangeNotification, scroll.documentView)] {
            observations.values.append(NotificationCenter.default.addObserver(forName: name, object: object, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.scheduleUpdate() }
            })
        }
    }
    private var starts: [(SettingsSection, CGFloat)] {
        guard let document = scroll?.documentView else { return [] }
        return SettingsSection.allCases.compactMap { section in
            guard let anchor = anchors[section], anchor.window != nil else { return nil }
            let frame = anchor.convert(anchor.bounds, to: document)
            return (section, document.isFlipped ? frame.minY : document.bounds.height - frame.maxY)
        }
    }
    private var offset: CGFloat {
        guard let scroll, let document = scroll.documentView else { return 0 }
        return document.isFlipped ? scroll.contentView.bounds.minY : document.bounds.height - scroll.contentView.bounds.maxY
    }
    private func setOffset(_ value: CGFloat) {
        guard let scroll, let document = scroll.documentView else { return }
        let maximum = max(0, document.bounds.height - scroll.contentView.bounds.height)
        let top = min(maximum, max(0, value))
        scroll.contentView.scroll(to: NSPoint(x: scroll.contentView.bounds.minX, y: document.isFlipped ? top : maximum - top))
        scroll.reflectScrolledClipView(scroll.contentView)
    }
    private func update() {
        guard let anchor = anchors[.dashboard], anchor.window != nil, !anchor.isHiddenOrHasHiddenAncestor,
              let scroll = anchor.enclosingScrollView else { return }
        observe(scroll)
        guard starts.count == SettingsSection.allCases.count else { return }
        if !restored {
            restored = true
            let horizontal = min(max(0, defaults.double(forKey: "settings.scrollX")), max(0, (scroll.documentView?.bounds.width ?? 0) - scroll.contentView.bounds.width))
            scroll.contentView.scroll(to: NSPoint(x: horizontal, y: scroll.contentView.bounds.minY))
            setOffset(CGFloat(defaults.double(forKey: "settings.scroll")))
        }
        guard !jumping else { return }
        let positions = starts
        let geometryChanged = positions.map(\.1) != lastStarts
        let scrolled = abs(offset - lastOffset) > 0.01
        if let target = jumpTarget, !scrolled {
            // Native control metrics can settle a layout later (notably after zoom).
            // Keep the requested heading aligned until an actual scroll takes over.
            if geometryChanged, let start = positions.first(where: { $0.0 == target })?.1 { setOffset(start - 12) }
        } else {
            jumpTarget = nil
            let next = Self.section(at: offset, starts: positions, current: active)
            if next != active { active = next }
        }
        lastStarts = positions.map(\.1)
        lastOffset = offset
        defaults.set(Double(offset), forKey: "settings.scroll")
        defaults.set(Double(scroll.contentView.bounds.minX), forKey: "settings.scrollX")
        defaults.set(active.rawValue, forKey: "settings.section")
    }
    func navigate(to section: SettingsSection) {
        guard let start = starts.first(where: { $0.0 == section })?.1 else { return }
        // Native immediate scrolling has no intermediate animation frames to fight the scroll spy.
        jumping = true
        jumpTarget = section
        active = section
        setOffset(start - 12)
        lastStarts = starts.map(\.1)
        lastOffset = offset
        defaults.set(Double(offset), forKey: "settings.scroll")
        defaults.set(section.rawValue, forKey: "settings.section")
        jumping = false
    }
}

@MainActor final class SettingsAnchorView: NSView {
    weak var navigation: SettingsNavigationState?
    override func layout() { super.layout(); navigation?.scheduleUpdate() }
    override func viewDidMoveToWindow() { navigation?.scheduleUpdate() }
}
struct SettingsSectionAnchor: NSViewRepresentable {
    let section: SettingsSection
    let navigation: SettingsNavigationState
    func makeNSView(context: Context) -> SettingsAnchorView { SettingsAnchorView() }
    func updateNSView(_ view: SettingsAnchorView, context: Context) {
        view.navigation = navigation
        view.identifier = .init("section-" + section.rawValue)
        navigation.register(view, section: section)
    }
}

struct SettingsSectionNavigation: View {
    @ObservedObject var navigation: SettingsNavigationState
    var body: some View {
        // Independently scrollable only when the window is too short for all destinations.
        ScrollView {
            VStack(alignment: .leading, spacing: 3) {
                ForEach(SettingsSection.allCases) { section in
                    SettingsNavigationButton(section: section, active: navigation.active == section) { navigation.navigate(to: section) }
                        .frame(height: 28)
                        .background(navigation.active == section ? Color.primary.opacity(0.08) : Color.clear, in: RoundedRectangle(cornerRadius: 5))
                }
            }
        }
        .accessibilityLabel("Settings sections")
    }
}

@MainActor final class SettingsSectionButton: SettingsNativeButton {
    override func keyDown(with event: NSEvent) {
        if [125, 126].contains(event.keyCode), event.modifierFlags.intersection([.command, .option, .control]).isEmpty, let parent = window?.contentView {
            func entries(_ view: NSView) -> [SettingsSectionButton] {
                if let entry = view as? SettingsSectionButton { return [entry] }
                return view.subviews.flatMap(entries)
            }
            let buttons = entries(parent).sorted { $0.identifier!.rawValue < $1.identifier!.rawValue }
            if let index = buttons.firstIndex(where: { $0 === self }) {
                let next = buttons[(index + (event.keyCode == 126 ? buttons.count - 1 : 1)) % buttons.count]
                next.scrollToVisible(next.bounds)
                window?.makeFirstResponder(next)
            }
        } else { super.keyDown(with: event) }
    }
}
struct SettingsNavigationButton: NSViewRepresentable {
    let section: SettingsSection
    let active: Bool
    let action: () -> Void
    func makeCoordinator() -> SettingsButton.Coordinator { SettingsButton.Coordinator() }
    func makeNSView(context: Context) -> SettingsSectionButton {
        let button = SettingsSectionButton(title: section.title, target: context.coordinator, action: #selector(SettingsButton.Coordinator.activate))
        button.isBordered = false
        button.alignment = .left
        button.setButtonType(.onOff)
        return button
    }
    func updateNSView(_ button: SettingsSectionButton, context: Context) {
        context.coordinator.action = action
        button.identifier = .init(section.navigationID)
        button.font = .systemFont(ofSize: 13)
        button.state = active ? .on : .off
        button.setAccessibilityLabel(section.title + " Settings section")
        button.setAccessibilityValue(active ? "Current section" : "")
    }
}

/// Keep the native Settings tree (including editors and Undo managers) mounted while visiting other screens.
struct SettingsSurface: NSViewRepresentable {
    let state: WorkspaceState
    let visible: Bool
    func makeCoordinator() -> Coordinator { Coordinator() }
    @MainActor final class Coordinator { var firstUpdate = true }
    func makeNSView(context: Context) -> NSHostingView<SettingsView> { NSHostingView(rootView: SettingsView(state: state)) }
    func updateNSView(_ view: NSHostingView<SettingsView>, context: Context) {
        if !visible && !view.isHidden { SettingsFocusRestoration.capture(in: view) }
        let returning = visible && (view.isHidden || context.coordinator.firstUpdate)
        context.coordinator.firstUpdate = false
        view.isHidden = !visible
        if returning {
            DispatchQueue.main.async { SettingsFocusRestoration.restore(in: view) }
        }
    }
}

@MainActor enum SettingsFocusRestoration {
    static func controls(in view: NSView) -> [NSView] { [view] + view.subviews.flatMap { controls(in: $0) } }
    static func capture(in root: NSView) {
        guard let responder = root.window?.firstResponder,
              controls(in: root).contains(where: { $0 is SettingsSectionButton }) else { return }
        guard let control = controls(in: root).first(where: { $0 === responder || ($0 as? NSControl)?.currentEditor() === responder }),
              let id = control.identifier?.rawValue, id.hasPrefix("settings-") else { return }
        UserDefaults.standard.set(id, forKey: "settings.focus")
        if let text = (control as? NSControl)?.currentEditor() as? NSTextView {
            UserDefaults.standard.set(NSStringFromRange(text.selectedRange()), forKey: "settings.selection." + id)
        }
    }
    @discardableResult static func restore(in root: NSView) -> Bool {
        guard !root.isHiddenOrHasHiddenAncestor, let window = root.window, window.attachedSheet == nil,
              let id = UserDefaults.standard.string(forKey: "settings.focus"),
              let control = controls(in: root).first(where: { $0.identifier?.rawValue == id && !$0.isHiddenOrHasHiddenAncestor && ($0 as? NSControl)?.isEnabled != false }) else { return false }
        window.makeFirstResponder(control)
        if let text = (control as? NSControl)?.currentEditor() as? NSTextView,
           let saved = UserDefaults.standard.string(forKey: "settings.selection." + id) {
            let range = NSRangeFromString(saved)
            let start = min(range.location, text.string.utf16.count)
            text.setSelectedRange(NSRange(location: start, length: min(range.length, text.string.utf16.count - start)))
        }
        return true
    }
}
