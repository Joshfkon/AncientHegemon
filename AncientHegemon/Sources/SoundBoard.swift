import AVFoundation
import SwiftUI

/// Battle sounds. They mix with the player's music and respect the silent switch, and can be
/// turned off from the replay.
@MainActor
final class SoundBoard {
    static let shared = SoundBoard()

    enum Cue: String, CaseIterable {
        case horn, clash, arrows, victory, defeat, click, drum, coins, wardrums, roar, gallop
    }

    /// Stored under this key in UserDefaults (read by `@AppStorage` in the replay).
    static let enabledKey = "soundOn"
    private var players: [Cue: AVAudioPlayer] = [:]

    private init() {
        try? AVAudioSession.sharedInstance().setCategory(.ambient)
        for cue in Cue.allCases {
            guard let url = Bundle.main.url(forResource: cue.rawValue, withExtension: "wav"),
                  let player = try? AVAudioPlayer(contentsOf: url) else { continue }
            player.prepareToPlay()
            players[cue] = player
        }
    }

    func play(_ cue: Cue, volume: Float = 1) {
        guard UserDefaults.standard.object(forKey: Self.enabledKey) as? Bool ?? true,
              let player = players[cue] else { return }
        player.volume = max(0.1, min(1, volume))
        player.numberOfLoops = 0
        player.currentTime = 0
        player.play()
    }

    /// Plays a cue over and over until `stop` (the war drums while the armies draw up).
    func loop(_ cue: Cue, volume: Float = 1) {
        guard UserDefaults.standard.object(forKey: Self.enabledKey) as? Bool ?? true,
              let player = players[cue], !player.isPlaying else { return }
        player.volume = max(0.1, min(1, volume))
        player.numberOfLoops = -1
        player.currentTime = 0
        player.play()
    }

    /// Fades a cue out.
    func stop(_ cue: Cue, fade: TimeInterval = 0.6) {
        guard let player = players[cue], player.isPlaying else { return }
        player.setVolume(0, fadeDuration: fade)
        DispatchQueue.main.asyncAfter(deadline: .now() + fade) {
            player.stop()
        }
    }
}
