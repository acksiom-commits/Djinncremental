# Djinncremental — System Overview (SysDoc)

**Purpose:** orient a fresh session on the *design intent* and the *current structure* of the game before any work starts. Read this first; then read source for whatever you're about to touch.
**Drafted:** 2026-10-05 from the author's design summary plus a fresh read of the source. Branch at time of writing: `difficulty-rework-star-reduction`.
**Status of this draft:** second pass (same day). The author ruled on the first draft's summary-vs-code disagreements (§9): the code was right on all of them, and the author's original Summary is superseded wherever it differs. A few smaller questions remain open in §9.

## How to read the tags

| Tag | Meaning |
|---|---|
| **[CODE]** | Read from source on the drafting date. Re-check before relying on it for a change. |
| **[INTENT]** | Design intent, taken from the author's summary. May be ahead of, or different from, the code. |
| **[NOT BUILT]** | Designed or planned. Nothing in code yet. Don't report it as a bug. |
| **[DIFFERS]** | The summary and the code disagree. See §9. |

**This doc is a map, not evidence.** For what any function does, read the function. `docs/early_game_architecture_overview.md` is a separate, older *refactor survey*, useful for file-level pain points and history, stale on content (see its banner).

---

## 1. What the game is

A Godot 4.6 incremental game with a Djinn theme. The player is a being who builds a pocket universe out of **Sparks**, guided by **Kaleb, the Archon**: assistant, tutor and narrative voice, and half of the prewritten dialogues. [INTENT]

- Prestige is narrated as **Expansion**: the pocket universe grows slightly and everything material resets.
- The design goal is to reach idle play *faster* than most incrementals. The early Archon automation (Foci) cuts clicking so the first several prestiges aren't tedious. A toggle dismisses dialogue on the first click for players who just want numbers going up. [INTENT]
- Long-play strategists should see, via mouseover all-time counters, that delaying the first Expansion is wasteful. [INTENT]
- Four **Ages**: `primordial`, `firmament`, `world`, `civilization` (`ages_popout.gd` `AGE_KEYS`). Only Primordial is built. [CODE]

## 2. Core resource chain (Primordial age) [CODE: `game_data.gd` `RECIPES`]

Sparks are *immaterial* (no storage cap, can't be Hourglass-cooled). Everything else is *material* and counts against the storage cap.

```
Sparks ─5→ Monad (Solid / Liquid / Gas, random)
Monad×4 + Spark×1 → Tetrad (15 varieties, 4 categories, below)
Tetrad×4 + Spark×1 → Particle
        ┌─ UONITE branch ("Will", cheap, bare-Spark cavity): 
        │    Particle×4 + Spark×11 → Iota → Iota×4 + Spark×36 → Mote
        │    Mote×20 + Spark×1 → UONITE   (this is also the Expansion trigger)
Particle┤
        └─ GRAIN branch ("Form", expensive, packed with real material):
             Particle×4 + Tetrad×8 + Spark×6 → Iota
             Iota×4 + Particle×8 + Tetrad×48 + Spark×36 → Mote
             Mote×4 + Monad×64 + Particle×16 + Spark×25 → GRAIN
```

Cumulative Spark cost of one finished unit: Uonite 28,801; Grain 16,825 (`UONITE_SPARKS_COST` and `GRAIN_SPARKS_COST` in `game_context.gd`). Resource keys are `iota_uonite`/`mote_uonite` and `iota_grains`/`mote_grains`; the unqualified names `iota`/`mote` are not keys.

**Tetrads — 15 varieties** (`game_data.gd` `TETRADS`): Fundaments (Adaemant 4S, Aquae 4L, Aethyr 4G); Elements (Earth, Water, Air); Symmetrics (Mud, Dust, Cloud); Medials (Silt, Sand, Haze, Mist, Ooze, Foam). Letters are Solid/Liquid/Gas counts. Note **Silt** (was "Dirt"; a save migration exists) and **Aquae** (spelling).

**Why two branches (author's rationale, 2026-10-05).** The original recipe (Uonite from 20 *Grains*, each Grain dense-packed) made the first Prestiges far too slow. Sourcing Uonites from 20 *Motes* instead, with Iota/Mote left bare and unpacked, brought the early prestige rate to roughly 3+ per session depending on play activity, which keeps early players interested. Grains moved to their own, expensive, dense-packed branch: only 4 Motes, but those Iotas and Motes must be packed with real smaller resources. [INTENT]

**Where the recipe reasoning is written down:**
- `game_data.gd` `RECIPES` comments: the Uonite branch's 11 and 36 Sparks are "cavity-fill pockets" (5 base + 6 for Iota; 36 for Mote); the Grain branch's numbers are the "verified octahedral cavity-packing decomposition".
- Geometry source of truth: `archai_lattice.gd` (`cavity_pockets()`, and the `_octa_*` helpers) with `dev_tests/test_cavity_connections.gd` and `test_archai_lattice.gd`. An octahedron of edge 2E splits into 6 octahedra + 8 tetrahedra of edge E sharing one centre. So an Iota's cavity packs to 8 Tetrads + 6 residual Spark pockets, and a Mote's to 8 Particles + 48 Tetrads + 36 Spark pockets.
- Project memory `planned_archai_purity_tier_taxonomy` has the long derivation. **Its older tables (Mote 72 Tetrads / 4,284 Sparks) are superseded; the code's 48 Tetrads / 3,780 Sparks is current.** Treat that memory as prototype-stage and defer to `game_data.gd`.

**Will / Form switch** (`GameContext.will_form_switch_is_will`, default Will = Uonite branch; commit `699d94f`, 2026-10-01). Flipping it swaps the visible creation cluster: **Create Uonite** (button, cycle bar, icosahedron display) versus **Create Grain** (button, storage-capped bar, tetrahedral lattice display via `grain_tetrahedron.gd`, counter), and fades the Uonite/Grain mini-icons beside the Particle/Iota/Mote buttons. [CODE]
- **Create Grain does not trigger an Expansion and has no per-cycle cap.** The storage cap is its only ceiling, by the author's explicit design (`manual_create_grain`, batch conversion). Create Uonite *is* the Expansion trigger and is capped per cycle by the Fibonacci `get_uonite_cycle_cap`.
- **The Grain branch is automation-only for now (author-confirmed).** The manual Iota and Mote Assemble *click* handlers (`root_ui.gd` `_on_iota_assemble_pressed`, `_on_mote_compress_pressed`) call only the Uonite-branch recipes, deliberately. The Grain-branch recipes exist in `production_manager.gd` (`manual_*_grains`, and automated batch ops `iota_assemble_grains`/`mote_assemble_grains`). **Sequencing:** the initial mid-game resource production gets defined first; only after that comes code for sorting Tetrads and so on up the chain, accounting for them, and the later numerics for how much of each mid-tier basic resource larger item categories (bars, bricks, ingots…) need. Don't wire Grain click paths or Grain-side sorting before then.
- Grains' mid-game uses are [NOT BUILT] (§7). In code, only Create Uonite triggers an Expansion; Create Grain never does. The design intent that Uonite and Grain are separate Prestige tracks, with a one-way "Densify" conversion, is from project memory: **no `densify` identifier exists in code**, so treat it as [NOT BUILT].

## 3. Automation economy [CODE unless tagged]

- **Archon Foci** (`archon_foci`): the Archon's basic automation points, assigned to tasks (summoning, compressing, assembling, constellation endowment, …). Granted by milestones and achievements (first-of-each-resource, totals thresholds, Expansion counts, Tetrad categories). Target: ~58–59 Foci by the first Uonite. [INTENT] In fiction, Focus increases are **Refinements**: changes in Kaleb the Archon Assistant. No code identifier uses that word yet; the author intends Refinements to eventually become **their own separate system**. [NOT BUILT]
- **Volitions**: higher-order automation. One is earned at each power of 5 in Foci (5, 25, 125, …) (`root_ui.gd` `_check_volition_grant`). **The second Volition is gated on tutorial progress, not just the threshold**, so a player isn't handed it unexplained.
- **Parent/Child Volitions.** The Archon constellation adds Child Volitions to each Parent Volition. A Child can only go to the same task category as its Parent. Slot model: `game_context.gd` `volition_slots`, `assign_parent_volition`/`assign_child_volition`.
- Volition targets include: production ops, purity locks, allocation-wheel entries, constellation endowment, **Volumitions** (additive click multiplier; single-category, so children auto-follow), **Stoctagon Overflow** (see below) and the **Hourglass** (cooldown cut on chosen ops).
- **Uonites**: intelligent beings that become the bulk of automation, surpassing Foci quickly. Planned four-rank ladder Uonite → Uonomoi → Uonasthai → Uonthetai (ranks of ancient Athens), with the Archon on top, able to use the best skill levels any Uonite reached. Training/skills [NOT BUILT]. Per-cycle Uonite cap is Fibonacci by Expansion count (`get_uonite_cycle_cap`).
- **Hourglass toggle** speeds chosen ops; its Volition-assigned count is capped and trimmed in `_rebuild_volition_assignments()`.

## 4. Storage and the Stoctagon [CODE]

- Storage cap starts at **987** material units (`storage_cap`), displayed by the **Stoctagon**. Sparks are exempt.
- Higher tiers *consume more than they make*, so repeated consolidation drains storage; Monads refill it fast.
- **Stoctagon Overflow**: Volitions assigned to `storage_overflow_volitions` force production *against* a full cap, which is what makes the consolidate-refill cycle run unattended.
- **Intended early strategy:** run automated Spark summoning at a deliberate deficit rather than rushing to a full cap. Manual clickers shrink automation more and make it up by clicking. [INTENT]
- **The cap grows only through The Satchel** (author-confirmed 2026-10-05): a live temporary multiplier while the Satchel is Volition-assigned, plus a flat permanent **+5% per Expansion**, granted only when the Satchel is active at Tier 3 at the moment of Expansion. There is no automatic growth from leftover Sparks; that early design was removed (2026-09-17).

## 5. Constellations [CODE: `constellation_data.gd` `BUILT_IN`]

Constellations appear as Expansions complete, are brightened by **Endowing** them with Sparks (competing with production), and give bonuses. Tiers are driven by Sparks invested, hardcoded and Fibonacci: **stars 4,181 → lines 10,946 → art 28,657** (`SPARKS_TIER_*`; each constellation's `spark_cap` is 28,657). Tier is visible as star size, then drawn lines, then an outline of the object. [CODE]

Each tier has an **unlock puzzle** (§6). Constellations are placed in the starfield per-player, and discoverable by a slight bias in Summoned-Spark flight direction. [INTENT]

Code order (id = unlock order; unlock key is `achievement:<n>th_prestige`):

| id | Name | Stars | Unlock | `bonus_key` | Tier values (stars / lines / art) | Consumer wired? |
|---|---|---|---|---|---|---|
| 0 | The Archon (KALEB) | 15 | 1st Expansion | `bonus_volitions` | +1 / +2 / **+4** child Volitions per Parent | yes (`game_context`) |
| 1 | The Spark (ALZIRO) | 16 | 2nd | `sparks_multiplier` | ×1.5 / ×2 / ×3 Spark summon, click and tick | yes (`production_manager.get_sparks_multiplier`) |
| 2 | The Hourglass (DRASIN) | 13 | 3rd | `cooldown_multiplier` | ×0.5 / ×0.25 / ×0.1 cooldown on one op | yes (`production_manager` ~2097) |
| 3 | The Bellows (DAJALA) | 18 | 4th | `click_volition_multiplier` | ×1.5 / ×2 / ×3 on the Volumitions click multiplier | yes (`game_context.get_click_multiplier`) |
| 4 | The Phial | 14 | 5th | `spark_bank_capacity` | banks Sparks across Expansions: per-Uonite rate 1 / 5 / 25, capped at ×0.25 / ×0.5 / ×1.0 of the live Stoctagon cap | yes (`get_phial_spark_bank_amount`) |
| 5 | The Satchel (HANLEE) | 17 | 6th | `storage_multiplier` | live ×2 / ×3 / ×3 Stoctagon cap while Volition-assigned; **tier 3 also gives a permanent +5% to base cap on Expansion** | yes (`get_effective_storage_cap`, `do_prestige_reset`) |
| 6 | The Vessel (ENIGMA); **code string is still `"The Djinn"`** | 17 | 7th | `endowment_multiplier` | ×1.5 / ×2 / ×3 declared | **NO reader anywhere; inert** |

**Author-confirmed 2026-10-05:** the order is Archon, Spark, Hourglass, Bellows, Phial, Satchel, Vessel. All the tier values above are correct as coded (Archon +1/+2/+4 children, Hourglass ×0.5/×0.25/×0.1, Satchel flat +5% at Tier 3). **The eighth early-game slot is set aside as a monthly Patreon Tier reward**; it has no entry in `BUILT_IN`. **The Stoker was renamed The Bellows**, whose effect is a multiplier on the Volumition click increase (long playtested). The Stoctagon-Overflow multiplier in the original Summary is no longer part of the design.

Other facts: The Archon also has `mechanic_key: unlock_archon_titles`. The Vessel is the **Player's own constellation**. **Its layout (Lamp, Ring or Jar) is chosen by the Player on the game's Start screen** (`intro_screen.gd`'s vessel-selection sequence), stored as `GameContext.chosen_vessel`, and resolved by `_resolve_vessel_layout()` in `constellation_data.gd` for both hard-mode geometry and each vessel's nested Beginner-mode `easy_layout`. Jar is designed (17 stars); Ring and Lamp art were still pending when last read. Earlier history called it "The Djinn"; **the code string `"The Djinn"` is deliberately left as is for now** (author, 2026-10-05), as are header notes that use it.

**Vessel bonus (author-confirmed):** `endowment_multiplier` ×1.5 / ×2 / ×3 on the Endowment rate stays the intended bonus. It is **deliberately inert for now**: eventually it will apply to the Endowment rate of *multiple selected Constellations at once*, but the selection UI for that isn't defined even for one constellation at a time, so nothing reads it yet. Don't report that as a bug. [NOT BUILT] The Archon resets to Tier 0 each Expansion, so child Volitions clear. Constellation IDs 0–15 built-in, 16–31 player-designed, 32–47 Patron monthly, 48–63 reserved. [CODE, `constellation_data.gd` header]

**Planned 64-slot sphere:** 8 octants × 8 cells, in four sets of 16 (preset bonuses / player-customized / monthly Patreon-designed / spare). [INTENT]

**Ids have been renumbered several times** (Bellows/Satchel/Phial swaps; see the `constellation_data.gd` v0.3.5–0.3.8 history). If you ever see a bare id literal in code or a test allowlist, check it against this table. Names/art/puzzle data stay with their constellation; only id/octant/unlock move.

## 6. The Constellation puzzle (the big subsystem)

Each tier is unlocked by a **logic-grid + musical puzzle**, then a **motif-playing** step. This is by far the largest subsystem (the generator file alone is ~10k lines, and `dev_tests/` has ~98 files). Tags: **[CODE]** read from source on 2026-10-05 (the earlier **[NOTES]** items were re-checked against source the same day; the corrections are folded in below); **[AUTHOR]** a design premise or rule stated by the author, which code cannot confirm; **[UNVERIFIED]** not checkable from source (e.g. how something looks on screen).

### 6.1 What the player does

1. **Study** a constellation (Study Overlay). Every star has a **name, colour, pitch and firing order**. The player *solves for* the **firing order (SEQUENCE)** and **which star each NAME denotes**. [CODE]
2. **Colour and Pitch are observables**, not unknowns: Colour is painted on the map, and **Listen** (a header toggle) plays a star's exact pitch. Neither carries a uniqueness requirement and neither has a solver. **Author premise:** players are presumed to have Listened to every star; skipping it is on the player, not the puzzle or the hints. So Colour/Pitch get no "deduce next" hints. [CODE for no-solver and for the hint axes (§6.4); AUTHOR for the premise] One nuance: hints do treat an unlistened star's pitch as still "maybe", and a hint can say "go Listen" when that would unlock progress (`hint_pitch_blocked`).
3. Clues are English sentences; the player marks the **Star Map**, the **Staff** and the **Sort** tab, all of which write into one shared set of match records (§6.4).
4. When solved, the player **clicks the stars in order to play the motif**, and the game answers with the call-response phrase. [INTENT; code in `click_sequence_puzzle_engine.gd`]

Each constellation's source melody: Archon, *The Liberty Bell*; Spark, Hallelujah Chorus; Hourglass, *Hall of the Mountain King*; Bellows, *Marriage of Figaro* Overture; Phial, *Tritsch-Tratsch Polka*; Satchel, see its entry in `constellation_data.gd`; Vessel, *Also sprach Zarathustra* (opening). [CODE, `puzzle_sequence` comments] Solve/reward audio files (`sequences/*.tres`) exist **only for constellations 0 and 1**; for the others the engine skips the audio silently and finishes the sequence. [CODE, `sequences/` and `click_sequence_puzzle_engine.gd`]

### 6.2 Difficulty: Easy (Beginner) and Hard

- Two difficulties per constellation, toggled from the Study Overlay; **the default is "easy"** for every constellation the player hasn't touched (`GameContext.get_constellation_difficulty`). Changing it regenerates that one puzzle, the same flow as RESET. [CODE]
- **"Easy" means a different, smaller, separately authored star layout**, not just fewer clues: each constellation has an `easy_layout` (this is what the code comments call "Beginner mode"). Beginner star counts: Archon 10 (Hard 15), Spark 7 (16), Hourglass 8 (13), Bellows 7 (18), Phial 6 (14), Satchel 7 (17), Vessel 8 (17, per vessel). It is a separate shape, not a subset of the Hard stars. The Vessel resolves its layout through the vessel choice first, then the difficulty. [CODE, `_resolve_difficulty_layout`]
- **Beginner melodies repeat.** An Easy layout has fewer stars than melody notes (Archon: 10 stars, 15 notes), so some stars fire more than once. **The repeat shape is public**: the staff shows which notes are the same star, with colours (singleton notes dim, repeating notes green until the star's colour is known) and arcs joining a repeating star's notes. A Hard melody is 1:1 and unaffected. [CODE: `_melody_repeats()`, `_staff_tick_color`, `_draw_repeat_arcs`. The colour rule is: known colour wins; otherwise a singleton note in a repeating melody is muted, and a repeating star's notes use the green "unknown" colour. How it looks on screen is UNVERIFIED; the drawing was only smoke-tested headless.]
- **Wording rules (author):** a clue names a star by one of its staff notes ("the star that fires 15th note"), and order clues say "first fires" when a mentioned star repeats (`_seq_tick_phrase`, `_seq_fire_verb`). **Never use the word "debut" player-facing**; the author rejected it (no `.gd` file contains it today). Hiding the repeat shape is a possible *later* difficulty option. [CODE for the wording; AUTHOR for the rule and the later option]
- **Hard** uses the full star counts, all Forms, and one guaranteed opening Mutual Exclusion. **Easy** leans on direct clues: tier mix 55/38/7%, six Forms excluded (3, 9, 14, 20, 21, 22), caps on Forms 12 and 15, and an ordered list of guaranteed opening clues. [CODE, `DIFFICULTY_PROFILES`]

### 6.3 The clue generator (`constellation_logic_puzzle.gd`)

Pipeline, in order (the file's own header is the authoritative version):

1. **Ground truth**: stars, names, colours, pitches, firing order (`sequence_rank_solution`) and map hop distances.
2. **Matrix/cells**: every pair of star characteristics is a cell graded true or false. A cell is marked "used" only when a clue consumes it. Distance is relational, tracked separately.
3. **Forms**: **25 automated clue templates** (`FORM_NAMES` has 26 ids; **Form 18, Degree Fact, is deliberately hand-tuned only**). Each builds a clue from sampled cells, chained so it links to an already-used characteristic. Examples: Exact Identity, Single/Dual Negation, Disjunction, Pairwise Order, Exact Offset, Adjacency, Range, Count, Extreme, Equality Pair, **Mutual Exclusion** (the "five-way" clue), Group Order/Comparison/Membership/Negation, Distance Existential/Extreme, Betweenness, Non-Adjacency, Cross-Domain Bridge, Pseudo-True Pairs (deliberately near-miss phrasing), and the Beginner-only **Firing Position (25)** and **Firing Relation (26)**, which talk about *when* a repeating star fires, including note arithmetic. Forms are grouped in three tiers (Entry Anchors / Relational Workhorses / Systemic Constraints; target mix 25/45/30%).
4. **Rendering**: each Form writes the English text and records what it *visibly states* (`search_terms`).
5. **Disclosures**: each clue also stores typed facts (`solver_facts` for the Sequence solver; `value_facts` for the Name axis and the deduction engine). **The disclosures, not the text and not the cells, are what every gate reads.** A clue is stored four ways (text, disclosures, cells, chars/search_terms); don't confuse them.
6. **Gate**: an attempt is accepted only if Sequence is uniquely solvable (`seq_unique`), every name is paired with another characteristic (`name_unique`, a mention-coverage flag), and a real Name proof holds (`name_unique_closure`). It retries; **if nothing passes, the puzzle is refused** (not cached, and the Study panel shows "not ready" until a retry passes).
7. **Post-passes**: name-coverage clues, a disambiguating-clue fallback (`_repair_uniqueness`), redundancy pruning, an anchor recheck and a whole-set safety net.

**One solver**, `_solve` (propagation plus bounded backtracking), is used for Sequence and, restricted by the one Sequence solution, for the Name closure. A search that hits its budget is never read as "unique". There is **no Pitch solver** and no matrix position axis. A dormant MUS-extraction explainer and difficulty score exist (`COMPUTE_DIFFICULTY_SCORE` is false); they take minutes per puzzle. [CODE]

**Traps worth knowing before touching it:**
- **The ship gate needs all three**: `seq_unique`, `name_unique` and `name_unique_closure` (`_gate_result_passes`). Until 2026-09-20 it checked only `seq_unique` and `name_unique`, and `name_unique` is just mention-coverage, not a proof, so a puzzle with two swappable stars shipped. Separately, earlier probes that measured only the closure reported perfect health while the gate was failing on `name_unique` (a "name_unique" gate that pruning had broken). Any health probe should report all three. [CODE; some code comments still describe the older gate]
- Capping Forms to rebalance the clue mix was **measured and rejected** (much slower generation, no mix gain). Don't retry caps on the negation Forms. [CODE, the `form_caps` comment]
- Forms 25/26 are exempt from redundancy pruning. [CODE, header]
- The generator runs at runtime for the player, so **generation time is a cost**: measure it alongside any mix change.

### 6.4 The player side

- **Match records** (`constellation_puzzle_deduction.gd`): the Star Map popup, the Staff popup and the Sort tab all write into one shared `_match_records` set. Effective state is read through `_effective_*`, folding in ground truth, slot label, raw toggle and derived state, in that order. The deduction engine propagates what the player has marked (including identity merges and sibling clearing).
- **Contradiction detector** (`_detect_contradictions`): runs on every refresh and flags impossible boards. It reports: a record no star can satisfy; a settled record whose own marks rule out its star (only possible for a confirmed identity); a record with every name, pitch or colour eliminated; two records provably the same star that disagree about a value; a merge refused because the records' marks clash; and one name claimed by two entries. **Two records merely sitting on the same star is *not* a contradiction** (it is the normal case). The wording only says a set is empty or that two of the player's own entries clash, **never which mark is wrong and never the correct value**, and the Name axis is never compared against ground truth. [CODE]
- **Tabs** (`constellation_puzzle_widgets.gd`): **Clues** (the working list; green = untouched, magenta = the player has marked something it names; the player can retire clues), **Notes** (free text plus clues filed by right-click), **Guide** (**placeholder text only**; content is not written), **Search** (filters by each clue's `search_terms`), **Hint**, and an **Explain** tab hidden by default (a dev view that reads ground truth, never player-facing). A "Waiting" bucket for clues blocked on another unknown clue is deliberately not built. [CODE]
- **Hints are five tiers, all currently free** (`hint_cost_sparks` is 0 for every tier, kept so prices can be set later): 1 "Is anything waiting?", 2 "Point me to a clue", 3 "What does it bear on?", 4 "Show me the step", 5 "Walk me through every step". Tiers 3–5 are built on an **actionable next-step finder over the player's own board** (`constellation_next_step_finder.gd`, `hint_next_steps()`), not on the MUS explainer. `hint_next_steps()` merges **four kinds of step**: Sequence, Name, Position (which stars a position can hold) and joint Name×Position steps, sorted by "resolves a star" first, then information gained. Tier 2 points at the lowest-numbered clue that still has something to give; tier 5 chains every currently reachable step (slow on an early board, so it shows a loading message). A hint can also *interrupt* with "you need to Listen to a star first", or report that waiting clues already say only what the player knows. [CODE]
- **Hint leak rules** (each has a guard test): a star is named only through a Name, Colour or Pitch descriptor already in the clue's own `search_terms` (**never by its Sequence position**, which would be a spoiler or a tautology); eliminations are built on the player's own candidate stars (`_stars_possible_for_descriptor`), a superset of the truth; every hint is re-validated against the live board on each repaint. Guard tests: `test_name_hints`, `test_next_step_hints`, `test_position_group_hints`, `test_joint_hints`, `test_implied_hints`, `test_hint_tiers`, `test_chain_hints`. [CODE]
- **Not built:** Colour/Pitch hints (moot by the Listen premise), multi-clue steps (measured and rejected: single-clue steps always exist mid-game), Kaleb-voiced hint text, hint prices.

### 6.5 File map (all at repo root)

| File | Role |
|---|---|
| `constellation_data.gd` | Autoload. Definitions, tiers, geometry, easy/vessel layout resolution, bonuses, puzzle cache passthrough, save/load. |
| `constellation_logic_puzzle.gd` | Ground truth + Forms generator + uniqueness solver (largest file). |
| `constellation_study_overlay.gd` | Orchestrator shell for the Study panel (Listen mode, difficulty toggle, star map). |
| `constellation_puzzle_widgets.gd` | All widget construction (tabs, popups, hint UI, star widgets). |
| `constellation_puzzle_deduction.gd` | Player-side deduction engine (`_match_records`, contradictions, hint step ranking). |
| `constellation_next_step_finder.gd` | Pure next-step finder used by hint tiers 3–5. |
| `constellation_content_certifier.gd` | Content-certification checks (e.g. intentionally isolated stars). |
| `constellation_overlay.gd`, `click_sequence_puzzle_engine.gd`, `constellation_fork_puzzle.gd` | The playable motif-clicking puzzle. |
| `staff_popup.gd`, `staff_popup_row.gd`, `*ChecklistPopup.gd` | Staff and per-axis checklist popups. |
| `constellation_popout.gd`, `constellation_panel.gd` | Selector/info UI (tier effects, endowment). |
| `puzzle_synths.gd`, `puzzle_sequence_resource.gd` | Audio. |

**Dev tests are the contract.** `dev_tests/` is tracked in git. **The run command, filename rules and hang traps are in `dev_tests/README.md`; read it before running anything.** `test_matrix_up_lint.gd` guards a recurring class of puzzle-logic bug: before any puzzle-logic change, ask whether you are reasoning over a CELL/VALUE or over a STAR and its characteristics.

## 7. Planned mid-game and beyond [INTENT / NOT BUILT]

Only stock *definitions* exist in code (`game_data.gd`: phlogiston, clay, stone, iron/copper/silver ore, oil, infusion, elixir, steam, smoke, spirit); there is no production loop for them yet. `FirmamentUI.tscn` is deliberately sparse.

Design:
- Grains become basic mid-game resources: **Earth** (Clay, Stones, Ores), **Water** (Oils, Acids), **Air** (Firedamp, Vapors).
- **Fuse** (the mid-game click, analogous to Summon Spark) makes creation resources: Solid (Bricks, Ingots, Gems…), Liquid (Baths, Infusions, Elixirs…), Gas (Steams, Smokes, Spirits…).
- Those make **Tools** (Hammers, Vats, Alembics…) and **Devices** (Forges, Crucibles, Distilleries…). They speed early-game compression and assembly, enable Forging and Calcination, and boost their own resources.
- Leveling **Skills** (Forging, Quenching, Calcination, Distillation, Vaporization…) that Uonites learn from automation experience.
- Archon **allocates Uonites** to tasks against player-set goals.
- **Purity locks**: hold chosen resources in storage so higher-tier items are built from them. This protects Fundament percentages, needed for high-purity Ingots/Gems and for achievements that raise Foci/Volitions. A minimum Fundament percentage per Grain is planned as the survival condition for stored resources across resets.
- **Endgame**: sufficiently pure, Fundament-rich Grains build **World Layers** (Earth, Water, Air), then ecologies, villages, towns, and finally Material-themed **Cities** (the City of Brass is the first).

Other designed-not-built items live in the project memory index (Archai/Particle lattice geometry, Uonite neurology, Sigils and Runes, Repeat Count clue axis, Kaleb-voiced hints). Check there before proposing anything in these areas, and treat each as a prototype unless its note says shipped.

## 8. Presentation, community, structure

- **Starfield background:** solid black at start, gains stars as unspent Sparks accumulate, fades again under a deficit strategy. 360° rotation on 2 axes. Spark summon = quick icon flash, then a small bright dot flies off. [INTENT]
- **Community [NOT BUILT]:** tiered Patreon names on the ticker bar; a monthly/weekly cooperative Mastermind-style puzzle to deduce a rare resource's composition and position, with premiere/regular/small rewards; legal YouTube music recommendations on the ticker; a monthly/weekly single-elimination "battle of the songs" (6–14 submissions).
- **Autoloads** (`project.godot`): `GameData`, `ConstellationData`, `GameContext`, `ProductionManager`, `SaveManager`, `ArchonDialogueManager`, `AchievementRegistry`. Main scene `IntroScreen.tscn` → `RootUI.tscn` (Primordial) → `FirmamentUI.tscn`.
- **Core scripts:** `production_manager.gd` (tick loop, all production ops), `game_context.gd` (state + slot model + prestige reset + save), `root_ui.gd` (Primordial controller, triggers), `archon_dialogue_manager.gd` (all dialogue; new beats must register a save flag), `big_num.gd` (all large numbers).
- **Saves:** `save_manager.gd`. Any rename of a saved key needs its own migration (precedents: `TETRAD_VARIETY_RENAMES`, `HOURGLASS_OP_RENAMES`).

## 9. Rulings and open questions

**Resolved by the author, 2026-10-05.** The original "Djincremental Summary" is out of date on each of these; the code was right:

| # | Topic | Ruling |
|---|---|---|
| 1 | Storage growth | The cap grows only through The Satchel. |
| 2 | Satchel Tier 3 | A flat +5%, applied only when the Satchel is active at Tier 3 at Expansion. (Not +15%.) |
| 3 | Archon child Volitions | +1 / +2 / +4 per tier. |
| 4 | Hourglass | ×0.5 / ×0.25 / ×0.1. |
| 5 | Stoker | Renamed The Bellows; its effect is a multiplier on the Volumition click increase. The Overflow-multiplier effect is not part of the design. |
| 6 | Recipes | Intentionally changed: Uonite = 20 Motes + 1 Spark with bare Iota/Mote; Grain = 4 Motes with dense-packed Iota/Mote; Particle = 4 Tetrads + 1 Spark. See §2. |
| 7 | Constellation order | Archon, Spark, Hourglass, Bellows, Phial, Satchel, Vessel. The eighth early slot is a monthly Patreon Tier reward. |
| 8 | Tetrad names | Silt and Aquae are current (the Summary's "Dirt"/"Aqauet" are old). |

**Resolved later the same day:** the Vessel code string stays `"The Djinn"` for now; the Vessel's `endowment_multiplier` stays the intended bonus but is deliberately unread until a multi-constellation selection UI exists; the Grain branch is automation-only until initial mid-game production is defined; "Refinements" is the in-fiction name for Focus increases and will later be its own system. All four are written into §2, §3 and §5.

**Still open:** nothing at the moment. §6 was expanded later the same day, and its memory-derived items were then checked against source (corrections folded in). Stale code comments found during that check, not edited: `constellation_puzzle_deduction.gd` ~330 says the merge-absorption hole "is still open" (the code below it handles merge refusals), and `constellation_logic_puzzle.gd` ~9026 says `name_unique` alone is the live gate (it is all three).

## 10. Maintenance

Update this file when a system's *design* changes, not on every commit. When something moves from **[NOT BUILT]** to built, flip the tag, name the owning file, and delete the matching §9 line if it resolves a disagreement. When memory and this doc disagree, read the code and fix both in the same turn.
