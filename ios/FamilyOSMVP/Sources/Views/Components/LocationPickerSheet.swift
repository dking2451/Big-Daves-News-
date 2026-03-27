import MapKit
import SwiftUI

/// In-app place search (MapKit). Prefer this over leaving for Apple Maps so the chosen place returns to the form.
struct LocationPickerSheet: View {
    @Binding var selectedAddress: String
    /// When MapKit returns a coordinate-backed match, passes it so the caller can store lat/lon for directions.
    var onResolvedPick: ((LocationResolutionService.ResolvedPlace?) -> Void)? = nil
    @Environment(\.dismiss) private var dismiss

    @State private var query = ""
    @State private var results: [LocationSearchRow] = []
    @State private var isSearching = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    TextField("Search address or place name", text: $query)
                        .textContentType(.fullStreetAddress)
                        .submitLabel(.search)
                        .onSubmit { Task { await search() } }

                    Button {
                        Task { await search() }
                    } label: {
                        if isSearching {
                            HStack {
                                ProgressView()
                                Text("Searching…")
                            }
                        } else {
                            Label("Search", systemImage: "magnifyingglass")
                        }
                    }
                    .disabled(query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSearching)
                }

                if !results.isEmpty {
                    Section("Results") {
                        ForEach(results) { row in
                            Button {
                                applySelection(row)
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(row.primaryText)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(.primary)
                                    if let sub = row.secondaryText {
                                        Text(sub)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Choose location")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private func applySelection(_ row: LocationSearchRow) {
        let formatted = LocationResolutionService.formattedAddress(for: row.mapItem)
        selectedAddress = formatted.isEmpty ? row.primaryText : formatted
        onResolvedPick?(LocationResolutionService.resolvedPlace(from: row.mapItem))
        dismiss()
    }

    private func search() async {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return }
        isSearching = true
        defer { isSearching = false }

        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = q
        request.resultTypes = [.address, .pointOfInterest]

        do {
            let response = try await MKLocalSearch(request: request).start()
            results = response.mapItems.prefix(20).map(LocationSearchRow.init(mapItem:))
        } catch {
            results = []
        }
    }
}

private struct LocationSearchRow: Identifiable {
    let id: String
    let mapItem: MKMapItem
    let primaryText: String
    let secondaryText: String?

    init(mapItem: MKMapItem) {
        self.mapItem = mapItem
        let p = mapItem.placemark
        let c = p.coordinate
        if let name = mapItem.name, !name.isEmpty {
            primaryText = name
            let sub = [p.subThoroughfare, p.thoroughfare, p.locality]
                .compactMap { $0 }
                .joined(separator: " ")
            secondaryText = sub.isEmpty ? p.title : sub
        } else if let title = p.title, !title.isEmpty {
            primaryText = title
            secondaryText = nil
        } else {
            primaryText = "Unknown place"
            secondaryText = nil
        }
        id = "\(primaryText)|\(c.latitude)|\(c.longitude)"
    }
}
