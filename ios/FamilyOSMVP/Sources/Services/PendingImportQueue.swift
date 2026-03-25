import Foundation

enum PendingImportKind: String, Codable {
    case text
    case image
}

struct PendingImportItem: Identifiable, Codable, Equatable {
    var id: UUID
    var kind: PendingImportKind
    var createdAt: Date

    /// For `.text`
    var text: String?
    /// For `.image` stored in app documents
    var imageFileName: String?
}

enum PendingImportQueue {
    private static let queueFileName = "pending_imports.json"
    private static let imageFolderName = "pending_import_images"

    static func enqueueText(_ text: String) throws -> PendingImportItem {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw PendingImportQueueError.emptyContent }

        var items = load()
        let item = PendingImportItem(
            id: UUID(),
            kind: .text,
            createdAt: Date(),
            text: trimmed,
            imageFileName: nil
        )
        items.insert(item, at: 0)
        save(items)
        return item
    }

    static func enqueueImageJPEG(_ data: Data) throws -> PendingImportItem {
        guard !data.isEmpty else { throw PendingImportQueueError.emptyContent }

        let itemID = UUID()
        let fileName = "import_\(itemID.uuidString).jpg"
        let folder = try imageFolderURL()
        let fileURL = folder.appendingPathComponent(fileName)

        try data.write(to: fileURL, options: .atomic)

        var items = load()
        let item = PendingImportItem(
            id: itemID,
            kind: .image,
            createdAt: Date(),
            text: nil,
            imageFileName: fileName
        )
        items.insert(item, at: 0)
        save(items)
        return item
    }

    static func load() -> [PendingImportItem] {
        guard let url = queueFileURL else { return [] }
        guard let data = try? Data(contentsOf: url) else { return [] }
        guard let decoded = try? JSONDecoder().decode([PendingImportItem].self, from: data) else { return [] }
        return decoded
    }

    static func remove(_ id: UUID) {
        var items = load()
        guard let idx = items.firstIndex(where: { $0.id == id }) else { return }
        let item = items[idx]
        items.remove(at: idx)
        save(items)

        if item.kind == .image, let imageFileName = item.imageFileName {
            let folder = imageFolderURLIfPossible()
            let fileURL = folder?.appendingPathComponent(imageFileName)
            if let fileURL, FileManager.default.fileExists(atPath: fileURL.path) {
                try? FileManager.default.removeItem(at: fileURL)
            }
        }
    }

    static var queueFileURL: URL? {
        guard let base = applicationSupportURL else { return nil }
        return base.appendingPathComponent(queueFileName)
    }

    private static var applicationSupportURL: URL? {
        do {
            let base = try FileManager.default.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            return base
        } catch {
            return nil
        }
    }

    private static func imageFolderURL() throws -> URL {
        guard let base = applicationSupportURL else { throw PendingImportQueueError.appSupportUnavailable }
        let folder = base.appendingPathComponent(imageFolderName, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    private static func imageFolderURLIfPossible() -> URL? {
        guard let base = applicationSupportURL else { return nil }
        let folder = base.appendingPathComponent(imageFolderName, isDirectory: true)
        return FileManager.default.fileExists(atPath: folder.path) ? folder : nil
    }

    private static func save(_ items: [PendingImportItem]) {
        guard let url = queueFileURL else { return }
        do {
            let data = try JSONEncoder().encode(items)
            try data.write(to: url, options: .atomic)
        } catch {
            // Best-effort; queue is optional.
        }
    }
}

enum PendingImportQueueError: LocalizedError {
    case emptyContent
    case appSupportUnavailable

    var errorDescription: String? {
        switch self {
        case .emptyContent:
            return "Nothing to save."
        case .appSupportUnavailable:
            return "Storage unavailable."
        }
    }
}

