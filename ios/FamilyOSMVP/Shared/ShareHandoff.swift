import Foundation

/// Minimal App Group handoff: one JSON file (`handoff.json`) + optional `import.jpg` for images.
enum ShareHandoff {
    static let appGroupIdentifier = "group.com.familyos.mvp"
    private static let handoffFileName = "handoff.json"
    private static let imageFileName = "import.jpg"

    enum Payload: Equatable {
        case text(String)
        case image(URL)
    }

    private struct FileDTO: Codable {
        var text: String?
        var image: Bool
    }

    static var containerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier)
    }

    /// Writes a text-only handoff (Phase 1).
    static func writeText(_ string: String) throws {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw ShareHandoffError.emptyContent
        }
        guard let base = containerURL else { throw ShareHandoffError.appGroupUnavailable }
        try resetFiles(in: base)
        let dto = FileDTO(text: trimmed, image: false)
        try write(dto: dto, to: base)
    }

    /// Writes a single JPEG image handoff (Phase 2). Fixed filename; no subfolders.
    static func writeImageJPEG(_ data: Data) throws {
        guard let base = containerURL else { throw ShareHandoffError.appGroupUnavailable }
        try resetFiles(in: base)
        let url = base.appendingPathComponent(imageFileName)
        try data.write(to: url, options: .atomic)
        let dto = FileDTO(text: nil, image: true)
        try write(dto: dto, to: base)
    }

    /// Reads and removes `handoff.json`. If the payload is an image, leaves `import.jpg` until `discardImageIfNeeded`.
    static func consume() -> Payload? {
        guard let base = containerURL else { return nil }
        let jsonURL = base.appendingPathComponent(handoffFileName)
        guard FileManager.default.fileExists(atPath: jsonURL.path) else { return nil }

        guard let data = try? Data(contentsOf: jsonURL) else {
            try? FileManager.default.removeItem(at: jsonURL)
            return nil
        }
        try? FileManager.default.removeItem(at: jsonURL)

        guard let dto = try? JSONDecoder().decode(FileDTO.self, from: data) else { return nil }

        if let t = dto.text?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty {
            return .text(t)
        }
        if dto.image {
            let url = base.appendingPathComponent(imageFileName)
            if FileManager.default.fileExists(atPath: url.path) {
                return .image(url)
            }
        }
        return nil
    }

    static func discardImageIfNeeded(for payload: Payload) {
        if case .image(let url) = payload {
            try? FileManager.default.removeItem(at: url)
        }
    }

    private static func write(dto: FileDTO, to base: URL) throws {
        let data = try JSONEncoder().encode(dto)
        try data.write(to: base.appendingPathComponent(handoffFileName), options: .atomic)
    }

    private static func resetFiles(in base: URL) throws {
        let json = base.appendingPathComponent(handoffFileName)
        if FileManager.default.fileExists(atPath: json.path) {
            try FileManager.default.removeItem(at: json)
        }
        let img = base.appendingPathComponent(imageFileName)
        if FileManager.default.fileExists(atPath: img.path) {
            try FileManager.default.removeItem(at: img)
        }
    }
}

enum ShareHandoffError: LocalizedError {
    case appGroupUnavailable
    case emptyContent

    var errorDescription: String? {
        switch self {
        case .appGroupUnavailable:
            return "App Group storage is not available for `\(ShareHandoff.appGroupIdentifier)`. Make sure App Groups includes this ID for both the app and the Share Extension, then reinstall the app."
        case .emptyContent:
            return "Nothing to share."
        }
    }
}
