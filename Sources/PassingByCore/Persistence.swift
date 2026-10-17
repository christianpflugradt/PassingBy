import Foundation
import Darwin

public enum WorkspacePersistenceError: LocalizedError {
    case couldNotFindApplicationSupport
    case readFailed(Error)
    case decodeFailed(Error)
    case writeFailed(Error)
    case migrationFailed(Error)

    public var errorDescription: String? {
        switch self {
        case .couldNotFindApplicationSupport: "The Application Support folder could not be found."
        case .readFailed(let error): "Passing By could not read your workspace: \(error.localizedDescription)"
        case .decodeFailed(let error): "Passing By could not open your workspace data: \(error.localizedDescription)"
        case .writeFailed(let error): "Passing By could not save your changes: \(error.localizedDescription)"
        case .migrationFailed(let error): "Passing By could not move your existing workspace: \(error.localizedDescription)"
        }
    }
}

public enum AppointmentImportError: LocalizedError {
    case invalidRows
    case unknownCategory
    case locked

    public var errorDescription: String? {
        switch self {
        case .invalidRows: "Correct all TSV errors before importing."
        case .unknownCategory: "The selected Category no longer exists. Choose another Category."
        case .locked: "Unlock Passing By before importing Appointments."
        }
    }
}

public struct WorkspacePersistence {
    public let url: URL
    public init(url: URL) { self.url = url }

    public static func standard() throws -> WorkspacePersistence {
        guard let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            throw WorkspacePersistenceError.couldNotFindApplicationSupport
        }
        return try standard(applicationSupportDirectory: directory)
    }

    // The directory argument also lets tests exercise migration without touching user data.
    public static func standard(applicationSupportDirectory: URL) throws -> WorkspacePersistence {
        let canonical = applicationSupportDirectory.appendingPathComponent("Passing By", isDirectory: true)
        let legacy = applicationSupportDirectory.appendingPathComponent("Passing by", isDirectory: true)
        let workspace = canonical.appendingPathComponent("workspace.json")
        let oldWorkspace = legacy.appendingPathComponent("workspace.json")
        let files = FileManager.default
        do {
            guard try exists(applicationSupportDirectory) else { return WorkspacePersistence(url: workspace) }
            let entries = try files.contentsOfDirectory(at: applicationSupportDirectory, includingPropertiesForKeys: nil)
            let hasCanonicalDirectory = entries.contains { $0.lastPathComponent == "Passing By" }
            let hasLegacyDirectory = entries.contains { $0.lastPathComponent == "Passing by" }
            // A canonical workspace always wins, including when the legacy copy remains.
            if hasCanonicalDirectory {
                if try exists(workspace) { return WorkspacePersistence(url: workspace) }
            }
            guard hasLegacyDirectory else { return WorkspacePersistence(url: workspace) }

            let oldContents = try files.contentsOfDirectory(at: legacy, includingPropertiesForKeys: nil)
            let oldWorkspaceExists = try exists(oldWorkspace)
            // Backups or other files alone must never become an apparently empty workspace.
            if !oldContents.isEmpty && !oldWorkspaceExists {
                throw CocoaError(.fileReadNoSuchFile, userInfo: [NSFilePathErrorKey: oldWorkspace.path])
            }
            if !hasCanonicalDirectory {
                // rename(2) also handles case-only changes on case-insensitive volumes.
                // It publishes the complete directory in one atomic operation.
                if rename(legacy.path, canonical.path) != 0 {
                    throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
                }
            } else {
                // A directory without workspace.json may already contain data. Copy into it
                // without replacing anything, and publish workspace.json only after all peers.
                for item in oldContents where item.lastPathComponent != "workspace.json" {
                    let destination = canonical.appendingPathComponent(item.lastPathComponent)
                    if try exists(destination) {
                        throw CocoaError(.fileWriteFileExists, userInfo: [NSFilePathErrorKey: destination.path])
                    }
                    try files.copyItem(at: item, to: destination)
                }
                if oldWorkspaceExists { try files.copyItem(at: oldWorkspace, to: workspace) }
            }
            return WorkspacePersistence(url: workspace)
        } catch {
            throw WorkspacePersistenceError.migrationFailed(error)
        }
    }

    private static func exists(_ url: URL) throws -> Bool {
        var details = stat()
        if lstat(url.path, &details) == 0 { return true }
        if errno == ENOENT { return false }
        throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
    }

    private func fileExists() throws -> Bool {
        do { return try Self.exists(url) }
        catch { throw WorkspacePersistenceError.readFailed(error) }
    }

    public func load() throws -> Workspace {
        if try !fileExists() { return Workspace() }
        let data: Data
        do { data = try Data(contentsOf: url) }
        catch { throw WorkspacePersistenceError.readFailed(error) }
        do { return try JSONDecoder().decode(Workspace.self, from: data) }
        catch { throw WorkspacePersistenceError.decodeFailed(error) }
    }

    public func save(_ workspace: Workspace) throws {
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(workspace)
            if try fileExists() {
                // Preserve the last readable snapshot before replacing it.
                let oldData = try Data(contentsOf: url)
                _ = try JSONDecoder().decode(Workspace.self, from: oldData)
                let backup = url.appendingPathExtension("backup")
                try oldData.write(to: backup, options: .atomic)
            }
            try data.write(to: url, options: .atomic)
        } catch { throw WorkspacePersistenceError.writeFailed(error) }
    }
}

public final class AppStore {
    public private(set) var workspace: Workspace
    public var persistenceError: String?
    public var onPersistenceError: ((String) -> Void)?
    private let persistence: WorkspacePersistence

    public init(persistence: WorkspacePersistence? = nil) throws {
        self.persistence = try persistence ?? .standard()
        self.workspace = try self.persistence.load()
        let old = workspace
        if workspace.statisticsStartedAt == nil { workspace.statisticsStartedAt = Date() }
        workspace.purgeExpired()
        if workspace != old { save() }
        evaluateScheduledTodos()
    }

    public func change(_ mutation: (inout Workspace) -> Void) {
        mutation(&workspace)
        cleanUp(save: false)
        save()
    }

    @discardableResult public func restoreDeletedItem(_ id: UUID, at now: Date = Date(), calendar: Calendar = .current) throws -> Bool {
        var candidate = workspace
        guard candidate.restoreDeletedItem(id, at: now, calendar: calendar) else { return false }
        candidate.purgeExpired(now: now, calendar: calendar)
        do { try persistence.save(candidate) }
        catch {
            persistenceError = error.localizedDescription
            onPersistenceError?(error.localizedDescription)
            throw error
        }
        workspace = candidate
        persistenceError = nil
        return true
    }

    public func importAppointments(_ parsed: AppointmentTSVImport, categoryID: UUID?) throws {
        guard parsed.canImport else { throw AppointmentImportError.invalidRows }
        guard categoryID == nil || workspace.labels.contains(where: { $0.id == categoryID }) else { throw AppointmentImportError.unknownCategory }
        var candidate = workspace
        candidate.dates.append(contentsOf: parsed.rows.map {
            DateItem(title: $0.title, date: $0.date, itemDescription: $0.description, labelID: categoryID)
        })
        do { try persistence.save(candidate) }
        catch {
            persistenceError = error.localizedDescription
            onPersistenceError?(error.localizedDescription)
            throw error
        }
        workspace = candidate
        persistenceError = nil
    }

    public func cleanUp(save: Bool = true) {
        let old = workspace
        workspace.purgeExpired()
        if save && old != workspace { self.save() }
    }

    @discardableResult public func evaluateScheduledTodos(at now: Date = Date(), calendar: Calendar = .current) -> Int {
        var candidate = workspace
        let created = candidate.evaluateScheduledTodos(at: now, calendar: calendar)
        guard candidate != workspace else { return 0 }
        do { try persistence.save(candidate) }
        catch {
            persistenceError = error.localizedDescription
            onPersistenceError?(error.localizedDescription)
            return 0
        }
        workspace = candidate
        persistenceError = nil
        return created
    }

    @discardableResult public func flush() -> Bool {
        do { try persistence.save(workspace); persistenceError = nil }
        catch { persistenceError = error.localizedDescription; onPersistenceError?(error.localizedDescription) }
        return persistenceError == nil
    }
    private func save() { _ = flush() }
}
