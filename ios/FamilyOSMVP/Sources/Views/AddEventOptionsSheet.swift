import SwiftUI
import UIKit

/// Lightweight bottom sheet: single entry point for all add / import paths.
struct AddEventOptionsSheet: View {
    let onQuickAdd: () -> Void
    let onPasteText: () -> Void
    let onUploadImage: () -> Void
    let onPasteFromClipboard: () -> Void

    @State private var clipboardPreview: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Add Event")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, 12)

            Divider()

            if let clipboardPreview {
                clipboardRow(preview: clipboardPreview)
                Divider()
            }

            optionRow(
                title: "Quick Add",
                systemImage: "bolt.fill",
                action: onQuickAdd
            )

            Divider()

            optionRow(
                title: "Paste Text",
                systemImage: "doc.on.clipboard",
                action: onPasteText
            )

            Divider()

            optionRow(
                title: "Scan / Upload",
                systemImage: "camera.viewfinder",
                action: onUploadImage
            )
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear {
            refreshClipboardPreview()
        }
    }

    private func clipboardRow(preview: String) -> some View {
        Button {
            onPasteFromClipboard()
        } label: {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: "doc.on.clipboard")
                    .font(.body.weight(.medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 28, alignment: .center)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Paste from Clipboard")
                        .font(.body.weight(.medium))
                        .foregroundStyle(.primary)
                    Text(preview)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .padding(.vertical, 12)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Paste from Clipboard")
    }

    private func optionRow(title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: systemImage)
                    .font(.body.weight(.medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 28, alignment: .center)
                Text(title)
                    .font(.body.weight(.medium))
                    .foregroundStyle(.primary)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .padding(.vertical, 14)
        }
        .buttonStyle(.plain)
    }

    private func refreshClipboardPreview() {
        guard let raw = UIPasteboard.general.string else {
            clipboardPreview = nil
            return
        }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            clipboardPreview = nil
            return
        }
        let maxLen = 50
        if trimmed.count <= maxLen {
            clipboardPreview = trimmed
        } else {
            let idx = trimmed.index(trimmed.startIndex, offsetBy: maxLen)
            clipboardPreview = String(trimmed[..<idx]) + "…"
        }
    }
}
