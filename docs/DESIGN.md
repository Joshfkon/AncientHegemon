# Ancient Hegemon — Game Design Document

*A grand strategy game of ancient empires.* Status: **draft v0.1** — pre-production, iPhone-native MVP.

---

## 1. Pitch

**Risk with logistics.** Conquest is easy; holding an empire is hard. Armies must be fed, trade
routes must be protected, and when your ruler dies, your own generals may tear the empire apart.

The game is a digital adaptation of the *Ancient Hegemon* board game: a hand-painted map of the
Mediterranean and Near East (~45 territories, Hibernia to Persia), unit cubes for infantry, archers
and cavalry, a 5×5 tactical battle board, resource and population tokens, events, and leaders.

### Design rule
Every mechanic must answer: **does this make holding territory interesting?**
Supply, trade, succession, rebellion, events, and terrain all exist to make an overextended empire
fragile. Mechanics that don't serve that are candidates to cut.

## 2. Pillars

1. **Logistics is strategy.** Armies eat. Supply and trade flow along a visible network of land
   routes and sea lanes. Cut the network, and the empire downstream starves.
2. **Trade is the second battlefield.** Resources are geographically scarce; no one is
   self-sufficient. Routes, passage rights, and chokepoints matter as much as borders.
3. **Battles are decided before they start.** You choose the formation; the battle plays out on its
   own. Generals, terrain, and composition decide it, not micromanagement.
4. **Empires die from within.** Government type and succession decide whether a ruler's death is a
   smooth handover or a civil war. Your best general is also your biggest threat.
5. **The world pushes back.** Famine, plague, omens, barbarians, and geography (mountains, rivers,
   deserts, seas) are real constraints, not flavor text.

## 3. Core loop

One **turn** = one season-year. Each player turn:

1. **Events**: Draw/resolve a random event (famine, plague, good harvest, omen...).
2. **Harvest & upkeep**: Territories produce resources; population grows from grain surplus; armies
   consume grain along their supply route. Unsupplied armies take attrition.
3. **Government**: Ruler ages; loyalty and legitimacy update; succession resolves if the ruler died.
4. **Orders**: Recruit units, move armies and fleets, make war or peace. (Supply and trade
   routes follow automatically from territory control; see §11.)
5. **Battles**: Any contested territory triggers a battle: set formation, watch it resolve.
6. **End turn**: AI empires take their turns (§12).

Target session: **45–90 minutes** for a full game, playable in sittings. (Open question; see §14.)

## 4. The map

- Source: the painted board. ~45 land territories plus sea zones (the dashed lines on the board).
- Each territory has: **terrain type**, **resource yields**, **population capacity**, **adjacency**
  (land and sea), and optional **chokepoint** / **mountain pass** flags.
- Map data is **data-driven JSON**, not hard-coded, so balance changes don't need code changes.

### Terrain

| Terrain | Movement | Battle effect | Notes |
|---|---|---|---|
| Plains / grassland | normal | Cavalry +1 | Most fertile |
| Hills | slow | Archers +1, defender bonus | |
| Mountains (Alps, Pyrenees, Taurus, Caucasus) | crossable only at passes; slow | Strong defender bonus; Cavalry −1; impassable battle tiles | Natural borders and chokepoints |
| Forest | slow | Infantry +1; Archers −1 (line of sight) | |
| River crossing | costs a move | Attacker penalty crossing | Rhine/Danube, Nile, Tigris/Euphrates |
| Desert (Sahara, Libya, Arabia) | slow | Attrition without supply | Low yield, hard to hold |
| Sea zone | fleets only | Naval battle | Armies need ships to cross |

Terrain also shapes the **battle grid**. A mountain territory's battlefield has impassable tiles;
plains are open (as on the physical battle board: "Unpassable", "Cavalry +1", "Infantry +1").

## 5. Military

### Units (MVP)

| Unit | Role | Strong vs | Weak vs |
|---|---|---|---|
| Infantry | Holds the line | Cavalry (in formation) | Archers (at range) |
| Archers | Ranged damage | Infantry | Cavalry (flanked) |
| Cavalry | Mobility, flanking | Archers | Infantry (frontal) |
| Ships (galley) | Carry 2 land units; fight naval battles; protect / raid sea lanes | | |

Units have **strength**, **morale**, and **experience**. Morale breaks before units die; a routing
army is how most battles end.

### Battle flow: "design the formation, watch it play out"

1. **Formation**: Each side picks a formation template (e.g. *Phalanx*, *Hammer and Anvil*,
   *Skirmish Screen*, *Refused Flank*, *Wedge*) that places its units on its 2 rows of the 5×5
   grid (the physical battle board), hidden from the opponent. Terrain tiles are shown.
   Free-form placement with per-unit stances (*Hold*, *Advance*, *Flank*, *Skirmish*) is post-MVP.
2. **Generals**: The commanding general's traits modify the army.
3. **Resolve**: A deterministic, seeded simulation runs in rounds and is animated on screen
   (~20–40 seconds). Players watch; no input.
4. **Outcome**: Casualties, routs, captured general, territory control.

Optional **auto-resolve** skips steps 1–3 using an AI-chosen formation, for minor battles.

### Generals

- Named characters with **traits** (e.g. *Tactician*: +1 morale; *Cavalry Commander*: cavalry +1;
  *Cautious*: defensive bonus, slower advance; *Reckless*: attack bonus, more likely to die).
- Gain **renown** from victories. Renown boosts the army and **reduces loyalty to the throne**:
  a famous general is a potential usurper (see §7).
- Can die in battle (higher risk when fighting at the front; this is the leader-present /
  leader-fighting rule from the board game).

### Navy

- Fleets occupy sea zones, transport armies, and fight naval battles (simplified: same formation
  system on a sea grid, or auto-resolve only for MVP; see §14).
- Fleets **protect or blockade sea lanes**, which is how naval power plugs into trade and supply.
- Ships require **timber**.

## 6. Logistics & trade

### Resources

| Resource | Main sources (historical) | Used for |
|---|---|---|
| Grain | Egypt, Sicily, Black Sea, Mesopotamia | Population growth, army upkeep |
| Copper | Cyprus, Anatolia | Bronze (with tin) |
| Tin | Britain, Iberia | Bronze (with copper) |
| Bronze | crafted | Bronze Age units |
| Iron | widespread, **Iron Age only** | Iron Age units |
| Horses | Scythia, Sarmatia, Thrace, Media | Cavalry |
| Timber | Macedonia, Gaul, Lebanon (Syria) | Ships, siege works |
| Gold | Dacia, Iberia, Egypt, Lydia | Tribute, bribes, mercenaries, loyalty |

### Supply

- Every army traces a **supply route** to a friendly city through controlled or allied territory /
  protected sea lanes. Routes are drawn on the map.
- Each step of route length costs grain. Out of supply: morale drops, then strength.
- Supply lines **flicker** on the map when stretched or threatened. The player should never need
  a menu to learn why an army is starving.
- Grain moves automatically along routes; the player decides what to protect and what to cut,
  not where each token goes.

### Trade routes

- A **trade route** links a resource source to a city that needs it, along land roads and/or sea
  lanes. Active routes pay **gold** to every empire they pass through (if a pact allows).
- **Chokepoints** (Gibraltar, Bosporus, Sicilian strait, Alpine/Pyrenean passes, Caucasus) can
  **tax or close** routes passing through.
- Routes are **raidable** by fleets, barbarians, and enemies; protection costs units.

### Agreements (small, mechanical set)

| Agreement | Effect |
|---|---|
| Passage rights | Goods and/or armies may cross the other's territory |
| Trade pact | Shared route income; routes through both empires pay both |
| Tribute | Recurring gold/resources for non-aggression |
| Embargo | Close your territory/chokepoints to a party |

Breaking an agreement is allowed but costs **Credibility**; low credibility means nobody trades with
you and neutrals turn hostile.

### Neutral powers

Computer-controlled **trading cities** (Phoenician/Greek colonies) and **barbarian tribes**. They
buy, sell, raid, and can be bribed or allied. They give diplomacy a third party in 2-player games
and are far simpler than a full AI opponent.

## 7. Government & succession

The defining system. Ancient empires rarely fell to foreign armies first. They fell to civil war
over the throne.

### Rulers

- Named, aging characters with traits (*Able Administrator*, *Cruel*, *Pious*, *Weak*...).
- Die of age, illness (plague), battle, or assassination.

### Government types (MVP: 3)

| Government | Succession | Strength | Weakness |
|---|---|---|---|
| **Monarchy** | Hereditary heir | Stable if a strong adult heir exists | Child/no heir → regency or civil war |
| **Republic** | Elected from leading generals/nobles | Rarely collapses; no single point of failure | Slow; popular generals can seize power (Caesar) |
| **Tribal confederation** | Strongest chief | Cheap, warlike, flexible | Fragments on almost every death |

Government can **change**, through reform, revolution, or a winning usurper (republic → monarchy).

### Legitimacy & loyalty

- **Legitimacy** (ruler): raised by victories, wealth, stability, religion; lowered by defeats,
  famine, broken agreements.
- **Loyalty** (each general and provincial governor): falls with renown, distance from the capital,
  and unpaid upkeep; rises with gold, honors, and shared victories.

### Succession crisis

When the ruler dies, roll succession based on government, heir status, and legitimacy:

1. **Smooth**: heir/elected successor takes over; minor legitimacy hit.
2. **Contested**: claimants appear (heir vs. popular general vs. governor). Resolve with gold,
   concessions, or force.
3. **Civil war**: The empire **splits**. Each disloyal general/governor takes their armies and the
   territories they control. The player keeps the loyalist side and must reconquer. In 2-player
   games, rebel factions become neutral powers.

Core tension: **you need great generals to win wars, and great generals are what start civil wars.**
Keeping armies small and close to the capital is safe and slow; sending famous generals far away
is fast and dangerous.

## 8. Events

Drawn each turn; weighted by state (famine is likelier in overpopulated territories; plague spreads
along trade routes).

| Event | Effect |
|---|---|
| Famine | Grain yield ×⅔ in affected territories |
| Plague | −20% population; spreads along trade routes; may kill ruler |
| Good harvest | Grain ×2 |
| Gold discovered | Territory gains +1 gold yield permanently |
| Bad omen | Cannot initiate attacks this turn (the sacred chickens refuse to eat) |
| Meteorite | +1 iron regardless of age |
| Ruler dies | Natural death → succession (§7) |
| Barbarian migration | Barbarian army spawns at the map edge |
| Revolt | Low-loyalty territory rebels |
| Earthquake / flood | Destroys buildings or blocks a route temporarily |

## 9. Ages

The time track runs from the **Bronze Age** to the **Iron Age**. At the transition, tin's value
collapses, iron becomes available everywhere, and the trade map reshuffles. (This mirrors the
Bronze Age collapse, which was a collapse of trade networks.) *Post-MVP unless cheap.*

## 10. Playable civilizations

Starting set from the original prototype: **Greece, Egypt, Italia, Mesopotamia**. Later: Persia,
Carthage, Macedonia, Gaul... Each has a starting government, territory, and one unique trait.

## 11. MVP scope

The guiding split: **the player makes Risk-sized decisions; the world simulates everything else.**
Supply, trade, events, and succession run automatically. They create pressure and consequences,
but they are not extra menus to manage. This keeps the game readable on a phone and keeps the AI
tractable (see §12).

### What the player does each turn
1. **Recruit**: Place new units (reinforcements come from territory income, like Risk).
2. **Attack / move**: Armies and fleets move between adjacent territories / sea zones.
3. **Formation**: Pick a formation *template* for a battle, or accept the default.
4. **Crisis decisions** (occasional): Answer prompts the simulation raises, such as backing a
   claimant in a succession crisis or accepting/refusing a peace offer.

### What happens automatically
- **Supply**: Routes are computed every turn; out-of-supply armies take attrition. Drawn on the map.
- **Trade**: Routes form automatically between your territories and with empires at peace with you;
  they break when a territory or sea lane on the path is lost or blockaded.
- **Events**: Drawn and resolved each turn.
- **Rulers and generals**: Age, gain renown, lose loyalty; succession resolves by rule, prompting
  the player only at real forks.
- **Barbarians**: Spawn and raid by script.

### In
- iPhone, portrait-first
- **1 human vs. 1–3 AI empires** (single-player first); hot-seat is a cheap extra if time allows
- Full painted map (~40 territories), terrain, sea zones
- Infantry, archers, cavalry; ships as **transports and sea-lane control** (naval battles
  auto-resolve)
- Formation battles: 4–5 formation templates, animated resolution, auto-resolve
- Generals with 1 trait each and renown
- Automatic grain supply with attrition, visible on the map
- 6 resources: grain, copper, tin, horses, timber, gold. Bronze is made automatically wherever
  copper and tin meet, so the tin routes from Britain/Iberia matter. Automatic trade routes;
  chokepoints
- Diplomacy: **war / peace only** (peace enables trade)
- Monarchy + Republic; succession; civil war (rebels become an independent faction)
- ~8 events
- Barbarians (scripted)
- Save/resume

### Out (post-MVP)
- Online multiplayer (Game Center turn-based)
- Free-form formation editing (templates only for now)
- Agreements beyond war/peace (passage rights, tribute, embargo)
- Tribal government; neutral trading cities
- Iron and the Bronze → Iron Age transition
- Sieges and city walls; tactical naval battles
- More civilizations

## 12. AI

### Baseline: Risk AI
Risk AI is well-trodden ground. The standard heuristic bots (border-strength ratios, region-bonus
valuation, attack-odds tables) play competently with very little code. The MVP AI starts there:

- **Recruit**: Reinforce threatened borders (enemy strength vs. own strength on each frontier) and
  the staging territory for the next planned attack.
- **Attack**: Score each possible attack by `P(win) × value(target) − risk(exposed border)`,
  execute in order while the score stays positive. `P(win)` comes from the battle simulator itself
  (run the deterministic sim a few times with sampled seeds), so the AI's estimate always matches
  the real rules.
- **Fortify**: Pull units from safe interior territories to borders.

### Extensions for this game
Because supply, trade, and succession are automatic, the AI doesn't plan them. It only needs
them **in its scoring**:

- **Target value** = territory resources + trade routes it would gain/cut + chokepoints + region
  completion (Risk-style continent bonus).
- **Supply penalty**: An attack that leaves the army out of supply is heavily discounted. This one
  term is what stops the AI from overextending like a Risk bot does.
- **Stability term**: Avoid long wars when ruler legitimacy is low or a general's loyalty is
  falling; prefer peace when it would restore trade income.
- **Formation choice**: Pick the template with the best simulated outcome against the visible
  enemy composition and terrain.
- **Crisis choices**: Simple rules (back the strongest claimant; accept peace when losing).

### Personalities
Weights per AI empire give variety cheaply: *Conqueror* (high aggression), *Merchant* (values
trade and peace), *Turtle* (defensive, fortifies chokepoints), *Opportunist* (attacks whoever is
in a civil war).

### Difficulty
Easy/Normal/Hard adjust **search depth and noise**, not cheating. A small reinforcement bonus at
Hard is acceptable if the honest AI tops out.

### Later
If the heuristic AI plateaus, the deterministic engine supports Monte Carlo search (simulate
candidate turns forward) without redesign.

## 13. Technical architecture

- **Platform**: iOS 17+, Swift, SwiftUI for menus/HUD, **SpriteKit** for the map and battle
  animation.
- **`HegemonCore`**: a pure-Swift package, no UI imports. Contains all rules:
  map graph, economy, supply pathfinding, trade, battles, succession, events.
  - **Deterministic**: all randomness through a seeded RNG stored in game state. The same state +
    the same orders always produce the same result. This enables replays, battle playback,
    debugging, and later online multiplayer and AI search.
  - **Codable state**: the full game state serializes to JSON (save games, bug reports).
  - **Command pattern**: player actions are values (`MoveArmy`, `SetFormation`, `ProposePact`...)
    validated and applied by the engine. The UI and a future AI use the same interface.
  - **Unit-tested** on its own, without the simulator.
- **`AncientHegemonApp`**: the iOS app target. Renders state, collects commands. No rules logic.
- **Data**: map, units, events, and traits in JSON for balancing without code changes.
- **Art**: the painted board, photographed/scanned at high resolution as the base map layer.
  Territory hit-areas are drawn as polygons over it.

## 14. Open questions

1. **Session length**: 45–90 min target, or a shorter (~30 min) mode for phone play?
2. **Battle depth**: are formation templates enough, or do players want to place units and give
   per-unit orders? (MVP: templates.)
3. **Naval battles**: auto-resolve for MVP; is a tactical sea grid ever worth it?
4. **Civil war in multiplayer**: does the losing faction become neutral, or can another player
   back a claimant?
5. **Victory conditions**: domination, wealth, prestige score at the end of the time track, or all
   three?
6. **Rulebook reconciliation**: the existing board-game rulebook should be mapped onto this doc;
   where they conflict, decide which wins.
7. **Territory list**: confirm the final territory set and adjacency from the painted map.

## Appendix: map decisions

Map data lives in `HegemonCore/Sources/HegemonCore/Resources/map.json` and is checked by
`tools/validate_map.py`.

- **40 territories**: Hibernia, Caledonia, Britain, Sitones, Saxone, Suebi, Venedi, Gaul, Hispania,
  Pyrenees, Baetica, Alps, Italia, Sardinia, Sicilia, Macedonia, Greece, Crete, Mauretania, Numidia,
  Sahara, Cyrenaica, Libya, Dacia, Thrace, Scythe, Sarmatia, Caucasus, Dahā, Media, Armenia, Taurus,
  Anatolia, Cyprus, Syria, Mesopotamia, Persia, Petraea, Egypt, Arabia.
- **Taurus is a territory**: a mountain territory holding the Cilician Gates, the pass between
  Anatolia and Syria/Mesopotamia. Mountain territories as chokepoints are a deliberate pattern
  (Pyrenees, Alps, Caucasus, Taurus).
- **Gaul ↔ Hispania only through the Pyrenees** by land. The pass is a mandatory chokepoint; the
  sea route around it remains open to fleets.
- **Sardinia added** (covers Corsica): the unnamed islands west of Italia become one territory,
  giving the western Mediterranean a contested island between Italia and Numidia.
- **Unnamed regions east of Armenia** and the small islands (Balearics) are folded into
  neighbors or left as sea.
- **Grain and resource values are balancing data**, first-pass estimates rather than the board's
  printed numbers. Every territory produces at least 1 grain. Tin is deliberately scarce
  (Britain, Hispania only).
- **Starting realms (provisional)**: each civilization starts holding only its capital; every
  other territory is unowned. This is a placeholder for the engine. Starting realm size is a
  balancing question to settle with `hegemon-sim` in build step 5.
- **Economy model (build step 2, provisional; values in `rules.json`)**:
  - Each grain feeds 2 people; each army unit eats 1 grain. A territory's population is capped at
    its grain yield, so a fully grown territory still has about half its grain free for armies.
  - Territories start at half their population cap. A surplus grows population by up to +1 per
    territory per turn (emptiest first, one grain each); what's left fills a granary holding up
    to one turn of production.
  - A deficit drains the granary, then people starve (from the fullest territories, never below
    1), then army units desert (from the largest stack).
  - Gold income = population ÷ 2 + gold yields. Recruiting costs gold and turns 1 population into
    1 unit, so manpower, not gold, limits armies. Cavalry need horses: each point of horse yield
    allows one cavalry recruit per turn.
  - Grain is pooled empire-wide for now. Build step 3 limits it to territories connected by supply.
  - Moving into an unowned or undefended territory captures it. Moving into another civ's army is
    blocked until the battle sim (step 4). Everyone is implicitly at war until diplomacy exists.
  - **Known gap**: gold accumulates with no sink yet. Sinks (loyalty, bribes, mercenaries) arrive
    with step 6. Greece (2 grain) starts in deficit and must expand or import; intended for now.
- **Supply, trade and diplomacy model (build step 3, provisional; values in `rules.json`)**:
  - **Supply network**: a civ's territories connect through its own land borders and through
    sea lanes (every coast reaches its seas; seas reach linked seas). A sea link gated by a
    chokepoint is closed while the chokepoint is held (all its territories) by a civ at war with
    the traveler. Land passes need no special rule: you must own the pass territory to use it.
  - **Seat and home network**: supply traces from the capital, or, if it has fallen, from the
    civ's highest-grain territory. The pocket connected to it is the home network: it shares
    grain and the granary, pays taxes and gold yields, makes bronze, and is the only place
    units can be recruited.
  - **Cut-off pockets** feed themselves with no granary, pay nothing, and their armies lose
    1 unit per stack per turn (2 in desert), on top of any starvation.
  - **Diplomacy**: everyone starts at war. `offerPeace` / `acceptPeace` (on the other civ's
    turn) / `declareWar`. You can't enter a peace partner's land. No credibility cost yet.
  - **Trade routes** form automatically between civs at peace whose home networks connect
    through their own land and open sea lanes (no passage through third parties' land). Each side
    earns 2 gold per route per turn and gets half (rounded down) of the partner's copper, tin,
    horses, timber and gold yields as "access". Grain is not traded yet.
  - **Chokepoint tolls**: a route crossing a sea chokepoint held by a third civ at peace with
    both pays that holder 1 gold from each side. A holder at war with either side closes it.
  - **Bronze**: each turn, `min(copper, tin)` across the home network plus trade access is added
    to a stockpile. What bronze buys (battle equipment bonus or unit cost) is decided in step 4.
  - Seas are all uncontested for now; fleets (blockades, transports) plug into the network later.
    Until ships exist, armies can't cross water, so islands can't be captured.
- **Battle model (build step 4, provisional; values under `battle` in `rules.json`)**:
  - The 5×5 board: attacker on rows 0–1, defender on rows 3–4 (columns mirrored), row 2 empty.
    Each army splits into at most 10 single-type blocks; larger armies make heavier blocks.
  - **Formations** (Phalanx, Hammer and Anvil, Skirmish Screen, Refused Flank, Wedge) set each
    unit type's preferred squares and whether it advances or holds. Each army keeps a formation
    (`setFormation`) used both attacking and defending. A holding block that is struck engages;
    the attacker's holding blocks advance after round 1 (the attacker must attack).
  - **Rounds**: blocks move toward the nearest enemy (cavalry 2 squares, others 1; which side
    moves first alternates), then strike simultaneously: melee if adjacent, else archers shoot
    (range 3; 2 in forest; half damage in melee). Cavalry get +50% on their first melee (charge).
  - **Triangle**: infantry ×1.5 vs cavalry, archers ×1.5 vs infantry, cavalry ×1.75 vs archers;
    the reverse matchups are ×0.75. With equal numbers, the counter wins almost always.
  - **Terrain**: plains cavalry +25%; hills archers +25% and defender −20% damage taken;
    mountains cavalry −25%, defender −35%, impassable squares; forest infantry +25%, archers
    −25%, defender −10%, impassable squares; desert neutral. Attacker penalties: river −20%,
    strait −25%, amphibious landing −30%.
  - **Morale**: blocks lose morale with damage taken, plus extra when hit by two enemies in
    one round; at 0 they rout. An army that has lost 60% of its strength breaks. If both
    break in the same round, the side with more strength left wins; after 20 rounds the defender
    holds. Damage has a ±25% per-strike swing plus a ±25% per-round "fortune" roll for each side,
    so odds are gradual: on open ground 6 vs 6 is about even, 7 vs 6 wins about 75–95%.
  - **Aftermath**: the loser loses 25% of its survivors in the retreat. A beaten defender falls
    back to an adjacent friendly territory (home network first) or is destroyed; a beaten
    attacker returns where it came from, its move spent.
  - **Generals**: each civ starts with one (Miltiades/Tactician, Thutmose/Cavalry Commander,
    Fabius/Cautious, Sargon/Reckless). A general moves with an army (`move … general: true`),
    gains 1 renown per victory (+5% attack per renown, max +25%), and dies 10% of the time
    on defeat, 3% on victory (×2 if Reckless). A general caught without an army is lost.
  - **Bronze**: the stockpile works as equipment: up to +20% attack, scaled by
    stockpile ÷ army size, not consumed.
  - Every battle produces a `BattleReport` with frame-by-frame replay (block positions, units,
    morale, strikes) for the iOS battle view. Auto-resolve is the same simulation, unwatched.
  - **Known gap: formation balance.** On open ground with mixed armies, Phalanx beats every
    other formation, and Skirmish Screen loses to all of them. Wedge does counter Hammer and
    Anvil. Tune this in step 5 using AI-vs-AI formation matrices.
- **Ships (build step 4, provisional; `ships` and `naval` in `rules.json`)**:
  - `buildShips` at a coastal home-network territory: 4 gold each, one per point of timber
    yield (including trade access) per turn; new ships sail next turn. Each ship's crew eats 1
    grain from home, as do the troops aboard.
  - Each ship carries 2 land units. `embark` (units that haven't moved; free), `moveFleet` (one
    sea per turn, cargo travels along; blocked by enemy-held chokepoints), `land` (uses the
    units' move; landing on an enemy army is an amphibious battle). Generals don't sail yet.
  - Sailing into an enemy fleet triggers an auto-resolved naval battle (strength by ships; a
    fleet that loses half its ships withdraws). Sunk ships drown cargo that no longer fits.
    A beaten defender fleet withdraws to a neighboring open sea or is lost. Civs at peace share seas.
  - **Blockade**: a sea with an enemy fleet and none of yours is closed to your supply and trade.
- **AI v1 (build step 5)**: `AIPlayer` in `HegemonCore`, playing through the same commands as a
  human. Each turn: diplomacy, recruit, attack, fortify, then defensive formations.
  - **Diplomacy**: offers or accepts peace with civs it doesn't border, when losing (under 0.75×
    their strength), or when trade-minded. Once it has no unclaimed land next door, it declares
    war on a bordering civ it outmatches by `1.6 − 0.4 × aggression` (conqueror ≈ 1.0×,
    turtle ≈ 1.3×).
  - **Recruit**: reinforces where threat minus garrison is highest (frontiers get a nudge),
    picks the counter to the nearby enemy's main unit type, and stops before army upkeep would
    outrun production plus a quarter of the granary.
  - **Attack**: scores each move as `P(win) × value × aggression − risk`, with `P(win)` from
    4 runs of the real battle simulator. Value counts grain, resources (tin and copper weighted up
    when lacking), enemy capitals, finishing off a civ, and completing a chokepoint. Moves from
    cut-off territory score 30%. It keeps garrisons against adjacent threats, picks the best
    attacking formation, and brings its general. It greedily repeats while the best score is
    positive.
  - **Fortify**: interior armies march one step toward the nearest border.
  - **Personalities**: conqueror, merchant, turtle, opportunist (weights for aggression,
    caution, trade, opportunism). Defaults: Greece merchant, Egypt turtle, Italia conqueror,
    Mesopotamia opportunist.
  - Deterministic, and never touches the game's RNG (its estimates use seeds derived from state).
  - **Naval AI**: each turn it picks the most valuable coast it can't reach by land (score:
    value − 0.7 × defenders − 0.75 × seas away), builds transports before recruiting (enough
    for `2 × defenders + 1` units, max 8, keeping gold for a recruit), boards spare troops at the
    nearest coast, sails one sea toward the target (avoiding enemy fleets it can't beat 1.5 to 1),
    and lands when 4 simulated landings give at least 60% success.
  - **Not yet**: no lookahead beyond one move; no dedicated warfleets or deliberate blockades.
- **Changes made from the first balance runs (step 5, provisional)**:
  - **Native garrisons**: every territory not in a starting realm holds `2 + grain ÷ 3` native
    infantry that defend but never move or act (raised from 1 + grain ÷ 3 after the naval-AI
    runs: Mesopotamia's win rate fell from 77% to 47% and games lengthened from 14 to 21 rounds). Without them, whoever had the most empty
    neighbors snowballed (Mesopotamia held 24 territories by turn 10).
  - **Starting heartlands** (replacing capital-only starts): Greece + Macedonia + Thrace,
    Egypt + Libya + Petraea, Italia + Sicilia, Mesopotamia + Persia. Greece's 2-grain capital
    alone could never grow or recruit.
  - **Supply-route upkeep** (DESIGN §6 "each step of route length costs grain"): units eat 1
    extra grain per 3 steps from the seat (sea crossings count 2).
  - **No harvest on turn 1**, so later seats don't start with a free harvest.
  - **Domination victory**: holding 60% of territories (24 of 40) wins. Placeholder for open
    question §14.5.
- **Balance goal: shifting advantage, not equal odds** (Josh, after step 5). Some regions
  should be stronger, as they were historically. What matters is that *who* is advantaged
  changes with technology and events, and that an advantage can turn into a weakness. Equal
  win rates are not the target. The aim is that each civ has eras or situations where it
  leads. Hooks for this, for steps 6+ and the Ages:
  - **Centrality cuts both ways**: Mesopotamia's many borders mean fast growth but also the most
    fronts, the most generals far from the capital (civil-war risk), and first contact with
    steppe migrations.
  - **River-valley breadbaskets** (Egypt, Mesopotamia) are most exposed to flood and famine
    events. **Trade hubs** are where plague spreads along routes.
  - **Bronze → Iron Age**: tin's value collapses and iron appears everywhere, so empires
    built on tin routes lose their edge while poorer, peripheral ones gain.
  - The sim should measure this: who leads at different points in a game and how often the
    lead changes, not just who wins.
- **Government, succession and events (build step 6, provisional; `government`, `rulerTraits`,
  `events`, `names` in `rules.json`)**:
  - **Rulers** age a year per turn, with a death chance of 1% plus 1% per year past 40. They die
    of old age or plague. Traits: Able Administrator (+20% taxes and mines), Pious (+1
    legitimacy/turn), Cruel (generals +10 loyalty, −1 legitimacy/turn), Weak (generals −15
    loyalty). Monarchs may get an heir (15%/turn when they have none).
  - **Legitimacy** (0–100, start 60, drifts 2/turn toward 50): battle won +2 / lost −3, capture
    +1, capital lost −15, starvation −3, breaking a peace −8.
  - **Generals' loyalty** moves a quarter of the way each turn toward
    `legitimacy − 6 × renown − 2 × supply steps from the seat` (± ruler trait). Each general costs
    1 gold a turn (unpaid: −10 loyalty). `appointGeneral` (8 gold; 1 per 6 territories, plus one)
    and `honorGeneral` (4 × (1 + renown) gold, +25 loyalty) are gold's first real uses.
  - **Succession**: a monarchy with an adult heir, legitimacy ≥ 35 and no claimants passes
    smoothly (−5). Otherwise a regent rules (−15). Claimants (renowned generals under 60
    loyalty leading an army) are bought off at 10 gold each (−10) if the treasury allows;
    otherwise each starts a civil war. Republics elect a successor, unless a general with
    renown ≥ 4 and loyalty < 50 seizes power and the republic becomes his monarchy. After any
    death, generals under 45 loyalty with an army rise up.
  - **Rebellion** can also happen any turn: a general under 25 loyalty leading 3+ units away
    from the seat rebels with 3% chance per point below 25.
  - **Civil war**: the general takes every territory closer to him than to the seat, with the
    armies and generals in them, and founds a new AI civilization (an opportunist) at war with
    the old one.
  - **Events** (50% chance per civ per turn, weighted by geography and state):
    famine (harvest ×½; river valleys and crowded lands), flood (river valleys lose population),
    good harvest (×2; river valleys favored), plague (−20% population in the 3 most populous home
    territories, 10% chance to kill the ruler, 50% chance to travel to each trade partner;
    weighted by trade routes), gold discovered (+1 gold; hills and mountains), bad omen (no
    attacks this turn; low legitimacy), barbarian migration (a horde of 3 + turn ÷ 8 strikes from
    a barbarian homeland next to the civ), revolt (the most distant territory, 5+ supply steps
    away, rises with a native garrison).
  - **Region tags** in `map.json`: `river_valley` (Egypt, Mesopotamia) and `barbarian_homeland`
    (Caledonia, Suebi, Venedi, Scythe, Sarmatia, Dahā, Arabia, Sahara).
  - Barbarians that win hold the land unowned, like natives. If raiders destroy every
    civilization, the game ends with the barbarians as "winner".
  - Crisis prompts for the player (backing a claimant, refusing a bribe) resolve automatically
    for now; the iOS app will surface them as decisions (step 7).
- **Victory (Josh, after step 6; answers open question §14.5)**: several ways to win, each
  graded, like Civilization. Values under `victory` in `rules.json`.
  - **Domination**: hold 60% of territories (24 of 40).
  - **Trade**: hold all three sea chokepoints (Gibraltar, Bosporus, Sicilian strait) while
    trading with every surviving rival, for 5 consecutive rounds. It needs peace with everyone.
  - **Legacy**: if nobody has won by the end of round 50, the highest prestige wins. Prestige =
    10 × territories + population + gold ÷ 2 + legitimacy ÷ 2 + 20 for holding your capital.
    (Josh's idea: "whoever has the most gold by turn X", generalized.)
  - **Last standing**: every rival destroyed.
  - **Grades**: decisive (domination or trade before round 30, or last standing), major
    (domination or trade later, or a legacy win with ≥ 1.5× the runner-up's prestige), minor
    (a narrower legacy win). The end screen ranks every empire: survivors by prestige, then
    the fallen, last to fall first.
- **Landscape on the phone** (Josh, replacing "portrait-first"): the map is wider than tall, so
  the game is landscape-only, with the map on the left and the panels on the right.
- **Map art from the painted board** (step 7): territory outlines are traced by hand from Josh's
  photo of the board (both halves side by side, 2000×924 px) in `tools/board_shapes.py`, which
  writes `AncientHegemon/Resources/map_shapes.json` (outlines, lettering positions and angles,
  rivers, mountain peaks, fleet anchors) and checks that the territories drawn as touching are
  exactly the land links in `map.json`. The app paints them in the board's palette with owner
  tints. If the photo itself is added to the repo, the outlines line up with it in the same
  pixel space and it can serve as the background layer.
  - **Open: painting vs rules.** The tracing found two places where the painting and `map.json`
    disagree: Venedi touches Macedonia along the river on the painting but they aren't linked in
    the rules, and the rules link Venedi to Scythe though Dacia lies between them on the
    painting. The rules are unchanged until Josh decides.
