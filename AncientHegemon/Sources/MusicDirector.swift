import AVFoundation
import HegemonCore

/// The soundtrack (Josh: "a soundtrack like CIV"). Original pieces rendered by
/// tools/make_music.py: a title theme, one for each realm, and a war theme. The director picks
/// what suits the moment and crossfades between pieces: your realm's theme in peace, with the
/// title and other realms' themes between; the war theme while you fight or are besieged; every
/// realm in turn while you watch. It stays silent while other audio is playing and respects the
/// silent switch, and can be turned off from the ⋯ menu.
@MainActor
final class MusicDirector: NSObject, AVAudioPlayerDelegate {
    static let shared = MusicDirector()

    enum Mood: Equatable {
        case title, realm(CivilizationID), war(CivilizationID), watching
    }

    /// Stored under this key in UserDefaults (read by `@AppStorage` in the menu).
    static let enabledKey = "musicOn"
    static var enabled: Bool { UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true }

    private var mood: Mood?
    private var player: AVAudioPlayer?
    private var playing: String?
    /// Pieces played in this mood, so the next one varies.
    private var count = 0
    private let volume: Float = 0.5
    private static let realms = ["greece", "egypt", "italia", "mesopotamia"]

    /// Sets the mood. A new mood fades in its first piece; the same mood carries on.
    func set(_ mood: Mood) {
        guard mood != self.mood else { return }
        let wasWar: Bool = { if case .war = self.mood { true } else { false } }()
        self.mood = mood
        count = 0
        // Back from war to the same realm: let the war theme play out its phrase, then move on.
        if wasWar, case .realm = mood { return }
        next(fade: 2.5)
    }

    /// The menu's switch.
    func enabledChanged() {
        if Self.enabled { next(fade: 1.5) } else { fadeOut(1) }
    }

    private func piece(for mood: Mood) -> String {
        defer { count += 1 }
        switch mood {
        case .title: return "title"
        case let .war(civ): return count % 3 == 2 ? civ : "war"
        case .watching: return Self.realms[count % Self.realms.count]
        case let .realm(civ):
            // Home, the age's theme, home again, then a neighbour's air.
            let others = Self.realms.filter { $0 != civ }
            return [civ, "title", civ, others[(count / 4) % others.count]][count % 4]
        }
    }

    private func next(fade: TimeInterval) {
        guard Self.enabled, let mood else { return }
        // Someone's listening to their own music or a podcast: keep out of the way.
        if AVAudioSession.sharedInstance().secondaryAudioShouldBeSilencedHint { return }
        let name = piece(for: mood)
        guard let url = Bundle.main.url(forResource: name, withExtension: "m4a"),
              let incoming = try? AVAudioPlayer(contentsOf: url) else { return }
        fadeOut(fade)
        incoming.delegate = self
        incoming.volume = 0
        incoming.prepareToPlay()
        incoming.play()
        incoming.setVolume(volume, fadeDuration: fade)
        player = incoming
        playing = name
    }

    private func fadeOut(_ fade: TimeInterval) {
        guard let old = player else { return }
        old.delegate = nil
        old.setVolume(0, fadeDuration: fade)
        DispatchQueue.main.asyncAfter(deadline: .now() + fade + 0.1) { old.stop() }
        player = nil
        playing = nil
    }

    nonisolated func audioPlayerDidFinishPlaying(_ finished: AVAudioPlayer, successfully flag: Bool) {
        // A breath of silence between pieces, as between movements.
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(4))
            guard self.player === finished else { return }
            self.next(fade: 0.5)
        }
    }
}
