# Early-Game Architecture Overview

**Written:** 2026-07-22, ahead of the first refactor pass since the Mote-based Expansion change and the Simon-says → zebra-grid puzzle rewrite. **Refreshed:** 2026-07-25, after that first refactor pass landed (the two outgrown files were split/de-duplicated, four branches merged — see the "Done" items below) and a fresh full re-read of every file in scope.
**Scope:** everything from Sparks through Expansion/prestige, plus the full Constellation puzzle system.
**Purpose:** orientation for a returning developer navigating this codebase's ongoing refactor. This is a living survey, not a changelog or a one-time audit — treat file:line references as approximate anchors, not exact contracts, and expect this doc to be refreshed again as more of the "Suggested refactor order" list gets executed.

**Read this together with existing memory** (`constellation_puzzle_*` entries) for how the Forms/Kinds/Clues generator behaves at a mechanical level — this doc covers structure and pain points, memory covers correctness properties already verified in-engine.

---

## 0. Two things to resolve before anything else

These surfaced during the audit and aren't refactor concerns — they're open questions or live bugs.

1. ~~**Only 5 constellations are defined, not 6.**~~ **RESOLVED** — `constellation_data.gd` now defines ids 0-5 (6 constellations, The Djinn added).
2. ~~**Two live economy-tracking bugs from the Grain→Mote Uonite migration**~~ **RESOLVED** — `game_data.gd` `RECIPES["uonite_assemble"]` and `production_manager.gd`'s `get_consumption_network()` both fixed to route through Mote.

---

## 1. Production / Economy Chain

**Files:** `production_manager.gd` (1390), `game_data.gd` (171), `big_num.gd` (344). `resource_registry.gd`/`.uid`/`.tscn` — **deleted 2026-07-25** (see §5), was a 1-line dead stub.

### Shape
`sparks → monad → tetrad → particle → iota → mote → grain`, driven by per-op timers and worker counts, ticked in `production_manager.gd:_process` (193-248). `monad_compress`/`tetrad_assemble` are bespoke (random S/L/G subtype rolls, 433-478); `particle_compress`/`iota_assemble`/`mote_compress`/`grain_assemble` share a generic path (`_produce_generic`, 484-517) driven by `game_data.RECIPES` for inputs/output and a `GENERIC_OPS_LOCK_KEYS` const (59-71) for lock-gating only.

**New since the last pass:** a `_recipe_cost(op, resource_key)` helper (101-102) reads costs off `game_data.RECIPES`, and `game_context.gd` gained generic `get_resource(key)`/`set_resource(key, value)` accessors (465-518, see §2) — together these closed two of the four recipe-cost duplication sites (see Pain points).

Uonite creation is still Mote-gated (`manual_create_uonite`, 1045-1070: 20 Mote + 1 Spark, capped by `game_context.gd:get_uonite_cycle_cap()`, a Fibonacci-by-expansions value, 578-585). `do_prestige_reset` and `expand_storage_cap()` unchanged from the prior pass.

### Key API
Signal: `manifold_ticked`. Entry points: `manual_summon_spark/monad_compress/tetrad_assemble/particle_compress/iota_assemble/mote_compress/grain_assemble/create_uonite`, `_recipe_cost()`, `reset_for_prestige()`, `apply_offline_progress()`, `get_consumption_network()`, `get_smoothed_rate()`. `game_context.gd` exposes `get_resource()`/`set_resource()`, `do_prestige_reset()`, `get_uonite_cycle_cap()`, `expand_storage_cap()`.

### Pain points
- ~~**Recipe costs duplicated 4x**~~ **RESOLVED 2026-07-25** (`ab45892`, `abf57e1`, and this pass): `_op_has_inputs` (575-586) and `get_consumption_network` (1290-1306) derive from `game_data.RECIPES` via `OP_LOCK_KEYS` (88-95); the single-unit manual-click functions go through `_recipe_cost()`; and `_produce_generic` (484-517, the per-tick production path for particle/iota/mote/grain) now reads inputs/output key straight off `game_data.RECIPES` too, keeping only the genuinely non-RECIPES data (`GENERIC_OPS_LOCK_KEYS`, 59-71) as its own const. All four sites now point at one source of truth for cost data; `GENERIC_OPS_LOCK_KEYS` and `OP_LOCK_KEYS` deliberately remain two separate tables (different call sites, intentionally different values for `iota_assemble`/`grain_assemble` — see the comment above `OP_LOCK_KEYS`).
- ~~**Batch vs. single-unit duplication (hardcoded literals)**~~ **LITERAL-DRIFT HALF RESOLVED** (`abf57e1`): the single-unit functions no longer hand-type costs. **Structural half still open**: `_produce_generic`/`_batch_roll_monads`/`_batch_assemble_tetrads` (batch path, 605-809) and `_try_assemble_tetrad`/`_try_assemble_iota`/`_try_assemble_grain`/`manual_*` (single-unit path, 915-1145) remain two independent reimplementations of the same draw/spend logic rather than one path with a quantity parameter — worth tracking as its own item now that the literal-drift complaint is gone.
- **`_process` (193-248) is still a junk drawer**: tick accumulation, storage overflow routing, Manifold transforms, and Constellation spark accumulation all live in one method.
- **`_batch_roll_monads`/`_batch_assemble_tetrads`/`_batch_distribute_tetrads`** (605-809) is still a dense probability-distribution block, worth a closer read before anyone touches subtype odds.
- Leftover debug `print()` in production paths: 296 (`=== OVERFLOW TICK START ===`), 1058 (`[UONITE-TEST]`).
- ~~`manual_create_uonite`'s "grains-out-experiment" comment~~ **RESOLVED** — gone, removed incidentally when the function was rewritten onto `_recipe_cost()`.
- Magic numbers with no single tunables block: `RANDOM_DRAW_THRESHOLD = 1000` (29), Manifold purity thresholds `0.60`/`0.35` (380-389), `EMA_ALPHA = 0.10` (366), Fibonacci Uonite-cap seed (`game_context.gd:578-585`).
- `game_data.gd`/`big_num.gd` themselves remain clean — no notes.

---

## 2. Root UI / Orchestration Layer

**Files:** `root_ui.gd` (2646), `game_context.gd` (1474), `archon_dialogue_manager.gd` (1118), `archon_tetrahedron.gd` (461), `firmament_ui.gd` (117).

### Shape
`game_context.gd` (`/root/GameContext`) is meant to be a pure-state singleton (resources, Volition-slot assignment model at 658-970, purity locks, save/load) but has drifted to include real logic: `expand_storage_cap`, `accumulate_constellation_sparks`, `do_prestige_reset`, `toggle_lock`/`toggle_category_lock`. The in-file changelog claiming "v1.0.0: production logic removed" is no longer accurate. **New since the last pass:** `get_resource(key)`/`set_resource(key, value)` (465-518) — a generic string-keyed accessor added on branch `dedupe-manual-recipe-costs` to let `production_manager.gd:584`'s `_op_has_inputs` read recipe costs off `GameData.RECIPES` instead of a hardcoded literal, closing one of the four duplicated recipe-cost sites flagged in §1. It's orthogonal to the "drifted into logic" complaint rather than a fix for it — `get_resource("monad")`/`"tetrad"` still delegate to `get_monad_unlocked_total()`/`get_tetrad_unlocked_total()`, which embed lock-filtering logic of their own. More notably, it hasn't been adopted anywhere except that one call site and game_context's own save/load loops (1149, 1312, 1320): `root_ui.gd`'s counters, bars, and tooltips still read `game_context.particle`/`.iota`/`.mote`/`.grain`/`.sparks` directly (28 raw-field accesses), so the codebase now has **three** coexisting ways to touch a resource — raw field access, the older per-resource total helpers, and this new generic accessor — with no consolidation yet.

`root_ui.gd` is the top-level scene controller for the Primordial age and has become a god object: button wiring, resource-bar rendering, dialogue-panel wiring, tutorial FX, the Expansion shader animation, Archon "poke"/lockdown minigame logic (embedded directly in `_on_archon_panel_gui_input`, 387-461), name-picker UI, constellation puzzle generation/caching (884-965 — `root_ui.gd` instantiates `ConstellationLogicPuzzle` directly, puzzle setup isn't delegated to a manager), achievement granting, and 22 narrative trigger predicates (`_check_*`, defined 728-2219), 19 of which are polled unconditionally every `_process` tick (2183-2208).

`archon_dialogue_manager.gd` is comparatively clean: one `enqueue_*` function per narrative beat (20+), each with its own `*_done` save flag, fully wired end-to-end (signals connect, `sequence_complete` fires, save/load round-trips). It touches `GameContext` exactly once (line 442). The bulk of the file (530-1118) is narrative string literals interleaved with control flow — every new story beat means editing this one file rather than authoring data.

`archon_tetrahedron.gd` is unchanged and still self-contained (procedural mesh, expression/tween system) with no game-state coupling — clean by comparison.

### A live scene/script drift bug — RESOLVED 2026-07-24
`root_ui.gd:1010` transitioned players to `TESTFirmamentUI.tscn` (test-prefixed name, shipping as the real transition target). Meanwhile `FirmamentUI.tscn` — the scene that reads as "the real one" by name — had drifted to load `root_ui.gd` as its script instead of `firmament_ui.gd`. Confirmed via node-tree comparison that the two scenes weren't near-duplicates: `FirmamentUI.tscn` (root_ui.gd) was a far more complete build (full constellation panel, every production button with cooldown bars, Uonite creation viewport) than `TESTFirmamentUI.tscn` (firmament_ui.gd, resource bars + Archon + dialogue only, no constellation/production UI) — raising a real question of whether content needed to migrate rather than just picking a name. Confirmed with the dev: `TESTFirmamentUI.tscn`'s sparseness is intentional (Firmament-age production/constellation gameplay isn't built yet by design); `FirmamentUI.tscn` was a genuinely abandoned earlier prototype. Resolution: deleted the old `FirmamentUI.tscn`, renamed `TESTFirmamentUI.tscn` → `FirmamentUI.tscn`, updated `root_ui.gd:1010`'s transition target to match. `constellation_selector.gd` (only used by the deleted scene) and `RootUI_v2.tscn` (confirmed unused, referenced nowhere in code) were removed in the same pass — see §4/§5 below, also updated. Re-confirmed this pass: a project-wide grep for `TESTFirmamentUI`, `constellation_selector`, and `RootUI_v2` turns up zero references in any tracked `.gd` file — only this doc still mentions the old names.

### Pain points
- `root_ui.gd:884-965` — `_start_puzzle_generation`/`_dev_recompute_puzzle` still duplicate ~35 lines of puzzle setup nearly verbatim.
- `root_ui.gd:728-2219` (definitions) / `2183-2208` (call site) — 22 hand-rolled `_check_*` trigger/milestone functions with near-identical guard-clause shape, 19 called unconditionally from `_process` every frame; a data-driven trigger table would collapse this into one loop plus a data file. Refactor-order item #5, still not started.
- `root_ui.gd:1509-1594` — dev/cheat hotkeys live permanently in `_input()` next to production code, including commented-out dead key handlers (1511-1517).
- `root_ui.gd:387-461` — Archon poke/lockdown minigame (durations, thresholds, achievement grants) still belongs in its own component, not a click handler. Also refactor-order item #5.
- `game_context.gd:850-867` and `:1283-1294` — the category↔key mapping is still encoded three separate times (`_volition_assignment_key`, `_bonus_volition_assignment_key`, `_key_to_category_target`); the new `get_resource`/`set_resource` accessors (above) don't touch this mapping at all.
- In-fiction terms used as literal identifiers with no gloss at point of use (`"stoctagon"`, `AUTO_FOLLOW_CATEGORIES`, "Volumitions") — a returning dev has to cross-reference dialogue text to know what these mean in plain terms.
- `root_ui.gd:85-86` — `_first_prestige_triggered` is still flagged `@warning_ignore("unused_private_class_variable")` rather than removed.
- Several `_on_*_complete` dialogue handlers are still empty `pass` stubs with no UI consequence (810-811, 814-815, 828-829, 832-833, 836-837) — dead-end sequences, likely fine but worth a pass to confirm nothing was meant to happen there.
- `archon_dialogue_manager.gd:913-949` — third/fourth/fifth prestige dialogues are still one-line placeholders ("Hourglass placeholder dialogue," etc.) — known unfinished content, not a bug.
- `archon_dialogue_manager.gd:978-992` — `enqueue_close_constellation_panel` is still commented out, and its `*_done` flag (76), signal (139), and handler (351-353) are all still live with zero callers/connections anywhere in `root_ui.gd`. One new wrinkle found this pass: the save/load pair is no longer symmetric — `get_save_data()` still writes `close_constellation_panel_done` (1071), but the matching read in `load_save_data()` is itself commented out (1110), so the flag is write-only and always resets to `false` on load. Still a half-removed feature that should come back or be fully deleted.
- **New this pass:** `root_ui.gd`'s `_transition_to_age` (1117-1122), `_reveal_panel` (529-544), and `_hide_all_panels` (500-505) are duplicated near-verbatim in `firmament_ui.gd` (112-117, 88-99, 80-85) — same tween-based age transition, same panel-reveal tween, same hide loop, copy-pasted across the two age-controller scripts instead of shared (e.g. via a common base class or helper autoload).
- ~~`resource_registry.gd` is still the same 1-line dead stub~~ **DELETED 2026-07-25** (see §5) — the `get_resource`/`set_resource` logic went straight into `game_context.gd` instead, so nothing was ever going to migrate into this file.

---

## 3. Constellation Data & Puzzle Core

**Files:** `constellation_data.gd` (1340), `constellation_logic_puzzle.gd` (3398, **primary refactor target #2**), `constellation_star_namer.gd` (68), `puzzle_sequence_resource.gd` (69).

### `constellation_data.gd`
Owns constellation definitions (`BUILT_IN`, see §0), octant geometry, unlock/mechanic-unlock logic, seeded star positions, patron-JSON loading, and save/load including puzzle-cache passthrough. No constellation currently sets the optional `name_theme` field, so `ConstellationStarNamer.DEFAULT_THEME` is the only theme ever exercised in practice — a built feature that's never actually used.

**Not audited this deeply in the original pass** — a fresh full read turned up several more instances of the same "field/function stays live in code/docs after the thing it served moved on" pattern already called out elsewhere in this doc:
- The header changelog (18-20) still credits itself with a `PUZZLE_SPARK_FRACTIONS` constant and a `grant_puzzle_sparks()` function as v0.2.0/v0.3.0 additions — project-wide grep confirms **neither exists anywhere in the file today**. They were apparently removed at some point without the changelog being updated — the same stale-changelog failure class already flagged for `game_context.gd`'s "v1.0.0: production logic removed" claim in §2.
- `PUZZLE_CALL_SEQUENCE` (631) is a dead global constant: it duplicates The Hourglass's own `"puzzle_sequence"` array (296) verbatim, left behind once that data moved into the per-constellation dict. `PUZZLE_NOTE_FREQS`/`PUZZLE_RESPONSE_FREQS` (619-654) are still technically live as the fallback default inside `get_note_freqs()`/`get_response_freqs()` (1116, 1121) — but all six current built-ins define their own `note_freqs`/`response_freqs`, so that fallback path is unreachable today; it would only fire for a future/patron constellation that omits the field.
- `"endowment_multiplier"`, The Djinn's (id 5) bonus key (550), is confirmed read by nothing outside this file (zero hits in `production_manager.gd` or anywhere else) — The Djinn's entire bonus mechanic is inert, exactly as its own header TODO (6-7) already admits.
- The Djinn also has no `fixed_star_positions`/`line_pairs` entry at all (per its TODO block, 536-537), so `get_star_positions()` falls through to the procedural-scatter branch for it — it's the only built-in currently rendering with randomly scattered stars instead of a designed shape.
- `star_brightness_scales` (read via `def.get(...)` at 1176) is a second optional per-star field, alongside `name_theme`, that no `BUILT_IN` entry ever sets.
- `_check_stat_unlocks()` (894-918) has a double-negative existence check at line 909 — `if not _game_context.get(field) != null: continue` — which means "skip if the field doesn't exist" but reads backwards; correct today, a trap for the next edit.

### `constellation_logic_puzzle.gd` — where the 3398 lines go
The line-number table below is freshly re-verified against the current 3398-line file (the previous pass's numbers were flagged as approximate/historical and have shifted).

| Lines | Section |
|---|---|
| 1-95 | Header docstring — **still stale**, describes the Forms as "not yet built" and the Name-axis solver as "deliberately not ported, pending work" (both true only for Name-axis; Forms are 21/22 live). One specific stale claim (the Pitch solver's strings "will be re-keyed to Form names") was fixed when the Pitch solver was deleted, but a duplicate of that same stale claim survives elsewhere — see Pain points. |
| 98-411 | Ground-truth generation (colors, degrees, distances, name shuffle, pitch rank) |
| 413-1040 | Sequence-axis CSP solver (possibility grid, arc-consistency, backtracking) — **live**, the Phase C uniqueness gate; untouched. |
| 1041-1201 | Generic helpers (alphabetical rank, shuffles), the public generation entry point (`generate_clues_async`, `is_generation_complete`), validation helper (`check_solution`), cache (de)serialization, and the dead-stub comment for the never-ported Name-axis solver |
| 1202-1451 | Record array (Category bijections + Distance relation), clue-text rendering (`_characteristic_label`), used/unused characteristic tracking |
| 1452-1861 | The True/False/Used matrix and its sampling primitives, orderable-axis helpers, solver-fact extraction |
| **1863-3156** | **Forms registry + the 22 (21 live) Form builders — ~38% of the file, the dominant mass** |
| 3158-3175 | Dead comment block documenting a removed subsystem (ZebraTutor tracker), no functional code |
| 3177-3228 | Form-tier classification + scheduling weights |
| 3229-3398 | Generation pipeline: `generate_clues_forms`, retry/orchestration loop, `get_form_clue_texts` |

**Duplication inside the Form builders is real, not just size**: `_build_form_exact_identity` (1915) and `_build_form_single_negation` (1935) differ by one boolean check and a connective word. The "reuse chain node if valid, else scan a shuffled star pool" fallback pattern is hand-rolled separately in at least `_build_form_dual_negation` (2301-2351) and `_build_form_mutual_exclusion` (2406-2465) rather than factored into one shared helper. Text rendering, matrix sampling, and `solver_facts` construction all live inside each `_build_form_*` rather than being split into a rendering pass — apparently deliberate (per the header's original intent) but means each Form function does three jobs. Still unresolved — this is the still-open half of refactor-order item #3.

**A real correctness gap, not just a doc note:** Name-axis uniqueness has no constraint-propagation proof the way Sequence does via `_solve()` — it's currently verified only by a heuristic co-occurrence check (`name_revealed`, declared 3281, updated 3351, checked 3382). The old file's Name solver (~560 lines) was dropped during the rewrite and never replaced. This matches the standing gap already tracked in memory (`constellation_puzzle_csp_review_findings`, `constellation_puzzle_multivariate_clue_requirement`) — this doc doesn't change that assessment, just confirms it's still true in the current file.

**Dead public API** (declared, zero external callers, re-confirmed via project-wide grep): `is_generation_complete()` (1086), `check_solution()` (1100), `get_form_clue_texts()` (3394). `constellation_study_overlay.gd` bypasses the puzzle object entirely and reads `chosen_form_clues` straight out of `ConstellationData.get_puzzle_cache()`.

~~**Residue from the Pitch-solver deletion**~~ **CLEANED UP 2026-07-25** (branch `cleanup-dead-stub-and-pitch-residue`): the comment above the Sequence-axis solver had a second copy of the stale "pitch-axis `tone_*` equivalents further down" claim (missed because it wasn't in the header itself) — rewritten to state Pitch has no solver equivalent. The two leftover state variables (`_final_pitch_clues`, `_final_identity_clues`, declared and reset every `setup()` call but never populated or read) were removed.

### `puzzle_sequence_resource.gd` — correction: this is live, not disconnected
The previous pass flagged this as "appears disconnected... no references found in any audited file." That was wrong, or the pipeline changed since — a project-wide grep now finds real, active use: `constellation_overlay.gd` (466, 502) and its Fork-mode duplicate `constellation_fork_puzzle.gd` (233, 268) both `load(path) as PuzzleSequenceResource` and hand the result to `puzzle_synths.gd`'s `play_sequence()` (171) to drive the solve-fanfare → completion-reward audio sequence after the live click-sequence puzzle is solved. Actual `.tres` resources exist under `sequences/`, but **only for constellations 0 and 1** (`constellation_0_solve.tres`, `constellation_0_reward.tres`, `constellation_1_solve.tres`, `constellation_1_reward.tres`) — constellations 2-5 have no corresponding files, so their `load()` calls return null and both call sites silently fall back to an immediate reset with no fanfare (`constellation_overlay.gd:469-471, 505-506`). Worth flagging to the dev: this isn't a bug, but it means 4 of 6 constellations currently skip the reward audio entirely, silently.

### Pain points
- `constellation_logic_puzzle.gd:1915` vs `1935`, and `2301` vs `2406` — Form-builder duplication described above; the still-open half of refactor-order item #3 (the Pitch-solver half of that item is done).
- Four separate small helpers for one concept: `_order_value`/`_order_word`/`_order_verb`/`_order_unit` (1668, 1680, 1689, 1696) — fine individually, not discoverable as a group.
- `_seq_fact_for_label` (1754) is load-bearing for not leaking ground truth, but its contract lives only in a prose comment (1723-1745) rather than being structurally enforced — a future edit could silently reintroduce a leak here (same failure class described in `constellation_puzzle_csp_review_findings`).
- Magic constants scattered with no single tunables block: `MAX_GENERATION_ATTEMPTS = 5` (3235), `TIER_OPPORTUNISTIC_ATTEMPTS = 4` (3201), `max_stall` (3290), `FRAME_BUDGET_MSEC = 2` (106) — and `FRAME_BUDGET_MSEC` specifically is worse than just unmoored: confirmed via grep it is **never read anywhere**, only declared; a leftover from when generation was expected to be frame-chunked, before `generate_clues_forms()` became synchronous (see the header note at 1077-1080).
- 3158-3175 — an 18-line dead comment block documenting a removed subsystem (ZebraTutor tracker), no functional code.
- `constellation_logic_puzzle_v1_backup.gd.txt` (6249 lines, untracked) still present, still zero references anywhere in tracked `.gd` files — inert, safe to delete once the rewrite is trusted, or keep as a diff reference; dev's call.

---

## 4. Constellation Presentation Layer

**Files:** `constellation_study_overlay.gd` (692), `constellation_puzzle_widgets.gd` (2339), `constellation_puzzle_deduction.gd` (1505), `constellation_fork_puzzle.gd` (335), `constellation_overlay.gd` (606), `constellation_popout.gd` (737), `puzzle_synths.gd` (456, clean).

**Split completed 2026-07-24** (refactor-order item #2 in §0/end-of-doc): the old 4041-line `constellation_study_overlay.gd` monolith this section used to describe no longer exists in that form. It's now an orchestrator shell plus three extracted files. `constellation_selector.gd` (previously listed here as "likely superseded") is confirmed deleted — see §2/§5.

### Shape
`constellation_overlay.gd` still projects stars to screen space and draws the constellation on the main game view, and still owns the **live in-game click-sequence puzzle** — the old Simon-says mechanic, unchanged by this pass. `constellation_popout.gd` is still the current (v2.0.0) left-edge constellation selector. Neither file was touched by the split; both are described below only for their pain points.

The Study Overlay itself is now four cooperating pieces:
- **`constellation_study_overlay.gd`** (692) — orchestrator shell. Owns node refs, ground-truth arrays (`_star_names`/`_star_colors`/`_star_degrees`/`_star_screen_pos`), style boxes, star-map draw/input, header, pitch-listen mode, and `_fork` (instantiates and dispatches to `ConstellationForkPuzzle`, but doesn't touch match records).
- **`constellation_puzzle_widgets.gd`** (2339) — all widget construction.
- **`constellation_puzzle_deduction.gd`** (1505) — the deduction engine: `_match_records` and everything that reads/mutates it.
- **`constellation_fork_puzzle.gd`** (335) — the Fork-mode tuning-fork sequence minigame, mechanically extracted.

**Wiring** (`constellation_study_overlay.gd:151-219`, `_ready()`): the three pieces are *not* symmetrically coupled.
```
_widgets = ConstellationPuzzleWidgets.new()
_deduction = ConstellationPuzzleDeduction.new()
_deduction.setup(self, Callable(_widgets, "_show_conflict_choice"))   # host + a Callable, NOT a widgets ref
_widgets.setup(self, _deduction)                                      # host AND a direct deduction ref
_fork = ConstellationForkPuzzle.new()
_fork.setup(_synth, _star_map_control, _fork_btn, self)                # raw nodes only — no widgets/deduction coupling
```
`constellation_puzzle_deduction.gd`'s header comment explains the asymmetry deliberately: deduction reads data off `_host` and is meant to reach the screen *only* through the injected `_conflict_dialog_fn` Callable, never by holding a widgets reference — so a UI change there can't ripple into deduction's contract. `constellation_puzzle_widgets.gd`'s header explains the opposite choice for itself: it's handed `_deduction` directly (not just `_host`) because widget construction calls into it "constantly." `constellation_fork_puzzle.gd` is a fourth, wholly separate lobe — no reference to either widgets or deduction, self-contained state.

**However** (new finding — the one-way contract isn't quite honored): `constellation_puzzle_deduction.gd:1192` (`_effective_pitch_state`) and `:1280` (`_records_provably_distinct`) both call `_host._widgets._note_name_for_star(...)` / `_host._widgets._distinct_note_names()` directly — two pure data lookups (pitch-index → frequency → note name) with no UI content at all. This isn't the sanctioned "put something on screen" exception the header describes (that's `_conflict_dialog_fn` only); it's the deduction engine reaching back into the widget file for math that arguably belongs in deduction itself, or on the host. A residual seam from splitting by "was this code inside a Control-heavy block" rather than by actual dependency — `_host._widgets` being reachable at all (since `_host` exposes a `_widgets` field) makes this an easy, silent violation to introduce with no compile-time signal.

Static-helper usage is now spread across files instead of centralized: both `constellation_puzzle_widgets.gd` and `constellation_puzzle_deduction.gd` call `ConstellationLogicPuzzle.note_name_for_freq(...)` directly at multiple call sites each — still the only coupling to `constellation_logic_puzzle.gd`, same as the old monolith, just duplicated across two files' call sites instead of one.

### `constellation_puzzle_widgets.gd` (2339) — widget/UI construction
Per its own header, built in four "slices": (1) markers panel (`_populate_*` per tab — color/sequence/pitch/proximity/name-clues, plus the Sort: sub-tabs), (2) Sort:tab record widgets (name/pitch checklist trigger buttons + popups, color/degree toggle rows, sequence range rows) and the conflict-choice dialog (`_show_conflict_choice`, called through `_deduction._conflict_dialog_fn`), (3) melody staff drawing + the Staff popup's per-axis check/X/protect/undo handlers, (4) floating star widgets (`_build_star_widgets_impl`, roughly lines 1600-2340 — the single largest block: full teardown+rebuild of every star's widget tree, including its per-star name checklist, on any state change) plus star tags (the compact "Name / Nth note / Pitch" labels drawn next to each star).

### `constellation_puzzle_deduction.gd` (1505) — deduction engine
Owns `_match_records` (documented in a struct-shaped comment at the top of the file) and everything that touches it: per-axis get-or-create lookups (by name, exact sequence slot, color/pitch/degree "slot label," or `star_idx`), effective-state queries (`_effective_color_state`/`_effective_pitch_state`/`_effective_name_state`/`_effective_degree_state`, each folding in ground truth → slot label → raw toggle → protect-derived soft-state in that tier order — a pattern repeated four times with only the field names changed), sibling-clearing propagation per axis, the two hairiest functions in the whole layer (`_merge_match_records` and `_confirm_match_record_identity`, handling N-way dict merges with a per-axis conflict dialog each), save/load (`_save_match_records`/`_load_match_records`), `_records_provably_distinct` (feeds sequence-candidate exclusion), and `_debug_dump_named_records`.

### `constellation_fork_puzzle.gd` (335) — Fork-mode minigame, mechanically extracted
Its own header is explicit about scope: "a mechanical move, not a rewrite," keeping every internal member's original `_fork_` prefix "to minimize the chance of a rename slipping past review." It also self-documents the unresolved duplication: *"a near-total copy of constellation_overlay.gd's live click-sequence puzzle, including a second independent WAV-synth fallback... flagged... as a future de-duplication candidate, not attempted here."*

### Pain points — re-verified against the new 4-file structure

- **Fork/overlay duplication survived the split; it was only relocated.** `constellation_fork_puzzle.gd` (the whole 335-line file) vs. `constellation_overlay.gd:341-607` (state machine + audio: `_check_puzzle_availability`, `_build_correct_star_sequence`, `_on_star_clicked`, `_on_puzzle_complete`, `_finish_puzzle_sequences`, etc.) are still near line-for-line duplicate click-sequence puzzles, function-for-function, differing mainly by the `_fork_` prefix. Two independently-maintained WAV-synth fallbacks remain: `_make_fork_tone_wav` (`constellation_fork_puzzle.gd:314-335`) and `_make_tone_wav` (`constellation_overlay.gd:552-573`) are near byte-identical, and both are still redundant with `puzzle_synths.gd`'s FM synth (the actual primary path whenever `_synth` resolves — the WAV path is a fallback for if it doesn't). This pairing was already two separate files before this pass (`constellation_study_overlay.gd` vs. `constellation_overlay.gd`); the split changed *which* file holds the Fork half, not whether the duplication exists.
- **`_debug_dump_named_records()` — now cross-file, still unconditional.** Definition moved to `constellation_puzzle_deduction.gd:1013-1021`, still hardcodes watch-names `"Eosaara"`/`"Pyrios"` and prints unconditionally. Called from `constellation_puzzle_widgets.gd:1053` (`_populate_color_group_rows`) and `:1124` (`_populate_degree_group_rows`) — i.e. every time the player opens or refreshes the Sort:Color or Sort:Degree tab.
- **Scattered ungated `print(...)` calls, now split across two files.** `constellation_puzzle_widgets.gd:281` (`[CONFLICT]`, in `_show_conflict_choice`), `:1070-1073` (`[DEBUG]` pitch row, fires on every Sort:Pitch row build), `:1848-1849` (`[DEBUG]` `btn_check` `gui_input`, fires on every press/release of every per-star name-checklist button — the noisiest of the set). `constellation_puzzle_deduction.gd:264,268` (inside `_possible_names_for_record`), plus the two inside `_debug_dump_named_records` above. **New finding:** the orchestrator shell itself, `constellation_study_overlay.gd`, has zero `print()` calls left — it came out of the split clean on this front; all the debug noise is now in the two extracted files.
- **`_name_assignments` — same "legacy" comment, now confirmed fully dead rather than just superseded.** Still declared at `constellation_study_overlay.gd:98`, still loaded from the `player_name_assignments` cache at `:316-320` with the identical "legacy positive-assignment slot" comment. New this pass: a project-wide grep for `_name_assignments` finds no reads anywhere across the four files — it's populated on every `show_for_constellation()` call and never consulted again. Not merely superseded by `_match_records` as the old comment hedges; it's write-only dead state.
- **Stale "PICKER — NAME ASSIGNMENT" header — gone, not just stale.** The literal header string no longer appears anywhere in the four files. `_save_puzzle_notes` (now `constellation_puzzle_deduction.gd:133-141`) sits between the "MELODY BAR SCORE" comment block and the "DEDUCTION ENGINE CORE" header with no section header of its own — the same orphaned-function shape as before, just without the misleading old label attached to it.
- **New: a within-`constellation_puzzle_widgets.gd` duplication the split didn't touch.** `_on_record_range_committed`/`_on_record_middle_committed` (`:711-790`, the Sort:tab record-row version) and `_on_widget_range_committed`/`_on_widget_middle_committed` (`:829-904`, the floating star-widget version) are near line-for-line duplicates of the same sequence-range-commit logic, differing only in how `record_idx` is obtained (passed in vs. resolved via `_get_or_create_match_record_for_star_idx`). Both correctly stayed together in one file across the split (both are UI), but the duplication itself — a same-file analog of the Form-builder duplication already flagged in §3 — is unaddressed, and the file's own section header at `:825-828` explicitly acknowledges it ("floating star-widget versions — see the Sort:tab versions above for the record-row equivalents") without resolving it.
- **TEMP debug styling left in shipped UI.** `constellation_puzzle_widgets.gd:2155-2159` (`_apply_name_row_visual`, state 4/"protected") renders in flat magenta with the comment `# protected — TEMP debug: impossible to miss` — self-admitted placeholder styling still live for the per-star name checklist's "still possible" state.
- `constellation_popout.gd:163-196` — one-shot debug dump of node rects still fires on first frame; unchanged, same line numbers as before the split (this file wasn't touched).
- `constellation_popout.gd:542-547` — the `CSTM` custom-multiplier input is still an explicit stub; button toggles visuals only, comment still says "not yet added."

---

## 5. Cross-cutting

- ~~**`resource_registry.gd`**~~ **DELETED 2026-07-25** (`.gd`, `.gd.uid`, `.tscn`, branch `cleanup-dead-stub-and-pitch-residue`) — confirmed zero references anywhere (not an autoload, not in `project.godot`, not `load()`ed from any script) before deletion. The `get_resource`/`set_resource` generic accessor added to `game_context.gd` this refactor round (§1/§2) — functionally the exact thing this stub read as scaffolding for — was built directly into `game_context.gd` instead, which is what settled the "finish it" side of the old either/or in favor of deleting.
- **A new three-way inconsistency in how resources get touched (§1/§2)**: raw field access (`game_context.particle` etc., still 28 call sites in `root_ui.gd`), older per-resource helpers (`get_monad_unlocked_total()` etc.), and the new generic `get_resource`/`set_resource` accessor now coexist with no consolidation — the accessor was added to serve one call site (`_op_has_inputs`) and a save/load loop, not adopted as the one way to read a resource.
- **The FirmamentUI/TESTFirmamentUI drift (§2) and the constellation_selector/constellation_popout duplication (§4) were the same underlying event** — **RESOLVED 2026-07-24**, both together: a "test" scene became the real one and the old "real" scene + its script were never fully retired. See §2's resolution note for what was deleted/renamed.
- **The recurring theme has sharpened from "duplication exists" to "splitting relocates duplication, it doesn't eliminate it."** This pass's Study Overlay split (§4) is the clearest case: extracting `constellation_fork_puzzle.gd` didn't resolve its duplication against `constellation_overlay.gd`'s click-sequence system, it just moved which file holds the Fork half — the two WAV-synth fallbacks are still near-byte-identical. The same shape shows up independently within a single file (`constellation_puzzle_widgets.gd`'s Sort:tab vs. star-widget range-commit handlers, §4). One instance of the pattern is now fully closed rather than partially: `GENERIC_OPS` vs. `game_data.RECIPES` (§1) is resolved — `_produce_generic` now reads `RECIPES` directly. Still-open, not-yet-attempted instances of the same pattern: the Form-builder near-duplicates (§3) and root_ui.gd/firmament_ui.gd's duplicated age-transition helpers (§2, new finding). This is the single biggest structural theme across the whole audit, more than any individual file's size — and the lesson from this round is that a "split" refactor needs a duplication check as its own explicit step, not an assumed side effect.

---

## Suggested refactor order (updated 2026-07-25 — for discussion)

**Done:**
1. ~~Resolve the two open questions in §0 (constellation count, the two stale-recipe-data bugs)~~ **DONE** — see §0.
2. ~~Split `constellation_study_overlay.gd` into deduction-engine / widget-UI / (retire or isolate) Fork-mode-duplicate~~ **DONE 2026-07-24** — split into `constellation_fork_puzzle.gd` (335 lines), `constellation_puzzle_widgets.gd` (2339 lines), `constellation_puzzle_deduction.gd` (1505 lines); the orchestrator shell is down to 692 lines. Note (§4): the split relocated the Fork/overlay duplication, it didn't resolve it — see item 9 below.
3. ~~Split or de-duplicate `constellation_logic_puzzle.gd`'s Sequence/Pitch solver clone~~ **DONE 2026-07-25** (branch `remove-dead-pitch-solver`): the Pitch solver was confirmed dead code, not live duplication, and was deleted rather than merged. Left two small leftovers — see item 7.
4. ~~Decide FirmamentUI vs TESTFirmamentUI and constellation_selector vs constellation_popout — delete or finish, not both living forever.~~ **DONE 2026-07-24** — see §2/§4 resolution notes.
5. ~~Recipe costs duplicated 4x~~ **DONE 2026-07-25** (branches `resource-registry-accessor`, `dedupe-manual-recipe-costs`, `dedupe-generic-ops-recipes`): `_op_has_inputs`, `get_consumption_network`, the manual single-unit functions, and now `_produce_generic` all derive from `game_data.RECIPES`. All four originally-duplicated sites resolved.
6. ~~Delete `resource_registry.gd`~~ **DONE 2026-07-25** (branch `cleanup-dead-stub-and-pitch-residue`) — deleted `.gd`/`.gd.uid`/`.tscn` after confirming zero references anywhere.
7. ~~Small cleanup from the Pitch-solver deletion~~ **DONE 2026-07-25** (same branch) — stale `tone_*`-solver comment rewritten, two dead state vars (`_final_pitch_clues`, `_final_identity_clues`) removed. See §3.
8. ~~`GENERIC_OPS` vs. `game_data.RECIPES`~~ **DONE 2026-07-25** (branch `dedupe-generic-ops-recipes`) — `_produce_generic` now reads inputs/output key off `game_data.RECIPES` directly; `GENERIC_OPS` renamed to `GENERIC_OPS_LOCK_KEYS` and trimmed to hold only the lock-gating data that has no RECIPES equivalent.

**Open, roughly in priority order:**
9. **Fork/overlay click-sequence duplication** (`constellation_fork_puzzle.gd` vs. `constellation_overlay.gd:341-607`, §4): near line-for-line duplicate state machines, including two independently-maintained WAV-synth fallbacks, both redundant with `puzzle_synths.gd`'s FM synth. The Fork extraction (item 2) relocated this, it didn't resolve it — real de-duplication work, not yet attempted.
10. **`root_ui.gd`'s `_check_*` trigger sprawl and Archon poke-minigame extraction** (§2) — unchanged from the original list, still the "god object" item. Related, smaller finding: `root_ui.gd` and `firmament_ui.gd` duplicate `_transition_to_age`/`_reveal_panel`/`_hide_all_panels` near-verbatim — worth folding into the same pass if a shared base/helper emerges from the trigger-table work.
11. **Form-builder near-duplicates in `constellation_logic_puzzle.gd`** (§3) — `_build_form_exact_identity`/`_build_form_single_negation` differ by one boolean check; the "reuse chain node or scan pool" pattern is hand-rolled separately in at least two more Form builders. Higher effort, more delicate (correctness-sensitive, per §3) — don't touch without re-running the uniqueness checks memory documents.
12. **Batch vs. single-unit structural duplication in `production_manager.gd`** (§1) — now that both paths are RECIPES-driven (items 5/8), the draw/spend logic itself is still reimplemented twice; collapsing to one path with a quantity parameter is a bigger, lower-urgency structural change.
13. **Three-way resource-access inconsistency** (`game_context.gd`/`root_ui.gd`, §2/§5) — raw field access, older per-resource helpers, and the new `get_resource`/`set_resource` accessor coexist with no consolidation plan. Not urgent on its own, but will keep getting worse every time a new call site picks whichever pattern is closest at hand.
