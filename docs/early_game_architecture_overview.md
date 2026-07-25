# Early-Game Architecture Overview

**Written:** 2026-07-22, ahead of the first refactor pass since the Mote-based Expansion change and the Simon-says → zebra-grid puzzle rewrite.
**Scope:** everything from Sparks through Expansion/prestige, plus the full Constellation puzzle system.
**Purpose:** orientation for a returning developer before splitting up the two files that have outgrown themselves (`constellation_study_overlay.gd`, `constellation_logic_puzzle.gd`) and cleaning up the wiring around them. This is a survey, not a changelog — treat file:line references as approximate anchors, not exact contracts.

**Read this together with existing memory** (`constellation_puzzle_*` entries) for how the Forms/Kinds/Clues generator behaves at a mechanical level — this doc covers structure and pain points, memory covers correctness properties already verified in-engine.

---

## 0. Two things to resolve before anything else

These surfaced during the audit and aren't refactor concerns — they're open questions or live bugs.

1. ~~**Only 5 constellations are defined, not 6.**~~ **RESOLVED** — `constellation_data.gd` now defines ids 0-5 (6 constellations, The Djinn added).
2. ~~**Two live economy-tracking bugs from the Grain→Mote Uonite migration**~~ **RESOLVED** — `game_data.gd` `RECIPES["uonite_assemble"]` and `production_manager.gd`'s `get_consumption_network()` both fixed to route through Mote.

---

## 1. Production / Economy Chain

**Files:** `production_manager.gd` (1363), `game_data.gd` (171), `big_num.gd` (344), `resource_registry.gd` (2, dead stub — see §5).

### Shape
`sparks → monad → tetrad → particle → iota → mote → grain`, driven by per-op timers and worker counts, ticked in `production_manager.gd:_process` (171-226). `monad_compress`/`tetrad_assemble` are bespoke (random S/L/G subtype rolls, 411-456); `particle_compress`/`iota_assemble`/`mote_compress`/`grain_assemble` share a generic path (`_produce_generic` + `GENERIC_OPS` table, 59-80 & 462-496).

**Uonite creation is now Mote-gated** (`manual_create_uonite`, 1033-1056: 20 Mote + 1 Spark, capped by `game_context.gd:get_uonite_cycle_cap()`, a Fibonacci-by-expansions value). Every successful Uonite creation fires the Expansion/prestige reset immediately: `root_ui.gd:1918 _on_create_uonite_pressed` → `_play_expansion_animation` (1954) → `_do_prestige_reset` (1292) → `game_context.gd:1365 do_prestige_reset`. Moving the gate from Grain to Mote — one stage earlier in the chain — is the entire mechanism behind the 90-120min → 30-45min speedup; there's no separate "fast path" logic to account for.

`do_prestige_reset` (`game_context.gd:1365-1426`) wipes sparks through grain, cycle counters, and Manifold state; **preserves** Volition-slot structure, purity locks, assignment keys, and lifetime totals. `expand_storage_cap()` (465-477) converts leftover Sparks into permanent storage growth each cycle.

### Key API
Signal: `manifold_ticked`. Entry points: `manual_summon_spark/monad_compress/tetrad_assemble/particle_compress/iota_assemble/mote_compress/grain_assemble/create_uonite`, `reset_for_prestige()`, `apply_offline_progress()`, `get_consumption_network()`, `get_smoothed_rate()`. `game_context.gd` exposes `do_prestige_reset()`, `get_uonite_cycle_cap()`, `expand_storage_cap()`.

### Pain points
- **Recipe costs duplicated 4x** (and already drifted once, per §0): `GENERIC_OPS` (59-80), hardcoded literals in `_op_has_inputs` (553-575), `get_consumption_network` (1263-1279), `game_data.RECIPES` (108-116). Any future cost change has to be made in four places by hand.
- **Batch vs. single-unit duplication**: `_produce_monad_compress`/`_produce_tetrad_assemble` (batch) vs. `manual_monad_compress`/`_try_assemble_tetrad`/`_try_assemble_iota`/`_try_assemble_grain` (884-1122) reimplement near-identical draw/spend logic separately rather than sharing one code path with a quantity parameter.
- **`_process` (171-226) is a junk drawer**: tick accumulation, storage overflow routing, Manifold transforms, and Constellation spark accumulation all live in one method.
- **`_batch_roll_monads`/`_batch_assemble_tetrads`/`_batch_distribute_tetrads`** (594-836) is a dense probability-distribution block, worth a closer read before anyone touches subtype odds.
- Leftover debug `print()` in production paths: 274, 1028, 1044 (`[UONITE-TEST]`, `=== OVERFLOW TICK ===`).
- `manual_create_uonite`'s own comment still calls it "grains-out-experiment" (1034) — reads as prototype code despite being the live prestige trigger.
- Magic numbers with no single tunables block: `RANDOM_DRAW_THRESHOLD = 1000` (29), Manifold purity thresholds `0.60`/`0.35` (355-369), `EMA_ALPHA = 0.10` (344), Fibonacci Uonite-cap seed (`game_context.gd:524-525`).
- `game_data.gd`/`big_num.gd` themselves are clean — no notes.

---

## 2. Root UI / Orchestration Layer

**Files:** `root_ui.gd` (2647), `game_context.gd` (1428), `archon_dialogue_manager.gd` (1118), `archon_tetrahedron.gd` (461), `firmament_ui.gd` (117).

### Shape
`game_context.gd` (`/root/GameContext`) is meant to be a pure-state singleton (resources, Volition-slot assignment model at 604-930, purity locks, save/load) but has drifted to include real logic: `expand_storage_cap`, `accumulate_constellation_sparks`, `do_prestige_reset`, `toggle_lock`/`toggle_category_lock`. The in-file changelog claiming "v1.0.0: production logic removed" is no longer accurate.

`root_ui.gd` is the top-level scene controller for the Primordial age and has become a god object: button wiring, resource-bar rendering, dialogue-panel wiring, tutorial FX, the Expansion shader animation, Archon "poke"/lockdown minigame logic (embedded directly in `_on_archon_panel_gui_input`, 387-461), name-picker UI, constellation puzzle generation/caching (868-964 — `root_ui.gd` instantiates `ConstellationLogicPuzzle` directly, puzzle setup isn't delegated to a manager), achievement granting, and ~25 narrative trigger predicates (`_check_*_trigger`, 1244-1503, all polled unconditionally every `_process` tick).

`archon_dialogue_manager.gd` is comparatively clean: one `enqueue_*` function per narrative beat (20+), each with its own `*_done` save flag, fully wired end-to-end (signals connect, `sequence_complete` fires, save/load round-trips). It touches `GameContext` exactly once (line 442). The bulk of the file (600-1118) is narrative string literals interleaved with control flow — every new story beat means editing this one file rather than authoring data.

`archon_tetrahedron.gd` is self-contained (procedural mesh, expression/tween system) and has no game-state coupling — clean by comparison.

### A live scene/script drift bug — RESOLVED 2026-07-24
`root_ui.gd:1010` transitioned players to `TESTFirmamentUI.tscn` (test-prefixed name, shipping as the real transition target). Meanwhile `FirmamentUI.tscn` — the scene that reads as "the real one" by name — had drifted to load `root_ui.gd` as its script instead of `firmament_ui.gd`. Confirmed via node-tree comparison that the two scenes weren't near-duplicates: `FirmamentUI.tscn` (root_ui.gd) was a far more complete build (full constellation panel, every production button with cooldown bars, Uonite creation viewport) than `TESTFirmamentUI.tscn` (firmament_ui.gd, resource bars + Archon + dialogue only, no constellation/production UI) — raising a real question of whether content needed to migrate rather than just picking a name. Confirmed with the dev: `TESTFirmamentUI.tscn`'s sparseness is intentional (Firmament-age production/constellation gameplay isn't built yet by design); `FirmamentUI.tscn` was a genuinely abandoned earlier prototype. Resolution: deleted the old `FirmamentUI.tscn`, renamed `TESTFirmamentUI.tscn` → `FirmamentUI.tscn`, updated `root_ui.gd:1010`'s transition target to match. `constellation_selector.gd` (only used by the deleted scene) and `RootUI_v2.tscn` (confirmed unused, referenced nowhere in code) were removed in the same pass — see §4/§5 below, also updated.

### Pain points
- `root_ui.gd:884-964` — `_start_puzzle_generation`/`_dev_recompute_puzzle` duplicate ~35 lines of puzzle setup nearly verbatim.
- `root_ui.gd:1244-1503` — ~25 hand-rolled `_check_*_trigger` functions with near-identical guard-clause shape; a data-driven trigger table would collapse this into one loop plus a data file.
- `root_ui.gd:1509-1593` — dev/cheat hotkeys live permanently in `_input()` next to production code, including commented-out dead key handlers (1511-1517).
- `root_ui.gd:387-461` — Archon poke/lockdown minigame (durations, thresholds, achievement grants) belongs in its own component, not a click handler.
- `game_context.gd:1231-1242` and `:795-812` — the category↔key mapping is encoded three separate times (`_key_to_category_target`, `_volition_assignment_key`, `_bonus_volition_assignment_key`).
- In-fiction terms used as literal identifiers with no gloss at point of use (`"stoctagon"`, `AUTO_FOLLOW_CATEGORIES`, "Volumitions") — a returning dev has to cross-reference dialogue text to know what these mean in plain terms.
- `root_ui.gd:85-86` — `_first_prestige_triggered` is flagged `@warning_ignore("unused_private_class_variable")` rather than removed.
- Several `_on_*_complete` dialogue handlers are empty `pass` stubs with no UI consequence (810-811, 814-815, 828-837) — dead-end sequences, likely fine but worth a pass to confirm nothing was meant to happen there.
- `archon_dialogue_manager.gd:913-949` — third/fourth/fifth prestige dialogues are one-line placeholders ("Hourglass placeholder dialogue," etc.) — known unfinished content, not a bug.
- `archon_dialogue_manager.gd:978-992` — `enqueue_close_constellation_panel` is commented out, but its `*_done` flag, signal, handler, and save/load entry are all still live — a half-removed feature with dangling scaffolding that should either come back or be fully deleted.

---

## 3. Constellation Data & Puzzle Core

**Files:** `constellation_data.gd` (1259), `constellation_logic_puzzle.gd` (3860, **primary refactor target #2**), `constellation_star_namer.gd` (68), `puzzle_sequence_resource.gd` (69, appears disconnected from the current pipeline — no references found in any audited file, confirm with dev whether it's still needed).

### `constellation_data.gd`
Owns constellation definitions (`BUILT_IN`, see §0), octant geometry, unlock/mechanic-unlock logic, seeded star positions, patron-JSON loading, and save/load including puzzle-cache passthrough. No constellation currently sets the optional `name_theme` field, so `ConstellationStarNamer.DEFAULT_THEME` is the only theme ever exercised in practice — a built feature that's never actually used.

### `constellation_logic_puzzle.gd` — where the (now 3398) lines go — **RESOLVED 2026-07-25**
Line numbers below are from the original 3860-line audit; the file is now 3398 lines after the change described next, so treat these as approximate/historical.

| Lines | Section |
|---|---|
| 1-81 | Header docstring — **stale**, describes the Forms as "not yet built" when 21/22 are fully implemented and live. Rewrite or delete before using this file top-down. (The one specific stale claim about the Pitch solver's literal strings "will be re-keyed to Form names" was fixed as part of the change below; the rest of the header is still stale.) |
| 84-400 | Ground-truth generation (colors, degrees, distances, name shuffle, pitch rank) |
| 403-941 | Sequence-axis CSP solver (possibility grid, arc-consistency, backtracking) — **live**, the Phase C uniqueness gate; untouched. |
| ~~942-1530~~ | ~~Pitch-axis CSP solver — structurally a near-total clone of the Sequence solver with `_pitch_` prefixes~~ **DELETED 2026-07-25, on branch `remove-dead-pitch-solver`** (not yet merged to `grains-out-experiment`). Three parallel exploration passes confirmed this was never live — no Form builder in the Forms/Cells pipeline ever emits a `tone_*` clue; Pitch carries no uniqueness requirement (fully recoverable via Listen), a design property that predates the Forms rewrite. Building it out would have been a regression to the old per-axis-solver architecture the Forms rewrite replaced, not a missing feature. See [[refactor_branches_in_flight_2026-07-24]] memory for details. Two smaller, separately-confirmed-dead pockets found alongside it were removed in the same pass: the Sequence-side `_possibility_grid_for_clues` front-end and four generic `_domain_*` helpers (all zero callers). |
| 1565-1690 | Public generation entry point, cache (de)serialization, dead-stub comment for the never-ported Name-axis solver |
| 1692-2140 | Record arrays, clue-text rendering (`_characteristic_label`), the True/False/Used matrix and its sampling primitives |
| 2141-2340 | Orderable-axis helpers, solver-fact extraction |
| **2341-3619** | **The 22 (21 live) Form builders — ~33% of the file, the dominant mass** |
| 3639-3690 | Form-tier classification + scheduling weights |
| 3691-3860 | Generation pipeline: `generate_clues_forms`, retry/orchestration loop |

**Duplication inside the Form builders is real, not just size**: `_build_form_exact_identity` (2393) and `_build_form_single_negation` (2413) differ by one boolean check and a connective word. The "reuse chain node if valid, else scan a shuffled star pool" fallback pattern is hand-rolled separately in at least `_build_form_dual_negation` (2802) and `_build_form_mutual_exclusion` (2905) rather than factored into one shared helper. Text rendering, matrix sampling, and `solver_facts` construction all live inside each `_build_form_*` rather than being split into a rendering pass — apparently deliberate (per the header's original intent) but means each Form function does three jobs.

**A real correctness gap, not just a doc note:** Name-axis uniqueness has no constraint-propagation proof the way Sequence does via `_solve()` — it's currently verified only by a heuristic co-occurrence check (`name_revealed`, 3743, 3803-3813). The old file's Name solver (~560 lines) was dropped during the rewrite and never replaced. This matches the standing gap already tracked in memory (`constellation_puzzle_csp_review_findings`, `constellation_puzzle_multivariate_clue_requirement`) — this doc doesn't change that assessment, just confirms it's still true in the current file.

**Dead public API** (declared, zero external callers, confirmed via project-wide grep): `is_generation_complete()` (1576), `check_solution()` (1590), `get_form_clue_texts()` (3856). `constellation_study_overlay.gd` bypasses the puzzle object entirely and reads `chosen_form_clues` straight out of `ConstellationData.get_puzzle_cache()`.

### Pain points
- ~~`constellation_logic_puzzle.gd:942-1530` vs `403-941` — a generic solver parameterized on "alldiff or not" would remove roughly 500 lines of duplication between the Sequence and Pitch solvers.~~ **RESOLVED 2026-07-25** — turned out not to be live duplication to merge: the Pitch solver was confirmed dead code (zero callers in the Forms pipeline; Pitch needs no uniqueness proof, unlike Sequence) and deleted outright, ~500 lines, on branch `remove-dead-pitch-solver`. See the file-structure table above.
- Four separate small helpers for one concept: `_order_value`/`_order_word`/`_order_verb`/`_order_unit` (2141-2200) — fine individually, not discoverable as a group.
- `_seq_fact_for_label` (2201-2223) is load-bearing for not leaking ground truth, but its contract lives only in a 20-line prose comment rather than being structurally enforced — a future edit could silently reintroduce a leak here (this is the same failure class described in `constellation_puzzle_csp_review_findings`).
- Magic constants scattered with no single tunables block: `MAX_GENERATION_ATTEMPTS = 5`, `TIER_OPPORTUNISTIC_ATTEMPTS = 4`, `max_stall`, `FRAME_BUDGET_MSEC = 2`.
- 3620-3637 — a 17-line dead comment block documenting a removed subsystem (ZebraTutor tracker), no functional code.
- `constellation_logic_puzzle_v1_backup.gd.txt` (6249 lines, untracked) has zero references anywhere in tracked `.gd` files — inert, safe to delete once the rewrite is trusted, or keep as a diff reference; dev's call.

---

## 4. Constellation Presentation Layer

**Files:** `constellation_study_overlay.gd` (4041, **primary refactor target #1**), `constellation_overlay.gd` (606), `constellation_popout.gd` (737), `constellation_selector.gd` (335, likely superseded), `puzzle_synths.gd` (456, clean).

### Shape
`constellation_overlay.gd` projects stars to screen space and draws the constellation on the main game view; it also owns the **live in-game click-sequence puzzle** — the old Simon-says mechanic, which is still the actual on-screen solve interaction. `constellation_study_overlay.gd` is the modal "study" panel: it renders the zebra-grid clues, tracks player deductions (`_match_records`), and persists them via `ConstellationData`. `constellation_popout.gd` is the current (v2.0.0) left-edge constellation selector, instanced as `ConstellationPopout.tscn` inside the live `RootUI.tscn`. `constellation_selector.gd` was an older (v0.8.0) bottom-slide equivalent, structurally near-identical but simpler — **RESOLVED 2026-07-24**: it was only used by the abandoned `FirmamentUI.tscn` (see §2), confirmed dead, and deleted alongside it.

`constellation_study_overlay.gd` never calls into `constellation_logic_puzzle.gd` directly (only the static `note_name_for_freq` helper) — all puzzle data comes through `ConstellationData.get_puzzle_cache()`.

### `constellation_study_overlay.gd` — where the 4041 lines go
| Lines | Section | Note |
|---|---|---|
| 203-698 | "MELODY BAR SCORE" (mislabeled) | Also contains a ~190-line popup UI builder and `_process` — a grab-bag under one header |
| 1036-1272 | Fork puzzle (tuning-fork sequence mode) | **Full duplicate** of `constellation_overlay.gd`'s click-sequence system, `_fork_`-prefixed, own WAV synth |
| 1516-2059 | Floating star widgets | Largest labeled block (543 lines); full teardown+rebuild of every star's widget tree on any state change |
| **2251-3371** | "Record identity lookups" | **Largest section (~1120 lines)** — actually the deduction engine (`_merge_match_records`, elimination propagation, conflict dialogs) interleaved with UI row-builders; the label undersells what's here |
| 3372-3610 | Range callbacks | More deduction math mixed with commit handlers |
| 3729-4041 | *(no header)* | ~312 lines of sort-tab row builders, silently orphaned after the "CLOSE" section |

**Why it's bloated**: three largely independent subsystems share one file with no boundaries — (a) the puzzle deduction/state engine (~1400+ lines), (b) floating/popup widget construction rebuilt wholesale on every change (~800+ lines), and (c) a full duplicate of the legacy click-sequence minigame (~240 lines). This is the clearest, highest-value split candidate in the codebase: the deduction engine, the widget/UI layer, and the Fork-mode duplicate are three natural files.

### Pain points
- `constellation_study_overlay.gd:1036-1272` vs `constellation_overlay.gd:341-606` — near line-for-line duplicate click-sequence puzzles, including two independently-maintained WAV synth fallbacks, both redundant with `puzzle_synths.gd`'s FM synth which is the actual primary audio path.
- `constellation_study_overlay.gd:2975-2984,3843,3942` — `_debug_dump_named_records()` unconditionally prints hardcoded watch-names (`"Eosaara"/"Pyrios"`) on every color/degree row population.
- Scattered ungated `print("[DEBUG] ...")` calls: 1750, 2359, 2363, 2710, 3862.
- `:743` — comment admits `_name_assignments` is a "legacy positive-assignment slot," seemingly superseded by `_match_records` but still loaded.
- `:1273-1287` — section header "PICKER — NAME ASSIGNMENT" now contains only `_save_puzzle_notes`; stale header from a refactor that moved the actual picker UI elsewhere.
- `constellation_popout.gd:163-196` — one-shot debug dump of node rects fires on first frame (harmless, but scaffolding).
- `constellation_popout.gd:542-547` — custom-multiplier input (`CSTM`) is an explicit stub; button toggles visuals only, no LineEdit wired yet.
- `constellation_selector.gd:327-336` — dead commented-out `_force_show_for_test()`.

---

## 5. Cross-cutting

- **`resource_registry.gd`** (2 lines, `extends Node`, no members) and its matching `.tscn` are referenced nowhere in the codebase. It reads as scaffolding for a planned refactor (centralizing resource dictionaries out of `game_context.gd`) that was started but never continued. Worth a decision: finish it or delete it — an empty autoload-shaped stub sitting in the tree is exactly the kind of thing that causes confusion in six months.
- **The FirmamentUI/TESTFirmamentUI drift (§2) and the constellation_selector/constellation_popout duplication (§4) were the same underlying event** — **RESOLVED 2026-07-24**, both together: a "test" scene became the real one and the old "real" scene + its script were never fully retired. See §2's resolution note for what was deleted/renamed.
- **Duplication pattern across the whole codebase**: near-duplicate solver pairs (Sequence/Pitch CSP), near-duplicate UI panel pairs (`constellation_selector`/`constellation_popout`), near-duplicate puzzle-interaction code (Fork mode/`constellation_overlay`'s click-sequence), and 4x-duplicated recipe cost data all share the same shape — a system got copied to iterate safely, and the old copy was never deleted or reunified once the new one won. This is the single biggest structural theme across the whole audit, more than any individual file's size.

---

## Suggested refactor order (not yet executed — for discussion)

1. ~~Resolve the two open questions in §0 (constellation count, the two stale-recipe-data bugs)~~ **DONE** — see §0.
2. ~~Split `constellation_study_overlay.gd` into deduction-engine / widget-UI / (retire or isolate) Fork-mode-duplicate~~ **DONE 2026-07-24** — split into `constellation_fork_puzzle.gd` (335 lines), `constellation_puzzle_widgets.gd` (2339 lines), `constellation_puzzle_deduction.gd` (1505 lines); the orchestrator shell is down to 692 lines, matching this doc's original target range.
3. ~~Split or de-duplicate `constellation_logic_puzzle.gd`'s Sequence/Pitch solver clone~~ — **DONE 2026-07-25** (branch `remove-dead-pitch-solver`): the Pitch solver was confirmed dead code, not live duplication, and was deleted rather than merged. The Form-builder near-duplicates half of this item (`_build_form_exact_identity`/`_build_form_single_negation`, the "reuse chain node or scan pool" pattern in `_build_form_dual_negation`/`_build_form_mutual_exclusion`, etc. — see §3's Form-builder duplication note above) is still open and unstarted.
4. ~~Decide FirmamentUI vs TESTFirmamentUI and constellation_selector vs constellation_popout — delete or finish, not both living forever.~~ **DONE 2026-07-24** — see §2/§4 resolution notes.
5. `root_ui.gd`'s `_check_*_trigger` sprawl and Archon poke-minigame extraction — lower urgency, same "god object" pattern.
6. `resource_registry.gd` — finish or delete.
