import SwiftUI

@main
@MainActor
struct RealityApp: App {
    @StateObject private var sessionStore = SessionStore.shared

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(sessionStore)
                .preferredColorScheme(.dark)
                .tint(Color.accentColor)
        }
    }
}

struct RootView: View {
    @EnvironmentObject private var store: SessionStore

    var body: some View {
        Group {
            if store.session == nil {
                LoginView()
            } else {
                HomeView()
            }
        }
    }
}
