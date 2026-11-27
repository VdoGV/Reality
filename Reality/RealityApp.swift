import SwiftUI

@main
@MainActor
struct RealityApp: App {
    @StateObject private var sessionStore = SessionStore.shared

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(sessionStore)
                .tint(Color.accentColor)
        }
    }
}

struct RootView: View {
    var body: some View {
        MainTabView()
    }
}
