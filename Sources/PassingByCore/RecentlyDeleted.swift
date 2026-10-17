import Foundation

public struct DeletedItem: Codable, Identifiable, Equatable {
    public enum Content: Codable, Equatable {
        case note(Note), task(Task), appointment(DateItem)
    }

    public let id: UUID
    public let content: Content
    public let deletedAt: Date
    public let originalIndex: Int

    init(content: Content, deletedAt: Date, originalIndex: Int) {
        id = UUID()
        self.content = content
        self.deletedAt = deletedAt
        self.originalIndex = originalIndex
    }

    public func hasExpired(at now: Date, calendar: Calendar = .current) -> Bool {
        guard let expiry = calendar.date(byAdding: .day, value: 30, to: deletedAt) else { return false }
        return now >= expiry
    }
}

extension Workspace {
    public mutating func deleteNote(_ id: UUID, at now: Date = Date()) {
        guard let index = notes.firstIndex(where: { $0.id == id }) else { return }
        recentlyDeleted.append(DeletedItem(content: .note(notes.remove(at: index)), deletedAt: now, originalIndex: index))
    }

    public mutating func deleteTask(_ id: UUID, at now: Date = Date()) {
        guard let index = tasks.firstIndex(where: { $0.id == id }) else { return }
        recentlyDeleted.append(DeletedItem(content: .task(tasks.remove(at: index)), deletedAt: now, originalIndex: index))
    }

    public mutating func deleteAppointment(_ id: UUID, at now: Date = Date()) {
        guard let index = dates.firstIndex(where: { $0.id == id }) else { return }
        recentlyDeleted.append(DeletedItem(content: .appointment(dates.remove(at: index)), deletedAt: now, originalIndex: index))
    }

    @discardableResult public mutating func restoreDeletedItem(_ id: UUID, at now: Date = Date(), calendar: Calendar = .current) -> Bool {
        guard let index = recentlyDeleted.firstIndex(where: { $0.id == id }),
              !recentlyDeleted[index].hasExpired(at: now, calendar: calendar) else { return false }
        let deleted = recentlyDeleted[index]
        switch deleted.content {
        case .note(var note):
            guard !notes.contains(where: { $0.id == note.id }) else { return false }
            if !labels.contains(where: { $0.id == note.labelID }) { note.labelID = nil }
            notes.insert(note, at: min(max(0, deleted.originalIndex), notes.count))
        case .task(var task):
            guard !tasks.contains(where: { $0.id == task.id }) else { return false }
            if !labels.contains(where: { $0.id == task.labelID }) { task.labelID = nil }
            task.restoredAt = now
            tasks.insert(task, at: min(max(0, deleted.originalIndex), tasks.count))
        case .appointment(var appointment):
            guard !dates.contains(where: { $0.id == appointment.id }) else { return false }
            if !labels.contains(where: { $0.id == appointment.labelID }) { appointment.labelID = nil }
            appointment.restoredAt = now
            dates.insert(appointment, at: min(max(0, deleted.originalIndex), dates.count))
        }
        recentlyDeleted.remove(at: index)
        return true
    }
}
