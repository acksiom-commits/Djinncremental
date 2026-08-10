class_name ConstellationPuzzleDeduction
extends RefCounted

# Deduction-engine half of the Constellation Study Overlay split (see
# docs/early_game_architecture_overview.md, §4, and the refactor plan this
# executes). Owns _match_records and everything that reads/mutates it —
# get-or-create lookups, elimination propagation, merge/conflict logic,
# save/load. Depends on nothing but data: reads ground-truth arrays and
# node-independent config off _host (star names/colors/counts, pitch
# tables, etc. — none of that is deduction's own state, so it stays on the
# host rather than being duplicated here), and the one place it needs to
# put something on screen mid-computation (the conflict-choice dialog) goes
# through the injected _conflict_dialog_fn Callable instead of reaching
# into the widgets file directly.
#
# Being built up incrementally, one independently headless-boot-verified
# slice at a time, same pattern as constellation_puzzle_widgets.gd.
# Progress: Slice A (ownership wiring + 4 scattered functions) in progress.

var _host: ConstellationStudyOverlay = null

# Shared puzzle-state color palette — see puzzle_state_colors.gd.
const STATE_COLORS: PuzzleStateColors = preload("res://puzzle_state_colors.tres")

# Deduction code (_merge_match_records/_confirm_match_record_identity) asks
# for a conflict choice through this instead of calling the widgets file's
# _show_conflict_choice directly — keeps this file's only "put something on
# screen" dependency behind one injected seam.
var _conflict_dialog_fn: Callable = Callable()

# The star widget's own per-star name checklist used to keep its protect
# and manual-block flags in two GLOBAL dicts keyed "star_idx:name",
# separate from the identical per-record fields every other surface uses
# (protected_staff_names / manual_name_blocks). That wasn't just
# duplication: because they were keyed by star and lived outside
# _match_records, _merge_match_records never merged them, so those flags
# sat entirely outside propagation, save-merging, and every settle pass.
# They now live on the star's own record, where the keying is identical
# (by name) and the existing merge/save paths pick them up for free.
# See _star_name_flags_record() below.

# Match records — one per set of facts the player has asserted belong to the same star.
# Each record: {
#   "name": String,              # "" if unknown
#   "seq_lo": int, "seq_hi": int, # 0 if unknown; exact position known when seq_lo == seq_hi > 0
#   "seq_candidates": Array,      # explicit narrowed set of possible sequence slots, if any
#   "color_states": Dictionary,   # {color_idx(int): state(int)} 0=neutral, 1=confirmed, 2=eliminated
#   "pitch_states": Dictionary,   # {note_name(String): state(int)}
#   "degree_states": Dictionary,  # {degree(int): state(int)}
#   "name_states": Dictionary,    # {name(String): state(int)}
#   "manual_name_blocks": Dictionary,   # {name(String): true} — names the player
#   "manual_pitch_blocks": Dictionary,  # X'd directly, as opposed to state-2
#   "manual_color_blocks": Dictionary,  # entries that are fallout from confirming
#                                        # a sibling value. Lets the Undo row tell
#                                        # "Undo selects" (revert sibling-clearing
#                                        # fallout only) apart from "Undo blocks"
#                                        # (revert the player's own X clicks only).
#   "protected_pitch_notes": Dictionary,  # {note_name(String): true} — right-click
#   "protected_color_idxs": Dictionary,   # "still possible" flags, one dict per
#   "protected_staff_names": Dictionary,  # category; cosmetic hints, not hard facts.
#   "pitch_revealed": bool,       # true once the record's pitch has been shown to the player
#   "star_elim": Dictionary,      # {star_idx(int): state(int)} — which stars are ruled out for THIS record
#   "color_star_elim_marks": Dictionary,  # {star_idx(int): true} — stars this record's
#                                          # color-derived elimination pass itself marked,
#                                          # so a later recompute knows what it owns
#   "star_idx": int,              # -1 until resolvable from seq_lo==seq_hi or map-widget confirm
#   "color_slot_label": String,   # "" unless bound to a Sort:Color grid slot (e.g. "Blue A")
#   "pitch_slot_label": String,   # "" unless bound to a Sort:Pitch grid slot
#   "degree_slot_label": String,  # "" unless bound to a Sort:Sequence grid slot
# }
var _match_records: Array[Dictionary] = []

## Bumped every time _match_records is cleared/rebuilt (see
## _load_match_records()). _merge_match_records() and
## _confirm_match_record_identity() both hold indices/Dictionary
## references across `await _conflict_dialog_fn.call(...)` — a real,
## reachable window, since root_ui.gd re-invokes show_for_constellation()
## (which rebuilds _match_records from scratch) on the SAME constellation
## a study overlay already has open, whenever that constellation's puzzle
## regenerates. Capturing this counter at entry and checking it after an
## await lets those functions detect "the array was rebuilt out from under
## me" and abort cleanly instead of writing to an orphaned Dictionary or
## bracket-indexing a stale/now-out-of-range index.
var _match_records_generation: int = 0


func setup(host: ConstellationStudyOverlay, conflict_dialog_fn: Callable) -> void:
    _host = host
    _conflict_dialog_fn = conflict_dialog_fn


# ==================================================
# TYPE COERCION — _load_match_records() is the one place untrusted,
# save-derived data enters _match_records. Every other function in this
# file that reads a record field (there are dozens, e.g. `int(r.get(
# "seq_lo", 0))` throughout) trusts that value is already the right type
# — true for records built by normal gameplay (literal ints/strings), but
# not for a corrupted-but-parseable save. Fully sanitizing every field
# here, once, means none of those downstream reads need their own guard:
# a wrong-typed value assigned into a typed variable, or passed to the
# global int()/bool() constructors, hangs the engine rather than raising
# a catchable error (confirmed repeatedly this session, bool() included).
# str() is safe for any input type (also confirmed) — the many str(...)
# calls elsewhere in this file don't need this treatment.
# ==================================================
func _coerce_int(val, default: int) -> int:
    if typeof(val) == TYPE_INT or typeof(val) == TYPE_FLOAT:
        return int(val)
    return default


# For coercing DICTIONARY KEYS that are semantically ints (color/star/degree
# indices), not values. JSON.stringify()/JSON.parse_string() — exactly what
# save_manager.gd's atomic write/read does to the whole save file — silently
# turns every int Dictionary key into a String (confirmed directly: {1:"a"}
# round-trips to {"1":"a"}). _coerce_int() alone only accepts already-typed
# int/float, so applying it straight to a key coming out of a real save
# reload returns `default` for every single key — collapsing an entire
# dict like color_states down to one entry, silently, on every normal
# save/load cycle, not just a corrupted one. This was the actual bug;
# range-clamping alone (added first, kept below) wasn't enough on its own.
func _coerce_int_key(val, default: int) -> int:
    if typeof(val) == TYPE_INT or typeof(val) == TYPE_FLOAT:
        return int(val)
    if typeof(val) == TYPE_STRING and (val as String).is_valid_int():
        return int(val)
    return default


func _coerce_bool(val, default: bool) -> bool:
    if typeof(val) == TYPE_BOOL:
        return val
    return default


func _coerce_dict(val, default: Dictionary) -> Dictionary:
    if typeof(val) == TYPE_DICTIONARY:
        return val
    return default


func _coerce_array(val, default: Array) -> Array:
    if typeof(val) == TYPE_ARRAY:
        return val
    return default


# ==================================================
# MELODY BAR SCORE — piano-roll style summary of confirmed Sequence×Pitch
# information. Purely a rendering query over _match_records: no ground
# truth is ever read here. A position only gets a notehead if the player
# has confirmed BOTH the exact sequence slot AND a pitch on that same
# record; a confirmed slot with unconfirmed pitch gets a "?" at neutral
# height; a wholly unconfirmed slot draws nothing.
# ==================================================
func _melody_marker_for_position(seq_pos: int) -> Dictionary:
    var has_position: bool = false
    for r in _match_records:
        var lo: int = int(r.get("seq_lo", 0))
        var hi: int = int(r.get("seq_hi", 0))
        if lo == seq_pos and hi == seq_pos:
            has_position = true
            var pitch_states: Dictionary = r.get("pitch_states", {})
            for note_name in pitch_states:
                if int(pitch_states[note_name]) == 1:
                    return {"has_position": true, "pitch_known": true, "note_name": str(note_name)}
    return {"has_position": has_position, "pitch_known": false, "note_name": ""}


func _known_color_for_seq_position(seq_pos: int) -> int:
    # A position's color counts as "known" either because the player
    # directly confirmed one, or because elimination (from here or
    # propagated in from a Sort: tab) has narrowed it down to the single
    # remaining candidate — that's the same "resolves by elimination"
    # pattern already used for identity anchors elsewhere in this panel.
    for r in _match_records:
        var lo: int = int(r.get("seq_lo", 0))
        var hi: int = int(r.get("seq_hi", 0))
        if lo != seq_pos or hi != seq_pos:
            continue
        var cs: Dictionary = r.get("color_states", {})
        var confirmed: int = -1
        var eliminated_count: int = 0
        var remaining: int = -1
        for ci in _host.COLOR_NAME_LABELS.size():
            var state: int = int(cs.get(ci, 0))
            if state == 1:
                confirmed = ci
            elif state == 2:
                eliminated_count += 1
            else:
                remaining = ci
        if confirmed >= 0:
            return confirmed
        if eliminated_count == _host.COLOR_NAME_LABELS.size() - 1 and remaining >= 0:
            return remaining
    return -1


func _propagate_pitch_confirmed_same_record(record_idx: int, confirmed_note: String) -> void:
    if record_idx < 0 or record_idx >= _match_records.size():
        return
    var r: Dictionary = _match_records[record_idx]
    var pitch_states: Dictionary = r.get("pitch_states", {})
    for f in _host._pitch_freqs:
        var note_name: String = ConstellationLogicPuzzle.note_name_for_freq(f)
        if note_name != confirmed_note:
            pitch_states[note_name] = 2
    pitch_states[confirmed_note] = 1
    r["pitch_states"] = pitch_states
    # A confirm supersedes any earlier manual X on the same note (edge case:
    # player X'd a note, then later confirmed that same note some other way)
    # — otherwise "Undo blocks" would later wipe out this now-confirmed value.
    var manual_pitch: Dictionary = r.get("manual_pitch_blocks", {})
    if manual_pitch.has(confirmed_note):
        manual_pitch.erase(confirmed_note)
        r["manual_pitch_blocks"] = manual_pitch
    # Same staleness fix as _sync_color_states_from_star_idx: a
    # pitch_slot_label naming a DIFFERENT note than what was just confirmed
    # is now wrong. _effective_pitch_state checks the label BEFORE raw
    # pitch_states, so an unfixed stale label here would keep showing the
    # superseded note as confirmed instead of this one.
    var label: String = str(r.get("pitch_slot_label", ""))
    if label != "" and not label.begins_with(confirmed_note):
        r["pitch_slot_label"] = ""


func _save_puzzle_notes() -> void:
    # Every mutation path calls this, so it's the reliable choke point for
    # invalidating the derived caches — see _clear_deduction_caches().
    _clear_deduction_caches()
    if not _host._cd or _host._constellation_id < 0:
        return
    var notes: Dictionary = {}
    notes["match_records"] = _save_match_records()
    # protected_names / user_blocks are gone as separate note fields — the
    # star widget's protect and manual-block flags now live on each star's
    # own record, so they round-trip inside match_records above.
    _host._cd.set_player_puzzle_notes(_host._constellation_id, notes)

# ==================================================
# DEDUCTION ENGINE CORE — record lookups, elimination
# propagation, merge/conflict logic, save/load
# ==================================================
func _clear_protected_names_for_star(star_idx: int) -> void:
    var idx: int = _find_match_record_by_star_idx(star_idx)
    if idx >= 0:
        _match_records[idx]["protected_staff_names"] = {}




# ==================================================
# NAME-PROPAGATION HELPERS
# ==================================================
func _propagate_name_confirmed(confirmed_star: int, star_name: String) -> void:
    # A name belongs to exactly one star in the WHOLE constellation. Now that
    # star_elim lives on _match_records instead of a separate per-star array,
    # this one write is visible from every display surface that reads the
    # same record — the map widgets, and any future Sort: tab that shows
    # name/star candidates — with nothing left to fall out of sync.
    var this_record: int = _get_or_create_match_record_for_name(star_name)
    var this_elim: Dictionary = _match_records[this_record].get("star_elim", {})
    for j in _host._star_count:
        this_elim[j] = 1 if j == confirmed_star else 2
    _match_records[this_record]["star_elim"] = this_elim

    for i in _match_records.size():
        # Only other records that themselves represent a candidate NAME —
        # star_elim's meaning is "which stars are ruled out for THIS
        # record's name," so it's only sound to write into it when there
        # is a name. A Color/Pitch/Sequence/Degree-slot record with no
        # name yet (e.g. an anonymous "Red A" placeholder for one of
        # several same-color stars) isn't a candidate for star_name at
        # all — writing confirmed_star's exclusion onto it anyway falsely
        # asserts "this slot isn't confirmed_star," contaminating
        # _records_provably_distinct's star category with a claim the
        # player never made and this slot has no actual basis for. Found
        # via a Color-tab exclusion query surfacing that exact
        # contamination: confirming a name onto a star wrongly excluded
        # that name from every same-color slot's Name selector.
        if i == this_record or str(_match_records[i].get("name", "")) == "":
            continue
        var r: Dictionary = _match_records[i]
        var elim: Dictionary = r.get("star_elim", {})
        var cur: int = int(elim.get(confirmed_star, 0))
        if cur != 1:
            elim[confirmed_star] = 2
        r["star_elim"] = elim

    _save_puzzle_notes()


# ==================================================
# RECORD IDENTITY LOOKUPS
# ==================================================

func _find_match_record_by_name(name_str: String) -> int:
    if name_str == "":
        return -1
    for i in _match_records.size():
        if _match_records[i]["name"] == name_str:
            return i
    return -1


func _star_elim_state(star_idx: int, name_str: String) -> int:
    var idx: int = _find_match_record_by_name(name_str)
    if idx < 0:
        return 0
    var r: Dictionary = _match_records[idx]
    if int(r.get("star_idx", -1)) == star_idx:
        return 1
    return int(r.get("star_elim", {}).get(star_idx, 0))



## The record that owns a star's own per-star name-checklist flags. Same
## record the star widget already binds to, so its protect/manual-block
## state now merges, saves, and propagates like every other record field
## (see the note where _protected_names/_user_blocks used to be declared).
func _star_name_flags_record(star_idx: int) -> int:
    if star_idx < 0 or star_idx >= _host._star_count:
        return -1
    return _get_or_create_match_record_for_star_idx(star_idx)


func _is_name_protected(star_idx: int, name_str: String) -> bool:
    var idx: int = _find_match_record_by_star_idx(star_idx)
    if idx < 0:
        return false
    return (_match_records[idx].get("protected_staff_names", {}) as Dictionary).has(name_str)


func _set_name_protected(star_idx: int, name_str: String, on: bool) -> void:
    var idx: int = _star_name_flags_record(star_idx)
    if idx < 0:
        return
    var protected: Dictionary = _match_records[idx].get("protected_staff_names", {})
    if on:
        protected[name_str] = true
    else:
        protected.erase(name_str)
    _match_records[idx]["protected_staff_names"] = protected


func _is_star_name_user_blocked(star_idx: int, name_str: String) -> bool:
    var idx: int = _find_match_record_by_star_idx(star_idx)
    if idx < 0:
        return false
    return (_match_records[idx].get("manual_name_blocks", {}) as Dictionary).has(name_str)


func _set_star_name_user_blocked(star_idx: int, name_str: String, on: bool) -> void:
    var idx: int = _star_name_flags_record(star_idx)
    if idx < 0:
        return
    var manual: Dictionary = _match_records[idx].get("manual_name_blocks", {})
    if on:
        manual[name_str] = true
    else:
        manual.erase(name_str)
    _match_records[idx]["manual_name_blocks"] = manual


## Every name this star's row has a manual block on — replaces scanning a
## global dict's "star:name" keys with a straight read of that star's own
## record.
func _user_blocked_names_for_star(star_idx: int) -> Array[String]:
    var out: Array[String] = []
    var idx: int = _find_match_record_by_star_idx(star_idx)
    if idx < 0:
        return out
    for k in (_match_records[idx].get("manual_name_blocks", {}) as Dictionary):
        out.append(str(k))
    return out


func _clear_star_name_user_blocks(star_idx: int) -> void:
    var idx: int = _find_match_record_by_star_idx(star_idx)
    if idx >= 0:
        _match_records[idx]["manual_name_blocks"] = {}


func _star_has_any_protected(star_idx: int, all_names_for_star: Array) -> bool:
    # Ignores stale protect flags on names that got hard-decided by some
    # other means since being protected (e.g. a later color elimination) —
    # only a name still sitting at neutral counts toward "protected."
    for n in all_names_for_star:
        var name_str: String = str(n)
        if _is_name_protected(star_idx, name_str) and _star_elim_state(star_idx, name_str) == 0:
            return true
    return false


func _effective_name_display_state(star_idx: int, name_str: String, all_names_for_star: Array) -> int:
    var base: int = _star_elim_state(star_idx, name_str)
    if base != 0:
        return base   # hard confirm (1) or hard eliminate (2) always wins
    if not _star_has_any_protected(star_idx, all_names_for_star):
        return 0       # neutral, nobody's protected anything yet in this row
    return 4 if _is_name_protected(star_idx, name_str) else 3


func _record_value_protected(record_idx: int, protect_key: String, value_key) -> bool:
    if record_idx < 0 or record_idx >= _match_records.size():
        return false
    var r: Dictionary = _match_records[record_idx]
    var protected: Dictionary = r.get(protect_key, {})
    return protected.has(value_key)


func _record_any_protected(record_idx: int, protect_key: String) -> bool:
    if record_idx < 0 or record_idx >= _match_records.size():
        return false
    var r: Dictionary = _match_records[record_idx]
    var protected: Dictionary = r.get(protect_key, {})
    return not protected.is_empty()


func _record_effective_state(record_idx: int, states_key: String, protect_key: String, value_key) -> int:
    if record_idx < 0 or record_idx >= _match_records.size():
        return 0
    var r: Dictionary = _match_records[record_idx]
    var states: Dictionary = r.get(states_key, {})
    var base: int = int(states.get(value_key, 0))
    if base != 0:
        return base
    if not _record_any_protected(record_idx, protect_key):
        return 0
    return 4 if _record_value_protected(record_idx, protect_key, value_key) else 3




# ── Record-level Undo engine ──────────────────────────────────────────
# Mirrors the star widget's Undo selects/blocks/all row (_on_undo_name_*
# above), scoped to a single record's own states dict instead of a star's
# cross-record star_elim. "Selects" reverts the fallout of the record's
# OWN most recent confirm (sibling-clearing set every other value to
# eliminated); "blocks" reverts only the values the player X'd directly,
# tracked in the manual_*_blocks dicts added alongside name_states/
# pitch_states/color_states. The two are independent so they compose:
# a value the player X'd, that ALSO happened to be swept by a later
# confirm's sibling-clearing, stays flagged manual and survives
# "Undo selects" — only "Undo blocks" (or "Undo all") clears it.
func _undo_category_selects(record_idx: int, states_key: String, manual_key: String, protect_key: String, all_values: Array) -> void:
    if record_idx < 0 or record_idx >= _match_records.size():
        return
    var r: Dictionary = _match_records[record_idx]
    var states: Dictionary = r.get(states_key, {})
    var manual: Dictionary = r.get(manual_key, {})
    for v in all_values:
        var cur: int = int(states.get(v, 0))
        if cur == 1 or (cur == 2 and not manual.has(v)):
            states[v] = 0
    r[states_key] = states
    # "still possible" protects only mean something relative to a
    # selection that no longer exists once that selection is undone —
    # same reasoning as _clear_protected_names_for_star.
    r[protect_key] = {}


func _undo_category_blocks(record_idx: int, states_key: String, manual_key: String) -> void:
    if record_idx < 0 or record_idx >= _match_records.size():
        return
    var r: Dictionary = _match_records[record_idx]
    var states: Dictionary = r.get(states_key, {})
    var manual: Dictionary = r.get(manual_key, {})
    for v in manual.keys():
        states[v] = 0
    r[states_key] = states
    r[manual_key] = {}




func _recompute_color_star_elim(record_idx: int) -> void:
    if record_idx < 0 or record_idx >= _match_records.size():
        return
    # Color is the one axis directly visible per star, so it's the one axis
    # that can safely auto-propagate into the name/star grid without leaking
    # anything the player hasn't earned. Sequence and pitch are themselves
    # unknowns from the player's perspective, so they intentionally do NOT
    # get this treatment — they only unify through record merging once
    # identity is independently confirmed.
    #
    # FIXED 2026-07-27 — this used to be _apply_color_elimination_to_names,
    # called with the specific (color_idx, new_state) that just changed. It
    # only ever ADDED elim=2 marks, never removed any — so un-confirming or
    # un-eliminating a color (the click-again-to-deselect / Undo paths) left
    # stale "this star can't be the name" marks behind, since nothing ever
    # told this function a mark's reason no longer held.
    #
    # Now this recomputes the color-derived portion of star_elim from
    # scratch off CURRENT color_states every time any color state changes
    # (confirm, eliminate, deselect, or Undo) — no need to track what
    # changed, just what's true now. color_star_elim_marks (persisted
    # alongside star_elim) remembers which stars THIS function marked, so a
    # star that's no longer ruled out gets released back to 0 — but only if
    # nothing stronger (a direct name/star-identity confirm, which
    # overwrites star_elim wholesale elsewhere and always wins) has since
    # claimed elim=1 there.
    var r: Dictionary = _match_records[record_idx]
    var name_str: String = str(r.get("name", ""))
    if name_str == "":
        return
    if int(r.get("star_idx", -1)) >= 0:
        return   # identity already pinned; a wholesale overwrite owns star_elim now
    var color_states: Dictionary = r.get("color_states", {})
    var confirmed_color: int = -1
    for ci in _host.COLOR_NAME_LABELS.size():
        if int(color_states.get(ci, 0)) == 1:
            confirmed_color = ci
            break
    var elim: Dictionary = r.get("star_elim", {})
    var prev_marks: Dictionary = r.get("color_star_elim_marks", {})
    var new_marks: Dictionary = {}
    for s in _host._star_count:
        var sc: int = _host._star_colors[s] if s < _host._star_colors.size() else 1
        var ruled_out: bool = false
        if confirmed_color >= 0:
            ruled_out = sc != confirmed_color
        else:
            ruled_out = int(color_states.get(sc, 0)) == 2
        if ruled_out:
            new_marks[s] = true
            if int(elim.get(s, 0)) != 1:
                elim[s] = 2
    for s in prev_marks.keys():
        if not new_marks.has(s) and int(elim.get(s, 0)) == 2:
            elim[s] = 0
    r["star_elim"] = elim
    r["color_star_elim_marks"] = new_marks


func _slot_letter(idx: int) -> String:
    return char(65 + idx) if idx < 26 else str(idx + 1)


func _anonymous_star_label(star_idx: int) -> String:
    var color_idx: int = _host._star_colors[star_idx] if star_idx < _host._star_colors.size() else 1
    var color_name: String = _host.COLOR_NAME_LABELS[clamp(color_idx, 0, _host.COLOR_NAME_LABELS.size() - 1)]
    var ordinal: int = 0
    for s in _host._star_count:
        var sc: int = _host._star_colors[s] if s < _host._star_colors.size() else 1
        if sc == color_idx and s < star_idx:
            ordinal += 1
    return "%s star %s" % [color_name, _slot_letter(ordinal)]




func _known_color_for_record(record_idx: int) -> int:
    if record_idx < 0 or record_idx >= _match_records.size():
        return -1
    var r: Dictionary = _match_records[record_idx]
    var star_idx: int = int(r.get("star_idx", -1))
    if star_idx >= 0:
        # Clamped, not just bounds-checked against array size — _star_colors
        # is int-coerced but not range-clamped on load (constellation_study_
        # overlay.gd), so a corrupted/stale puzzle-cache entry could put an
        # out-of-range value here. The three callers in constellation_puzzle_
        # widgets.gd (_build_pitch_group_row) bracket-index the 4-element
        # STAR_COLORS_BY_IDX with this return value with no clamp of their
        # own — every OTHER _star_colors consumer in that file already
        # clamps to 0-3 before indexing the same array; this closes the one
        # path that routed through here instead and skipped it.
        return clamp(_host._star_colors[star_idx], 0, 3) if star_idx < _host._star_colors.size() else -1
    var cs: Dictionary = r.get("color_states", {})
    for ci in _host.COLOR_NAME_LABELS.size():
        if int(cs.get(ci, 0)) == 1:
            return ci
    return -1


func _sync_color_states_from_star_idx(record_idx: int) -> void:
    if record_idx < 0 or record_idx >= _match_records.size():
        return
    var r: Dictionary = _match_records[record_idx]
    var star_idx: int = int(r.get("star_idx", -1))
    if star_idx < 0 or star_idx >= _host._star_colors.size():
        return
    var true_color: int = clamp(_host._star_colors[star_idx], 0, 3)
    for ci in _host.COLOR_NAME_LABELS.size():
        r["color_states"][ci] = 1 if ci == true_color else 2
    # A color_slot_label ("Blue A") only means something while the record's
    # color is still ambiguous — once star_idx pins it to ground truth, a
    # label naming a DIFFERENT color is stale and would leave that slot's
    # Sort:Color row pointing at a record that no longer belongs there.
    var label: String = str(r.get("color_slot_label", ""))
    if label != "" and not label.begins_with(_host.COLOR_NAME_LABELS[true_color]):
        r["color_slot_label"] = ""


## Single source of truth for a match record's field set. The full literal
## used to be written out SIX times (once per _get_or_create_match_record_
## for_* function) with _save_match_records()/_load_match_records() carrying
## their own hand-maintained copies of the same field list on top — eight
## places to keep in sync, every one of them by hand. Adding or removing one
## field meant eight correct edits or a silently-dropped value; proven live
## when a field added for one experiment had to be threaded through all
## eight and then unpicked from all eight again.
##
## `overrides` sets whatever the specific creation site needs; everything
## else takes the default below. Load also starts from this, so a save
## written before a field existed comes back with that field's default
## rather than missing entirely.
func _new_match_record(overrides: Dictionary = {}) -> Dictionary:
    var r: Dictionary = {
        "name": "",
        "seq_lo": 0, "seq_hi": 0,
        "seq_candidates": [],
        "color_states": {},
        "pitch_states": {},
        "degree_states": {},
        "name_states": {},
        "manual_name_blocks": {},
        "manual_pitch_blocks": {},
        "manual_color_blocks": {},
        "protected_pitch_notes": {},
        "protected_color_idxs": {},
        "protected_staff_names": {},
        "pitch_revealed": false,
        "star_elim": {},
        "color_star_elim_marks": {},
        "star_idx": -1,
        "color_slot_label": "",
        "pitch_slot_label": "",
        "degree_slot_label": "",
    }
    for k in overrides:
        r[k] = overrides[k]
    return r


func _get_or_create_match_record_for_color_slot(color_idx: int, position_in_group: int) -> int:
    var label: String = "%s %s" % [_host.COLOR_NAME_LABELS[color_idx], _slot_letter(position_in_group)]
    for i in _match_records.size():
        if str(_match_records[i].get("color_slot_label", "")) == label:
            return i
    for i in _match_records.size():
        var r: Dictionary = _match_records[i]
        if str(r.get("color_slot_label", "")) != "":
            continue
        if int(r.get("color_states", {}).get(color_idx, 0)) == 1:
            r["color_slot_label"] = label
            return i
    _match_records.append(_new_match_record({"color_slot_label": label}))
    return _match_records.size() - 1


func _get_or_create_match_record_for_pitch_slot(pitch_freq: float, position_in_group: int) -> int:
    var pitch_name: String = ConstellationLogicPuzzle.note_name_for_freq(pitch_freq)
    var label: String = "%s %s" % [pitch_name, _slot_letter(position_in_group)]
    for i in _match_records.size():
        if str(_match_records[i].get("pitch_slot_label", "")) == label:
            return i
    var note_name: String = pitch_name
    for i in _match_records.size():
        var r: Dictionary = _match_records[i]
        if str(r.get("pitch_slot_label", "")) != "":
            continue
        if int(r.get("pitch_states", {}).get(note_name, 0)) == 1:
            r["pitch_slot_label"] = label
            return i
    _match_records.append(_new_match_record({"pitch_slot_label": label}))
    return _match_records.size() - 1


func _reconcile_unique_pitch_slot(record_idx: int, note_name: String) -> int:
    # _get_or_create_match_record_for_pitch_slot's "adopt an existing
    # confirmed record" path only runs at the moment a slot label is
    # FIRST created — if the Sort:Pitch tab was opened (creating a blank
    # placeholder record for e.g. "G4 A") before this star was ever
    # listened to, that placeholder is permanently locked in from then on
    # by the label-match lookup that always runs first, and this newly-
    # confirmed record never gets linked to it. Only safe to fix by
    # merging when this note has EXACTLY one star (_pitch_star_count==1):
    # for a shared note, the "A"/"B" slot lettering is arbitrary discovery
    # order with no way to tell which physical letter this specific star
    # belongs to from a single confirm alone — merging there would be
    # unsound. Called only from the Listen click handler (a deliberate,
    # low-frequency player action), never from the passive
    # _full_propagation_refresh path, so this is the one place in the
    # merge-vs-query tradeoff explored earlier where a merge is both safe
    # and necessary — there's no live-query equivalent that can make a
    # blank slot record's OWN star_idx exist.
    if _pitch_star_count(note_name) != 1:
        return record_idx
    var freq: float = _host._widgets._freq_for_note_name(note_name)
    if freq < 0.0:
        return record_idx
    var slot_idx: int = _get_or_create_match_record_for_pitch_slot(freq, 0)
    if slot_idx != record_idx:
        record_idx = await _merge_match_records(record_idx, slot_idx)
    return record_idx


func _get_or_create_match_record_for_name(name_str: String) -> int:
    var idx: int = _find_match_record_by_name(name_str)
    if idx >= 0:
        return idx
    _match_records.append(_new_match_record({"name": name_str}))
    return _match_records.size() - 1


func _get_or_create_match_record_for_seq(slot: int) -> int:
    var idx: int = _find_match_record_by_exact_seq(slot)
    if idx >= 0:
        return idx
    _match_records.append(_new_match_record({"seq_lo": slot, "seq_hi": slot}))
    return _match_records.size() - 1


func _get_or_create_match_record_for_star_idx(star_idx: int) -> int:
    var idx: int = _find_match_record_by_star_idx(star_idx)
    if idx >= 0:
        return idx
    _match_records.append(_new_match_record({"star_idx": star_idx}))
    return _match_records.size() - 1


func _get_or_create_match_record_for_degree_slot(degree: int, position_in_group: int) -> int:
    # Label carries the degree VALUE ("Conn3 A"), not a bare "Conn A". The
    # old format collided across groups: the degree-2 group's "A" slot and
    # the degree-3 group's "A" slot produced the identical string, so any
    # label-equality check treated two records for provably DIFFERENT stars
    # as the same slot — including _records_provably_identical's slot-label
    # branch, which would have merged them outright. Also what blocked
    # Degree from participating in group/member propagation at all, since
    # the group couldn't be identified from the label.
    var label: String = "Conn%d %s" % [degree, _slot_letter(position_in_group)]
    for i in _match_records.size():
        if str(_match_records[i].get("degree_slot_label", "")) == label:
            return i
    for i in _match_records.size():
        var r: Dictionary = _match_records[i]
        if str(r.get("degree_slot_label", "")) != "":
            continue
        if int(r.get("degree_states", {}).get(degree, 0)) == 1:
            r["degree_slot_label"] = label
            return i
    _match_records.append(_new_match_record({"degree_slot_label": label}))
    return _match_records.size() - 1


func _find_match_record_by_exact_seq(seq: int) -> int:
    for i in _match_records.size():
        var r: Dictionary = _match_records[i]
        if int(r["seq_lo"]) > 0 and int(r["seq_lo"]) == int(r["seq_hi"]) and int(r["seq_lo"]) == seq:
            return i
    return -1


func _find_match_record_by_star_idx(star_idx: int) -> int:
    if star_idx < 0:
        return -1
    for i in _match_records.size():
        if int(_match_records[i]["star_idx"]) == star_idx:
            return i
    return -1




## allow_await=false is for SYNCHRONOUS callers (currently
## _settle_identical_records, which runs inside the non-async
## _full_propagation_refresh). A coroutine suspended mid-merge would
## silently abandon the rest of the refresh, so in that mode this function
## refuses any merge that would need a conflict dialog and leaves the pair
## for the explicit commit paths, which can await properly.
##
## Two layers keep that honest: the _merge_conflict_kinds() check below —
## the SINGLE place conflicts are detected, shared with
## _records_have_merge_conflict() so the two can't drift — and a fail-safe
## `if not allow_await: return` at every dialog site, so a future conflict
## added without updating the kinds list degrades to an abandoned merge
## rather than a suspended refresh.
func _merge_match_records(target_idx: int, source_idx: int, allow_await: bool = true) -> int:
    if target_idx == source_idx:
        return target_idx
    if target_idx < 0 or target_idx >= _match_records.size() \
            or source_idx < 0 or source_idx >= _match_records.size():
        return target_idx
    if not allow_await and not _merge_conflict_kinds(target_idx, source_idx).is_empty():
        return target_idx
    var entry_generation: int = _match_records_generation
    var target: Dictionary = _match_records[target_idx]
    var source: Dictionary = _match_records[source_idx]

    # Tracks a name that lost the "Keep: X / Keep: Y" conflict below, so it can
    # be explicitly re-eliminated for the resolved star after its own record
    # gets deleted by this merge — otherwise that elimination is lost entirely
    # and the checklist row comes back up neutral next rebuild.
    var discarded_name: String = ""

    if target["name"] == "" and source["name"] != "":
        target["name"] = source["name"]
    elif target["name"] != "" and source["name"] != "" and target["name"] != source["name"]:
        # Fail-safe (see allow_await): unreachable while
        # _merge_conflict_kinds() lists every conflict below, and an
        # abandoned merge if it ever stops doing so — never a suspend.
        if not allow_await:
            return target_idx
        var kept_name: String = await _conflict_dialog_fn.call("name", target["name"], source["name"])
        discarded_name = source["name"] if kept_name == target["name"] else target["name"]
        target["name"] = kept_name

    # Intersect both sides' bounds (0 = unconstrained on that side) instead
    # of branching on seq_lo alone. The old branch only ever checked
    # seq_lo>0 to decide whether source had "real" sequence info — a
    # hi-only exclusive bound (seq_lo==0, seq_hi>0, e.g. "not the last
    # position") carries real information too, but was silently DROPPED
    # whenever it merged into a target with no lo of its own (neither
    # branch matched), and silently OVERWRITTEN by whichever side merged in
    # second otherwise — losing exactly the kind of fact
    # _records_provably_distinct's sequence check now depends on.
    var t_lo: int = int(target["seq_lo"])
    var t_hi: int = int(target["seq_hi"])
    var s_lo: int = int(source["seq_lo"])
    var s_hi: int = int(source["seq_hi"])
    var t_exact: bool = t_lo > 0 and t_lo == t_hi
    var s_exact: bool = s_lo > 0 and s_lo == s_hi
    if t_exact and s_exact and t_lo != s_lo:
        # Fail-safe (see allow_await): unreachable while
        # _merge_conflict_kinds() lists every conflict below, and an
        # abandoned merge if it ever stops doing so — never a suspend.
        if not allow_await:
            return target_idx
        var winning_seq: int = int(await _conflict_dialog_fn.call(
            "sequence position", str(t_lo), str(s_lo)))
        target["seq_lo"] = winning_seq
        target["seq_hi"] = winning_seq
    elif t_lo > 0 or t_hi > 0 or s_lo > 0 or s_hi > 0:
        var new_lo: int = max(t_lo, s_lo)
        var hi_candidates: Array = []
        if t_hi > 0: hi_candidates.append(t_hi)
        if s_hi > 0: hi_candidates.append(s_hi)
        var new_hi: int = hi_candidates.min() if not hi_candidates.is_empty() else 0
        if new_lo > 0 and new_hi > 0 and new_lo > new_hi:
            # The two partial bounds contradict once intersected (shouldn't
            # arise from sound player input) — keep target's own prior
            # bounds rather than write an inverted, meaningless range.
            new_lo = t_lo
            new_hi = t_hi
        target["seq_lo"] = new_lo
        target["seq_hi"] = new_hi

    var target_cand: Array = target.get("seq_candidates", [])
    var source_cand: Array = source.get("seq_candidates", [])
    if target_cand.is_empty() and not source_cand.is_empty():
        target["seq_candidates"] = source_cand.duplicate()
    elif not target_cand.is_empty() and not source_cand.is_empty():
        var merged_cand: Array = []
        for v in target_cand:
            if source_cand.has(v):
                merged_cand.append(v)
        target["seq_candidates"] = merged_cand

    # Same conflict-detection shape as the pitch merge just below — two
    # DIFFERENT hard-confirmed colors on either side of a merge is a real
    # contradiction, not something a blind key-by-key union should paper
    # over. This was missing here even though the pitch logic right below
    # already did it correctly — exactly the same failure class as the
    # star-identity/color bug already fixed elsewhere in this file.
    var target_confirmed_color: int = -1
    for ck0 in target["color_states"]:
        if int(target["color_states"][ck0]) == 1:
            target_confirmed_color = int(ck0)
            break
    var source_confirmed_color: int = -1
    for ck1 in source["color_states"]:
        if int(source["color_states"][ck1]) == 1:
            source_confirmed_color = int(ck1)
            break
    if target_confirmed_color >= 0 and source_confirmed_color >= 0 and target_confirmed_color != source_confirmed_color:
        # Fail-safe (see allow_await): unreachable while
        # _merge_conflict_kinds() lists every conflict below, and an
        # abandoned merge if it ever stops doing so — never a suspend.
        if not allow_await:
            return target_idx
        var winning_color: String = await _conflict_dialog_fn.call(
            "confirmed color", _host.COLOR_NAME_LABELS[target_confirmed_color], _host.COLOR_NAME_LABELS[source_confirmed_color])
        if winning_color == _host.COLOR_NAME_LABELS[source_confirmed_color]:
            target["color_states"][target_confirmed_color] = 0
            target_confirmed_color = source_confirmed_color
        else:
            source["color_states"][source_confirmed_color] = 0
            source_confirmed_color = -1

    for ck in source["color_states"]:
        var sv: int = int(source["color_states"][ck])
        var tv: int = int(target["color_states"].get(ck, 0))
        if int(ck) == source_confirmed_color and target_confirmed_color >= 0 and int(ck) != target_confirmed_color:
            continue
        if sv == 1 or tv == 1:
            target["color_states"][ck] = 1
        elif sv == 2 or tv == 2:
            target["color_states"][ck] = 2

    # Same fix, degree axis.
    var target_confirmed_degree: int = -1
    for dk0 in target["degree_states"]:
        if int(target["degree_states"][dk0]) == 1:
            target_confirmed_degree = int(dk0)
            break
    var source_confirmed_degree: int = -1
    for dk1 in source["degree_states"]:
        if int(source["degree_states"][dk1]) == 1:
            source_confirmed_degree = int(dk1)
            break
    if target_confirmed_degree >= 0 and source_confirmed_degree >= 0 and target_confirmed_degree != source_confirmed_degree:
        # Fail-safe (see allow_await): unreachable while
        # _merge_conflict_kinds() lists every conflict below, and an
        # abandoned merge if it ever stops doing so — never a suspend.
        if not allow_await:
            return target_idx
        var winning_degree: String = await _conflict_dialog_fn.call(
            "confirmed degree", str(target_confirmed_degree), str(source_confirmed_degree))
        if winning_degree == str(source_confirmed_degree):
            target["degree_states"][target_confirmed_degree] = 0
            target_confirmed_degree = source_confirmed_degree
        else:
            source["degree_states"][source_confirmed_degree] = 0
            source_confirmed_degree = -1

    for dk in source["degree_states"]:
        var sv_d: int = int(source["degree_states"][dk])
        var tv_d: int = int(target["degree_states"].get(dk, 0))
        if int(dk) == source_confirmed_degree and target_confirmed_degree >= 0 and int(dk) != target_confirmed_degree:
            continue
        if sv_d == 1 or tv_d == 1:
            target["degree_states"][dk] = 1
        elif sv_d == 2 or tv_d == 2:
            target["degree_states"][dk] = 2

    var target_confirmed_note: String = ""
    for pk0 in target["pitch_states"]:
        if int(target["pitch_states"][pk0]) == 1:
            target_confirmed_note = str(pk0)
            break
    var source_confirmed_note: String = ""
    for pk1 in source["pitch_states"]:
        if int(source["pitch_states"][pk1]) == 1:
            source_confirmed_note = str(pk1)
            break
    if target_confirmed_note != "" and source_confirmed_note != "" and target_confirmed_note != source_confirmed_note:
        # Fail-safe (see allow_await): unreachable while
        # _merge_conflict_kinds() lists every conflict below, and an
        # abandoned merge if it ever stops doing so — never a suspend.
        if not allow_await:
            return target_idx
        var winning_note: String = await _conflict_dialog_fn.call(
            "confirmed pitch", target_confirmed_note, source_confirmed_note)
        if winning_note == source_confirmed_note:
            target["pitch_states"][target_confirmed_note] = 0
            target_confirmed_note = source_confirmed_note
        else:
            source["pitch_states"][source_confirmed_note] = 0
            source_confirmed_note = ""

    for pk in source["pitch_states"]:
        var sv2: int = int(source["pitch_states"][pk])
        var tv2: int = int(target["pitch_states"].get(pk, 0))
        if pk == source_confirmed_note and target_confirmed_note != "" and pk != target_confirmed_note:
            continue
        if sv2 == 1 or tv2 == 1:
            target["pitch_states"][pk] = 1
        elif sv2 == 2 or tv2 == 2:
            target["pitch_states"][pk] = 2

    if bool(source.get("pitch_revealed", false)):
        target["pitch_revealed"] = true

    var target_elim: Dictionary = target.get("star_elim", {})
    var source_elim: Dictionary = source.get("star_elim", {})
    for sk in source_elim:
        var sv3: int = int(source_elim[sk])
        var tv3: int = int(target_elim.get(sk, 0))
        if sv3 == 1 or tv3 == 1:
            target_elim[sk] = 1
        elif sv3 == 2 or tv3 == 2:
            target_elim[sk] = 2
    target["star_elim"] = target_elim

    # source gets deleted at the end of this function — anything not copied
    # over here is gone for good. name_states was being silently dropped
    # (union merge, same shape as star_elim above — a genuinely conflicting
    # pair of confirmed names is already caught by the "name" field's own
    # dialog-protected merge near the top of this function, so this doesn't
    # need its own dialog). The three protected_* dicts are just "still
    # possible" cosmetic hints, not hard facts, so a plain union is enough.
    var target_name_states: Dictionary = target.get("name_states", {})
    var source_name_states: Dictionary = source.get("name_states", {})
    for nk in source_name_states:
        var snv: int = int(source_name_states[nk])
        var tnv: int = int(target_name_states.get(nk, 0))
        if snv == 1 or tnv == 1:
            target_name_states[nk] = 1
        elif snv == 2 or tnv == 2:
            target_name_states[nk] = 2
    target["name_states"] = target_name_states

    for protect_key in ["protected_pitch_notes", "protected_color_idxs", "protected_staff_names", "manual_name_blocks", "manual_pitch_blocks", "manual_color_blocks"]:
        var target_protect: Dictionary = target.get(protect_key, {})
        var source_protect: Dictionary = source.get(protect_key, {})
        for pk in source_protect:
            target_protect[pk] = true
        target[protect_key] = target_protect

    if int(target["star_idx"]) < 0 and int(source["star_idx"]) >= 0:
        target["star_idx"] = source["star_idx"]

    var target_label: String = str(target.get("color_slot_label", ""))
    var source_label: String = str(source.get("color_slot_label", ""))
    if target_label == "" and source_label != "":
        target["color_slot_label"] = source_label
    elif target_label != "" and source_label != "" and target_label != source_label:
        # Fail-safe (see allow_await): unreachable while
        # _merge_conflict_kinds() lists every conflict below, and an
        # abandoned merge if it ever stops doing so — never a suspend.
        if not allow_await:
            return target_idx
        target["color_slot_label"] = await _conflict_dialog_fn.call("color slot label", target_label, source_label)

    var target_pitch_label: String = str(target.get("pitch_slot_label", ""))
    var source_pitch_label: String = str(source.get("pitch_slot_label", ""))
    if target_pitch_label == "" and source_pitch_label != "":
        target["pitch_slot_label"] = source_pitch_label
    elif target_pitch_label != "" and source_pitch_label != "" and target_pitch_label != source_pitch_label:
        # Fail-safe (see allow_await): unreachable while
        # _merge_conflict_kinds() lists every conflict below, and an
        # abandoned merge if it ever stops doing so — never a suspend.
        if not allow_await:
            return target_idx
        target["pitch_slot_label"] = await _conflict_dialog_fn.call("pitch slot label", target_pitch_label, source_pitch_label)

    var target_degree_label: String = str(target.get("degree_slot_label", ""))
    var source_degree_label: String = str(source.get("degree_slot_label", ""))
    if target_degree_label == "" and source_degree_label != "":
        target["degree_slot_label"] = source_degree_label
    elif target_degree_label != "" and source_degree_label != "" and target_degree_label != source_degree_label:
        # Fail-safe (see allow_await): unreachable while
        # _merge_conflict_kinds() lists every conflict below, and an
        # abandoned merge if it ever stops doing so — never a suspend.
        if not allow_await:
            return target_idx
        target["degree_slot_label"] = await _conflict_dialog_fn.call("degree slot label", target_degree_label, source_degree_label)

    # _match_records may have been cleared/rebuilt by one of the awaits
    # above (see _match_records_generation's own comment) — target_idx/
    # source_idx and the target/source Dictionary references could now
    # point at nothing, or at unrelated records in a freshly-rebuilt
    # array. Abort here rather than let remove_at()/the bracket-indexing
    # below act on stale indices.
    if _match_records_generation != entry_generation:
        return target_idx

    _sync_color_states_from_star_idx(target_idx)
    # color_states just got unioned from two records (or resynced from
    # ground truth above) — recompute rather than trying to merge the two
    # sides' color_star_elim_marks by hand; a no-op if star_idx is now
    # resolved, since _sync_color_states_from_star_idx already owns that case.
    _recompute_color_star_elim(target_idx)

    _match_records.remove_at(source_idx)
    if source_idx < target_idx:
        target_idx -= 1

    # The name that lost the conflict above no longer has any record of its own —
    # whichever side it came from was just deleted. Re-create a blank record for
    # it now and immediately mark it eliminated for the star this merged record
    # ended up representing, so the checklist row stays darkened instead of
    # reverting to a fresh, unmarked neutral candidate on the next rebuild.
    if discarded_name != "" and int(_match_records[target_idx]["star_idx"]) >= 0:
        var resolved_star: int = int(_match_records[target_idx]["star_idx"])
        var loser_record_idx: int = _get_or_create_match_record_for_name(discarded_name)
        if loser_record_idx != target_idx:
            var loser_elim: Dictionary = _match_records[loser_record_idx].get("star_elim", {})
            loser_elim[resolved_star] = 2
            _match_records[loser_record_idx]["star_elim"] = loser_elim

    return target_idx


func _confirm_match_record_identity(record_idx: int, star_idx: int, star_name: String) -> int:
    if record_idx < 0 or record_idx >= _match_records.size():
        return -1  # callers already treat a negative return as "abort"
    # See _match_records_generation's comment — this function holds
    # record_idx/Dictionary references across three separate awaits
    # (including one that calls _merge_match_records, which does its own
    # rebuild-during-await work). Checked after each one below.
    var entry_generation: int = _match_records_generation
    # Color contradiction check FIRST, before any merge — every star widget
    # auto-creates a blank star_idx-bound record just by rendering, so the
    # merge below runs almost every time a name gets confirmed onto a star.
    # _merge_match_records ends with its own unconditional
    # _sync_color_states_from_star_idx(target_idx) call, which silently
    # resyncs color_states from star_idx — checking for a contradiction
    # AFTER that merge would just find the record already rewritten to
    # agree with itself. Ground truth (_host._star_colors) doesn't need the
    # record to have merged anything first, so this check can and must run
    # before the merge touches anything.
    var true_color: int = clamp(_host._star_colors[star_idx] if star_idx < _host._star_colors.size() else 1, 0, 3)
    var r0: Dictionary = _match_records[record_idx]
    var prior_confirmed_color: int = -1
    for ci in _host.COLOR_NAME_LABELS.size():
        if int(r0["color_states"].get(ci, 0)) == 1:
            prior_confirmed_color = ci
            break
    if prior_confirmed_color >= 0 and prior_confirmed_color != true_color:
        var old_color_label: String = "%s (previous)" % _host.COLOR_NAME_LABELS[prior_confirmed_color]
        var new_color_label: String = "%s (%s's true color)" % [_host.COLOR_NAME_LABELS[true_color], star_name]
        var color_winner: String = await _conflict_dialog_fn.call(
            "color for '%s'" % star_name, old_color_label, new_color_label)
        if color_winner == old_color_label:
            return -1
        if _match_records_generation != entry_generation:
            return -1

    var existing_by_star: int = _find_match_record_by_star_idx(star_idx)
    if existing_by_star >= 0 and existing_by_star != record_idx:
        record_idx = await _merge_match_records(record_idx, existing_by_star)
        if _match_records_generation != entry_generation \
                or record_idx < 0 or record_idx >= _match_records.size():
            return -1

    var r: Dictionary = _match_records[record_idx]
    if int(r["star_idx"]) >= 0 and int(r["star_idx"]) != star_idx:
        var old_label: String = "%s (current)" % _anonymous_star_label(int(r["star_idx"]))
        var new_label: String = "%s (just checked)" % _anonymous_star_label(star_idx)
        var winner: String = await _conflict_dialog_fn.call(
            "star identity for '%s'" % star_name, old_label, new_label)
        if winner == old_label:
            return -1
        if _match_records_generation != entry_generation:
            return -1

    if str(r["name"]) == "":
        r["name"] = star_name
    r["star_idx"] = star_idx
    _sync_color_states_from_star_idx(record_idx)

    var elim: Dictionary = r.get("star_elim", {})
    for j in _host._star_count:
        elim[j] = 1 if j == star_idx else 2
    r["star_elim"] = elim

    return record_idx


func _save_match_records() -> Array:
    # Deep-copies whatever the record actually holds instead of restating
    # the field list a third time. The old per-field version had to be kept
    # in sync with _new_match_record() and _load_match_records() by hand,
    # and a field missing from THIS list was written to disk as gone —
    # silent, and invisible until the next load. Values are already
    # correctly typed in memory (creation goes through _new_match_record,
    # load coerces on the way in), so no per-field coercion is needed here;
    # the int-key-becomes-String hazard of a JSON round-trip is handled on
    # the load side by _coerce_int_key, which is where it actually happens.
    var out: Array = []
    for r in _match_records:
        out.append((r as Dictionary).duplicate(true))
    return out


func _load_match_records(data: Array) -> void:
    _match_records.clear()
    _match_records_generation += 1
    _clear_deduction_caches()
    for entry in data:
        if not entry is Dictionary:
            continue
        var e: Dictionary = entry

        var raw_color_states: Dictionary = _coerce_dict(e.get("color_states"), {})
        var color_states: Dictionary = {}
        for ck in raw_color_states:
            var color_idx: int = _coerce_int_key(ck, -1)
            # Unlike pitch/name/degree_states (string or open-ended int keys,
            # never used to index a fixed-size array), color_states keys DO
            # get bracket-indexed straight into the 4-entry COLOR_NAME_LABELS/
            # STAR_COLORS_BY_IDX arrays elsewhere (_display_color_for_record,
            # _merge_match_records) with no bounds check at the read site —
            # a corrupted/hand-edited save with an out-of-range key would
            # crash there. Dropped here rather than clamped: clamping a KEY
            # (unlike clamping a scalar value elsewhere in this file) risks
            # silently colliding with — and overwriting — a different,
            # already-valid color's real state.
            if color_idx < 0 or color_idx >= _host.COLOR_NAME_LABELS.size():
                continue
            color_states[color_idx] = _coerce_int(raw_color_states[ck], 0)

        var raw_pitch_states: Dictionary = _coerce_dict(e.get("pitch_states"), {})
        var pitch_states: Dictionary = {}
        for pk in raw_pitch_states:
            pitch_states[str(pk)] = _coerce_int(raw_pitch_states[pk], 0)

        var raw_star_elim: Dictionary = _coerce_dict(e.get("star_elim"), {})
        var star_elim: Dictionary = {}
        for sk in raw_star_elim:
            var star_key: int = _coerce_int_key(sk, -1)
            if star_key < 0:
                continue
            star_elim[star_key] = _coerce_int(raw_star_elim[sk], 0)

        var color_star_elim_marks: Dictionary = {}
        for csk in _coerce_dict(e.get("color_star_elim_marks"), {}):
            var elim_star_key: int = _coerce_int_key(csk, -1)
            if elim_star_key < 0:
                continue
            color_star_elim_marks[elim_star_key] = true

        var raw_name_states: Dictionary = _coerce_dict(e.get("name_states"), {})
        var name_states: Dictionary = {}
        for nk in raw_name_states:
            name_states[str(nk)] = _coerce_int(raw_name_states[nk], 0)

        var manual_name_blocks: Dictionary = {}
        for mnk in _coerce_dict(e.get("manual_name_blocks"), {}):
            manual_name_blocks[str(mnk)] = true

        var manual_pitch_blocks: Dictionary = {}
        for mpk in _coerce_dict(e.get("manual_pitch_blocks"), {}):
            manual_pitch_blocks[str(mpk)] = true

        var manual_color_blocks: Dictionary = {}
        for mck in _coerce_dict(e.get("manual_color_blocks"), {}):
            var mc_idx: int = _coerce_int_key(mck, -1)
            if mc_idx < 0 or mc_idx >= _host.COLOR_NAME_LABELS.size():
                continue
            manual_color_blocks[mc_idx] = true

        var raw_degree_states: Dictionary = _coerce_dict(e.get("degree_states"), {})
        var degree_states: Dictionary = {}
        for dk in raw_degree_states:
            var degree_key: int = _coerce_int_key(dk, -1)
            if degree_key < 0:
                continue
            degree_states[degree_key] = _coerce_int(raw_degree_states[dk], 0)

        var protected_pitch_notes: Dictionary = {}
        for ppk in _coerce_dict(e.get("protected_pitch_notes"), {}):
            protected_pitch_notes[str(ppk)] = true

        var protected_color_idxs: Dictionary = {}
        for pck in _coerce_dict(e.get("protected_color_idxs"), {}):
            var pc_idx: int = _coerce_int_key(pck, -1)
            if pc_idx < 0 or pc_idx >= _host.COLOR_NAME_LABELS.size():
                continue
            protected_color_idxs[pc_idx] = true

        var protected_staff_names: Dictionary = {}
        for psnk in _coerce_dict(e.get("protected_staff_names"), {}):
            protected_staff_names[str(psnk)] = true

        var seq_candidates: Array = []
        for v in _coerce_array(e.get("seq_candidates"), []):
            seq_candidates.append(_coerce_int(v, 0))

        # Built on _new_match_record() rather than as its own literal, so a
        # save written before some field existed comes back carrying that
        # field's current default instead of missing it entirely — and so
        # adding a field never again means remembering to edit this list.
        _match_records.append(_new_match_record({
            "name": str(e.get("name", "")),
            "seq_lo": _coerce_int(e.get("seq_lo"), 0), "seq_hi": _coerce_int(e.get("seq_hi"), 0),
            "seq_candidates": seq_candidates,
            "color_states": color_states,
            "pitch_states": pitch_states,
            "degree_states": degree_states,
            "name_states": name_states,
            "manual_name_blocks": manual_name_blocks,
            "manual_pitch_blocks": manual_pitch_blocks,
            "manual_color_blocks": manual_color_blocks,
            "protected_pitch_notes": protected_pitch_notes,
            "protected_color_idxs": protected_color_idxs,
            "protected_staff_names": protected_staff_names,
            "pitch_revealed": _coerce_bool(e.get("pitch_revealed"), false),
            "star_elim": star_elim,
            "color_star_elim_marks": color_star_elim_marks,
            "star_idx": _coerce_int(e.get("star_idx"), -1),
            "color_slot_label": str(e.get("color_slot_label", "")),
            "pitch_slot_label": str(e.get("pitch_slot_label", "")),
            "degree_slot_label": str(e.get("degree_slot_label", "")),
        }))


func _display_color_for_record(record_idx: int) -> Color:
    if record_idx < 0 or record_idx >= _match_records.size():
        return STATE_COLORS.unresolved_fallback
    var r: Dictionary = _match_records[record_idx]
    for ck in r["color_states"]:
        if int(r["color_states"][ck]) == 1:
            return _host.STAR_COLORS_BY_IDX[int(ck)]
    return STATE_COLORS.unresolved_fallback


## TEMPORARY DIAGNOSTIC (added 2026-08-07, remove once the Staff-popup ->
## Sort:Pitch report is resolved). Dumps every match record that touches a
## given note, plus the ground truth needed to interpret them, so the
## actual in-game state can be compared against what the headless repro
## produces — six scenarios of that repro pass, so the trigger is something
## about live state rather than the linkage logic itself.
## Bound to SHIFT+D in constellation_study_overlay.gd's _input().
func _debug_dump_pitch_records(note_name: String) -> void:
    print("")
    print("========= PITCH RECORD DUMP: '%s' =========" % note_name)
    print("  incidence (_pitch_star_count) = %d   [1 = singleton, linkage expected]"
        % _pitch_star_count(note_name))
    var carriers: Array = []
    for s in _host._star_count:
        if _host._widgets._note_name_for_star(s) == note_name:
            carriers.append(s)
    print("  stars actually carrying it   = %s" % str(carriers))
    for s2 in carriers:
        print("    star %d: name='%s' colour=%d degree=%d true_rank(1-based)=%d" % [
            int(s2),
            str(_host._star_names[int(s2)]) if int(s2) < _host._star_names.size() else "?",
            int(_host._star_colors[int(s2)]) if int(s2) < _host._star_colors.size() else -1,
            int(_host._star_degrees[int(s2)]) if int(s2) < _host._star_degrees.size() else -1,
            (int(_host._pitch_rank_solution[int(s2)]) + 1) if int(s2) < _host._pitch_rank_solution.size() else -1,
        ])
    print("  --- records mentioning this note ---")
    var shown: int = 0
    for i in _match_records.size():
        var r: Dictionary = _match_records[i]
        var raw: int = int((r.get("pitch_states", {}) as Dictionary).get(note_name, 0))
        var eff: int = _effective_pitch_state(i, note_name)
        var label: String = str(r.get("pitch_slot_label", ""))
        # Only the interesting ones: anything asserting/denying this note,
        # anything wearing its slot label, and anything pinned to a carrier.
        if raw == 0 and eff == 0 and label == "" and not carriers.has(int(r.get("star_idx", -1))):
            continue
        shown += 1
        print("    [%d] name='%s' star_idx=%d seq=%d..%d cand=%s" % [
            i, str(r.get("name", "")), int(r.get("star_idx", -1)),
            int(r.get("seq_lo", 0)), int(r.get("seq_hi", 0)),
            str(r.get("seq_candidates", []))])
        print("         raw_pitch=%d effective_pitch=%d pitch_revealed=%s" % [
            raw, eff, str(bool(r.get("pitch_revealed", false)))])
        print("         labels: pitch='%s' colour='%s' degree='%s'" % [
            label, str(r.get("color_slot_label", "")), str(r.get("degree_slot_label", ""))])
        print("         stub?=%s  candidate_stars=%s" % [
            str(_record_is_unconfirmed_star_widget_stub(i)),
            str(_candidate_stars_for_record(i))])
    if shown == 0:
        print("    (no record mentions this note at all)")
    # Why any two of them did or didn't unify — the actual question.
    print("  --- pairwise identity/conflict among those records ---")
    for i2 in _match_records.size():
        for j2 in range(i2 + 1, _match_records.size()):
            var same: bool = _records_provably_identical(i2, j2)
            var distinct: bool = _records_provably_distinct(i2, j2)
            if not same and not distinct:
                continue
            print("    [%d]x[%d] identical=%s distinct=%s conflicts=%s" % [
                i2, j2, str(same), str(distinct), str(_merge_conflict_kinds(i2, j2))])
    print("=========================================")
    print("")


func _debug_dump_named_records() -> void:
    for watch_name in ["Eosaara", "Pyrios"]:
        var idx: int = _find_match_record_by_name(watch_name)
        if idx < 0:
            print("[DEBUG] record for '%s': NOT FOUND" % watch_name)
            continue
        var r: Dictionary = _match_records[idx]
        print("[DEBUG] record for '%s': star_idx=%d color_slot_label='%s' color_states=%s" %
            [watch_name, int(r.get("star_idx", -1)), str(r.get("color_slot_label", "")), str(r.get("color_states", {}))])




func _confirm_color_against_ground_truth(record_idx: int, color_idx: int, asserting_true: bool) -> bool:
    if record_idx < 0 or record_idx >= _match_records.size():
        return false  # matches this function's own "false means abort" contract
    # Returns false if the caller should abort. Only meaningful once
    # star_idx is resolved to real ground truth (_host._star_colors) — before
    # that there's nothing to check against. This is what catches a
    # misclick on a Sort:tab or staff-popup color button overwriting a
    # color that's already pinned by a resolved star identity — same
    # failure class as the star-identity confirm bug fixed elsewhere in
    # this file, just reachable directly instead of through a merge.
    var r: Dictionary = _match_records[record_idx]
    var star_idx: int = int(r.get("star_idx", -1))
    if star_idx < 0 or star_idx >= _host._star_colors.size():
        return true
    var true_color: int = clamp(_host._star_colors[star_idx], 0, 3)
    var contradicts: bool = (asserting_true and color_idx != true_color) or (not asserting_true and color_idx == true_color)
    if not contradicts:
        return true
    var claim: String = "%s (your click)" % _host.COLOR_NAME_LABELS[color_idx]
    var truth: String = "%s (this star's true color)" % _host.COLOR_NAME_LABELS[true_color]
    var winner: String = await _conflict_dialog_fn.call("color for this star", claim, truth)
    return winner == claim


func _color_star_count(color_idx: int) -> int:
    var count: int = 0
    for s in _host._star_count:
        var sc: int = _host._star_colors[s] if s < _host._star_colors.size() else 1
        if sc == color_idx:
            count += 1
    return count


func _degree_star_count(degree: int) -> int:
    # Same shape as _color_star_count/_pitch_star_count, keyed by Degree
    # (per-star connection count) — gates _compute_excluded_degrees_for the
    # same way, since a degree value is only safe to exclude elsewhere when
    # exactly one star has it.
    var count: int = 0
    for s in _host._star_count:
        var d: int = int(_host._star_degrees[s]) if s < _host._star_degrees.size() else 0
        if d == degree:
            count += 1
    return count


func _pitch_star_count(note_name: String) -> int:
    # Same shape as _color_star_count, keyed by note name instead of color
    # index — ground-truth incidence count, used to gate
    # _compute_excluded_pitches_for below (a note can have more than one
    # star, unlike Sequence/Name, so exclusion is only sound when exactly
    # one star has it). Also the canonical version of the incidence-count
    # loop widgets.gd previously duplicated inline in two places.
    var count: int = 0
    for s in _host._star_count:
        if s >= _host._star_pitch_index.size():
            continue
        var p: int = int(_host._star_pitch_index[s])
        if p < 0 or p >= _host._pitch_freqs.size():
            continue
        if ConstellationLogicPuzzle.note_name_for_freq(_host._pitch_freqs[p]) == note_name:
            count += 1
    return count


func _confirm_color_against_cap(record_idx: int, color_idx: int) -> bool:
    # ADDED 2026-07-27 — color has a fixed, always-visible ground-truth
    # count per constellation (e.g. exactly 4 Blue stars, from the star map
    # the player can already see). _confirm_color_against_ground_truth above
    # only catches a contradiction once THIS record's own star identity is
    # resolved (star_idx >= 0) — but most Sort:tab records don't have one
    # yet during normal solving, so nothing else stopped more records than
    # actually exist from independently confirming the same color (found via
    # playtesting: 5+ records confirmed Blue when only 4 stars are Blue).
    # This catches that broader, cross-record case.
    var cap: int = _color_star_count(color_idx)
    var already_confirmed: int = 0
    for i in _match_records.size():
        if i == record_idx:
            continue
        if int(_match_records[i].get("color_states", {}).get(color_idx, 0)) == 1:
            already_confirmed += 1
    if already_confirmed < cap:
        return true
    var color_name: String = _host.COLOR_NAME_LABELS[color_idx]
    var claim: String = "%s here (your click)" % color_name
    var truth: String = "the existing %d confirmed elsewhere (the max for this constellation)" % already_confirmed
    var winner: String = await _conflict_dialog_fn.call("color count for this constellation", claim, truth)
    return winner == claim


func _propagate_color_confirmed_same_record(record_idx: int, confirmed_color_idx: int) -> void:
    if record_idx < 0 or record_idx >= _match_records.size():
        return
    # Confirming one color on a record means every OTHER color is
    # automatically eliminated on that SAME record — a slot/name/star can
    # only be one color.
    var r: Dictionary = _match_records[record_idx]
    for ci in _host.COLOR_NAME_LABELS.size():
        if ci != confirmed_color_idx:
            r["color_states"][ci] = 2
    # A confirm supersedes any earlier manual X on the same color — see the
    # matching comment in _propagate_pitch_confirmed_same_record.
    var manual_color: Dictionary = r.get("manual_color_blocks", {})
    if manual_color.has(confirmed_color_idx):
        manual_color.erase(confirmed_color_idx)
        r["manual_color_blocks"] = manual_color
    # Same staleness fix as _sync_color_states_from_star_idx: a
    # color_slot_label naming a DIFFERENT color than what was just
    # confirmed is now wrong and would leave that slot's Sort:Color row
    # pointing at a record that no longer belongs there.
    var label: String = str(r.get("color_slot_label", ""))
    if label != "" and not label.begins_with(_host.COLOR_NAME_LABELS[confirmed_color_idx]):
        r["color_slot_label"] = ""






func _propagate_degree_confirmed_same_record(record_idx: int, confirmed_degree: int) -> void:
    if record_idx < 0 or record_idx >= _match_records.size():
        return
    # Same rule as color/pitch: confirming one degree value means every
    # OTHER possible degree is eliminated on that SAME record. Degree had
    # no equivalent to _propagate_color_confirmed_same_record/
    # _propagate_pitch_confirmed_same_record before this — two different
    # degrees could end up simultaneously marked confirmed on one record.
    var r: Dictionary = _match_records[record_idx]
    var degree_states: Dictionary = r.get("degree_states", {})
    var degrees_set: Dictionary = {}
    for i in _host._star_count:
        degrees_set[int(_host._star_degrees[i]) if i < _host._star_degrees.size() else 0] = true
    for deg in degrees_set.keys():
        if int(deg) != confirmed_degree:
            degree_states[deg] = 2
    degree_states[confirmed_degree] = 1
    r["degree_states"] = degree_states


func _propagate_name_states_confirmed_same_record(record_idx: int, confirmed_name: String) -> void:
    if record_idx < 0 or record_idx >= _match_records.size():
        return
    # Same rule as color/pitch/degree: confirming one name on a record
    # means every OTHER name is eliminated on that SAME record. This is
    # the record-level name_states field (staff popup NAME section, Sort:tab
    # name checklist popup) — distinct from _propagate_name_confirmed,
    # which is the unrelated star_elim mechanism for binding a name to a
    # star. name_states never got sibling-clearing when color/pitch/degree
    # did — confirming a name here previously left every other name sitting
    # at neutral instead of showing eliminated.
    var r: Dictionary = _match_records[record_idx]
    var name_states: Dictionary = r.get("name_states", {})
    for n in _host._star_names:
        var name_str: String = str(n)
        if name_str != confirmed_name:
            name_states[name_str] = 2
    name_states[confirmed_name] = 1
    r["name_states"] = name_states
    # A confirm supersedes any earlier manual X on the same name — see the
    # matching comment in _propagate_pitch_confirmed_same_record.
    var manual_name: Dictionary = r.get("manual_name_blocks", {})
    if manual_name.has(confirmed_name):
        manual_name.erase(confirmed_name)
        r["manual_name_blocks"] = manual_name

    # Promote into the real identity field (r["name"]), same reasoning as
    # _settle_singleton_sequences promoting a narrowed-to-one Sequence
    # range into seq_lo==seq_hi. Without this, every caller of this
    # function (_on_staff_name_check, _on_slot_name_check, and this file's
    # own _settle_singleton_names) only ever wrote name_states — never
    # r["name"], the ONLY field _find_match_record_by_name/
    # _get_or_create_match_record_for_name ever look at. Checking a name
    # off via the Staff popup or the NameChecklistPopup therefore never
    # linked that record to the one the Sort:Name tab creates/reuses for
    # the same name — two permanently separate records for the same star,
    # exactly the same failure shape as the Sequence propagation bug this
    # file's _records_provably_distinct fix addressed, just on the write
    # side instead of the read side. Skips promotion (same rule
    # _settle_singleton_sequences already uses) when a DIFFERENT record
    # already owns this name — a real contradiction needing a conflict
    # dialog, which this function can't await; it surfaces on the next
    # explicit Sort:Name-tab interaction with that name instead.
    if str(r.get("name", "")) == "":
        var existing_idx: int = _find_match_record_by_name(confirmed_name)
        if existing_idx < 0 or existing_idx == record_idx:
            r["name"] = confirmed_name



func _compressed_possible_positions_str(record_idx: int) -> String:
    var candidates: Array = _effective_seq_candidates(record_idx)
    if candidates.is_empty():
        return ""
    if candidates.size() == _host._star_count:
        return ""
    candidates.sort()
    if candidates.size() == 1:
        return str(candidates[0])

    var segments: Array = []
    var seg_start: int = candidates[0]
    var prev: int = candidates[0]
    for idx in range(1, candidates.size()):
        var c: int = candidates[idx]
        if c == prev + 1:
            prev = c
        else:
            segments.append([seg_start, prev])
            seg_start = c
            prev = c
    segments.append([seg_start, prev])

    var parts: Array = []
    for seg in segments:
        parts.append(str(seg[0]) if seg[0] == seg[1] else "%d-%d" % [seg[0], seg[1]])
    return ",".join(parts)




func _effective_color_state(record_idx: int, color_idx: int) -> int:
    if record_idx < 0 or record_idx >= _match_records.size():
        return 0
    # Four sources of "known color" for a record, checked in order of
    # certainty: ground-truth visible color (star-anchored), the slot label
    # itself (a "Blue A" row is structurally Blue even though nothing ever
    # writes that into color_states), the player's raw toggled state, and —
    # same fold-in as _effective_pitch_state, see that function's comment —
    # the staff popup's right-click "still possible" protect set, so a
    # narrowed color set can also prove cross-record distinctness.
    var r: Dictionary = _match_records[record_idx]
    var star_idx: int = int(r.get("star_idx", -1))
    if star_idx >= 0:
        var true_color: int = _host._star_colors[star_idx] if star_idx < _host._star_colors.size() else -1
        return 1 if true_color == color_idx else 2

    var label: String = str(r.get("color_slot_label", ""))
    if label != "":
        var label_color: int = _host.COLOR_NAME_LABELS.find(label.get_slice(" ", 0))
        if label_color >= 0:
            return 1 if label_color == color_idx else 2

    var derived: int = _record_effective_state(record_idx, "color_states", "protected_color_idxs", color_idx)
    match derived:
        3: return 2   # soft-eliminated (a sibling color is protected) counts as eliminated
        4: return 0   # protected ("still possible") is not a confirmation — stays neutral
        _: return derived


func _effective_pitch_state(record_idx: int, note_name: String) -> int:
    if record_idx < 0 or record_idx >= _match_records.size():
        return 0
    # Same three tiers as _effective_color_state (ground truth, slot label,
    # raw toggled state), plus a fourth: the staff popup's right-click
    # "still possible" protect set. Narrowing that set to a few notes is the
    # player asserting "every other note is eliminated for this record" —
    # folding the *derived* soft-eliminated/protected states in here (rather
    # than writing them into the real, right-click-guarded pitch_states
    # dict) is what lets that assertion prove cross-record distinctness
    # without the right-click guard locking out the very next note the
    # player wants to also mark "still possible" the moment the first click
    # would otherwise hard-eliminate everything else.
    var r: Dictionary = _match_records[record_idx]
    var star_idx: int = int(r.get("star_idx", -1))
    if star_idx >= 0:
        var true_note: String = _host._widgets._note_name_for_star(star_idx)
        return 1 if true_note == note_name else 2

    var label: String = str(r.get("pitch_slot_label", ""))
    if label != "":
        var label_note: String = label.get_slice(" ", 0)
        return 1 if label_note == note_name else 2

    var derived: int = _record_effective_state(record_idx, "pitch_states", "protected_pitch_notes", note_name)
    match derived:
        3: return 2   # soft-eliminated (a sibling note is protected) counts as eliminated
        4: return 0   # protected ("still possible") is not a confirmation — stays neutral
        _: return derived


func _effective_name_state(record_idx: int, name_str: String) -> int:
    if record_idx < 0 or record_idx >= _match_records.size():
        return 0
    # Deliberately does NOT shortcut via star_idx the way
    # _effective_pitch_state/_effective_color_state do (see those
    # functions) — a record's star_idx gets set by things that are NOT a
    # legitimate name confirmation: _build_star_widgets_impl() auto-
    # creates a star_idx-bound record for every star merely by rendering
    # its floating widget, and _get_or_create_match_record_for_pitch_slot
    # can go on to ADOPT that same record as a Sort:Pitch-tab row once the
    # listen mechanic legitimately confirms its pitch — which reveals
    # PITCH, never identity. r["name"] is the safe signal instead: it's
    # ONLY ever set by a genuine player identity confirmation
    # (_confirm_match_record_identity always sets it together with
    # star_idx), never by auto-creation — so this isn't losing any real
    # coverage the star_idx tier had, just the leak it caused. Found via a
    # singleton Pitch slot showing an unconfirmed star's true name as
    # already selected on a puzzle that had barely started — the adopted
    # record's leftover star_idx (from mere widget rendering) was being
    # read as "the player knows this star's identity."
    var r: Dictionary = _match_records[record_idx]
    var rn: String = str(r.get("name", ""))
    if rn != "":
        return 1 if rn == name_str else 2

    var derived: int = _record_effective_state(record_idx, "name_states", "protected_staff_names", name_str)
    match derived:
        3: return 2
        4: return 0
        _: return derived


func _effective_degree_state(record_idx: int, degree: int) -> int:
    if record_idx < 0 or record_idx >= _match_records.size():
        return 0
    # Only two tiers, unlike Color/Pitch/Name: Degree has no staff-popup
    # protect/right-click mechanism at all (_on_record_degree_toggle/
    # _eliminate write degree_states directly, unconditionally, with no
    # soft-eliminated/protected layer to fold in), so there's no derived
    # state to consult. Deliberately skips degree_slot_label too — that
    # label is just "Conn <letter>" with no degree number embedded, so two
    # different degree-value groups' "A" slot collide on the same label;
    # ground truth + raw state is both sufficient and safe here.
    var r: Dictionary = _match_records[record_idx]
    var star_idx: int = int(r.get("star_idx", -1))
    if star_idx >= 0 and star_idx < _host._star_degrees.size():
        return 1 if int(_host._star_degrees[star_idx]) == degree else 2
    return int(r.get("degree_states", {}).get(degree, 0))


func _effective_star_state(record_idx: int, star_idx: int) -> int:
    if record_idx < 0 or record_idx >= _match_records.size():
        return 0
    # System A: the star widget's own per-star name checklist. A record
    # confirmed to BE a specific star (star_idx resolved) or one that has
    # explicitly X'd that star via star_elim (written by _on_name_check/
    # _on_name_x on the *name*-identified record, keyed by star_idx) is just
    # as solid a distinctness proof as a confirmed/eliminated Color or
    # Pitch — this was the primary, actually-used name-elimination path,
    # and it wasn't feeding _records_provably_distinct at all before.
    var r: Dictionary = _match_records[record_idx]
    var rs: int = int(r.get("star_idx", -1))
    if rs >= 0:
        return 1 if rs == star_idx else 2
    return int(r.get("star_elim", {}).get(star_idx, 0))


## Raw (non-recursive) possible-position set for a record: the explicit
## seq_candidates list if one exists, else the seq_lo..seq_hi range with 0
## bounds treated as fully open (1.._star_count). Empty means "no sequence
## information at all" — distinct from "narrowed to nothing," which can't
## happen for a live record. Used only by _records_provably_distinct(),
## which must not call _effective_seq_candidates()/
## _compute_excluded_positions_for() — see that function's comment.
func _raw_seq_candidate_set(r: Dictionary) -> Array:
    var explicit: Array = r.get("seq_candidates", [])
    if not explicit.is_empty():
        return explicit
    var lo: int = int(r.get("seq_lo", 0))
    var hi: int = int(r.get("seq_hi", 0))
    if lo <= 0 and hi <= 0:
        return []
    if lo <= 0:
        lo = 1
    if hi <= 0:
        hi = _host._star_count
    var out: Array = []
    for p in range(lo, hi + 1):
        out.append(p)
    return out


# ==================================================
# RECORD IDENTITY UNIFICATION — the missing mirror of
# _records_provably_distinct below.
#
# Every merge in this codebase used to happen only at a hardcoded pairwise
# UI entry point: the Listen handler merging into a pitch SLOT record
# (_reconcile_unique_pitch_slot), an identity confirm merging by star_idx,
# a Sequence commit merging by exact position, a name pick merging by name.
# Each of those only fires when the player touches that specific control,
# and only unifies records colliding on that ONE key. Nothing ever asked
# the general question: "do these two records provably describe the same
# star, whatever route each of them got its facts by?"
#
# So a record identified by NAME that the player gave a singleton Pitch to,
# and a star-map record whose pitch was legitimately revealed by Listen,
# stayed permanently separate — each holding half the picture, neither
# showing the other's facts, on every surface. Confirmed live (2026-08-07,
# Helios/C#5): four separate reported symptoms — Sort:Name missing its
# Color, the star map missing its Name, and the Sort:Pitch slot missing its
# Name — were all one instance of this single missing rule, and every
# earlier propagation bug this session was another.
#
# _records_provably_identical mirrors _records_provably_distinct exactly:
# same category sweep, same singleton-incidence gating for the non-alldiff
# axes (Color/Pitch/Degree), same unconfirmed-stub guard for Pitch.
# ==================================================

## The confirmed value of one raw states dict, or -1/"" when none. Reads
## the RAW dict (not _effective_*_state) deliberately — _merge_match_records
## compares raw states when deciding whether a merge conflicts, so the
## conflict pre-check below has to look at exactly what it will look at.
func _raw_confirmed_int_key(r: Dictionary, states_key: String) -> int:
    for k in r.get(states_key, {}):
        if int(r[states_key][k]) == 1:
            return int(k)
    return -1


func _raw_confirmed_string_key(r: Dictionary, states_key: String) -> String:
    for k in r.get(states_key, {}):
        if int(r[states_key][k]) == 1:
            return str(k)
    return ""


## THE single place a merge conflict is detected. Returns one identifier
## per conflict that _merge_match_records() would raise a dialog for, in
## the same order it raises them; empty means the merge is purely additive.
##
## Both consumers read this rather than restating the conditions:
## _merge_match_records()'s allow_await=false guard, and
## _records_have_merge_conflict() below. Keeping ONE list is the point —
## the two used to be independent copies of the same six-way check, which
## is precisely the shape of duplication that silently rots.
##
## Reads RAW state dicts, not _effective_*_state, because that is what the
## merge itself compares when deciding to raise each dialog.
func _merge_conflict_kinds(idx_a: int, idx_b: int) -> Array[String]:
    var kinds: Array[String] = []
    if idx_a < 0 or idx_a >= _match_records.size() \
            or idx_b < 0 or idx_b >= _match_records.size():
        return kinds
    var a: Dictionary = _match_records[idx_a]
    var b: Dictionary = _match_records[idx_b]

    var a_name: String = str(a.get("name", ""))
    var b_name: String = str(b.get("name", ""))
    if a_name != "" and b_name != "" and a_name != b_name:
        kinds.append("name")

    var a_lo: int = int(a.get("seq_lo", 0))
    var b_lo: int = int(b.get("seq_lo", 0))
    if a_lo > 0 and a_lo == int(a.get("seq_hi", 0)) \
            and b_lo > 0 and b_lo == int(b.get("seq_hi", 0)) and a_lo != b_lo:
        kinds.append("sequence")

    var ac: int = _raw_confirmed_int_key(a, "color_states")
    var bc: int = _raw_confirmed_int_key(b, "color_states")
    if ac >= 0 and bc >= 0 and ac != bc:
        kinds.append("color")

    var ad: int = _raw_confirmed_int_key(a, "degree_states")
    var bd: int = _raw_confirmed_int_key(b, "degree_states")
    if ad >= 0 and bd >= 0 and ad != bd:
        kinds.append("degree")

    var ap: String = _raw_confirmed_string_key(a, "pitch_states")
    var bp: String = _raw_confirmed_string_key(b, "pitch_states")
    if ap != "" and bp != "" and ap != bp:
        kinds.append("pitch")

    for label_key in ["color_slot_label", "pitch_slot_label", "degree_slot_label"]:
        var al: String = str(a.get(label_key, ""))
        var bl: String = str(b.get(label_key, ""))
        if al != "" and bl != "" and al != bl:
            kinds.append(label_key)

    return kinds


func _records_have_merge_conflict(idx_a: int, idx_b: int) -> bool:
    return not _merge_conflict_kinds(idx_a, idx_b).is_empty()


## Every uniquely-identifying fact a record confirms, as a token set. Two
## records describe the same star exactly when their sets intersect, which
## turns the identity test from a full category sweep PER PAIR into one
## sweep per record plus a small set intersection.
##
## This was measured, not guessed: at 75 records _settle_identical_records
## was taking 2.2-3.5 SECONDS, essentially the whole sequence-entry stall,
## because it re-swept 4 colours + 10 notes + every degree for each of
## ~2800 pairs, on every rescan.
##
## Only genuinely unique facts become tokens — Colour/Pitch/Degree qualify
## only at incidence 1, same gating as the exclusion rules, since a shared
## value proves nothing about identity.
func _identity_signature(record_idx: int) -> Dictionary:
    if _identity_sig_cache.has(record_idx):
        return _identity_sig_cache[record_idx]
    var sig: Dictionary = {}
    var r: Dictionary = _match_records[record_idx]

    var star: int = int(r.get("star_idx", -1))
    if star >= 0:
        sig["X:%d" % star] = true
    var nm: String = str(r.get("name", ""))
    if nm != "":
        sig["N:" + nm] = true
    var lo: int = int(r.get("seq_lo", 0))
    if lo > 0 and lo == int(r.get("seq_hi", 0)):
        sig["S:%d" % lo] = true
    for label_key in ["color_slot_label", "pitch_slot_label", "degree_slot_label"]:
        var lbl: String = str(r.get(label_key, ""))
        if lbl != "":
            sig["L:" + lbl] = true

    for ci in _host.COLOR_NAME_LABELS.size():
        if _color_star_count(ci) == 1 and _effective_color_state(record_idx, ci) == 1:
            sig["C:%d" % ci] = true

    # Same unconfirmed-stub guard as everywhere else: a bare auto-created
    # star-widget record's ground-truth pitch isn't earned until Listen.
    if not (_record_is_unconfirmed_star_widget_stub(record_idx) \
            and not bool(r.get("pitch_revealed", false))):
        for note in _host._widgets._distinct_note_names():
            if _pitch_star_count(note) == 1 and _effective_pitch_state(record_idx, note) == 1:
                sig["P:" + str(note)] = true

    var degrees_set: Dictionary = {}
    for s in _host._star_count:
        degrees_set[int(_host._star_degrees[s]) if s < _host._star_degrees.size() else 0] = true
    for deg in degrees_set.keys():
        if _degree_star_count(int(deg)) == 1 and _effective_degree_state(record_idx, int(deg)) == 1:
            sig["D:%d" % int(deg)] = true

    _identity_sig_cache[record_idx] = sig
    return sig


## Do these two records provably describe the SAME star? True when they
## share any fact that uniquely identifies one star.
func _records_provably_identical(idx_a: int, idx_b: int) -> bool:
    if idx_a < 0 or idx_a >= _match_records.size() \
            or idx_b < 0 or idx_b >= _match_records.size() or idx_a == idx_b:
        return false
    # Both pinned to a star is decisive either way, and cheap — check it
    # before building signatures.
    var a_star: int = int(_match_records[idx_a].get("star_idx", -1))
    var b_star: int = int(_match_records[idx_b].get("star_idx", -1))
    if a_star >= 0 and b_star >= 0:
        return a_star == b_star
    var sig_a: Dictionary = _identity_signature(idx_a)
    if sig_a.is_empty():
        return false
    var sig_b: Dictionary = _identity_signature(idx_b)
    for k in sig_a:
        if sig_b.has(k):
            return true
    return false


## Merges every pair of records that provably describe the same star, so
## facts gathered through different surfaces end up on one record instead
## of two half-pictures. Runs first in _full_propagation_refresh() so the
## later settle passes see unified records.
##
## Skips any pair needing a conflict dialog (allow_await=false makes the
## merge itself refuse) — this pass is synchronous and must not suspend.
## Those pairs keep surfacing through the explicit commit paths, which can
## await properly.
##
## SCANS EACH j DESCENDING, AND DOES NOT RESTART. _merge_match_records()
## removes the source record, shifting every index above it — which is why
## this used to restart the whole O(n^2) sweep after every single merge.
## Measured at 75 records that cost 2.2-3.5 SECONDS and was essentially the
## entire sequence-entry stall. Walking j from high to low means a removal
## only ever shifts indices we have already passed, so the scan stays
## valid and the pass is O(n^2) once instead of O(merges x n^2).
func _settle_identical_records() -> void:
    var i: int = 0
    while i < _match_records.size():
        var j: int = _match_records.size() - 1
        while j > i:
            if _records_provably_identical(i, j):
                _merge_match_records(i, j, false)
                # Record indices just shifted, and _identity_sig_cache /
                # _distinct_pair_cache / _candidate_star_cache /
                # _confirmer_clique_cache are all keyed by (or store) them.
                _clear_deduction_caches()
            j -= 1
        i += 1


## Pairwise distinctness memo. This is the innermost primitive of the whole
## engine — every exclusion function, every confirmer clique, coverage, and
## each Sort row's bounds derivation bottoms out here, and each call sweeps
## all five categories. Cached per refresh; same lifetime as the candidate
## sets, so it's cleared everywhere they are.
var _distinct_pair_cache: Dictionary = {}

## Per-record identity token sets — see _identity_signature(). Same
## index-keyed lifetime as the caches above.
var _identity_sig_cache: Dictionary = {}

## Per-record distinctness profiles — see _distinct_profile(). Same
## index-keyed lifetime as the caches above.
var _distinct_profile_cache: Dictionary = {}


func _records_provably_distinct(idx_a: int, idx_b: int) -> bool:
    if idx_a < 0 or idx_a >= _match_records.size() or idx_b < 0 or idx_b >= _match_records.size():
        return false  # can't prove distinctness with an invalid index
    # Symmetric, so normalise the key rather than caching both orderings.
    var key: String = "%d:%d" % [mini(idx_a, idx_b), maxi(idx_a, idx_b)]
    if _distinct_pair_cache.has(key):
        return bool(_distinct_pair_cache[key])
    var verdict: bool = _compute_records_provably_distinct(idx_a, idx_b)
    _distinct_pair_cache[key] = verdict
    return verdict


## Per-record view of everything _compute_records_provably_distinct needs:
## the raw possible-position set, and per axis the single confirmed value
## (null if none) plus the set of eliminated ones. Built once per record;
## the pairwise test is then a handful of dictionary lookups instead of
## ~90 _effective_*_state() calls.
##
## Uses the same _effective_*_state functions the loops did, so the verdict
## is unchanged — only how often they're evaluated. Note each axis can hold
## at most one confirmed value by construction (a record can't be two
## colours), which is what makes the collapse valid.
func _distinct_profile(record_idx: int) -> Dictionary:
    if _distinct_profile_cache.has(record_idx):
        return _distinct_profile_cache[record_idx]

    var seq_set: Dictionary = {}
    for p in _raw_seq_candidate_set(_match_records[record_idx]):
        seq_set[int(p)] = true

    var prof: Dictionary = {"seq": seq_set}

    var col: Dictionary = {"confirmed": null, "eliminated": {}}
    for ci in _host.COLOR_NAME_LABELS.size():
        var s: int = _effective_color_state(record_idx, ci)
        if s == 1: col["confirmed"] = ci
        elif s == 2: (col["eliminated"] as Dictionary)[ci] = true
    prof["color"] = col

    var pit: Dictionary = {"confirmed": null, "eliminated": {}}
    for note in _host._widgets._distinct_note_names():
        var s2: int = _effective_pitch_state(record_idx, str(note))
        if s2 == 1: pit["confirmed"] = str(note)
        elif s2 == 2: (pit["eliminated"] as Dictionary)[str(note)] = true
    prof["pitch"] = pit

    var nam: Dictionary = {"confirmed": null, "eliminated": {}}
    for n in _host._star_names:
        var s3: int = _effective_name_state(record_idx, str(n))
        if s3 == 1: nam["confirmed"] = str(n)
        elif s3 == 2: (nam["eliminated"] as Dictionary)[str(n)] = true
    prof["name"] = nam

    var st: Dictionary = {"confirmed": null, "eliminated": {}}
    for si in _host._star_count:
        var s4: int = _effective_star_state(record_idx, si)
        if s4 == 1: st["confirmed"] = si
        elif s4 == 2: (st["eliminated"] as Dictionary)[si] = true
    prof["star"] = st

    var deg: Dictionary = {"confirmed": null, "eliminated": {}}
    var degrees_set: Dictionary = {}
    for s5 in _host._star_count:
        degrees_set[int(_host._star_degrees[s5]) if s5 < _host._star_degrees.size() else 0] = true
    for d in degrees_set.keys():
        var s6: int = _effective_degree_state(record_idx, int(d))
        if s6 == 1: deg["confirmed"] = int(d)
        elif s6 == 2: (deg["eliminated"] as Dictionary)[int(d)] = true
    prof["degree"] = deg

    _distinct_profile_cache[record_idx] = prof
    return prof


func _compute_records_provably_distinct(idx_a: int, idx_b: int) -> bool:
    var a: Dictionary = _match_records[idx_a]
    var b: Dictionary = _match_records[idx_b]

    var a_star: int = int(a.get("star_idx", -1))
    var b_star: int = int(b.get("star_idx", -1))
    if a_star >= 0 and b_star >= 0:
        return a_star != b_star

    var a_name: String = str(a.get("name", ""))
    var b_name: String = str(b.get("name", ""))
    if a_name != "" and b_name != "" and a_name != b_name:
        return true

    # Sequence-range disjointness: if the two records' possible-position
    # sets don't overlap at all, they can't be the same star, regardless of
    # whether either side is pinned to an exact position. This was missing
    # entirely — every _compute_excluded_*_for() function gates its
    # cross-record exclusion on this function, so a Sort:Name record's
    # Sequence range (e.g. "not position 15") could never exclude that name
    # from a different, position-keyed record's Staff-popup checklist no
    # matter how correctly it was entered, since nothing here ever compared
    # ranges. Deliberately reads the RAW seq_lo/seq_hi/seq_candidates
    # fields, not _effective_seq_candidates() — that function calls
    # _compute_excluded_positions_for(), which calls back into this
    # function, so using it here would recurse.
    var pa_prof: Dictionary = _distinct_profile(idx_a)
    var pb_prof: Dictionary = _distinct_profile(idx_b)

    var a_seq: Dictionary = pa_prof["seq"]
    var b_seq: Dictionary = pb_prof["seq"]
    if not a_seq.is_empty() and not b_seq.is_empty():
        var overlap: bool = false
        for v in a_seq:
            if b_seq.has(v):
                overlap = true
                break
        if not overlap:
            return true

    # One confirmed value landing in the other side's eliminated set is
    # exactly what the five per-category loops used to look for, but those
    # ran ~90 _effective_*_state() calls PER PAIR — the dominant cost of
    # warming the pairwise cache (measured: ~590 ms for a full sweep cold
    # vs ~8 ms warm). The profile does that work once per record instead.
    for axis in ["color", "pitch", "name", "star", "degree"]:
        var ca = pa_prof[axis]["confirmed"]
        var cb = pb_prof[axis]["confirmed"]
        if ca != null and (pb_prof[axis]["eliminated"] as Dictionary).has(ca):
            return true
        if cb != null and (pa_prof[axis]["eliminated"] as Dictionary).has(cb):
            return true

    var degrees_set: Dictionary = {}
    for si2 in _host._star_count:
        degrees_set[int(_host._star_degrees[si2]) if si2 < _host._star_degrees.size() else 0] = true
    for deg in degrees_set.keys():
        var da: int = _effective_degree_state(idx_a, deg)
        var db: int = _effective_degree_state(idx_b, deg)
        if (da == 1 and db == 2) or (db == 1 and da == 2):
            return true

    return false


func _parse_candidate_list(raw: String) -> Array:
    var result: Dictionary = {}
    for chunk in raw.split(",", false):
        var c: String = chunk.strip_edges()
        if c == "":
            continue
        var dash: int = c.find("-")
        if dash > 0:
            var a_str: String = c.substr(0, dash).strip_edges()
            var b_str: String = c.substr(dash + 1).strip_edges()
            if a_str.is_valid_int() and b_str.is_valid_int():
                var a: int = int(a_str)
                var b: int = int(b_str)
                if a > b:
                    var tmp := a; a = b; b = tmp
                for p in range(a, b + 1):
                    result[p] = true
        elif c.is_valid_int():
            result[int(c)] = true
    var out: Array = result.keys()
    out.sort()
    return out


func _effective_seq_candidates(record_idx: int) -> Array:
    if record_idx < 0 or record_idx >= _match_records.size():
        return []
    var r: Dictionary = _match_records[record_idx]
    var explicit: Array = r.get("seq_candidates", [])
    var base: Array = []
    if not explicit.is_empty():
        base = explicit.duplicate()
    else:
        var lo: int = int(r.get("seq_lo", 0))
        var hi: int = int(r.get("seq_hi", 0))
        if lo <= 0:
            lo = 1
        if hi <= 0:
            hi = _host._star_count
        for p in range(lo, hi + 1):
            base.append(p)

    var excluded: Array = _compute_excluded_positions_for(record_idx)
    var result: Array = []
    for p in base:
        if not excluded.has(p):
            result.append(p)
    return result


func _settle_singleton_sequences() -> void:
    # Case 1 promotion: if exclusion has narrowed a record down to exactly
    # one surviving sequence candidate, that's logically the same fact as
    # an exact commit — "only 4 is left" IS "this is position 4." Promote
    # it into seq_lo/seq_hi so _compute_excluded_positions_for (which only
    # ever reads seq_lo == seq_hi on OTHER records) can use it to exclude
    # position 4 elsewhere, same as if the player had typed "4" directly.
    #
    # Lives here rather than inline inside _effective_seq_candidates —
    # that function is a read-only query every widget builder calls
    # expecting no side effects, so the write belongs in an explicit
    # "settle" step instead, called once per _full_propagation_refresh().
    # Recomputed fresh every call, so nothing here can get stuck on a stale
    # value. Skipped entirely for a record that's already pinned (never
    # silently overwrite an explicit commit, even one that looks
    # inconsistent — that should surface to the player, not get papered
    # over) or when a DIFFERENT record already legitimately owns that exact
    # position (a real merge belongs on the explicit-commit path, which can
    # safely await the conflict dialog; this loop can't).
    #
    # One pass over every record, in index order — a promotion made for an
    # earlier record in this same pass is immediately visible to a later
    # one's own candidate check (since each iteration re-reads live state),
    # but the reverse isn't guaranteed within a single pass; an unresolved
    # reverse-order cascade just resolves on the next refresh instead, same
    # eventual-consistency behavior _compute_excluded_positions_for already
    # has everywhere else.
    for i in _match_records.size():
        var r: Dictionary = _match_records[i]
        var already_exact: bool = int(r.get("seq_lo", 0)) > 0 and int(r.get("seq_lo", 0)) == int(r.get("seq_hi", 0))
        if already_exact:
            continue
        var result: Array = _effective_seq_candidates(i)
        if result.size() != 1:
            continue
        var existing_idx: int = _find_match_record_by_exact_seq(result[0])
        if existing_idx < 0 or existing_idx == i:
            r["seq_lo"] = result[0]
            r["seq_hi"] = result[0]
            r["seq_candidates"] = []


func _settle_singleton_names() -> void:
    # Same "narrowed-to-one IS a confirm" promotion as
    # _settle_singleton_sequences above, applied to the Sort:tab/Staff-
    # popup name_states dict instead of seq_lo/seq_hi. Name (this
    # record-level mechanism, distinct from the star widget's star_elim)
    # is alldiff — one name per star — exactly like Sequence, so the same
    # reasoning holds unconditionally. Reuses the existing sibling-
    # clearing propagate function rather than duplicating its logic.
    for i in _match_records.size():
        var r: Dictionary = _match_records[i]
        var name_states: Dictionary = r.get("name_states", {})
        var confirmed_name: String = ""
        var remaining: String = ""
        var remaining_count: int = 0
        var already_confirmed: bool = false
        for n in _host._star_names:
            var name_str: String = str(n)
            var state: int = int(name_states.get(name_str, 0))
            if state == 1:
                already_confirmed = true
                confirmed_name = name_str
                break
            if state != 2:
                remaining_count += 1
                remaining = name_str
        if not already_confirmed and remaining_count == 1:
            _propagate_name_states_confirmed_same_record(i, remaining)
        elif already_confirmed and str(r.get("name", "")) == "":
            # Re-run on every refresh (not just once) so a record confirmed
            # before the r["name"] promotion existed — or one whose
            # promotion was skipped earlier because another record still
            # held this name at the time — keeps retrying as state changes,
            # same self-healing shape _settle_singleton_sequences already
            # has for Sequence. Idempotent: sibling-clearing/manual-block
            # erase are no-ops when already applied.
            _propagate_name_states_confirmed_same_record(i, confirmed_name)


func _settle_singleton_pitches() -> void:
    # Same promotion as _settle_singleton_names, for pitch_states. Pitch
    # is NOT alldiff (see _pitch_star_count/_compute_excluded_pitches_for
    # below) but a single record narrowed to one remaining candidate is
    # still exactly as much a confirm on THAT record as it always was for
    # Sequence/Name — the alldiff question only matters for whether it's
    # also safe to exclude the value from OTHER records, handled
    # separately by _compute_excluded_pitches_for.
    for i in _match_records.size():
        var r: Dictionary = _match_records[i]
        if bool(r.get("pitch_revealed", false)):
            continue   # listen mechanic already owns this record's pitch state
        var pitch_states: Dictionary = r.get("pitch_states", {})
        var remaining: String = ""
        var remaining_count: int = 0
        var already_confirmed: bool = false
        for note_name in _host._widgets._distinct_note_names():
            var state: int = int(pitch_states.get(note_name, 0))
            if state == 1:
                already_confirmed = true
                break
            if state != 2:
                remaining_count += 1
                remaining = note_name
        if not already_confirmed and remaining_count == 1:
            _propagate_pitch_confirmed_same_record(i, remaining)


func _settle_singleton_colors() -> void:
    # Same promotion as _settle_singleton_pitches, for color_states. Color
    # is also not alldiff (see _color_star_count) — same reasoning as
    # Pitch applies: narrowing to one remaining candidate is still a
    # confirm on THIS record regardless of alldiff-ness; the incidence
    # guard only matters for whether _compute_excluded_colors_for can
    # also exclude the value from OTHER records.
    for i in _match_records.size():
        var r: Dictionary = _match_records[i]
        var color_states: Dictionary = r.get("color_states", {})
        var remaining: int = -1
        var remaining_count: int = 0
        var already_confirmed: bool = false
        for ci in _host.COLOR_NAME_LABELS.size():
            var state: int = int(color_states.get(ci, 0))
            if state == 1:
                already_confirmed = true
                break
            if state != 2:
                remaining_count += 1
                remaining = ci
        if not already_confirmed and remaining_count == 1:
            _propagate_color_confirmed_same_record(i, remaining)
            _recompute_color_star_elim(i)


func _settle_singleton_degrees() -> void:
    # The fourth axis's version of the same "narrowed to one remaining
    # candidate IS a confirm" promotion that Sequence, Name, Pitch and
    # Colour each already had. Degree simply never got one — the same
    # systematic under-featuring that left it with no cross-record
    # exclusion until _compute_excluded_degrees_for was added. Degree's
    # value set is the distinct degrees actually present among this
    # constellation's stars, not a fixed table, so it's enumerated the same
    # way _propagate_degree_confirmed_same_record enumerates it.
    var degrees_set: Dictionary = {}
    for s in _host._star_count:
        degrees_set[int(_host._star_degrees[s]) if s < _host._star_degrees.size() else 0] = true
    var degree_values: Array = degrees_set.keys()
    for i in _match_records.size():
        var r: Dictionary = _match_records[i]
        if int(r.get("star_idx", -1)) >= 0:
            continue   # ground truth already governs this record's degree
        var degree_states: Dictionary = r.get("degree_states", {})
        var remaining: int = -1
        var remaining_count: int = 0
        var already_confirmed: bool = false
        for dv in degree_values:
            var state: int = int(degree_states.get(int(dv), 0))
            if state == 1:
                already_confirmed = true
                break
            if state != 2:
                remaining_count += 1
                remaining = int(dv)
        if not already_confirmed and remaining_count == 1:
            _propagate_degree_confirmed_same_record(i, remaining)


func _compute_excluded_positions_for(record_idx: int) -> Array:
    # Scans the CURRENT full set of records live, every call. Nothing is
    # stored or pushed, so a record created AFTER some other record's
    # position was confirmed still sees the exclusion correctly — proven
    # necessary by the Sort:Color test: color-slot records created after
    # the Blue/15 confirmation never received a one-time push, because a
    # push cannot reach something that doesn't exist yet.
    var excluded: Array = []
    for i in _match_records.size():
        if i == record_idx:
            continue
        var r: Dictionary = _match_records[i]
        var lo: int = int(r.get("seq_lo", 0))
        var hi: int = int(r.get("seq_hi", 0))
        if lo > 0 and lo == hi and _records_provably_distinct(record_idx, i):
            excluded.append(lo)
    return excluded


func _compute_excluded_names_for(record_idx: int) -> Array[String]:
    # Same live-query shape as _compute_excluded_positions_for above —
    # Name (this record-level name_states mechanism) is alldiff, single
    # canonical record per name via _get_or_create_match_record_for_name,
    # same as Sequence's _get_or_create_match_record_for_seq — so the
    # exclusion is unconditional, no incidence-count guard needed (unlike
    # Pitch below). Deliberately calls _effective_name_state, NOT this
    # function's own eventual caller — that's the "base" ground-truth/
    # slot-label/raw tier, safe to call here with no recursion, since the
    # cross-record exclusion this computes is layered on TOP of it only at
    # display call sites, never inside _effective_name_state itself.
    # Name is alldiff, so a record confirms at most ONE name — found once
    # per record here rather than by asking _effective_name_state about all
    # 15 of them. The distinctness check is hoisted out of that loop too:
    # it never depended on the name, so it was being recomputed once per
    # (record x name) instead of once per record. Together those made this
    # the second-largest cost in a refresh at 75 records (~640 ms across a
    # full set of rows, measured).
    var excluded: Array[String] = []
    for i in _match_records.size():
        if i == record_idx or _record_is_unconfirmed_star_widget_stub(i):
            continue
        var confirmed: String = _confirmed_name_for_record(i)
        if confirmed == "":
            continue
        if _records_provably_distinct(record_idx, i):
            excluded.append(confirmed)
    return excluded


## The single name a record confirms, or "". Checks the identity field
## first (set by every real confirmation path) and falls back to a scan of
## name_states for a record confirmed before that promotion existed.
func _confirmed_name_for_record(record_idx: int) -> String:
    var r: Dictionary = _match_records[record_idx]
    var nm: String = str(r.get("name", ""))
    if nm != "":
        return nm
    for k in (r.get("name_states", {}) as Dictionary):
        if int(r["name_states"][k]) == 1:
            return str(k)
    return ""


# ==================================================
# CROSS-RECORD VALUE EXCLUSION — general cardinality (pigeonhole) rule.
#
# All three non-alldiff axes (Color, Pitch, Degree) used to gate on
# `_X_star_count(v) != 1` — i.e. they implemented ONLY the k=1 special case
# of the real rule, and silently did nothing for every value with two or
# more stars. The general rule:
#
#   A value V can be ruled out for record R once the number of OTHER
#   records that confirm V, and are provably distinct from R and from each
#   other, has reached V's total incidence count. All the stars carrying V
#   are then accounted for, so R cannot be another one.
#
# k=1 is just that with incidence 1. Confirmed live (2026-08-07): with
# every star's pitch revealed via Listen and colors sorted, all Blue stars
# were G4 or A#4 — two stars per note, so incidence 2 — and G4/A#4 were
# never excluded from any other colour's slot, because `!= 1` skipped them
# outright. The counting idea already existed in this file for VALIDATION
# (_confirm_color_against_cap catches "5 records confirmed Blue when only 4
# stars are Blue"); it just never reached the exclusion side.
#
# Name and Sequence deliberately keep their own simpler functions: both are
# alldiff, so incidence is always 1 and the general rule collapses back to
# the pairwise check they already do.
# ==================================================

## Largest set of records that all confirm one value AND are pairwise
## provably distinct — i.e. how many DIFFERENT stars are demonstrably
## accounted for by that value so far. Greedy, so it can undercount when
## the distinctness graph is awkward (exact maximum clique is NP-hard);
## undercounting only ever means "exclude later than strictly possible",
## never a wrong exclusion, so the approximation is safe in the sound
## direction. Cached per value for the reasons in _clear_deduction_caches().
func _confirmer_clique(cache_key: String, confirms: Callable) -> Array:
    if _confirmer_clique_cache.has(cache_key):
        return _confirmer_clique_cache[cache_key]
    var clique: Array = []
    for i in _match_records.size():
        if not bool(confirms.call(i)):
            continue
        var independent: bool = true
        for j in clique:
            if not _records_provably_distinct(i, int(j)):
                independent = false
                break
        if independent:
            clique.append(i)
    _confirmer_clique_cache[cache_key] = clique
    return clique


## Is every star carrying this value already accounted for by records other
## than record_idx? See this section's header comment for the rule.
func _value_fully_accounted_for(record_idx: int, clique: Array, incidence: int) -> bool:
    if incidence <= 0:
        return false
    var n: int = 0
    for i in clique:
        var idx: int = int(i)
        if idx == record_idx:
            return false   # this record is itself one of the carriers
        if _records_provably_distinct(record_idx, idx):
            n += 1
    return n >= incidence


func _compute_excluded_pitches_for(record_idx: int) -> Array[String]:
    var excluded: Array[String] = []
    for note_name in _host._widgets._distinct_note_names():
        var note: String = str(note_name)
        var clique: Array = _confirmer_clique("P:" + note, func(i: int) -> bool:
            # The stub-skip stops an UNEARNED pitch leaking (a record's
            # star_idx is set the instant its floating widget is built, with
            # nothing actually confirmed) — but once pitch_revealed is true
            # the Listen mechanic has legitimately earned that ground truth,
            # exactly the way Color's is earned for free.
            if _record_is_unconfirmed_star_widget_stub(i) \
                    and not bool(_match_records[i].get("pitch_revealed", false)):
                return false
            return _effective_pitch_state(i, note) == 1)
        if _value_fully_accounted_for(record_idx, clique, _pitch_star_count(note)):
            excluded.append(note)
    return excluded


func _compute_excluded_colors_for(record_idx: int) -> Array[int]:
    # Deliberately does NOT skip unconfirmed star-widget stubs the way the
    # Name/Pitch exclusions do: Color is a "given" axis (see
    # constellation_puzzle_category_facts memory) — painted on the map, zero
    # effort, true for every star whether or not its identity is confirmed —
    # so _effective_color_state's ground-truth tier isn't a leak here.
    var excluded: Array[int] = []
    for ci in _host.COLOR_NAME_LABELS.size():
        var color_idx: int = int(ci)
        var clique: Array = _confirmer_clique("C:%d" % color_idx, func(i: int) -> bool:
            return _effective_color_state(i, color_idx) == 1)
        if _value_fully_accounted_for(record_idx, clique, _color_star_count(color_idx)):
            excluded.append(color_idx)
    return excluded


func _compute_excluded_degrees_for(record_idx: int) -> Array[int]:
    # Same "given axis" reasoning as Color — Degree is structural, visible
    # on the map by tracing connections.
    var excluded: Array[int] = []
    var degrees_set: Dictionary = {}
    for s in _host._star_count:
        degrees_set[int(_host._star_degrees[s]) if s < _host._star_degrees.size() else 0] = true
    for deg in degrees_set.keys():
        var degree: int = int(deg)
        var clique: Array = _confirmer_clique("D:%d" % degree, func(i: int) -> bool:
            return _effective_degree_state(i, degree) == 1)
        if _value_fully_accounted_for(record_idx, clique, _degree_star_count(degree)):
            excluded.append(degree)
    return excluded


# ==================================================
# CLUE COVERAGE — built on the CELL model, per the unified-grid design
# intent (the grid is meant to be the one shared checker for entropy,
# trimming, and coverage alike, not a parallel ad-hoc checker per consumer).
#
# A clue's persisted "cells" (ConstellationLogicPuzzle CACHE_VERSION 4) are
# its actual ASSERTIONS, each {cat_a, star_a, cat_b, star_b, is_true}
# meaning "the star identified via cat_a and the star identified via cat_b
# are (is_true) / are not (not is_true) the same star" — see
# _build_matrix()'s own `is_true: star_a == star_b`.
#
# _match_records models exactly that same thing: one record IS a
# hypothesized star identity with descriptors attached. So a cell is
# "resolved" when the player's own records assert the same relation, and
# the sign falls out natively — an ELIMINATION resolves an is_true==false
# cell just as fully as a confirm resolves an is_true==true one. That is
# the whole reason the previous chars-based version could not be made
# correct by adjustment: "chars" records which entities a clue MENTIONS,
# and two clues asserting opposite things carry identical chars.
#
# Also note what's gone: no ground-truth lookup (pitch_rank_solution /
# star_names / star_colors as an answer key) appears below any more. Both
# sides are expressed in the same descriptor space, so coverage no longer
# asks "is the truth about this star known" — only "did the player record
# this relation."
# ==================================================

## Player-space state of one descriptor — "is this record the star that
## (has this name / fires at this position / is this color / plays this
## note)" — as 1 confirmed, 2 ruled out, 0 unknown. `star` identifies WHICH
## descriptor via the cached ground-truth arrays, exactly the way each
## Form's own label rendering does; it is not itself an answer-key read,
## since nothing here returns the star.
func _record_descriptor_state(record_idx: int, cat: int, star: int) -> int:
    if record_idx < 0 or record_idx >= _match_records.size():
        return 0
    if star < 0 or star >= _host._star_count:
        return 0
    match cat:
        ConstellationLogicPuzzle.Category.NAME:
            if star >= _host._star_names.size():
                return 0
            return _effective_name_state(record_idx, str(_host._star_names[star]))
        ConstellationLogicPuzzle.Category.SEQUENCE:
            if star >= _host._pitch_rank_solution.size():
                return 0
            var pos: int = int(_host._pitch_rank_solution[star]) + 1
            var r: Dictionary = _match_records[record_idx]
            var lo: int = int(r.get("seq_lo", 0))
            var hi: int = int(r.get("seq_hi", 0))
            if lo > 0 and lo == hi:
                return 1 if lo == pos else 2
            # Deliberately _raw_seq_candidate_set (this record's own stored
            # bounds/candidates), NOT _effective_seq_candidates: the latter
            # calls _compute_excluded_positions_for, which loops every
            # record calling _records_provably_distinct, which itself sweeps
            # every category — all of that nested inside this function's own
            # per-record loop, inside a per-cell loop, inside a per-clue
            # loop, re-run on every _populate_markers_panel(). That was the
            # multi-second Study-panel delay (roughly 10^6 ops per repaint).
            # No coverage is lost: an exclusion that _compute_excluded_
            # positions_for would have derived gets promoted into real
            # bounds by _settle_singleton_sequences() on the same refresh.
            var raw_set: Array = _raw_seq_candidate_set(r)
            if raw_set.is_empty():
                return 0   # no sequence information at all on this record
            return 0 if raw_set.has(pos) else 2
        ConstellationLogicPuzzle.Category.COLOR:
            if star >= _host._star_colors.size():
                return 0
            return _effective_color_state(record_idx, int(_host._star_colors[star]))
        ConstellationLogicPuzzle.Category.PITCH:
            # Skip an auto-created star-widget stub's un-earned ground-truth
            # tier, same guard _compute_excluded_pitches_for uses — a stub
            # exists for every star the instant its widget renders, and its
            # pitch is only legitimately known once Listen has fired.
            if _record_is_unconfirmed_star_widget_stub(record_idx) \
                    and not bool(_match_records[record_idx].get("pitch_revealed", false)):
                return 0
            var note: String = _host._widgets._note_name_for_star(star)
            if note == "?":
                return 0
            return _effective_pitch_state(record_idx, note)
    return 0


## Has the player's own note state resolved this cell to the value the clue
## asserts? Three sound routes, matching how the records actually get used:
##  - is_true: one record confirms BOTH descriptors (they're the same star).
##  - not is_true: one record confirms one descriptor and rules out the
##    other (same record can't be both) ...
##  - not is_true: ...or two DIFFERENT records confirm one descriptor each
##    and are provably distinct (so the descriptors are on different stars).
func _cell_resolved_by_player(cell: Dictionary) -> bool:
    var cat_a: int = int(cell.get("cat_a", -1))
    var star_a: int = int(cell.get("star_a", -1))
    var cat_b: int = int(cell.get("cat_b", -1))
    var star_b: int = int(cell.get("star_b", -1))
    var want_true: bool = bool(cell.get("is_true", false))

    var confirms_a: Array[int] = []
    var confirms_b: Array[int] = []
    for i in _match_records.size():
        var sa: int = _record_descriptor_state(i, cat_a, star_a)
        var sb: int = _record_descriptor_state(i, cat_b, star_b)
        if want_true:
            if sa == 1 and sb == 1:
                return true
        else:
            if (sa == 1 and sb == 2) or (sb == 1 and sa == 2):
                return true
        if sa == 1:
            confirms_a.append(i)
        if sb == 1:
            confirms_b.append(i)

    if not want_true:
        for ia in confirms_a:
            for ib in confirms_b:
                if ia != ib and _records_provably_distinct(ia, ib):
                    return true
    return false


## Coverage for one clue: how many of its asserted cells the player's own
## notes have resolved. Returns {"covered": int, "total": int}; total drops
## any cell with an out-of-range star (corrupted/stale cache), so it can be
## zero — check before dividing.
func _clue_coverage(cells: Array) -> Dictionary:
    var covered: int = 0
    var total: int = 0
    for cell in cells:
        if not (cell is Dictionary):
            continue
        var c: Dictionary = cell
        var star_a: int = int(c.get("star_a", -1))
        var star_b: int = int(c.get("star_b", -1))
        if star_a < 0 or star_a >= _host._star_count \
                or star_b < 0 or star_b >= _host._star_count:
            continue
        total += 1
        if _cell_resolved_by_player(c):
            covered += 1
    return {"covered": covered, "total": total}


## Memoizes _clue_coverage_fraction within one refresh cycle. Each of the
## three coverage tabs iterates the FULL clue list and asks every clue for
## its fraction, so without this the same answer is recomputed once per tab
## per repaint. Cleared at the top of _full_propagation_refresh() (the only
## thing that can change the answer) and on _load_match_records().
var _coverage_cache: Dictionary = {}

## Per-value confirmer cliques (see _confirmer_clique). Building one is
## O(records²) in _records_provably_distinct calls, and every Sort:tab row
## and popup asks for the same values over and over while a panel rebuilds,
## so without this the cardinality rule would reintroduce the same
## multi-second stall the coverage code just had. Cleared by
## _clear_deduction_caches().
var _confirmer_clique_cache: Dictionary = {}


## Candidate-star sets, keyed by record index. Split out of the clique
## cache rather than sharing it: the two have genuinely different
## lifetimes — a clique stays valid for a whole refresh, while a candidate
## set is invalidated the moment that record's own colour/pitch/degree
## state changes, which _settle_derived_eliminations() does mid-pass. They
## were briefly in one dict; nothing read a stale entry on today's call
## order, but that was luck, not design.
var _candidate_star_cache: Dictionary = {}


## Invalidated by any change to _match_records. Called at the start of
## _full_propagation_refresh() (which precedes every full UI rebuild) and
## from _save_puzzle_notes() (which every mutation path already calls), so
## a popup opened without an intervening refresh can't read stale data.
func _clear_deduction_caches() -> void:
    _coverage_cache.clear()
    _confirmer_clique_cache.clear()
    _candidate_star_cache.clear()
    _distinct_pair_cache.clear()
    _identity_sig_cache.clear()
    _distinct_profile_cache.clear()
    _listened_stars_cache.clear()
    _listened_stars_built = false


## Convenience wrapper — 0.0 (nothing recorded yet) to 1.0 (every assertion
## this clue makes is already in the player's notes), 0.0 for a clue with
## no usable cells rather than dividing by zero.
func _clue_coverage_fraction(cells: Array) -> float:
    var key: String = str(cells)
    if _coverage_cache.has(key):
        return float(_coverage_cache[key])
    var cov: Dictionary = _clue_coverage(cells)
    var total: int = int(cov["total"])
    var result: float = 0.0 if total <= 0 else float(cov["covered"]) / float(total)
    _coverage_cache[key] = result
    return result


func _record_is_unconfirmed_star_widget_stub(record_idx: int) -> bool:
    if record_idx < 0 or record_idx >= _match_records.size():
        return false
    # _build_star_widgets_impl() auto-creates a star_idx-bound record for
    # EVERY star the instant its floating widget is built
    # (_get_or_create_match_record_for_star_idx), regardless of anything
    # the player has done — so star_idx >= 0 alone is NOT proof the player
    # has legitimately confirmed that star's identity. r["name"] is a safe
    # signal: it's only ever set by a real player action
    # (_confirm_match_record_identity, or a name-slot record's own
    # defining field) — never by mere auto-creation. Without this guard,
    # _effective_name_state/_effective_pitch_state's ground-truth tier
    # (star_idx >= 0 → read the true value directly) leaks every
    # unconfirmed star's true name/pitch into _records_provably_distinct,
    # which _compute_excluded_names_for/_compute_excluded_pitches_for
    # then surface as if legitimately deduced — caught via a singleton
    # Pitch slot showing every OTHER star's Name selector as already
    # solved on a puzzle that had barely started.
    var r: Dictionary = _match_records[record_idx]
    return int(r.get("star_idx", -1)) >= 0 and str(r.get("name", "")) == ""


func _exclusive_display_lo(inclusive_lo: int, inclusive_hi: int) -> int:
    if inclusive_lo <= 0:
        return 0
    if inclusive_lo == inclusive_hi:
        return inclusive_lo
    return inclusive_lo - 1


func _exclusive_display_hi(inclusive_lo: int, inclusive_hi: int) -> int:
    if inclusive_hi <= 0:
        return 0
    if inclusive_lo == inclusive_hi:
        return inclusive_hi
    var shown: int = inclusive_hi + 1
    return 0 if shown > _host._star_count else shown


func _parse_exclusive_bounds(raw_lo: int, raw_hi: int) -> Array:
    if raw_lo > 0 and raw_hi > 0 and raw_lo == raw_hi:
        return [raw_lo, raw_hi]
    var lo: int = raw_lo + 1 if raw_lo > 0 else 0
    var hi: int = raw_hi - 1 if raw_hi > 0 else 0
    if lo > 0 and hi > 0 and lo > hi:
        return [0, 0]
    return [lo, hi]


func _effective_seq_bounds(record_idx: int) -> Array:
    if record_idx < 0 or record_idx >= _match_records.size():
        return [0, 0, []]
    var r: Dictionary = _match_records[record_idx]
    var stored_lo: int = int(r.get("seq_lo", 0))
    var stored_hi: int = int(r.get("seq_hi", 0))
    if stored_lo > 0 and stored_lo == stored_hi and (r.get("seq_candidates", []) as Array).is_empty():
        return [stored_lo, stored_hi, []]

    var candidates: Array = _effective_seq_candidates(record_idx)
    if candidates.is_empty():
        return [0, 0, []]

    candidates.sort()
    var eff_lo: int = candidates[0]
    var eff_hi: int = candidates[candidates.size() - 1]

    var mid_excluded: Array = []
    for p in range(eff_lo, eff_hi + 1):
        if not candidates.has(p):
            mid_excluded.append(p)

    var display_lo: int = eff_lo if (stored_lo > 0 or eff_lo > 1) else 0
    var display_hi: int = eff_hi if (stored_hi > 0 or eff_hi < _host._star_count) else 0
    return [display_lo, display_hi, mid_excluded]


func _full_propagation_refresh() -> void:
    _clear_deduction_caches()
    _settle_identical_records()
    _derive_color_eliminations_from_star_elim()
    # Candidate-star closure before the per-axis settles: it can resolve a
    # record's identity outright (star_idx), which every downstream pass
    # then reads ground truth through.
    _settle_star_identity_from_candidates()
    _settle_derived_eliminations()
    _settle_group_sequence_bounds()
    _settle_singleton_sequences()
    _settle_singleton_names()
    _settle_singleton_pitches()
    _settle_singleton_colors()
    _settle_singleton_degrees()
    _host._widgets._build_star_widgets()
    _host._widgets._build_star_tags()
    _host._melody_staff_panel.queue_redraw()
    _host._widgets.request_markers_rebuild()


# ==================================================
# CANDIDATE-STAR SET — the general closure for group/member propagation on
# every "given" axis at once, replacing what would otherwise be a separate
# hand-written rule per (axis x direction) pair.
#
# Every record has a set of stars it could still be. Once that set is
# known, ALL of these fall out of it uniformly instead of needing their own
# implementations:
#   * member -> group: a "White A" slot's candidates are the white stars,
#     so any value no white star carries is eliminated for it (this is the
#     "all Blue stars are G4/A#4, so Blue slots can't be anything else"
#     case).
#   * group -> member: a star-bound record's candidate set is that one
#     star, so its given values are pinned (already the ground-truth tier
#     in _effective_*_state).
#   * identity by elimination: a candidate set narrowed to exactly ONE star
#     means the record IS that star — set star_idx and every ground-truth
#     tier cascades at once.
#
# Only Colour and Degree drive the set unconditionally: both are "given"
# axes (painted on the map / traceable by eye), so reading them leaks
# nothing. Pitch contributes ONLY for stars whose pitch the player has
# actually revealed via Listen — using ground-truth pitch otherwise would
# hand over an un-earned answer, the leak class documented throughout this
# file. Name and Sequence never contribute: their star mapping is precisely
# what the puzzle withholds.
# ==================================================

## Scanned every record on every call, and is called inside per-star loops
## that are themselves inside per-record loops (_candidate_stars_for_record,
## _settle_derived_eliminations) — O(records^2 x stars). Built once per
## refresh instead; invalidated by _clear_deduction_caches() along with
## everything else derived from _match_records.
var _listened_stars_cache: Dictionary = {}
var _listened_stars_built: bool = false


func _player_knows_star_pitch(star: int) -> bool:
    if not _listened_stars_built:
        _listened_stars_cache.clear()
        for r in _match_records:
            var s: int = int(r.get("star_idx", -1))
            if s >= 0 and bool(r.get("pitch_revealed", false)):
                _listened_stars_cache[s] = true
        _listened_stars_built = true
    return _listened_stars_cache.has(star)


## Stars this record could still be. Intersects every constraint that maps
## soundly onto stars; returns every star when nothing constrains it.
func _candidate_stars_for_record(record_idx: int) -> Array:
    if record_idx < 0 or record_idx >= _match_records.size():
        return []
    if _candidate_star_cache.has(record_idx):
        return _candidate_star_cache[record_idx]

    var r: Dictionary = _match_records[record_idx]
    var out: Array = []
    var pinned: int = int(r.get("star_idx", -1))
    if pinned >= 0 and pinned < _host._star_count:
        out = [pinned]
        _candidate_star_cache[record_idx] = out
        return out

    var elim: Dictionary = r.get("star_elim", {})
    for s in _host._star_count:
        if int(elim.get(s, 0)) == 2:
            continue
        # Colour — always given.
        var sc: int = int(_host._star_colors[s]) if s < _host._star_colors.size() else -1
        if sc >= 0 and _effective_color_state(record_idx, sc) == 2:
            continue
        # Degree — always given.
        var sd: int = int(_host._star_degrees[s]) if s < _host._star_degrees.size() else -1
        if sd >= 0 and _effective_degree_state(record_idx, sd) == 2:
            continue
        # Pitch — only for stars the player has actually listened to.
        if _player_knows_star_pitch(s):
            var note: String = _host._widgets._note_name_for_star(s)
            if note != "?" and _effective_pitch_state(record_idx, note) == 2:
                continue
        out.append(s)
    _candidate_star_cache[record_idx] = out
    return out


## |candidates| == 1 means the record IS that star. Setting star_idx makes
## every _effective_*_state ground-truth tier fire at once, so Colour,
## Degree, and (once listened) Pitch all resolve without their own rules.
func _settle_star_identity_from_candidates() -> void:
    for i in _match_records.size():
        var r: Dictionary = _match_records[i]
        if int(r.get("star_idx", -1)) >= 0:
            continue
        var cands: Array = _candidate_stars_for_record(i)
        if cands.size() != 1:
            continue
        var s: int = int(cands[0])
        # Refuse if another record already owns that star — a real conflict
        # belongs on an explicit path that can await the dialog, not here.
        if _find_match_record_by_star_idx(s) >= 0:
            continue
        r["star_idx"] = s
        _sync_color_states_from_star_idx(i)
        # Identity resolution invalidates every derived cache: cliques
        # depend on provable-distinctness, candidate sets on this record's
        # own state, and the listened-stars set on which record owns which
        # star_idx — which is exactly what just changed. Routed through the
        # shared helper so a cache added later can't be missed here.
        _clear_deduction_caches()


## Eliminates every given-axis value that NO candidate star carries. This
## is the member -> group half; the group -> member half is the ground-truth
## tier that fires once star_idx resolves.
func _settle_derived_eliminations() -> void:
    for i in _match_records.size():
        var r: Dictionary = _match_records[i]
        if int(r.get("star_idx", -1)) >= 0:
            continue   # ground truth already governs this record
        var cands: Array = _candidate_stars_for_record(i)
        if cands.is_empty() or cands.size() >= _host._star_count:
            continue   # unconstrained: nothing to derive

        var colors: Dictionary = {}
        var degrees: Dictionary = {}
        var notes: Dictionary = {}
        var all_pitches_known: bool = true
        for c in cands:
            var s: int = int(c)
            if s < _host._star_colors.size():
                colors[int(_host._star_colors[s])] = true
            if s < _host._star_degrees.size():
                degrees[int(_host._star_degrees[s])] = true
            if _player_knows_star_pitch(s):
                var n: String = _host._widgets._note_name_for_star(s)
                if n != "?":
                    notes[n] = true
            else:
                all_pitches_known = false

        var color_states: Dictionary = r.get("color_states", {})
        for ci in _host.COLOR_NAME_LABELS.size():
            if not colors.has(int(ci)) and int(color_states.get(ci, 0)) == 0:
                color_states[ci] = 2
        r["color_states"] = color_states

        var degree_states: Dictionary = r.get("degree_states", {})
        for s2 in _host._star_count:
            var dv: int = int(_host._star_degrees[s2]) if s2 < _host._star_degrees.size() else -1
            if dv >= 0 and not degrees.has(dv) and int(degree_states.get(dv, 0)) == 0:
                degree_states[dv] = 2
        r["degree_states"] = degree_states

        # Only sound once EVERY candidate's pitch is player-known: an
        # unlistened candidate could be carrying the very note about to be
        # eliminated.
        if all_pitches_known and not bool(r.get("pitch_revealed", false)):
            var pitch_states: Dictionary = r.get("pitch_states", {})
            for n2 in _host._widgets._distinct_note_names():
                var nn: String = str(n2)
                if not notes.has(nn) and int(pitch_states.get(nn, 0)) == 0:
                    pitch_states[nn] = 2
            r["pitch_states"] = pitch_states

    # This pass writes the very colour/degree/pitch state that candidate
    # sets AND pairwise distinctness are derived FROM, so both caches are
    # now potentially stale. Relying on the call order not to re-read one
    # is exactly the fragility these caches were split out to avoid.
    _candidate_star_cache.clear()
    _distinct_pair_cache.clear()


# ==================================================
# GROUP -> MEMBER PROPAGATION (disjunction narrowing).
#
# THIRD distinct structural rule class in this engine, after record-identity
# unification and the cardinality/pigeonhole exclusion rule. This one is
# about facts that apply to a GROUP rather than to one record:
#
#   A star known to be (say) White is one of the White slot records, though
#   we can't tell WHICH. So any constraint true of EVERY White slot is true
#   of that star, even though no merge is possible and none should be —
#   "White A" is an arbitrary discovery-order letter, not an identity.
#
# The engine already had the opposite direction for exactly one axis pair
# (_derive_color_eliminations_from_star_elim: every star of a colour X'd
# for a name => that colour eliminated for that name), and nothing at all
# in this direction. Confirmed live 2026-08-07: "The star that plays D5
# precedes every white star" entered as a lower bound on every White slot's
# Sequence row never reached any white star's own map widget.
#
# SCOPE — deliberately narrow, stated rather than assumed complete:
#   * Implemented: Sequence-position narrowing, from Colour and Pitch slot
#     groups onto a star-bound record.
#   * NOT implemented: the same narrowing driven by Degree groups (their
#     "Conn A"/"Conn B" labels collide across different degree values —
#     see _effective_degree_state's own comment — so the group can't be
#     identified reliably); group->member propagation on the Name, Colour
#     or Pitch axes; and member->group in any direction beyond the one
#     colour/name case that already existed.
# ==================================================

## Union of the sequence positions still available to a slot group, or []
## when the group can't be trusted to cover the value's stars exactly, or
## when any member is wholly unconstrained (union would be everything, so
## narrowing is a no-op anyway).
func _group_position_union(record_idx: int, label_key: String, prefix: String, incidence: int) -> Array:
    if incidence <= 0 or prefix == "":
        return []
    var group: Array = []
    for j in _match_records.size():
        if j == record_idx:
            continue
        var lbl: String = str(_match_records[j].get(label_key, ""))
        if lbl != "" and lbl.begins_with(prefix):
            group.append(j)
    # The group must account for every star carrying the value; a partial
    # set proves nothing about which slot this star is.
    if group.size() != incidence:
        return []
    var union: Dictionary = {}
    for j in group:
        var member_set: Array = _raw_seq_candidate_set(_match_records[int(j)])
        if member_set.is_empty():
            return []   # unconstrained member — union is every position
        for p in member_set:
            union[int(p)] = true
    var out: Array = union.keys()
    out.sort()
    return out


func _settle_group_sequence_bounds() -> void:
    for i in _match_records.size():
        var r: Dictionary = _match_records[i]
        var s: int = int(r.get("star_idx", -1))
        if s < 0 or s >= _host._star_count:
            continue   # only a star-bound record has a knowable group
        var lo: int = int(r.get("seq_lo", 0))
        if lo > 0 and lo == int(r.get("seq_hi", 0)):
            continue   # already pinned exactly; nothing left to narrow

        var unions: Array = []
        if s < _host._star_colors.size():
            var ci: int = int(_host._star_colors[s])
            if ci >= 0 and ci < _host.COLOR_NAME_LABELS.size():
                var cu: Array = _group_position_union(
                    i, "color_slot_label", str(_host.COLOR_NAME_LABELS[ci]), _color_star_count(ci))
                if not cu.is_empty():
                    unions.append(cu)
        # Pitch group — only when the player has actually revealed this
        # star's pitch, else the group membership itself is un-earned.
        if _player_knows_star_pitch(s):
            var note: String = _host._widgets._note_name_for_star(s)
            if note != "?":
                var pu: Array = _group_position_union(
                    i, "pitch_slot_label", note, _pitch_star_count(note))
                if not pu.is_empty():
                    unions.append(pu)
        # Degree group — now identifiable, since the slot label carries the
        # degree value (see _get_or_create_match_record_for_degree_slot).
        if s < _host._star_degrees.size():
            var dg: int = int(_host._star_degrees[s])
            var du: Array = _group_position_union(
                i, "degree_slot_label", "Conn%d " % dg, _degree_star_count(dg))
            if not du.is_empty():
                unions.append(du)
        if unions.is_empty():
            continue

        var current: Array = _raw_seq_candidate_set(r)
        if current.is_empty():
            current = []
            for p in range(1, _host._star_count + 1):
                current.append(p)
        var narrowed: Array = current.duplicate()
        for u in unions:
            var next: Array = []
            for p in narrowed:
                if (u as Array).has(p):
                    next.append(p)
            narrowed = next
        # An empty result would mean the player's own entries contradict;
        # surface that through their explicit entries rather than silently
        # writing an impossible record here.
        if narrowed.is_empty() or narrowed.size() >= current.size():
            continue
        r["seq_candidates"] = narrowed
        r["seq_lo"] = 0
        r["seq_hi"] = 0


func _derive_color_eliminations_from_star_elim() -> void:
    # If every star of some color has been explicitly X'd for a name (via
    # the star widget's own checklist — "System A"), that color is
    # definitely not this name's color, even though nobody directly
    # touched its Color buttons. Without this, a name's Sort:Name row (and
    # anything else reading color_states) still lets that color through as
    # if nothing had ruled it out.
    for r in _match_records:
        var elim: Dictionary = r.get("star_elim", {})
        if elim.is_empty():
            continue
        var color_states: Dictionary = r.get("color_states", {})
        for ci in _host.COLOR_NAME_LABELS.size():
            if int(color_states.get(ci, 0)) != 0:
                continue   # already confirmed or eliminated some other way
            var any_star_of_color: bool = false
            var all_eliminated: bool = true
            for s in _host._star_count:
                if s < _host._star_colors.size() and int(_host._star_colors[s]) == ci:
                    any_star_of_color = true
                    if int(elim.get(s, 0)) != 2:
                        all_eliminated = false
                        break
            if any_star_of_color and all_eliminated:
                color_states[ci] = 2
        r["color_states"] = color_states
