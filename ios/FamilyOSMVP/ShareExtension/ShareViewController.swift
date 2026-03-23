import UIKit
import UniformTypeIdentifiers

/// Bridges `NSExtensionContext` into `@Sendable` async continuations (the type is not `Sendable`).
private final class ExtensionContextContinuationBox: @unchecked Sendable {
    let context: NSExtensionContext
    init(_ context: NSExtensionContext) { self.context = context }
}

/// Share Extension: **text first**, then **one image**. Writes into App Group via `ShareHandoff`, opens host app.
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

        // 1) Shared text (Messages / Notes / Mail / selected text)
        if let textProvider = providers.first(where: {
            $0.hasItemConformingToTypeIdentifier(UTType.plainText.identifier)
                || $0.hasItemConformingToTypeIdentifier(UTType.text.identifier)
        }), let text = await loadString(from: textProvider, types: [UTType.plainText, UTType.text]) {
            do {
                try ShareHandoff.writeText(text)
                await openHostAppThenComplete(context: context)
            } catch {
                finishWithError(error.localizedDescription)
            }
            return
        }

        // 2) URL as text (e.g. Safari)
        if let urlProvider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.url.identifier) }),
           let url = await loadURL(from: urlProvider) {
            do {
                try ShareHandoff.writeText(url.absoluteString)
                await openHostAppThenComplete(context: context)
            } catch {
                finishWithError(error.localizedDescription)
            }
            return
        }

        // 3) Single image (Photos / screenshot)
        if let imageProvider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.image.identifier) }),
           let image = await loadUIImage(from: imageProvider),
           let data = image.jpegData(compressionQuality: 0.9) {
            do {
                try ShareHandoff.writeImageJPEG(data)
                await openHostAppThenComplete(context: context)
            } catch {
                finishWithError("Could not save the image. \(error.localizedDescription)")
            }
            return
        }

        finishWithError("Could not read the shared content.")
    }

    private func loadUIImage(from provider: NSItemProvider) async -> UIImage? {
        await withCheckedContinuation { continuation in
            provider.loadItem(forTypeIdentifier: UTType.image.identifier, options: nil) { item, _ in
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
    private func openHostAppThenComplete(context: NSExtensionContext) async {
        guard let url = URL(string: "familyosmvp://import") else {
            finishWithError("Could not open Family OS.")
            return
        }

        let contextBox = ExtensionContextContinuationBox(context)
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            contextBox.context.open(url) { _ in
                contextBox.context.completeRequest(returningItems: [], completionHandler: { _ in
                    continuation.resume()
                })
            }
        }
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
