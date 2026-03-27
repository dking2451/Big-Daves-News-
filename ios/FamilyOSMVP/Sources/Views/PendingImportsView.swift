import SwiftUI

struct PendingImportsView: View {
    @EnvironmentObject private var store: EventStore
    @State private var pendingItems: [PendingImportItem] = []
    @State private var itemToProcess: PendingImportItem?

    var body: some View {
        List {
            if pendingItems.isEmpty {
                ContentUnavailableView(
                    "No pending imports",
                    systemImage: "tray.and.arrow.down",
                    description: Text("When you share a message and choose “Save for later”, it appears here.")
                )
            } else {
                Section("Pending") {
                    ForEach(pendingItems) { item in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(alignment: .top, spacing: 10) {
                                Image(systemName: item.kind == .text ? "text.bubble" : "photo")
                                    .font(.body.weight(.semibold))
                                    .foregroundStyle(FamilyTheme.accent)

                                VStack(alignment: .leading, spacing: 4) {
                                    Text(item.kind == .text ? "Shared text" : "Shared image")
                                        .font(.subheadline.weight(.semibold))
                                    Text(item.createdAt, style: .date)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }

                                Spacer()

                                Menu {
                                    Button("Delete", role: .destructive) {
                                        PendingImportQueue.remove(item.id)
                                        reload()
                                    }
                                } label: {
                                    Image(systemName: "ellipsis.circle")
                                        .foregroundStyle(.secondary)
                                }
                                .accessibilityLabel("More actions")
                            }

                            if item.kind == .text, let t = item.text {
                                Text(t)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(3)
                            } else if item.kind == .image {
                                Text("Image stored for later OCR.")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }

                            HStack(spacing: 12) {
                                Button {
                                    itemToProcess = item
                                } label: {
                                    Label("Extract & review", systemImage: "sparkles")
                                }
                                .buttonStyle(.borderedProminent)

                                Button {
                                    PendingImportQueue.remove(item.id)
                                    reload()
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                                .buttonStyle(.bordered)
                                .tint(.secondary)
                            }
                            .padding(.top, 2)
                        }
                        .padding(.vertical, 6)
                    }
                }
            }
        }
        .navigationTitle("Pending Imports")
        .onAppear(perform: reload)
        .sheet(item: $itemToProcess) { item in
            PendingImportReviewSheet(item: item)
                .environmentObject(store)
        }
    }

    private func reload() {
        pendingItems = PendingImportQueue.load()
    }
}

