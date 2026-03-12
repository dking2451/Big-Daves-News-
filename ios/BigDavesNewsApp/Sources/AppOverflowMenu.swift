import SwiftUI

struct AppOverflowMenu: View {
    @State private var showSettings = false

    var body: some View {
        Button {
            showSettings = true
        } label: {
            Image(systemName: "gearshape.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppTheme.primary)
                .padding(8)
                .background(AppTheme.primary.opacity(0.14))
                .clipShape(Circle())
        }
        .accessibilityLabel("Settings")
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
    }
}
