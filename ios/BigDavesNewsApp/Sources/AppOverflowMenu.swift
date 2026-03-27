import SwiftUI
import UIKit

/// App-wide overflow: **Saved** (cross-tab) + **Settings**. Same control on every main tab—no extra tab bar item.
struct AppOverflowMenu: View {
    @Environment(\.tonightModeActive) private var tonightModeActive
    @State private var showSettings = false
    @State private var showSaved = false

    /// When set (Sports tab), adds **How Sports works** to this menu.
    var onHowSportsWorks: (() -> Void)? = nil

    /// Watch tab: match Refresh / Help toolbar chrome (one control group).
    var useWatchToolbarChrome: Bool = false

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
            if useWatchToolbarChrome {
                WatchToolbarMenuLabel(systemName: "ellipsis.circle")
            } else {
                AppToolbarIcon(systemName: "ellipsis.circle", role: .neutral)
            }
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

/// Shared copy for Settings and `AppHelpView` so onboarding / feedback footers stay in sync.
enum AppHelpCopy {
    static let feedbackFooter = "Include a screenshot and the steps you took so we can fix issues faster."
    static let onboardingFooter = "Walk through genres, streaming, and sports again. Your current choices load as a starting point; you can change them before saving."
}

enum AppHelpSupport {
    static func feedbackMailURL() -> URL? {
        let appVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "-"
        let buildNumber = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "-"
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
}

struct AppHelpButton: View {
    /// Toolbar (Headlines-style plain icon) vs Watch header bordered pill to match Saved / Filter.
    enum Chrome {
        case toolbarPlain
        case watchHeaderBordered
    }

    var chrome: Chrome = .toolbarPlain

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var showHelp = false

    var body: some View {
        Button {
            showHelp = true
        } label: {
            if chrome == .watchHeaderBordered {
                Image(systemName: "info.circle")
                    .font(.body.weight(.semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.primary)
                    .frame(width: 44, height: 44)
                    .contentShape(Circle())
            } else {
                AppToolbarIcon(systemName: "info.circle", role: .neutral)
            }
        }
        .modifier(AppHelpButtonChromeModifier(chrome: chrome, dynamicTypeSize: dynamicTypeSize))
        .accessibilityLabel("Help")
        .accessibilityHint("Opens help and how to use the app.")
        .sheet(isPresented: $showHelp) {
            AppHelpView()
        }
    }
}

private struct AppHelpButtonChromeModifier: ViewModifier {
    let chrome: AppHelpButton.Chrome
    let dynamicTypeSize: DynamicTypeSize

    func body(content: Content) -> some View {
        switch chrome {
        case .toolbarPlain:
            content.buttonStyle(.borderless)
        case .watchHeaderBordered:
            content
                .buttonStyle(.bordered)
                .tint(.primary)
                .controlSize(dynamicTypeSize >= .accessibility2 ? .large : .regular)
        }
    }
}

struct AppHelpView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    var body: some View {
        NavigationStack {
            List {
                Section("How to Use the App") {
                    Label("Saved (••• menu): bookmarked articles and TV shows from across the app, in one place.", systemImage: "bookmark")
                    Label("Watch: My List, Filter, and Help in the header; save, seen, and thumbs on each card tune recommendations.", systemImage: "play.tv")
                    Label("Headlines: read top stories and local news quickly.", systemImage: "newspaper")
                    Label("Brief: get your daily snapshot in under a minute.", systemImage: "sunrise")
                    Label("Sports: see live games and what starts soon.", systemImage: "sportscourt")
                    Label("Weather: view alerts, forecast, and radar.", systemImage: "cloud.sun")
                    Label("Business: track major indexes and tickers.", systemImage: "chart.line.uptrend.xyaxis")
                }

                Section("Feedback") {
                    Button {
                        guard let url = AppHelpSupport.feedbackMailURL() else { return }
                        openURL(url)
                    } label: {
                        Label("Submit Feedback", systemImage: "envelope")
                    }
                    Text(AppHelpCopy.feedbackFooter)
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
                    Text(AppHelpCopy.onboardingFooter)
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
