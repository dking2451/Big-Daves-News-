import UIKit
import UniformTypeIdentifiers

/// Bridges `NSExtensionContext` into `@Sendable` async continuations (the type is not `Sendable`).
private final class ExtensionContextContinuationBox: @unchecked Sendable {
    let context: NSExtensionContext
    init(_ context: NSExtensionContext) { self.context = context }
}

/// Share Extension: prefers **real image data** (Photos / Messages photo / screenshot), then text / URLs.
/// Messages often supplies a `file:///…/Attachments/…/photo.png` string as “text” before the image provider; taking text first breaks OCR.
final class ShareViewController: UIViewController {
    private let statusLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.textAlignment = .center
        label.numberOfLines = 0
        label.font = .preferredFont(forTextStyle: .body)
        label.textColor = .label
        return label
    }()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        statusLabel.text = "Preparing import…"
        view.addSubview(statusLabel)
        NSLayoutConstraint.activate([
            statusLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            statusLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            statusLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor),
        ])
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        Task { await importSharedContent() }
    }

    @MainActor
    private func importSharedContent() async {
        guard let context = extensionContext else {
            finishWithError("Share extension is unavailable.")
            return
        }

        let items = (context.inputItems as? [NSExtensionItem]) ?? []
        var providers: [NSItemProvider] = []
        for item in items {
            if let attachments = item.attachments {
                providers.append(contentsOf: attachments)
            }
        }

        guard !providers.isEmpty else {
            finishWithError("Nothing to import.")
            return
        }

        // 1) Images first — avoids Messages handing us only a sandbox file path as “text”.
        for provider in providers {
            guard let typeId = bestImageTypeIdentifier(for: provider) else { continue }
            if let image = await loadUIImage(from: provider, typeIdentifier: typeId),
               let data = image.jpegData(compressionQuality: 0.9) {
                do {
                    try ShareHandoff.writeImageJPEG(data)
                    await notifyThenOpenHostApp(context: context)
                } catch {
                    finishWithError("Could not save the image. \(error.localizedDescription)")
                }
                return
            }
        }

        // 2) Plain / rich text (but not a lone local image path — treat that as image)
        if let textProvider = providers.first(where: {
            $0.hasItemConformingToTypeIdentifier(UTType.plainText.identifier)
                || $0.hasItemConformingToTypeIdentifier(UTType.text.identifier)
        }), let text = await loadString(from: textProvider, types: [UTType.plainText, UTType.text]) {
            if let jpeg = jpegDataIfLocalImageFileReference(text) {
                do {
                    try ShareHandoff.writeImageJPEG(jpeg)
                    await notifyThenOpenHostApp(context: context)
                } catch {
                    finishWithError("Could not save the image. \(error.localizedDescription)")
                }
                return
            }

            do {
                try ShareHandoff.writeText(text)
                await notifyThenOpenHostApp(context: context)
            } catch let error as ShareHandoffError {
                if case .appGroupUnavailable = error {
                    await notifyThenOpenHostApp(context: context, url: fallbackImportURL(text: text))
                } else {
                    finishWithError(error.localizedDescription)
                }
            } catch {
                finishWithError(error.localizedDescription)
            }
            return
        }

        // 3) Web URL as text (e.g. Safari) — skip file URLs (handled above as image when applicable)
        if let urlProvider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.url.identifier) }),
           let url = await loadURL(from: urlProvider) {
            if url.isFileURL, let jpeg = jpegDataIfLocalImageFileURL(url) {
                do {
                    try ShareHandoff.writeImageJPEG(jpeg)
                    await notifyThenOpenHostApp(context: context)
                } catch {
                    finishWithError("Could not save the image. \(error.localizedDescription)")
                }
                return
            }

            do {
                try ShareHandoff.writeText(url.absoluteString)
                await notifyThenOpenHostApp(context: context)
            } catch let error as ShareHandoffError {
                if case .appGroupUnavailable = error {
                    await notifyThenOpenHostApp(context: context, url: fallbackImportURL(text: url.absoluteString))
                } else {
                    finishWithError(error.localizedDescription)
                }
            } catch {
                finishWithError(error.localizedDescription)
            }
            return
        }

        finishWithError("Could not read the shared content.")
    }

    private func bestImageTypeIdentifier(for provider: NSItemProvider) -> String? {
        let candidates = [
            UTType.image.identifier,
            UTType.jpeg.identifier,
            UTType.png.identifier,
            UTType.heic.identifier,
            UTType.gif.identifier,
            UTType.webP.identifier,
        ]
        return candidates.first { provider.hasItemConformingToTypeIdentifier($0) }
    }

    private func loadUIImage(from provider: NSItemProvider, typeIdentifier: String) async -> UIImage? {
        await withCheckedContinuation { continuation in
            provider.loadItem(forTypeIdentifier: typeIdentifier, options: nil) { item, _ in
                if let image = item as? UIImage {
                    continuation.resume(returning: image)
                    return
                }
                if let url = item as? URL {
                    if let data = try? Data(contentsOf: url), let image = UIImage(data: data) {
                        continuation.resume(returning: image)
                    } else {
                        continuation.resume(returning: nil)
                    }
                    return
                }
                if let data = item as? Data, let image = UIImage(data: data) {
                    continuation.resume(returning: image)
                    return
                }
                continuation.resume(returning: nil)
            }
        }
    }

    /// Messages sometimes shares only a `file:///…/photo.png` string; load bytes from that path when possible.
    private func jpegDataIfLocalImageFileReference(_ raw: String) -> Data? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = solitaryFileURL(from: trimmed), url.isFileURL else { return nil }
        return jpegDataIfLocalImageFileURL(url)
    }

    private func jpegDataIfLocalImageFileURL(_ url: URL) -> Data? {
        guard url.isFileURL else { return nil }
        let ext = url.pathExtension.lowercased()
        let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "heic", "heif", "gif", "webp", "tif", "tiff", "bmp"]
        guard imageExtensions.contains(ext) else { return nil }
        guard let data = try? Data(contentsOf: url), let image = UIImage(data: data) else { return nil }
        return image.jpegData(compressionQuality: 0.9)
    }

    /// Single-line or single URL string that’s only a file URL.
    private func solitaryFileURL(from text: String) -> URL? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.range(of: "\n") != nil { return nil }
        if let url = URL(string: trimmed), url.scheme == "file" { return url }
        return nil
    }

    private func loadString(from provider: NSItemProvider, types: [UTType]) async -> String? {
        for ut in types {
            let id = ut.identifier
            guard provider.hasItemConformingToTypeIdentifier(id) else { continue }
            let value: String? = await withCheckedContinuation { continuation in
                provider.loadItem(forTypeIdentifier: id, options: nil) { item, _ in
                    if let string = item as? String {
                        continuation.resume(returning: string)
                        return
                    }
                    if let data = item as? Data, let string = String(data: data, encoding: .utf8) {
                        continuation.resume(returning: string)
                        return
                    }
                    if let url = item as? URL, let string = try? String(contentsOf: url) {
                        continuation.resume(returning: string)
                        return
                    }
                    continuation.resume(returning: nil)
                }
            }
            if let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return value }
        }
        return nil
    }

    private func loadURL(from provider: NSItemProvider) async -> URL? {
        await withCheckedContinuation { continuation in
            provider.loadItem(forTypeIdentifier: UTType.url.identifier, options: nil) { item, _ in
                if let url = item as? URL {
                    continuation.resume(returning: url)
                } else if let string = item as? String, let url = URL(string: string) {
                    continuation.resume(returning: url)
                } else {
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    @MainActor
    private func notifyThenOpenHostApp(context: NSExtensionContext) async {
        await ShareImportNotifier.scheduleImportReadyNotification()
        await openHostAppThenComplete(context: context)
    }

    @MainActor
    private func notifyThenOpenHostApp(context: NSExtensionContext, url: URL) async {
        await ShareImportNotifier.scheduleImportReadyNotification()
        await openHostAppThenComplete(context: context, url: url)
    }

    @MainActor
    private func openHostAppThenComplete(context: NSExtensionContext) async {
        guard let url = URL(string: "familyosmvp://import") else {
            finishWithError("Could not open Family OS.")
            return
        }
        await openHostAppThenComplete(context: context, url: url)
    }

    @MainActor
    private func openHostAppThenComplete(context: NSExtensionContext, url: URL) async {
        let contextBox = ExtensionContextContinuationBox(context)
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            contextBox.context.open(url) { _ in
                contextBox.context.completeRequest(returningItems: [], completionHandler: { _ in
                    continuation.resume()
                })
            }
        }
    }

    /// Fallback when App Groups are unavailable: pass shared text via URL query.
    /// This is only for text; images still require App Groups.
    private func fallbackImportURL(text: String) -> URL {
        let maxChars = 6000
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count <= maxChars else {
            return URL(string: "familyosmvp://import")!
        }

        let b64 = Data(trimmed.utf8).base64EncodedString()
        let urlSafe = b64
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")

        var components = URLComponents(string: "familyosmvp://import")!
        components.queryItems = [URLQueryItem(name: "text", value: urlSafe)]
        return components.url ?? URL(string: "familyosmvp://import")!
    }

    @MainActor
    private func finishWithError(_ message: String) {
        statusLabel.text = message
        statusLabel.textColor = .secondaryLabel

        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setTitle("Close", for: .normal)
        button.titleLabel?.font = .preferredFont(forTextStyle: .headline)
        button.addAction(UIAction { [weak self] _ in
            let error = NSError(domain: "FamilyOSMVPShareExtension", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
            self?.extensionContext?.cancelRequest(withError: error)
        }, for: .touchUpInside)
        view.addSubview(button)

        NSLayoutConstraint.activate([
            button.topAnchor.constraint(equalTo: statusLabel.bottomAnchor, constant: 16),
            button.centerXAnchor.constraint(equalTo: view.centerXAnchor),
        ])
    }
}
