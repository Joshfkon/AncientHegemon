# Handoff: Ancient Hegemon iPhone MVP

Context for a new Claude Code session on the Mac mini. Read this, then `docs/DESIGN.md`.

## Where things stand

- **Project**: turn Josh's *Ancient Hegemon* board game (hand-painted Mediterranean map, unit
  cubes, 5×5 battle board, rulebook) into a native iPhone game.
- **Branch**: `claude/charming-fermat-eb6vmf`. Work continues here.
- **Done so far**:
  - **Build step 1 complete**: `HegemonCore` package with typed map models, validated
    `GameMap` loading and adjacency queries, `SeededRNG` (SplitMix64), Codable `GameState`,
    a stub `hegemon-sim` CLI, and 18 passing tests (`swift test` in `HegemonCore/`).
  - **Build step 2 complete**: `rules.json` (unit stats, economy, start), `Engine.apply` with
    `Command`s (`recruit`, `move`, `endTurn`) returning `GameEvent`s, harvest/growth/starvation,
    gold income, capture and elimination. `hegemon-sim [seed] [turns]` runs a placeholder
    land-grab policy and prints a per-civ table. 38 tests. Economy decisions are in the
    DESIGN.md appendix.
  - **Build step 3 complete**: supply network (`Network.swift`: pockets, seat, chokepoint
    holders, sea lanes), per-pocket harvest with out-of-supply attrition, war/peace commands,
    automatic trade routes with chokepoint tolls and resource sharing, bronze stockpile.
    `hegemon-sim [seed] [turns] [--peace]`. 59 tests.
  - **Build step 4 complete** (Josh asked to fold ships into it): `BattleSimulator` (5×5 land
    battles with formations, triangle, terrain, morale, generals, bronze; replay frames) and
    naval auto-resolve; engine battles on contested moves with retreats; generals; formations;
    ships (build, sail, embark, land, naval battles, blockades). 85 tests. Battle and ship rules,
    plus the open formation-balance issue, are in the DESIGN.md appendix.
  - **Build step 5 complete**: `AIPlayer` (AI/), `playAIMatch`, and `hegemon-sim` as the balance
    tool (`swift run -c release hegemon-sim --games 40`, `--personality NAME`, `--trace`,
    `formations`). First balance runs led to native garrisons, starting heartlands,
    supply-route upkeep and a 60% domination victory (all in the DESIGN.md appendix).
  - **Naval AI added** (Josh asked for it before step 6): `AI/NavalAI.swift`. The AI builds
    transports and runs amphibious campaigns. Native garrisons raised to 2 + grain ÷ 3.
    96 tests. Next: build step 6.
  - `docs/DESIGN.md`: game design doc. Sections 11 (MVP scope) and 12 (AI) are the build spec.
  - `HegemonCore/Sources/HegemonCore/Resources/map.json`: the map as data. 40 territories,
    land links (with `river` / `strait` crossings), 12 sea zones, 7 chokepoints, 4 civs.
  - `tools/validate_map.py`: checks the map data. Run it after any map edit:
    `python3 tools/validate_map.py`.
- **Legacy**: `legacy/*.cs` is a 2021 Unity prototype. Nothing is being ported from it.
- **Previous blocker**: the cloud session couldn't install a Swift toolchain. The Mac has Xcode,
  so that's resolved.

## Balance findings (after the naval AI; 40 games, default personalities, shuffled seating)

| Civ | Wins | Eliminated | Avg land at end | Ships built / landings per game |
|---|---|---|---|---|
| Mesopotamia | 47% | 0% | 18.3 | 3.5 / 2.9 |
| Italia | 12% | 0% | 6.3 | 4.2 / 2.6 |
| Egypt | 10% | 0% | 7.2 | 3.2 / 1.6 |
| Greece | 5% | 0% | 4.7 | 4.2 / 2.7 |

Before the naval AI and stronger natives: Mesopotamia 77%, Greece eliminated 90% of the time,
games about 14 rounds. Now: games average 21 rounds, and 10 of 40 hit the 150-round limit
undecided (stalemates).

- **Josh's balance goal** (recorded in the DESIGN.md appendix): regional advantage is fine and
  realistic. The target is advantage that *shifts* with technology and events, not equal odds.
  Mesopotamia leading now is acceptable if step 6's events and internal strain, and later the
  Iron Age, can turn its strengths into weaknesses.
- **Defending almost never works** (defences hold 0–4%). The AI only attacks when it expects
  to win, and defenders spread thin. Consider rewarding concentrated garrisons or capital defense.
- **Formations**: the AI attacks with Hammer and Anvil and defends in Phalanx almost exclusively.
  Skirmish Screen and Wedge are rarely worth choosing (`hegemon-sim formations`).
- **Stalemates**: a quarter of games end undecided at 150 rounds. Step 6's succession and
  revolts should break these up; if not, revisit the victory condition (open question §14.5).
- Gold still piles up (no sink until step 6). The sim shuffles turn order per seed, because
  seating mattered a lot. The app should randomize or rotate it too.
- Suggested sim addition for step 6: track the leader at rounds 10/20/30 and count lead changes.

## Decisions already made (don't re-litigate)

- **Platform**: native iOS, Swift. SwiftUI for menus/HUD, SpriteKit for the map and battles.
  iOS 17+. Portrait-first.
- **Single-player vs. AI from day one.** 1 human vs. 1–3 AI empires. No online multiplayer in MVP.
- **Player makes Risk-sized decisions; the world simulates the rest.** Player: recruit, move /
  attack, pick a battle formation template, answer occasional crisis prompts. Automatic: supply,
  trade routes, events, ruler aging, generals' loyalty, succession, barbarians.
- **AI baseline is a Risk heuristic bot** (reinforce threatened borders, score attacks by
  P(win) × value − exposure, fortify borders), extended with a supply penalty, trade/chokepoint
  value, and a stability term. P(win) comes from running the real battle sim. Personalities via
  weights. See DESIGN §12.
- **Battles**: pick a formation template, then watch a deterministic simulation on the 5×5 grid.
  Infantry / archers / cavalry triangle; terrain modifies the grid and bonuses; generals have
  traits and renown. Auto-resolve available. Naval battles auto-resolve only.
- **Resources (6)**: grain, copper, tin, horses, timber, gold. Bronze is made automatically
  where copper and tin meet. Josh specifically wants resource variety, so don't cut it.
  Iron and the Bronze → Iron Age transition are post-MVP.
- **Every territory produces at least 1 grain.** Population is capped by local + imported grain.
  Armies eat from the same pool.
- **Trade matters a lot**, but as routes, agreements and access, not haggling. MVP diplomacy is
  war / peace only (peace enables trade). Trade routes form automatically.
- **Succession and civil war are a headline feature.** Monarchy + Republic in MVP. Core tension:
  generals' renown lowers their loyalty, so great generals are the civil-war risk.
- **Map decisions** (Josh delegated these): see the appendix at the end of DESIGN.md. Grain and
  resource values are balancing data; tune them from AI-vs-AI simulation results.

## Architecture (DESIGN §13)

```
HegemonCore/            Swift package, no UI imports, platforms iOS 17 / macOS 14
  Sources/HegemonCore/  rules engine
  Sources/hegemon-sim/  CLI: headless AI-vs-AI games for testing and balance
  Tests/HegemonCoreTests/
AncientHegemon/         iOS app (Xcode project), depends on HegemonCore
```

Engine rules:
- **Deterministic**: all randomness through a seeded RNG (e.g. SplitMix64) stored in game state.
  Never use `Int.random` / `SystemRandomNumberGenerator` in the engine.
- **Codable state**: the whole `GameState` serializes to JSON (saves, bug repros).
- **Commands**: player and AI actions are values (`Recruit`, `Move`, `SetFormation`,
  `MakePeace`...) validated and applied by the engine. The UI and AI use the same API.
- **Data-driven**: map, units, events, traits from JSON resources.
- **Tested**: `swift test` in `HegemonCore/` must pass before every push.

## Build order

Each milestone ends with passing tests and a push.

1. **Package skeleton**: `Package.swift`, load `map.json` into typed models (`Territory`,
   `SeaZone`, `Chokepoint`, `Civilization`), adjacency queries, seeded RNG, `GameState`.
   Tests: map loads, 40 territories, adjacency symmetric, RNG reproducible.
2. **Turn loop & economy**: grain production, population growth / starvation, army upkeep,
   recruitment from income, territory control.
3. **Supply & trade**: supply-route pathfinding (controlled land + controlled/uncontested sea),
   attrition when out of supply, automatic trade routes, chokepoint control, bronze production.
4. **Battle simulation**: 5×5 grid, formation templates, unit triangle, terrain tiles and
   bonuses, morale and rout, generals. Deterministic; tests for the triangle and terrain.
5. **AI v1 + `hegemon-sim`**: Risk-style bot; CLI runs N AI-vs-AI games and reports win rates,
   game length, and how often empires starve or collapse. This is the main balance tool.
6. **Government, succession, events**: rulers, legitimacy, loyalty, succession / civil war,
   the ~8 events in DESIGN §8.
7. **iOS app**: Xcode project, SwiftUI shell, SpriteKit map with territory hit-areas, battle
   playback view, HUD with the 6 resources. Run in the Simulator, then on Josh's iPhone.

The painted board should become the map art. A high-resolution photo or scan is needed; ask
Josh for it before step 7. Until then use a placeholder.

## Working with Josh

- Direct, no sugar-coating; push back when something is a bad idea.
- He's happy to delegate detail decisions. Make the call, record it in DESIGN.md, and tell him.
- Explain trade-offs in plain terms; he's a designer first, coder second.
- Commit messages: clear and descriptive. Don't open a PR unless asked.
