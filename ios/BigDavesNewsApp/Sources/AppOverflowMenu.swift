import SwiftUI

struct AppOverflowMenu: View {
    @State private var showSettings = false
    @State private var showHelp = false

    var body: some View {
        Menu {
            Button {
                showSettings = true
            } label: {
                Label("Settings", systemImage: "gearshape")
            }
            Button {
                showHelp = true
            } label: {
                Label("Help", systemImage: "questionmark.circle")
            }
        } label: {
            Image(systemName: "ellipsis.circle")
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
        .sheet(isPresented: $showHelp) {
            AppHelpView()
        }
    }
}

private struct AppHelpView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("Quick Tips") {
                    Label("Use Watch thumbs up/down to personalize recommendations.", systemImage: "hand.thumbsup")
                    Label("Use Brief for a fast morning snapshot.", systemImage: "sunrise")
                    Label("Tap refresh on any tab for the latest data.", systemImage: "arrow.clockwise")
                }
                Section("Need Support?") {
                    Text("If something looks off, send a screenshot and what device/version you used.")
                        .font(.subheadline)
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
