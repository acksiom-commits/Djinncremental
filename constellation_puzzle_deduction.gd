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

# Deduction code (_merge_match_records/_confirm_match_record_identity) asks
# for a conflict choice through this instead of calling the widgets file's
# _show_conflict_choice directly — keeps this file's only "put something on
# screen" dependency behind one injected seam.
var _conflict_dialog_fn: Callable = Callable()

var _protected_names: Dictionary = {}   # key "star_idx:name" -> true; right-click "still possible" flags
var _user_blocks: Dictionary = {}       # "star_idx:name" -> true; blocks placed by user clicking X, not by propagation

# Match records — one per set of facts the player has asserted belong to the same star.
# Each record: {
#   "name": String,              # "" if unknown
#   "seq_lo": int, "seq_hi": int, # 0 if unknown; exact position known when seq_lo == seq_hi > 0
#   "color_states": Dictionary,   # {color_idx(int): state(int)} 0=neutral, 1=confirmed, 2=eliminated
#   "pitch_states": Dictionary,   # {note_name(String): state(int)}
#   "manual_name_blocks": Dictionary,   # {name(String): true} — names the player
#   "manual_pitch_blocks": Dictionary,  # X'd directly, as opposed to state-2
#   "manual_color_blocks": Dictionary,  # entries that are fallout from confirming
#                                        # a sibling value. Lets the Undo row tell
#                                        # "Undo selects" (revert sibling-clearing
#                                        # fallout only) apart from "Undo blocks"
#                                        # (revert the player's own X clicks only).
#   "pitch_carousel_idx": int,    # transient UI state, not persisted
#   "star_idx": int,              # -1 until resolvable from seq_lo==seq_hi or map-widget confirm
# }
var _match_records: Array[Dictionary] = []


func setup(host: ConstellationStudyOverlay, conflict_dialog_fn: Callable) -> void:
    _host = host
    _conflict_dialog_fn = conflict_dialog_fn


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
    if not _host._cd or _host._constellation_id < 0:
        return
    var notes: Dictionary = {}
    notes["adjacency_states"] = _host._proximity_states.duplicate()
    notes["match_records"] = _save_match_records()
    notes["protected_names"] = _protected_names.duplicate()
    notes["user_blocks"] = _user_blocks.duplicate()
    _host._cd.set_player_puzzle_notes(_host._constellation_id, notes)

# ==================================================
# DEDUCTION ENGINE CORE — record lookups, elimination
# propagation, merge/conflict logic, save/load
# ==================================================
func _clear_protected_names_for_star(star_idx: int) -> void:
    var to_erase: Array[String] = []
    for key in _protected_names.keys():
        var parts: PackedStringArray = key.split(":")
        if parts.size() == 2 and parts[0].is_valid_int() and int(parts[0]) == star_idx:
            to_erase.append(key)
    for k in to_erase:
        _protected_names.erase(k)




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
        if i == this_record:
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


func _star_confirmed_name(star_idx: int) -> String:
    for r in _match_records:
        if int(r.get("star_idx", -1)) == star_idx:
            return str(r.get("name", ""))
    return ""


func _possible_names_for_record(record_idx: int) -> Array[String]:
    var r: Dictionary = _match_records[record_idx]
    var this_star_idx: int = int(r.get("star_idx", -1))
    var this_name: String = str(r.get("name", ""))
    var this_seq_lo: int = int(r.get("seq_lo", 0))
    var this_seq_hi: int = int(r.get("seq_hi", 0))
    var this_seq_exact: int = this_seq_lo if this_seq_lo > 0 and this_seq_lo == this_seq_hi else -1
    var this_color_label: String = str(r.get("color_slot_label", ""))
    var this_pitch_label: String = str(r.get("pitch_slot_label", ""))
    var this_degree_label: String = str(r.get("degree_slot_label", ""))

    var result: Array[String] = []
    for n in _host._star_names:
        var name_str: String = str(n)
        if name_str == this_name:
            result.append(name_str)
            continue

        var other_idx: int = _find_match_record_by_name(name_str)
        if other_idx >= 0 and other_idx != record_idx:
            var other: Dictionary = _match_records[other_idx]
            var other_star: int = int(other.get("star_idx", -1))
            var other_seq_lo: int = int(other.get("seq_lo", 0))
            var other_seq_hi: int = int(other.get("seq_hi", 0))
            var other_seq_exact: int = other_seq_lo if other_seq_lo > 0 and other_seq_lo == other_seq_hi else -1
            var other_color_label: String = str(other.get("color_slot_label", ""))
            var other_pitch_label: String = str(other.get("pitch_slot_label", ""))
            var other_degree_label: String = str(other.get("degree_slot_label", ""))

            var conflict: bool = false
            var conflict_reason: String = ""
            if this_star_idx >= 0 and other_star >= 0 and other_star != this_star_idx:
                conflict = true
                conflict_reason = "star %d vs %d" % [this_star_idx, other_star]
            if this_seq_exact > 0 and other_seq_exact > 0 and other_seq_exact != this_seq_exact:
                conflict = true
                conflict_reason = "seq %d vs %d" % [this_seq_exact, other_seq_exact]
            if this_color_label != "" and other_color_label != "" and other_color_label != this_color_label:
                conflict = true
                conflict_reason = "color slot '%s' vs '%s'" % [this_color_label, other_color_label]
            if this_pitch_label != "" and other_pitch_label != "" and other_pitch_label != this_pitch_label:
                conflict = true
                conflict_reason = "pitch slot '%s' vs '%s'" % [this_pitch_label, other_pitch_label]
            if this_degree_label != "" and other_degree_label != "" and this_degree_label != other_degree_label:
                conflict = true
                conflict_reason = "degree slot '%s' vs '%s'" % [this_degree_label, other_degree_label]
            if conflict:
                print("[DEBUG] possible_names: record %d excludes '%s' — %s" % [record_idx, name_str, conflict_reason])
                continue

        if this_star_idx >= 0 and _star_elim_state(this_star_idx, name_str) == 2:
            print("[DEBUG] possible_names: record %d excludes '%s' — X'd for this slot's star %d" % [record_idx, name_str, this_star_idx])
            continue

        result.append(name_str)
    result.sort_custom(func(a, b): return String(a).nocasecmp_to(String(b)) < 0)
    return result


func _protect_key(star_idx: int, name_str: String) -> String:
    return "%d:%s" % [star_idx, name_str]


func _is_name_protected(star_idx: int, name_str: String) -> bool:
    return _protected_names.has(_protect_key(star_idx, name_str))


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
    var r: Dictionary = _match_records[record_idx]
    var protected: Dictionary = r.get(protect_key, {})
    return protected.has(value_key)


func _record_any_protected(record_idx: int, protect_key: String) -> bool:
    var r: Dictionary = _match_records[record_idx]
    var protected: Dictionary = r.get(protect_key, {})
    return not protected.is_empty()


func _record_effective_state(record_idx: int, states_key: String, protect_key: String, value_key) -> int:
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
    var r: Dictionary = _match_records[record_idx]
    var states: Dictionary = r.get(states_key, {})
    var manual: Dictionary = r.get(manual_key, {})
    for v in manual.keys():
        states[v] = 0
    r[states_key] = states
    r[manual_key] = {}




func _apply_color_elimination_to_names(record_idx: int, color_idx: int, new_state: int) -> void:
    # Color is the one axis directly visible per star, so it's the one axis
    # that can safely auto-propagate into the name/star grid without leaking
    # anything the player hasn't earned. Sequence and pitch are themselves
    # unknowns from the player's perspective, so they intentionally do NOT
    # get this treatment — they only unify through record merging once
    # identity is independently confirmed.
    var r: Dictionary = _match_records[record_idx]
    var elim: Dictionary = r.get("star_elim", {})
    var name_str: String = str(r.get("name", ""))
    if name_str == "":
        return
    if new_state == 2:
        for s in _host._star_count:
            var sc: int = _host._star_colors[s] if s < _host._star_colors.size() else 1
            if sc == color_idx and int(elim.get(s, 0)) != 1:
                elim[s] = 2
    elif new_state == 1:
        for s in _host._star_count:
            var sc2: int = _host._star_colors[s] if s < _host._star_colors.size() else 1
            if sc2 != color_idx and int(elim.get(s, 0)) != 1:
                elim[s] = 2
    r["star_elim"] = elim


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
    var r: Dictionary = _match_records[record_idx]
    var star_idx: int = int(r.get("star_idx", -1))
    if star_idx >= 0:
        return _host._star_colors[star_idx] if star_idx < _host._star_colors.size() else -1
    var cs: Dictionary = r.get("color_states", {})
    for ci in _host.COLOR_NAME_LABELS.size():
        if int(cs.get(ci, 0)) == 1:
            return ci
    return -1


func _sync_color_states_from_star_idx(record_idx: int) -> void:
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
    _match_records.append({
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
        "pitch_revealed": false,
        "star_elim": {},
        "pitch_carousel_idx": 0,
        "star_idx": -1,
        "color_slot_label": label,
        "pitch_slot_label": "",
        "degree_slot_label": "",
    })
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
    _match_records.append({
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
        "pitch_revealed": false,
        "star_elim": {},
        "pitch_carousel_idx": 0,
        "star_idx": -1,
        "color_slot_label": "",
        "pitch_slot_label": label,
        "degree_slot_label": "",
    })
    return _match_records.size() - 1


func _get_or_create_match_record_for_name(name_str: String) -> int:
    var idx: int = _find_match_record_by_name(name_str)
    if idx >= 0:
        return idx
    _match_records.append({
        "name": name_str,
        "seq_lo": 0, "seq_hi": 0,
        "seq_candidates": [],
        "color_states": {},
        "pitch_states": {},
        "degree_states": {},
        "name_states": {},
        "manual_name_blocks": {},
        "manual_pitch_blocks": {},
        "manual_color_blocks": {},
        "pitch_revealed": false,
        "star_elim": {},
        "pitch_carousel_idx": 0,
        "star_idx": -1,
        "color_slot_label": "",
        "pitch_slot_label": "",
        "degree_slot_label": "",
    })
    return _match_records.size() - 1


func _get_or_create_match_record_for_seq(slot: int) -> int:
    var idx: int = _find_match_record_by_exact_seq(slot)
    if idx >= 0:
        return idx
    _match_records.append({
        "name": "",
        "seq_lo": slot, "seq_hi": slot,
        "seq_candidates": [],
        "color_states": {},
        "pitch_states": {},
        "degree_states": {},
        "name_states": {},
        "manual_name_blocks": {},
        "manual_pitch_blocks": {},
        "manual_color_blocks": {},
        "pitch_revealed": false,
        "star_elim": {},
        "pitch_carousel_idx": 0,
        "star_idx": -1,
        "color_slot_label": "",
        "pitch_slot_label": "",
        "degree_slot_label": "",
    })
    return _match_records.size() - 1


func _get_or_create_match_record_for_star_idx(star_idx: int) -> int:
    var idx: int = _find_match_record_by_star_idx(star_idx)
    if idx >= 0:
        return idx
    _match_records.append({
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
        "pitch_revealed": false,
        "star_elim": {},
        "pitch_carousel_idx": 0,
        "star_idx": star_idx,
        "color_slot_label": "",
        "pitch_slot_label": "",
        "degree_slot_label": "",
    })
    return _match_records.size() - 1


func _get_or_create_match_record_for_degree_slot(degree: int, position_in_group: int) -> int:
    var label: String = "%s %s" % ["Conn", _slot_letter(position_in_group)]
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
    _match_records.append({
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
        "pitch_revealed": false,
        "star_elim": {},
        "pitch_carousel_idx": 0,
        "star_idx": -1,
        "color_slot_label": "",
        "pitch_slot_label": "",
        "degree_slot_label": label,
    })
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




func _merge_match_records(target_idx: int, source_idx: int) -> int:
    if target_idx == source_idx:
        return target_idx
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
        var kept_name: String = await _conflict_dialog_fn.call("name", target["name"], source["name"])
        discarded_name = source["name"] if kept_name == target["name"] else target["name"]
        target["name"] = kept_name

    if int(target["seq_lo"]) == 0 and int(source["seq_lo"]) > 0:
        target["seq_lo"] = source["seq_lo"]
        target["seq_hi"] = source["seq_hi"]
    elif int(target["seq_lo"]) > 0 and int(source["seq_lo"]) > 0 and int(target["seq_lo"]) != int(source["seq_lo"]):
        var winning_seq: int = int(await _conflict_dialog_fn.call(
            "sequence position", str(int(target["seq_lo"])), str(int(source["seq_lo"]))))
        target["seq_lo"] = winning_seq
        target["seq_hi"] = winning_seq

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
        target["color_slot_label"] = await _conflict_dialog_fn.call("color slot label", target_label, source_label)

    var target_pitch_label: String = str(target.get("pitch_slot_label", ""))
    var source_pitch_label: String = str(source.get("pitch_slot_label", ""))
    if target_pitch_label == "" and source_pitch_label != "":
        target["pitch_slot_label"] = source_pitch_label
    elif target_pitch_label != "" and source_pitch_label != "" and target_pitch_label != source_pitch_label:
        target["pitch_slot_label"] = await _conflict_dialog_fn.call("pitch slot label", target_pitch_label, source_pitch_label)

    var target_degree_label: String = str(target.get("degree_slot_label", ""))
    var source_degree_label: String = str(source.get("degree_slot_label", ""))
    if target_degree_label == "" and source_degree_label != "":
        target["degree_slot_label"] = source_degree_label
    elif target_degree_label != "" and source_degree_label != "" and target_degree_label != source_degree_label:
        target["degree_slot_label"] = await _conflict_dialog_fn.call("degree slot label", target_degree_label, source_degree_label)

    _sync_color_states_from_star_idx(target_idx)

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

    var existing_by_star: int = _find_match_record_by_star_idx(star_idx)
    if existing_by_star >= 0 and existing_by_star != record_idx:
        record_idx = await _merge_match_records(record_idx, existing_by_star)

    var r: Dictionary = _match_records[record_idx]
    if int(r["star_idx"]) >= 0 and int(r["star_idx"]) != star_idx:
        var old_label: String = "%s (current)" % _anonymous_star_label(int(r["star_idx"]))
        var new_label: String = "%s (just checked)" % _anonymous_star_label(star_idx)
        var winner: String = await _conflict_dialog_fn.call(
            "star identity for '%s'" % star_name, old_label, new_label)
        if winner == old_label:
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
    var out: Array = []
    for r in _match_records:
        out.append({
            "name": r["name"],
            "seq_lo": r["seq_lo"], "seq_hi": r["seq_hi"],
            "seq_candidates": (r.get("seq_candidates", []) as Array).duplicate(),
            "color_states": (r["color_states"] as Dictionary).duplicate(),
            "pitch_states": (r["pitch_states"] as Dictionary).duplicate(),
            "degree_states": (r.get("degree_states", {}) as Dictionary).duplicate(),
            "name_states": (r.get("name_states", {}) as Dictionary).duplicate(),
            "manual_name_blocks": (r.get("manual_name_blocks", {}) as Dictionary).duplicate(),
            "manual_pitch_blocks": (r.get("manual_pitch_blocks", {}) as Dictionary).duplicate(),
            "manual_color_blocks": (r.get("manual_color_blocks", {}) as Dictionary).duplicate(),
            "protected_pitch_notes": (r.get("protected_pitch_notes", {}) as Dictionary).duplicate(),
            "protected_color_idxs": (r.get("protected_color_idxs", {}) as Dictionary).duplicate(),
            "protected_staff_names": (r.get("protected_staff_names", {}) as Dictionary).duplicate(),
            "pitch_revealed": bool(r.get("pitch_revealed", false)),
            "star_elim": (r.get("star_elim", {}) as Dictionary).duplicate(),
            "star_idx": r["star_idx"],
            "color_slot_label": str(r.get("color_slot_label", "")),
            "pitch_slot_label": str(r.get("pitch_slot_label", "")),
            "degree_slot_label": str(r.get("degree_slot_label", "")),
        })
    return out


func _load_match_records(data: Array) -> void:
    _match_records.clear()
    for entry in data:
        var e: Dictionary = entry
        var color_states: Dictionary = {}
        for ck in e.get("color_states", {}):
            color_states[int(ck)] = int(e["color_states"][ck])
        var pitch_states: Dictionary = {}
        for pk in e.get("pitch_states", {}):
            pitch_states[str(pk)] = int(e["pitch_states"][pk])
        var star_elim: Dictionary = {}
        for sk in e.get("star_elim", {}):
            star_elim[int(sk)] = int(e["star_elim"][sk])
        var name_states: Dictionary = {}
        for nk in e.get("name_states", {}):
            name_states[str(nk)] = int(e["name_states"][nk])
        var manual_name_blocks: Dictionary = {}
        for mnk in e.get("manual_name_blocks", {}):
            manual_name_blocks[str(mnk)] = true
        var manual_pitch_blocks: Dictionary = {}
        for mpk in e.get("manual_pitch_blocks", {}):
            manual_pitch_blocks[str(mpk)] = true
        var manual_color_blocks: Dictionary = {}
        for mck in e.get("manual_color_blocks", {}):
            manual_color_blocks[int(mck)] = true
        var degree_states: Dictionary = {}
        for dk in e.get("degree_states", {}):
            degree_states[int(dk)] = int(e["degree_states"][dk])
        var protected_pitch_notes: Dictionary = {}
        for ppk in e.get("protected_pitch_notes", {}):
            protected_pitch_notes[str(ppk)] = true
        var protected_color_idxs: Dictionary = {}
        for pck in e.get("protected_color_idxs", {}):
            protected_color_idxs[int(pck)] = true
        var protected_staff_names: Dictionary = {}
        for psnk in e.get("protected_staff_names", {}):
            protected_staff_names[str(psnk)] = true
        var seq_candidates: Array = []
        for v in e.get("seq_candidates", []):
            seq_candidates.append(int(v))
        _match_records.append({
            "name": str(e.get("name", "")),
            "seq_lo": int(e.get("seq_lo", 0)), "seq_hi": int(e.get("seq_hi", 0)),
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
            "pitch_revealed": bool(e.get("pitch_revealed", false)),
            "star_elim": star_elim,
            "pitch_carousel_idx": 0,
            "star_idx": int(e.get("star_idx", -1)),
            "color_slot_label": str(e.get("color_slot_label", "")),
            "pitch_slot_label": str(e.get("pitch_slot_label", "")),
            "degree_slot_label": str(e.get("degree_slot_label", "")),
        })


func _display_color_for_record(record_idx: int) -> Color:
    if record_idx < 0 or record_idx >= _match_records.size():
        return Color(0.2, 0.9, 0.2, 1)
    var r: Dictionary = _match_records[record_idx]
    for ck in r["color_states"]:
        if int(r["color_states"][ck]) == 1:
            return _host.STAR_COLORS_BY_IDX[int(ck)]
    return Color(0.2, 0.9, 0.2, 1)


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


func _propagate_color_confirmed_same_record(record_idx: int, confirmed_color_idx: int) -> void:
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
    # Same shape as _effective_pitch_state/_effective_color_state, for the
    # staff popup's NAME section (name_states/protected_staff_names on a
    # non-star record, e.g. a sequence slot) — ground truth via star_idx,
    # then the record's own confirmed name field, then the protect-derived
    # soft state folded in the same way.
    var r: Dictionary = _match_records[record_idx]
    var star_idx: int = int(r.get("star_idx", -1))
    if star_idx >= 0 and star_idx < _host._star_names.size():
        return 1 if _host._star_names[star_idx] == name_str else 2

    var rn: String = str(r.get("name", ""))
    if rn != "":
        return 1 if rn == name_str else 2

    var derived: int = _record_effective_state(record_idx, "name_states", "protected_staff_names", name_str)
    match derived:
        3: return 2
        4: return 0
        _: return derived


func _effective_degree_state(record_idx: int, degree: int) -> int:
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


func _records_provably_distinct(idx_a: int, idx_b: int) -> bool:
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

    for ci in _host.COLOR_NAME_LABELS.size():
        var sa: int = _effective_color_state(idx_a, ci)
        var sb: int = _effective_color_state(idx_b, ci)
        if (sa == 1 and sb == 2) or (sb == 1 and sa == 2):
            return true

    for note in _host._widgets._distinct_note_names():
        var pa: int = _effective_pitch_state(idx_a, note)
        var pb: int = _effective_pitch_state(idx_b, note)
        if (pa == 1 and pb == 2) or (pb == 1 and pa == 2):
            return true

    for name_str in _host._star_names:
        var na: int = _effective_name_state(idx_a, str(name_str))
        var nb: int = _effective_name_state(idx_b, str(name_str))
        if (na == 1 and nb == 2) or (nb == 1 and na == 2):
            return true

    for si in _host._star_count:
        var ea: int = _effective_star_state(idx_a, si)
        var eb: int = _effective_star_state(idx_b, si)
        if (ea == 1 and eb == 2) or (eb == 1 and ea == 2):
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
    _derive_color_eliminations_from_star_elim()
    _settle_singleton_sequences()
    _host._widgets._build_star_widgets()
    _host._widgets._build_star_tags()
    _host._melody_staff_panel.queue_redraw()
    _host._widgets.call_deferred("_populate_markers_panel")


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
