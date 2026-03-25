import SwiftUI
import UIKit

struct MainTabView: View {
    var body: some View {
        TabView {
            NavigationStack {
                HomeView()
            }
            .familyBrandToolbarIcon()
            .tabItem {
                Label("Home", systemImage: "house")
            }

            NavigationStack {
                UpcomingEventsView()
            }
            .familyBrandToolbarIcon()
            .tabItem {
                Label("Upcoming", systemImage: "calendar")
            }

            NavigationStack {
                SettingsView()
            }
            .familyBrandToolbarIcon()
            .tabItem {
                Label("Settings", systemImage: "gearshape")
            }
        }
        .tint(.blue)
    }
}

private struct FamilyBrandToolbarIconModifier: ViewModifier {
    func body(content: Content) -> some View {
        content.toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                familyBrandIcon
                    .accessibilityLabel("Family OS")
            }
        }
    }

    @ViewBuilder
    private var familyBrandIcon: some View {
        if let image = resolvedIconImage {
            Image(uiImage: image)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(width: 22, height: 22)
                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
        } else {
            Image(systemName: "house.and.flag.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.blue)
        }
    }

    private var resolvedIconImage: UIImage? {
        UIImage(named: "AppIcon")
            ?? UIImage(named: "icon-60")
            ?? UIImage(named: "icon-120")
            ?? UIImage(named: "icon-180")
    }
}

extension View {
    func familyBrandToolbarIcon() -> some View {
        modifier(FamilyBrandToolbarIconModifier())
    }
}
