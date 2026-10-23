import SwiftUI

/// Pick a civilization and play it against the AI empires, on the painted board.
@main
struct AncientHegemonApp: App {
    @State private var session: GameSession
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

    init() {
        // The Store says which expansions are owned; their empires join new games.
        let store = Store.shared
        let session = GameSession()
        _session = State(initialValue: session)
        session.setExpansions(store.owned)
        store.onChange = { session.setExpansions($0) }
        // Under the Store tests, StoreKit starts after their test session is set up.
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil { store.start() }
    }
}
