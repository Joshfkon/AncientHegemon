import Foundation
import HegemonCore

/// Everything needed to pick a game back up: the engine's state plus the app's chronicle.
struct SavedGame: Codable {
    /// Bumped when this format changes; older saves are ignored rather than misread.
    static let currentVersion = 1

    var version = SavedGame.currentVersion
    var human: CivilizationID
    var seed: UInt64
    var state: GameState
    var log: [LogLine]
    var battles: [BattleEntry]
    var savedAt: Date
}

/// One autosave slot in Application Support.
enum SaveStore {
    private static var url: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("AncientHegemon", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("autosave.json")
    }

    static func save(_ game: SavedGame) {
        do {
            let data = try JSONEncoder().encode(game)
            try data.write(to: url, options: .atomic)
        } catch {
            print("Autosave failed: \(error)")
        }
    }

    /// The saved game, if there is one this version of the game can still play.
    static func load(for engine: Engine) -> SavedGame? {
        guard let data = try? Data(contentsOf: url),
              let game = try? JSONDecoder().decode(SavedGame.self, from: data),
              game.version == SavedGame.currentVersion,
              game.state.mapVersion == engine.map.version,
              game.state.rulesVersion == engine.rules.version,
              game.state.winner == nil else { return nil }
        return game
    }

    static func delete() {
        try? FileManager.default.removeItem(at: url)
    }
}
