import SwiftUI

/// My List tab: same rail layout rhythm as `TVWatchHomeView`, driven by synced profile + `myListItems`.
struct TVMyListView: View {
    @EnvironmentObject private var viewModel: TVWatchHomeViewModel
    var onSelectShow: (TVWatchShowItem) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: TVLayout.sectionGap) {
                if viewModel.myListLoading && viewModel.myListItems.isEmpty && !viewModel.myListIsEmptyPerProfile {
                    ProgressView("Loading My List…")
                        .padding(.top, TVLayout.Spacing.s24 * 5)
                        .frame(maxWidth: .infinity)
                } else if viewModel.myListIsEmptyPerProfile {
                    TVEmptyStateMessage(
                        title: "Your list is empty",
                        subtitle: "Save shows on your iPhone to start watching here."
                    )
                } else if viewModel.myListLoadError != nil, viewModel.myListItems.isEmpty {
                    TVEmptyStateMessage(
                        title: TVShellErrorCopy.title,
                        subtitle: TVShellErrorCopy.subtitle,
                        retryTitle: "Try again",
                        retryAction: { Task { await viewModel.loadMyList() } }
                    )
                } else {
                    if !viewModel.myListStartWatchingRail.isEmpty {
                        TVContentRail(title: "Start Watching", subtitle: nil) {
                            ForEach(viewModel.myListStartWatchingRail) { show in
                                TVPosterCard(show: show, footnote: show.primaryProvider) {
                                    onSelectShow(show)
                                }
                            }
                        }
                    }

                    if !viewModel.myListContinueWatchingRail.isEmpty {
                        TVContentRail(title: "Continue Watching", subtitle: "Pick up where you left off") {
                            ForEach(viewModel.myListContinueWatchingRail) { show in
                                TVPosterCard(show: show, footnote: show.primaryProvider) {
                                    onSelectShow(show)
                                }
                            }
                        }
                    }

                    if !viewModel.myListFromYourListRail.isEmpty {
                        TVContentRail(title: "From Your List", subtitle: "Saved and ready when you are") {
                            ForEach(viewModel.myListFromYourListRail) { show in
                                TVPosterCard(show: show, footnote: show.primaryProvider) {
                                    onSelectShow(show)
                                }
                            }
                        }
                    }

                    if !viewModel.myListFinishedRail.isEmpty {
                        TVContentRail(title: "Finished", subtitle: "Recently finished") {
                            ForEach(viewModel.myListFinishedRail) { show in
                                TVPosterCard(show: show, footnote: show.primaryProvider) {
                                    onSelectShow(show)
                                }
                            }
                        }
                    }
                }

                if let err = viewModel.myListLoadError,
                   !viewModel.myListIsEmptyPerProfile,
                   !viewModel.myListItems.isEmpty
                {
                    Text(err)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, TVLayout.contentGutter)
                }
            }
            .padding(.top, TVLayout.screenTopInset)
        }
        .background(TVLayout.appBackground)
        .task { await viewModel.loadMyList() }
        .onAppear {
            if viewModel.myListItems.isEmpty, !viewModel.myListLoading {
                Task { await viewModel.loadMyList() }
            }
        }
    }
}
