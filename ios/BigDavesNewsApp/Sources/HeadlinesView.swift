import SwiftUI

@MainActor
final class HeadlinesViewModel: ObservableObject {
    @Published var claims: [Claim] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var selectedCategory = "All"

    var categories: [String] {
        let unique = Set(claims.map(\.category)).sorted()
        return ["All"] + unique
    }

    var filteredClaims: [Claim] {
        guard selectedCategory != "All" else { return claims }
        return claims.filter { $0.category == selectedCategory }
    }

    func refresh() async {
        isLoading = true
        errorMessage = nil
        do {
            claims = try await APIClient.shared.fetchFacts()
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}

struct HeadlinesView: View {
    @StateObject private var vm = HeadlinesViewModel()

    var body: some View {
        NavigationStack {
            Group {
                if vm.isLoading && vm.claims.isEmpty {
                    ProgressView("Loading headlines...")
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 12) {
                            BrandCard {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Category")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Picker("Category", selection: $vm.selectedCategory) {
                                        ForEach(vm.categories, id: \.self) { category in
                                            Text(category).tag(category)
                                        }
                                    }
                                    .pickerStyle(.menu)
                                }
                            }

                            if let error = vm.errorMessage {
                                BrandCard {
                                    Text(error)
                                        .foregroundStyle(.red)
                                }
                            }

                            ForEach(vm.filteredClaims) { claim in
                                BrandCard {
                                    VStack(alignment: .leading, spacing: 8) {
                                        if let imageURL = claim.imageURL, let url = URL(string: imageURL) {
                                            AsyncImage(url: url) { phase in
                                                switch phase {
                                                case .success(let image):
                                                    image
                                                        .resizable()
                                                        .scaledToFill()
                                                        .frame(height: 170)
                                                        .clipped()
                                                        .cornerRadius(10)
                                                case .failure:
                                                    EmptyView()
                                                case .empty:
                                                    ProgressView().frame(height: 40)
                                                @unknown default:
                                                    EmptyView()
                                                }
                                            }
                                        }
                                        Text(claim.text)
                                            .font(.headline)
                                        Text("\(claim.category) • \(claim.subtopic)")
                                            .font(.subheadline)
                                            .foregroundStyle(.secondary)
                                        if let first = claim.evidence.first, let url = URL(string: first.articleURL) {
                                            Link(first.sourceName, destination: url)
                                                .font(.caption)
                                        }
                                    }
                                }
                            }
                        }
                    }
                    .padding(.horizontal)
                    .refreshable {
                        await vm.refresh()
                    }
                }
            }
            .navigationTitle("Headlines")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await vm.refresh() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                }
            }
        }
        .task {
            await vm.refresh()
        }
    }
}
