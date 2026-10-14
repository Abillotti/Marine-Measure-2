import SwiftUI

struct RootView: View {
    @AppStorage(SettingsKey.hasOnboarded) private var hasOnboarded = false
    @State private var showSplash = true

    var body: some View {
        ZStack {
            if hasOnboarded {
                MainTabView()
            } else {
                OnboardingView()
            }
            if showSplash {
                SplashView()
                    .transition(.opacity)
                    .zIndex(2)
            }
        }
        .task {
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            withAnimation(.easeOut(duration: 0.45)) { showSplash = false }
        }
    }
}

struct MainTabView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var appState = appState
        TabView(selection: $appState.selectedTab) {
            HomeView()
                .tabItem { Label("Scan", systemImage: "camera.viewfinder") }
                .tag(AppState.Tab.scan)
            JournalView()
                .tabItem { Label("Journal", systemImage: "book.closed.fill") }
                .tag(AppState.Tab.journal)
            SpeciesListView()
                .tabItem { Label("Species", systemImage: "fish.fill") }
                .tag(AppState.Tab.species)
            CommunityView()
                .tabItem { Label("Community", systemImage: "map.fill") }
                .tag(AppState.Tab.community)
            ProfileView()
                .tabItem { Label("Profile", systemImage: "person.crop.circle.fill") }
                .tag(AppState.Tab.profile)
        }
        .sheet(item: Binding(
            get: { appState.pendingBadges.first },
            set: { newValue in
                if newValue == nil, !appState.pendingBadges.isEmpty {
                    appState.pendingBadges.removeFirst()
                }
            })) { badge in
            BadgeCelebrationView(badge: badge)
        }
    }
}
