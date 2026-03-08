import SwiftUI

struct WatchView: View {
    @State private var shows: [WatchShowItem] = []
    @State private var isLoading = false
    @State private var errorMessage = ""

    var body: some View {
        NavigationStack {
            Group {
                if isLoading && shows.isEmpty {
                    ProgressView("Loading trending shows...")
                } else if !errorMessage.isEmpty && shows.isEmpty {
                    VStack(spacing: 12) {
                        Text(errorMessage)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                        Button("Retry") {
                            Task { await refresh() }
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .padding()
                } else {
                    ScrollView {
                        LazyVStack(spacing: 14) {
                            ForEach(shows) { show in
                                WatchShowCard(show: show)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                    }
                    .refreshable { await refresh() }
                }
            }
            .navigationTitle("What To Watch")
            .task {
                if shows.isEmpty {
                    await refresh()
                }
            }
        }
    }

    private func refresh() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let list = try await APIClient.shared.fetchWatchShows(limit: 20)
            await MainActor.run {
                self.shows = list
                self.errorMessage = ""
            }
        } catch {
            await MainActor.run {
                if self.shows.isEmpty {
                    self.errorMessage = "Could not load trending shows right now."
                }
            }
        }
    }
}

private struct WatchShowCard: View {
    let show: WatchShowItem

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            AsyncImage(url: URL(string: show.posterURL)) { phase in
                switch phase {
                case .empty:
                    ZStack {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color(.secondarySystemFill))
                        ProgressView()
                    }
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                case .failure:
                    ZStack {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color(.secondarySystemFill))
                        Image(systemName: "tv")
                            .foregroundStyle(.secondary)
                    }
                @unknown default:
                    Color(.secondarySystemFill)
                }
            }
            .frame(width: 86, height: 126)
            .clipShape(RoundedRectangle(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top) {
                    Text(show.title)
                        .font(.headline)
                        .lineLimit(2)
                    Spacer()
                    Text(String(format: "%.0f", show.trendScore))
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.blue.opacity(0.15))
                        .foregroundStyle(.blue)
                        .clipShape(Capsule())
                }

                HStack(spacing: 8) {
                    if let badge = releaseBadge(releaseDate: show.releaseDate) {
                        Text(badge)
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 4)
                            .background(Color.orange.opacity(0.18))
                            .foregroundStyle(.orange)
                            .clipShape(Capsule())
                    }
                    Text(show.seasonEpisodeStatus)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Text(show.synopsis)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(show.providers, id: \.self) { provider in
                            Text(provider)
                                .font(.caption2.weight(.medium))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color(.tertiarySystemFill))
                                .clipShape(Capsule())
                        }
                    }
                }
            }
        }
        .padding(12)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func releaseBadge(releaseDate: String) -> String? {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        guard let date = formatter.date(from: releaseDate) else { return nil }
        let start = Calendar.current.startOfDay(for: Date())
        let diff = Calendar.current.dateComponents([.day], from: start, to: date).day ?? 0
        if diff < -14 { return nil }
        if diff <= 0 { return "New" }
        if diff <= 7 { return "This Week" }
        return "Upcoming"
    }
}
