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
    96 tests.
  - **Build step 6 complete**: `Government.swift` (rulers, heirs, legitimacy, loyalty,
    succession, coups, civil war into new rebel civs, appoint/honor generals), `Events.swift`
    (8 geography-weighted events, barbarian raids, revolts), region tags in `map.json`, AI court
    phase, and lead/government/event reporting in `hegemon-sim`. Tests use `Engine.calm()` /
    `Engine.bare()` rule variants for exact-number scenarios. 114 tests.
  - **Simulator preview app** (start of step 7, at Josh's request): `AncientHegemon/`, generated
    by xcodegen from `project.yml` (run `xcodegen` there after changing it). It plays an
    AI-vs-AI game round by round on a schematic placeholder map (approximate lon/lat
    positions in `MapLayout.swift`), shows each empire's land, army, gold, legitimacy and
    ruler, keeps a chronicle, and replays any battle on the 5×5 board. SwiftUI Canvas only so
    far; no human player, no painted-board art, no SpriteKit yet. Landscape layout; shows the
    victory banner and final standings. Build with `-configuration Release` for the Simulator,
    or rounds crawl (debug-built engine).
  - **Map art traced from Josh's board photo**: `tools/board_shapes.py` (hand-traced outlines in
    the photo's pixel space, with an adjacency check against `map.json`); the preview app now
    paints the board. Two painting-vs-rules questions are open (see the DESIGN.md appendix).
    Josh's second photo shows the board with its resource tokens; reconciling `map.json`'s
    resource values against those tokens is still to do.
  - **Victory conditions added**: domination, trade, legacy and last-standing wins, graded.
    In 40 sim games every game ends by round 50 (average 34): 20 decisive domination, 17 legacy
    (9 minor, 8 major), 3 major domination, no trade wins (the AI doesn't pursue them yet).
    Wins: Mesopotamia 45%, Italia 22%, Greece 20%, Egypt 10%. 119 tests.
  - `docs/DESIGN.md`: game design doc. Sections 11 (MVP scope) and 12 (AI) are the build spec.
  - `HegemonCore/Sources/HegemonCore/Resources/map.json`: the map as data. 40 territories,
    land links (with `river` / `strait` crossings), 12 sea zones, 7 chokepoints, 4 civs.
  - `tools/validate_map.py`: checks the map data. Run it after any map edit:
    `python3 tools/validate_map.py`.
- **Legacy**: `legacy/*.cs` is a 2021 Unity prototype. Nothing is being ported from it.
- **Previous blocker**: the cloud session couldn't install a Swift toolchain. The Mac has Xcode,
  so that's resolved.

## Balance findings (after step 6; 40 games, default personalities, shuffled seating)

```
40 games, max 150 turns, 161.6s
decided: 23/40, average length 22 turns

civ          personality   wins  elim  collapse  avg land  peak  starving turns  deserted  attrition    attacks won   defences held  rejected
greece       merchant        2%    2%       30%       3.4   7.2             8.5         7          0     93% of 230      16% of 204         0
egypt        turtle          5%    2%       82%       4.0  10.5             9.9        15          1     97% of 450      17% of 314         0
italia       conqueror      17%    0%       42%       6.5  10.9             7.8         9          2     94% of 503      29% of 311         0
mesopotamia  opportunist    32%    0%       52%      11.1  17.6            10.8        14          2     97% of 807      18% of 346         0

lead changes per game: average 2.1, games with none  12%; the round-10 leader went on to win  69% of decided games
civ          led at round 10   20   30   wins  rebel wins
greece                       2%   7%  12%     2%          0%
egypt                       17%  15%   7%     5%          0%
italia                       2%  20%  15%    17%          0%
mesopotamia                 57%  35%  15%    32%          0%
rebels                       0%   0%   0%     0%

per 100 turns
civ          rulers died  civil wars  regencies  coups      famine    flood goodHarv   plague goldDisc  badOmen barbaria   revolt
greece              13.9         0.0        0.9    0.1         6.8      0.3      6.4     15.5      6.9      3.8      4.3      0.9
egypt                5.1         0.5        2.8    0.0        11.5      7.4      9.1     14.6      3.2      3.5      5.6      2.3
italia              10.0         0.3        0.8    0.4         7.2      0.0      7.6     14.6      6.5      3.8      6.7      0.6
mesopotamia          5.4         0.5        3.1    0.0         8.7      4.7      8.2     13.8      4.9      4.1     10.0      1.6
rebel factions per game: 1.3
```

- **Advantage now shifts.** The lead changes hands about twice a game. Mesopotamia leads at
  round 10 in 57% of games but wins 32%, and collapses (loses half its peak) in 52%: its river
  valley brings famine and floods, and its long steppe frontier draws the most barbarian raids.
  Italia rises late (leads at round 20 in 20% of games). Greece and Egypt are still weak.
- **Stalemates: 17 of 40 games reach 150 rounds undecided.** Internal strain now stops runaway
  empires, but nothing ends a long game. This needs a victory-condition decision from Josh
  (open question §14.5), e.g. a time track ending in a prestige score.
- Plague is the most common event (about 14 per 100 turns per civ, counting arrivals along
  trade routes). Republic magistrates are elected old and die often, but those successions
  are smooth.
- Rebel factions appear about 1.3 times a game but haven't won one yet.
- Still open from step 5: defending is weak (defences hold 16–29%), and Phalanx/Hammer and
  Anvil dominate formations.

## Decisions already made (don't re-litigate)

- **Platform**: native iOS, Swift. SwiftUI for menus/HUD, SpriteKit for the map and battles.
  iOS 17+. **Landscape** (changed from portrait-first after the preview app).
- **Victory**: domination, trade or legacy (prestige at round 50), each graded decisive / major /
  minor, with final standings. See the DESIGN.md appendix.
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

The painted board is the map art: outlines traced from Josh's photo (see above). A better photo
or scan in the repo would let the painting itself be the background layer.

## Working with Josh

- Direct, no sugar-coating; push back when something is a bad idea.
- He's happy to delegate detail decisions. Make the call, record it in DESIGN.md, and tell him.
- Explain trade-offs in plain terms; he's a designer first, coder second.
- Commit messages: clear and descriptive. Don't open a PR unless asked.
