import SwiftUI

/// Cross-app hub for saved articles and saved Watch shows (same APIs as Brief).
/// Self-loads on appear so any tab can present it without passing `BriefViewModel` state.
struct SavedHubView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    @State private var savedArticles: [SavedArticleItem] = []
    @State private var savedShows: [WatchShowItem] = []
    @State private var selectedSegment = 0
    @State private var isLoading = true
    @State private var errorMessage: String?

    private let deviceID = WatchDeviceIdentity.current

    var body: some View {
        NavigationStack {
            Group {
                if isLoading && savedArticles.isEmpty && savedShows.isEmpty && errorMessage == nil {
                    ProgressView("Loading saved…")
                        .frame(maxWidth: .infinity, minHeight: 200)
                } else if let errorMessage, savedArticles.isEmpty, savedShows.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "bookmark.slash")
                            .font(.largeTitle)
                            .foregroundStyle(.secondary)
                        Text("Couldn’t load saved")
                            .font(.headline)
                        Text(errorMessage)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                        Button("Try again") {
                            Task { await load() }
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .padding(24)
                    .frame(maxWidth: .infinity)
                } else {
                    List {
                        Picker("Saved Type", selection: $selectedSegment) {
                            Text("Articles").tag(0)
                            Text("Shows").tag(1)
                        }
                        .pickerStyle(.segmented)

                        if selectedSegment == 0 {
                            if savedArticles.isEmpty {
                                Text("No saved articles yet.")
                                    .foregroundStyle(.secondary)
                            } else {
                                ForEach(savedArticles) { item in
                                    Button {
                                        guard let destination = URL(string: item.url) else { return }
                                        openURL(destination)
                                    } label: {
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(item.title)
                                                .font(.subheadline.weight(.semibold))
                                                .lineLimit(2)
                                            Text(item.sourceName)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        } else {
                            if savedShows.isEmpty {
                                Text("No saved shows yet.")
                                    .foregroundStyle(.secondary)
                            } else {
                                ForEach(savedShows) { show in
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(show.title)
                                            .font(.subheadline.weight(.semibold))
                                        Text(show.primaryProvider ?? "Streaming")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    }
                    .refreshable {
                        await load()
                    }
                }
            }
            .navigationTitle("Saved")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .task {
            await load()
        }
    }

    private func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        async let articlesTask: Result<[SavedArticleItem], Error> = {
            do {
                return .success(try await APIClient.shared.fetchSavedArticles(deviceID: deviceID))
            } catch {
                return .failure(error)
            }
        }()

        async let showsTask: Result<[WatchShowItem], Error> = {
            do {
                let r = try await APIClient.shared.fetchWatchShows(
                    limit: 30,
                    minimumCount: 10,
                    deviceID: deviceID,
                    hideSeen: false,
                    onlySaved: true
                )
                return .success(r.items)
            } catch {
                return .failure(error)
            }
        }()

        switch await articlesTask {
        case .success(let items):
            savedArticles = items
        case .failure(let error):
            errorMessage = error.localizedDescription
            savedArticles = []
        }

        switch await showsTask {
        case .success(let items):
            savedShows = items
        case .failure(let error):
            if errorMessage == nil {
                errorMessage = error.localizedDescription
            }
            savedShows = []
        }
    }
}
