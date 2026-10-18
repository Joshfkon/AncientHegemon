import SwiftUI

/// Pick a civilization and play it against the AI empires, on the painted board.
@main
struct AncientHegemonApp: App {
    @State private var session = GameSession()

    var body: some Scene {
        WindowGroup {
            if session.started {
                GameScreen(session: session)
            } else {
                CivPickerView(session: session)
            }
        }
    }
}
