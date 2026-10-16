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
4. **Orders**: Recruit units, move armies and fleets, establish or cut trade routes, propose
   agreements.
5. **Battles**: Any contested territory triggers a battle: set formation, watch it resolve.
6. **End turn**: Pass the device (MVP hot-seat).

Target session: **45–90 minutes** for a full game, playable in sittings. (Open question; see §13.)

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

1. **Deploy**: Each side places units on its 2 rows of the 5×5 grid (the physical battle board),
   hidden from the opponent. Terrain tiles are shown.
2. **Orders**: Each unit or flank gets a simple stance: *Hold*, *Advance*, *Flank*, *Skirmish*
   (archers fall back when engaged).
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
  system on a sea grid, or auto-resolve only for MVP; see §13).
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

The MVP is a **playtestable vertical slice**, not a store launch.

**In**
- iPhone (portrait-first; iPad universal if cheap)
- 2–4 player **hot-seat** (pass and play)
- Full painted map (~45 territories), terrain, sea zones
- Infantry, archers, cavalry, ships
- Formation battles with animated resolution + auto-resolve
- Generals with traits and renown
- Grain supply with visible supply lines and attrition
- Resources and basic trade routes, with chokepoints
- Agreements: passage rights and trade pact
- Neutral barbarians (simple scripted behavior)
- Monarchy + Republic, rulers, succession, civil war
- ~10 events
- Save/resume

**Out (post-MVP)**
- AI opponent for single-player (biggest post-MVP item; required for launch)
- Online multiplayer (Game Center turn-based)
- Tribal government, tribute/embargo, neutral trading cities
- Bronze → Iron Age transition
- Sieges and city walls; tactical naval battles
- Additional civilizations

Note: **without a single-player AI this is a playtest build, not a product.** Most phone players
play alone. The architecture must make adding AI straightforward (see §12).

## 12. Technical architecture

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

## 13. Open questions

1. **Session length**: 45–90 min target, or a shorter (~30 min) mode for phone play?
2. **Battle depth**: is the stance system (Hold/Advance/Flank/Skirmish) enough, or do players want
   to give per-unit orders?
3. **Naval battles**: same formation system on a sea grid, or auto-resolve only?
4. **Civil war in multiplayer**: does the losing faction become neutral, or can another player
   back a claimant?
5. **Victory conditions**: domination, wealth, prestige score at the end of the time track, or all
   three?
6. **Rulebook reconciliation**: the existing board-game rulebook should be mapped onto this doc;
   where they conflict, decide which wins.
7. **Territory list**: confirm the final territory set and adjacency from the painted map.

## Appendix: territories on the painted map

Hibernia, Caledonia, Britain, Sitones, Saxone, Suebi, Venedi, Gaul, Hispania, Pyrenees, Baetica,
Alps, Italia, Sicilia, Macedonia, Greece, Crete, Mauretania, Numidia, Sahara, Cyrenaica, Libya,
Dacia, Thrace, Scythe, Sarmatia, Caucasus, Dahā, Media, Armenia, Taurus, Anatolia, Cyprus, Syria,
Mesopotamia, Persia, Petraea, Egypt, Arabia. *(Plus unnamed regions to confirm.)*
