import SwiftUI

/// Edit device-local genres, streaming picks, and favorite teams (no account).
struct UserPreferencesEditorView: View {
    @ObservedObject private var prefs = LocalUserPreferences.shared
    @State private var draftTeams: Set<String> = []
    @State private var draftGenres: Set<String> = []
    @State private var draftProviders: Set<String> = []
    @State private var draftLeagues: Set<String> = []

    var body: some View {
        Form {
            Section {
                Text("Saved on this device only. Watch uses this to **rank** recommendations; Sports and Brief boost leagues and teams you pick.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("Favorite genres") {
                genreChips
            }

            Section("Preferred streaming") {
                providerChips
            }

            Section("Favorite leagues") {
                leagueChips
            }

            Section("Favorite teams") {
                teamDisclosureGroups
            }

            Section {
                Button("Clear all preferences", role: .destructive) {
                    prefs.clearAll()
                    syncDraftFromStore()
                }
                .disabled(prefs.isEmpty)
            }
        }
        .navigationTitle("My preferences")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            syncDraftFromStore()
        }
        .onChange(of: draftGenres) { _ in prefs.setFavoriteGenres(draftGenres) }
        .onChange(of: draftProviders) { _ in prefs.setPreferredProviders(draftProviders) }
        .onChange(of: draftLeagues) { _ in prefs.setFavoriteLeagues(draftLeagues) }
        .onChange(of: draftTeams) { _ in prefs.setFavoriteTeams(draftTeams) }
    }

    private var leagueChips: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 88), spacing: 8)], alignment: .leading, spacing: 8) {
            ForEach(SportsFavoritesCatalog.leagues, id: \.self) { league in
                let key = PreferenceNormalization.league(league)
                let selected = draftLeagues.contains(key)
                Button {
                    if selected {
                        draftLeagues.remove(key)
                    } else {
                        draftLeagues.insert(key)
                    }
                } label: {
                    Text(league)
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity)
                        .background(selected ? Color.accentColor.opacity(0.22) : Color(.secondarySystemFill))
                        .foregroundStyle(.primary)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 4)
    }

    private var genreChips: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 8)], alignment: .leading, spacing: 8) {
            ForEach(UserPreferencesCatalog.genres, id: \.self) { genre in
                let key = PreferenceNormalization.genre(genre)
                let selected = draftGenres.contains(key)
                Button {
                    if selected {
                        draftGenres.remove(key)
                    } else {
                        draftGenres.insert(key)
                    }
                } label: {
                    Text(genre)
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity)
                        .background(selected ? Color.accentColor.opacity(0.22) : Color(.secondarySystemFill))
                        .foregroundStyle(.primary)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 4)
    }

    private var providerChips: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 112), spacing: 8)], alignment: .leading, spacing: 8) {
            ForEach(UserPreferencesCatalog.streamingProviders, id: \.self) { name in
                let key = PreferenceNormalization.streamingProvider(name)
                let selected = draftProviders.contains(key)
                Button {
                    if selected {
                        draftProviders.remove(key)
                    } else {
                        draftProviders.insert(key)
                    }
                } label: {
                    Text(name)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(2)
                        .minimumScaleFactor(0.85)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity)
                        .background(selected ? Color.accentColor.opacity(0.22) : Color(.secondarySystemFill))
                        .foregroundStyle(.primary)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 4)
    }

    private var teamDisclosureGroups: some View {
        ForEach(SportsFavoritesCatalog.leagues, id: \.self) { league in
            DisclosureGroup(league) {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 8)], alignment: .leading, spacing: 8) {
                    ForEach(SportsFavoritesCatalog.teams(for: league), id: \.self) { team in
                        let key = PreferenceNormalization.team(team)
                        let selected = draftTeams.contains(key)
                        Button {
                            if selected {
                                draftTeams.remove(key)
                            } else {
                                draftTeams.insert(key)
                            }
                        } label: {
                            Text(team)
                                .font(.caption.weight(.semibold))
                                .lineLimit(2)
                                .multilineTextAlignment(.center)
                                .padding(8)
                                .frame(maxWidth: .infinity)
                                .background(selected ? Color.accentColor.opacity(0.22) : Color(.secondarySystemFill))
                                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 6)
            }
        }
    }

    private func syncDraftFromStore() {
        draftTeams = prefs.favoriteTeamsNormalized
        draftGenres = prefs.favoriteGenresNormalized
        draftProviders = prefs.preferredProvidersNormalized
        draftLeagues = prefs.favoriteLeaguesNormalized
    }
}
