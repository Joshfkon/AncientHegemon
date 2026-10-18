import SwiftUI

/// Pick a civilization and play it against the AI empires, on the painted board.
@main
struct AncientHegemonApp: App {
    @State private var session = GameSession()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            if session.started {
                GameScreen(session: session)
            } else {
                CivPickerView(session: session)
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { session.autosave() }
        }
    }
}
