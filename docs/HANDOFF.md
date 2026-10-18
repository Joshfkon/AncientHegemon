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

## Working with Josh

- Direct, no sugar-coating; push back when something is a bad idea.
- He's happy to delegate detail decisions. Make the call, record it in DESIGN.md, and tell him.
- Explain trade-offs in plain terms; he's a designer first, coder second.
- Commit messages: clear and descriptive. Don't open a PR unless asked.
