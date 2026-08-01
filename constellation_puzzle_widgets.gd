class_name ConstellationPuzzleWidgets
extends RefCounted

# Widget-construction half of the Constellation Study Overlay split
# (see docs/early_game_architecture_overview.md, §4, and the refactor plan
# this executes). Holds a back-reference to the host script for Control
# node refs, ground-truth arrays, and style boxes, plus a direct reference
# to the deduction engine (_deduction) — widget construction calls into it
# constantly (get-or-create/effective-state/etc.), so it's handed directly
# rather than reached through _host, per the original plan's design.
#
# Was built up incrementally, one self-contained UI cluster ("slice") at a
# time, each independently headless-boot-verified before the next.
# Complete: Slice 1 (markers panel), Slice 2 (Sort:tab record widgets,
# clue/fact helpers, _show_conflict_choice), Slice 3 (melody staff + Staff
# popup), Slice 4 (floating star widgets). Stage 2 complete.

var _host: ConstellationStudyOverlay = null
var _deduction: ConstellationPuzzleDeduction = null

# Shared puzzle-state color palette (confirmed/eliminated/protected/neutral/
# muted) — see puzzle_state_colors.gd for the full rationale. Single
# Inspector-editable source instead of ~25 duplicated Color(...) literals.
const STATE_COLORS: PuzzleStateColors = preload("res://puzzle_state_colors.tres")

# Staff popup column scaling — see _open_staff_popup()'s call sites and
# staff_popup.gd's _rebuild_columns(). Tune these if a section still
# needs scrolling for very large constellations.
const STAFF_POPUP_MAX_ROWS_PER_COLUMN: int = 6
const STAFF_POPUP_MAX_COLUMNS:         int = 4

func _staff_popup_column_count(row_count: int) -> int:
    if row_count <= 0:
        return 2
    return clampi(ceili(float(row_count) / STAFF_POPUP_MAX_ROWS_PER_COLUMN), 2, STAFF_POPUP_MAX_COLUMNS)


func setup(host: ConstellationStudyOverlay, deduction: ConstellationPuzzleDeduction) -> void:
    _host = host
    _deduction = deduction


# ==================================================
# MARKERS PANEL
# ==================================================
func _set_marker_tab(tab_idx: int) -> void:
    _host._active_marker_tab = tab_idx
    _host._tab_color.add_theme_stylebox_override("normal",
        _host._sb_tab_active if tab_idx == 0 else _host._sb_tab_inactive)
    _host._tab_sequence.add_theme_stylebox_override("normal",
        _host._sb_tab_active if tab_idx == 1 else _host._sb_tab_inactive)
    _host._tab_pitch.add_theme_stylebox_override("normal",
        _host._sb_tab_active if tab_idx == 2 else _host._sb_tab_inactive)
    _host._tab_proximity.add_theme_stylebox_override("normal",
        _host._sb_tab_active if tab_idx == 3 else _host._sb_tab_inactive)
    _host._tab_name_clues.add_theme_stylebox_override("normal",
        _host._sb_tab_active if tab_idx == 4 else _host._sb_tab_inactive)
    _populate_markers_panel()


func _populate_markers_panel() -> void:
    for child in _host._markers_content.get_children():
        child.queue_free()

    match _host._active_marker_tab:
        0: _populate_color_markers()
        1: _populate_sequence_markers()
        2: _populate_pitch_markers()
        3: _populate_proximity_markers()
        4: _populate_name_clues_markers()
        _: _populate_name_markers()


func _coerce_int(val, default: int) -> int:
    if typeof(val) == TYPE_INT or typeof(val) == TYPE_FLOAT:
        return int(val)
    return default


# _host._form_clues_cache round-trips through save data (see
# ConstellationStudyOverlay._load_constellation_data()'s chosen_form_clues
# read) — that load already guarantees the outer value is an Array, but not
# that every element is a Dictionary with well-typed fields. Appending a
# mixed-type Array into a typed Array[Dictionary] doesn't crash — Godot
# silently discards the WHOLE result (confirmed: one bad element blanks out
# every clue, not just itself), which would blank every Markers tab with no
# error. Build the result element-by-element from sanitized dicts instead.
func _all_final_clues_for_tabs() -> Array[Dictionary]:
    var result: Array[Dictionary] = []
    for raw in _host._form_clues_cache:
        if not (raw is Dictionary):
            continue
        var characteristics: Array = raw["characteristics"] if raw.get("characteristics") is Array else []
        result.append({
            "characteristics": characteristics,
            "text": str(raw.get("text", "")),
            "form_id": _coerce_int(raw.get("form_id", 0), 0),
        })
    return result


## Called when the player clicks the pinned-clue readout in the study
## panel's header — jumps back to whichever marker tab the clue was
## originally pinned from (_host._selected_clue_tab, recorded by
## _on_clue_row_clicked at selection time) and scrolls it into view, so
## working down a clue list doesn't require manually re-finding your
## place after tabbing away.
func _jump_to_selected_clue() -> void:
    if _host._selected_clue_text == "" or _host._selected_clue_tab < 0:
        return
    _set_marker_tab(_host._selected_clue_tab)
    # Wait a frame — _set_marker_tab()'s clear+repopulate happens
    # synchronously, but ensure_control_visible() needs the freshly-added
    # rows to have a settled layout (valid rects) to compute a scroll
    # offset from. Calling it in the same frame as the repopulate landed
    # at the top of the tab instead of the selected clue's actual
    # position.
    await _host.get_tree().process_frame
    for child in _host._markers_content.get_children():
        if child is PanelContainer and child.has_meta("clue_text") \
        and str(child.get_meta("clue_text")) == _host._selected_clue_text:
            _host._markers_scroll.ensure_control_visible(child)
            break


func _populate_color_markers() -> void:
    var shown: bool = false
    var neutral_col := STATE_COLORS.muted
    for clue in _all_final_clues_for_tabs():
        var characteristics: Array = clue.get("characteristics", [])
        if not ("Color" in characteristics):
            continue
        var text: String = str(clue.get("text", ""))
        if text == "":
            continue
        var col: Color = neutral_col if int(clue.get("form_id", 0)) == 2 else STATE_COLORS.neutral
        _host._markers_content.add_child(_make_clue_label(text, col))
        shown = true

    if not shown:
        var lbl := Label.new()
        lbl.text = "Color clues will appear here once the puzzle is generated."
        lbl.add_theme_color_override("font_color", Color(0.50, 0.42, 0.65, 1))
        lbl.add_theme_font_size_override("font_size", 13)
        lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
        _host._markers_content.add_child(lbl)


func _populate_sequence_markers() -> void:
    var shown: bool = false
    for clue in _all_final_clues_for_tabs():
        var characteristics: Array = clue.get("characteristics", [])
        if not ("Sequence" in characteristics):
            continue
        var text: String = str(clue.get("text", ""))
        if text == "":
            continue
        _host._markers_content.add_child(_make_clue_label(text, STATE_COLORS.neutral))
        shown = true

    if not shown:
        var lbl := Label.new()
        lbl.text = "Sequence clues will appear here once the puzzle is generated."
        lbl.add_theme_color_override("font_color", Color(0.50, 0.42, 0.65, 1))
        lbl.add_theme_font_size_override("font_size", 13)
        lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
        _host._markers_content.add_child(lbl)


func _populate_pitch_markers() -> void:
    var shown: bool = false
    var neutral_col := STATE_COLORS.muted
    for clue in _all_final_clues_for_tabs():
        var characteristics: Array = clue.get("characteristics", [])
        if not ("Pitch" in characteristics):
            continue
        var text: String = str(clue.get("text", ""))
        if text == "":
            continue
        var col: Color = neutral_col if int(clue.get("form_id", 0)) == 2 else STATE_COLORS.neutral
        _host._markers_content.add_child(_make_clue_label(text, col))
        shown = true

    if not shown:
        var lbl := Label.new()
        lbl.text = "Pitch clues will appear here once the puzzle is generated."
        lbl.add_theme_color_override("font_color", Color(0.50, 0.42, 0.65, 1))
        lbl.add_theme_font_size_override("font_size", 13)
        lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
        _host._markers_content.add_child(lbl)


func _populate_proximity_markers() -> void:
    var shown: bool = false
    for clue in _all_final_clues_for_tabs():
        var characteristics: Array = clue.get("characteristics", [])
        if not ("Proximity" in characteristics):
            continue
        var text: String = str(clue.get("text", ""))
        if text == "":
            continue
        _host._markers_content.add_child(_make_clue_label(text, STATE_COLORS.neutral))
        shown = true

    if not shown:
        var lbl := Label.new()
        lbl.text = "Proximity clues will appear here once the puzzle is generated."
        lbl.add_theme_color_override("font_color", Color(0.50, 0.42, 0.65, 1))
        lbl.add_theme_font_size_override("font_size", 13)
        lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
        _host._markers_content.add_child(lbl)


func _populate_name_clues_markers() -> void:
    var shown: bool = false
    for clue in _all_final_clues_for_tabs():
        var characteristics: Array = clue.get("characteristics", [])
        var text: String = str(clue.get("text", ""))
        if text == "":
            continue
        if not ("NameClues" in characteristics or _text_mentions_star_name(text)):
            continue
        _host._markers_content.add_child(_make_clue_label(text, STATE_COLORS.neutral))
        shown = true

    if not shown:
        var lbl := Label.new()
        lbl.text = "Name clues will appear here once the puzzle is generated."
        lbl.add_theme_color_override("font_color", Color(0.50, 0.42, 0.65, 1))
        lbl.add_theme_font_size_override("font_size", 13)
        lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
        _host._markers_content.add_child(lbl)


func _sort_matches(mode: int) -> void:
    if mode < 0 or mode > 4:
        push_warning("StudyOverlay: _sort_matches called with invalid mode %d, ignoring" % mode)
        return
    _host._matches_sort_mode = mode
    # Route through _set_marker_tab so _active_marker_tab correctly lands on
    # -1 (Matches/default) and the top-level tab highlighting clears. Without
    # this, _active_marker_tab stayed at whatever top tab was last active,
    # so any later refresh (e.g. a color toggle) would dispatch back to that
    # stale tab instead of staying on the Sort: view.
    _set_marker_tab(-1)


func _populate_name_markers() -> void:
    for child in _host._markers_content.get_children():
        child.queue_free()

    # Sort: sub-tab buttons live in SortSubTabBar, a sibling of the scroll
    # container — NOT inside _markers_content — so they stay pinned in view
    # regardless of scroll position. Rebuilt here (rather than once in
    # _ready) since _sort_matches() calls this function directly on every
    # button press, same as the dispatcher path does.
    for child in _host._sort_sub_tab_bar.get_children():
        child.queue_free()
    _host._sort_sub_tab_bar.visible = true
    _host._sort_sub_tab_bar.add_theme_constant_override("separation", 6)
    # Sequence (mode 1) and Degree (mode 4) tabs hidden for the Map/Staff
    # widget-space experiment (Djinncremental Notes, Map/Staff redesign) —
    # mode numbers deliberately left unrenumbered (still 0=Name,1=Sequence,
    # 2=Color,3=Pitch,4=Degree) for save compatibility and easy restoration;
    # just add the entries back to bring a tab back.
    var sort_entries: Array = [
        {"label": "Name",  "mode": 0},
        {"label": "Color", "mode": 2},
        {"label": "Pitch", "mode": 3},
    ]
    for entry in sort_entries:
        var btn := Button.new()
        btn.text = "Sort: %s" % entry["label"]
        btn.add_theme_font_size_override("font_size", 16)
        btn.custom_minimum_size = Vector2(0, 40)
        btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        btn.focus_mode = Control.FOCUS_NONE
        var mode: int = entry["mode"]
        btn.pressed.connect(func(): _sort_matches(mode))
        _host._sort_sub_tab_bar.add_child(btn)

    match _host._matches_sort_mode:
        0, -1:
            _populate_name_rows()
        1:
            _populate_sequence_slot_rows()
        2:
            _populate_color_group_rows()
        3:
            _populate_pitch_group_rows()
        4:
            _populate_degree_group_rows()
        _:
            push_warning("StudyOverlay: unknown _matches_sort_mode %d, resetting to Name" % _host._matches_sort_mode)
            _host._matches_sort_mode = 0
            _populate_name_rows()


func _text_mentions_star_name(text: String) -> bool:
    for n in _host._star_names:
        var name_str: String = str(n)
        if name_str != "" and text.find(name_str) != -1:
            return true
    return false


func _on_proximity_check(edge_key: String, btn_check: Button, btn_x: Button) -> void:
    var cur: int = int(_host._proximity_states.get(edge_key, 0))
    var new_state: int = 0 if cur == 1 else 1
    _host._proximity_states[edge_key] = new_state
    btn_check.modulate = STATE_COLORS.confirmed if new_state == 1 else Color(1,1,1,1.0)
    btn_x.modulate = Color(1,1,1,1.0)
    _deduction._save_puzzle_notes()


func _on_proximity_x(edge_key: String, btn_check: Button, btn_x: Button) -> void:
    var cur: int = int(_host._proximity_states.get(edge_key, 0))
    var new_state: int = 0 if cur == 2 else 2
    _host._proximity_states[edge_key] = new_state
    btn_x.modulate = STATE_COLORS.eliminated if new_state == 2 else Color(1,1,1,1.0)
    btn_check.modulate = Color(1,1,1,1.0)
    _deduction._save_puzzle_notes()


# ==================================================
# CONFLICT DIALOG (bound to _deduction._conflict_dialog_fn — see that member's
# comment for why the deduction-engine half calls through a Callable
# instead of reaching into this file directly)
# ==================================================
func _show_conflict_choice(what: String, value_a: String, value_b: String) -> String:
    var dlg := AcceptDialog.new()
    dlg.title = "Conflicting %s" % what
    dlg.dialog_text = "Two entries disagree on %s. Which is correct?" % what
    dlg.get_ok_button().hide()
    dlg.add_button("Keep: %s" % value_a, false, "choice_a")
    dlg.add_button("Keep: %s" % value_b, false, "choice_b")
    # AcceptDialog can be dismissed without either button — Escape or the
    # popup's own close corner both fire `canceled`, not `custom_action`
    # (root_ui.gd's save-corruption dialog already handles `canceled`
    # separately for exactly this reason). Since this function awaits
    # custom_action specifically, an unhandled cancel would leave that
    # await permanently unresolved — stalling whatever puzzle-state
    # resolution called this. Defaulting to value_a (keep the pre-existing
    # entry) guarantees the await always resumes.
    dlg.canceled.connect(func(): dlg.emit_signal("custom_action", "choice_a"))
    _host.add_child(dlg)
    dlg.popup_centered()
    var chosen_action: String = await dlg.custom_action
    dlg.queue_free()
    var winner: String = value_a if chosen_action == "choice_a" else value_b
    var loser: String = value_b if chosen_action == "choice_a" else value_a
    print("[CONFLICT] %s: kept '%s', discarded '%s'" % [what, winner, loser])
    return winner


# ==================================================
# SORT:TAB RECORD WIDGETS — Name/Pitch checklist popups, Color/Degree
# toggle rows, and the Sequence range row
# ==================================================
func _make_name_checklist_trigger_button(record_idx: int) -> Button:
    # Compact trigger, not the checklist itself — clicking it pops
    # _name_checklist_popup (a single shared, independent popup instance,
    # same lifecycle pattern as _staff_popup) positioned under the button.
    # Record-keyed (name_states), not the star widget's star_idx-keyed
    # checklist (star_elim) — a Sort:tab slot record (e.g. "Blue A")
    # frequently has no resolved star_idx yet to key against.
    var btn := Button.new()
    btn.custom_minimum_size = Vector2(110, 0)
    btn.add_theme_font_size_override("font_size", 13)
    btn.focus_mode = Control.FOCUS_NONE
    # Checks BOTH the record's own "name" field (set by identity confirms
    # elsewhere) and name_states (set by this checklist itself, either a
    # direct check or _settle_singleton_names narrowing it to one) — same
    # two sources _make_pitch_checklist_trigger_button already checks for
    # pitch_states; "name" alone left this button stuck on "Select Name"
    # even after the checklist had a confirmed row.
    var current_name: String = str(_deduction._match_records[record_idx].get("name", ""))
    if current_name == "":
        var name_states: Dictionary = _deduction._match_records[record_idx].get("name_states", {})
        for n in _host._star_names:
            var name_str: String = str(n)
            if int(name_states.get(name_str, 0)) == 1:
                current_name = name_str
                break
    btn.text = current_name if current_name != "" else "Select Name"
    var ridx := record_idx
    var btn_ref := btn
    btn.pressed.connect(func():
        # PopupPanel extends Window, not Control — see the identical
        # comment on the staff-popup open call for why get_screen_transform()
        # is required here (this is what was silently breaking left-click
        # on the popup's rows).
        var target: Vector2 = btn_ref.global_position + Vector2(0, btn_ref.size.y)
        _open_name_checklist_popup(ridx, btn_ref.get_viewport().get_screen_transform() * target))
    return btn


func _open_name_checklist_popup(record_idx: int, screen_pos: Vector2) -> void:
    _host._name_checklist_popup.clear_rows()
    var names_sorted: Array = _host._star_names.duplicate()
    names_sorted.sort_custom(func(a, b): return String(a).nocasecmp_to(String(b)) < 0)
    # A record another Sort:tab has already proven distinct from this one,
    # that has ITSELF confirmed a name, rules that name out here too — see
    # _compute_excluded_names_for. Computed once, not per-row.
    var excluded_names: Array[String] = _deduction._compute_excluded_names_for(record_idx)
    for n in names_sorted:
        var name_str: String = str(n)
        var state: int = _deduction._effective_name_state(record_idx, name_str)
        # Only checked when still neutral: a hard confirm/eliminate/
        # protect already decided wins over a cross-record inference.
        if state == 0 and excluded_names.has(name_str):
            state = 2
        _host._name_checklist_popup.add_name_row(name_str, state, STATE_COLORS.neutral)
    _host._name_checklist_popup.open(record_idx, screen_pos)


func _on_slot_name_check(record_idx: int, star_name: String, _row: StaffPopupRow) -> void:
    var r: Dictionary = _deduction._match_records[record_idx]
    var name_states: Dictionary = r.get("name_states", {})
    var cur: int = int(name_states.get(star_name, 0))
    if cur == 1:
        # Toggling back off — see _on_staff_name_check for why siblings
        # aren't restored here.
        name_states[star_name] = 0
        r["name_states"] = name_states
    else:
        _deduction._propagate_name_states_confirmed_same_record(record_idx, star_name)
    _deduction._save_puzzle_notes()
    _deduction._full_propagation_refresh()
    _open_name_checklist_popup(record_idx, _host._name_checklist_popup.position)


func _on_slot_name_undo_selects(record_idx: int) -> void:
    _deduction._undo_category_selects(record_idx, "name_states", "manual_name_blocks", "protected_staff_names", _host._star_names.duplicate())
    _deduction._save_puzzle_notes()
    _deduction._full_propagation_refresh()
    _open_name_checklist_popup(record_idx, _host._name_checklist_popup.position)


func _on_slot_name_undo_blocks(record_idx: int) -> void:
    _deduction._undo_category_blocks(record_idx, "name_states", "manual_name_blocks")
    _deduction._save_puzzle_notes()
    _deduction._full_propagation_refresh()
    _open_name_checklist_popup(record_idx, _host._name_checklist_popup.position)


func _on_slot_name_undo_all(record_idx: int) -> void:
    _deduction._undo_category_selects(record_idx, "name_states", "manual_name_blocks", "protected_staff_names", _host._star_names.duplicate())
    _deduction._undo_category_blocks(record_idx, "name_states", "manual_name_blocks")
    _deduction._save_puzzle_notes()
    _deduction._full_propagation_refresh()
    _open_name_checklist_popup(record_idx, _host._name_checklist_popup.position)


func _on_slot_name_x(record_idx: int, star_name: String, _row: StaffPopupRow) -> void:
    var r: Dictionary = _deduction._match_records[record_idx]
    var name_states: Dictionary = r.get("name_states", {})
    var cur: int = int(name_states.get(star_name, 0))
    name_states[star_name] = 0 if cur == 2 else 2
    r["name_states"] = name_states
    # Track this as a player-driven block (vs. sibling-clearing fallout from
    # a confirm) so the Undo row can tell the two apart later.
    var manual: Dictionary = r.get("manual_name_blocks", {})
    if cur == 2:
        manual.erase(star_name)
    else:
        manual[star_name] = true
    r["manual_name_blocks"] = manual
    _deduction._save_puzzle_notes()
    _deduction._full_propagation_refresh()
    _open_name_checklist_popup(record_idx, _host._name_checklist_popup.position)


func _on_slot_name_protect(record_idx: int, star_name: String) -> void:
    var r: Dictionary = _deduction._match_records[record_idx]
    var states: Dictionary = r.get("name_states", {})
    if int(states.get(star_name, 0)) != 0:
        return   # already hard-confirmed or hard-eliminated; right-click no-ops
    var protected: Dictionary = r.get("protected_staff_names", {})
    if protected.has(star_name):
        protected.erase(star_name)
    else:
        protected[star_name] = true
    r["protected_staff_names"] = protected
    _deduction._save_puzzle_notes()
    _deduction._full_propagation_refresh()
    _open_name_checklist_popup(record_idx, _host._name_checklist_popup.position)


func _make_pitch_checklist_trigger_button(record_idx: int) -> Button:
    # Same trigger-button/shared-popup pattern as
    # _make_name_checklist_trigger_button — see its comment for why
    # get_screen_transform() is required on the position passed to open().
    var btn := Button.new()
    btn.custom_minimum_size = Vector2(110, 0)
    btn.add_theme_font_size_override("font_size", 13)
    btn.focus_mode = Control.FOCUS_NONE
    var confirmed_note: String = ""
    var pitch_states: Dictionary = _deduction._match_records[record_idx].get("pitch_states", {})
    for f in _host._pitch_freqs:
        var n: String = ConstellationLogicPuzzle.note_name_for_freq(f)
        if int(pitch_states.get(n, 0)) == 1:
            confirmed_note = n
            break
    btn.text = confirmed_note if confirmed_note != "" else "Select Pitch"
    var ridx := record_idx
    var btn_ref := btn
    btn.pressed.connect(func():
        var target: Vector2 = btn_ref.global_position + Vector2(0, btn_ref.size.y)
        _open_pitch_checklist_popup(ridx, btn_ref.get_viewport().get_screen_transform() * target))
    return btn


func _open_pitch_checklist_popup(record_idx: int, screen_pos: Vector2) -> void:
    _host._pitch_checklist_popup.clear_rows()
    # A record another Sort:tab has already proven distinct from this one,
    # that has ITSELF confirmed a note whose incidence count is exactly
    # 1 (the only case where excluding it elsewhere is sound — a shared
    # note can't be excluded just because one of its stars is spoken for),
    # rules that note out here too — see _compute_excluded_pitches_for.
    var excluded_pitches: Array[String] = _deduction._compute_excluded_pitches_for(record_idx)
    for pitch_idx in _host._pitch_freqs.size():
        var f: float = _host._pitch_freqs[pitch_idx]
        var note_name: String = ConstellationLogicPuzzle.note_name_for_freq(f)
        var incidence_count: int = _deduction._pitch_star_count(note_name)
        var state: int = _deduction._effective_pitch_state(record_idx, note_name)
        if state == 0 and excluded_pitches.has(note_name):
            state = 2
        _host._pitch_checklist_popup.add_pitch_row(note_name, incidence_count, state, STATE_COLORS.neutral)
    _host._pitch_checklist_popup.open(record_idx, screen_pos)


func _on_pitch_checklist_check(record_idx: int, note_name: String, _row: StaffPopupRow) -> void:
    if bool(_deduction._match_records[record_idx].get("pitch_revealed", false)):
        return
    var pitch_states: Dictionary = _deduction._match_records[record_idx].get("pitch_states", {})
    var cur: int = int(pitch_states.get(note_name, 0))
    if cur == 1:
        # Toggling back off — see _on_staff_name_check for why siblings
        # aren't restored here.
        pitch_states[note_name] = 0
        _deduction._match_records[record_idx]["pitch_states"] = pitch_states
    else:
        _deduction._propagate_pitch_confirmed_same_record(record_idx, note_name)
    _deduction._save_puzzle_notes()
    _deduction._full_propagation_refresh()
    _open_pitch_checklist_popup(record_idx, _host._pitch_checklist_popup.position)


func _on_pitch_checklist_x(record_idx: int, note_name: String, _row: StaffPopupRow) -> void:
    if bool(_deduction._match_records[record_idx].get("pitch_revealed", false)):
        return
    var r: Dictionary = _deduction._match_records[record_idx]
    var pitch_states: Dictionary = r.get("pitch_states", {})
    var cur: int = int(pitch_states.get(note_name, 0))
    pitch_states[note_name] = 0 if cur == 2 else 2
    r["pitch_states"] = pitch_states
    # Track this as a player-driven block (vs. sibling-clearing fallout from
    # a confirm) so the Undo row can tell the two apart later.
    var manual: Dictionary = r.get("manual_pitch_blocks", {})
    if cur == 2:
        manual.erase(note_name)
    else:
        manual[note_name] = true
    r["manual_pitch_blocks"] = manual
    _deduction._save_puzzle_notes()
    _deduction._full_propagation_refresh()
    _open_pitch_checklist_popup(record_idx, _host._pitch_checklist_popup.position)


func _on_pitch_checklist_protect(record_idx: int, note_name: String) -> void:
    if bool(_deduction._match_records[record_idx].get("pitch_revealed", false)):
        return
    var r: Dictionary = _deduction._match_records[record_idx]
    var states: Dictionary = r.get("pitch_states", {})
    if int(states.get(note_name, 0)) != 0:
        return   # already hard-confirmed or hard-eliminated; right-click no-ops
    var protected: Dictionary = r.get("protected_pitch_notes", {})
    if protected.has(note_name):
        protected.erase(note_name)
    else:
        protected[note_name] = true
    r["protected_pitch_notes"] = protected
    _deduction._save_puzzle_notes()
    _deduction._full_propagation_refresh()
    _open_pitch_checklist_popup(record_idx, _host._pitch_checklist_popup.position)


func _on_pitch_checklist_undo_selects(record_idx: int) -> void:
    if bool(_deduction._match_records[record_idx].get("pitch_revealed", false)):
        return
    _deduction._undo_category_selects(record_idx, "pitch_states", "manual_pitch_blocks", "protected_pitch_notes", _distinct_note_names())
    # The confirmed note (if any) no longer exists once selects are undone —
    # same staleness fix _propagate_pitch_confirmed_same_record applies.
    var r: Dictionary = _deduction._match_records[record_idx]
    if str(r.get("pitch_slot_label", "")) != "":
        r["pitch_slot_label"] = ""
    _deduction._save_puzzle_notes()
    _deduction._full_propagation_refresh()
    _open_pitch_checklist_popup(record_idx, _host._pitch_checklist_popup.position)


func _on_pitch_checklist_undo_blocks(record_idx: int) -> void:
    if bool(_deduction._match_records[record_idx].get("pitch_revealed", false)):
        return
    _deduction._undo_category_blocks(record_idx, "pitch_states", "manual_pitch_blocks")
    _deduction._save_puzzle_notes()
    _deduction._full_propagation_refresh()
    _open_pitch_checklist_popup(record_idx, _host._pitch_checklist_popup.position)


func _on_pitch_checklist_undo_all(record_idx: int) -> void:
    if bool(_deduction._match_records[record_idx].get("pitch_revealed", false)):
        return
    _deduction._undo_category_selects(record_idx, "pitch_states", "manual_pitch_blocks", "protected_pitch_notes", _distinct_note_names())
    _deduction._undo_category_blocks(record_idx, "pitch_states", "manual_pitch_blocks")
    var r: Dictionary = _deduction._match_records[record_idx]
    if str(r.get("pitch_slot_label", "")) != "":
        r["pitch_slot_label"] = ""
    _deduction._save_puzzle_notes()
    _deduction._full_propagation_refresh()
    _open_pitch_checklist_popup(record_idx, _host._pitch_checklist_popup.position)


func _make_color_toggle_row_for_record(record_idx: int) -> HBoxContainer:
    var row := HBoxContainer.new()
    row.add_theme_constant_override("separation", 3)
    # Alphabetical order: Blue(0), Red(3), White(1), Yellow(2)
    var btn_order: Array = [0, 3, 1, 2]
    # A record another Sort:tab has already proven distinct from this one,
    # that has ITSELF confirmed a color whose incidence count is exactly 1
    # (the only case where excluding it elsewhere is sound), rules that
    # color out here too — see _compute_excluded_colors_for.
    var excluded_colors: Array[int] = _deduction._compute_excluded_colors_for(record_idx)
    for ci in btn_order:
        var btn := Button.new()
        btn.custom_minimum_size = Vector2(26, 24)
        btn.focus_mode = Control.FOCUS_NONE
        btn.add_theme_font_size_override("font_size", 13)
        var cidx: int = int(ci)
        var ridx := record_idx
        btn.pressed.connect(func(): _on_record_color_toggle(ridx, cidx, btn))
        btn.gui_input.connect(func(event: InputEvent):
            if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
                _on_record_color_eliminate(ridx, cidx, btn)
                btn.get_viewport().set_input_as_handled())
        # Effective state so a staff-popup "still possible" mark shows here too.
        var cur_state: int = _deduction._effective_color_state(record_idx, ci)
        if cur_state == 0 and excluded_colors.has(ci):
            cur_state = 2
        _style_color_toggle_btn(btn, ci, cur_state)
        row.add_child(btn)
    return row


func _on_record_color_toggle(record_idx: int, color_idx: int, btn: Button) -> void:
    if record_idx < 0 or record_idx >= _deduction._match_records.size():
        return
    var r: Dictionary = _deduction._match_records[record_idx]
    # Click-again-to-deselect: clicking an already-confirmed color resets
    # just this one button back to neutral — same toggle shape as the Staff
    # popup's _on_staff_color_check, matched here for consistency.
    var cur: int = int(r["color_states"].get(color_idx, 0))
    var new_state: int = 0 if cur == 1 else 1
    if new_state == 1 and not await _deduction._confirm_color_against_ground_truth(record_idx, color_idx, true):
        return
    if new_state == 1 and not await _deduction._confirm_color_against_cap(record_idx, color_idx):
        return
    if new_state == 0:
        # FIXED 2026-07-27 — deselecting a CONFIRM needs to release the
        # sibling-clearing fallout too, not just this button's own state.
        # Confirming color_idx forced every other color to eliminated
        # (_propagate_color_confirmed_same_record); undoing just color_idx's
        # own state left those siblings stuck red forever, only fixable one
        # at a time by re-confirming a different color. _undo_category_selects
        # is exactly the existing whole-record tool for this — releases the
        # confirm plus every non-manually-blocked eliminated sibling, while
        # correctly leaving alone any color the player independently
        # right-click-eliminated (tracked in manual_color_blocks).
        var color_values: Array = []
        for ci in _host.COLOR_NAME_LABELS.size():
            color_values.append(ci)
        _deduction._undo_category_selects(record_idx, "color_states", "manual_color_blocks", "protected_color_idxs", color_values)
    else:
        r["color_states"][color_idx] = new_state
        _deduction._propagate_color_confirmed_same_record(record_idx, color_idx)
    _style_color_toggle_btn(btn, color_idx, new_state)
    _deduction._recompute_color_star_elim(record_idx)
    _deduction._save_puzzle_notes()
    _deduction._full_propagation_refresh()


func _on_record_color_eliminate(record_idx: int, color_idx: int, btn: Button) -> void:
    if record_idx < 0 or record_idx >= _deduction._match_records.size():
        return
    var r: Dictionary = _deduction._match_records[record_idx]
    # Click-again-to-deselect (right-click an already-eliminated color) —
    # same shape as _on_staff_color_x.
    var cur: int = int(r["color_states"].get(color_idx, 0))
    var new_state: int = 0 if cur == 2 else 2
    if new_state == 2 and not await _deduction._confirm_color_against_ground_truth(record_idx, color_idx, false):
        return
    r["color_states"][color_idx] = new_state
    # Same manual-block bookkeeping as _on_staff_color_x — this toggle row
    # writes the same color_states/manual_color_blocks dict on the same
    # record, so the Staff popup's Undo row needs to see blocks placed here.
    var manual: Dictionary = r.get("manual_color_blocks", {})
    if cur == 2:
        manual.erase(color_idx)
    else:
        manual[color_idx] = true
    r["manual_color_blocks"] = manual
    _style_color_toggle_btn(btn, color_idx, new_state)
    _deduction._recompute_color_star_elim(record_idx)
    _deduction._save_puzzle_notes()
    _deduction._full_propagation_refresh()


func _make_degree_toggle_row_for_record(record_idx: int) -> HBoxContainer:
    var row := HBoxContainer.new()
    row.add_theme_constant_override("separation", 3)
    var degrees_set: Dictionary = {}
    for i in _host._star_count:
        var deg: int = int(_host._star_degrees[i]) if i < _host._star_degrees.size() else 0
        degrees_set[deg] = true
    var degree_list: Array = degrees_set.keys()
    degree_list.sort()
    for deg in degree_list:
        var btn := Button.new()
        btn.text = str(deg)
        btn.custom_minimum_size = Vector2(32, 24)
        btn.focus_mode = Control.FOCUS_NONE
        btn.add_theme_font_size_override("font_size", 13)
        var deg_val: int = int(deg)
        var ridx := record_idx
        btn.pressed.connect(func(): _on_record_degree_toggle(ridx, deg_val, btn))
        btn.gui_input.connect(func(event: InputEvent):
            if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
                _on_record_degree_eliminate(ridx, deg_val, btn)
                btn.get_viewport().set_input_as_handled())
        var cur_state: int = int(_deduction._match_records[record_idx]["degree_states"].get(deg, 0))
        _style_degree_toggle_btn(btn, deg_val, cur_state)
        row.add_child(btn)
    return row


func _style_degree_toggle_btn(btn: Button, _degree: int, state: int) -> void:
    match state:
        0:
            btn.modulate = Color(1, 1, 1, 1.0)
            btn.add_theme_stylebox_override("normal",
                btn.get_theme_stylebox("normal", "Button"))
        1:
            btn.modulate = STATE_COLORS.confirmed
            btn.add_theme_stylebox_override("normal",
                btn.get_theme_stylebox("normal", "Button"))
        2:
            btn.modulate = STATE_COLORS.eliminated
            btn.add_theme_stylebox_override("normal",
                btn.get_theme_stylebox("normal", "Button"))
        _:
            btn.modulate = Color(1, 1, 1, 1.0)


func _on_record_degree_toggle(record_idx: int, degree: int, btn: Button) -> void:
    if record_idx < 0 or record_idx >= _deduction._match_records.size():
        return
    _deduction._propagate_degree_confirmed_same_record(record_idx, degree)
    _style_degree_toggle_btn(btn, degree, 1)
    _deduction._save_puzzle_notes()
    _deduction._full_propagation_refresh()


func _on_record_degree_eliminate(record_idx: int, degree: int, btn: Button) -> void:
    if record_idx < 0 or record_idx >= _deduction._match_records.size():
        return
    var r: Dictionary = _deduction._match_records[record_idx]
    r["degree_states"][degree] = 2
    _style_degree_toggle_btn(btn, degree, 2)
    _deduction._save_puzzle_notes()
    _deduction._full_propagation_refresh()


func _make_sequence_range_row_for_record(record_idx: int, row_color: Color) -> HBoxContainer:
    var row := HBoxContainer.new()
    row.add_theme_constant_override("separation", 2)

    var bounds: Array = _deduction._effective_seq_bounds(record_idx)

    var edit_lo := LineEdit.new()
    edit_lo.custom_minimum_size = Vector2(20, 24)
    edit_lo.max_length = 2
    edit_lo.placeholder_text = "–"
    var lo_val: int = _deduction._exclusive_display_lo(int(bounds[0]), int(bounds[1]))
    edit_lo.text = str(lo_val) if lo_val > 0 else ""
    edit_lo.add_theme_font_size_override("font_size", 12)
    edit_lo.add_theme_constant_override("minimum_character_width", 2)
    _style_range_edit(edit_lo, row_color)
    row.add_child(edit_lo)

    var lbl_lt := Label.new()
    lbl_lt.text = "<"
    lbl_lt.add_theme_font_size_override("font_size", 13)
    lbl_lt.add_theme_color_override("font_color", Color(0.7, 0.65, 0.85, 0.9))
    row.add_child(lbl_lt)

    var edit_mid := LineEdit.new()
    edit_mid.custom_minimum_size = Vector2(58, 24)
    edit_mid.max_length = 12
    edit_mid.placeholder_text = "–"
    edit_mid.text = _deduction._compressed_possible_positions_str(record_idx)
    edit_mid.add_theme_font_size_override("font_size", 11)
    edit_mid.alignment = HORIZONTAL_ALIGNMENT_CENTER
    _style_range_edit(edit_mid, row_color)
    row.add_child(edit_mid)

    var lbl_gt := Label.new()
    lbl_gt.text = "<"
    lbl_gt.add_theme_font_size_override("font_size", 13)
    lbl_gt.add_theme_color_override("font_color", Color(0.7, 0.65, 0.85, 0.9))
    row.add_child(lbl_gt)

    var edit_hi := LineEdit.new()
    edit_hi.custom_minimum_size = Vector2(20, 24)
    edit_hi.max_length = 2
    edit_hi.placeholder_text = "–"
    var hi_val: int = _deduction._exclusive_display_hi(int(bounds[0]), int(bounds[1]))
    edit_hi.text = str(hi_val) if hi_val > 0 else ""
    edit_hi.add_theme_font_size_override("font_size", 12)
    edit_hi.add_theme_constant_override("minimum_character_width", 2)
    _style_range_edit(edit_hi, row_color)
    row.add_child(edit_hi)

    var ridx := record_idx
    edit_lo.text_submitted.connect(func(_t): _on_record_range_committed(ridx, edit_lo, edit_hi))
    edit_lo.focus_exited.connect(func(): _on_record_range_committed(ridx, edit_lo, edit_hi))
    edit_hi.text_submitted.connect(func(_t): _on_record_range_committed(ridx, edit_lo, edit_hi))
    edit_hi.focus_exited.connect(func(): _on_record_range_committed(ridx, edit_lo, edit_hi))
    edit_mid.text_submitted.connect(func(_t): _on_record_middle_committed(ridx, edit_lo, edit_mid, edit_hi))
    edit_mid.focus_exited.connect(func(): _on_record_middle_committed(ridx, edit_lo, edit_mid, edit_hi))

    return row


func _on_record_range_committed(record_idx: int, lo_edit: LineEdit, hi_edit: LineEdit) -> void:
    if record_idx < 0 or record_idx >= _deduction._match_records.size():
        return
    var raw_lo: String = lo_edit.text.strip_edges()
    var raw_hi: String = hi_edit.text.strip_edges()

    var typed_lo: int = int(raw_lo) if raw_lo.is_valid_int() else 0
    var typed_hi: int = int(raw_hi) if raw_hi.is_valid_int() else 0

    if typed_lo < 1 or typed_lo > _host._star_count: typed_lo = 0
    if typed_hi < 1 or typed_hi > _host._star_count: typed_hi = 0

    if typed_lo > 0 and typed_hi > 0 and typed_lo > typed_hi:
        var tmp := typed_lo; typed_lo = typed_hi; typed_hi = tmp

    var converted: Array = _deduction._parse_exclusive_bounds(typed_lo, typed_hi)
    var lo: int = int(converted[0])
    var hi: int = int(converted[1])

    var r: Dictionary = _deduction._match_records[record_idx]

    # Same self-conflict protection _confirm_match_record_identity already
    # gives star identity: if this record was already pinned to an exact
    # position and this commit pins it to a DIFFERENT exact position, ask
    # rather than silently overwriting — catches a misclick same as a
    # genuine correction, no way to tell those apart from the value alone.
    var old_lo: int = int(r.get("seq_lo", 0))
    var old_hi: int = int(r.get("seq_hi", 0))
    if old_lo > 0 and old_lo == old_hi and lo > 0 and lo == hi and old_lo != lo:
        var winner: String = await _deduction._conflict_dialog_fn.call("sequence position", str(old_lo), str(lo))
        if winner == str(old_lo):
            lo_edit.text = str(_deduction._exclusive_display_lo(old_lo, old_hi))
            hi_edit.text = str(_deduction._exclusive_display_hi(old_lo, old_hi))
            _deduction._full_propagation_refresh()
            return

    r["seq_lo"] = lo
    r["seq_hi"] = hi
    r["seq_candidates"] = []

    lo_edit.text = str(_deduction._exclusive_display_lo(lo, hi)) if lo > 0 else ""
    hi_edit.text = str(_deduction._exclusive_display_hi(lo, hi)) if hi > 0 else ""

    if lo > 0 and lo == hi:
        var existing_idx: int = _deduction._find_match_record_by_exact_seq(lo)
        if existing_idx >= 0 and existing_idx != record_idx:
            record_idx = await _deduction._merge_match_records(record_idx, existing_idx)

    _deduction._save_puzzle_notes()
    _deduction._full_propagation_refresh()


func _on_record_middle_committed(record_idx: int, lo_edit: LineEdit, mid_edit: LineEdit, hi_edit: LineEdit) -> void:
    var raw: String = mid_edit.text.strip_edges()
    if raw == "":
        _deduction._match_records[record_idx]["seq_candidates"] = []
        mid_edit.text = _deduction._compressed_possible_positions_str(record_idx)
        return

    var parsed: Array = _deduction._parse_candidate_list(raw)
    var valid: Array = []
    for p in parsed:
        if p >= 1 and p <= _host._star_count:
            valid.append(p)

    if valid.is_empty():
        mid_edit.text = _deduction._compressed_possible_positions_str(record_idx)
        return

    if valid.size() == 1:
        lo_edit.text = str(valid[0])
        hi_edit.text = str(valid[0])
        _on_record_range_committed(record_idx, lo_edit, hi_edit)
        return

    _deduction._match_records[record_idx]["seq_candidates"] = valid
    _deduction._match_records[record_idx]["seq_lo"] = 0
    _deduction._match_records[record_idx]["seq_hi"] = 0
    _deduction._save_puzzle_notes()
    _deduction._full_propagation_refresh()


func _on_record_name_selected(record_idx: int, selected_name: String) -> void:
    if record_idx < 0 or record_idx >= _deduction._match_records.size():
        return
    var r: Dictionary = _deduction._match_records[record_idx]
    var old_name: String = str(r.get("name", ""))
    if old_name == selected_name:
        return

    if selected_name == "":
        r["name"] = ""
        _deduction._save_puzzle_notes()
        _deduction._full_propagation_refresh()
        return

    # Same self-conflict protection as the sequence commit above: this
    # record was already given a different name, ask before overwriting.
    if old_name != "" and old_name != selected_name:
        var winner: String = await _deduction._conflict_dialog_fn.call("name", old_name, selected_name)
        if winner == old_name:
            _deduction._full_propagation_refresh()
            return

    r["name"] = selected_name

    var existing_idx: int = _deduction._find_match_record_by_name(selected_name)
    if existing_idx >= 0 and existing_idx != record_idx:
        record_idx = await _deduction._merge_match_records(record_idx, existing_idx)

    _deduction._save_puzzle_notes()
    _deduction._full_propagation_refresh()


# ==================================================
# RANGE CALLBACKS (floating star-widget versions — see the Sort:tab
# versions above for the record-row equivalents)
# ==================================================
func _on_widget_range_committed(star_idx: int, lo_edit: LineEdit, hi_edit: LineEdit) -> void:
    if star_idx < 0 or star_idx >= _host._star_count:
        return
    var raw_lo: String = lo_edit.text.strip_edges()
    var raw_hi: String = hi_edit.text.strip_edges()

    var typed_lo: int = int(raw_lo) if raw_lo.is_valid_int() else 0
    var typed_hi: int = int(raw_hi) if raw_hi.is_valid_int() else 0

    if typed_lo < 1 or typed_lo > _host._star_count: typed_lo = 0
    if typed_hi < 1 or typed_hi > _host._star_count: typed_hi = 0

    if typed_lo > 0 and typed_hi > 0 and typed_lo > typed_hi:
        var tmp := typed_lo; typed_lo = typed_hi; typed_hi = tmp

    var converted: Array = _deduction._parse_exclusive_bounds(typed_lo, typed_hi)
    var lo: int = int(converted[0])
    var hi: int = int(converted[1])

    var record_idx: int = _deduction._get_or_create_match_record_for_star_idx(star_idx)
    var r: Dictionary = _deduction._match_records[record_idx]

    # Same self-conflict protection as the sequence-slot row's own commit
    # handler above — this star's record was already pinned to an exact
    # position and this commit pins it to a DIFFERENT exact position.
    var old_lo: int = int(r.get("seq_lo", 0))
    var old_hi: int = int(r.get("seq_hi", 0))
    if old_lo > 0 and old_lo == old_hi and lo > 0 and lo == hi and old_lo != lo:
        var winner: String = await _deduction._conflict_dialog_fn.call("sequence position", str(old_lo), str(lo))
        if winner == str(old_lo):
            lo_edit.text = str(_deduction._exclusive_display_lo(old_lo, old_hi))
            hi_edit.text = str(_deduction._exclusive_display_hi(old_lo, old_hi))
            _deduction._full_propagation_refresh()
            return

    lo_edit.text = str(_deduction._exclusive_display_lo(lo, hi)) if lo > 0 else ""
    hi_edit.text = str(_deduction._exclusive_display_hi(lo, hi)) if hi > 0 else ""

    r["seq_lo"] = lo
    r["seq_hi"] = hi
    r["seq_candidates"] = []

    if lo > 0 and lo == hi:
        var existing_idx: int = _deduction._find_match_record_by_exact_seq(lo)
        if existing_idx >= 0 and existing_idx != record_idx:
            record_idx = await _deduction._merge_match_records(record_idx, existing_idx)

    _deduction._save_puzzle_notes()
    _deduction._full_propagation_refresh()


func _on_widget_middle_committed(star_idx: int, lo_edit: LineEdit, mid_edit: LineEdit, hi_edit: LineEdit) -> void:
    var record_idx: int = _deduction._get_or_create_match_record_for_star_idx(star_idx)
    var raw: String = mid_edit.text.strip_edges()
    if raw == "":
        _deduction._match_records[record_idx]["seq_candidates"] = []
        mid_edit.text = _deduction._compressed_possible_positions_str(record_idx)
        return
    var parsed: Array = _deduction._parse_candidate_list(raw)
    var valid: Array = []
    for p in parsed:
        if p >= 1 and p <= _host._star_count:
            valid.append(p)
    if valid.is_empty():
        mid_edit.text = _deduction._compressed_possible_positions_str(record_idx)
        return
    if valid.size() == 1:
        lo_edit.text = str(valid[0])
        hi_edit.text = str(valid[0])
        _on_widget_range_committed(star_idx, lo_edit, hi_edit)
        return
    _deduction._match_records[record_idx]["seq_candidates"] = valid
    _deduction._match_records[record_idx]["seq_lo"] = 0
    _deduction._match_records[record_idx]["seq_hi"] = 0
    _deduction._save_puzzle_notes()
    _deduction._full_propagation_refresh()


# ==================================================
# CLUE LIST
# ==================================================
var _color_regexes: Array = []


func _bbcode_for_clue_text(text: String) -> String:
    if _color_regexes.is_empty():
        for color_name in _host.COLOR_NAME_LABELS:
            var re := RegEx.new()
            re.compile("(?i)\\b%s\\b" % color_name.replace("-", "\\-"))
            _color_regexes.append(re)
    var bb: String = text
    for i in _color_regexes.size():
        var col_hex: String = _host.STAR_COLORS_BY_IDX[i].to_html()
        bb = (_color_regexes[i] as RegEx).sub(bb, "[color=#%s]$0[/color]" % col_hex, true)
    return bb


func _make_clue_label(text: String, _color: Color) -> PanelContainer:
    var pc := PanelContainer.new()
    pc.add_theme_stylebox_override("panel", _host._sb_selected if text == _host._selected_clue_text else _host._sb_clue_normal)
    pc.mouse_filter = Control.MOUSE_FILTER_STOP
    pc.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
    pc.set_meta("clue_text", text)
    var rtl := RichTextLabel.new()
    rtl.bbcode_enabled = true
    rtl.fit_content = true
    rtl.scroll_active = false
    rtl.mouse_filter = Control.MOUSE_FILTER_PASS
    rtl.text = _bbcode_for_clue_text(text)
    rtl.add_theme_color_override("default_color", STATE_COLORS.unresolved_fallback)
    rtl.add_theme_font_size_override("normal_font_size", 18)
    rtl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    rtl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    pc.add_child(rtl)

    var captured_text := text
    pc.gui_input.connect(func(event: InputEvent):
        if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
            _on_clue_row_clicked(captured_text)
            pc.get_viewport().set_input_as_handled())
    return pc


func _on_clue_row_clicked(text: String) -> void:
    # Click again to unpin — a plain, expected toggle, not something that
    # needed a separate ask.
    _host._selected_clue_text = "" if _host._selected_clue_text == text else text
    # Remember which tab this was pinned from, so the header readout's
    # click-to-jump (_jump_to_selected_clue) can return to exactly that
    # tab instead of guessing via characteristics — a clue can in
    # principle satisfy more than one tab's filter.
    _host._selected_clue_tab = _host._active_marker_tab if _host._selected_clue_text != "" else -1
    _host._select_clue(_bbcode_for_clue_text(_host._selected_clue_text) if _host._selected_clue_text != "" else "")
    # Re-style in place rather than a full repopulate — cheaper, and a
    # repopulate would re-run every populate function's own clue filtering
    # logic just to change which one row looks selected.
    for child in _host._markers_content.get_children():
        if child is PanelContainer and child.has_meta("clue_text"):
            var ct: String = str(child.get_meta("clue_text"))
            child.add_theme_stylebox_override("panel", _host._sb_selected if ct == _host._selected_clue_text else _host._sb_clue_normal)


func _make_fact_row(label_text: String, control: Control, color: Color) -> HBoxContainer:
    var row := HBoxContainer.new()
    row.add_theme_constant_override("separation", 4)
    var lbl := Label.new()
    lbl.text = label_text
    lbl.add_theme_font_size_override("font_size", 16)
    lbl.add_theme_color_override("font_color", Color(color.r, color.g, color.b, 1.0))
    row.add_child(lbl)
    row.add_child(control)
    return row


func _make_fact_line(text: String, color: Color) -> Label:
    var lbl := Label.new()
    lbl.text = text
    lbl.add_theme_font_size_override("font_size", 16)
    lbl.add_theme_color_override("font_color", Color(color.r, color.g, color.b, 0.9))
    lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    return lbl


# ==================================================
# ORPHANED SORT:TAB ROW BUILDERS — see docs/early_game_architecture_overview.md
# §4 for why these never got a section header of their own before this split
# ==================================================
func _build_sequence_slot_row(slot: int) -> void:
    var record_idx: int = _deduction._get_or_create_match_record_for_seq(slot)
    var row_color: Color = _deduction._display_color_for_record(record_idx)

    var row := HBoxContainer.new()
    row.add_theme_constant_override("separation", 8)
    row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    _host._markers_content.add_child(row)

    var seq_lbl := Label.new()
    seq_lbl.text = _ordinal(slot)
    seq_lbl.custom_minimum_size = Vector2(64, 0)
    seq_lbl.add_theme_font_size_override("font_size", 16)
    seq_lbl.add_theme_color_override("font_color", row_color)
    row.add_child(seq_lbl)

    var facts_vbox := VBoxContainer.new()
    facts_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    facts_vbox.add_theme_constant_override("separation", 1)
    row.add_child(facts_vbox)

    facts_vbox.add_child(_make_fact_row("Name:", _make_name_checklist_trigger_button(record_idx), row_color))
    facts_vbox.add_child(_make_fact_row("Color:", _make_color_toggle_row_for_record(record_idx), row_color))
    facts_vbox.add_child(_make_fact_row("Pitch:", _make_pitch_checklist_trigger_button(record_idx), row_color))

    _host._markers_content.add_child(HSeparator.new())


func _populate_sequence_slot_rows() -> void:
    for slot in range(1, _host._star_count + 1):
        _build_sequence_slot_row(slot)


func _build_color_group_row(color_idx: int, position_in_group: int) -> void:
    var record_idx: int = _deduction._get_or_create_match_record_for_color_slot(color_idx, position_in_group)
    var row_color: Color = _deduction._display_color_for_record(record_idx)

    var row := HBoxContainer.new()
    row.add_theme_constant_override("separation", 8)
    row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    _host._markers_content.add_child(row)

    var color_lbl := Label.new()
    color_lbl.text = _host.COLOR_NAME_LABELS[color_idx]
    color_lbl.custom_minimum_size = Vector2(64, 0)
    color_lbl.add_theme_font_size_override("font_size", 16)
    color_lbl.add_theme_color_override("font_color", _host.STAR_COLORS_BY_IDX[color_idx])
    row.add_child(color_lbl)

    var facts_vbox := VBoxContainer.new()
    facts_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    facts_vbox.add_theme_constant_override("separation", 1)
    row.add_child(facts_vbox)

    facts_vbox.add_child(_make_fact_row("Name:", _make_name_checklist_trigger_button(record_idx), row_color))
    facts_vbox.add_child(_make_fact_row("Sequence:", _make_sequence_range_row_for_record(record_idx, row_color), row_color))
    facts_vbox.add_child(_make_fact_row("Pitch:", _make_pitch_checklist_trigger_button(record_idx), row_color))

    _host._markers_content.add_child(HSeparator.new())


func _populate_color_group_rows() -> void:
    _deduction._debug_dump_named_records()
    var color_order: Array = range(_host.COLOR_NAME_LABELS.size())
    color_order.sort_custom(func(a, b):
        return String(_host.COLOR_NAME_LABELS[a]).nocasecmp_to(String(_host.COLOR_NAME_LABELS[b])) < 0)
    for ci in color_order:
        var count_in_color: int = 0
        for i in _host._star_count:
            if clamp(_host._star_colors[i] if i < _host._star_colors.size() else 1, 0, 3) == ci:
                count_in_color += 1
        for pos in count_in_color:
            _build_color_group_row(ci, pos)


func _build_pitch_group_row(pitch_freq: float, position_in_group: int) -> void:
    var record_idx: int = _deduction._get_or_create_match_record_for_pitch_slot(pitch_freq, position_in_group)
    var known_star_color: int = _deduction._known_color_for_record(record_idx)
    # Unlike _display_color_for_record (used as row_color on every other
    # Sort:tab row), this also checks ground truth via star_idx, not just
    # an explicit color_states confirm — needed now that this row has no
    # Color selector of its own to ever write color_states directly (see
    # below); without this, every Pitch-slot row's fact labels would stay
    # stuck at the unresolved/neutral color forever, even after the
    # player has listened to the star and its color is fully knowable.
    var row_color: Color = _host.STAR_COLORS_BY_IDX[known_star_color] if known_star_color >= 0 else _deduction._display_color_for_record(record_idx)

    var row := HBoxContainer.new()
    row.add_theme_constant_override("separation", 8)
    row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    _host._markers_content.add_child(row)

    var pitch_lbl := Label.new()
    pitch_lbl.text = ConstellationLogicPuzzle.note_name_for_freq(pitch_freq)
    pitch_lbl.custom_minimum_size = Vector2(64, 0)
    pitch_lbl.add_theme_font_size_override("font_size", 16)
    pitch_lbl.add_theme_color_override("font_color",
        _host.STAR_COLORS_BY_IDX[known_star_color] if known_star_color >= 0 else row_color)
    row.add_child(pitch_lbl)
    if known_star_color >= 0:
        var swatch := ColorRect.new()
        swatch.color = _host.STAR_COLORS_BY_IDX[known_star_color]
        swatch.custom_minimum_size = Vector2(10, 10)
        swatch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
        row.add_child(swatch)

    var facts_vbox := VBoxContainer.new()
    facts_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    facts_vbox.add_theme_constant_override("separation", 1)
    row.add_child(facts_vbox)

    # No Color selector here — a star's color is already fully knowable
    # for free by running through every star with the Listen toggle, same
    # tier as this row's own note name (see the swatch/known_star_color
    # handling above), so a separate manual Color entry here was pure UI
    # clutter, never adding information the row wasn't already showing.
    facts_vbox.add_child(_make_fact_row("Name:", _make_name_checklist_trigger_button(record_idx), row_color))
    facts_vbox.add_child(_make_fact_row("Sequence:", _make_sequence_range_row_for_record(record_idx, row_color), row_color))

    _host._markers_content.add_child(HSeparator.new())


func _populate_pitch_group_rows() -> void:
    var pitch_freqs: Array = []
    for pf in _host._pitch_freqs:
        if not pitch_freqs.has(pf):
            pitch_freqs.append(pf)
    pitch_freqs.sort_custom(func(a, b): return float(a) < float(b))

    for pf in pitch_freqs:
        var count_in_pitch: int = _deduction._pitch_star_count(ConstellationLogicPuzzle.note_name_for_freq(pf))
        for pos in count_in_pitch:
            _build_pitch_group_row(pf, pos)


func _populate_degree_group_rows() -> void:
    _deduction._debug_dump_named_records()
    var degree_order: Array = []
    var degrees_set: Dictionary = {}
    for i in _host._star_count:
        var deg: int = int(_host._star_degrees[i]) if i < _host._star_degrees.size() else 0
        degrees_set[deg] = true
    for d in degrees_set.keys():
        degree_order.append(int(d))
    degree_order.sort()
    for deg in degree_order:
        var count_in_degree: int = 0
        for i in _host._star_count:
            if i < _host._star_degrees.size() and int(_host._star_degrees[i]) == deg:
                count_in_degree += 1
        for pos in count_in_degree:
            _build_degree_group_row(deg, pos)


func _build_degree_group_row(degree: int, position_in_group: int) -> void:
    var record_idx: int = _deduction._get_or_create_match_record_for_degree_slot(degree, position_in_group)
    var row_color: Color = _deduction._display_color_for_record(record_idx)
    var row := HBoxContainer.new()
    row.add_theme_constant_override("separation", 8)
    row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    _host._markers_content.add_child(row)
    var degree_lbl := Label.new()
    var word: String = "connection" if degree == 1 else "connections"
    degree_lbl.text = "%d %s" % [degree, word]
    degree_lbl.custom_minimum_size = Vector2(80, 0)
    degree_lbl.add_theme_font_size_override("font_size", 16)
    degree_lbl.add_theme_color_override("font_color", row_color)
    row.add_child(degree_lbl)
    var facts_vbox := VBoxContainer.new()
    facts_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    facts_vbox.add_theme_constant_override("separation", 1)
    row.add_child(facts_vbox)
    facts_vbox.add_child(_make_fact_row("Name:", _make_name_checklist_trigger_button(record_idx), row_color))
    facts_vbox.add_child(_make_fact_row("Color:", _make_color_toggle_row_for_record(record_idx), row_color))
    facts_vbox.add_child(_make_fact_row("Sequence:", _make_sequence_range_row_for_record(record_idx, row_color), row_color))
    _host._markers_content.add_child(HSeparator.new())


func _build_name_row(name_str: String) -> void:
    var record_idx: int = _deduction._get_or_create_match_record_for_name(name_str)
    var row_color: Color = _deduction._display_color_for_record(record_idx)

    var row := HBoxContainer.new()
    row.add_theme_constant_override("separation", 8)
    row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    _host._markers_content.add_child(row)

    var name_lbl := Label.new()
    name_lbl.text = name_str
    name_lbl.custom_minimum_size = Vector2(90, 0)
    name_lbl.clip_text = true
    name_lbl.add_theme_font_size_override("font_size", 16)
    name_lbl.add_theme_color_override("font_color", row_color)
    row.add_child(name_lbl)

    var facts_vbox := VBoxContainer.new()
    facts_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    facts_vbox.add_theme_constant_override("separation", 1)
    row.add_child(facts_vbox)

    facts_vbox.add_child(_make_fact_row("Color:", _make_color_toggle_row_for_record(record_idx), row_color))
    facts_vbox.add_child(_make_fact_row("Sequence:", _make_sequence_range_row_for_record(record_idx, row_color), row_color))
    facts_vbox.add_child(_make_fact_row("Pitch:", _make_pitch_checklist_trigger_button(record_idx), row_color))

    _host._markers_content.add_child(HSeparator.new())


func _populate_name_rows() -> void:
    var names_sorted: Array = _host._star_names.duplicate()
    names_sorted.sort_custom(func(a, b): return String(a).nocasecmp_to(String(b)) < 0)
    for n in names_sorted:
        _build_name_row(String(n))


# ==================================================
# MELODY BAR SCORE — piano-roll drawing + click-to-open the Staff popup
# ==================================================
func _freq_for_note_name(note_name: String) -> float:
    for f in _host._pitch_freqs:
        if ConstellationLogicPuzzle.note_name_for_freq(f) == note_name:
            return f
    return -1.0


func _freq_to_y_fraction(freq: float) -> float:
    # 0.0 = lowest note in this constellation's scale, 1.0 = highest.
    if _host._pitch_freqs.is_empty() or freq < 0.0:
        return 0.5
    var min_f: float = _host._pitch_freqs[0]
    var max_f: float = _host._pitch_freqs[0]
    for f in _host._pitch_freqs:
        min_f = minf(min_f, f)
        max_f = maxf(max_f, f)
    if is_equal_approx(max_f, min_f):
        return 0.5
    return (freq - min_f) / (max_f - min_f)


func _draw_melody_staff() -> void:
    var panel_size: Vector2 = _host._melody_staff_panel.size
    if _host._star_count <= 0 or panel_size.x <= 0.0 or panel_size.y <= 0.0:
        return

    var margin_x: float = 20.0
    var margin_top: float = 14.0
    var margin_bottom: float = 20.0
    var usable_w: float = panel_size.x - margin_x * 2.0
    var usable_h: float = panel_size.y - margin_top - margin_bottom
    var step_x: float = usable_w / float(maxi(_host._star_count - 1, 1))

    var baseline_y: float = margin_top + usable_h * 0.5
    var baseline_col := STATE_COLORS.muted
    _host._melody_staff_panel.draw_line(
        Vector2(margin_x, baseline_y), Vector2(margin_x + usable_w, baseline_y), baseline_col, 1.0)

    # Faint measure dividers, every 4 notes — a piano-roll rhythm cue, not
    # tied to the actual melody's real phrase structure (which varies per
    # constellation and isn't something the UI should assume it knows).
    var bar_col := STATE_COLORS.muted
    var pos: int = 4
    while pos < _host._star_count:
        var bx: float = margin_x + step_x * float(pos)
        _host._melody_staff_panel.draw_line(
            Vector2(bx, margin_top), Vector2(bx, margin_top + usable_h), bar_col, 1.0)
        pos += 4

    var note_col := STATE_COLORS.neutral
    var unknown_col := STATE_COLORS.muted
    var font := ThemeDB.fallback_font
    var font_size_small := 16

    for seq_pos in range(1, _host._star_count + 1):
        var x: float = margin_x + step_x * float(seq_pos - 1)
        var marker: Dictionary = _deduction._melody_marker_for_position(seq_pos)

        if marker["has_position"] and marker["pitch_known"]:
            var freq: float = _freq_for_note_name(str(marker["note_name"]))
            var frac: float = _freq_to_y_fraction(freq)
            var y: float = margin_top + usable_h * (1.0 - frac)
            _host._melody_staff_panel.draw_circle(Vector2(x, y), 5.0, note_col)
            var label: String = str(marker["note_name"])
            var label_w: float = font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size_small).x
            _host._melody_staff_panel.draw_string(font, Vector2(x - label_w * 0.5, y - 9.0),
                label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size_small, note_col)
        elif marker["has_position"]:
            var qw: float = font.get_string_size("?", HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
            _host._melody_staff_panel.draw_string(font, Vector2(x - qw * 0.5, baseline_y + 4.0),
                "?", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, unknown_col)

        var num_label: String = str(seq_pos)
        var nw: float = font.get_string_size(num_label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size_small).x
        var known_color: int = _deduction._known_color_for_seq_position(seq_pos)
        var num_col: Color = _host.STAR_COLORS_BY_IDX[known_color] if known_color >= 0 else _host.UNKNOWN_SEQ_COLOR
        _host._melody_staff_panel.draw_string(font, Vector2(x - nw * 0.5, margin_top + usable_h + 14.0),
            num_label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size_small, num_col)


func _on_melody_staff_input(event: InputEvent) -> void:
    if not (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT):
        return
    if _host._star_count <= 0:
        return

    var panel_size: Vector2 = _host._melody_staff_panel.size
    var margin_x: float = 20.0
    var usable_w: float = panel_size.x - margin_x * 2.0
    var step_x: float = usable_w / float(maxi(_host._star_count - 1, 1))

    var click_x: float = event.position.x
    var nearest_pos: int = 1
    var nearest_dist: float = INF
    for seq_pos in range(1, _host._star_count + 1):
        var x: float = margin_x + step_x * float(seq_pos - 1)
        var d: float = abs(click_x - x)
        if d < nearest_dist:
            nearest_dist = d
            nearest_pos = seq_pos

    if nearest_dist <= step_x * 0.5:
        # PopupPanel extends Window, not Control — its position is actual
        # screen/window pixels, not this canvas's logical coordinate space.
        # Without get_screen_transform(), any viewport stretch/scale leaves
        # the popup's real position mismatched from where its content
        # visually renders, which silently breaks left-click (Godot's
        # click-outside-to-dismiss check only gates left-click, so it
        # intercepts left-clicks against the wrong bounds while right-click
        # skips that check and still hit-tests correctly).
        var target: Vector2 = _host._melody_staff_panel.global_position + Vector2(click_x, event.position.y) - Vector2(90, 0)
        _open_staff_popup(nearest_pos, _host._melody_staff_panel.get_viewport().get_screen_transform() * target)


func _open_staff_popup(seq_pos: int, screen_pos: Vector2) -> void:
    _host._staff_popup_seq_pos = seq_pos
    var record_idx: int = _deduction._get_or_create_match_record_for_seq(seq_pos)

    _host._staff_popup.clear_all_rows()

    # Column counts scale with content instead of a fixed 2, so a section
    # spreads wider rather than getting taller and taller (Name in
    # particular scales with star_count) — needed anyway for
    # constellations with more stars than fit nicely in 2 columns, and
    # also what keeps the popup from growing tall enough to cover the
    # study panel's clue readout above it.
    _host._staff_popup.set_pitch_column_count(_staff_popup_column_count(_host._pitch_freqs.size()))
    _host._staff_popup.set_color_column_count(_staff_popup_column_count(_host.COLOR_NAME_LABELS.size()))
    _host._staff_popup.set_name_column_count(_staff_popup_column_count(_host._star_count))

    # Add pitch rows — same cross-record exclusion as
    # _open_pitch_checklist_popup, since the Staff popup is a third UI
    # surface hitting the exact same records (see
    # _compute_excluded_pitches_for).
    var excluded_pitches: Array[String] = _deduction._compute_excluded_pitches_for(record_idx)
    for pitch_idx in _host._pitch_freqs.size():
        var f: float = _host._pitch_freqs[pitch_idx]
        var note_name: String = ConstellationLogicPuzzle.note_name_for_freq(f)
        var incidence_count: int = _deduction._pitch_star_count(note_name)
        var state: int = _deduction._effective_pitch_state(record_idx, note_name)
        if state == 0 and excluded_pitches.has(note_name):
            state = 2
        _host._staff_popup.add_pitch_row(note_name, incidence_count, state, STATE_COLORS.neutral)

    # Add color rows — same cross-record exclusion as
    # _make_color_toggle_row_for_record (see _compute_excluded_colors_for).
    var excluded_colors: Array[int] = _deduction._compute_excluded_colors_for(record_idx)
    for ci in _host.COLOR_NAME_LABELS.size():
        var cstate: int = _deduction._effective_color_state(record_idx, ci)
        if cstate == 0 and excluded_colors.has(ci):
            cstate = 2
        _host._staff_popup.add_color_row(_host.COLOR_NAME_LABELS[ci], ci, cstate, _host.STAR_COLORS_BY_IDX[ci])

    # Add name rows — same cross-record exclusion as
    # _open_name_checklist_popup (see _compute_excluded_names_for).
    var all_names: Array[String] = []
    for j in _host._star_count:
        all_names.append(_host._star_names[j] if j < _host._star_names.size() else "?")
    all_names.sort_custom(func(a, b): return String(a).nocasecmp_to(String(b)) < 0)
    var excluded_names: Array[String] = _deduction._compute_excluded_names_for(record_idx)
    for name_str in all_names:
        var state: int = _deduction._effective_name_state(record_idx, name_str)
        if state == 0 and excluded_names.has(name_str):
            state = 2
        _host._staff_popup.add_name_row(name_str, state, STATE_COLORS.neutral)

    # Vertically center the popup within the study panel instead of
    # anchoring its top edge at the click point — the melody staff sits
    # near the bottom of the panel, so a click-anchored top edge left the
    # (now correctly-sized, post row-clear fix) popup bottom-justified
    # against the panel rather than centered in it. Computed after row
    # population so get_contents_minimum_size() reflects the final
    # content height. X stays click-driven (unchanged) — only Y is
    # recentered here.
    var panel: Control = _host.get_node(_host.PANEL_ROOT_PATH)
    var popup_height: float = _host._staff_popup.get_contents_minimum_size().y
    var panel_center_local: Vector2 = panel.global_position + panel.size * 0.5
    var target_top_local: Vector2 = Vector2(panel_center_local.x, panel_center_local.y - popup_height * 0.5)
    screen_pos.y = (panel.get_viewport().get_screen_transform() * target_top_local).y

    _host._staff_popup.open(seq_pos, record_idx, screen_pos)


func _on_staff_pitch_check(record_idx: int, note_name: String, _row: StaffPopupRow) -> void:
    if bool(_deduction._match_records[record_idx].get("pitch_revealed", false)):
        return
    var pitch_states: Dictionary = _deduction._match_records[record_idx].get("pitch_states", {})
    var cur: int = int(pitch_states.get(note_name, 0))
    var new_state: int = 0 if cur == 1 else 1
    if new_state == 1:
        _deduction._propagate_pitch_confirmed_same_record(record_idx, note_name)
    else:
        pitch_states[note_name] = new_state
        _deduction._match_records[record_idx]["pitch_states"] = pitch_states
    _deduction._save_puzzle_notes()
    _deduction._full_propagation_refresh()
    _open_staff_popup(_host._staff_popup_seq_pos, _host._staff_popup.position)


func _on_staff_pitch_x(record_idx: int, note_name: String, _row: StaffPopupRow) -> void:
    if bool(_deduction._match_records[record_idx].get("pitch_revealed", false)):
        return
    var r: Dictionary = _deduction._match_records[record_idx]
    var pitch_states: Dictionary = r.get("pitch_states", {})
    var cur: int = int(pitch_states.get(note_name, 0))
    pitch_states[note_name] = 0 if cur == 2 else 2
    r["pitch_states"] = pitch_states
    # Track this as a player-driven block (vs. sibling-clearing fallout from
    # a confirm) so the Undo row can tell the two apart later.
    var manual: Dictionary = r.get("manual_pitch_blocks", {})
    if cur == 2:
        manual.erase(note_name)
    else:
        manual[note_name] = true
    r["manual_pitch_blocks"] = manual
    _deduction._save_puzzle_notes()
    _deduction._full_propagation_refresh()
    _open_staff_popup(_host._staff_popup_seq_pos, _host._staff_popup.position)


func _on_staff_pitch_protect(record_idx: int, note_name: String) -> void:
    if not bool(_deduction._match_records[record_idx].get("pitch_revealed", false)):
        _on_record_value_protect_toggle(record_idx, "pitch_states", "protected_pitch_notes", note_name)


func _on_staff_color_check(record_idx: int, color_idx: int, _row: StaffPopupRow) -> void:
    var r: Dictionary = _deduction._match_records[record_idx]
    var cur: int = int(r["color_states"].get(color_idx, 0))
    var new_state: int = 0 if cur == 1 else 1
    if new_state == 1 and not await _deduction._confirm_color_against_ground_truth(record_idx, color_idx, true):
        return
    if new_state == 1 and not await _deduction._confirm_color_against_cap(record_idx, color_idx):
        return
    if new_state == 0:
        # FIXED 2026-07-27 — same sibling-fallout gap as
        # _on_record_color_toggle; see that function's comment.
        var color_values: Array = []
        for ci in _host.COLOR_NAME_LABELS.size():
            color_values.append(ci)
        _deduction._undo_category_selects(record_idx, "color_states", "manual_color_blocks", "protected_color_idxs", color_values)
    else:
        r["color_states"][color_idx] = new_state
        _deduction._propagate_color_confirmed_same_record(record_idx, color_idx)
    _deduction._recompute_color_star_elim(record_idx)
    _deduction._save_puzzle_notes()
    _deduction._full_propagation_refresh()
    _open_staff_popup(_host._staff_popup_seq_pos, _host._staff_popup.position)


func _on_staff_color_x(record_idx: int, color_idx: int, _row: StaffPopupRow) -> void:
    var r: Dictionary = _deduction._match_records[record_idx]
    var cur: int = int(r["color_states"].get(color_idx, 0))
    var new_state: int = 0 if cur == 2 else 2
    if new_state == 2 and not await _deduction._confirm_color_against_ground_truth(record_idx, color_idx, false):
        return
    r["color_states"][color_idx] = new_state
    # Track this as a player-driven block (vs. sibling-clearing fallout from
    # a confirm) so the Undo row can tell the two apart later.
    var manual: Dictionary = r.get("manual_color_blocks", {})
    if cur == 2:
        manual.erase(color_idx)
    else:
        manual[color_idx] = true
    r["manual_color_blocks"] = manual
    _deduction._recompute_color_star_elim(record_idx)
    _deduction._save_puzzle_notes()
    _deduction._full_propagation_refresh()
    _open_staff_popup(_host._staff_popup_seq_pos, _host._staff_popup.position)


func _on_staff_color_protect(record_idx: int, color_idx: int) -> void:
    _on_record_value_protect_toggle(record_idx, "color_states", "protected_color_idxs", color_idx)


func _on_staff_name_check(record_idx: int, star_name: String, _row: StaffPopupRow) -> void:
    var r: Dictionary = _deduction._match_records[record_idx]
    var name_states: Dictionary = r.get("name_states", {})
    var cur: int = int(name_states.get(star_name, 0))
    if cur == 1:
        # Toggling back off — just this name reverts to neutral; siblings
        # already eliminated by the confirm below stay as they were, same
        # "eliminations are sticky" behavior as color/pitch/degree.
        name_states[star_name] = 0
        r["name_states"] = name_states
    else:
        _deduction._propagate_name_states_confirmed_same_record(record_idx, star_name)
    _deduction._save_puzzle_notes()
    _deduction._full_propagation_refresh()
    _open_staff_popup(_host._staff_popup_seq_pos, _host._staff_popup.position)


func _on_staff_name_x(record_idx: int, star_name: String, _row: StaffPopupRow) -> void:
    var r: Dictionary = _deduction._match_records[record_idx]
    var name_states: Dictionary = r.get("name_states", {})
    var cur: int = int(name_states.get(star_name, 0))
    name_states[star_name] = 0 if cur == 2 else 2
    r["name_states"] = name_states
    # Track this as a player-driven block (vs. sibling-clearing fallout from
    # a confirm) so the Undo row can tell the two apart later.
    var manual: Dictionary = r.get("manual_name_blocks", {})
    if cur == 2:
        manual.erase(star_name)
    else:
        manual[star_name] = true
    r["manual_name_blocks"] = manual
    _deduction._save_puzzle_notes()
    _deduction._full_propagation_refresh()
    _open_staff_popup(_host._staff_popup_seq_pos, _host._staff_popup.position)


func _on_staff_name_protect(record_idx: int, star_name: String) -> void:
    _on_record_value_protect_toggle(record_idx, "name_states", "protected_staff_names", star_name)


func _all_star_names_padded() -> Array:
    # Matches _open_staff_popup's own name-row enumeration exactly, so Undo
    # covers precisely the keys that popup could have written into
    # name_states (padding with "?" if _star_names is short, same as there).
    var names: Array = []
    for j in _host._star_count:
        names.append(_host._star_names[j] if j < _host._star_names.size() else "?")
    return names


func _on_staff_pitch_undo_selects(record_idx: int) -> void:
    if bool(_deduction._match_records[record_idx].get("pitch_revealed", false)):
        return
    _deduction._undo_category_selects(record_idx, "pitch_states", "manual_pitch_blocks", "protected_pitch_notes", _distinct_note_names())
    var r: Dictionary = _deduction._match_records[record_idx]
    if str(r.get("pitch_slot_label", "")) != "":
        r["pitch_slot_label"] = ""
    _deduction._save_puzzle_notes()
    _deduction._full_propagation_refresh()
    _open_staff_popup(_host._staff_popup_seq_pos, _host._staff_popup.position)


func _on_staff_pitch_undo_blocks(record_idx: int) -> void:
    if bool(_deduction._match_records[record_idx].get("pitch_revealed", false)):
        return
    _deduction._undo_category_blocks(record_idx, "pitch_states", "manual_pitch_blocks")
    _deduction._save_puzzle_notes()
    _deduction._full_propagation_refresh()
    _open_staff_popup(_host._staff_popup_seq_pos, _host._staff_popup.position)


func _on_staff_pitch_undo_all(record_idx: int) -> void:
    if bool(_deduction._match_records[record_idx].get("pitch_revealed", false)):
        return
    _deduction._undo_category_selects(record_idx, "pitch_states", "manual_pitch_blocks", "protected_pitch_notes", _distinct_note_names())
    _deduction._undo_category_blocks(record_idx, "pitch_states", "manual_pitch_blocks")
    var r: Dictionary = _deduction._match_records[record_idx]
    if str(r.get("pitch_slot_label", "")) != "":
        r["pitch_slot_label"] = ""
    _deduction._save_puzzle_notes()
    _deduction._full_propagation_refresh()
    _open_staff_popup(_host._staff_popup_seq_pos, _host._staff_popup.position)


func _on_staff_color_undo_selects(record_idx: int) -> void:
    var color_values: Array = []
    for ci in _host.COLOR_NAME_LABELS.size():
        color_values.append(ci)
    _deduction._undo_category_selects(record_idx, "color_states", "manual_color_blocks", "protected_color_idxs", color_values)
    var r: Dictionary = _deduction._match_records[record_idx]
    if str(r.get("color_slot_label", "")) != "":
        r["color_slot_label"] = ""
    # FIXED 2026-07-27 — this Undo used to reset color_states without ever
    # touching star_elim, leaving stale "this star can't be the name" marks
    # behind from whatever confirm/eliminate just got undone. See
    # _recompute_color_star_elim's own comment for the full story.
    _deduction._recompute_color_star_elim(record_idx)
    _deduction._save_puzzle_notes()
    _deduction._full_propagation_refresh()
    _open_staff_popup(_host._staff_popup_seq_pos, _host._staff_popup.position)


func _on_staff_color_undo_blocks(record_idx: int) -> void:
    _deduction._undo_category_blocks(record_idx, "color_states", "manual_color_blocks")
    _deduction._recompute_color_star_elim(record_idx)
    _deduction._save_puzzle_notes()
    _deduction._full_propagation_refresh()
    _open_staff_popup(_host._staff_popup_seq_pos, _host._staff_popup.position)


func _on_staff_color_undo_all(record_idx: int) -> void:
    var color_values: Array = []
    for ci in _host.COLOR_NAME_LABELS.size():
        color_values.append(ci)
    _deduction._undo_category_selects(record_idx, "color_states", "manual_color_blocks", "protected_color_idxs", color_values)
    _deduction._undo_category_blocks(record_idx, "color_states", "manual_color_blocks")
    _deduction._recompute_color_star_elim(record_idx)
    var r: Dictionary = _deduction._match_records[record_idx]
    if str(r.get("color_slot_label", "")) != "":
        r["color_slot_label"] = ""
    _deduction._save_puzzle_notes()
    _deduction._full_propagation_refresh()
    _open_staff_popup(_host._staff_popup_seq_pos, _host._staff_popup.position)


func _on_staff_name_undo_selects(record_idx: int) -> void:
    _deduction._undo_category_selects(record_idx, "name_states", "manual_name_blocks", "protected_staff_names", _all_star_names_padded())
    _deduction._save_puzzle_notes()
    _deduction._full_propagation_refresh()
    _open_staff_popup(_host._staff_popup_seq_pos, _host._staff_popup.position)


func _on_staff_name_undo_blocks(record_idx: int) -> void:
    _deduction._undo_category_blocks(record_idx, "name_states", "manual_name_blocks")
    _deduction._save_puzzle_notes()
    _deduction._full_propagation_refresh()
    _open_staff_popup(_host._staff_popup_seq_pos, _host._staff_popup.position)


func _on_staff_name_undo_all(record_idx: int) -> void:
    _deduction._undo_category_selects(record_idx, "name_states", "manual_name_blocks", "protected_staff_names", _all_star_names_padded())
    _deduction._undo_category_blocks(record_idx, "name_states", "manual_name_blocks")
    _deduction._save_puzzle_notes()
    _deduction._full_propagation_refresh()
    _open_staff_popup(_host._staff_popup_seq_pos, _host._staff_popup.position)


func _on_record_value_protect_toggle(record_idx: int, states_key: String, protect_key: String, value_key, reopen_staff_popup: bool = true) -> void:
    var r: Dictionary = _deduction._match_records[record_idx]
    var states: Dictionary = r.get(states_key, {})
    var base: int = int(states.get(value_key, 0))
    if base != 0:
        return   # already hard-confirmed or hard-eliminated; right-click no-ops
    var protected: Dictionary = r.get(protect_key, {})
    if protected.has(value_key):
        protected.erase(value_key)
    else:
        protected[value_key] = true
    r[protect_key] = protected
    _deduction._save_puzzle_notes()
    _deduction._full_propagation_refresh()
    # Sort:tab checklists pass reopen_staff_popup = false — there's no
    # popup open to refresh, and this would otherwise pop one open
    # unexpectedly using a stale _staff_popup_seq_pos.
    if reopen_staff_popup:
        _open_staff_popup(_host._staff_popup_seq_pos, _host._staff_popup.position)


# ==================================================
# FLOATING STAR WIDGETS
# ==================================================
func _build_star_widgets() -> void:
    # Always deferred: this tears down and rebuilds every star widget,
    # including whichever one's own LineEdit/Button signal may currently be
    # mid-dispatch on the call stack that triggered this (e.g. a range
    # field's focus_exited firing as part of the very rebuild it causes).
    # Mutating a node's ancestor tree synchronously from inside its own
    # signal handler is a hard Godot error ("Parent node is busy setting up
    # children") — deferring by one frame, imperceptible for a UI rebuild,
    # removes the race entirely rather than requiring every call site to
    # remember to defer it themselves.
    call_deferred("_build_star_widgets_impl")


func _build_star_widgets_impl() -> void:
    # Tear down any previous widgets.
    for w in _host._star_widgets:
        if is_instance_valid(w):
            w.queue_free()
    _host._star_widgets.clear()

    if _host._star_screen_pos.is_empty():
        return

    for i in _host._star_count:
        var color_idx: int = _host._star_colors[i] if i < _host._star_colors.size() else 1
        var star_color: Color = _host.STAR_COLORS_BY_IDX[clamp(color_idx, 0, 3)]

        # Root container — no background, just a layout anchor.
        var root := VBoxContainer.new()
        root.mouse_filter = Control.MOUSE_FILTER_PASS
        root.add_theme_constant_override("separation", 4)
        root.z_index = 10
        _host._star_map_control.add_child(root)
        _host._star_widgets.append(root)
        root.visible = (i == _host._selected_star) and not _host._widget_closed.get(i, false)

        # ── Range row ──────────────────────────────────────────────
        var range_row := HBoxContainer.new()
        range_row.mouse_filter = Control.MOUSE_FILTER_PASS
        range_row.add_theme_constant_override("separation", 3)

        var existing_record: int = _deduction._get_or_create_match_record_for_star_idx(i)
        var star_bounds: Array = _deduction._effective_seq_bounds(existing_record)

        var edit_lo := LineEdit.new()
        edit_lo.custom_minimum_size = Vector2(20, 28)
        edit_lo.max_length = 2
        edit_lo.placeholder_text = "–"
        var display_lo: int = _deduction._exclusive_display_lo(int(star_bounds[0]), int(star_bounds[1]))
        edit_lo.text = str(display_lo) if display_lo > 0 else ""
        edit_lo.add_theme_font_size_override("font_size", 13)
        edit_lo.add_theme_constant_override("minimum_character_width", 2)
        _style_range_edit(edit_lo, star_color)
        range_row.add_child(edit_lo)

        var lbl_lt := Label.new()
        lbl_lt.text = "<"
        lbl_lt.add_theme_font_size_override("font_size", 14)
        lbl_lt.add_theme_color_override("font_color", Color(0.7, 0.65, 0.85, 1.0))
        lbl_lt.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
        range_row.add_child(lbl_lt)

        var edit_mid := LineEdit.new()
        edit_mid.custom_minimum_size = Vector2(62, 28)
        edit_mid.max_length = 12
        edit_mid.placeholder_text = "–"
        edit_mid.text = _deduction._compressed_possible_positions_str(existing_record)
        edit_mid.add_theme_font_size_override("font_size", 11)
        edit_mid.alignment = HORIZONTAL_ALIGNMENT_CENTER
        _style_range_edit(edit_mid, star_color)
        range_row.add_child(edit_mid)

        var lbl_gt := Label.new()
        lbl_gt.text = "<"
        lbl_gt.add_theme_font_size_override("font_size", 14)
        lbl_gt.add_theme_color_override("font_color", Color(0.7, 0.65, 0.85, 1.0))
        lbl_gt.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
        range_row.add_child(lbl_gt)

        var edit_hi := LineEdit.new()
        edit_hi.custom_minimum_size = Vector2(20, 28)
        edit_hi.max_length = 2
        edit_hi.placeholder_text = "–"
        var display_hi: int = _deduction._exclusive_display_hi(int(star_bounds[0]), int(star_bounds[1]))
        edit_hi.text = str(display_hi) if display_hi > 0 else ""
        edit_hi.add_theme_font_size_override("font_size", 13)
        edit_hi.add_theme_constant_override("minimum_character_width", 2)
        _style_range_edit(edit_hi, star_color)
        range_row.add_child(edit_hi)

        var spacer := Control.new()
        spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        range_row.add_child(spacer)

        var btn_close := Button.new()
        btn_close.text = "✕"
        btn_close.custom_minimum_size = Vector2(28, 28)
        btn_close.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        btn_close.focus_mode = Control.FOCUS_NONE
        btn_close.add_theme_font_size_override("font_size", 14)
        btn_close.flat = false
        range_row.add_child(btn_close)

        root.add_child(range_row)

        # ── Pitch label ────────────────────────────────────────────
        # Shows the revealed note once the player has clicked this star
        # with Listen toggled on (_on_pitch_listen_star_clicked sets
        # pitch_revealed on the record); literal "PITCH" placeholder until
        # then — Pitch is designed to be primarily Listen-revealed rather
        # than deduced, so this deliberately doesn't show a state that was
        # only inferred some other way.
        var pitch_lbl := Label.new()
        pitch_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
        pitch_lbl.add_theme_font_size_override("font_size", 13)
        if bool(_deduction._match_records[existing_record].get("pitch_revealed", false)):
            pitch_lbl.text = _confirmed_pitch_str_for_star(i)
            pitch_lbl.add_theme_color_override("font_color", star_color)
        else:
            pitch_lbl.text = "PITCH"
            pitch_lbl.add_theme_color_override("font_color", Color(0.5, 0.45, 0.6, 1.0))
        root.add_child(pitch_lbl)

        # Capture index for lambdas.
        var si := i
        var lo_ref := edit_lo
        var mid_ref := edit_mid
        var hi_ref := edit_hi
        edit_lo.text_submitted.connect(func(_t): _on_widget_range_committed(si, lo_ref, hi_ref))
        edit_lo.focus_exited.connect(func(): _on_widget_range_committed(si, lo_ref, hi_ref))
        edit_hi.text_submitted.connect(func(_t): _on_widget_range_committed(si, lo_ref, hi_ref))
        edit_hi.focus_exited.connect(func(): _on_widget_range_committed(si, lo_ref, hi_ref))
        edit_mid.text_submitted.connect(func(_t): _on_widget_middle_committed(si, lo_ref, mid_ref, hi_ref))
        edit_mid.focus_exited.connect(func(): _on_widget_middle_committed(si, lo_ref, mid_ref, hi_ref))

        var close_si := i
        btn_close.pressed.connect(func(): _host._widget_closed[close_si] = true; root.visible = false)

        # ── Reset buttons ──────────────────────────────────────────
        var reset_row := HBoxContainer.new()
        reset_row.mouse_filter = Control.MOUSE_FILTER_PASS
        reset_row.add_theme_constant_override("separation", 3)
        root.add_child(reset_row)

        var btn_undo_sel := Button.new()
        btn_undo_sel.text = "Undo selects"
        btn_undo_sel.focus_mode = Control.FOCUS_NONE
        btn_undo_sel.custom_minimum_size = Vector2(0, 30)
        btn_undo_sel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        btn_undo_sel.add_theme_font_size_override("font_size", 11)
        reset_row.add_child(btn_undo_sel)

        var btn_undo_block := Button.new()
        btn_undo_block.text = "Undo blocks"
        btn_undo_block.focus_mode = Control.FOCUS_NONE
        btn_undo_block.custom_minimum_size = Vector2(0, 30)
        btn_undo_block.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        btn_undo_block.add_theme_font_size_override("font_size", 11)
        reset_row.add_child(btn_undo_block)

        var btn_undo_all := Button.new()
        btn_undo_all.text = "Undo all"
        btn_undo_all.focus_mode = Control.FOCUS_NONE
        btn_undo_all.custom_minimum_size = Vector2(0, 30)
        btn_undo_all.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        btn_undo_all.add_theme_font_size_override("font_size", 11)
        reset_row.add_child(btn_undo_all)

        var si_reset := i
        btn_undo_sel.pressed.connect(func(): _on_undo_name_selects(si_reset))
        btn_undo_block.pressed.connect(func(): _on_undo_name_blocks(si_reset))
        btn_undo_all.pressed.connect(func(): _on_undo_name_all(si_reset))

        # ── Full candidate checklist (check/X/protect) — always visible ──
        var all_star_names: Array[String] = []
        for j in _host._star_count:
            all_star_names.append(_host._star_names[j] if j < _host._star_names.size() else "?")
        all_star_names.sort_custom(func(a, b): return String(a).nocasecmp_to(String(b)) < 0)

        if not all_star_names.is_empty():
            var panel := PanelContainer.new()
            var panel_sb := StyleBoxFlat.new()
            panel_sb.bg_color = Color(0.06, 0.04, 0.14, 1.0)
            panel_sb.border_color = Color(star_color.r * 0.6, star_color.g * 0.6, star_color.b * 0.6, 1.0)
            panel_sb.border_width_left = 1
            panel_sb.border_width_top = 1
            panel_sb.border_width_right = 1
            panel_sb.border_width_bottom = 1
            panel_sb.corner_radius_top_left = 4
            panel_sb.corner_radius_top_right = 4
            panel_sb.corner_radius_bottom_right = 4
            panel_sb.corner_radius_bottom_left = 4
            panel_sb.content_margin_left = 4
            panel_sb.content_margin_right = 4
            panel_sb.content_margin_top = 4
            panel_sb.content_margin_bottom = 4
            panel.add_theme_stylebox_override("panel", panel_sb)
            panel.self_modulate = Color(1, 1, 1, 1)
            panel.custom_minimum_size = Vector2(300, 0)
            root.add_child(panel)

            var name_hbox := HBoxContainer.new()
            name_hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
            name_hbox.add_theme_constant_override("separation", 6)
            panel.add_child(name_hbox)

            @warning_ignore("integer_division")
            var half: int = (all_star_names.size() + 1) / 2
            for col_i in 2:
                var col_vbox := VBoxContainer.new()
                col_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
                name_hbox.add_child(col_vbox)

                var start: int = col_i * half
                var end: int = mini(start + half, all_star_names.size())
                for ci in range(start, end):
                    var name_str: String = all_star_names[ci]
                    var row := HBoxContainer.new()
                    row.mouse_filter = Control.MOUSE_FILTER_PASS
                    row.add_theme_constant_override("separation", 3)

                    var name_lbl := Label.new()
                    name_lbl.text = name_str
                    name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
                    name_lbl.add_theme_font_size_override("font_size", 16)
                    name_lbl.add_theme_color_override("font_color", star_color)
                    name_lbl.clip_text = true
                    row.add_child(name_lbl)

                    var btn_check := Button.new()
                    btn_check.text = "✓"
                    btn_check.custom_minimum_size = Vector2(28, 26)
                    btn_check.focus_mode = Control.FOCUS_NONE
                    btn_check.add_theme_font_size_override("font_size", 15)
                    row.add_child(btn_check)

                    var btn_x := Button.new()
                    btn_x.text = "✗"
                    btn_x.custom_minimum_size = Vector2(28, 26)
                    btn_x.focus_mode = Control.FOCUS_NONE
                    btn_x.add_theme_font_size_override("font_size", 15)
                    row.add_child(btn_x)

                    col_vbox.add_child(row)

                    var captured_name := name_str
                    btn_check.pressed.connect(func(): _on_name_check(si, captured_name, name_lbl, btn_check, btn_x))
                    btn_check.gui_input.connect(func(event: InputEvent):
                        if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
                            _on_name_protect_toggle(si, captured_name)
                            btn_check.get_viewport().set_input_as_handled())
                    btn_x.pressed.connect(func(): _on_name_x(si, captured_name, name_lbl, btn_check, btn_x))
                    btn_x.gui_input.connect(func(event: InputEvent):
                        if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
                            _on_name_protect_toggle(si, captured_name)
                            btn_x.get_viewport().set_input_as_handled())

            # Refresh all rows across both columns — pass full name list for correct cross-referencing.
            for col_i in 2:
                var col_vbox: VBoxContainer = name_hbox.get_child(col_i)
                _refresh_name_widget(i, col_vbox, all_star_names, star_color, col_i * half)

    _reposition_star_widgets()


func _style_range_edit(edit: LineEdit, star_color: Color) -> void:
    var sb := StyleBoxFlat.new()
    sb.bg_color = Color(0.06, 0.04, 0.14, 1.0)
    sb.border_color = Color(star_color.r * 0.6, star_color.g * 0.6, star_color.b * 0.6, 1.0)
    sb.border_width_left = 1; sb.border_width_top = 1
    sb.border_width_right = 1; sb.border_width_bottom = 1
    sb.corner_radius_top_left = 2; sb.corner_radius_top_right = 2
    sb.corner_radius_bottom_right = 2; sb.corner_radius_bottom_left = 2
    sb.content_margin_left = 3; sb.content_margin_right = 3
    sb.content_margin_top = 1; sb.content_margin_bottom = 1
    edit.add_theme_stylebox_override("normal", sb)
    edit.add_theme_stylebox_override("focus", sb)
    edit.add_theme_color_override("font_color", Color(0.90, 0.87, 1.00, 1.0))
    edit.add_theme_color_override("font_placeholder_color", Color(0.40, 0.35, 0.60, 1.0))


func _sequence_number(star_idx: int) -> int:
    if star_idx >= 0 and star_idx < _host._pitch_rank_solution.size():
        return _host._pitch_rank_solution[star_idx] + 1
    return star_idx + 1


func _confirmed_sequence_str(star_idx: int) -> String:
    if star_idx < 0:
        return "?"
    var idx: int = _deduction._find_match_record_by_star_idx(star_idx)
    if idx < 0:
        return "?"
    var lo_i: int = int(_deduction._match_records[idx].get("seq_lo", 0))
    var hi_i: int = int(_deduction._match_records[idx].get("seq_hi", 0))
    if lo_i > 0 and lo_i == hi_i:
        return str(lo_i)
    return "?"


func _confirmed_pitch_str_for_star(star_idx: int) -> String:
    if star_idx < 0:
        return "?"
    var idx: int = _deduction._find_match_record_by_star_idx(star_idx)
    if idx < 0:
        return "?"
    var pitch_states: Dictionary = _deduction._match_records[idx].get("pitch_states", {})
    for note in pitch_states:
        if int(pitch_states[note]) == 1:
            return str(note)
    return "?"


func _ordinal(n: int) -> String:
    var mod100: int = n % 100
    if mod100 >= 11 and mod100 <= 13:
        return "%dth note" % n
    match n % 10:
        1: return "%dst note" % n
        2: return "%dnd note" % n
        3: return "%drd note" % n
        _: return "%dth note" % n


func _ordinal_str(raw: String) -> String:
    if raw == "?" or not raw.is_valid_int():
        return raw
    return _ordinal(int(raw))


func _note_name_for_star(star_idx: int) -> String:
    if star_idx < 0 or star_idx >= _host._star_pitch_index.size():
        return "?"
    var p: int = _host._star_pitch_index[star_idx]
    if p < 0 or p >= _host._pitch_freqs.size():
        return "?"
    return ConstellationLogicPuzzle.note_name_for_freq(_host._pitch_freqs[p])


func _distinct_note_names() -> Array[String]:
    var uniq_freqs: Array = []
    for f in _host._pitch_freqs:
        if not uniq_freqs.has(f):
            uniq_freqs.append(f)
    uniq_freqs.sort()
    var names: Array[String] = []
    for f in uniq_freqs:
        names.append(ConstellationLogicPuzzle.note_name_for_freq(f))
    return names


func _style_color_toggle_btn(btn: Button, color_idx: int, state: int) -> void:
    var base_col: Color = _host.STAR_COLORS_BY_IDX[color_idx]
    var letter: String = _host.COLOR_NAME_LABELS[color_idx].substr(0, 1)
    match state:
        1:  # confirmed
            btn.modulate = Color(base_col.r, base_col.g, base_col.b, 1.0)
            btn.text = letter + "✓"
        2:  # eliminated
            btn.modulate = Color(base_col.r, base_col.g, base_col.b, 1.0)
            btn.text = letter + "✗"
        3:  # soft-eliminated — another color on this record is protected
            btn.modulate = Color(base_col.r, base_col.g, base_col.b, 0.5)
            btn.text = letter + "✗"
        4:  # protected — "still possible"
            btn.modulate = STATE_COLORS.protected
            btn.text = letter
        _:  # neutral
            btn.modulate = Color(base_col.r, base_col.g, base_col.b, 1.0)
            btn.text = letter


func _confirmed_name_for_star(star_idx: int) -> String:
    if star_idx < 0:
        return ""
    var idx: int = _deduction._find_match_record_by_star_idx(star_idx)
    if idx < 0:
        return ""
    return str(_deduction._match_records[idx].get("name", ""))


func _reposition_star_widgets() -> void:
    var map_h: float = _host._star_map_control.size.y
    var map_w: float = _host._star_map_control.size.x
    for i in _host._star_widgets.size():
        if i >= _host._star_screen_pos.size():
            break
        var w: Control = _host._star_widgets[i]
        if not is_instance_valid(w):
            continue
        w.reset_size()
        var wh: float = w.get_combined_minimum_size().y
        var ww: float = w.get_combined_minimum_size().x
        var dot: Vector2 = _host._star_screen_pos[i]
        # Flip above dot if widget would overflow bottom, else place below.
        var flip_up: bool = dot.y + _host.WIDGET_OFFSET_BELOW + wh > map_h
        var pos_y: float
        if flip_up:
            pos_y = dot.y - wh - _host.WIDGET_OFFSET_ABOVE
        else:
            pos_y = dot.y + _host.WIDGET_OFFSET_BELOW
        # Clamp Y to keep widget fully inside map bounds.
        pos_y = clampf(pos_y, 0.0, maxf(0.0, map_h - wh))
        # Centre the widget horizontally on the dot, clamped to map bounds.
        var pos_x: float = clampf(dot.x - ww * 0.5, 0.0, maxf(0.0, map_w - ww))
        w.position = Vector2(pos_x, pos_y)


func _build_star_tags() -> void:
    call_deferred("_build_star_tags_impl")


func _build_star_tags_impl() -> void:
    for t in _host._star_tags:
        if is_instance_valid(t):
            t.queue_free()
    _host._star_tags.clear()

    if _host._star_screen_pos.is_empty():
        return

    for i in _host._star_count:
        var color_idx: int = _host._star_colors[i] if i < _host._star_colors.size() else 1
        var star_color: Color = _host.STAR_COLORS_BY_IDX[clamp(color_idx, 0, 3)]

        var root := Control.new()
        root.mouse_filter = Control.MOUSE_FILTER_IGNORE
        _host._star_map_control.add_child(root)
        _host._star_tags.append(root)

        var vbox := VBoxContainer.new()
        vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
        vbox.add_theme_constant_override("separation", 1)
        root.add_child(vbox)

        var hbox := HBoxContainer.new()
        hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
        hbox.add_theme_constant_override("separation", 4)
        root.add_child(hbox)

        var name_str: String = _confirmed_name_for_star(i)
        if name_str == "":
            name_str = "?"
        var seq_str: String = _confirmed_sequence_str(i)
        var pitch_str: String = _confirmed_pitch_str_for_star(i)

        var name_lbl := Label.new()
        name_lbl.name = "NameLabel"
        name_lbl.text = name_str
        name_lbl.add_theme_font_size_override("font_size", 16)
        name_lbl.add_theme_color_override("font_color", star_color)
        name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

        var seq_lbl := Label.new()
        seq_lbl.name = "SeqLabel"
        seq_lbl.text = "%s" % _ordinal_str(seq_str)
        seq_lbl.add_theme_font_size_override("font_size", 16)
        seq_lbl.add_theme_color_override("font_color", Color(star_color.r, star_color.g, star_color.b, 0.75))
        seq_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

        var pitch_lbl := Label.new()
        pitch_lbl.name = "PitchLabel"
        pitch_lbl.text = pitch_str
        pitch_lbl.add_theme_font_size_override("font_size", 16)
        pitch_lbl.add_theme_color_override("font_color", Color(star_color.r, star_color.g, star_color.b, 0.75))
        pitch_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

        vbox.add_child(name_lbl.duplicate())
        vbox.add_child(seq_lbl.duplicate())
        vbox.add_child(pitch_lbl.duplicate())
        hbox.add_child(name_lbl)
        hbox.add_child(seq_lbl)
        hbox.add_child(pitch_lbl)

    _reposition_star_tags()


func _reposition_star_tags() -> void:
    var map_w: float = _host._star_map_control.size.x
    var map_h: float = _host._star_map_control.size.y
    for i in _host._star_tags.size():
        if i >= _host._star_screen_pos.size():
            break
        var root: Control = _host._star_tags[i]
        if not is_instance_valid(root):
            continue
        # Safe enough by construction today — _build_star_tags_impl() always
        # adds exactly a VBoxContainer then an HBoxContainer, in that order,
        # to every root — but a direct typed assignment from get_child()
        # HANGS the engine (not a catchable error) if that ever stops being
        # true. `as` + null-check degrades to skipping this tag instead.
        if root.get_child_count() < 2:
            continue
        var vbox: VBoxContainer = root.get_child(0) as VBoxContainer
        var hbox: HBoxContainer = root.get_child(1) as HBoxContainer
        if not vbox or not hbox:
            continue
        var dot: Vector2 = _host._star_screen_pos[i]

        vbox.reset_size()
        var stacked_h: float = vbox.get_combined_minimum_size().y
        var fits_below: bool = dot.y + _host.TAG_OFFSET_BELOW + stacked_h <= map_h
        var fits_above: bool = dot.y - _host.TAG_OFFSET_ABOVE - stacked_h >= 0.0

        if fits_below or fits_above:
            vbox.visible = true
            hbox.visible = false
            var vw: float = vbox.get_combined_minimum_size().x
            var pos_y: float = dot.y + _host.TAG_OFFSET_BELOW if fits_below else dot.y - _host.TAG_OFFSET_ABOVE - stacked_h
            var pos_x: float = clampf(dot.x - vw * 0.5, 0.0, maxf(0.0, map_w - vw))
            root.position = Vector2(pos_x, pos_y)
        else:
            vbox.visible = false
            hbox.visible = true
            hbox.reset_size()
            var hw: float = hbox.get_combined_minimum_size().x
            var hh: float = hbox.get_combined_minimum_size().y
            var pos_y2: float = dot.y - hh * 0.5
            var fits_right: bool = dot.x + _host.TAG_OFFSET_SIDE + hw <= map_w
            var pos_x2: float
            if fits_right:
                pos_x2 = dot.x + _host.TAG_OFFSET_SIDE
            else:
                pos_x2 = dot.x - _host.TAG_OFFSET_SIDE - hw
            root.position = Vector2(pos_x2, pos_y2)


func _refresh_name_widget(star_idx: int, name_vbox: VBoxContainer,
        all_star_names: Array[String], star_color: Color, col_start: int = 0) -> void:
    var rows: Array = name_vbox.get_children()
    for ri in rows.size():
        var name_idx: int = col_start + ri
        if name_idx >= all_star_names.size():
            break
        var row: HBoxContainer = rows[ri]
        var name_lbl: Label = row.get_child(0)
        var btn_check: Button = row.get_child(1)
        var btn_x: Button = row.get_child(2)
        var captured_name: String = all_star_names[name_idx]
        var state: int = _deduction._effective_name_display_state(star_idx, captured_name, all_star_names)
        _apply_name_row_visual(state, name_lbl, btn_check, btn_x, star_color)


func _apply_name_row_visual(state: int, name_lbl: Label,
        btn_check: Button, btn_x: Button, star_color: Color) -> void:
    match state:
        1:  # confirmed ✓ (hard)
            name_lbl.add_theme_color_override("font_color",
                Color(star_color.r, star_color.g, star_color.b, 1.0))
            name_lbl.modulate = Color(1, 1, 1, 1)
            btn_check.modulate = STATE_COLORS.confirmed
            btn_x.modulate = Color(1, 1, 1, 1.0)
        2:  # eliminated ✗ (hard)
            name_lbl.add_theme_color_override("font_color", Color(0.35, 0.30, 0.45, 1.0))
            name_lbl.modulate = Color(1, 1, 1, 1.0)
            btn_check.modulate = Color(1, 1, 1, 1.0)
            btn_x.modulate = STATE_COLORS.eliminated
        3:  # soft-eliminated — another candidate in this row is protected
            name_lbl.add_theme_color_override("font_color", STATE_COLORS.soft_eliminated)
            name_lbl.modulate = Color(1, 1, 1, 1.0)
            btn_check.modulate = Color(1, 1, 1, 1.0)
            btn_x.modulate = Color(1.0, 0.6, 0.5, 1.0)
        4:  # protected — TEMP debug: impossible to miss
            name_lbl.add_theme_color_override("font_color", STATE_COLORS.protected)
            name_lbl.modulate = Color(1, 1, 1, 1)
            btn_check.modulate = STATE_COLORS.protected
            btn_x.modulate = STATE_COLORS.protected
        _:  # neutral
            name_lbl.add_theme_color_override("font_color",
                Color(star_color.r, star_color.g, star_color.b, 1.0))
            name_lbl.modulate = Color(1, 1, 1, 1)
            btn_check.modulate = Color(1, 1, 1, 1.0)
            btn_x.modulate = Color(1, 1, 1, 1.0)


# ==================================================
# NAME STATE CALLBACKS
# ==================================================
func _on_name_check(star_idx: int, star_name: String,
        name_lbl: Label, btn_check: Button, btn_x: Button) -> void:
    var color_idx: int = _host._star_colors[star_idx] if star_idx < _host._star_colors.size() else 1
    var star_color: Color = _host.STAR_COLORS_BY_IDX[clamp(color_idx, 0, 3)]

    var cur: int = _deduction._star_elim_state(star_idx, star_name)
    var new_state: int = 0 if cur == 1 else 1

    if new_state == 1:
        var name_record: int = _deduction._find_match_record_by_name(star_name)
        if name_record >= 0:
            var existing_star: int = int(_deduction._match_records[name_record].get("star_idx", -1))
            if existing_star >= 0 and existing_star != star_idx:
                _apply_name_row_visual(2, name_lbl, btn_check, btn_x, star_color)
                return
        var record_idx: int = _deduction._get_or_create_match_record_for_name(star_name)
        record_idx = await _deduction._confirm_match_record_identity(record_idx, star_idx, star_name)
        if record_idx < 0:
            _apply_name_row_visual(_deduction._star_elim_state(star_idx, star_name), name_lbl, btn_check, btn_x, star_color)
            return
        var resolved_name: String = str(_deduction._match_records[record_idx]["name"])
        _deduction._propagate_name_confirmed(star_idx, resolved_name)
        _deduction._save_puzzle_notes()
        _deduction._full_propagation_refresh()
        return

    var record_idx2: int = _deduction._get_or_create_match_record_for_name(star_name)
    var elim2: Dictionary = _deduction._match_records[record_idx2].get("star_elim", {})
    elim2[star_idx] = new_state
    _deduction._match_records[record_idx2]["star_elim"] = elim2
    _apply_name_row_visual(new_state, name_lbl, btn_check, btn_x, star_color)
    _deduction._save_puzzle_notes()
    _deduction._full_propagation_refresh()


func _on_name_x(star_idx: int, star_name: String,
        name_lbl: Label, btn_check: Button, btn_x: Button) -> void:
    var color_idx: int = _host._star_colors[star_idx] if star_idx < _host._star_colors.size() else 1
    var star_color: Color = _host.STAR_COLORS_BY_IDX[clamp(color_idx, 0, 3)]

    var cur: int = _deduction._star_elim_state(star_idx, star_name)
    var new_state: int = 0 if cur == 2 else 2

    var record_idx: int = _deduction._get_or_create_match_record_for_name(star_name)
    var elim: Dictionary = _deduction._match_records[record_idx].get("star_elim", {})
    elim[star_idx] = new_state
    _deduction._match_records[record_idx]["star_elim"] = elim
    _apply_name_row_visual(new_state, name_lbl, btn_check, btn_x, star_color)

    var ukey: String = "%d:%s" % [star_idx, star_name]
    if new_state == 2:
        _deduction._user_blocks[ukey] = true
    else:
        _deduction._user_blocks.erase(ukey)

    _deduction._save_puzzle_notes()
    _deduction._full_propagation_refresh()


# ==================================================
# UNDO NAME-SELECTION/NAME-BLOCK CALLBACKS
# ==================================================
func _on_undo_name_selects(star_idx: int) -> void:
    var own_record: int = _deduction._find_match_record_by_star_idx(star_idx)
    if own_record >= 0:
        var r: Dictionary = _deduction._match_records[own_record]
        r["star_idx"] = -1
        # color_states was fully overwritten by _sync_color_states_from_star_idx
        # when this identity was confirmed — with the binding now undone,
        # that ground-truth-derived data has no basis anymore and would
        # otherwise sit there looking like a still-valid confirmation.
        r["color_states"] = {}
        var own_elim: Dictionary = r.get("star_elim", {})
        if own_elim.has(star_idx):
            own_elim.erase(star_idx)
            r["star_elim"] = own_elim
    for i in _deduction._match_records.size():
        if i == own_record:
            continue
        var other: Dictionary = _deduction._match_records[i]
        var other_star: int = int(other.get("star_idx", -1))
        if other_star >= 0 and other_star != star_idx:
            continue
        var other_name: String = str(other.get("name", ""))
        var ukey: String = "%d:%s" % [star_idx, other_name]
        if _deduction._user_blocks.has(ukey):
            continue
        var elim2: Dictionary = other.get("star_elim", {})
        if int(elim2.get(star_idx, 0)) == 2:
            elim2.erase(star_idx)
            other["star_elim"] = elim2
    _deduction._clear_protected_names_for_star(star_idx)
    _deduction._save_puzzle_notes()
    _deduction._full_propagation_refresh()


func _on_undo_name_blocks(star_idx: int) -> void:
    var user_blocked_names: Array[String] = []
    for ukey in _deduction._user_blocks.keys():
        var parts: PackedStringArray = ukey.split(":")
        if parts.size() == 2 and parts[0].is_valid_int() and int(parts[0]) == star_idx:
            user_blocked_names.append(parts[1])
    for name_str in user_blocked_names:
        var rec: int = _deduction._find_match_record_by_name(name_str)
        if rec >= 0:
            var elim: Dictionary = _deduction._match_records[rec].get("star_elim", {})
            if elim.has(star_idx):
                elim.erase(star_idx)
                _deduction._match_records[rec]["star_elim"] = elim
        _deduction._user_blocks.erase("%d:%s" % [star_idx, name_str])
    _deduction._save_puzzle_notes()
    _deduction._full_propagation_refresh()


func _on_undo_name_all(star_idx: int) -> void:
    var own_record: int = _deduction._find_match_record_by_star_idx(star_idx)
    if own_record >= 0:
        var r: Dictionary = _deduction._match_records[own_record]
        r["star_idx"] = -1
        # color_states was fully overwritten by _sync_color_states_from_star_idx
        # when this identity was confirmed — with the binding now undone,
        # that ground-truth-derived data has no basis anymore and would
        # otherwise sit there looking like a still-valid confirmation.
        r["color_states"] = {}
        var own_elim: Dictionary = r.get("star_elim", {})
        if own_elim.has(star_idx):
            own_elim.erase(star_idx)
            r["star_elim"] = own_elim

    # Union of "Undo selects" + "Undo blocks", scoped to this star's row only.
    # Names confirmed at a DIFFERENT star are left alone — that elimination
    # is structural (the name belongs elsewhere), not part of this star's row.
    for i in _deduction._match_records.size():
        if i == own_record:
            continue
        var other: Dictionary = _deduction._match_records[i]
        var other_star: int = int(other.get("star_idx", -1))
        if other_star >= 0 and other_star != star_idx:
            continue
        var elim2: Dictionary = other.get("star_elim", {})
        if elim2.has(star_idx):
            elim2.erase(star_idx)
            other["star_elim"] = elim2

    _deduction._clear_protected_names_for_star(star_idx)

    var user_blocked_names: Array[String] = []
    for ukey in _deduction._user_blocks.keys():
        var parts: PackedStringArray = ukey.split(":")
        if parts.size() == 2 and parts[0].is_valid_int() and int(parts[0]) == star_idx:
            user_blocked_names.append(parts[1])
    for name_str in user_blocked_names:
        _deduction._user_blocks.erase("%d:%s" % [star_idx, name_str])

    _deduction._save_puzzle_notes()
    _deduction._full_propagation_refresh()


func _on_name_protect_toggle(star_idx: int, star_name: String) -> void:
    var base: int = _deduction._star_elim_state(star_idx, star_name)
    if base != 0:
        return   # already hard-confirmed or hard-eliminated; right-click no-ops
    var key: String = _deduction._protect_key(star_idx, star_name)
    if _deduction._protected_names.has(key):
        _deduction._protected_names.erase(key)
    else:
        _deduction._protected_names[key] = true
    _deduction._save_puzzle_notes()
    _deduction._full_propagation_refresh()
