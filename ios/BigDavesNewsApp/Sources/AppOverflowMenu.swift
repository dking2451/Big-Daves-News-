import SwiftUI
import UIKit

struct AppOverflowMenu: View {
    @State private var showSettings = false

    var body: some View {
        Button {
            showSettings = true
        } label: {
            Image(systemName: "gearshape")
                .font(.body.weight(.semibold))
                .foregroundStyle(AppTheme.primary)
        }
        .accessibilityLabel("Settings")
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
                .foregroundStyle(AppTheme.primary)
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
                    Label("Headlines: read top stories and local news quickly.", systemImage: "newspaper")
                    Label("Watch: use save/seen/thumbs to improve recommendations.", systemImage: "play.tv")
                    Label("Brief: get your daily snapshot in under a minute.", systemImage: "sunrise")
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
