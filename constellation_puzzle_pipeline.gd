extends RefCounted
# ================= CONSTELLATION PUZZLE PIPELINE v1.0.0 =================
# Builds, caches and resets Constellation logic puzzles for one page's UI root:
# root_ui.gd on Primordial, firmament_ui.gd on Firmament (2026-11-03). Moved
# here from root_ui.gd unchanged so both pages share one pipeline (see
# CLAUDE.md, "Reduce menu switching"); root_ui.gd keeps its old method names
# as one-line pass-throughs, which the dev tests call.
#
# The host is the page's UI root. Its parent holds the ConstellationOverlay
# (asked for each constellation's melody) and the ConstellationStudyOverlay,
# and the host itself has `game_context`, `archon_dialogue_manager` and
# `_study_overlay` members, read with get() so a test stand-in without its
# scene still works.

const _PuzzleScript = preload("res://constellation_logic_puzzle.gd")

var host: Node = null
## constellation_id -> the ConstellationLogicPuzzle being built for it now. ONE
## build per constellation (2026-10-20). Selecting a constellation whose cache
## is empty used to start a build even while one was running, and a RESET clears
## the cache before its own build starts, so picking the constellation during
## a reset ran a second build from another seed; whichever finished last
## replaced the puzzle, so it looked as if the reset happened twice. Now a
## build that something newer (a RESET, a dev recompute) replaces is aborted and
## its result dropped, and a build that only fills a missing cache is not
## started at all while another is running. See generate().
var builds: Dictionary = {}


func _init(p_host: Node, p_builds: Dictionary) -> void:
    host = p_host
    builds = p_builds


## On selecting a constellation: serve its puzzle from cache, or build it.
func select(constellation_id: int) -> void:
    if constellation_id < 0:
        return
    var cd = host.get_node_or_null("/root/ConstellationData")
    if not cd or not host.get("archon_dialogue_manager"):
        return

    # Serve from cache if already generated.
    var cached: Dictionary = cd.get_puzzle_cache(constellation_id)
    if not cached.is_empty():
        # A structurally INVALID cache is cleared, not just skipped: the Study
        # overlay reads this cache directly and never goes through
        # from_cache_dict, so leaving it in place would keep showing corrupt
        # data while regeneration runs. See invalid_cache_reason.
        var cache_problem: String = invalid_cache_reason(cached)
        if cache_problem != "":
            push_warning("%s: constellation %d cached puzzle is invalid (%s) -- discarding it and regenerating." % [host.name, constellation_id, cache_problem])
            cd.clear_puzzle_cache(constellation_id)
            cached = {}
    if not cached.is_empty():
        var puzzle = _PuzzleScript.new()
        var scn: int = int(cached.get("star_count", 0))
        if scn > 0:
            # setup() first so the dump below has real pitch tables and
            # topology (from_cache_dict() alone leaves both empty — see
            # debug_dump_clueset()'s own comment), THEN overwrite with the
            # SAVED solution/clues. Same order as probe_live_clues.gd, and
            # for the same reason: setup()'s own colour/name/sequence
            # assignment is seed-derived and would otherwise silently
            # diverge from what this puzzle actually generated.
            var cdef: Dictionary = cd.get_constellation_def(constellation_id)
            var sq: Array = []
            for i in range(scn):
                sq.append(i)
            puzzle.setup(scn, cdef.get("line_pairs", []), sq, cd.player_seed,
                constellation_id, cdef.get("name_theme", {}),
                cd.get_note_assignment(constellation_id),
                cd.get_note_freqs(constellation_id), null)
        if puzzle.from_cache_dict(cached):
            # Dump the ALREADY-generated puzzle too, not just freshly built
            # ones. The generation-time dump never fires for a puzzle that
            # is being served from cache, which is every puzzle after the
            # session that created it — i.e. exactly the one being played.
            if puzzle.DEBUG_DUMP_CLUES:
                puzzle.debug_dump_clueset("loaded from cache")
            return

    # Cache miss — generate now (should only happen on first run before
    # pre-generation has completed, or after a save with missing cache).
    start_generation(constellation_id)


func start_generation(constellation_id: int) -> void:
    var cd = host.get_node_or_null("/root/ConstellationData")
    if not cd:
        return
    # Fills a MISSING puzzle only. The pre-generation calls on each prestige
    # used to rebuild unconditionally, which would replace a puzzle (and the
    # notes on it) the player already had.
    if builds.has(constellation_id) or not cd.get_puzzle_cache(constellation_id).is_empty():
        return
    var def: Dictionary = cd.get_constellation_def(constellation_id)
    generate(constellation_id, cd, def, cd.get_puzzle_seed(constellation_id),
        "puzzle generation",
        func(cid: int, puzzle): on_generation_complete(cid, puzzle))


## Why a cached puzzle must be DISCARDED, or "" if it can stay. Only a
## structurally INVALID cache (wrong-length arrays, a rank list that is not a
## permutation, a clue pointing at a missing star...) is discarded. A merely
## stale-VERSION cache is left alone: it is still a valid, playable puzzle
## with the player's notes attached, and regeneration can be refused. Static
## so it can be tested without building the scene.
static func invalid_cache_reason(cached: Dictionary) -> String:
    var problem: String = _PuzzleScript.validate_cache_dict(cached)
    if problem.begins_with("version"):
        return ""
    return problem


## The ONE place a finished generation becomes a cached puzzle. A puzzle that
## failed the uniqueness gate on every attempt (puzzle.gate_passed == false) is
## REFUSED: it is not cached, so nothing unsolvable is ever shown, and the
## constellation is marked failed so the Study panel says "not ready".
## Selecting the constellation again finds no cache and regenerates.
## Returns whether the puzzle was accepted.
static func accept_generated_puzzle(cd: Node, constellation_id: int, puzzle) -> bool:
    if not puzzle.gate_passed:
        push_warning("Constellation %d puzzle failed the uniqueness gate on every attempt -- refused, not cached." % constellation_id)
        cd.puzzle_generation_failed[constellation_id] = true
        return false
    cd.puzzle_generation_failed.erase(constellation_id)
    cd.set_puzzle_cache(constellation_id, puzzle.to_cache_dict())
    return true


func on_generation_complete(constellation_id: int, puzzle) -> void:
    var cd = host.get_node_or_null("/root/ConstellationData")
    if not cd:
        return
    accept_generated_puzzle(cd, constellation_id, puzzle)
    var study = host.get("_study_overlay")
    if study and study.visible and study.has_method("show_for_constellation") \
            and study.has_method("get_current_constellation_id") \
            and study.get_current_constellation_id() == constellation_id:
        study.show_for_constellation(constellation_id)


func dev_recompute(constellation_id: int) -> void:
    var cd = host.get_node_or_null("/root/ConstellationData")
    var gc = host.get("game_context")
    if not cd or not gc:
        return
    cd.clear_puzzle_cache(constellation_id)
    var solve_key: String = "constellation_%d_solve_count" % constellation_id
    var hw_key: String = "constellation_%d_high_water" % constellation_id
    gc.assignments.erase(solve_key)
    gc.assignments.erase(hw_key)

    var def: Dictionary = cd.get_constellation_def(constellation_id)
    var dev_seed: int = randi()
    generate(constellation_id, cd, def, dev_seed,
        "puzzle recompute",
        func(cid: int, puzzle):
            var accepted: bool = accept_generated_puzzle(cd, cid, puzzle)
            print("[DEV] Constellation %d puzzle %s, seed=%d" % [cid, "recomputed" if accepted else "REFUSED (failed the uniqueness gate)", dev_seed])
            var study = host.get("_study_overlay")
            if study and study.visible and study.has_method("show_for_constellation"):
                study.show_for_constellation(cid))


## Player-facing full reshuffle for one constellation's puzzle — unlike
## dev_recompute (dev-only; note assignment untouched, so the
## melody/Sequence/Pitch ground truth never actually varied), this also
## reshuffles which star plays which note via
## ConstellationData.reset_note_assignment(), and resyncs the live
## click-sequence puzzle engine so it and the Study Overlay's regenerated
## clues agree on the new mapping. Triggered by the Study Overlay's RESET
## button after its confirmation dialog — see constellation_study_overlay.gd's
## reset_requested signal, connected by each page's UI root.
func reset(constellation_id: int) -> void:
    var cd = host.get_node_or_null("/root/ConstellationData")
    var gc = host.get("game_context")
    if not cd or not gc:
        return

    cd.reset_note_assignment(constellation_id)
    # Wipes the puzzle cache AND the player's own deduction notes for this
    # constellation in one call — player_puzzle_notes lives nested inside
    # the same per-constellation cache entry (see constellation_data.gd's
    # get_player_puzzle_notes()/set_player_puzzle_notes()), so there's
    # nothing extra to clear here: notes describing the OLD star-to-name/
    # pitch mapping would be actively wrong once the mapping changes, not
    # just stale.
    cd.clear_puzzle_cache(constellation_id)
    # A reset is another version to enjoy, not a lost solve: solve_count is
    # what turns the Constellation's effect on, so it stays, and the new
    # puzzle is marked open so it can still be played (reported 2026-11-01).
    var solve_key: String = "constellation_%d_solve_count" % constellation_id
    var hw_key: String = "constellation_%d_high_water" % constellation_id
    if gc._assignment_int(solve_key, 0) > 0:
        gc.constellation_puzzle_reopened[constellation_id] = true
    gc.assignments.erase(hw_key)

    # Resync the LIVE click-sequence puzzle before regenerating clues —
    # click_sequence_puzzle_engine.gd caches note_assignment/correct_
    # sequence the first time it's needed and never re-fetches on its own;
    # without this it would keep validating star clicks against the OLD
    # melody while the Study Overlay's freshly-generated clues describe the
    # NEW one. constellation_fork_puzzle.gd's own engine gets the same
    # resync for free below, via show_for_constellation()'s existing
    # _fork.set_constellation() call.
    var overlay := host.get_parent().find_child("ConstellationOverlay", true, false)
    if overlay and overlay.has_method("_reset_puzzle"):
        overlay._reset_puzzle()

    var def: Dictionary = cd.get_constellation_def(constellation_id)
    var new_seed: int = randi()
    # Recorded so the puzzle counts as built from the right seed later: the
    # boot check for The Archon, and a rebuild after a lost cache.
    cd.puzzle_seed_overrides[str(constellation_id)] = new_seed
    var started: bool = generate(constellation_id, cd, def, new_seed,
        "puzzle reset",
        func(cid: int, puzzle):
            accept_generated_puzzle(cd, cid, puzzle)
            end_study_regeneration(cid)
            var study = host.get("_study_overlay")
            if study and study.visible and study.has_method("show_for_constellation"):
                study.show_for_constellation(cid))
    if not started:
        end_study_regeneration(constellation_id)


## Lifts the Study panel's "Regenerating" cover for this constellation (see
## constellation_study_overlay.gd's regeneration_finished).
func end_study_regeneration(constellation_id: int) -> void:
    var study = host.get("_study_overlay")
    if study and study.has_method("regeneration_finished"):
        study.regeneration_finished(constellation_id)


# ==================================================
# SHARED — validates a constellation def, builds a ConstellationLogicPuzzle,
# and kicks off async generation. Extracted 2026-07-27 from
# _start_puzzle_generation/_dev_recompute_puzzle, which used to reimplement
# this ~17-line block near-verbatim; each caller keeps its own guard,
# pre-work (cache/state reset or none), seed, and completion callback —
# only the mechanical lookup+construction part was shared.
# ==================================================
static func coerce_int(val, default: int) -> int:
    if typeof(val) == TYPE_INT or typeof(val) == TYPE_FLOAT:
        return int(val)
    return default


static func coerce_array(val, default: Array) -> Array:
    if typeof(val) == TYPE_ARRAY:
        return val
    return default


static func coerce_dict(val, default: Dictionary) -> Dictionary:
    if typeof(val) == TYPE_DICTIONARY:
        return val
    return default


## Returns whether a build was started (on_complete is called only if so).
func generate(constellation_id: int, cd: Node, def: Dictionary,
        puzzle_seed: int, warning_context: String, on_complete: Callable) -> bool:
    if def.is_empty():
        return false
    # def can be a player/patron constellation's dict, loaded straight from
    # save data — its fields aren't guaranteed the right type, and a typed
    # Array/Dictionary/int assignment from a wrong-typed value hangs the
    # engine rather than raising a catchable error (confirmed this session).
    var star_count: int = coerce_int(def.get("star_count"), 0)
    if star_count <= 0:
        return false
    var overlay := host.get_parent().find_child("ConstellationOverlay", true, false)
    if not overlay or not overlay.has_method("get_correct_star_sequence"):
        push_warning("%s: ConstellationOverlay not found for %s." % [host.name, warning_context])
        return false
    var line_pairs: Array = coerce_array(def.get("line_pairs"), [])
    var correct_star_sequence: Array = overlay.get_correct_star_sequence(constellation_id)
    var name_theme: Dictionary = coerce_dict(def.get("name_theme"), {})
    var star_pitch_index: Array = cd.get_note_assignment(constellation_id)
    var pitch_freqs: Array = cd.get_note_freqs(constellation_id)

    var puzzle = _PuzzleScript.new()
    puzzle.setup(star_count, line_pairs, correct_star_sequence,
            puzzle_seed, constellation_id, name_theme,
            star_pitch_index, pitch_freqs, host)
    var gc = host.get("game_context")
    if gc:
        puzzle.difficulty = gc.get_constellation_difficulty(constellation_id)
    # The newest build wins; an older one still running (built before a reset
    # changed the note assignment, or a duplicate) stops and is ignored.
    var superseded = builds.get(constellation_id)
    if superseded != null:
        superseded.abort_requested = true
    builds[constellation_id] = puzzle
    puzzle.generation_complete.connect(
        func(cid: int):
            if builds.get(cid) != puzzle:
                return
            builds.erase(cid)
            on_complete.call(cid, puzzle))
    puzzle.generate_clues_async.call_deferred()
    return true
