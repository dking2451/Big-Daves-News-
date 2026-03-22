import SwiftUI

/// 5-step, swipeable personalization flow (under ~30s). Persists to `LocalUserPreferences` on completion.
struct PersonalizationOnboardingFlow: View {
    @ObservedObject var viewModel: PersonalizationOnboardingViewModel
    @Binding var isPresented: Bool

    @State private var sportsSegment: SportsOnboardingSegment = .leagues

    private enum SportsOnboardingSegment: Int, CaseIterable {
        case leagues = 0
        case teams = 1
    }

    var body: some View {
        TabView(selection: $viewModel.step) {
            welcomePage
                .tag(PersonalizationOnboardingViewModel.Step.welcome)

            genresPage
                .tag(PersonalizationOnboardingViewModel.Step.genres)

            streamingPage
                .tag(PersonalizationOnboardingViewModel.Step.streaming)

            sportsPage
                .tag(PersonalizationOnboardingViewModel.Step.sports)

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
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 108), spacing: 10)],
                alignment: .leading,
                spacing: 10
            ) {
                ForEach(UserPreferencesCatalog.onboardingGenres, id: \.self) { genre in
                    PreferenceChip(
                        title: genre,
                        systemImage: nil,
                        isSelected: viewModel.isGenreSelected(genre)
                    ) {
                        viewModel.toggleGenre(displayName: genre)
                    }
                }
            }
            .padding(.top, 4)
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
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 112), spacing: 10)],
                alignment: .leading,
                spacing: 10
            ) {
                ForEach(UserPreferencesCatalog.onboardingStreamingProviders, id: \.self) { name in
                    PreferenceChip(
                        title: name,
                        systemImage: "play.rectangle.fill",
                        isSelected: viewModel.isProviderSelected(name)
                    ) {
                        viewModel.toggleProvider(displayName: name)
                    }
                }
            }
            .padding(.top, 4)
        }
    }

    private var sportsPage: some View {
        OnboardingScreenLayout(
            title: "Follow your teams (optional)",
            subtitle: "Choose leagues, teams, both, or neither — Sports and your daily Brief will highlight what you care about.",
            currentStep: 3,
            totalSteps: viewModel.totalSteps,
            primaryTitle: "Continue",
            secondaryTitle: "Skip",
            onPrimary: { viewModel.goToNext() },
            onSecondary: { viewModel.goToNext() }
        ) {
            Picker("Mode", selection: $sportsSegment) {
                Text("Leagues").tag(SportsOnboardingSegment.leagues)
                Text("Teams").tag(SportsOnboardingSegment.teams)
            }
            .pickerStyle(.segmented)
            .padding(.vertical, 4)

            switch sportsSegment {
            case .leagues:
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 100), spacing: 10)],
                    alignment: .leading,
                    spacing: 10
                ) {
                    ForEach(SportsFavoritesCatalog.leagues, id: \.self) { league in
                        PreferenceChip(
                            title: league,
                            systemImage: "sportscourt.fill",
                            isSelected: viewModel.isLeagueSelected(league)
                        ) {
                            viewModel.toggleLeague(displayName: league)
                        }
                    }
                }
            case .teams:
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(SportsFavoritesCatalog.leagues, id: \.self) { league in
                        DisclosureGroup(league) {
                            LazyVGrid(
                                columns: [GridItem(.adaptive(minimum: 130), spacing: 8)],
                                alignment: .leading,
                                spacing: 8
                            ) {
                                ForEach(SportsFavoritesCatalog.teams(for: league), id: \.self) { team in
                                    PreferenceChip(
                                        title: team,
                                        systemImage: nil,
                                        isSelected: viewModel.isTeamSelected(team)
                                    ) {
                                        viewModel.toggleTeam(displayName: team)
                                    }
                                }
                            }
                            .padding(.vertical, 8)
                        }
                    }
                }
            }
        }
    }

    private var completionPage: some View {
        OnboardingScreenLayout(
            title: "You’re all set",
            subtitle: "We’ll build your daily Brief and tonight’s picks using what you shared — no account needed.",
            currentStep: 4,
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
