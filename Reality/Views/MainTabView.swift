import SwiftUI

enum MainTab: Hashable {
    case home
    case profile
    case library
    case settings
}

struct MainTabView: View {
    @State private var tab: MainTab = .home

    var body: some View {
        TabView(selection: $tab) {
            NavigationStack {
                HomeTabView(selectedTab: $tab)
                    .realityNavigationDestinations()
            }
            .tabItem { Label("主页", systemImage: "house.fill") }
            .tag(MainTab.home)

            NavigationStack {
                ProfileView()
            }
            .tabItem { Label("我的", systemImage: "person.crop.circle.fill") }
            .tag(MainTab.profile)

            NavigationStack {
                MediaLibraryTab()
                    .realityNavigationDestinations()
            }
            .tabItem { Label("媒体库", systemImage: "rectangle.stack.fill") }
            .tag(MainTab.library)

            NavigationStack {
                SettingsView()
            }
            .tabItem { Label("设置", systemImage: "gearshape.fill") }
            .tag(MainTab.settings)
        }
    }
}

extension View {
    func realityNavigationDestinations() -> some View {
        self
            .navigationDestination(for: ItemRoute.self) { route in
                DetailView(itemId: route.id)
            }
            .navigationDestination(for: LibraryRoute.self) { route in
                LibraryView(libraryId: route.id, title: route.name)
            }
    }
}
