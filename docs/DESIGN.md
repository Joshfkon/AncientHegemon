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
  - **Capital-only starts** (Josh, after the balance pass; replaces the starting heartlands of
    Greece + Macedonia + Thrace, Egypt + Libya + Petraea, Italia + Sicilia, Mesopotamia +
    Persia). Every civ starts with its capital alone; native garrisons stay. The sea powers get
    their own starts so they can grow: see "Capital-only starts" at the end of this document.
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
  - **Painting wins** (Josh): the tracing found two places where `map.json` disagreed with the
    painting. Fixed to match it: Venedi now borders Macedonia across the river, and no longer
    borders Scythe. Painting and rules now agree on every border. In 40 sim games afterward,
    Mesopotamia won 60% (was 45%) and Greece 10% (was 20%); Macedonia has one more border.
- **Playing it (step 7)**: the app opens on a civilization picker (or "watch the empires").
  On your turn: tap your army, then a highlighted destination; an order panel sets how many
  units go, whether the general leads, and the attacking formation, and shows the chance of
  victory (12 seeded runs of the real battle sim, never touching the game's RNG). Battles you
  fight replay at once. Tapping your own land offers recruiting, the defending formation,
  appointing a general and building ships; ships are boarded by tapping a sea with your fleet,
  sailed by tapping the fleet then a neighboring sea, and landed by tapping a coast. The Empire
  panel holds diplomacy (offer or accept peace, declare war) and generals (loyalty, honors).
  The AI empires then take their turns one at a time so their moves can be watched.
  - **Succession crises are the player's call**: when a human ruler's throne is contested, the
    game waits on a decision: pay off the claimants (gold), crown the strongest claimant (a new
    dynasty, legitimacy cost, no war), or stand firm (each claimant rises in civil war). AI
    empires still resolve these by rule.
  - **Logistics on screen** (Josh: "I don't see grain or trade routes"): the header shows gold and
    grain with their change per turn; map layers show supply lines from the capital (orange/red
    where distance costs extra grain, cut-off land in red), trade routes along their real paths
    with strait holders, and each territory's grain and resources; an Economy section breaks down
    grain (harvest, people, armies, long supply lines, crews), gold (taxes, mines, trade), trade
    partners, bronze and the resources within reach. Forecasts come from `Engine.economy`, which
    runs the harvest on a scratch copy, so they match what happens. Declaring war asks first.
  - Iron is not shown: the Bronze → Iron Age shift is still post-MVP.

## Late Bronze Age redesign (Josh, after the playable build)

Josh's framing: the game covers **the end of the Bronze Age** and is **"Risk with logistics."**
Decisions (his answers, with the details filled in):

- **New resources**: **iron** (ore in the ground, useless until Metallurgy reaches ironworking,
  then it arms troops without needing tin), **wine & oil** (sells for gold, more when exported to a
  partner who lacks it), **luxuries** (purple dye, papyrus, ivory, incense: feed legitimacy), and
  **stone** (builds projects). Non-grain resources now also accumulate in **stockpiles**.
- **Technology is not chosen.** Each civ earns knowledge at a rate set by **population and wealth**.
  It flows into **fields** in proportion to recent **experience**: naval battles and sea trade build
  Seafaring, cavalry fighting and horses build Horsemanship, harvests build Agriculture, bronze and
  iron ore build Metallurgy, projects and stone build Construction, battles build Warfare, trade and
  wealth build Administration. **Contact** (a shared border or trade route) with a more advanced
  civ passes part of their lead each turn. Fields and levels are **revealed by experience**: a
  desert empire that never sails never sees Navigation.
- **Taxes and investment**: a **tax slider**. Higher taxes give more gold to invest (projects,
  armies) but slow population growth and drain legitimacy; lower taxes leave more to consumption:
  growth and goodwill, less gold.
- **Projects**: spend gold, stone and timber on **roads** (supply lines through them cost nothing),
  **walls** (defense), **farms** (grain), **mines** (more ore) and **harbors** (trade income,
  cheaper ships). They take turns to build and are captured with the land; earthquakes and raids
  can destroy them.
- **The collapse arc** (escalating, scripted): from round 12, pressure rises toward round 40. **Sea
  Peoples** raid coasts from the sea, **droughts** deepen, **earthquakes** wreck buildings, and
  **trade routes break** for several rounds at a time. **Bronze wears out** without a steady tin
  supply; **iron** doesn't need tin. Tin-dependent palace empires crack; iron-workers endure.
- **Trade made visible**: the map shows what goods flow along each route.

### Knowledge model (phase 2, as built)

- **Points a turn** = 10 × max(1, population/10 + income/5), in tenths of a point so small shares
  still count. They split across fields in proportion to **experience**; leftovers go to the
  most practiced field. Levels are reached at 8, 24 and 56 points (lowered from 12/36/80 so most
  civs reach level 1 in a few fields by round 20).
- **Experience each harvest**: Agriculture production/8; Metallurgy bronze + 2 × iron ore;
  Horsemanship 2 × horses; Seafaring ships + 2 × sea routes; Construction stone; Administration
  routes + territories/6 + income/10. **Events add more**: every land battle gives Warfare
  3 + (infantry + archers)/3 and Horsemanship 2 × cavalry to both sides; naval battles give
  Seafaring 5 to both sides; a finished project gives Construction 4 (farms add Agriculture,
  mines Metallurgy). Experience **fades 10% a turn**, so direction follows recent practice.
- **Diffusion**: each field gains the best of its contacts' leads × 2% (neighbor) or 5% (trade
  partner). Kept low on purpose: at 5%/10% every civ converged on the same profile within 30 turns.
- **Levels** (and what each does):
  Agriculture: Irrigation (+1 grain in river valleys), Granaries (store 2 turns of grain more), Crop
  rotation (+1 grain from farms). Metallurgy: Bronze casting (+50% bronze), Ironworking (iron ore
  becomes usable), Steel (iron counts double for equipment). Horsemanship: Chariots (cavalry +15%),
  Horse breeding (2 cavalry per horse), Horse archers (cavalry +15% more). Seafaring: Galleys (+1
  troop per ship), Navigation (+30% at sea), Triremes (+30% more). Construction: Masonry (projects
  a turn faster), Fortification (walls +15%), Engineering (1 less stone and timber). Warfare: Drill
  (infantry +10%), Composite bows (archers +15%), Tactics (+10 morale). Administration: Writing
  (+10 loyalty), Coinage (+20% taxes), Law (+1 legitimacy a turn).
- A field appears in a civ's tree only once it has some experience or knowledge of it.

### The collapse (phase 3, as built)

- **Pressure** runs 0 → 100 between rounds 12 and 40. At full pressure the chance of an event each
  turn rises from 50% to 80%, and four collapse events join the table with weights scaled by
  pressure:
  - **Sea Peoples** (6 per coastal territory): 3 + pressure/25 raiders (two-thirds infantry, a
    third archers) land in a random coastal territory. If they win, they burn its buildings and
    hold it as barbarians; if they lose, the survivors sail away.
  - **Drought** (30, +20 with no river valley): the three richest non-river territories harvest
    at half (river valleys go last).
  - **Earthquake** (10, +4 per hill or mountain territory): a rugged territory loses 1 population
    and its construction site, or one finished building.
  - **Trade disruption** (15 per route): one trade route breaks for 3 rounds.
- **Bronze wears** 5% a harvest (rounded up), so a stockpile melts without fresh tin.
- **Iron arms troops** once Ironworking is known: equipment = (bronze + iron in store × weight) /
  units, with weight 1 (2 with Steel). Iron in store doesn't wear.
- First sims (40 games): the collapse fires at sensible rates, but half the games are already
  decided by round 25, before it peaks. Pacing it against domination is phase 4's job.

### AI and balance after the redesign (phase 4)

- The AI treats every coast as a front once collapse pressure reaches 25 (armies hold coasts instead
  of all marching to the land border), and walls its most populous coast before building mines.
- The sim reports average knowledge levels at round 20 and projects built and lost per game.
- 40 games after phase 4: average length about 40 rounds (34 before the collapse); endings 17
  decisive domination, 2 major domination, 11 major legacy, 10 minor legacy. Wins: Mesopotamia 52%,
  Greece 17%, Egypt 17%, Italia 12%. About 20 projects built and 3–4 lost per civ per game. By round
  20 Mesopotamia leads in horsemanship (1.7) and metallurgy; everyone has some seafaring.
- **Still open**: Mesopotamia's early lead (it wins about half, as before the redesign), and
  defenders still rarely hold (about 25%).

### Balance pass (after phase 5)

Three targets. Josh's order after the first round: **defenders rarely holding** (priority 1:
"seems like a big issue"), then the AI hoarding gold, then Mesopotamia winning half the games.
Rules version 4, so older saves are ignored.

**What was wrong**

- **Defending had no edge.** In formation mirrors on open plains the attacker won (phalanx v
  phalanx 62%, hammer v hammer 58%, refused flank 81%, wedge 100%; `hegemon-sim formations
  --seeds 200`). The advancing side picks where to engage and gangs up on holding blocks for the
  flank-morale penalty, and open ground gave the defender nothing. Battles were also close to a
  step function: per-strike and per-round luck average out over 20 rounds, so a quarter more
  troops won almost every time and any flat bonus decided equal fights outright.
  The headline "defences held 25%" was mostly beaten raids. **Against another civ, defences held
  1–2%.** The AI attacks only what its own battle estimate says it will win, and most civ-vs-civ
  battles were fought at 2× odds or more (377 of 616).
- **Gold had nothing to buy.** The AI started one project a turn, but the deeper problem is that
  grain, not gold, caps every army: population grows to eat any surplus, so recruiting stalls on
  food long before money. Once an empire had built everything (or ran out of timber), gold just
  piled up. A grain-poor, wine-rich Greece had no way at all to turn gold into soldiers.
- **Mesopotamia's edge is the map, not its personality.** With every civ given the same
  temperament it still wins 47% (all opportunists) and 57% (all turtles). A 9-grain river capital
  plus Persia feeds about 16 troops by round 10 (others 7 to 11), and five weak native lands sit
  next door on foot. 14 of its 21 wins were dominations before round 50, most by round 25. Its
  counterweights don't bite: barbarian hordes are 3 + round/8 units against a 20-unit army, and
  the collapse hits coasts (Sea Peoples) and dry land (drought), which spares an inland river
  valley. Making expansion harder in general backfires: tougher natives (77%) or +15% defence
  everywhere (72%) help Mesopotamia, because only it has the army to push through. Trimming its
  grain (capital 8, Persia 3) looked good on one set of 40 seeds (37%) and did nothing on another
  (55%).

**Rule changes: battles**

- **Fortune of the day** (`battle.dayFortunePercent`: 40). Each side draws its luck once per
  battle, scaling all its damage by up to 40% either way. Unlike the per-round roll it doesn't
  average out, so an edge makes a battle likely rather than certain. This is what lets a modest
  defender edge read as modest.
- **Home ground** (`battle.homeGroundPercent`: 2). Every defender takes 2% less damage, on top of
  terrain and walls. Small on paper, but it tips the even fights: values from 1 to 5 all play the
  same because of rounding in the damage steps. A first try at 10% (without day fortune) made the
  defender hold 86% of mirror matchups and stretched games toward round 50, so it was replaced.
- **Walls 25% → 35%** (`projectEffects.wallsDefensePercent`; 50% with Fortification) and **river
  crossings 20% → 30%** (`battle.crossingPenaltyPercent.river`). With these, walls or a river
  alone make the attacker want about 1.5×, and walls on a hill about 2×, as in Risk.

Formations, attacker win % on plains (4 infantry, 2 archers, 2 cavalry each, 200 seeds):

```
before               phalanx hammer  skirm  refused  wedge   after   phalanx hammer  skirm  refused  wedge
phalanx                  62%    87%   100%      86%    93%              37%    59%    85%      49%    63%
hammer_and_anvil         59%    58%    94%      91%    97%              38%    40%    60%      58%    61%
skirmish_screen           2%     0%    62%       6%     0%              15%    12%    40%      20%    17%
refused_flank            46%    41%   100%      81%    91%              41%    37%    63%      44%    53%
wedge                    15%    77%   100%      26%   100%              33%    45%    81%      35%    75%
```

The defender now holds 56–63% of mirrors (Josh's target 55–60%). The wedge mirror still favors the
attacker (75%), but the AI almost never fields wedge. Formations also matter less: the worst
pairing is no longer a sure thing either way.

Attacker win % by odds (`hegemon-sim defence`; mixed armies; the defender picks a formation and
the attacker answers it, as the AI does, which is why 4v4 on plains is 56% here):

```
                          before                       after
                   1.25x  1.5x   2x   (5v4 6v4 8v4)   1.25x  1.5x   2x
plains                 100%  100% 100%                  86%  100% 100%
plains, walls          93%  100% 100%                  35%   90% 100%
plains, across river      -                             35%   90% 100%
hills                  98%  100% 100%                  65%  100% 100%
hills, walls            8%   98% 100%                  11%   56%  90%
```

**Rule changes: economy and the collapse**

- **Grain imports.** At harvest, if the home pocket would go hungry after the granary is emptied,
  it buys grain from trade partners: up to 2 per active route (`trade.grainPerRoute`), at 3 gold
  each (`trade.grainPrice`). Broken routes (war, the collapse) cut it off, which is the
  period's story: palace economies that lived on imported grain fell when trade broke. Imports only
  cover a shortfall; they never feed growth. New event `grainImported`; the Economy report gains
  `grainImportCap`. Chosen over a buy-grain command because it is automatic (the player makes
  Risk-sized decisions) and it uses routes, not haggling.
- **Migrations swell with the collapse.** The collapse adds barbarian raids to its event table, 20
  weight per exposure to a barbarian homeland at full pressure (`collapse.weights.migrationsPerExposure`),
  and hordes gain pressure/20 units (`collapse.migrationPressurePerExtra`), up to +5. This is the
  land twin of the Sea Peoples: the Arameans out of the Syrian desert, the steppe and northern
  forest peoples. It falls hardest on the empire with the longest open frontier, which is
  Mesopotamia (about 24 raids per 100 turns, was 17), but also on Egypt's desert flanks and
  Greece's Danube.

**AI changes**

- **Invests several projects a turn** (up to 4) while keeping a reserve of 4 × infantry cost + 1
  per territory. Same priorities as before, plus walls on the border post facing the most enemy
  troops where a garrison stands.
- **Raises troops on imported grain** as long as the treasury beyond the reserve could pay for 8
  turns of it.
- **Cuts taxes when gold can't be spent**: 10 below default above reserve + 30, 20 below above
  3 × reserve + 30, and 0% above 6 × reserve + 60. Unspendable gold becomes legitimacy instead.
- Fix: fleets no longer try to sail through a strait held by an enemy (a latent bug that showed
  up as rejected commands once games ran differently).

**Sim tool**: `hegemon-sim defence` (attacker win % by size, terrain, walls and river crossing);
`--set KEY=VALUE` to override any rules number for one run (e.g. `--set
battle.dayFortunePercent=30`), so balance ideas can be tried without rebuilding; a "vs civs held"
column next to "defences held"; a table of civ-against-civ battles by force ratio; median gold in
hand and units at rounds 10, 20 and 30 (civs holding land only); and each game line names how it
was won.

**Before and after** (40 games, seeds 1–40, default personalities, shuffled seating)

```
                          before                                  after
civ          wins  led r10  def held  vs civs held    wins  led r10  def held  vs civs held
greece        17%      2%      24%        2%            12%      0%      39%        5%
egypt         17%     17%      17%        1%             7%      7%      31%        3%
italia        12%      5%      27%        1%            17%      7%      46%        1%
mesopotamia   52%     55%      26%        2%            62%     67%      48%       12%

endings   before: 17 decisive domination, 2 major domination, 11 major legacy, 10 minor legacy
          after:  10 decisive domination, 1 major domination, 18 major legacy, 11 minor legacy
length    36 → 41 rounds; lead changes per game 2.1 → 2.0
civ-vs-civ battles  616 → 306; attacker won 94–99% → 82–99% (lowest at even odds)
median gold in hand   r20 before → after   r30 before → after
  greece                  171 → 85              270 → 141
  egypt                    53 → 21               89 → 45
  italia                   48 → 37               87 → 85
  mesopotamia              99 → 28              210 → 141
projects built per game  16–24 → 21–47
```

Seeds 101–140 after: Mesopotamia 65%, Italia 20%, Greece 10%, Egypt 5%; 42 rounds; 9
dominations, 30 legacy, 1 trade; defences held 28–54%, against civs 7–10%.

**What it means**

- **Defending works as a rule.** Even fights lean to the defender, walls and rivers ask for 1.5×,
  walls on a hill for 2×. For a human player that is what counts. In AI-vs-AI games the
  civ-vs-civ hold rate stays low (1–12%) because the AI still only attacks what it expects to
  win. That is the AI playing well, not the battle system favoring attackers. What changed is
  that it now needs real odds to attack: there are half as many civ-vs-civ battles.
- **Pace holds.** Games run 41 rounds (36 before), and 11 of 40 still end in domination (19
  before). An earlier version with a 10% home-ground bonus ran to 45 rounds with 6 dominations.
- **Mesopotamia is stronger again: 62–65% wins (52% before).** The 10% home-ground version had
  held it to 40%, by making every conquest of a defended civ slow. The modest edge Josh asked for
  doesn't do that, and day fortune doesn't hurt the side with the biggest army. Stronger
  migrations (twice the weight, twice the growth) and bigger hordes in general were tried on both
  seed sets: Mesopotamia 50–65%, games 41–46 rounds. Neither is worth keeping.

**Still open**

- **Mesopotamia** (priority 3) needs a lever aimed at its early army, not at defence in general.
  Candidates, in the order I'd try them: its starting realm (Persia) given to the natives, so it
  starts with one territory like Italia; a supply cost for armies far from the river; or making
  the AI's opportunist personality less greedy when it's already ahead.
- **Egypt is the weak civ** (5–7% wins, collapses in 57–70% of games). The turtle sits behind
  desert flanks that border two barbarian homelands, and the migrations find it.
- **Greece still banks gold** in long peaceful games: everything built, grain already imported up
  to the cap, nothing left to buy. Its gold counts for prestige (gold/2) at round 50, so this is
  partly a legacy strategy. A real fix needs something new to buy (e.g. temples or monuments for
  prestige), which is a design call for Josh.
- **Archers attacking infantry** on open ground are now roughly even (86% before; the test
  asks for at least 40%); defending, archers still beat infantry.

### Mesopotamia and Egypt (balance pass, part 3)

*Superseded by "Capital-only starts" below: Egypt no longer starts with Syria, and
Mesopotamia's capital is back to 9 grain.*

After the defence changes Mesopotamia won 62–65% and Egypt 5–7%. Josh's aim: Mesopotamia can still
be the strongest (about 30–40%), the others 15–30%, without slowing games or weakening defence.
Rules version 5 and map version 2, so saves from before this change are ignored.

**Changes (map and starting realms)**

- **Egypt starts with Syria** (`start.realms.egypt`: Libya, Petraea, Syria). New Kingdom Egypt held
  the Levant in the Late Bronze Age, so this is the period's map. It takes Mesopotamia's richest
  westward target (4 grain, timber, wine) and gives Egypt a real frontier and a Mediterranean
  trade coast, instead of two 1-grain deserts.
- **Mesopotamia's capital grain 9 → 8** (`map.json`). It is still the second-richest land on
  the map after Egypt's Nile (10), so the river-valley identity stays.

**What was tried** (40 games each, seeds 1–40 and 101–140; Mesopotamia's wins)

```
Persia to the natives (Mesopotamia starts with one territory)    50% / 32%   games 46–48 rounds, 2–5 dominations
  ... and Egypt loses Libya                                      75% / 55%   Egypt only gets weaker
Persia to the natives and Egypt starts with Syria                17% / 17%   Egypt leads instead; overshoots
Egypt starts with Syria                                          45% / 40%
Egypt starts with Syria, Persia grain 4 → 3                      37% / 32%   Italia 10% on one set
Egypt starts with Syria, Mesopotamia grain 9 → 8 (chosen)        32% / 32%
```

Persia to the natives worked on Mesopotamia but stalled the game: nobody else had the army to
dominate, so most games ran to round 50. Giving Egypt Syria works the other way, by giving
Mesopotamia a real rival next door.

**Before and after** (40 games; first number seeds 1–40, second seeds 101–140)

```
                    before (5e9b244)                       after
civ          wins       led r10    def held        wins       led r10    def held
greece       12% / 10%   0% /  2%   39% / 54%      22% / 25%   7% /  7%   29% / 40%
egypt         7% /  5%   7% / 10%   31% / 28%      22% / 22%  37% / 37%   26% / 24%
italia       17% / 20%   7% / 10%   46% / 44%      22% / 20%  12% /  7%   44% / 52%
mesopotamia  62% / 65%  67% / 75%   48% / 44%      32% / 32%  35% / 37%   32% / 42%

length       41 / 42 rounds  →  38 / 43 rounds
endings      11 / 9 dominations, 29 / 30 legacy, 0 / 1 trade  →  16 / 10 dominations, 23 / 30 legacy, 1 / 0 trade
round-10 leader won   50% / 60%  →  50% / 57%
```

**What it means**: every civ now wins 20–32% on both seed sets. Mesopotamia is still the most
likely winner, but Egypt and Mesopotamia now share the early lead (each leads at round 10 in
about a third of games) and the lead moves on from there. Games are as quick or quicker, with
more domination endings. Defences held dip a little (24–52%, from 28–54%): Mesopotamia and Egypt
now border each other and fight more evenly matched wars. Against other civs the hold rate is
unchanged (1–16%).

**Still open**: Egypt still collapses in about 70% of games (it rises early and falls to the
migrations), so its wins come from early dominations more than from lasting. Greece still banks
gold in long peaceful games.

### Capital-only starts (Josh)

**Decision**: every civilization starts with one territory, its capital. `start.realms` is
empty for all; native garrisons stay. Rules version 6, map version 3, so older saves are ignored.

With no other change (40 games, seeds 1–40 / 101–140), Greece won 2% / 0% and never held more
than about 2 territories. Its 2-grain capital fed two soldiers and nothing more. Italia won
10% / 15% and collapsed in two-thirds of games; Egypt and Mesopotamia shared the rest.

**What made the Mycenaeans a power was the sea**, not farmland: ships and rowers, trade (wine
and oil out, tin and grain in), raids, and the Aegean islands. Italia's road out is the sea too:
its only land neighbor is the Alps, and Sicily is a crossing away. So the two sea powers get
starts that let a small, poor homeland put a real force to sea.

**Per-civ starts** (new optional `start` fields, all in `rules.json`):

- **Greece**: 5 infantry (`start.armies`), a war chest of 20 grain (`start.granaries`; it may
  exceed the usual cap and is drawn down while the army outgrows the land), 1 ship in the
  Aegean (`start.fleets`), and Galleys known (seafaring at level 1, `start.knowledge`), inherited
  from the Minoans. Capital grain 2 → 3, standing in for Messenia and the Kopais basin.
- **Italia**: 5 infantry, 20 grain, 1 ship in the Tyrrhenian.
- **Egypt**: capital grain 10 → 8. Alone on the Nile with five weak desert neighbors, Egypt
  became the runaway civ once the others lost their heartlands.
- **Mesopotamia**: capital grain back to 9 (the 9 → 8 cut was for the heartland map).
- Egypt's Syria start is reverted (it was a heartland).
- Everyone else starts with the standard 2 infantry and 6 grain.

**Rule changes**:

- **Island natives are lighter**: territories with no land border (Crete, Cyprus, Sardinia,
  Hibernia, the Sitones) hold 1 + grain ÷ 3 natives instead of 2 + grain ÷ 3
  (`start.natives.islandBase`). Island peoples were fewer and scattered. At 0 the free islands
  helped Italia more than Greece, so 1 it is.
- **Overseas grain**: every coastal territory in the home network can buy 1 grain a turn from
  overseas merchants (`trade.grainPerCoast`), plus 2 more with a harbor (`trade.grainPerHarbor`),
  on top of the 2 per trade route. Without it, grain imports only began once a civ had trade
  partners, which is too late for a grain-poor coast. The AI builds a harbor on a hungry coast.
- **The AI values wine, luxuries, stone and iron** when weighing land (it counted only grain,
  metals, horses, timber and gold), so Crete and the islands are worth an expedition.

**Tried and dropped**: 2 ships for Greece at the start (crews eat grain, so Greece starved; with
a bigger war chest it helped Greece a little and Mesopotamia more); Greece as opportunist or
conqueror instead of merchant (5–7% either way); island natives at 0; capital grain 4 for Greece
(beyond Josh's cap; Greece peaks at 6–7 territories but still wins 5–7%).

**Before and after** (40 games; seeds 1–40 / 101–140; "before" is capital-only with no fixes)

```
                         before                                    after
civ          wins       peak land   def held        wins       peak land   def held
greece        2% /  0%  1.8 / 1.6   37% / 39%        5% /  7%  4.4 / 5.5   57% / 51%
egypt        42% / 35%   15 / 14    33% / 32%       32% / 27%   11 / 11    38% / 32%
italia       10% / 15%  7.9 / 9.0   29% / 34%       22% / 27%   12 / 14    41% / 36%
mesopotamia  40% / 47%   14 / 15    33% / 29%       40% / 37%   15 / 15    41% / 36%

length       44 / 42 rounds  →  43 / 42 rounds; every game decided by round 50
endings      8 / 12 dominations, 32 / 28 legacy  →  10 / 10 dominations, 30 / 30 legacy
```

**Where it lands against Josh's targets**: Mesopotamia 37–40% (target 25–40%) ✓; Egypt and
Italia 22–32% ✓; games about 42 rounds, all decided by 50 ✓; defences held 32–57% (about where
they were) ✓. **Greece misses**: it wins 5–7% (target 10%+), and peaks at 4.4–5.5 territories
(target over 5). Greece now grows, to 4–6 territories at its peak, but it collapses in 27–40%
of games: it is all coastline, and the Sea Peoples fall hardest on coasts.

**Next lever for Greece** (not yet tried): the collapse. Sea Peoples weight is 6 per coastal
territory, so an all-coast Greece draws the most raids. Options are a lower per-coast weight,
or walls counting against Sea Peoples landings; both would also help Italia and Egypt's Delta.


### Greece is meant to be hard (Josh, after capital-only starts)

Greece wins 5–7% of sim games and falls apart in 27–40%, mostly to the Sea Peoples, because it
is all coastline. Josh accepted this as it stands: "That's just real life. It's not perfectly
balanced. It'll just be harder to win as them." The Mycenaean palaces did burn around 1200 BC.
No further fixes for Greece: walls against Sea Peoples landings and lighter coastal raids were
both considered and set aside. The 10%-minimum target doesn't apply to Greece.

### Battle plans unlocked by generals and knowledge (Josh, after the UI pass)

Josh: options for formation and strategy, "a smaller army will have less depth optionally,
cavalry on the wings, feigned retreat… more options depending on generals and/or experience on
the war tech tree." Decided: gate the existing formations too.

- A **battle plan** is a formation, a line depth and an optional stratagem, kept on the army
  (`Army.plan`, set with `.setBattlePlan`). Attacks use the attacking army's plan, defences the
  garrison's.
- **Unlocks** (`battle.plans` in rules.json): knowledge counts for every army; a general's trait
  counts only when that general leads the army. Either is enough.

| Option | Unlocked by |
|---|---|
| Phalanx, Skirmish screen | always |
| Hammer and anvil | Chariots (Horsemanship 1) or a Cavalry Commander |
| Wedge | Drill (Warfare 1) or a Reckless general |
| Refused flank | Composite bows (Warfare 2) or a Tactician |
| Stand fast | always |
| Feigned retreat (needs cavalry) | Horse breeding (Horsemanship 2) or a Cavalry Commander |
| Shield wall | Drill (Warfare 1) |
| Flanking march | Tactics (Warfare 3) or a Tactician |

- **Line depth**: *deep* is the formation as drawn; *wide* puts every block in the front rank
  first (center outward), so a small army can't be outflanked but has no reserve.
- **Stratagems**: *Stand fast*: nobody advances unless struck, +10 morale. *Feigned retreat*: the
  cavalry falls back a square in round 1 while the rest wait; enemy blocks that move in rounds 1–2
  are disordered and take +30% damage until the end of round 3. *Shield wall*: infantry takes 25%
  less from arrows and moves only every other round. *Flanking march*: blocks on the formation's
  outer columns start a rank further forward, if the square is free.
- A plan is checked when set (against the general standing with the army) and again at battle:
  whatever isn't unlocked for the army as it actually fights (its general stayed behind or died, or
  a feigned retreat with no cavalry) falls back to the default formation and no stratagem.
- **AI**: attacking, it picks its best unlocked formation by simulated odds, then tries a wide line
  and each unlocked attacking stratagem and keeps whichever improves the odds. Defending, the same
  with a wide line, stand fast and shield wall.
- **Sims** (80 games, two seed sets): average length 43–46 rounds (was 42–43); dominations 11 and 4
  (was 10 and 10). Wins: Egypt 35–42%, Mesopotamia 25–35%, Italia 22–30%, Greece 2–7%. Egypt gains
  because Thutmose, a Cavalry Commander, unlocks hammer and anvil and the feigned retreat from the
  start: an Egyptian chariot edge, kept. Advanced options are used in a few percent of battles,
  since few civs reach the knowledge by mid-game.
- Also fixed on the way: the naval AI no longer builds ships whose crews the harvest can't feed,
  and brings troops home instead of leaving a too-small landing force to starve at sea.

### No exact odds (Josh)

"I don't like knowing the odds so specifically in advance… let's just say their numbers are roughly
the same as ours." The player never sees a win percentage. Before an attack a **scouts' report**
says how the numbers compare (greatly outnumber / outnumber / roughly the same / outnumbered /
greatly outnumbered, by troop ratio), what favours the defender (walls, hills or mountains or
forest, a river or strait crossing, a landing from the sea, a general), and the officers' outlook
in one word from the simulated odds: Confident (80%+), Favourable (60–80), Uncertain (40–60),
Risky (20–40), Desperate. Formation cards and the attack arrow show the same word. The AI still
uses the exact estimate internally.

### The levy (Josh: "if you're attacked you should be able to raise an army from your population, even if they're low skill")

Turns are sequential, so the player can't act while a rival attacks; the levy rises by itself.
- When an empire's land is attacked, its people take up arms beside any garrison: **1 militiaman
  per 3 people, at most 3**, where at least 2 live (`battle.levy` in rules.json). Native and
  unclaimed land has its own garrisons and raises no levy.
- Militia fight as infantry blocks marked *militia*: **half damage**, **30 less morale**, and no
  bronze or knowledge bonuses.
- Every militiaman who falls is a person lost from that territory; survivors go home and don't
  join the army.
- Empty land of an empire with people in it is no longer taken by walking in: the levy fights.
- The AI knows: its attack options, battle estimates, landings and defensive planning all count
  the levy.
- Sims (80 games, two seed sets): first tried 1 per 2 people up to 4; Mesopotamia's populous river
  valley made it 40–45% wins. At 1 per 3 up to 3: Egypt 30–37%, Mesopotamia 32–35%, Italia 27%,
  Greece 2–7%; about 45 rounds a game.

### Diplomacy tab (Josh)

A "Rivals" tab (headed Diplomacy; the toolbar's people button opens it) with a card per rival:
war or peace and the action (offer peace / accept / declare war, with confirmation), land, troops
and prestige, the ruler and how secure they are, whether they border you and where, and any trade
route with the goods each side receives and tolls paid. The Empire tab is renamed Realm.

### Disbanding (Josh)

`.disband(territory:units:)` sends any number of the player's soldiers home. On the empire's own
land each becomes a person again, up to the land's population cap; elsewhere they scatter. No gold
comes back, so recruiting and disbanding can't be cycled for profit; the gain is the grain their
upkeep was costing. It's undoable like any other order. The AI doesn't disband yet.

### Look and feel (polish pass)

- **Title screen**: the painted board drifting behind a bronze serif title and "The end of the
  Bronze Age · 1200 BC"; each empire a hanging banner (emblem, tagline, general, government);
  choosing one sounds a horn before the game starts.
- **Map**: terrain keeps its own colour; ownership is a bold inner border in the empire's colour
  with a light wash. A paper grain and painted wave marks make it read as the board.
- **Moments**: captures, losses, discoveries, war and peace, and disasters on the player's land
  appear one at a time as ribbon banners with sound and haptics; captures sweep the new owner's
  colour over the land, disasters shake or tint the screen.
- **Movement**: marches and landings glide along their path before settling into arrows; battles
  burst; while rivals move the camera follows them. When watching, each round's arrows replace the
  last's.
- **Battles**: terrain-coloured ground with marks, rocks, a river across the field for crossings,
  a bronze frame on parchment, dust on hits, and a Victory/Defeat banner at the end. Routs read
  as "X broke and fled; nobody fell".
- **End of game**: a full-screen Victory or Defeat with the victory type, standings, and the
  borders replayed round by round (the session records who held what each round).
- **Sounds**: a click on selection, a drum on End turn, coins when spending.

### The battlefield, the chase, and tribes (Josh: "choose the battle plan after you move to the battle map… are we winning? If they flee, do we chase?… if I tap a country held by no one… diplomacy")

- **Plan on the field.** Ordering an attack picks troops and the general, then "To the
  battlefield" opens the 5×5 board with both armies deployed exactly as they would stand
  (`BattleSimulator.deployment`, which rolls nothing). Changing formation, line or stratagem
  moves the blocks. War drums play while the armies draw up; "Charge!" roars, sets the plan and
  fights, and the battle plays out on the same board. Landings still fight in the army's
  standing plan (there is no army ashore to plan with).
- **Are we winning?** A tug-of-war bar compares the two sides' strength each round (men still in
  the line, weighted by morale; broken blocks count for little) with the officers' word for it,
  and a caption narrates each round ("The lines crash together!", "Their cavalry break and run!",
  losses on each side). At the end the bar swings to the winner.
- **The chase.** A new choice in every battle plan: *chase them* or *hold the field*. Chasing
  cuts down 25% of the beaten survivors (40% if the winner still has cavalry); archers covering
  the retreat fell one pursuer per 3 archers (cavalry first). Holding lets them go with no risk.
  Before this the rout always happened. The replay shows the beaten running off the board,
  horsemen riding after them, and says what the chase cost. Defenders can set it too, in the
  territory's defensive plan.
- **Tribes.** Unclaimed land held by natives, next to the player's land, has a Diplomacy card:
  - **Gifts**: 3 gold + 2 per warrior, with a chance described in words. The chance is
    40% + 8% per own troop next door beyond their warriors, ± half of legitimacy above 50,
    +10% with Writing, clamped to 10–85%.
  - **Demand submission**: free, but it works only with 3× their warriors at the border. A
    refusal costs 3 legitimacy and adds a warrior.
  - **Attack.**
  - Either way, a tribe that comes over becomes your land and half its warriors join as
    infantry. One parley per tribe per turn.
  - Tribes don't trade or sign treaties; that's for civilizations, on the Rivals tab.
  - The AI doesn't parley yet.
- **Balance check**: 40 games on each of two seed sets, against a baseline with the new pursuit
  rules switched off (`--set battle.pursuitCavalryPercent=0 --set battle.rearguardArchersPerLoss=1000`).
  Win shares moved within noise: Greece 2/7% → 0/12%, Egypt 37/30% → 42/15%, Italia 27/27% →
  30/32%, Mesopotamia 32/35% → 27/40%. Game length (44–47 rounds) and defences held were
  unchanged. The AI always chases.

### Army pay and the overland haul (Josh: "they should cost a small amount of gold to maintain"; "I do want having roads and ships make a difference")

- **Pay**: every 4 soldiers (on land or aboard ship) draw 1 gold a turn, rounded down, so a
  guard of up to 3 is free. It's paid after the harvest. When the treasury can't cover it, half
  of the unpaid soldiers go home, from the largest stacks. Ships' crews still cost grain only.
  The AI raises troops only while pay stays within about three quarters of its income.
- **Haul**: each soldier eats 1 grain a turn, plus 1 for every 3 *overland* steps grain is
  carted to him from the capital. A road makes its step free, and so does a sea leg through a
  sea where the civ has ships. That's the real logic of ancient logistics: carts and oxen ate
  the cargo, ships didn't. It replaces the old surcharge, which counted sea steps double and
  didn't care about ships. Cut-off armies still lose a unit a turn.
- **Naval AI**: boards only a force that could land (two thirds of what the ships carry), and
  empty fleets wait at a port with troops. This ended a loop where Greece shuttled two soldiers
  on and off a ship every turn.
- **Balance** (40 games × 2 seed sets, against the build before): Mesopotamia 27/40% → 42/45%,
  Italia 30/32% → 32/22%, Egypt 42/15% → 22/20% (it collapses more; its westward desert push
  is a long haul), Greece 0/12% → 2/12%. Armies are smaller (Italia's median 18–20 units at
  round 30). Rules version 10.

### Throne room and council (Josh: "a throne room you can decorate + a council of advisors")

- **Throne room** (crown button on the toolbar): the ruler's hall drawn in the empire's style
  (Egyptian sandstone, Greek painted megaron, Italic timber, Mesopotamian glazed brick).
- **Decorations**: seven pieces, bought with gold and stockpiled stone or timber:
  - braziers 5 gold;
  - purple hangings 10 gold;
  - painted columns 6 gold + 3 stone;
  - cedar ceiling 8 gold + 3 timber;
  - mosaic floor 8 gold + 3 stone;
  - statue of the ruler 10 gold + 4 stone;
  - gilded throne 14 gold.
  Each adds 1–3 magnificence, and each appears in the hall.
- **Trophies**, won automatically and shown on a shelf, 2 magnificence each:
  - a rival's standard when you take its capital (once per rival);
  - a raider's shield each time raiders are beaten off your land;
  - a tribe's totem when it swears to you.
- **Magnificence** adds 2 prestige a point (prestige decides a round-50 legacy victory). A
  smooth succession needs less legitimacy, by magnificence ÷ 2 (at most 10 less). The AI
  decorates only with gold beyond three times its reserve, which gives hoarding realms (Greece)
  something to spend on.
- **Council**: four advisors with names in each empire's style. Each says the one most
  pressing thing in their field, with a button to go to the place or tab:
  - the general: the worst threat to our land, else the best attack on offer;
  - the steward: grain deficit, pay outrunning income, cut-off land, or idle gold;
  - the envoy: peace offers, a tribe likely to take gifts, or a missing resource a rival holds;
  - the high priest: bad omens, low legitimacy, an old king without a safe heir, or the
    coming collapse.
  The crown button shows a badge for advisors who sound the alarm.
- **Balance** (40 games × 2): Mesopotamia 50/42%, Italia 27/25%, Egypt 17/17%, Greece 5/15%.
  Rules version 11.
- **Egypt fixed** (Josh: "fix egypt"). Over 120 games Egypt sat at 16–18% with pay and the
  haul on or off, so neither caused it; the earlier 42% on seed 1 was noise. Its land was being
  lost to barbarian migrations: 77 of 175 lost territories over 30 games went to raiders out of
  Sahara and Arabia. Those are barbarian homelands, and the AI kept settling them and the land
  bordering them, and every such front draws more migrations. Historically Egypt was the realm
  that weathered the collapse.
  - The AI now values unclaimed homelands at −2.5, and −1.2 for each new homeland border a
    claim would open. Rival land is valued as before.
  - Land the AI won't settle no longer counts as room to expand, so it still turns on its
    neighbours once the good land is gone.
  - 120 games, seeds 501–620:
    - Egypt 16% → 24%, collapses 55% → 44%;
    - Italia 35% → 28%;
    - Mesopotamia 40% → 44%;
    - Greece 6% → 3%;
    - games 39 → 46 rounds, dominations 41 → 15.

### Veterans, spoils, court influence, and readability (Josh, playtesting build 12)

- **Veterans** ("armies should also get a veteran status and improve as they survive battles"):
  - Each army carries its soldiers' average number of battles survived (`Army.battles`; for
    troops at sea, `Fleet.cargoBattles`). Every survivor of a battle, on either side, gains one.
  - Recruits are green and dilute the average (rounded to nearest). Marches, landings,
    retreats and fall-backs carry their honours with them.
  - Ranks: Blooded at 1 battle, Veteran at 2, Elite at 4. Each rank adds +6% strength to every
    unit type and +5 morale. The map shows gold chevrons, one per rank; the territory card
    shows the rank and battles to the next; the battlefield and the scouts compare ranks.
- **Spoils**: every territory taken by force adds a spoils trophy (1 magnificence each, 8 at
  most). A rival's capital still gives its standard (2).
- **A splendid court**:
  - +1 legitimacy a turn per 5 magnificence (at most +2);
  - tribes are 1% likelier to take gifts per point;
  - at magnificence 10, rivals accept your peace offers even when they'd rather fight,
    unless they're twice your strength.
- **Readability**:
  - **People** total in the status bar (tap for the breakdown and room to grow).
  - **People counter** on every territory at every zoom.
  - **Buildings on the map**: roads, walls and harbors always shown beside the token; farms,
    mines and works in progress too once zoomed in.
  - **Sea names** on the map in italic, brighter for the seas next to the selected territory.
  - **Fleets** shown as coloured chips with what's aboard.
  - **Discoveries** say in a sentence what they do ("Drill: your infantry fight 10% harder"),
    stay up longer, and the chronicle says it too.
  - **Turn report**: "events elsewhere" were invisible (.secondary inside a button on
    material), so they now use explicit colours.
  - **Being attacked**: rivals start the game at war, so they never declared it. Now the first
    attack by each rival in a turn raises a "Mesopotamia attacks!" banner with a horn.
  - **Rivals tab**: a mood line for each rival, read from what moves the AI: "They want peace",
    "They think we are weak", "They fear our armies", "Good friends: trade binds us",
    "Awed by our court", wary or hostile.
- **Balance** (120 games, seeds 501–620): Mesopotamia 46%, Italia 30%, Egypt 19%, Greece 3%.
  Veterans favour the realms that fight most, so Egypt slipped from 24%. Rules version 13.
  202 tests.

### No landing past a defending fleet (Josh: "an enemy shouldn't be able to attack a coastal area and land troops until they defeat your naval ships first")

- Sailing into a sea that holds an enemy fleet already forced a sea battle. The gap was a landing
  from a sea where both sides' ships already sat (fleets that met while at peace). Now the
  landing fleet must fight every enemy fleet in those waters first. If it loses, the troops stay
  aboard (or drown with sunk ships); if it wins, the survivors land.
- Every sea battle your ships fight now raises a banner: "Victory at sea", or "Our fleet is
  beaten: X now holds the sea; its troops can land". The chronicle gives both sides' ships
  and how many sank. The landing order warns when enemy ships guard the water.
- Balance unchanged (120 games: Mesopotamia 44%, Italia 31%, Egypt 20%, Greece 2%). 205 tests.

### Sea battles on the grid (Josh: "a sea battle should have the same grid battle as a land battle")

- Sea battles are fought by the land battle simulator on the 5×5 board: each ship is one unit,
  on open water (`BattleSetup.naval`), with strength from seafaring knowledge. Morale, routs,
  chasing and formations all work the same. `NavalReport.battle` keeps the grid battle for the
  replay. The old auto-resolve (`resolveNaval`) is no longer used in play.
- Fleets have their own battle plan (`Command.setFleetPlan`), used when they attack and when
  they defend. It sails with the squadron, and so do the troops' battle honours.
- Sailing your fleet into a sea holding enemy ships opens the battlefield, as a land attack does:
  ships drawn up on water, a naval scouts' report, the plan cards, then "Row in!". Every sea
  battle your ships fight shows the replay with blue water, ship blocks and naval narration
  ("Bronze rams crash into hulls!").
- Balance (120 games): Mesopotamia 43%, Italia 35%, Egypt 15%, Greece 5%. Sea battles are more
  even than before (each side wins 41–54%), and more of them are fought (beaten fleets now
  live to fight again). Egypt's 15% is within noise of its 19–20%. Debug launch argument:
  `-demoSeaBattle YES`. 206 tests.

### Command bar and the title screen's look in play (Josh: "you have to scroll so far to see what you can build… a horizontal menu on the bottom… look more like the splash page")

- Selecting a territory or sea no longer opens the side panel. A command bar slides up along the
  bottom instead:
  - on the left, the place's name in bronze serif capitals, its owner, people, grain, army,
    rank and a one-line hint;
  - on the right, every action as a parchment card in a row you slide through, grouped
    Recruit · Build · Ships · Command (general, defence plan, disband), or Diplomacy for
    tribal land, or Fleet (the fleet's battle plan) for a sea.
  - Cards show cost and effect. Cards you can't afford stay readable with the cost in red; a
    tap on one gives a warning buzz. Recruit cards show "+N" raised this turn.
  - Plans and disbanding open as popovers.
- The side panel is now only for orders being composed (march, board, land) and the
  Realm / Rivals / Chronicle tabs.
- Everything floating over the map uses the title screen's dark wood with a bronze edge
  (`woodPanel`): the status box, layer picker, toolbar, notices, round buttons, side panel and
  the "rivals move" pill. End turn is a bronze button in serif type, like Continue on the
  title screen.

### Sail and attack in one order (Josh: "it's unclear how I can take my troops on board ships and attack a coastal country")

- Selecting an army on a coast now also lights up, in blue with a ⛵, every coast its ships can
  reach this turn (`Engine.seaRoutes`): coasts of a sea where it has ships with room, and,
  if those ships haven't moved, coasts one sea further. Land next door stays white (march).
- Tapping a blue coast opens one "Sail and attack" order: pick who goes (capped at the room
  aboard), see the route and the scouts' report, and the game boards, sails if needed, and
  lands. Each step is a normal command, so a fleet beaten at sea on the way stops there.
- The command bar's hint says so, or, with no ships, says to build one first. The walkthrough
  page on crossing the sea is updated. The step-by-step way (board, sail, land) still works.

### Standings (Josh: "difficult to tell how you're doing vs the other players"; no regions or ambitions: "I want it to be realistic… Civilization should be more the feel")

- A standings bar sits under the map layers: every living empire's prestige as a bar in its
  colour, leader first with a crown, yours outlined. It warns when anyone holds 80% of the
  land needed for domination ("Mesopotamia holds 52% of the land; 60% wins").
- Tap it for the standings sheet:
  - prestige over the game as a line chart (`GameSession.prestigeHistory`, saved);
  - each empire's prestige broken down (`Engine.prestigeBreakdown`: land, people, gold,
    legitimacy, capital, court);
  - the last five rounds' trend;
  - land share against the domination line.
- Borders and prestige are now recorded on every change of round. Before, a round that turned
  over on the player's own End turn was missed, which also left gaps in the end-of-game
  border replay.

### City view and trade (Josh: "tap into your city like the throne room… see your improvements and the gold/resources it brings in"; "make it clearer what our trade routes are providing")

- **Enter the town** from the command bar of any territory you hold. On the left the town is
  drawn from its real state:
  - one house per person and one field per grain;
  - the capital's palace, a river for river valleys, terrain and trees;
  - walls, road, mine, farm irrigation, harbor and the ships offshore;
  - building work in progress, and the army camped outside under its owner's flag.
  On the right: what it gives each turn (grain, people of room, taxes, mines, wine, harbor
  trade, total gold; `Engine.territoryReport`), its yields, its buildings, and build buttons.
- **Trade** (new ⇄ toolbar button; `Engine.tradeReports`):
  - a total of what all trade brings each turn (gold, every resource, grain on call);
  - each route's partner, what comes in and what goes out, gold after tolls, wine sales, and
    what would cut it;
  - every empire you don't trade with, and the resources they have that you lack.

### Graphs and army supply (Josh: "graphs… your rise relative to other empires, and your gold and other resources, armies. Just like Age of Empires at the end of a game"; "see how well an army is supplied when we tap it")

- Each round the session records every empire's prestige, land, people, gold, army (soldiers
  on land and at sea), ships, granary and knowledge (`RoundStats`, saved with the game).
- `EmpireGraphs`: a line per empire (yours thicker), with a picker for Prestige, Land, People,
  Gold, Army, Ships or Knowledge. It's in the standings sheet during play and behind a Graphs
  button on the end screen ("How the age unfolded"). The end screen's standings scroll when
  rebel factions make the list long.
- Tapping one of your armies puts a Supply card first in the command bar:
  - its state: well supplied, long haul, strained, or cut off;
  - grain a turn, with the carted extra shown separately, and its share of army pay;
  - one line on why, and what would fix it (a road, ships in the sea between, retaking the
    land).

### Roads speed marches (Josh: "roads should speed troop movement - maybe you get 2 moves without fighting")

- A march from a territory with a road to another with a road, both yours and with nobody to
  fight at the far end, doesn't use up the troops' move: they may march once more that turn
  (`GameState.roadMoved`, `Engine.roadLinks`). The second move is the last, road or not, so a
  road network gives two steps a turn, not unlimited. Attacks never get the bonus.
- The AI uses it automatically (it reads readiness the same way). Roads also still carry
  supply free. Rules version 14; three tests.

### Alliances (Josh: "set up defence alliances and try to get the AIs to join us in a war")

- Empires at peace can swear a defensive alliance (at most 2 allies each). Whoever attacks a
  member (declares war on them, or fights them in a land battle) calls the others to arms:
  - an AI ally joins unless the attacker is more than twice its strength; refusing ends the
    alliance;
  - a person gets a call to answer on the Rivals tab (a banner and a notice say so). Joining
    declares war with no legitimacy cost. Refusing, or ignoring it until the ally moves again,
    ends the alliance and costs 8 legitimacy.
- You can also ask an ally to join one of your wars (once per ally per turn). It weighs the
  enemy's strength the same way, and a refusal doesn't end the alliance. Leaving an alliance,
  or declaring war on an ally, costs 8 legitimacy.
- AI courts accept or propose an alliance when they share an enemy at least as strong as
  themselves. They offer one to a person now and then (every fourth round), not every turn.
  An AI never attacks its ally, and won't make a separate peace while its ally fights that
  enemy (unless it's losing).
- The Rivals tab shows, for each rival, whether they'd likely ally, plus Propose / Ally / Ask
  to fight X / Leave alliance. There are banners for alliances made and broken, allies joining
  wars, and calls to arms, and chronicle lines for each.
- A court's answer to your proposal (an alliance, or a call to join your war) shows at once: a
  toast, and a note on that rival's card for the rest of the turn saying yes or no and why
  (Josh: "they declined my alliance, but it wasn't immediately clear that they had").
- Balance (80 games): unchanged within noise. Rules version 15; 219 tests.

### Holding an empire together, great works, patronage and the court's dilemmas (Josh: "let's do all of these"; "maybe you need to garrison troops to prevent rebellions")

Aimed at the runaway leader and at giving a builder something to build, without artificial
goals: everything here follows from how real Bronze Age empires held together or didn't.

- **Restless land (overextension).** Land taken in the last 5 rounds, or 5+ supply steps from
  the capital, needs a garrison of at least 1 soldier. Without one it is *restless*: it pays no
  taxes, and revolts now fall on restless land (each restless land adds 5 to the revolt chance
  weight; a realm past 8 lands adds 3 per extra land). The capital never needs a garrison.
  Roads shorten the supply distance, so they calm far provinces too. We tried a garrison of 2:
  wars between empires fell by about 80%, so it's 1. The map shows a red raised hand on your
  restless land; the command bar, the town view and the steward say what to do.
- **Coalitions.** The leader becomes a *menace* when its prestige is at least 160% of the
  runner-up's and it holds at least 35% of the domination share, or when it holds 70% of the
  land it needs to win. AIs then look for war against it (if they border it with a decent edge),
  make peace among themselves, and ally with anyone else fighting it. The standings bar warns
  ("rivals will band together against you").
- **Great works.** Five, one in the world each: the Great Pyramid and the Ziggurat (river
  valley), the Lion Gate (hills or mountains), the Royal Library and the Lighthouse (coast).
  Each costs gold, stone and timber and several turns, and gives prestige plus a lasting effect
  (in rules.json). Several empires can race for the same one; the first to finish wins and the
  others' sites are abandoned with half the cost back. A finished work belongs to whoever holds
  its land, so it can be conquered. Built from the town view ("Great works"); the standings
  sheet lists the age's works and who holds them; a gold seal marks them on the map (pale while
  rising); banners when one is finished anywhere. The AI builds one when it has gold to spare.
- **Patronage.** Pay 3 gold a turn to masters of one field (farmers, smiths, shipwrights…) for
  12 extra knowledge a turn in it. Chosen at the top of the Knowledge sheet; it lapses if the
  treasury can't pay.
- **The court's dilemmas** (people only; the AI's realm runs itself). At most one a turn, as a
  wood card with two answers:
  - *Famine*: open the granaries (the grain, +3 legitimacy) or keep them shut (−3 legitimacy,
    and the land loses a person);
  - *A general demands honours*: pay, or refuse (−15 loyalty: sulking generals stage coups);
  - *Sea Peoples mercenaries*: 3 blooded warriors at the capital for 9 gold.
  Ending the turn without answering refuses.
- Balance (80 games, seed 501): Egypt 38%, Mesopotamia 30%, Italia 22%, Greece 8%; 2
  dominations; the round-10 leader goes on to win only 38% of games, so the lead now changes
  hands. Egypt gains most from great works (two need a river valley). Rules version 16; 228
  tests.

### Granaries (Josh: "do we have granaries?… let's add that")

- The realm already had one grain store, capped at a turn's home harvest (two with the second
  level of agriculture, one more with the Ziggurat). There is now a granary building too:
  5 gold, 1 stone, 1 timber, 2 turns, buildable anywhere. Each granary in the home network
  lets the store hold 6 more grain (`projectEffects.granaryGrain`), to carry the realm through
  famine, drought and siege, or to open to the hungry when famine strikes.
- It shows as 🏺 on the map and as a storehouse by the fields in the town view. The AI builds
  one at its capital when its store is full and the harvest still has grain to spare.
- Balance (80 games): unchanged within a game or two. Rules version 17; 229 tests.

### Map plaques (Josh: "the numbers and resources on the game map don't match the higher quality style… more readable? and more clearly for the territory in question")

- Each territory's numbers now sit on one dark-wood plaque with a bronze rim, hung from its
  army token (or centred where there's none), with the owner's colour as a stripe down its
  side. It replaces the separate people counter, buildings label and white info plates, which
  stepped aside for each other and drifted toward neighbours.
- Detail grows with zoom: zoomed out, people plus roads, walls and harbors; zoomed in (or on
  the Resources layer), grain, every resource and every building; closer still, or when
  selected, the army's make-up. The plaque stops growing past a moderate zoom. The selected
  territory gets a bronze outline and a larger plaque drawn on top.
- Resources use one drawn icon set (new symbols for grain, timber, stone, gold and wine,
  alongside the metal ingots), tinted per resource, in the HUD, command bar, town view, trade
  view and the Resources legend as well as on the map.

### Succession crises, restyled, and rebellions you can't miss (Josh: "I paid off a general - but it didn't work and he still rebelled (I like that) but it wasn't immediately clear… the event screen didn't match the style")

- Paying off claimants still settles the crisis at once, but a general whose loyalty sinks
  low enough can rise later anyway. The choice now says so ("bought loyalty can sour").
- The crisis is a wood card over the dimmed map with three parchment choices, like the
  court's other dilemmas, in place of the system sheet.
- When one of your generals rebels there's a stamped red banner ("Horemheb rebels! He seizes
  …"), war drums, the seized land flashes and the map turns to it. If you had paid him off,
  it says "Your gold bought only a season."
- Debug launch arguments: `-demoCrisis YES`, `-demoRebellion YES`.

### Feel and clarity, Polytopia-style (Josh: "more physical feedback… one clear cost and payoff per decision")

- **Armies move bodily.** A moved army's own token (bronze rim, count) marches along a curved
  path with a step bob and a shadow; its token appears at the destination only when it arrives,
  with a ring in its colour. Marching sounds a drum, or hoofbeats with cavalry.
- **Captures burst**: bronze sparks and a ring from the token, on top of the colour sweep, and
  "+N prestige" rises from land you take.
- **Gains rise from the land** as your turn begins: "+6 gold" and "+2 grain" at the capital,
  "+1 person" where people grew, new buildings where they were finished. They wait until the
  news, any dilemma and any succession crisis are dealt with, then the map turns to the capital
  and they rise one after another, fanned out side by side, with a coin sound.
- **Every choice shows its cost and payoff before you tap**: recruits ("+1 soldier, strong
  against cavalry"; gold, a person, grain a turn), ships (troops carried; gold, timber, grain a
  turn), generals (gold, and pay a turn), buildings (corrected walls figure), patronage ("+12
  knowledge a turn"), diplomacy (declaring war: −legitimacy, ends trade; peace: free, opens
  trade), and the court's dilemmas (each answer's gains and losses under its button). Battle
  odds stay hidden.

### Limited sight (Josh: "not quite fog of war… you shouldn't see everything across the map")

- The lie of the land and who holds it are common knowledge. Armies, people and works are seen
  only in your own land and what borders it, where your armies stand and what borders them, on
  coasts of seas your fleets sail, through your allies' eyes, and in the capitals of your trade
  partners (merchants talk). `Engine.sight(of:in:)`.
- Beyond sight the land is hazed; its plaque, army and buildings are hidden (resources still
  show on the Resources layer). A host of 8 or more (`sight.rumouredArmy`) shows as a dashed
  "?" token: rumour of a great army, not its size. Rival fleets on unwatched seas are hidden.
  Rivals' marches, battles and raises out of sight aren't drawn; captures still are (news
  travels). The territory panel and quick look say "Beyond your sight" and how to see further.
- Rules version 18; 234 tests.
- The AI plays by the same sight. Within its sight it knows armies' true sizes; beyond it,
  `Engine.perceivedArmy` gives a rumoured host (8 or more) as exactly `sight.rumouredArmy`, a
  rival's other land as `sight.assumedGarrison` (2) whether or not anyone is there, and
  unclaimed land as the tribe that held it at the start. Rival fleets count only on seas it
  watches. This feeds the AI's war and peace strength comparison (`perceivedStrength`), the
  danger around land it might take, sea-campaign targets, and an ally's "is this enemy too
  strong / worth allying against" (`willingToFight`, `wouldAlly`). Garrisons, walls, recruits
  and defensive formations only look next to the AI's own land and armies, which it always
  sees. Fleet routing (`sailable`) and levies on unseen land still use the true state (known
  simplifications). Deterministic: no new randomness.
- Balance (80 games, seed 501), before → after: Egypt 38% → 42%, Mesopotamia 30% → 22%,
  Italia 22% → 20%, Greece 8% → 15%; dominations 2 → 2; no rejected commands. Mesopotamia
  loses a little of its edge (it sizes up rivals by rumour now) and Greece gains, so the
  field is a little more even. Not tuned. 237 tests.

### Tempo (Josh: "faster rival turns… quick battles for small fights")

- Rivals' turns only pause for what happens in sight; news from afar (including distant
  captures) appears without a pause or a camera move. Pauses are shorter (march 0.48 s, battle
  0.6 s, other 0.22 s, 0.25 s between rivals), and a 1×/2× toggle beside Skip (remembered)
  more than halves them. A round of rivals now takes about 5 seconds, down from 10 or more.
- Quick battles: when one side has at least three times the other's troops (levy included),
  the fight resolves on the map (a burst and a toast: "Easy victory at Libya" or
  "Libya: overwhelmed") instead of opening the battle replay. Attacking with such odds, the
  order card offers "Attack" (straight in with the army's standing plan) beside "Battlefield".
  Close fights still go to the battlefield.
- Debug launch argument `-demoHost YES` swells the capital's army to 14 for trying quick battles.
- The board can slide about a third of the screen past any edge (a fifth when fully zoomed
  out), so land in the corners can be brought out from under the status panel, toolbar and
  buttons (Josh: "playing in a corner of the map it's somewhat obscured by menus").

### Steering knowledge, made obvious (Josh: "make it more clear you can give the tech tree direction")

- The Knowledge sheet opens with "Choose a direction": people learn from what they do, but you
  steer by funding one field (3 gold a turn, +12 knowledge a turn there). Every field on the tree
  has a Fund button under its name; the funded one shows "Funded ✓" and a bronze outline, and the
  header names it with a "Stop funding" button. (The separate patronage strip is gone.)
- Nudges while nothing is funded: a bronze dot on the toolbar's books button, the priest's advice
  in the council when the treasury can afford it, and the first-discovery tip.

### From Civilization and Risk: queues, splendour, iron, sacks, rulers, the age replayed, combined attacks and sieges (Josh: "let's do 1-6 and 8… combine troops and attack from multiple territories, or territories and a fleet… we haven't really incorporated sieges")

- **Build queues.** A territory can line up three projects behind the one under way; each starts
  (and is paid for) when the site frees, if the treasury and stores allow, otherwise it waits. A
  project that no longer fits drops out. Queueing on an idle site just starts it. The command
  bar shows the queue ("Next, when this finishes"; tap to clear) and "Then …" tiles.
- **Next turn.** A line by End turn names what the next turn brings: works finishing, great works
  completing, discoveries close (within a turn's practice or patronage), sieges biting, the end of
  splendour.
- **Ages of splendour.** From round 6, a realm among the two most prestigious with legitimacy
  75+ enters 5 rounds of splendour: building twice as fast, +25% gold, +50% growth. Then 12
  rounds before another. Banner, status line and chronicle.
- **The Iron Age.** When the collapse reaches 60% pressure, iron (which needs no tin) becomes
  usable by everyone, ironworking or not. Banner and "Iron Age" by the round counter.
- **Sacking a capital.** Taking a rival's capital carries off half its treasury and is worth 15
  prestige for the rest of the game ("Capitals sacked" in the breakdown), on top of the capital
  loss it already cost them.
- **Rival rulers.** The Rivals tab shows each ruler's portrait (their emblem on their colour,
  crowned or laurelled), a temperament (their AI personality in words: "hungry for land",
  "a trader at heart"…) and a line in their voice for their court's mood. War, peace and
  alliance banners, and refusals, quote them.
- **The age replayed.** The end screen's border replay has play/pause, a slider through the
  rounds, and that round's turning points from the chronicle (conquests, sacks, wonders, wars,
  peace, the Iron Age).
- **Combined attacks** (`Command.assault`). When you attack, every other army of yours next to the
  target with troops ready, and every fleet of yours in its seas with troops aboard, is offered as
  a "Join the attack" toggle. They fight as one host (the largest land group's plan and
  approach; landings fight as amphibious only if no land group joins); beaten, each part falls
  back where it came from in proportion. Enemy ships in a sea must be beaten first, by a normal
  landing. The battlefield and quick attack both carry the joiners.
- **Sieges** (`Command.besiege` / `liftSiege`). A walled town of a rival at war can be besieged from
  a neighbouring army that hasn't moved: the whole army camps for the turn. Each round, at the
  besieger's turn, while the camp's army stays and the war goes on: the town's fields give no
  grain and its people no taxes; after its granary's 3 rounds (none without one) a quarter of
  the garrison starves (at least one) and a person dies; and the walls lose 10 points of defence
  (20 with rams, Construction level 2). The besieger storms whenever it likes; the defender can
  sally against the camp; moving the army away, peace, or the walls falling lifts it. The map
  shows tents round the town, a dashed line from the camp and the round; the territory panel
  shows the siege and a Lift button; the order card offers "Lay siege" beside the attack. The AI
  besieges walled towns it can't storm (under 55% odds) when it has at least 80% of the
  defenders' strength, then storms once the odds turn.
- Fixed: the famine dilemma no longer asks for grain the granary doesn't hold.
- Balance (80 games, seed 501): Egypt 43%, Italia 23%, Mesopotamia 23%, Greece 8%; 3 dominations
  and a trade win. Rules version 19; 251 tests. Debug launch argument `-demoSiege YES`.

### Declining peace, and audiences with rival rulers (Josh: "there doesn't seem to be an easy way to decline an offer of peace"; "we could see the rival rulers like in Civ? … they should appear when they ask for peace or declare war. and I should be able to tap to visit them")

- `Command.declinePeace(from:)`: the offer is withdrawn and the offerer won't offer peace again
  for 5 rounds (`alliances.rebuffedRounds`). Each peace offer now shows on the map as its own
  notice with Decline and Accept (more than two collapse to "+N more"); the Rivals tab has
  Decline beside Accept peace.
- **Audiences.** A rival ruler who offers you peace or declares war on you comes to you in
  person once the news, dilemmas and banners are dealt with: a full screen with their own hall
  (their throne room as decorated), the ruler's portrait on the throne, their name, government
  and temperament, a line in their voice, where the two realms stand, and what you can do
  (accept or decline peace; offer peace; propose an alliance; declare war, tapped twice to
  confirm; take your leave). Several wait their turn. The Rivals tab opens with a row of the
  age's rulers — tap one (or the portrait on their card) to visit their court any time.
- Rules version 20; 252 tests.

### Road marches in one go, armies as cubes, and selection you can't miss (Josh: "If there are roads I should be able to move my troops 2 spaces in one go… much clearer that you've selected your troops… like a 3D cube")

- With an army selected, land two steps away along a road also glows: the first step to a
  neighbour of ours with a road (and a road where the army stands, nobody to fight there),
  then one step anywhere. Tapping it composes one order ("Attack Arabia by road through
  Petraea"); sending it makes both moves. If the last step can't be taken, the army stays where
  it got to. A general marching by road may go on with his troops (once a turn:
  `generalsRoadMoved`). Only troops that haven't already taken a road step can make the march.
- Armies are drawn as blocks from the board game: a cube in the owner's colour seen from the
  front and a little above, the count on its face, a shadow on the board (tribes' cubes grey).
  Marching armies are cubes too.
- The selected army lifts off the board with a bobbing bronze arrow over it and pulsing bronze
  rings beneath; the "can still move" ring steps aside. The map brings whatever you select into
  the clear space above the command bar (and may pan further past the board's edge to do it),
  and the map's notices hide while something is selected.
- Rules version 21 (the state gained a field; old saves are retired); 253 tests.

### One more turn, and the army's own menu (Josh: "like Civ you should have the option to play one more turn at the end of the game"; "when you tap on the cubes, you shouldn't see the territory menu. you should see an army menu")

- **One more turn** (`Command.playOn`). The end screen offers "One more turn" beside "Play
  again" (while the player still has a realm). The result stands (the victory is kept), but
  play goes on as long as you like: no further victories are declared, the round limit no
  longer applies, and the status reads "Round N · playing on". Raiders wiping everyone out
  after that just leaves the world empty.
- **Army menu.** Tapping an army's cube (rather than the land around it) opens the army's own
  menu: its cube and size, units, general and rank, how many can still march, supply, defence
  plan, general and disband. Tapping the land shows the territory (recruit, build, ships), with
  an "Army" tile to switch to the army; the army menu has "The land of …" to switch back. The
  next-army button opens armies in their menu.
- Rules unchanged (version 21); 254 tests.

### Placing blocks and giving them orders, and livelier battles (Josh: "a bit of animation and battle sounds… move our pieces on the grid before the battle… orders like move forward, or this unit holds its ground")

- **Placement.** On the battlefield before a land attack, drag any of your blocks to another
  square of your own two ranks (not onto rock); a block already there trades places. Stored as
  `BattlePlan.placements` (block index → square) and applied after the formation's deployment.
  Out-of-range squares are ignored, so a stale placement never breaks a battle.
- **Orders.** Tap a block to cycle: advance (↑; marches from the first round, and archers close
  in rather than stopping to shoot), hold (✋; stands until struck), or the formation's way.
  `BattlePlan.orders` → `BlockOrder`; a block's own order outranks its formation and the army's
  stratagem. Badges on the blocks show them; "Reset placings" clears both. They stay with the
  army's standing plan (as defender they're ignored: they're in attacker coordinates).
- **Animation and sound.** Blocks lunge into the block they strike in melee; archers' volleys
  fly as three shafts along the arc; marching rounds thump a drum; blows land a beat after the
  volley's whistle; cavalry charges gallop; a block breaking draws a cry.
- A battle you drew up on the battlefield always plays out there, even at three to one (quick
  battles are for attacks sent straight from the map).
- 257 tests. AI armies don't place or order blocks (unchanged balance).

### The open board (Josh: "let's remove the fog of war. make it more like a board game")

- Limited sight is now a rules option, off by default (`sight.limited: false`): every player
  and every AI court sees the whole board — every army, its size, people and works — as on the
  tabletop. No haze, no "?" rumours, and rivals' moves anywhere are shown (and paced) again.
  Switching it on restores everything in "Limited sight" above, AI included.
- Balance (80 games, seed 501): Egypt 37%, Mesopotamia ~32%, Italia 21%, Greece 10%; 2
  dominations, 1 trade win. Rules version 22; 258 tests.
- Fixed (Josh: "I can position my troops… but it just seems to revert once the battle
  starts"): an army stores its standing plan field by field, and placements and orders weren't
  among them, so setting the plan at the charge dropped them. `Army` now keeps `placements` and
  `orders`. In a combined attack, the army that called the others sets the plan.

### Rulers in person (Josh: "Could we add civ like leader animations? I like their throne rooms - but it's not a person")

- Audiences now show the ruler as a drawn, animated figure seated on a throne in their own hall
  (`RulerFigure`): breathing, blinking every few seconds, glancing about, the head tilting, and
  the mouth moving for a couple of seconds as they speak.
- Each realm's own dress: Egypt's pharaoh in the striped nemes with the cobra, kohl-lined eyes,
  the plaited false beard and a broad collar; Mesopotamia's king in the tall horned cap with a
  long, square, curled beard; the Greek with a crested bronze helmet pushed back and a full
  beard; the Italian clean-shaven, laurel-crowned, a purple band across the toga. Robes in the
  realm's colour; a sceptre in the right hand.
- The face shows the court's mood: angry when declaring war (knitted brows, mouth turned down,
  leaning in, sceptre raised), stern at war, pleased when offering peace or allied, wary when
  you outnumber them, neutral otherwise.
- The hall's empty throne makes way for theirs; the realm's emblem hangs above. Debug launch
  argument `-demoAudience egypt` (or `war:greece`).

### The town, painted (Josh: "can we make the city view nicer as well? looks a bit too much like just icons")

- The town view is now a painted scene (`TownPainter`, in a 1000 × 600 frame fitted to the
  view's height and centred on the town) instead of SF Symbols:
  - **Landscape:** sky with a sun and drifting clouds; far hills, dunes or snow-capped
    mountains by terrain; grass or sand; a river valley's river with reeds and moving glints; a
    coast's sea with waves.
  - **Town:** houses in the realm's style (whitewashed with red-tiled roofs for Greece and
    Italy, flat-roofed mudbrick with awnings for Egypt and Mesopotamia), two per person, in
    depth order around the centre. At the heart, the capital's great building: Egypt's temple
    pylon, Mesopotamia's ziggurat, the Greek or Italian columned temple; elsewhere a hall. Flags
    in the owner's colour stir in the wind.
  - **Works:** irrigation channel and shaduf (farm), striped fields one per grain, a mine
    tunnel and ore cart in a hill, a paved road, a stone wall with battlements and gate towers,
    domed granaries, a quay and pier (harbour) with ships bobbing under coloured sails, a building
    site with a crane swinging a block, and any great work standing there (pyramid, ziggurat,
    Lion Gate, library, lighthouse with a pulsing light).
  - **Produce:** vineyards (wine), grazing horses, stacked logs (timber), cut stone, a market
    stall (luxuries).
  - **The army:** tents in its colour, its flag and a smoking campfire.
- Debug launch argument `-demoTown YES` opens the capital; `-demoTown full` paints every
  building.

### Sieges softened, and sallying out (Josh: "laying siege might be too strong - how do you go out and meet them in combat")

- **Sally out.** A besieged town with troops of yours shows a "Besieged" section with a
  "Sally out" tile: it opens the attack on the camp (the usual order card: battlefield, quick
  attack at three to one, joined by other armies). Beating the camp's army lifts the siege. The
  AI sallies too: when its odds against the camp are 55%, or 40% once its stores have run out.
- **Softer pacing.** The town's own stores hold the first round (plus 3 with a granary) before
  anyone starves; hunger then takes 15% of the garrison a round (was 25%). From the third round
  sickness spreads in the besiegers' camp, taking 8% of its army a round (at least one); a camp
  that dies out lifts the siege. Walls still wear down 10 points a round (20 with rams).
- Balance (80 games): Egypt 35%, Italia 23%, Greece 8%, Mesopotamia ~34%. Rules version 23;
  261 tests. Debug launch argument `-demoBesieged YES`.

### Levees and drains (Josh: "we need things to be able to limit the floods - dams?"; "sanitation for plague?")

- **Levees** (river valleys only; 6 gold, 1 stone, 1 timber, 2 turns): earthen banks along the
  river. A flood that strikes a leveed valley takes no one. (The Bronze Age built levees and
  canals far more than dams, so levees it is.)
- **Drains & wells** (anywhere; 6 gold, 2 stone, 2 turns): plague takes half as many in that
  territory, and may take no one in a small town.
- Both show on the map (🌊, ⛲) and in the town view (banks along the river; a well with a basin
  and a drain). The AI builds levees on its richest valleys, and drains in crowded towns once
  it trades.
- Balance (80 games): Egypt 33%, Italia 26%, Mesopotamia ~33%, Greece 8%. Rules version 24; 264
  tests.

### Difficulty and scenarios (Josh: "add an easy medium hard and god mode. and maybe some scenarios")

- **Difficulty** is picked on the title screen (remembered between games) and only matters when
  a human plays; watched games are always even. Rivals' income, their opening troops and their
  appetite for war scale; the player gets a head start only on Easy. No cheating on dice.

  | Level  | Rival income | Rival extra infantry | Rival aggression | Player start |
  |--------|--------------|----------------------|------------------|--------------|
  | Easy   | 80%          | 0                    | 75%              | +15 gold, +3 infantry |
  | Medium | 100%         | 0                    | 100%             | —            |
  | Hard   | 125%         | 2                    | 115%             | —            |
  | God    | 160%         | 4                    | 130%             | —            |

- **Scenarios** (the Scenarios button) start from a historical moment with a short round limit.
  Prizes are named territories worth extra prestige to whoever holds them at the end (shown in
  the prestige breakdown as "Prizes held"); otherwise victory works as usual.
  - *Kadesh* (1274 BC, 15 rounds): Egypt's chariot army in Sinai against Mesopotamia's host in
    walled Syria. Prize: Syria +30.
  - *The Siege of Troy* (c. 1190 BC, 20 rounds): Greece with a fleet of a thousand ships (five)
    against walled, stocked Anatolia. Prize: Anatolia +40.
  - *The Collapse* (1177 BC, 15 rounds): every court larger, armed and richer, ten rounds from
    the crisis peak.
- Engine: `Engine.prepare(_:human:difficulty:scenario:)` in `Engine/Setup.swift`; the state
  remembers difficulty, scenario, round limit and prizes. Rules version 25.

### Disbanding ships (Josh: "There doesn't seem to be a way to disband fleets")

- The fleet menu has a **Disband** tile: pick how many ships to break up. Each saves its crew's
  grain upkeep; no gold comes back, like disbanding troops. Ships still needed to carry the
  troops aboard can't be disbanded (land them first). Order `Command.disbandShips(sea:ships:)`.
- Title screen: difficulty and scenario sit on their own row with the blurb beside them, so a
  saved game's "Continue" button no longer crowds them. Debug launch argument `-demoFleet YES`.

### The statue of the ruler (Josh: "improve the statue of the ruler in the throne room")

- No longer a stock stick figure: a carved likeness of the ruler in each realm's own sculpture,
  on a stepped plinth with the ruler's name cut into it (`RulerStatue.swift`). Egypt: a
  sandstone striding pharaoh against a back pillar, painted nemes and collar. Mesopotamia: dark
  diorite, hands clasped, tall cap and curled beard (after the statues of Gudea). Greece:
  painted marble with crested helmet, spear and spiral shield. Italia: cast bronze in a toga and
  laurel, arm raised to the crowd. Debug launch argument `-demoThrone <civ>` opens a fully
  decorated throne room.

### Sailing, storms and pirates (Josh: "add pirates and ships lost at storms (if not at harbor) but also I think ships should move 2 spaces by default")

- **Two seas a turn.** A fleet sails up to `ships.moves` (2) seas in one order, along open
  lanes, never *through* a sea an enemy fleet holds (it may sail *into* one, to fight; a beaten
  squadron falls back to the sea it came through). Sea assaults reach as far: an army boards,
  sails up to two seas and lands in one order. The AI sails as far toward its goal as it can.
- **Storms.** At the start of each turn, every fleet not off a harbour of its own (a coast of
  that sea, owned, with a harbour) has a 4% chance of a storm, less 1 per Seafaring level (never
  below 2%), halved off any coast of its own and halved again by the Lighthouse. (At 6% and
  without the inshore halving, storms drowned Greek expeditions often enough to eliminate
  Greece in 12–17% of sims.) A storm sinks a third of the ships (at least one) and
  drowns the troops that no longer fit. Harbours were already worth building for cheaper
  ships; now they also shelter fleets. The AI parks idle ships off its harbours.
- **Pirates (☠).** From round 4, an 18% chance each round that a band of 2 ships (+1 per 15
  rounds) puts to sea in waters where no ships ride, up to 2 bands at once. A band breaks up
  with a 10% chance each round (without that, bands settled for good in the Persian Gulf and
  bled Mesopotamia of ~85 gold a game). Each round a band drifts toward easy pickings (never into waters where any nation's ships ride) and plunders
  one coast: 4 gold from the owner of an unwalled coast with none of the owner's ships in that
  sea or the next.
- **Navies keep pirates down** (Josh: "having strong navies should probably prevent pirates").
  A fleet of 3+ ships patrols its sea and the seas next to it: no band puts to sea there, none
  sails in, and a band caught there breaks up with a 35% chance a round (10% elsewhere). Pirates are at war with everyone, so the sea they hold is closed to trade, supply and
  shipbuilding, just as an enemy fleet's would be. Sinking pirate ships pays a bounty of 3 gold
  each (ships with nowhere to flee count as sunk) and wins a raider's shield for the throne
  room. The AI hunts pirates within a turn's sailing when the odds are 65% or better.
- Balance (80 games): Italia 36%, Egypt 22%, Greece 10% (eliminated 6%), Mesopotamia ~32%.
  Gold plundered per game: Mesopotamia ~41 (no fleet in the Persian Gulf), others 1–13.
  Ships lost to storms: 0.2–0.5 per empire per game. The sim's sea table now counts storm
  losses, gold plundered and bounties. Rules version 26. Test rules (`Engine.calm()`) switch
  storms and pirates off.

### Minor kingdoms and vassals (Josh: "making the smaller regions have their own AIs and personalities… not playable for users"; "an option to have a conquered country be a vassal state. lots of advantages")

- **Peoples.** Each of the 28 native lands that isn't a barbarian homeland is a named people
  with a ruler and a temperament (`minors.peoples` in rules.json), drawn from the age where we
  can: Hatti under Suppiluliuma II, Ugarit under Ammurapi, Alashiya, Knossos, Tartessos, Elam,
  the Libu under Meryey, the Sherden, the Lukka, the Thracians under Rhesus… Temperaments:
  warlike (base attitude −10), proud (0), mercantile (+10), peaceable (+20).
- **Memory.** Each people's attitude toward each empire runs −100…100. Gifts warm them by 15
  even when refused (so gold is never quite wasted); a refused demand chills them by 20, a
  refused offer of vassalage by 10; attacking them costs 50, and every people next door fears
  the attacker (−10). Feelings drift back toward the base by 2 a round. Half the attitude is
  added to the chance gifts win them over.
- **Their own turn** (once a round, after pirates): warriors lost grow back by one every 5
  rounds, up to their starting strength. (Growing 2 beyond it made tribes tough enough that
  empires rarely met: wars between the four nearly vanished in the sims.) Warlike peoples with 3+ warriors raid (15% a round) the most
  weakly held land of an empire they hate (attitude ≤ −20): half their warriors plus one go,
  fight any garrison, carry off up to 4 gold and a person, and go home; the land stays the
  empire's. Mercantile peoples pay 1 gold a turn to each friendly empire (attitude ≥ 40) that
  borders them or shares a sea. A people devoted to a neighbouring empire (≥ 70) may come over
  of its own accord (5% a round).
- **Vassals.** "Make vassal" succeeds when your troops next door are twice their warriors, or
  they like you (≥ 40). A vassal keeps its land and warriors and:
  - pays tribute every turn: 1 gold + 1 per 3 of its grain ("Vassals & peoples" in the
    treasury);
  - needs no garrison and causes no unrest, since it isn't your land;
  - is shielded: nobody at peace with you may attack it or treat with it (and you can't attack
    your own);
  - adds 8 prestige ("Vassals" in the breakdown);
  - can be levied every 5 rounds: half its warriors join your army next door;
  - can be annexed after 8 loyal rounds: the land becomes yours with its warriors, and since it
    wasn't conquered, it isn't restless.
  A vassal with none of your troops next door may break free (8% a round), and is freed if you
  fall. Someone at war with you may still conquer it.
- **Passage** (Josh: "I need to be able to move troops through a vassal's land to reach other
  territory"). An army marches straight through its own vassal's land to the land beyond in
  one order (the vassal's warriors stand aside; the crossing that counts in battle is the last
  one). Supply and trade pass through vassals' land too, though it never becomes yours: it
  isn't in your pockets, taxes or harvest. The AI marches through its vassals as well.
- **Garrisons** (Josh: "you should also be able to station troops in a vassal territory, to
  defend them"). Marching into your own vassal's land stations a garrison there, with no
  battle. The people's warriors stand aside with it (kept in `MinorState.stationed`) and
  fight beside it as its levy if anyone attacks; their dead come off their number. The vassal
  feeds the garrison (no cut-off attrition, no grain from you; you still pay the soldiers),
  and a garrisoned vassal never breaks free. When the last soldier leaves, the warriors hold
  the land alone again. Annexing a garrisoned vassal folds its warriors into the garrison.
- Balance: passage and supply through vassals favoured Italia (the conqueror) most, since it
  took the poor mountain peoples as vassals and they linked its far conquests: 48% wins. A
  true conqueror (aggression 1.3+) now takes no vassals and conquers outright; with that,
  80 games: Mesopotamia 37%, Italia 26%, Egypt 21%, Greece 15%.
- **AI** (Josh: "in some cases it may make sense to just conquer outright"). Rich land (grain
  5+) is conquered outright; poor land (grain 3 or less) is taken as a vassal when they'd
  swear; in between, merchants and turtles take vassals and conquerors and opportunists fight.
  Every vassal is annexed once its 8 rounds are up. (Keeping vassals as buffers, or taking
  every people as a vassal, slowed expansion until the empires barely met.) Nobody attacks a
  shielded vassal.
- Balance (80 games): Italia 36%, Mesopotamia 26%, Egypt 20%, Greece 17%; wars between the
  empires as common as before. Rules version 27.
- Vassalage between the four empires themselves (a beaten Egypt submitting to you) is not in
  yet: it needs submission terms in diplomacy and changes to peace and alliances.
- Debug launch arguments: `-demoAs <civ>` starts a game as that civ; `-demoVassal YES` makes
  the first people next to your capital your vassal and selects it (`look` only selects it).

### Wall levels (Josh: "walls should have levels. Higher walls, more defense, can last for a siege longer")

- Walls rise in three levels: **mud-brick** (+35% defence), **stone walls and towers**
  (+50%), **cyclopean walls** (+65%, needs Masonry, Construction 1). Raising them is the walls
  project again: gold and stone times the new level, a turn longer per level. Fortification is
  capped at 80% so no wall makes a garrison invulnerable.
- Each level above the first adds a round of stores against a siege before hunger starts, on
  top of the town's own round and a granary's three; and higher walls take longer for a
  siege's 10 points a round (20 with rams) to wear down.
- An earthquake cracks high walls down a level instead of toppling them.
- The town view paints each level: low mud-brick with a small gate; stone with battlements and
  two gate towers; huge rough-fitted blocks with four towers and a lintel over the gate, as at
  Mycenae. Troy (the scenario) has cyclopean walls; Kadesh's Syria has stone ones.
- The AI raises its capital's walls with the threat: one level for a small one, two for a
  host of 6+, three for 12+.
- Debug launch argument `-demoWalls 1|2|3` paints walls of that height in the town view.

### Soundtrack (Josh: "a soundtrack like CIV")

- Six original pieces, composed and rendered by `tools/make_music.py` (deterministic; re-run
  to change them): a title theme, one for each realm, and a war theme. The instruments are the
  age's: a plucked lyre (Karplus-Strong strings, tuned with a fractional-delay allpass) or harp,
  a double-reed pipe like the aulos or a breathy ney, a drone, frame drums or war drums, bronze
  horn calls, in a hall's reverb. Each realm has its own mode and rhythm: Greece Dorian on a
  light beat; Egypt the double-harmonic mode on a harp and ney over the maqsum rhythm;
  Mesopotamia Phrygian, slower, with a heavier drone; Italia Mixolydian on the ney; war
  Aeolian at 108 beats with war drums and horn calls. Each piece is a phrase and its answer,
  sung again with ornaments, a contrasting phrase twice, and the return: 66–120 seconds,
  about 1 MB each as AAC.
- `MusicDirector` picks by mood and crossfades. Title theme on the title screen. In a game:
  your realm's theme, then the title theme, yours again, then a neighbour's. The war theme
  while you're besieged or besieging, or for a round after any battle you fought. Every realm
  in turn while watching. Four seconds of silence between pieces. It stays silent while other
  audio is playing (podcasts, your own music), respects the silent switch, and has an on/off
  switch in the ⋯ menu ("Music").

### Advisors who speak up (Josh: "advisors should pop up and introduce / remind you about things like taxes and research etc.")

- The throne room's council now steps forward unasked. At the start of your turn, once the news,
  audiences, dilemmas and tips are out of the way and nothing is selected, one advisor appears
  in a small card at the bottom left. The card shows a drawn portrait dressed for the office: the
  general in a crested bronze helmet, the steward with his clay tablet, the envoy with a fillet and
  herald's staff, the high priest in a tall cap with a sun disc. Each portrait blinks and speaks.
  The card gives the advisor's name and role and one line in character. Its buttons go where the
  line points (the Realm, the books, Rivals, a town, a territory, a sea) or say "Got it".
- **Introductions** come once a game, the first time each system matters:
  - taxes, after the first harvest;
  - patronage of knowledge, from round 2 if no field is funded;
  - peace offers;
  - a building you can afford;
  - laying siege to a town;
  - a town of ours under siege;
  - restless land;
  - ships at sea and storms;
  - pirates off our coasts;
  - vassals.
- **Reminders** come back when needed, each with a cooldown of 2–10 rounds:
  - famine close (2 turns of grain or fewer) or people starving;
  - soldiers unpaid, or about to be;
  - a town of ours besieged;
  - an army cut off from supply;
  - the treasury thin while taxes are low, or taxes too heavy while legitimacy sags;
  - a discovery with no patron funded;
  - idle gold that could build something;
  - a siege of ours dragging on;
  - storms or pirate raids that hit us;
  - a vassal ready to be levied or annexed;
  - a peace offer still unanswered;
  - restless land.
- Alarms come first, then introductions, then reminders. At most two advisors speak a turn, and
  the second only for an alarm or an introduction. An introduction also starts its topic's
  reminder cooldown, so the same advice doesn't come twice in a row.
- Memory is kept per game (seed and civ) in UserDefaults, so a resumed game doesn't repeat
  itself. "Advisors" in the ⋯ menu turns them off.
- App layer only (`Advisors.swift`). `GameSession.sinceLastTurn` keeps the events since you
  ended your turn (harvest, pay, starvation, discoveries, storms, plunder).
- Debug launch argument `-demoAdvisor YES` shows the first advisor with something to say; a topic
  key such as `-demoAdvisor intro.besieged` (with `-demoBesieged YES`) shows that one.

### Kingdoms: stronger, expanding, with leaders (Josh: "too easy to expand empires now. Lets make the independent regions stronger… leaders for them and let them be their own AIs and expand")

- **Their own banner.** Each named people is now a kingdom with its own owner id
  (`kingdomID(homeland)` = "k_" + homeland, `GameState.kingdoms`), colour and ruler; its
  warriors are its own, not just "natives". A kingdom's lands are wherever its warriors stand on
  unclaimed land (or stand beside its overlord's garrison: `GameState.stationed`). Nameless
  tribes (the barbarian homelands) are still `nativesID`.
- **Stronger.** Native strength is now 2 + 1 per 2 grain (was per 3): rich lands field more
  (Gaul 5, Sicily 5, Anatolia 4), poor ones the same. Lost warriors grow back to one above that.
  A kingdom's people also take up arms in defence, at half an empire's levy (small lands raise
  none). Trying 3 + 1 per 3 left the empires stuck at 1–3 lands.
- **Expanding.** Each round a kingdom may try to take one land next door (warlike 30%, proud
  15%, mercantile and peaceable 8%), sending all but one warrior of a land with 3+, only where
  they outnumber the defenders (garrison and levy) by half again. Peaceable and mercantile
  kingdoms only settle empty land; tribes and other kingdoms are attacked only by the warlike
  and proud; empires' land (or an empire's army on unclaimed land) only by the warlike, and only
  empires they hate. Nobody's capital is taken. What they win joins the kingdom.
- **Diplomacy with the whole kingdom.** Gifts, demands and offers of vassalage reckon with all
  its warriors and all your troops next to any of its lands; a kingdom that comes over (gifts,
  demand, its own love for you) brings all its lands; vassalage, tribute (from all its grain),
  levies and annexation are the whole kingdom's.
- **AI.** Empires treat a kingdom as a threat only if it is warlike and hates them (treating
  every warlike or proud kingdom as one made them hoard garrisons and stop expanding). They
  weigh a kingdom by its richest land when choosing between vassalage and conquest. The AI's
  levy estimate counts a kingdom's people.
- **Leaders.** "Meet <ruler>" on any kingdom's land opens an audience: the ruler on their throne
  in a hall like their neighbours', dressed as their people dress (new looks: the Hittites' tall
  pointed cap; Libyan feathers and sidelock; northern braids and gold torc; or a Mycenaean or
  Levantine style), their face and words showing how they feel about you, with gifts,
  protection and demands offered from there.
- **Map and news.** Kingdom land carries a light wash and border in its colour (a vassal's is
  dashed in its overlord's). The chronicle tells of kingdoms conquering each other, subduing
  tribes, settling empty land, and seizing empires' land.
- The sim now reports kingdoms' lands at the end, lands taken a game, and how many from empires.
- Balance (80 games): Greece 27%, Egypt 27%, Italia 22%, Mesopotamia 22%; empires average
  1.7–5.1 lands at the end (they were 2–9); kingdoms hold ~12 lands at the end and take ~4.5 a
  game. Every game now ends in a legacy win: with kingdoms in between, the empires meet
  later and fight each other less. Rules version 29.
- Debug launch argument: `-demoKingdom <territory>` opens an audience with that land's ruler.

### Guided start (Josh: "my brother thought the game started too abruptly… spend a few turns where it's slower and it walks you through some of the mechanics")

- **Quiet opening** (engine, `GameState.quietUntil`, set by `prepare(…, guided: true)`): for the
  first 5 rounds the player is left alone. Rival empires don't attack their land (or an army of
  theirs on open land), besiege it or land on it from the sea; kingdoms don't raid it or take
  it; pirates don't plunder it; no storms or random events strike them (no windfalls either).
  The rest of the world plays on as usual. `inQuietOpening(civ)`, `spared(territory)`.
- **The tour** (`GuidedOpening.swift`): the council walks the player through the basics, one
  step at a time, in a card under the treasury and standings. Readings wait for Continue;
  tasks tick off when done:
  1. Welcome, with the quiet opening explained.
  2. Tap the capital.
  3. Raise soldiers.
  4. March into a neighbouring land.
  5. End the turn.
  6. The harvest, grain and gold, the Realm.
  7. Meet a neighbouring ruler.
  8. Start building in a town.
  9. Choose a patron in the books.
  10. Farewell as the rivals stir.
  
  "Show me" brings each step's place into view or opens the right screen, and the map follows
  the tour. "Skip the tour" ends it. Progress is remembered per game.
- While touring, the advisors and tips wait. The first turn's "Since your last turn" flood is
  held back, and rivals' peace envoys don't burst in (their offers wait in Rivals).
- **Optional** (Josh: "let's make it optional for new players"). The first time a player picks a
  realm, they're asked: "Guide me through the first turns" or "Jump right in". The answer sets
  the **Guided** switch on the title screen (beside difficulty and scenarios), which they can
  flip for later games. Scenarios are never guided. Debug: `-demoAs <civ> -demoGuided YES`.

### A peaceful start (Josh: "we should start at peace with our rivals")

- The four empires now begin at peace with one another (`start.atPeace` in rules.json). War
  must be declared, at the usual cost in legitimacy for breaking the peace (−8). Kingdoms,
  tribes, barbarians and pirates are not party to it. Scenarios are wars already under way:
  everyone starts them at war.
- Starting at peace also means trade routes from the first turn, and no flood of peace envoys
  on round 1.
- A rival's land now shows whether you're at peace, allied or at war, with a "Meet <ruler>"
  button: the audience offers peace or an alliance, or a confirmed declaration of war.
- The AI already declared war on weaker neighbours when it ran out of land to settle; it does
  so as before. Balance (80 games): Egypt 30%, Greece 26%, Mesopotamia 23%, Italia 20%;
  empire-against-empire battles about as common as before. Rules version 30. Test rules
  (`Engine.calm()`) still start at war, as the older tests expect.
