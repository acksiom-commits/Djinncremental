extends RefCounted
# ================= ONE WALK THROUGH THE FINISHED PUZZLE =================
# The author's final redundancy pass (2026-10-31). The passes in the generator
# ask "does the solver still find one answer without this clue?", which keeps
# any clue a solver needs and drops clues a person leans on: measured, cutting
# on that test alone took hint reach from 95% of notes to 62%. This asks what
# the player's own path needs.
#
# On a hidden board, with every star Listened, each clue is applied ALONE, in
# order, again and again until none gives anything new. A clue none of whose
# steps ever changed the board has added nothing by the time it was reached,
# and is a candidate for removal. One walk, not a solve per clue.
#
# Used by ConstellationLogicPuzzle._final_clue_walk, which still proves every
# removal (a clue unused on THIS path is not proven unneeded: see
# mus_zebratutor_dormant_and_not_a_redundancy_shortcut) and runs one ordinary
# hint run on the result, which must reach exactly as far.
#
# Measured on 18 Beginner puzzles: 20.9 -> 19.3 clues, hint reach unchanged on
# every one, ~7 s a puzzle on a desktop. Most of the overlap it cannot see: a
# clue that still adds one small fact when reached counts as used. Trying each
# removal found 16.7 clues at ~17 s; the author chose this.
#
# THE BOARD IS A HIDDEN OVERLAY, because the step finder and the marks live on
# it. It must stay inert, so:
#   - _cd stays null (only show_for_constellation sets it), which is what keeps
#     this scratch board's saves away from the player's real notes;
#   - hold_refresh stays up, for speed: a run spent 87% of its time saving and
#     refreshing after every single mark, so _apply settles once instead;
#   - pause_tree hands frames back through the engine's own *_pausing phases:
#     this runs during play, while a puzzle pre-generates, and neither a refresh
#     nor the hint search may hold a frame (test_generation_frame_slicing);
#   - its synth is dropped: Listen would otherwise chime through every star;
#   - board_only skips the panel redraws a refresh ends with;
#   - a merge conflict answers itself: the dialog would wait on a click forever;
#   - _form_clues_cache stays empty: the engine applies Hop facts from it by
#     itself, and a clue whose work it did would read as unused.
# ========================================================================

var _g = null
var _tree: SceneTree = null
var _host = null
var _d = null
var _w = null


func open(g, tree: SceneTree) -> void:
    _g = g
    _tree = tree
    _host = load("res://ConstellationStudyOverlay.tscn").instantiate()
    tree.root.add_child(_host)
    await tree.process_frame
    _host.process_mode = Node.PROCESS_MODE_DISABLED
    _host._synth = null
    _host._constellation_id = int(g.constellation_id)
    _host._star_count = int(g.star_count)
    _host._star_names = g.star_names.duplicate()
    _host._star_colors = g.star_colors.duplicate()
    _host._star_degrees = g.star_degrees.duplicate()
    _host._pitch_freqs = g._pitch_freqs.duplicate()
    _host._star_pitch_index = g.star_pitch_index.duplicate()
    _host._sequence_rank_solution = g.sequence_rank_solution.duplicate()
    _host._melody_seq_pos_sequence = g.melody_seq_pos_sequence.duplicate()
    _host._melody_star_sequence = g.melody_star_sequence.duplicate()
    _host._repeat_count = g.repeat_count.duplicate()
    _host._widgets.clear_pitch_caches()
    _d = _host._deduction
    _w = _host._widgets
    _d.hold_refresh = true
    _d.board_only = true
    # Without a host there is nobody to keep responsive, and a test stays quick.
    _d.pause_tree = tree if g._host else null
    _d._conflict_dialog_fn = func(_what: String, _a: String, _b: String) -> String:
        return "choice_a"


func close() -> void:
    if _host != null and is_instance_valid(_host):
        _host.queue_free()
    _host = null
    _d = null
    _w = null


## Every clue alone, in `order`, until none gives anything new. Returns the
## clue indices that changed the board, and how far it got.
func walk(order: Array) -> Dictionary:
    await _fresh_board()
    var clues: Array = _clue_list()
    var used: Dictionary = {}
    var board_changed: bool = true
    for _pass in 12:
        if _g.abort_requested:
            break
        var moved: bool = false
        for i in order:
            var steps: Array = await _d.hint_next_steps_pausing([clues[int(i)]], board_changed)
            board_changed = false
            if steps.is_empty():
                continue
            board_changed = true
            # A step citing no clue reads only the player's marks: it is nobody's.
            var mine: Array = []
            var free: Array = []
            for st in steps:
                if int(st.get("clue_index", 0)) >= 0:
                    mine.append(st)
                else:
                    free.append(st)
            if not free.is_empty():
                await _apply(free)
            if not mine.is_empty() and await _apply(mine):
                used[int(i)] = true
                moved = true
        if moved:
            continue
        # Stalled one clue at a time: what only several clues give together.
        var together: Array = await _d.hint_next_steps_pausing(clues)
        if together.is_empty() or not await _apply(together):
            break
        for st2 in together:
            for ci in st2.get("clue_indices", [st2.get("clue_index", -1)]):
                if int(ci) >= 0:
                    used[int(ci)] = true
    var out: Dictionary = _score()
    out["used"] = used
    return out


## How far the ordinary hints get: every step of a round at once, round after
## round, on an empty board. The player's Hint button, repeated.
func reach() -> Dictionary:
    await _fresh_board()
    var clues: Array = _clue_list()
    for _round in 30:
        if _g.abort_requested:
            break
        var now: Array = await _d.hint_next_steps_pausing(clues)
        if now.is_empty():
            break
        await _apply(now)
    return _score()


func _clue_list() -> Array:
    var out: Array = []
    for c in _g.chosen_form_clues:
        out.append(c)
    return out


## Empty, with every star Listened: the premise the puzzle is built on.
func _fresh_board() -> void:
    _d._load_match_records([])
    for s in int(_g.star_count):
        await _host._on_pitch_listen_star_clicked(s)
        await _d.pause_if_due()
    await _d.refresh_pausing()


func _score() -> Dictionary:
    var placed: int = 0
    for r in _d.record_count():
        placed += (_d.record_at(r).get("melody_ticks", []) as Array).size()
    var tied: int = 0
    for n in int(_g.star_count):
        var nr: int = _d._find_match_record_by_name(str(_g.star_names[n]))
        if nr >= 0 and _d._candidate_stars_for_record(nr).size() == 1:
            tied += 1
    return {"placed": placed, "tied": tied}


func _row_record(step: Dictionary) -> int:
    match str(step["row_kind"]):
        "name":
            return _d._get_or_create_match_record_for_name(str(step["row_key"]))
        "star":
            return _d._get_or_create_match_record_for_star_idx(int(step["row_key"]))
    return _d._get_or_create_match_record_for_melody_tick(int(step["row_key"]))


## Puts the steps on the board as the player would, then runs the engine once.
## Returns whether any mark landed.
func _apply(steps: Array) -> bool:
    var changed: bool = false
    for stp in steps:
        match str(stp["axis"]):
            "note":
                for t in stp["must_ticks"]:
                    var rec: int = _row_record(stp)
                    if _d._repeat_note_state_for_record(rec, int(t)) == 0:
                        await _w._on_seq_note_select(rec, int(t))
                        changed = true
                for t2 in stp["cannot_ticks"]:
                    var rec2: int = _row_record(stp)
                    if _d._repeat_note_state_for_record(rec2, int(t2)) == 0:
                        _w._on_seq_note_toggle(rec2, int(t2))
                        changed = true
            "repeat":
                var rec3: int = _row_record(stp)
                if int(stp["must_value"]) >= 0:
                    if _d._effective_repeat_state(rec3, int(stp["must_value"])) == 0:
                        _w._repeat_toggle_confirm(rec3, int(stp["must_value"]))
                        changed = true
                else:
                    for v in stp["cannot_values"]:
                        rec3 = _row_record(stp)
                        if _d._effective_repeat_state(rec3, int(v)) == 0:
                            _w._repeat_toggle_block(rec3, int(v))
                            changed = true
            "name":
                var nrec: int = _d._get_or_create_match_record_for_name(str(_g.star_names[int(stp["star"])]))
                var elim: Dictionary = _d.record_at(nrec).get("star_elim", {})
                for s in stp["eliminated_stars"]:
                    if int(elim.get(int(s), 0)) == 0:
                        elim[int(s)] = 2
                        changed = true
                _d.record_at(nrec)["star_elim"] = elim
    await _d.refresh_pausing()
    return changed
