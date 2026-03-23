import SwiftUI
import UIKit

/// App-wide overflow: **Saved** (cross-tab) + **Settings**. Same control on every main tab—no extra tab bar item.
struct AppOverflowMenu: View {
    @Environment(\.tonightModeActive) private var tonightModeActive
    @State private var showSettings = false
    @State private var showSaved = false

    /// When set (Sports tab), adds **How Sports works** to this menu.
    var onHowSportsWorks: (() -> Void)? = nil

    var body: some View {
    Menu {
            Button {
                showSaved = true
            } label: {
                Label("Saved", systemImage: "bookmark.fill")
            }
            .accessibilityHint("Articles and shows you saved")

            if tonightModeActive {
                Button {
                    AppNavigationState.shared.openWatchTonightPick()
                } label: {
                    Label("What should I watch tonight?", systemImage: "sparkles.tv.fill")
                }
                .accessibilityHint("Opens Watch and scrolls to Tonight’s pick.")
            }

            if let onHowSportsWorks {
                Button {
                    onHowSportsWorks()
                } label: {
                    Label("How Sports works", systemImage: "info.circle")
                }
            }

            Button {
                showSettings = true
            } label: {
                Label("Settings", systemImage: "gearshape.fill")
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.body.weight(.semibold))
                .foregroundStyle(.primary)
        }
        .accessibilityLabel("More")
        .sheet(isPresented: $showSaved) {
            SavedHubView()
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
    }
}

struct AppHelpButton: View {
    @State private var showHelp = false

    var body: some View {
        Button {
            showHelp = true
        } label: {
            Image(systemName: "questionmark.circle")
                .font(.body.weight(.semibold))
                .foregroundStyle(.primary)
        }
        .accessibilityLabel("Help")
        .sheet(isPresented: $showHelp) {
            AppHelpView()
        }
    }
}

struct AppHelpView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "-"
    }

    private var buildNumber: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "-"
    }

    private var feedbackURL: URL? {
        let subject = "Big Daves News iOS Feedback"
        let body = """
        What happened:

        Steps to reproduce:

        App version: \(appVersion) (\(buildNumber))
        iOS: \(UIDevice.current.systemVersion)
        Device: \(UIDevice.current.model)
        """
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = "daveking5916@gmail.com"
        components.queryItems = [
            URLQueryItem(name: "subject", value: subject),
            URLQueryItem(name: "body", value: body)
        ]
        return components.url
    }

    var body: some View {
        NavigationStack {
            List {
                Section("How to Use the App") {
                    Label("Saved: use the ••• menu (top right) for articles and shows you bookmarked from any tab.", systemImage: "bookmark")
                    Label("Headlines: read top stories and local news quickly.", systemImage: "newspaper")
                    Label("Watch: use save/seen/thumbs to improve recommendations.", systemImage: "play.tv")
                    Label("Brief: get your daily snapshot in under a minute.", systemImage: "sunrise")
                    Label("Sports: see live games and what starts soon.", systemImage: "sportscourt")
                    Label("Weather: view alerts, forecast, and radar.", systemImage: "cloud.sun")
                    Label("Business: track major indexes and tickers.", systemImage: "chart.line.uptrend.xyaxis")
                }

                Section("Feedback") {
                    Button {
                        guard let url = feedbackURL else { return }
                        openURL(url)
                    } label: {
                        Label("Submit Feedback", systemImage: "envelope")
                    }
                    Text("Include a screenshot and the steps you took so we can fix issues faster.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Onboarding") {
                    Button {
                        dismiss()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                            PersonalizationOnboardingReplay.trigger()
                        }
                    } label: {
                        Label("Replay personalization onboarding", systemImage: "arrow.counterclockwise.circle")
                    }
                    Text("Re-run the setup flow. Your current preferences load as a starting point.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Help")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
