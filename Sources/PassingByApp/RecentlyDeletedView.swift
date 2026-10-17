import AppKit
import SwiftUI
import PassingByCore

extension DeletedItem {
    var title: String {
        switch content {
        case .note(let note): note.title.isEmpty ? "Untitled Note" : note.title
        case .task(let task): task.title
        case .appointment(let appointment): appointment.title
        }
    }

    var kind: String {
        switch content {
        case .note: "Note"
        case .task: "To-do"
        case .appointment: "Appointment"
        }
    }

    var preview: String {
        switch content {
        case .note(let note): note.contentMarkdown
        case .task(let task): task.taskDescription
        case .appointment(let appointment): appointment.itemDescription
        }
    }

    func detail(in workspace: Workspace) -> String {
        let categoryID: UUID?
        let status: String
        switch content {
        case .note(let note): categoryID = note.labelID; status = "Markdown Note"
        case .task(let task): categoryID = task.labelID; status = task.completedAt == nil ? "Open To-do" : "Completed To-do"
        case .appointment(let appointment):
            categoryID = appointment.labelID
            status = appointment.date.formatted(date: .abbreviated, time: .omitted)
        }
        let category = workspace.labels.first { $0.id == categoryID }?.name ?? "Uncategorized"
        return status + " · " + category
    }
}

@MainActor private final class RecoverySelection: ObservableObject {
    @Published var selection: UUID?
    @Published var notice = ""
    @Published var restoreError: String?
}

struct RecentlyDeletedView: View {
    @ObservedObject var state: WorkspaceState
    @Environment(\.dismiss) private var dismiss
    @StateObject private var recovery = RecoverySelection()
    @StateObject private var focus = SettingsFocus()

    private var items: [DeletedItem] {
        state.workspace.recentlyDeleted.filter { !$0.hasExpired(at: Date()) }.sorted {
            $0.deletedAt == $1.deletedAt ? $0.id.uuidString < $1.id.uuidString : $0.deletedAt > $1.deletedAt
        }
    }
    private var selected: DeletedItem? { items.first { $0.id == recovery.selection } }

    var body: some View {
        Group {
            if !state.isLocked {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Recently Deleted").font(.title2.weight(.semibold))
                    Text("Items are permanently removed 30 days after deletion.")
                        .font(.callout).foregroundStyle(.secondary)
                    if items.isEmpty {
                        Text("No recently deleted items.")
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        DeletedItemsTable(items: items, selection: $recovery.selection)
                            .frame(height: 155)
                        Text(selected?.title ?? "Select an item to preview")
                            .font(.headline).lineLimit(1)
                        Text(selected.map { $0.detail(in: state.workspace) } ?? " ")
                            .font(.caption).foregroundStyle(.secondary)
                        DeletedItemPreview(text: selected?.preview ?? "", isNote: selected?.kind == "Note")
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    Text(recovery.notice).font(.callout).foregroundStyle(.secondary).lineLimit(1)
                        .help(recovery.notice).frame(height: 18).accessibilityLabel(recovery.notice)
                    HStack {
                        SettingsButton(title: "Restore", id: "settings-030-deleted-restore", enabled: selected != nil && !state.isLocked) { restore() }
                            .disabled(selected == nil || state.isLocked)
                        Spacer()
                        SettingsButton(title: "Done", id: "settings-040-deleted-done", isDefault: true) { dismiss() }
                    }
                }
                .padding(24)
            }
        }
        .frame(width: 600, height: 520)
        .background(SettingsKeyLoop(request: focus.request, requestedID: focus.requestedID))
        .onAppear {
            recovery.selection = items.first?.id
            focus.focus(items.isEmpty ? "settings-040-deleted-done" : "settings-010-deleted-list")
        }
        .onExitCommand { dismiss() }
        .alert("Could Not Restore Item", isPresented: Binding(get: { recovery.restoreError != nil }, set: { if !$0 { recovery.restoreError = nil } })) {
            Button("OK") { recovery.restoreError = nil }
        } message: { Text(recovery.restoreError ?? "The item is still available in Recently Deleted. Try again.") }
    }

    private func restore() {
        guard let item = selected else { return }
        let index = items.firstIndex { $0.id == item.id } ?? 0
        do {
            if try state.restoreDeletedItem(item.id) {
                switch item.content {
                case .note: recovery.notice = "Restored “\(item.title)” to Notes."
                case .task(let task): recovery.notice = task.completedAt == nil ? "Restored “\(item.title)” to To-dos." : "Restored to To-dos. Turn on Show Completed To-dos to see it."
                case .appointment(let appointment): recovery.notice = state.workspace.isPassed(appointment) ? "Restored to Appointments. Turn on Show past to see it." : "Restored “\(item.title)” to Appointments."
                }
            } else {
                state.refresh()
                recovery.notice = "This item could not be restored. It may have expired."
            }
            recovery.selection = items.isEmpty ? nil : items[min(index, items.count - 1)].id
            focus.focus(items.isEmpty ? "settings-040-deleted-done" : "settings-010-deleted-list")
        } catch {
            recovery.restoreError = "\(error.localizedDescription)\nThe item remains in Recently Deleted. Try again."
        }
    }
}

struct DeletedItemsTable: NSViewRepresentable {
    let items: [DeletedItem]
    @Binding var selection: UUID?

    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> NSScrollView {
        let table = NSTableView()
        table.identifier = .init("settings-010-deleted-list")
        table.setAccessibilityLabel("Recently deleted items")
        table.headerView = nil
        table.rowHeight = 44
        table.addTableColumn(NSTableColumn(identifier: .init("deleted-item")))
        table.columnAutoresizingStyle = .firstColumnOnlyAutoresizingStyle
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
        let changed = coordinator.parent.items != items
        coordinator.parent = self
        guard let table = scroll.documentView as? NSTableView else { return }
        coordinator.updating = true
        defer { coordinator.updating = false }
        if changed || table.numberOfRows != items.count { table.reloadData() }
        if let index = items.firstIndex(where: { $0.id == selection }) {
            if table.selectedRow != index { table.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false) }
        } else { table.deselectAll(nil) }
    }
    @MainActor final class Coordinator: NSObject, NSTableViewDelegate, NSTableViewDataSource {
        var parent: DeletedItemsTable
        var updating = false
        init(_ parent: DeletedItemsTable) { self.parent = parent }
        func numberOfRows(in tableView: NSTableView) -> Int { parent.items.count }
        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            let item = parent.items[row]
            let field = NSTextField(wrappingLabelWithString: item.title + "\n" + item.kind + " · Deleted " + item.deletedAt.formatted(date: .abbreviated, time: .shortened))
            field.maximumNumberOfLines = 2
            field.lineBreakMode = .byTruncatingTail
            field.font = .systemFont(ofSize: 13)
            field.setAccessibilityLabel(field.stringValue)
            return field
        }
        func tableViewSelectionDidChange(_ notification: Notification) {
            guard !updating, let table = notification.object as? NSTableView else { return }
            parent.selection = parent.items.indices.contains(table.selectedRow) ? parent.items[table.selectedRow].id : nil
        }
    }
}

private struct DeletedItemPreview: NSViewRepresentable {
    let text: String
    let isNote: Bool
    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        let view = scroll.documentView as! NSTextView
        view.identifier = .init("settings-020-deleted-preview")
        view.setAccessibilityLabel("Deleted item content, read only")
        view.isEditable = false
        view.isSelectable = true
        view.isRichText = false
        view.textContainerInset = NSSize(width: 8, height: 8)
        view.autoresizingMask = [.width]
        view.textContainer?.widthTracksTextView = true
        scroll.borderType = .bezelBorder
        return scroll
    }
    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let view = scroll.documentView as? NSTextView else { return }
        if view.string != text {
            view.string = text
            view.setSelectedRange(NSRange(location: 0, length: 0))
            view.scrollRangeToVisible(NSRange(location: 0, length: 0))
        }
        view.font = isNote ? .monospacedSystemFont(ofSize: 13, weight: .regular) : .systemFont(ofSize: 13)
        view.textColor = .labelColor
        view.backgroundColor = .textBackgroundColor
    }
}
