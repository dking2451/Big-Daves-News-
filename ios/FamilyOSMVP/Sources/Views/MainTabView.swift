import SwiftUI
import UIKit

struct MainTabView: View {
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                HomeView()
            }
            .familyBrandToolbarIcon()
            .tabItem {
                Label("Home", systemImage: "house")
            }
            .tag(0)

            NavigationStack {
                UpcomingEventsView()
            }
            .tabItem {
                Label("Upcoming", systemImage: "calendar")
            }
            .tag(1)

            NavigationStack {
                SettingsView()
            }
            .familyBrandToolbarIcon()
            .tabItem {
                Label("Settings", systemImage: "gearshape")
            }
            .tag(2)
        }
        .tint(FamilyTheme.accent)
        .onReceive(NotificationCenter.default.publisher(for: .familyOSNavigateToHome)) { _ in
            selectedTab = 0
        }
    }
}

private struct FamilyBrandToolbarIconModifier: ViewModifier {
    func body(content: Content) -> some View {
        content.toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: 10) {
                    if let pendingCount = pendingCount, pendingCount > 0 {
                        NavigationLink(destination: PendingImportsView()) {
                            pendingIcon(count: pendingCount)
                                .accessibilityLabel("\(pendingCount) pending imports")
                        }
                        .buttonStyle(.plain)
                    }

                    familyBrandIcon
                        .accessibilityLabel("Family OS")
                }
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
                .foregroundStyle(FamilyTheme.accent)
        }
    }

    private var pendingCount: Int? {
        PendingImportQueue.load().count
    }

    private func pendingIcon(count: Int) -> some View {
        ZStack(alignment: .topTrailing) {
            Image(systemName: "tray.and.arrow.down.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(FamilyTheme.accent)
                .frame(width: 24, height: 24)

            Text("\(min(count, 99))")
                .font(.caption2.weight(.bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 7)
                .padding(.vertical, 2)
                .background(Circle().fill(Color.red))
                .offset(x: 10, y: -8)
                .accessibilityHidden(true)
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
