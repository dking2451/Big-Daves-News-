import SwiftUI

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
