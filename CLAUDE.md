# Ancient Hegemon

Native iPhone strategy game adapted from Josh's board game.

- Start here: `docs/HANDOFF.md` (current state, decisions, build order), then `docs/DESIGN.md`.
- Rules engine: `HegemonCore/` Swift package. Run `swift test` there before pushing.
- Map data: `HegemonCore/Sources/HegemonCore/Resources/map.json`. After editing, run
  `python3 tools/validate_map.py`.
- The engine must stay deterministic: all randomness goes through the seeded RNG in game state.
- Root-level `*.cs` files are a 2021 Unity prototype; nothing is ported from them.
