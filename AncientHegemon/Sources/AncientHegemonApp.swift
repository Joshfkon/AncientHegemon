import SwiftUI

/// Preview build: watch the AI play itself on a schematic map and replay its battles.
/// The real game screens (step 7) will grow from here.
@main
struct AncientHegemonApp: App {
    @State private var session = GameSession()

    var body: some Scene {
        WindowGroup {
            TabView {
                WorldView(session: session)
                    .tabItem { Label("World", systemImage: "globe.europe.africa") }
                BattleListView(session: session)
                    .tabItem { Label("Battles", systemImage: "shield.lefthalf.filled") }
            }
        }
    }
}
