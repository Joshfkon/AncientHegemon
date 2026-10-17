/// SplitMix64: small, fast, and fully reproducible across platforms.
///
/// All randomness in the engine goes through this generator, stored in `GameState`, so the same
/// state plus the same commands always produce the same result. Never use `Int.random(in:)`
/// without passing `using: &state.rng`, and never use `SystemRandomNumberGenerator` in the engine.
public struct SeededRNG: RandomNumberGenerator, Codable, Sendable, Equatable {
    public private(set) var state: UInt64

    public init(seed: UInt64) {
        state = seed
    }

    public mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
