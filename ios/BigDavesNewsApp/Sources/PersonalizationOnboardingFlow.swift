import SwiftUI

/// Swipeable personalization: Welcome → Genres → Streaming → Sports leagues → Sports teams → Done.
struct PersonalizationOnboardingFlow: View {
    @ObservedObject var viewModel: PersonalizationOnboardingViewModel
    @Binding var isPresented: Bool

    var body: some View {
        TabView(selection: $viewModel.step) {
            welcomePage
                .tag(PersonalizationOnboardingViewModel.Step.welcome)

            genresPage
                .tag(PersonalizationOnboardingViewModel.Step.genres)

            streamingPage
                .tag(PersonalizationOnboardingViewModel.Step.streaming)

            sportsLeaguesPage
                .tag(PersonalizationOnboardingViewModel.Step.sportsLeagues)

            sportsTeamsPage
                .tag(PersonalizationOnboardingViewModel.Step.sportsTeams)

            completionPage
                .tag(PersonalizationOnboardingViewModel.Step.done)
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .animation(.easeInOut(duration: 0.28), value: viewModel.step)
    }

    // MARK: - Pages

    private var welcomePage: some View {
        OnboardingScreenLayout(
            title: "Make Big Dave’s News yours",
            subtitle: "We’ll personalize what to watch, what’s happening, and what matters to you.",
            showsProgress: true,
            currentStep: 0,
            totalSteps: viewModel.totalSteps,
            primaryTitle: "Get Started",
            secondaryTitle: "Skip",
            onPrimary: { viewModel.goToNext() },
            onSecondary: {
                viewModel.finishWithoutSaving()
                AppNavigationState.shared.routeToFirstPersonalizedExperience()
                isPresented = false
            }
        ) {
            EmptyView()
        }
    }

    private var genresPage: some View {
        OnboardingScreenLayout(
            title: "What do you like to watch?",
            subtitle: "Pick all that apply — you can change this anytime in Settings.",
            currentStep: 1,
            totalSteps: viewModel.totalSteps,
            primaryTitle: "Continue",
            secondaryTitle: "Skip",
            onPrimary: { viewModel.goToNext() },
            onSecondary: { viewModel.goToNext() }
        ) {
            OnboardingGenreCardGrid(
                genres: UserPreferencesCatalog.onboardingGenres,
                isSelected: { viewModel.isGenreSelected($0) },
                toggle: { viewModel.toggleGenre(displayName: $0) }
            )
        }
    }

    private var streamingPage: some View {
        OnboardingScreenLayout(
            title: "Which apps do you use?",
            subtitle: "We use this to rank Watch picks and match streaming links.",
            currentStep: 2,
            totalSteps: viewModel.totalSteps,
            primaryTitle: "Continue",
            secondaryTitle: "Skip",
            onPrimary: { viewModel.goToNext() },
            onSecondary: { viewModel.goToNext() }
        ) {
            OnboardingStreamingCardGrid(
                providers: UserPreferencesCatalog.onboardingStreamingProviders,
                isSelected: { viewModel.isProviderSelected($0) },
                toggle: { viewModel.toggleProvider(displayName: $0) }
            )
        }
    }

    private var sportsLeaguesPage: some View {
        OnboardingScreenLayout(
            title: "Which leagues matter to you?",
            subtitle: "We’ll prioritize scores and stories for what you choose — or skip both sports steps.",
            currentStep: 3,
            totalSteps: viewModel.totalSteps,
            primaryTitle: "Continue",
            secondaryTitle: "Skip sports",
            onPrimary: { viewModel.goToNext() },
            onSecondary: { viewModel.skipSportsToCompletion() }
        ) {
            LeagueOnboardingSelectionView(
                leagues: SportsFavoritesCatalog.leagues,
                featuredLeagues: SportsFavoritesCatalog.featuredLeagueOrder,
                categories: SportsFavoritesCatalog.leagueCategories,
                displayTitle: { SportsFavoritesCatalog.displayTitle(for: $0) },
                isSelected: { viewModel.isLeagueSelected($0) },
                toggle: { viewModel.toggleLeague(displayName: $0) }
            )
        }
    }

    private var sportsTeamsPage: some View {
        OnboardingScreenLayout(
            title: "Pick your teams",
            subtitle: "Large catalogs — search works great. Leagues you chose above are listed first.",
            currentStep: 4,
            totalSteps: viewModel.totalSteps,
            primaryTitle: "Continue",
            secondaryTitle: "Skip",
            onPrimary: { viewModel.goToNext() },
            onSecondary: { viewModel.goToNext() }
        ) {
            TeamOnboardingSelectionView(
                leagues: viewModel.prioritizedLeaguesForTeamPicker(allLeagues: SportsFavoritesCatalog.leagues),
                teamsForLeague: { SportsFavoritesCatalog.teams(for: $0) },
                displayTitle: { SportsFavoritesCatalog.displayTitle(for: $0) },
                isTeamSelected: { viewModel.isTeamSelected($0) },
                toggleTeam: { viewModel.toggleTeam(displayName: $0) },
                selectedCountInLeague: { viewModel.selectedTeamCount(forLeague: $0) }
            )
        }
    }

    private var completionPage: some View {
        OnboardingScreenLayout(
            title: "You’re all set",
            subtitle: "We’ll build your daily Brief and tonight’s picks using what you shared — no account needed.",
            currentStep: 5,
            totalSteps: viewModel.totalSteps,
            primaryTitle: "Start Exploring",
            secondaryTitle: nil,
            onPrimary: {
                viewModel.completeAndPersist()
                AppNavigationState.shared.openWatchTonightPick()
                isPresented = false
            },
            onSecondary: nil
        ) {
            VStack(alignment: .leading, spacing: 12) {
                Label("Watch & Tonight’s picks", systemImage: "play.tv.fill")
                Label("Sports lineups", systemImage: "sportscourt.fill")
                Label("Your Brief", systemImage: "sunrise.fill")
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .padding(.top, 8)
        }
    }
}

// MARK: - Container (owns ViewModel)

struct PersonalizationOnboardingContainer: View {
    @Binding var isPresented: Bool
    @StateObject private var viewModel = PersonalizationOnboardingViewModel()

    var body: some View {
        PersonalizationOnboardingFlow(viewModel: viewModel, isPresented: $isPresented)
            .onAppear {
                viewModel.syncFromExistingPrefs()
            }
    }
}

#if DEBUG
#Preview {
    Text("Preview")
        .sheet(isPresented: .constant(true)) {
            PersonalizationOnboardingContainer(isPresented: .constant(true))
        }
}
#endif
