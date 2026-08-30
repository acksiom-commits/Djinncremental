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
# SCREEN-SPACE POPUP CLAMPING
# ==================================================
# The Staff popup, Name checklist, and Pitch checklist are all PopupPanel
# (i.e. Window) — entirely outside the Control clipping hierarchy that
# protects every other panel element, positioned in real screen pixels.
# Reported live: they can render over the pinned-clue box at the top of
# the header. The existing mitigation (_staff_popup's column-count scaling,
# see _open_staff_popup) only ever shrinks a popup's OWN height; it was
# never a guarantee the popup stays below any particular line, so a large
# constellation (more Name rows even after column-scaling) or Godot's own
# generic off-screen-avoidance (which only knows about the SCREEN edge, not
# this app's header) can both still push one up over the clue box.
#
# The actual invariant — no popup's top edge renders above the header — was
# never enforced anywhere. This is that enforcement, applied once at the
# tail of each of the three _open_*_popup functions rather than at every
# call site, so it also covers the re-open-at-current-position calls
# (toggling a checklist row) for free.

## Screen-space Y a popup's top edge must never render above: the header's
## bottom edge (HeaderSeparator, the 1px line under HeaderHBox). Read live,
## not cached — SelectedClueDisplay now grows to fit a long pinned clue
## (fit_content), so the header's height is no longer a fixed number.
func _popup_min_screen_y() -> float:
    var sep: Control = _host._header_separator
    if sep == null or not is_instance_valid(sep):
        return 0.0
    var local_bottom: Vector2 = sep.global_position + Vector2(0, sep.size.y)
    return (sep.get_viewport().get_screen_transform() * local_bottom).y


## Apply to every screen_pos handed to a PopupPanel's open()/position —
## floors Y at the header boundary, leaves X untouched.
func _clamp_popup_screen_pos(screen_pos: Vector2) -> Vector2:
    screen_pos.y = maxf(screen_pos.y, _popup_min_screen_y())
    return screen_pos


## Character budget for the middle sequence field (the explicit
## candidate-position list, e.g. "1,4-8,12-15"). Was a flat max_length=12,
## which silently truncated real clue-derived lists — confirmed live: a
## fully-enumerated 15-star list needs 35 characters, and even a modest
## "1,3,5,7,9,11,13" is 15. Computed from the actual worst case (every
## position listed individually) rather than guessed at, so it scales with
## whatever constellation is open; a range form ("1-15") is always shorter
## than the enumeration it stands for, so this is a true upper bound.
func _max_candidate_list_length() -> int:
    var n: int = _host._star_count
    if n <= 0:
        return 32
    var digits: int = 0
    for p in range(1, n + 1):
        digits += str(p).length()
    return digits + maxi(0, n - 1)   # + one comma between each pair


# ==================================================
# MARKERS PANEL
# ==================================================
## Tab indices, in the order the buttons read. -1 is the default Matches
## panel.
##
## NAMED, because the raw numbers already drifted once: removing "Useful"
## renumbered everything, and a hardcoded 4 left over from the old order
## (where it meant SEARCH) sent the search-term picker to HINT instead
## (reported 2026-08-14). Use these, never a literal.
const TAB_CLUES: int = 0
const TAB_NOTES: int = 1
const TAB_GUIDE: int = 2
const TAB_SEARCH: int = 3
const TAB_HINT: int = 4


func _set_marker_tab(tab_idx: int) -> void:
    _host._active_marker_tab = tab_idx
    _host._tab_clues.add_theme_stylebox_override("normal",
        _host._sb_tab_active if tab_idx == TAB_CLUES else _host._sb_tab_inactive)
    _host._tab_notes.add_theme_stylebox_override("normal",
        _host._sb_tab_active if tab_idx == TAB_NOTES else _host._sb_tab_inactive)
    _host._tab_guide.add_theme_stylebox_override("normal",
        _host._sb_tab_active if tab_idx == TAB_GUIDE else _host._sb_tab_inactive)
    _host._tab_search.add_theme_stylebox_override("normal",
        _host._sb_tab_active if tab_idx == TAB_SEARCH else _host._sb_tab_inactive)
    _host._tab_hint.add_theme_stylebox_override("normal",
        _host._sb_tab_active if tab_idx == TAB_HINT else _host._sb_tab_inactive)
    _populate_markers_panel()


## Deferred, coalescing entry point — call this rather than
## call_deferred("_populate_markers_panel") directly, so repeat requests in
## one frame collapse to a single rebuild (see the note above
## _build_star_widgets()).
func request_markers_rebuild() -> void:
    if _markers_dirty:
        return
    _markers_dirty = true
    call_deferred("_populate_markers_panel")


func _populate_markers_panel() -> void:
    _markers_dirty = false
    for child in _host._markers_content.get_children():
        child.queue_free()

    # The Notes entry box is a PERSISTENT scene node (see its @onready
    # comment in constellation_study_overlay.gd) — it is never one of the
    # children freed above, so its visibility has to be set explicitly on
    # every dispatch, defaulting off here and turned on only inside
    # _populate_notes_markers(). Getting this backwards would either hide
    # it on the one tab that needs it, or leave it floating over every
    # other tab's content.
    _host._notes_entry_box.visible = false

    match _host._active_marker_tab:
        TAB_CLUES:   _populate_clue_markers()
        TAB_NOTES:   _populate_notes_markers()
        TAB_GUIDE:   _populate_guide_markers()
        TAB_SEARCH:  _populate_search_markers()
        TAB_HINT:    _populate_hint_markers()
        _:           _populate_name_markers()


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
        # chars (CACHE_VERSION 3) and cells (CACHE_VERSION 4) are both
        # already per-element coerced by _load_constellation_data() — these
        # only guard each outer field's own type, same belt-and-suspenders
        # reasoning as characteristics/text/form_id above.
        var chars: Array = raw["chars"] if raw.get("chars") is Array else []
        var cells: Array = raw["cells"] if raw.get("cells") is Array else []
        var terms: Array = raw["search_terms"] if raw.get("search_terms") is Array else []
        # disclosures must ride along or every tab below scores coverage as
        # if the clue had none — see _load_constellation_data()'s note; it
        # is already per-field coerced there, same as chars/cells.
        var discs: Array = raw["disclosures"] if raw.get("disclosures") is Array else []
        result.append({
            "characteristics": characteristics,
            "text": str(raw.get("text", "")),
            "form_id": _coerce_int(raw.get("form_id", 0), 0),
            "chars": chars,
            "cells": cells,
            "search_terms": terms,
            "disclosures": discs,
        })
    return result


# ==================================================
# CLUES SEARCH TAB
#
# Terms come from each clue's "search_terms" (CACHE_VERSION 5) — the values
# its text VISIBLY states, recorded by _characteristic_label() as it renders
# them. Deliberately NOT derived from "chars", which lists nodes several
# Forms never render, nor from "cells", which records assertions rather than
# mentions (a clue saying a name is NOT something must still be findable
# under that name).
# ==================================================

## The term the player last picked, e.g. "N:Theryis". "" = none chosen yet,
## so the tab shows its prompt instead of an empty result list.
var _search_term: String = ""

## Set order and headings for the popup. Keys are the token prefixes
## _characteristic_label() writes.
const SEARCH_SETS: Array = [
    {"key": "N", "title": "Names"},
    {"key": "C", "title": "Colors"},
    {"key": "S", "title": "Sequence positions"},
    {"key": "P", "title": "Pitches"},
    {"key": "H", "title": "Hop distances"},
]


## Every term of one kind that appears in at least one clue, deduplicated
## and ordered for display — numerically for the two integer sets, and
## alphabetically otherwise.
func _search_terms_of_kind(kind: String) -> Array:
    var seen: Dictionary = {}
    for clue in _all_final_clues_for_tabs():
        for t in (clue.get("search_terms", []) as Array):
            var term: String = str(t)
            if term.begins_with(kind + ":"):
                seen[term.substr(kind.length() + 1)] = true
    var out: Array = seen.keys()
    if kind == "S" or kind == "H":
        out.sort_custom(func(a, b): return int(a) < int(b))
    else:
        out.sort_custom(func(a, b): return String(a).nocasecmp_to(String(b)) < 0)
    return out


## Human-readable form of a token, for the header above the results.
func _search_term_display(term: String) -> String:
    if term == "" or not term.contains(":"):
        return term
    var kind: String = term.get_slice(":", 0)
    var val: String = term.substr(kind.length() + 1)
    match kind:
        "N": return val
        "C": return "%s stars" % val
        "S": return "the %s note" % ConstellationLogicPuzzle._ordinal(int(val))
        "P": return "pitch %s" % val
        "H": return "%s %s" % [val, "hop" if int(val) == 1 else "hops"]
    return val


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


# Replaced the five characteristic tabs (Color/Sequence/Pitch/Proximity/
# NameClues) with three coverage-ranked ones. A clue's coverage fraction —
# _deduction._clue_coverage_fraction(cells) — is how many of the ASSERTIONS
# that clue makes the player's own notes have already resolved, checked on
# the shared cell/grid model (see that function's section comment). Covers
# all three input surfaces at once for free: Star Map popup, Staff popup,
# and Sort:tab all write into the same _match_records. "Waiting" (a clue
# blocked on a fact from a DIFFERENT not-yet-known clue) needs cross-clue
# dependency reasoning that per-clue coverage doesn't carry, so it's
# deliberately not one of these three — see memory
# (planned_clues_tab_utility_rework) for that gap.
## THE working clue list: everything the player has not retired.
##
## GREEN  = untouched. MAGENTA = the player has entered at least one mark
## overlapping what this clue names. Colour is the only distinction; there
## is no second tab, because the split was never worth a click.
func _populate_clue_markers() -> void:
    var shown: bool = false
    var marked: Dictionary = _deduction.player_marked_terms()
    # Indexed, not `for clue in`: the loop index IS the canonical clue
    # number (see _clue_number_for_text), and it must keep counting past
    # the clues this tab skips — a clue filed into Notes must not renumber
    # everything after it.
    var all_clues: Array[Dictionary] = _all_final_clues_for_tabs()
    for i in all_clues.size():
        var clue: Dictionary = all_clues[i]
        var text: String = str(clue.get("text", ""))
        if text == "" or _deduction.is_clue_noted(text):
            continue
        _host._markers_content.add_child(
            _make_clue_label(text, _clue_state_color(clue, marked), i + 1))
        shown = true

    if not shown:
        var lbl := Label.new()
        lbl.text = "Every clue has been filed in Notes. Right-click one there to bring it back."
        lbl.add_theme_color_override("font_color", Color(0.50, 0.42, 0.65, 1))
        lbl.add_theme_font_size_override("font_size", 16)
        lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
        _host._markers_content.add_child(lbl)


## Green until the player has personally marked something the clue NAMES,
## magenta after.
##
## Matched on search_terms — the encoding that records what the text
## VISIBLY states — so the colour tracks what the player can actually read
## in the sentence. `cells` records assertions several Forms never render,
## and `chars` lists nodes that are never shown at all; either would turn
## clues magenta for words that are not on screen. See
## [[clue_encodings_four_representations]].
##
## One mark can turn several clues magenta. That is correct, not a bug: it
## genuinely IS information bearing on all of them.
func _clue_state_color(clue: Dictionary, marked: Dictionary) -> Color:
    for t in (clue.get("search_terms", []) as Array):
        if marked.has(str(t)):
            return STATE_COLORS.protected      # magenta — worked on
    return STATE_COLORS.confirmed              # green — untouched


# ============================================================================
# NOTES TAB (2026-08-24, replacing Used Up — see [[planned_player_controlled_
# clue_state]] for the 2026-08-14 history this superseded, and this block's
# own git history for the original DEV SPEC this tab was decided from).
#
# Used Up meant "I am done with this clue" and had exactly one content type
# (a right-clicked clue, greyed out of the working list). The player asked
# for somewhere to keep their OWN deductions while solving — chains like the
# one that came out of a hand-traced puzzle walkthrough, where "if X is not
# Y then Z must be W" needs to be written down somewhere the player controls,
# not inferred by the engine. Notes has two content types instead of one:
#
#   - clue REFERENCES, right-click same as before (still reversible, still
#     "right-click again to remove") — kept because pinning a specific clue
#     in front of you while you reason about it is still useful, just no
#     longer means "finished"
#   - freeform TEXT, typed into the persistent entry box above the list and
#     committed with ADD NOTE (or Enter) — the player's own words, saved
#     verbatim, never parsed or interpreted
#
# Both round-trip through the save (_save_puzzle_notes), both are isolated
# per-constellation the same way Used Up was (test_constellation_switch_
# isolation.gd covers this).
# ============================================================================

## Two content types, oldest first: freeform text the player typed, then
## clues they right-clicked in as a reference. Text entries render with a
## remove ("×") button since there's no clue row to right-click; clue
## references reuse _make_clue_label, so right-click still un-files them —
## the SAME gesture and SAME "right-click again" wording as before, just
## filing to Notes instead of Used Up.
func _populate_notes_markers() -> void:
    _host._notes_entry_box.visible = true
    var shown: bool = false

    for i in _deduction._note_entries.size():
        _host._markers_content.add_child(_make_note_text_row(i, str(_deduction._note_entries[i])))
        shown = true

    var marked: Dictionary = _deduction.player_marked_terms()
    # Indexed for the same reason as the Clues tab: a clue keeps the number
    # it has there, so filing it into Notes does not rename it.
    var all_clues: Array[Dictionary] = _all_final_clues_for_tabs()
    for i in all_clues.size():
        var clue: Dictionary = all_clues[i]
        var text: String = str(clue.get("text", ""))
        if text == "" or not _deduction.is_clue_noted(text):
            continue
        _host._markers_content.add_child(
            _make_clue_label(text, _clue_state_color(clue, marked), i + 1))
        shown = true

    if not shown:
        var lbl := Label.new()
        lbl.text = "Nothing here yet. Type a note above and press ADD NOTE, or right-click a clue to keep it in view while you work on it."
        lbl.add_theme_color_override("font_color", Color(0.50, 0.42, 0.65, 1))
        lbl.add_theme_font_size_override("font_size", 16)
        lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
        _host._markers_content.add_child(lbl)


## One freeform note row: the text plus a small remove button. Unlike a
## clue row there is no underlying clue to right-click, so removal is an
## explicit control rather than a gesture on the row itself.
func _make_note_text_row(index: int, text: String) -> PanelContainer:
    var pc := PanelContainer.new()
    pc.add_theme_stylebox_override("panel", _host._sb_clue_normal)

    var hbox := HBoxContainer.new()
    hbox.add_theme_constant_override("separation", 8)
    pc.add_child(hbox)

    var lbl := RichTextLabel.new()
    lbl.bbcode_enabled = false
    lbl.fit_content = true
    lbl.scroll_active = false
    lbl.text = text
    lbl.add_theme_color_override("default_color", STATE_COLORS.confirmed)
    lbl.add_theme_font_size_override("normal_font_size", 18)
    lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    hbox.add_child(lbl)

    var remove_btn := Button.new()
    remove_btn.text = "×"
    remove_btn.focus_mode = Control.FOCUS_NONE
    remove_btn.tooltip_text = "Remove this note"
    remove_btn.add_theme_font_size_override("font_size", 18)
    var captured_index := index
    remove_btn.pressed.connect(func():
        _deduction.remove_note_entry(captured_index)
        request_markers_rebuild())
    hbox.add_child(remove_btn)

    return pc


## ADD NOTE button handler. TextEdit, not LineEdit — a note may reasonably
## run to several lines, so Enter inserts a newline rather than submitting;
## the button is the only commit path. Reads the persistent entry box
## directly rather than being passed the text, since it is the one thing in
## this tab that is never rebuilt (see the box's @onready comment in
## constellation_study_overlay.gd) — there is always exactly one to read.
func _on_notes_add_pressed() -> void:
    var text: String = _host._notes_text_edit.text
    _deduction.add_note_entry(text)
    _host._notes_text_edit.text = ""
    request_markers_rebuild()


## Placeholder. The mechanic: charge with further Spark endowments after the
## third tier, costs starting at the Tier amounts, and a charge points at a
## clue that currently yields new information WITHOUT saying what it yields —
## preserving the deduction and removing only the search. Deliberately not
## built during the current testing cycle.
func _populate_hint_markers() -> void:
    var lbl := Label.new()
    lbl.text = "Hints are not available yet.\n\nLater: spend Spark endowments to charge a hint, and a charge will point out a clue that still has something to give — without telling you what."
    lbl.add_theme_color_override("font_color", Color(0.50, 0.42, 0.65, 1))
    lbl.add_theme_font_size_override("font_size", 16)
    lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    _host._markers_content.add_child(lbl)


func _populate_search_markers() -> void:
    if _search_term == "":
        var hint := Label.new()
        hint.text = "Press SEARCH again to pick a name, color, sequence position, pitch, or hop distance — only those actually written into this constellation's clues are listed."
        hint.add_theme_color_override("font_color", Color(0.50, 0.42, 0.65, 1))
        hint.add_theme_font_size_override("font_size", 16)
        hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
        _host._markers_content.add_child(hint)
        return

    var header := Label.new()
    header.text = "Clues mentioning %s" % _search_term_display(_search_term)
    header.add_theme_color_override("font_color", Color(0.70, 0.58, 0.90, 1))
    header.add_theme_font_size_override("font_size", 16)
    header.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    _host._markers_content.add_child(header)

    var shown: bool = false
    var neutral_col := STATE_COLORS.muted
    # Indexed: SEARCH shows a filtered subset, so its rows must still carry
    # each clue's canonical number rather than 1..n of whatever matched.
    var all_clues: Array[Dictionary] = _all_final_clues_for_tabs()
    for i in all_clues.size():
        var clue: Dictionary = all_clues[i]
        var text: String = str(clue.get("text", ""))
        if text == "":
            continue
        if not (clue.get("search_terms", []) as Array).has(_search_term):
            continue
        var col: Color = neutral_col if int(clue.get("form_id", 0)) == 2 else STATE_COLORS.neutral
        _host._markers_content.add_child(_make_clue_label(text, col, i + 1))
        shown = true

    if not shown:
        var lbl := Label.new()
        lbl.text = "No clue mentions that."
        lbl.add_theme_color_override("font_color", Color(0.50, 0.42, 0.65, 1))
        lbl.add_theme_font_size_override("font_size", 16)
        lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
        _host._markers_content.add_child(lbl)


## The picker. Built fresh each open so it always reflects the current
## puzzle — a RESET reshuffles which values the clues actually use.
func _open_search_popup() -> void:
    var popup := PopupPanel.new()
    _host.add_child(popup)

    var margin := MarginContainer.new()
    for side in ["left", "right", "top", "bottom"]:
        margin.add_theme_constant_override("margin_" + side, 12)
    popup.add_child(margin)

    var outer := VBoxContainer.new()
    outer.add_theme_constant_override("separation", 10)
    margin.add_child(outer)

    var title := Label.new()
    title.text = "SEARCH CLUES"
    title.add_theme_color_override("font_color", Color(0.70, 0.58, 0.90, 1))
    title.add_theme_font_size_override("font_size", 19)
    title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    outer.add_child(title)

    var columns := HBoxContainer.new()
    columns.add_theme_constant_override("separation", 18)
    outer.add_child(columns)

    var any_terms: bool = false
    for set_def in SEARCH_SETS:
        var kind: String = str(set_def["key"])
        var values: Array = _search_terms_of_kind(kind)
        if values.is_empty():
            continue   # this constellation's clues never state one
        any_terms = true

        var col := VBoxContainer.new()
        col.add_theme_constant_override("separation", 3)
        col.size_flags_vertical = Control.SIZE_FILL
        columns.add_child(col)

        var heading := Label.new()
        heading.text = str(set_def["title"])
        heading.add_theme_color_override("font_color", Color(0.70, 0.58, 0.90, 1))
        heading.add_theme_font_size_override("font_size", 16)
        col.add_child(heading)

        var sep := HSeparator.new()
        col.add_child(sep)

        for v in values:
            var term: String = "%s:%s" % [kind, str(v)]
            var btn := Button.new()
            btn.text = str(v)
            btn.focus_mode = Control.FOCUS_NONE
            btn.add_theme_font_size_override("font_size", 16)
            btn.custom_minimum_size = Vector2(96, 26)
            if term == _search_term:
                btn.add_theme_color_override("font_color", STATE_COLORS.confirmed)
            var chosen := term
            btn.pressed.connect(func():
                _search_term = chosen
                popup.hide()
                popup.queue_free()
                # 3 = SEARCH. Was 4 before "Useful" was removed and the tabs
                # were renumbered; 4 is now HINT, so picking a search term
                # jumped to the wrong tab (reported 2026-08-14).
                _set_marker_tab(TAB_SEARCH))
            col.add_child(btn)

    if not any_terms:
        var none := Label.new()
        none.text = "No clues generated yet."
        none.add_theme_color_override("font_color", Color(0.50, 0.42, 0.65, 1))
        none.add_theme_font_size_override("font_size", 16)
        outer.add_child(none)

    # Dismissing without choosing leaves the previous result in place.
    popup.popup_hide.connect(func(): popup.queue_free())
    var panel: Control = _host.get_node(_host.PANEL_ROOT_PATH)
    popup.popup_centered(Vector2i(mini(1000, int(panel.size.x) - 80), 0))


# DEV: GUIDE TAB — placeholder for later use as a list of BOTH the standard
# logic-puzzle language conventions (e.g. "earlier than", "fires immediately
# after", "is 1 hop from", "exactly N of X's connected stars fire before it",
# "the star that plays <note>") AND those specific to these constellation
# puzzles (sub-rank labels like "Blue-B"/"A4-C", star-name references, the
# note/fire-step naming, hop-distance graph language). No clue rows here yet —
# this tab is intentionally empty until that reference content is written.
#
# ── GUIDE CONTENT NOTES (drafted 2026-08-07, verified against the clue
# ── builders; write these up as player-facing entries when the tab is built)
#
# "BETWEEN" IS NEVER THE MAP (asked by the player 2026-08-14, answered
# from _build_form_betweenness)
# Betweenness is ordering along ONE axis, never star-map topology. Which
# axis is carried by the VERB, and that is the whole tell:
#
#   "X fires between A and B."  -> SEQUENCE. Firing order.
#   "X is between A and B."     -> PITCH. Pitch rank.
#
# _order_verb() returns "fires" for Sequence and "is" for everything else,
# and the Form picks Sequence 70% of the time, Pitch 30%.
#
# Map distance is a different family entirely and always says so out loud —
# "is 1 hop from", "is not connected to". If a clue does not mention hops or
# connection, it is not about the map.
#
# FIXED 2026-08-14 — the verb now names the axis, so the tell above is
# reliable rather than a trap:
#
#   "Chroneeia fires between A and B."     Sequence
#   "Helios is pitched between A and B."   Pitch
#
# It used to be the bare "is", naming no axis at all, and the reported
# example put a SEQUENCE descriptor among its three labels —
#
#   "Helios is between Nyxaos and the star that fires 5th note."
#
# — which actively pulled the reader to the wrong axis. Identifiers and the
# compared axis are independent by design (id_cat is chosen separately from
# axis), so the labels were not the bug; the verb was.
#
# Fixing it in _order_verb rather than in the one Form that noticed improved
# four sentence shapes at once, and let _order_unit drop "pitch rank" for
# plain "step" — "is pitched exactly 2 pitch ranks higher" said it twice.
#
# It also surfaced a bug older than the Form's own report: two of
# Betweenness's three phrasings hardcoded before/after for EVERY axis, so
# Pitch clues read "Helios is before Keriion" — a temporal word for a
# frequency ordering. Now _order_chain_word: before/after for Sequence,
# lower/higher for Pitch. Found only by printing the rendered sentences;
# wording cannot be verified by reading the code.
#
# DISTINCT STARS, NOT DISTINCT PITCHES (measured 2026-08-10)
# Every star a clue names is a different star — a clue never refers to the
# same star twice under two labels. It does NOT follow that they all have
# different PITCHES. Notes repeat: constellation 0 has 15 stars across 10
# distinct notes, and _order_value() ranks Pitch with ties shared. Of 90
# generated clues naming 2+ stars, 11 named two stars carrying the same
# note.
#
# This is the trap worth writing up for players, because the wrong reading
# over-eliminates. Given:
#
#   "The star that fires 12th note has a lower pitch than Nyxeai, the star
#    that fires 2nd note, the star that fires 11th note, and the star that
#    fires 15th note."
#
# the sound inference is "lower than each of those four stars" — NOT
# "outside the top four pitches". If two of the four happen to share a
# note, they span only three distinct pitch values, and the subject can sit
# as high as the 4th-highest. The listed stars are each strictly above the
# subject (_build_form_group_comparison filters on v <= subject_val), but
# nothing orders them against EACH OTHER.
#
# Corrected from an earlier note that claimed pitch-distinctness. The audit
# behind it read search_terms — the rendered-label encoding, where every
# star already gets a unique label, so "no duplicates" was true by
# construction and could not have detected this. Read `chars` for mentions.
# See [[clue_encodings_four_representations]].
#
# "CONNECTED" MEANS EXACTLY ONE HOP — direct line-neighbours only, never
# multi-hop reach. All three clue forms using the word read proximity[star],
# built by constellation_logic_puzzle.gd's _build_proximity() straight from
# the constellation's authored line_pairs: each pair records only its two
# endpoints as neighbours of each other. There is no transitive closure and
# no traversal, so a star's "connected stars" are precisely the stars it has
# a line drawn directly to — the same set its Degree counts.
#   - "X is the earliest/latest to fire among its connected stars."
#     (_build_form_extreme) Among ONLY X's direct line-neighbours. Says
#     nothing about stars two or more hops away.
#   - "Exactly N of X's connected stars fire before it."
#     (_build_form_count) Of X's direct neighbours only, exactly N are
#     earlier. Implies X has >= N neighbours, and combined with X's Degree,
#     that the remaining neighbours all fire after it.
#   - "X is not connected to Y." (_build_form_distance_negation) No line
#     drawn DIRECTLY between X and Y. They may still be linked through
#     intermediate stars.
#
# The third one is the trap worth calling out explicitly for players:
# "not connected" is strictly weaker than "far apart". Reading it as
# "unrelated / nowhere near each other" leads to over-elimination.
#
# Also worth distinguishing in the same entry, since it's the same map data
# phrased differently: the HOP clues ("X is 1 hop from a star that plays
# E5", "X is 2 hops from...") are the multi-hop language, counting
# shortest-path steps through _distances. So "connected" == 1 hop always;
# "N hops" is the general distance relation, of which 1 hop and "connected"
# are the same statement.
func _populate_guide_markers() -> void:
    var lbl := Label.new()
    lbl.text = "Guide content will appear here in a future update."
    lbl.add_theme_color_override("font_color", Color(0.50, 0.42, 0.65, 1))
    lbl.add_theme_font_size_override("font_size", 16)
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
        btn.add_theme_font_size_override("font_size", 19)
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
    btn.add_theme_font_size_override("font_size", 16)
    btn.focus_mode = Control.FOCUS_NONE
    # Checks BOTH the record's own "name" field (set by identity confirms
    # elsewhere) and name_states (set by this checklist itself, either a
    # direct check or _settle_singleton_names narrowing it to one) — same
    # two sources _make_pitch_checklist_trigger_button already checks for
    # pitch_states; "name" alone left this button stuck on "Select Name"
    # even after the checklist had a confirmed row.
    var current_name: String = str(_deduction.record_at(record_idx).get("name", ""))
    if current_name == "":
        var name_states: Dictionary = _deduction.record_at(record_idx).get("name_states", {})
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


# ==================================================
# COPY TO NOTES
# ==================================================
# A "still open" list from any checklist surface, written straight into the
# Notes tab as one entry. The player is reading a popup, sees three
# survivors, and wants that written down before they close it and lose the
# view.

## Row states that survive into a copied list.
##
## 2 is a hard X and 3 is soft-eliminated (a sibling value on this row is
## protected) — BOTH mean "ruled out", so both are dropped and the list is
## exactly what is still live. 0 neutral, 1 confirmed and 4 protected all
## stay: a confirmed value is usually the single most useful thing to note,
## and dropping it would make the entry read as though nothing were decided.
const COPYABLE_ROW_STATES: Array = [0, 1, 4]


## One Notes entry: "<header>: a, b, c".
##
## Writes through _deduction.add_note_entry, the same path the Notes tab's
## own text box uses, so a copied list round-trips through the save and can
## be removed exactly like a typed note.
##
## An empty list still records a line — "nothing left" is a real and
## alarming state (it means the board contradicts itself), and silently
## writing nothing would look like the button was broken.
func _copy_open_items_to_notes(header: String, items: Array) -> void:
    # PackedStringArray, not a plain Array: String.join() is typed, and
    # handing it an untyped Array is the silent-abort class this project
    # has hit before (see _solve's typed-array crash).
    var parts := PackedStringArray()
    for it in items:
        parts.append(str(it))
    var body: String = ", ".join(parts) if parts.size() > 0 else "(none left)"
    _deduction.add_note_entry("%s: %s" % [header, body])
    # Repaint only when the player is actually looking at Notes. The copy is
    # usually pressed from a popup over some OTHER tab, where rebuilding the
    # marker list would be wasted work — and _populate_notes_markers assumes
    # the Notes tab owns the marker area, so calling it while another tab
    # holds it would draw notes into that tab's list.
    if _host._active_marker_tab == TAB_NOTES:
        _populate_notes_markers()


## Header naming the SOURCE of a copied list, so a Notes entry still means
## something after ten more are added above it.
##
## A record is identified by whatever the player has actually pinned down —
## its name if identified, else its sequence position, else a bare "Slot".
## Reads the effective position via the same accessor the staff uses, so a
## DERIVED pin names the entry just as a typed one does.
func _copy_header_for_record(record_idx: int, section: String) -> String:
    # record_at / record_count, NOT _match_records — that array is private
    # to the deduction engine and test_record_boundary scans every shipped
    # script for reaches into it. Caught there rather than by review.
    var who: String = ""
    var nm: String = str(_deduction.record_at(record_idx).get("name", "")) \
        if record_idx >= 0 and record_idx < _deduction.record_count() else ""
    if nm != "":
        who = nm
    else:
        var s: Array = _deduction._seq_candidate_set_for(record_idx)
        who = "Note %d" % int(s[0]) if s.size() == 1 else "Slot"
    return "%s — %s" % [who, section]


## THE COPY MUST AGREE WITH THE ROWS THE PLAYER IS LOOKING AT, which means
## reproducing BOTH steps the popup builders perform, not just the first.
##
## 1. collapse_soft=FALSE, same as the popups, so the raw 0-4 tiers arrive.
##    That is why COPYABLE_ROW_STATES has to drop 3 explicitly: with the
##    collapse ON, 3 would already read as 2 and dropping {2} alone would
##    be correct. With it OFF — the form copied from the popup code — a
##    filter of {2} alone silently keeps every soft-eliminated value.
##
## 2. The cross-record exclusion overlay. A value another record has
##    already claimed is not in this record's own state dict at all; the
##    popups fold it in afterwards with exactly the rule below. Omitting it
##    listed values the popup itself was drawing as X'd.
##
## Both omissions fail the same way and it is the dangerous way: the list
## is a SUPERSET of the truth. Nothing looks malformed, nothing contradicts
## anything the player typed — the note just quietly offers options that
## are gone, while the popup beside it shows them struck out.
##
## "sequence" is the one section that skips step 2 deliberately, not by
## omission: _effective_seq_candidates already folds cross-record exclusion
## in at its own base tier (_compute_excluded_positions_for), unlike the
## per-value state dicts the other three sections read — it's exactly the
## set the row's own centre box renders, so there is no second overlay step
## left to reproduce.
func _on_staff_copy(record_idx: int, section: String) -> void:
    var items: Array = []
    match section:
        "sequence":
            var positions: Array = _deduction._effective_seq_candidates(record_idx).duplicate()
            positions.sort()
            for p in positions:
                items.append(str(int(p)))
        "pitch":
            var excluded_pitches: Array[String] = _deduction._compute_excluded_pitches_for(record_idx)
            for pitch_idx in _host._pitch_freqs.size():
                var note_name: String = ConstellationLogicPuzzle.note_name_for_freq(_host._pitch_freqs[pitch_idx])
                var ps: int = _deduction._effective_pitch_state(record_idx, note_name, false)
                if (ps == 0 or ps == 4) and excluded_pitches.has(note_name):
                    continue
                if COPYABLE_ROW_STATES.has(ps):
                    items.append(note_name)
        "color":
            var excluded_colors: Array[int] = _deduction._compute_excluded_colors_for(record_idx)
            for ci in _host.COLOR_NAME_LABELS.size():
                var cs: int = _deduction._effective_color_state(record_idx, ci, false)
                if (cs == 0 or cs == 4) and excluded_colors.has(ci):
                    continue
                if COPYABLE_ROW_STATES.has(cs):
                    items.append(str(_host.COLOR_NAME_LABELS[ci]))
        "name":
            var excluded_names: Array[String] = _deduction._compute_excluded_names_for(record_idx)
            for n in _host._star_names:
                var name_str: String = str(n)
                var ns: int = _deduction._effective_name_state(record_idx, name_str, false)
                if (ns == 0 or ns == 4) and excluded_names.has(name_str):
                    continue
                if COPYABLE_ROW_STATES.has(ns):
                    items.append(name_str)
    _copy_open_items_to_notes(_copy_header_for_record(record_idx, section.capitalize()), items)


func _on_name_checklist_copy(record_idx: int) -> void:
    _on_staff_copy(record_idx, "name")


func _on_pitch_checklist_copy(record_idx: int) -> void:
    _on_staff_copy(record_idx, "pitch")


func _open_name_checklist_popup(record_idx: int, screen_pos: Vector2) -> void:
    _host._name_checklist_popup.clear_rows()
    var names_sorted: Array = _host._star_names.duplicate()
    names_sorted.sort_custom(func(a, b): return String(a).nocasecmp_to(String(b)) < 0)
    # Every name gets a row, so the sorted list's size IS the total the
    # column-major split needs. Must come after clear_rows(), which resets it.
    _host._name_checklist_popup.set_expected_row_count(names_sorted.size())
    # A record another Sort:tab has already proven distinct from this one,
    # that has ITSELF confirmed a name, rules that name out here too — see
    # _compute_excluded_names_for. Computed once, not per-row.
    var excluded_names: Array[String] = _deduction._compute_excluded_names_for(record_idx)
    for n in names_sorted:
        var name_str: String = str(n)
        # collapse_soft=false so the row can paint the protect tier: 3
        # dimmer, 4 magenta. StaffPopupRow has always styled both; the
        # collapse upstream just meant it never saw them.
        var state: int = _deduction._effective_name_state(record_idx, name_str, false)
        # Only when nothing hard has decided it. 0 and 4 are exactly the
        # states with no hard fact behind them (4 is "still possible", a
        # hint), so a real cross-record exclusion outranks both.
        if (state == 0 or state == 4) and excluded_names.has(name_str):
            state = 2
        _host._name_checklist_popup.add_name_row(name_str, state, STATE_COLORS.neutral)
    _host._name_checklist_popup.open(record_idx, _clamp_popup_screen_pos(screen_pos))


func _on_slot_name_check(record_idx: int, star_name: String, _row: StaffPopupRow) -> void:
    if record_idx < 0 or record_idx >= _deduction.record_count():
        return
    var r: Dictionary = _deduction.record_at(record_idx)
    var name_states: Dictionary = r.get("name_states", {})
    var cur: int = int(name_states.get(star_name, 0))
    if cur == 1:
        # Toggling back off — see _on_staff_name_check for why siblings
        # aren't restored here, and for why r["name"] also needs clearing
        # here now that the confirm path promotes into it.
        name_states[star_name] = 0
        r["name_states"] = name_states
        if str(r.get("name", "")) == star_name:
            r["name"] = ""
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
    if record_idx < 0 or record_idx >= _deduction.record_count():
        return
    var r: Dictionary = _deduction.record_at(record_idx)
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
    if record_idx < 0 or record_idx >= _deduction.record_count():
        return
    var r: Dictionary = _deduction.record_at(record_idx)
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
    btn.add_theme_font_size_override("font_size", 16)
    btn.focus_mode = Control.FOCUS_NONE
    var confirmed_note: String = ""
    var pitch_states: Dictionary = _deduction.record_at(record_idx).get("pitch_states", {})
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


## The trigger button plus a COPY button, same pairing as
## _make_color_toggle_row_for_record's inline copy — the popup this trigger
## opens carries its own copy button too (added when checklist popups first
## got one), but that one only reaches Notes while the popup is open. This
## is the tab slot's own line, so a player working straight down a Sort:tab
## list doesn't have to open the popup just to file this record's pitches.
func _make_pitch_checklist_row_for_record(record_idx: int) -> HBoxContainer:
    var row := HBoxContainer.new()
    row.add_theme_constant_override("separation", 3)
    row.add_child(_make_pitch_checklist_trigger_button(record_idx))
    var copy_btn := Button.new()
    copy_btn.text = "⎘"
    copy_btn.custom_minimum_size = Vector2(26, 24)
    copy_btn.focus_mode = Control.FOCUS_NONE
    copy_btn.tooltip_text = "Write the still-possible pitches into the Notes tab"
    var cridx := record_idx
    copy_btn.pressed.connect(func(): _on_staff_copy(cridx, "pitch"))
    row.add_child(copy_btn)
    return row


func _open_pitch_checklist_popup(record_idx: int, screen_pos: Vector2) -> void:
    _host._pitch_checklist_popup.clear_rows()
    # One row per pitch, so the pitch count IS the total the column-major
    # split needs. After clear_rows(), which resets it.
    _host._pitch_checklist_popup.set_expected_row_count(_host._pitch_freqs.size())
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
        # See the name checklist above for collapse_soft / the 0-or-4 rule.
        var state: int = _deduction._effective_pitch_state(record_idx, note_name, false)
        if (state == 0 or state == 4) and excluded_pitches.has(note_name):
            state = 2
        _host._pitch_checklist_popup.add_pitch_row(note_name, incidence_count, state, STATE_COLORS.neutral)
    _host._pitch_checklist_popup.open(record_idx, _clamp_popup_screen_pos(screen_pos))


func _on_pitch_checklist_check(record_idx: int, note_name: String, _row: StaffPopupRow) -> void:
    if record_idx < 0 or record_idx >= _deduction.record_count():
        return
    if bool(_deduction.record_at(record_idx).get("pitch_revealed", false)):
        return
    var pitch_states: Dictionary = _deduction.record_at(record_idx).get("pitch_states", {})
    var cur: int = int(pitch_states.get(note_name, 0))
    if cur == 1:
        # Toggling back off — see _on_staff_name_check for why siblings
        # aren't restored here.
        pitch_states[note_name] = 0
        _deduction.record_at(record_idx)["pitch_states"] = pitch_states
    else:
        _deduction._propagate_pitch_confirmed_same_record(record_idx, note_name)
    _deduction._save_puzzle_notes()
    _deduction._full_propagation_refresh()
    _open_pitch_checklist_popup(record_idx, _host._pitch_checklist_popup.position)


func _on_pitch_checklist_x(record_idx: int, note_name: String, _row: StaffPopupRow) -> void:
    if record_idx < 0 or record_idx >= _deduction.record_count():
        return
    if bool(_deduction.record_at(record_idx).get("pitch_revealed", false)):
        return
    var r: Dictionary = _deduction.record_at(record_idx)
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
    if record_idx < 0 or record_idx >= _deduction.record_count():
        return
    if bool(_deduction.record_at(record_idx).get("pitch_revealed", false)):
        return
    var r: Dictionary = _deduction.record_at(record_idx)
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
    if record_idx < 0 or record_idx >= _deduction.record_count():
        return
    if bool(_deduction.record_at(record_idx).get("pitch_revealed", false)):
        return
    _deduction._undo_category_selects(record_idx, "pitch_states", "manual_pitch_blocks", "protected_pitch_notes", _distinct_note_names())
    # The confirmed note (if any) no longer exists once selects are undone —
    # same staleness fix _propagate_pitch_confirmed_same_record applies.
    var r: Dictionary = _deduction.record_at(record_idx)
    if str(r.get("pitch_slot_label", "")) != "":
        r["pitch_slot_label"] = ""
    _deduction._save_puzzle_notes()
    _deduction._full_propagation_refresh()
    _open_pitch_checklist_popup(record_idx, _host._pitch_checklist_popup.position)


func _on_pitch_checklist_undo_blocks(record_idx: int) -> void:
    if record_idx < 0 or record_idx >= _deduction.record_count():
        return
    if bool(_deduction.record_at(record_idx).get("pitch_revealed", false)):
        return
    _deduction._undo_category_blocks(record_idx, "pitch_states", "manual_pitch_blocks")
    _deduction._save_puzzle_notes()
    _deduction._full_propagation_refresh()
    _open_pitch_checklist_popup(record_idx, _host._pitch_checklist_popup.position)


func _on_pitch_checklist_undo_all(record_idx: int) -> void:
    if record_idx < 0 or record_idx >= _deduction.record_count():
        return
    if bool(_deduction.record_at(record_idx).get("pitch_revealed", false)):
        return
    _deduction._undo_category_selects(record_idx, "pitch_states", "manual_pitch_blocks", "protected_pitch_notes", _distinct_note_names())
    _deduction._undo_category_blocks(record_idx, "pitch_states", "manual_pitch_blocks")
    var r: Dictionary = _deduction.record_at(record_idx)
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
        btn.add_theme_font_size_override("font_size", 16)
        var cidx: int = int(ci)
        var ridx := record_idx
        btn.pressed.connect(func(): _on_record_color_toggle(ridx, cidx, btn))
        btn.gui_input.connect(func(event: InputEvent):
            if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
                _on_record_color_eliminate(ridx, cidx, btn)
                btn.get_viewport().set_input_as_handled())
        # Effective state so a staff-popup "still possible" mark shows here
        # too — collapse_soft=false, since _style_color_toggle_btn already
        # paints 3 dimmed and 4 magenta and was only ever handed 0/1/2.
        var cur_state: int = _deduction._effective_color_state(record_idx, ci, false)
        if (cur_state == 0 or cur_state == 4) and excluded_colors.has(ci):
            cur_state = 2
        _style_color_toggle_btn(btn, ci, cur_state)
        row.add_child(btn)
    # COPY, on the slot's own colour row — matched by Sequence's and
    # Pitch's own inline copy buttons on their rows (see
    # _make_sequence_range_row_for_record / _make_pitch_checklist_row_for_
    # record). Name is the one axis with no inline copy: it has no
    # candidate list of its own to show inline at all — just the trigger
    # button that opens the shared checklist popup, which carries its own
    # copy button already.
    var copy_btn := Button.new()
    copy_btn.text = "⎘"
    copy_btn.custom_minimum_size = Vector2(26, 24)
    copy_btn.focus_mode = Control.FOCUS_NONE
    copy_btn.tooltip_text = "Write the still-possible colours into the Notes tab"
    var cridx := record_idx
    copy_btn.pressed.connect(func(): _on_staff_copy(cridx, "color"))
    row.add_child(copy_btn)
    return row


func _on_record_color_toggle(record_idx: int, color_idx: int, btn: Button) -> void:
    if record_idx < 0 or record_idx >= _deduction.record_count():
        return
    var r: Dictionary = _deduction.record_at(record_idx)
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
    if record_idx < 0 or record_idx >= _deduction.record_count():
        return
    var r: Dictionary = _deduction.record_at(record_idx)
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
    # A record another Sort:tab has already proven distinct from this one,
    # that has ITSELF confirmed a degree whose incidence count is exactly 1
    # (the only case where excluding it elsewhere is sound), rules that
    # degree out here too — see _compute_excluded_degrees_for. Same pattern
    # as _make_color_toggle_row_for_record; Degree previously had neither
    # this cross-record overlay nor even _effective_degree_state's
    # ground-truth tier, reading the record's own raw degree_states dict
    # directly instead.
    var excluded_degrees: Array[int] = _deduction._compute_excluded_degrees_for(record_idx)
    for deg in degree_list:
        var btn := Button.new()
        btn.text = str(deg)
        btn.custom_minimum_size = Vector2(32, 24)
        btn.focus_mode = Control.FOCUS_NONE
        btn.add_theme_font_size_override("font_size", 16)
        var deg_val: int = int(deg)
        var ridx := record_idx
        btn.pressed.connect(func(): _on_record_degree_toggle(ridx, deg_val, btn))
        btn.gui_input.connect(func(event: InputEvent):
            if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
                _on_record_degree_eliminate(ridx, deg_val, btn)
                btn.get_viewport().set_input_as_handled())
        var cur_state: int = _deduction._effective_degree_state(record_idx, deg_val)
        if cur_state == 0 and excluded_degrees.has(deg_val):
            cur_state = 2
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
    if record_idx < 0 or record_idx >= _deduction.record_count():
        return
    _deduction._propagate_degree_confirmed_same_record(record_idx, degree)
    _style_degree_toggle_btn(btn, degree, 1)
    _deduction._save_puzzle_notes()
    _deduction._full_propagation_refresh()


func _on_record_degree_eliminate(record_idx: int, degree: int, btn: Button) -> void:
    if record_idx < 0 or record_idx >= _deduction.record_count():
        return
    var r: Dictionary = _deduction.record_at(record_idx)
    r["degree_states"][degree] = 2
    _style_degree_toggle_btn(btn, degree, 2)
    _deduction._save_puzzle_notes()
    _deduction._full_propagation_refresh()


func _make_sequence_range_row_for_record(record_idx: int, row_color: Color) -> HBoxContainer:
    var row := HBoxContainer.new()
    row.add_theme_constant_override("separation", 2)

    var edit_lo := LineEdit.new()
    # A bare two-digit bound is all this box ever shows now — the "= N"
    # exact-pin form moved to the centre box (see _refresh_range_edits), so
    # it no longer needs room for the leading "= ". minimum_character_width
    # is the real floor here, not custom_minimum_size: LineEdit's own
    # get_minimum_size() (character-width-based) and custom_minimum_size
    # are both floors, and Godot renders at whichever is LARGER — at 2 it
    # was silently overriding the previous custom_minimum_size shrink, so
    # this drops it to 1 as well or the box would not visibly shrink at all.
    edit_lo.custom_minimum_size = Vector2(16, 24)
    edit_lo.max_length = 2
    edit_lo.placeholder_text = "–"
    edit_lo.add_theme_font_size_override("font_size", 15)
    edit_lo.add_theme_constant_override("minimum_character_width", 1)
    _style_range_edit(edit_lo, row_color)
    row.add_child(edit_lo)

    var lbl_lt := Label.new()
    lbl_lt.text = "<"
    lbl_lt.add_theme_font_size_override("font_size", 16)
    lbl_lt.add_theme_color_override("font_color", Color(0.7, 0.65, 0.85, 0.9))
    row.add_child(lbl_lt)

    var edit_mid := LineEdit.new()
    edit_mid.custom_minimum_size = Vector2(96, 24)
    edit_mid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    edit_mid.max_length = _max_candidate_list_length()
    edit_mid.placeholder_text = "–"
    edit_mid.text = _deduction._compressed_possible_positions_str(record_idx)
    edit_mid.add_theme_font_size_override("font_size", 14)
    edit_mid.alignment = HORIZONTAL_ALIGNMENT_CENTER
    _style_range_edit(edit_mid, row_color)
    row.add_child(edit_mid)

    var lbl_gt := Label.new()
    lbl_gt.text = "<"
    lbl_gt.add_theme_font_size_override("font_size", 16)
    lbl_gt.add_theme_color_override("font_color", Color(0.7, 0.65, 0.85, 0.9))
    row.add_child(lbl_gt)

    var edit_hi := LineEdit.new()
    edit_hi.custom_minimum_size = Vector2(14, 24)
    edit_hi.max_length = 2
    edit_hi.placeholder_text = "–"
    edit_hi.add_theme_font_size_override("font_size", 15)
    edit_hi.add_theme_constant_override("minimum_character_width", 1)
    _style_range_edit(edit_hi, row_color)
    row.add_child(edit_hi)

    var ridx := record_idx
    edit_lo.text_submitted.connect(func(_t): _commit_sequence_range(ridx, edit_lo, edit_mid, edit_hi))
    edit_lo.focus_exited.connect(func(): _commit_sequence_range(ridx, edit_lo, edit_mid, edit_hi))
    edit_hi.text_submitted.connect(func(_t): _commit_sequence_range(ridx, edit_lo, edit_mid, edit_hi))
    edit_hi.focus_exited.connect(func(): _commit_sequence_range(ridx, edit_lo, edit_mid, edit_hi))
    edit_mid.text_submitted.connect(func(_t): _commit_sequence_candidates(ridx, edit_lo, edit_mid, edit_hi))
    edit_mid.focus_exited.connect(func(): _commit_sequence_candidates(ridx, edit_lo, edit_mid, edit_hi))

    # Initial render goes through the same formatter the commit path uses,
    # so an exact pin shows as "= N" here too rather than the contradictory
    # "N < x < N" the raw display helpers produce.
    _refresh_range_edits(record_idx, edit_lo, edit_mid, edit_hi)

    # COPY, matching Colour's and Pitch's inline buttons — see
    # _make_color_toggle_row_for_record. "Still possible" for Sequence is
    # exactly the centre box's own candidate set (_effective_seq_candidates),
    # so this writes the same list the player is already looking at.
    var copy_btn := Button.new()
    copy_btn.text = "⎘"
    copy_btn.custom_minimum_size = Vector2(26, 24)
    copy_btn.focus_mode = Control.FOCUS_NONE
    copy_btn.tooltip_text = "Write the still-possible sequence positions into the Notes tab"
    copy_btn.pressed.connect(func(): _on_staff_copy(ridx, "sequence"))
    row.add_child(copy_btn)

    return row


# ==================================================
# SEQUENCE RANGE COMMIT — one implementation, two entry points.
#
# The Sort:tab row and the floating star-widget row were near-identical
# copies differing only in how the record is obtained (passed in vs.
# resolved from a star index). Every fix to the commit logic had to be
# hand-mirrored between them — done three separate times in one session
# before this extraction — which is exactly how the two silently drift.
# The shared body lives here; the two _on_*_committed functions below are
# thin adapters that resolve a record and delegate.
# ==================================================
## Re-renders a record's THREE boxes from its CURRENT stored state — the
## two bound boxes and the centre candidate-list box. Used both after a
## successful commit and to snap the row back when an entry is rejected, so
## a refused entry visibly reverts instead of sitting there looking
## accepted. Single source for the display formatting, which the commit
## path and the conflict-cancel path each used to spell out.
func _refresh_range_edits(record_idx: int, lo_edit: LineEdit, mid_edit: LineEdit, hi_edit: LineEdit) -> void:
    if record_idx < 0 or record_idx >= _deduction.record_count():
        lo_edit.text = ""
        mid_edit.text = ""
        hi_edit.text = ""
        return
    # EFFECTIVE bounds, not the raw stored pair — matches what the row
    # builders show (derived narrowing included), so a rebuild and a
    # post-commit refresh can't disagree about the same row.
    var bounds: Array = _deduction._effective_seq_bounds(record_idx)
    var lo: int = int(bounds[0])
    var hi: int = int(bounds[1])
    # An exact pin renders as "= N" in the CENTRE box — the candidate-list
    # box, which is exactly where a single remaining candidate belongs —
    # with both bound boxes cleared, instead of the contradiction "7 < x <
    # 7" this row's "lo < position < hi" notation would otherwise read as.
    # The commit path already treats two equal typed values as an exact
    # pin, and _parse_exclusive_bounds keeps accepting that form.
    if lo > 0 and lo == hi:
        lo_edit.text = ""
        hi_edit.text = ""
        mid_edit.text = "= %d" % lo
        return
    var lo_val: int = _deduction._exclusive_display_lo(lo, hi)
    var hi_val: int = _deduction._exclusive_display_hi(lo, hi)
    lo_edit.text = str(lo_val) if lo_val > 0 else ""
    hi_edit.text = str(hi_val) if hi_val > 0 else ""
    mid_edit.text = _deduction._compressed_possible_positions_str(record_idx)


func _commit_sequence_range(record_idx: int, lo_edit: LineEdit, mid_edit: LineEdit, hi_edit: LineEdit) -> void:
    if record_idx < 0 or record_idx >= _deduction.record_count():
        return
    var raw_lo: String = lo_edit.text.strip_edges()
    var raw_hi: String = hi_edit.text.strip_edges()

    # "= N" is how _refresh_range_edits renders an exact pin (see there for
    # why it isn't shown as "N < x < N"). It has to survive being committed
    # again — focus_exited fires on any interaction with the row — so it's
    # parsed back into the equal-values form the exact branch expects.
    # A player typing "=12" by hand works for the same reason.
    var exact_typed: bool = raw_lo.begins_with("=")
    if exact_typed:
        raw_lo = raw_lo.substr(1).strip_edges()

    var typed_lo: int = int(raw_lo) if raw_lo.is_valid_int() else 0
    var typed_hi: int = int(raw_hi) if raw_hi.is_valid_int() else 0

    if typed_lo < 1 or typed_lo > _host._star_count: typed_lo = 0
    if typed_hi < 1 or typed_hi > _host._star_count: typed_hi = 0

    if exact_typed:
        if typed_lo <= 0:
            _refresh_range_edits(record_idx, lo_edit, mid_edit, hi_edit)
            return
        typed_hi = typed_lo

    if typed_lo > 0 and typed_hi > 0 and typed_lo > typed_hi:
        var tmp := typed_lo; typed_lo = typed_hi; typed_hi = tmp

    var converted: Array = _deduction._parse_exclusive_bounds(typed_lo, typed_hi)
    var lo: int = int(converted[0])
    var hi: int = int(converted[1])

    var r: Dictionary = _deduction.record_at(record_idx)

    # NO-OP EARLY-OUT. This handler is bound to text_submitted AND
    # focus_exited on both boxes, so a single Enter press used to run the
    # whole thing twice: the commit rebuilds every row (replacing the very
    # LineEdit being edited), focus then leaves the stale node, and
    # focus_exited fires a second identical commit — each one a full
    # _full_propagation_refresh with a synchronous rebuild of all 15 star
    # widgets and every Sort row. Merely tabbing through a row without
    # editing did the same. Bailing when the parsed result already matches
    # what's stored removes that entire duplicate pass; the display is
    # already correct by construction in that case, so there is nothing to
    # re-render either.
    if lo == int(r.get("seq_lo", 0)) and hi == int(r.get("seq_hi", 0)) \
            and (r.get("seq_candidates", []) as Array).is_empty():
        return

    # Reject an entry whose CONVERTED bounds can't be satisfied, instead of
    # writing a meaningless range. The clamps above only check the typed
    # numbers are within 1..star_count; they say nothing about whether the
    # exclusive bound those numbers produce is reachable, and the two
    # extremes used to fail silently in opposite directions:
    #   * "< 1" (typing 1 in the high box) converts to hi = 0, which is the
    #     sentinel for NO upper bound — an impossible constraint silently
    #     became "any position", the exact inverse of the request.
    #   * "> star_count" (typing the last position in the low box) converts
    #     to lo = star_count + 1, giving an empty candidate set that reads
    #     as "no information" in _record_descriptor_state but as a genuinely
    #     empty set in _effective_seq_bounds.
    # Same shape as _merge_match_records' "bounds contradict once
    # intersected" guard: keep what was there and re-render it, so the row
    # visibly snaps back rather than appearing to accept the entry.
    # The equal-values case is an EXACT pin, not a pair of exclusive bounds
    # (see _parse_exclusive_bounds' first branch), so "1 and 1" or
    # "15 and 15" are perfectly valid and must skip these checks — they'd
    # otherwise be rejected as "< 1" and "> 15".
    var is_exact_entry: bool = typed_lo > 0 and typed_lo == typed_hi
    if not is_exact_entry:
        var impossible_hi: bool = typed_hi > 0 and typed_hi <= 1
        var impossible_lo: bool = typed_lo > 0 and typed_lo >= _host._star_count
        if impossible_hi or impossible_lo or (lo > 0 and hi > 0 and lo > hi):
            _refresh_range_edits(record_idx, lo_edit, mid_edit, hi_edit)
            return

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
            _refresh_range_edits(record_idx, lo_edit, mid_edit, hi_edit)
            _deduction._full_propagation_refresh()
            return

    r["seq_lo"] = lo
    r["seq_hi"] = hi
    r["seq_candidates"] = []

    _refresh_range_edits(record_idx, lo_edit, mid_edit, hi_edit)

    if lo > 0 and lo == hi:
        var existing_idx: int = _deduction._find_match_record_by_exact_seq(lo)
        if existing_idx >= 0 and existing_idx != record_idx:
            record_idx = await _deduction._merge_match_records(record_idx, existing_idx)

    _deduction._save_puzzle_notes()
    _deduction._full_propagation_refresh()


func _commit_sequence_candidates(record_idx: int, lo_edit: LineEdit, mid_edit: LineEdit, hi_edit: LineEdit) -> void:
    if record_idx < 0 or record_idx >= _deduction.record_count():
        return
    var raw: String = mid_edit.text.strip_edges()
    if raw == "":
        _deduction.record_at(record_idx)["seq_candidates"] = []
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
        _commit_sequence_range(record_idx, lo_edit, mid_edit, hi_edit)
        return

    _deduction.record_at(record_idx)["seq_candidates"] = valid
    _deduction.record_at(record_idx)["seq_lo"] = 0
    _deduction.record_at(record_idx)["seq_hi"] = 0
    _deduction._save_puzzle_notes()
    _deduction._full_propagation_refresh()


func _on_record_name_selected(record_idx: int, selected_name: String) -> void:
    if record_idx < 0 or record_idx >= _deduction.record_count():
        return
    var r: Dictionary = _deduction.record_at(record_idx)
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
# RANGE CALLBACKS — floating star-widget entry points. Both used to
# be full copies of the Sort:tab versions above; they are adapters
# now, resolving the star to its record and delegating to the one
# shared implementation (_commit_sequence_range /
# _commit_sequence_candidates).
# ==================================================
func _on_widget_range_committed(star_idx: int, lo_edit: LineEdit, mid_edit: LineEdit, hi_edit: LineEdit) -> void:
    if star_idx < 0 or star_idx >= _host._star_count:
        return
    _commit_sequence_range(
        _deduction._get_or_create_match_record_for_star_idx(star_idx), lo_edit, mid_edit, hi_edit)


func _on_widget_middle_committed(star_idx: int, lo_edit: LineEdit, mid_edit: LineEdit, hi_edit: LineEdit) -> void:
    if star_idx < 0 or star_idx >= _host._star_count:
        return
    _commit_sequence_candidates(
        _deduction._get_or_create_match_record_for_star_idx(star_idx), lo_edit, mid_edit, hi_edit)


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


## The clue's canonical 1-based number: its index in the puzzle's own saved
## clue order (_form_clues_cache), NOT its position in whichever tab is
## showing it.
##
## This distinction is the whole point of the feature. The number exists so
## two people can say "clue 14" and mean the same clue, and every tab shows
## a DIFFERENT subset — Clues hides anything filed into Notes, Notes shows
## only those, SEARCH filters by term. Numbering by display position would
## give the same clue a different number in each tab, and would renumber
## the entire list the moment a clue was filed. Canonical order is fixed
## for the life of the puzzle, and is the same numbering
## debug_dump_clueset() prints, so a dev dump and a player's screen agree.
##
## Returns 0 when the text isn't found, which _clue_number_prefix renders
## as no prefix at all rather than a wrong "0.".
func _clue_number_for_text(text: String) -> int:
    if text == "":
        return 0
    var all: Array[Dictionary] = _all_final_clues_for_tabs()
    for i in all.size():
        if str(all[i].get("text", "")) == text:
            return i + 1
    return 0


## Dimmed "12." prefix. Muted on purpose — it is a reference handle for
## talking about the clue, not part of what the clue says, so it must not
## compete with the clue's own state colour.
func _clue_number_prefix(number: int) -> String:
    if number <= 0:
        return ""
    return "[color=#%s]%d.[/color]  " % [STATE_COLORS.muted.to_html(), number]


## `color` is the clue's player-driven state: green untouched, magenta
## worked on (see _clue_state_color). It used to be ignored entirely — the
## parameter was `_color` — because the tab itself carried the state.
##
## `number` is the canonical clue number (see _clue_number_for_text); 0
## renders no prefix. It affects the DISPLAY only — `clue_text` meta and
## every identity comparison below still use the raw text, because that is
## what selection, right-click filing and click-to-jump all match on.
func _make_clue_label(text: String, color: Color, number: int = 0) -> PanelContainer:
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
    rtl.text = _clue_number_prefix(number) + _bbcode_for_clue_text(text)
    rtl.add_theme_color_override("default_color", color)
    rtl.add_theme_font_size_override("normal_font_size", 18)
    rtl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    rtl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    pc.add_child(rtl)

    var captured_text := text
    pc.gui_input.connect(func(event: InputEvent):
        if not (event is InputEventMouseButton and event.pressed):
            return
        if event.button_index == MOUSE_BUTTON_LEFT:
            _on_clue_row_clicked(captured_text)
            pc.get_viewport().set_input_as_handled()
        elif event.button_index == MOUSE_BUTTON_RIGHT:
            # File to Notes, or un-file from there. Symmetric on purpose:
            # this is the player's own filing, so a misclick must cost one
            # more click and nothing else.
            _deduction.toggle_clue_noted(captured_text)
            # The row is about to be freed by the rebuild, so drop any
            # pin pointing at it first.
            if _host._selected_clue_text == captured_text:
                _host._selected_clue_text = ""
                _host._selected_clue_tab = -1
            request_markers_rebuild()
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
    # The pinned readout carries the number too — it is the one clue a
    # player is most likely to be quoting to someone else. Looked up by
    # text rather than threaded through the click, so it stays correct no
    # matter which tab did the pinning.
    var pinned: String = _host._selected_clue_text
    if pinned == "":
        _host._select_clue("")
    else:
        _host._select_clue(_clue_number_prefix(_clue_number_for_text(pinned))
            + _bbcode_for_clue_text(pinned))
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
    lbl.add_theme_font_size_override("font_size", 19)
    lbl.add_theme_color_override("font_color", Color(color.r, color.g, color.b, 1.0))
    row.add_child(lbl)
    row.add_child(control)
    return row


func _make_fact_line(text: String, color: Color) -> Label:
    var lbl := Label.new()
    lbl.text = text
    lbl.add_theme_font_size_override("font_size", 19)
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
    seq_lbl.add_theme_font_size_override("font_size", 19)
    seq_lbl.add_theme_color_override("font_color", row_color)
    row.add_child(seq_lbl)

    var facts_vbox := VBoxContainer.new()
    facts_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    facts_vbox.add_theme_constant_override("separation", 1)
    row.add_child(facts_vbox)

    facts_vbox.add_child(_make_fact_row("Name:", _make_name_checklist_trigger_button(record_idx), row_color))
    facts_vbox.add_child(_make_fact_row("Color:", _make_color_toggle_row_for_record(record_idx), row_color))
    facts_vbox.add_child(_make_fact_row("Pitch:", _make_pitch_checklist_row_for_record(record_idx), row_color))

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
    color_lbl.add_theme_font_size_override("font_size", 19)
    color_lbl.add_theme_color_override("font_color", _host.STAR_COLORS_BY_IDX[color_idx])
    row.add_child(color_lbl)

    var facts_vbox := VBoxContainer.new()
    facts_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    facts_vbox.add_theme_constant_override("separation", 1)
    row.add_child(facts_vbox)

    facts_vbox.add_child(_make_fact_row("Name:", _make_name_checklist_trigger_button(record_idx), row_color))
    facts_vbox.add_child(_make_fact_row("Sequence:", _make_sequence_range_row_for_record(record_idx, row_color), row_color))
    facts_vbox.add_child(_make_fact_row("Pitch:", _make_pitch_checklist_row_for_record(record_idx), row_color))

    _host._markers_content.add_child(HSeparator.new())


func _populate_color_group_rows() -> void:
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
    pitch_lbl.add_theme_font_size_override("font_size", 19)
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
    degree_lbl.add_theme_font_size_override("font_size", 19)
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
    name_lbl.add_theme_font_size_override("font_size", 19)
    name_lbl.add_theme_color_override("font_color", row_color)
    row.add_child(name_lbl)

    var facts_vbox := VBoxContainer.new()
    facts_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    facts_vbox.add_theme_constant_override("separation", 1)
    row.add_child(facts_vbox)

    facts_vbox.add_child(_make_fact_row("Color:", _make_color_toggle_row_for_record(record_idx), row_color))
    facts_vbox.add_child(_make_fact_row("Sequence:", _make_sequence_range_row_for_record(record_idx, row_color), row_color))
    facts_vbox.add_child(_make_fact_row("Pitch:", _make_pitch_checklist_row_for_record(record_idx), row_color))

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


## Staff name row. Still smaller than the numeral — a name is far longer
## than a digit — but no longer squeezed to a single column's width: the two
## staggered rows below give each name its neighbours' space as well.
const FONT_SIZE_STAFF_NAME: int = 12

## Names alternate between two rows, ODD positions high and EVEN low, so a
## name's horizontal neighbours are never on its own row. Its nearest
## same-row neighbours are two positions away, which is what buys the ~2x
## width — at 15 stars a single column is about a third of a name and the
## ellipsis fired constantly.
##
## All three offsets are from the PANEL'S TOP EDGE now (name/pitch swapped
## 2026-08-29: Name+numeral read first, above the staff; Pitch's height-
## mapped note sits below them). The numeral sits below both name rows.
## Keep NAME_ROW_LOW_DY < the numeral's offset or the low row lands on top
## of it.
const NAME_ROW_HIGH_DY: float = 12.0
const NAME_ROW_LOW_DY: float = 24.0
const STAFF_NUMERAL_DY: float = 38.0


## `text` shortened with a trailing ellipsis until it fits `max_w`.
##
## Returns "" rather than a lone ellipsis when even one character will not
## fit — a column too narrow to say anything should say nothing, not draw a
## dot the player might read as a value.
func _fit_string_to_width(font: Font, text: String, size: int, max_w: float) -> String:
    if max_w <= 0.0:
        return ""
    if font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x <= max_w:
        return text
    var cut: int = text.length() - 1
    while cut > 0:
        var candidate: String = text.substr(0, cut) + "…"
        if font.get_string_size(candidate, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x <= max_w:
            return candidate
        cut -= 1
    return ""


func _draw_melody_staff() -> void:
    var panel_size: Vector2 = _host._melody_staff_panel.size
    if _host._star_count <= 0 or panel_size.x <= 0.0 or panel_size.y <= 0.0:
        return

    var margin_x: float = 20.0
    var staff_pad_bottom: float = 14.0
    # Room for THREE readout rows ABOVE the staff now (swapped 2026-08-29):
    # the two staggered name rows (NAME_ROW_HIGH_DY / NAME_ROW_LOW_DY) and
    # the numeral below them (STAFF_NUMERAL_DY), plus a few px of
    # clearance before the staff itself starts. Derived from those
    # constants rather than typed, so moving a row cannot silently push it
    # into the staff.
    #
    # Taken out of the staff's own height, not the panel's, so the .tscn
    # stays untouched and the pitch spread just compresses.
    var staff_top: float = STAFF_NUMERAL_DY + 8.0
    var usable_w: float = panel_size.x - margin_x * 2.0
    var usable_h: float = panel_size.y - staff_top - staff_pad_bottom
    var step_x: float = usable_w / float(maxi(_host._star_count - 1, 1))

    var baseline_y: float = staff_top + usable_h * 0.5
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
            Vector2(bx, staff_top), Vector2(bx, staff_top + usable_h), bar_col, 1.0)
        pos += 4

    # No per-readout colours any more: every mark belonging to a position
    # takes that POSITION's colour. See pos_col in the loop.
    var font := ThemeDB.fallback_font
    var font_size_small := 16

    for seq_pos in range(1, _host._star_count + 1):
        var x: float = margin_x + step_x * float(seq_pos - 1)
        var marker: Dictionary = _deduction._melody_marker_for_position(seq_pos)

        # ONE COLOUR PER POSITION, and COLOUR is what sets it.
        #
        # Green (UNKNOWN_SEQ_COLOR) is the not-yet-known state for the whole
        # position: at puzzle start the numeral and both "?" marks are
        # green. The moment the position's COLOUR is deduced, all three turn
        # that colour — whether they are still showing "?" or have since
        # resolved to a real pitch and name. So the row reads as "this
        # position is now known to be a blue star" independently of how much
        # else about it has been worked out.
        #
        # Colour is a GIVEN axis (painted on the map), so tinting by it
        # reveals nothing the player has not already got.
        var known_color: int = _deduction._known_color_for_seq_position(seq_pos)
        var pos_col: Color = _host.STAR_COLORS_BY_IDX[known_color] if known_color >= 0 else _host.UNKNOWN_SEQ_COLOR

        # NAME, on one of two staggered rows, above the staff. "?" until
        # identified, then the name itself.
        #
        # ODD positions high, EVEN low, so no name shares a row with either
        # horizontal neighbour and each may run to roughly TWO columns
        # before it can collide — with the position two along, on its own
        # row. The ellipsis stays as a backstop for a very narrow panel or a
        # very long name, but at 15 stars it should now rarely fire.
        var star_name: String = _deduction._known_name_for_seq_position(seq_pos)
        var name_dy: float = NAME_ROW_HIGH_DY if seq_pos % 2 == 1 else NAME_ROW_LOW_DY
        var name_label: String = _fit_string_to_width(
            font, star_name, FONT_SIZE_STAFF_NAME, step_x * 2.0 - 6.0) if star_name != "" else "?"
        var fw: float = font.get_string_size(name_label, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE_STAFF_NAME).x
        _host._melody_staff_panel.draw_string(font, Vector2(x - fw * 0.5, name_dy),
            name_label, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE_STAFF_NAME, pos_col)

        var num_label: String = str(seq_pos)
        var nw: float = font.get_string_size(num_label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size_small).x
        _host._melody_staff_panel.draw_string(font, Vector2(x - nw * 0.5, STAFF_NUMERAL_DY),
            num_label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size_small, pos_col)

        # PITCH: its note at its own staff height once known, otherwise "?"
        # on the baseline, now below the name/numeral block. The "?" is NOT
        # gated on a record existing at this position — every position has
        # a pitch to find, so every unresolved one says so from the start.
        # It used to draw only where a record was already pinned, which
        # meant a fresh puzzle showed nothing at all across the whole staff.
        if marker["pitch_known"]:
            var freq: float = _freq_for_note_name(str(marker["note_name"]))
            var frac: float = _freq_to_y_fraction(freq)
            var y: float = staff_top + usable_h * (1.0 - frac)
            _host._melody_staff_panel.draw_circle(Vector2(x, y), 5.0, pos_col)
            var label: String = str(marker["note_name"])
            var label_w: float = font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size_small).x
            _host._melody_staff_panel.draw_string(font, Vector2(x - label_w * 0.5, y - 9.0),
                label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size_small, pos_col)
        else:
            var qw: float = font.get_string_size("?", HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
            _host._melody_staff_panel.draw_string(font, Vector2(x - qw * 0.5, baseline_y + 4.0),
                "?", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, pos_col)


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
    # Second argument is the row TOTAL, which the column-major split needs
    # — see StaffPopup._add_row_to_column_array. Each section receives
    # exactly as many rows as the collection it is built from, and the
    # loops below add one row per element with no filtering, so these
    # counts are the totals rather than an estimate of them.
    _host._staff_popup.set_pitch_column_count(
        _staff_popup_column_count(_host._pitch_freqs.size()), _host._pitch_freqs.size())
    _host._staff_popup.set_color_column_count(
        _staff_popup_column_count(_host.COLOR_NAME_LABELS.size()), _host.COLOR_NAME_LABELS.size())
    _host._staff_popup.set_name_column_count(
        _staff_popup_column_count(_host._star_count), _host._star_count)

    # Add pitch rows — same cross-record exclusion as
    # _open_pitch_checklist_popup, since the Staff popup is a third UI
    # surface hitting the exact same records (see
    # _compute_excluded_pitches_for).
    var excluded_pitches: Array[String] = _deduction._compute_excluded_pitches_for(record_idx)
    for pitch_idx in _host._pitch_freqs.size():
        var f: float = _host._pitch_freqs[pitch_idx]
        var note_name: String = ConstellationLogicPuzzle.note_name_for_freq(f)
        var incidence_count: int = _deduction._pitch_star_count(note_name)
        # See _open_name_checklist_popup for collapse_soft / the 0-or-4 rule.
        var state: int = _deduction._effective_pitch_state(record_idx, note_name, false)
        if (state == 0 or state == 4) and excluded_pitches.has(note_name):
            state = 2
        _host._staff_popup.add_pitch_row(note_name, incidence_count, state, STATE_COLORS.neutral)

    # Add color rows — same cross-record exclusion as
    # _make_color_toggle_row_for_record (see _compute_excluded_colors_for).
    var excluded_colors: Array[int] = _deduction._compute_excluded_colors_for(record_idx)
    for ci in _host.COLOR_NAME_LABELS.size():
        var cstate: int = _deduction._effective_color_state(record_idx, ci, false)
        if (cstate == 0 or cstate == 4) and excluded_colors.has(ci):
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
        var state: int = _deduction._effective_name_state(record_idx, name_str, false)
        if (state == 0 or state == 4) and excluded_names.has(name_str):
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

    # Centering in the PANEL doesn't know the header eats some of that
    # panel's height — for a tall enough popup (many stars, even after the
    # column-scaling above) the centered top edge lands ABOVE the header,
    # over the clue box. This is the actual floor.
    _host._staff_popup.open(seq_pos, record_idx, _clamp_popup_screen_pos(screen_pos))


func _on_staff_pitch_check(record_idx: int, note_name: String, _row: StaffPopupRow) -> void:
    if bool(_deduction.record_at(record_idx).get("pitch_revealed", false)):
        return
    var pitch_states: Dictionary = _deduction.record_at(record_idx).get("pitch_states", {})
    var cur: int = int(pitch_states.get(note_name, 0))
    var new_state: int = 0 if cur == 1 else 1
    if new_state == 1:
        _deduction._propagate_pitch_confirmed_same_record(record_idx, note_name)
    else:
        pitch_states[note_name] = new_state
        _deduction.record_at(record_idx)["pitch_states"] = pitch_states
    _deduction._save_puzzle_notes()
    _deduction._full_propagation_refresh()
    _open_staff_popup(_host._staff_popup_seq_pos, _host._staff_popup.position)


func _on_staff_pitch_x(record_idx: int, note_name: String, _row: StaffPopupRow) -> void:
    if bool(_deduction.record_at(record_idx).get("pitch_revealed", false)):
        return
    var r: Dictionary = _deduction.record_at(record_idx)
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
    if not bool(_deduction.record_at(record_idx).get("pitch_revealed", false)):
        _on_record_value_protect_toggle(record_idx, "pitch_states", "protected_pitch_notes", note_name)


func _on_staff_color_check(record_idx: int, color_idx: int, _row: StaffPopupRow) -> void:
    var r: Dictionary = _deduction.record_at(record_idx)
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
    var r: Dictionary = _deduction.record_at(record_idx)
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
    var r: Dictionary = _deduction.record_at(record_idx)
    var name_states: Dictionary = r.get("name_states", {})
    var cur: int = int(name_states.get(star_name, 0))
    if cur == 1:
        # Toggling back off — just this name reverts to neutral; siblings
        # already eliminated by the confirm below stay as they were, same
        # "eliminations are sticky" behavior as color/pitch/degree. Also
        # clears r["name"] when it's this same name — _propagate_name_
        # states_confirmed_same_record now promotes into r["name"] on
        # confirm (see its own comment), so leaving it set here would keep
        # this record permanently identified even after the player
        # explicitly undoes the confirm that set it.
        name_states[star_name] = 0
        r["name_states"] = name_states
        if str(r.get("name", "")) == star_name:
            r["name"] = ""
    else:
        _deduction._propagate_name_states_confirmed_same_record(record_idx, star_name)
    _deduction._save_puzzle_notes()
    _deduction._full_propagation_refresh()
    _open_staff_popup(_host._staff_popup_seq_pos, _host._staff_popup.position)


func _on_staff_name_x(record_idx: int, star_name: String, _row: StaffPopupRow) -> void:
    var r: Dictionary = _deduction.record_at(record_idx)
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
    if bool(_deduction.record_at(record_idx).get("pitch_revealed", false)):
        return
    _deduction._undo_category_selects(record_idx, "pitch_states", "manual_pitch_blocks", "protected_pitch_notes", _distinct_note_names())
    var r: Dictionary = _deduction.record_at(record_idx)
    if str(r.get("pitch_slot_label", "")) != "":
        r["pitch_slot_label"] = ""
    _deduction._save_puzzle_notes()
    _deduction._full_propagation_refresh()
    _open_staff_popup(_host._staff_popup_seq_pos, _host._staff_popup.position)


func _on_staff_pitch_undo_blocks(record_idx: int) -> void:
    if bool(_deduction.record_at(record_idx).get("pitch_revealed", false)):
        return
    _deduction._undo_category_blocks(record_idx, "pitch_states", "manual_pitch_blocks")
    _deduction._save_puzzle_notes()
    _deduction._full_propagation_refresh()
    _open_staff_popup(_host._staff_popup_seq_pos, _host._staff_popup.position)


func _on_staff_pitch_undo_all(record_idx: int) -> void:
    if bool(_deduction.record_at(record_idx).get("pitch_revealed", false)):
        return
    _deduction._undo_category_selects(record_idx, "pitch_states", "manual_pitch_blocks", "protected_pitch_notes", _distinct_note_names())
    _deduction._undo_category_blocks(record_idx, "pitch_states", "manual_pitch_blocks")
    var r: Dictionary = _deduction.record_at(record_idx)
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
    var r: Dictionary = _deduction.record_at(record_idx)
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
    var r: Dictionary = _deduction.record_at(record_idx)
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
    var r: Dictionary = _deduction.record_at(record_idx)
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
# Coalescing flags for the three deferred UI rebuilds below. call_deferred()
# QUEUES every call rather than collapsing duplicates, so a frame that
# triggers several _full_propagation_refresh() passes used to run the full
# teardown-and-rebuild of ~15 star widgets (each carrying a 15-name
# checklist), their tags, and the markers panel once PER pass. The result is
# identical either way — each rebuild reads the same settled state — so only
# the first request in a frame needs to survive.
var _star_widgets_dirty: bool = false
var _star_tags_dirty: bool = false
var _markers_dirty: bool = false


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
    if _star_widgets_dirty:
        return   # already queued this frame; one rebuild is enough
    _star_widgets_dirty = true
    call_deferred("_build_star_widgets_impl")


func _build_star_widgets_impl() -> void:
    _star_widgets_dirty = false
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

        var edit_lo := LineEdit.new()
        # Wide enough for the "= N" exact-pin form (see _refresh_range_edits).
        edit_lo.custom_minimum_size = Vector2(38, 28)
        edit_lo.max_length = 4
        edit_lo.placeholder_text = "–"
        edit_lo.add_theme_font_size_override("font_size", 16)
        edit_lo.add_theme_constant_override("minimum_character_width", 2)
        _style_range_edit(edit_lo, star_color)
        range_row.add_child(edit_lo)

        var lbl_lt := Label.new()
        lbl_lt.text = "<"
        lbl_lt.add_theme_font_size_override("font_size", 17)
        lbl_lt.add_theme_color_override("font_color", Color(0.7, 0.65, 0.85, 1.0))
        lbl_lt.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
        range_row.add_child(lbl_lt)

        var edit_mid := LineEdit.new()
        edit_mid.custom_minimum_size = Vector2(96, 28)
        edit_mid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        edit_mid.max_length = _max_candidate_list_length()
        edit_mid.placeholder_text = "–"
        edit_mid.text = _deduction._compressed_possible_positions_str(existing_record)
        edit_mid.add_theme_font_size_override("font_size", 14)
        edit_mid.alignment = HORIZONTAL_ALIGNMENT_CENTER
        _style_range_edit(edit_mid, star_color)
        range_row.add_child(edit_mid)

        var lbl_gt := Label.new()
        lbl_gt.text = "<"
        lbl_gt.add_theme_font_size_override("font_size", 17)
        lbl_gt.add_theme_color_override("font_color", Color(0.7, 0.65, 0.85, 1.0))
        lbl_gt.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
        range_row.add_child(lbl_gt)

        var edit_hi := LineEdit.new()
        edit_hi.custom_minimum_size = Vector2(20, 28)
        edit_hi.max_length = 2
        edit_hi.placeholder_text = "–"
        edit_hi.add_theme_font_size_override("font_size", 16)
        edit_hi.add_theme_constant_override("minimum_character_width", 2)
        _style_range_edit(edit_hi, star_color)
        range_row.add_child(edit_hi)

        # COPY, in the space the ✕ close button used to occupy — that
        # button is redundant now that clicking outside this popup closes
        # it (see _maybe_close_star_widget_on_outside_click in
        # constellation_study_overlay.gd), matching every other popup on
        # this panel. "Still possible" for Sequence is exactly the centre
        # box's own candidate set, same as the Sort:tab row's copy button.
        var range_copy_btn := Button.new()
        range_copy_btn.text = "⎘"
        range_copy_btn.custom_minimum_size = Vector2(26, 28)
        range_copy_btn.focus_mode = Control.FOCUS_NONE
        range_copy_btn.tooltip_text = "Write the still-possible sequence positions into the Notes tab"
        var range_copy_rec := existing_record
        range_copy_btn.pressed.connect(func(): _on_staff_copy(range_copy_rec, "sequence"))
        range_row.add_child(range_copy_btn)

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
        pitch_lbl.add_theme_font_size_override("font_size", 16)
        if bool(_deduction.record_at(existing_record).get("pitch_revealed", false)):
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
        edit_lo.text_submitted.connect(func(_t): _on_widget_range_committed(si, lo_ref, mid_ref, hi_ref))
        edit_lo.focus_exited.connect(func(): _on_widget_range_committed(si, lo_ref, mid_ref, hi_ref))
        edit_hi.text_submitted.connect(func(_t): _on_widget_range_committed(si, lo_ref, mid_ref, hi_ref))
        edit_hi.focus_exited.connect(func(): _on_widget_range_committed(si, lo_ref, mid_ref, hi_ref))
        edit_mid.text_submitted.connect(func(_t): _on_widget_middle_committed(si, lo_ref, mid_ref, hi_ref))
        edit_mid.focus_exited.connect(func(): _on_widget_middle_committed(si, lo_ref, mid_ref, hi_ref))

        # Same shared formatter as the Sort:tab row (see there).
        if existing_record >= 0:
            _refresh_range_edits(existing_record, edit_lo, edit_mid, edit_hi)

        # ── Reset buttons ──────────────────────────────────────────
        var reset_row := HBoxContainer.new()
        reset_row.mouse_filter = Control.MOUSE_FILTER_PASS
        reset_row.add_theme_constant_override("separation", 3)
        root.add_child(reset_row)

        var btn_undo_sel := Button.new()
        # "Undo ✓" / "Undo ✕", not the old "Undo selects"/"Undo blocks" —
        # same ✓/✕ iconography as the checklist rows just below this row,
        # shortened specifically to free width for the COPY button added
        # at the end of this row.
        btn_undo_sel.text = "Undo ✓"
        btn_undo_sel.tooltip_text = "Undo selects"
        btn_undo_sel.focus_mode = Control.FOCUS_NONE
        btn_undo_sel.custom_minimum_size = Vector2(0, 30)
        btn_undo_sel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        btn_undo_sel.add_theme_font_size_override("font_size", 14)
        reset_row.add_child(btn_undo_sel)

        var btn_undo_block := Button.new()
        btn_undo_block.text = "Undo ✕"
        btn_undo_block.tooltip_text = "Undo blocks"
        btn_undo_block.focus_mode = Control.FOCUS_NONE
        btn_undo_block.custom_minimum_size = Vector2(0, 30)
        btn_undo_block.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        btn_undo_block.add_theme_font_size_override("font_size", 14)
        reset_row.add_child(btn_undo_block)

        var btn_undo_all := Button.new()
        btn_undo_all.text = "Undo all"
        btn_undo_all.focus_mode = Control.FOCUS_NONE
        btn_undo_all.custom_minimum_size = Vector2(0, 30)
        btn_undo_all.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        btn_undo_all.add_theme_font_size_override("font_size", 14)
        reset_row.add_child(btn_undo_all)

        var si_reset := i
        btn_undo_sel.pressed.connect(func(): _on_undo_name_selects(si_reset))
        btn_undo_block.pressed.connect(func(): _on_undo_name_blocks(si_reset))
        btn_undo_all.pressed.connect(func(): _on_undo_name_all(si_reset))

        # COPY, for this row's Name section — same button as the Sort:tab
        # Name row's checklist popup, placed here since the star-map
        # widget shows the Name checklist inline instead of behind a
        # popup trigger.
        var name_copy_btn := Button.new()
        name_copy_btn.text = "⎘"
        name_copy_btn.custom_minimum_size = Vector2(26, 30)
        name_copy_btn.focus_mode = Control.FOCUS_NONE
        name_copy_btn.tooltip_text = "Write the still-possible names into the Notes tab"
        var name_copy_rec := existing_record
        name_copy_btn.pressed.connect(func(): _on_staff_copy(name_copy_rec, "name"))
        reset_row.add_child(name_copy_btn)

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
                    name_lbl.add_theme_font_size_override("font_size", 19)
                    name_lbl.add_theme_color_override("font_color", star_color)
                    name_lbl.clip_text = true
                    row.add_child(name_lbl)

                    var btn_check := Button.new()
                    btn_check.text = "✓"
                    btn_check.custom_minimum_size = Vector2(28, 26)
                    btn_check.focus_mode = Control.FOCUS_NONE
                    btn_check.add_theme_font_size_override("font_size", 18)
                    row.add_child(btn_check)

                    var btn_x := Button.new()
                    btn_x.text = "✗"
                    btn_x.custom_minimum_size = Vector2(28, 26)
                    btn_x.focus_mode = Control.FOCUS_NONE
                    btn_x.add_theme_font_size_override("font_size", 18)
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
    if star_idx >= 0 and star_idx < _host._sequence_rank_solution.size():
        return _host._sequence_rank_solution[star_idx] + 1
    return star_idx + 1


func _confirmed_sequence_str(star_idx: int) -> String:
    if star_idx < 0:
        return "?"
    var idx: int = _deduction._find_match_record_by_star_idx(star_idx)
    if idx < 0:
        return "?"
    # EFFECTIVE bounds, matching what the Sort rows render — reading raw
    # seq_lo/seq_hi let a position that is pinned only through derived
    # narrowing show as "?" on the tag while the row beside it showed the
    # number. Same raw-vs-effective split as the colour and pitch readers.
    var bounds: Array = _deduction._effective_seq_bounds(idx)
    var lo_i: int = int(bounds[0])
    var hi_i: int = int(bounds[1])
    if lo_i > 0 and lo_i == hi_i:
        return str(lo_i)
    return "?"


func _confirmed_pitch_str_for_star(star_idx: int) -> String:
    if star_idx < 0:
        return "?"
    var idx: int = _deduction._find_match_record_by_star_idx(star_idx)
    if idx < 0:
        return "?"
    # Shared displayable-pitch guard rather than a raw pitch_states scan: a
    # Listen-revealed note lives in ground truth via star_idx and never
    # enters that dict, so star tags showed "?" for pitches the player had
    # already earned — while the guard still refuses to read ground truth
    # off an un-listened stub.
    var note: String = _deduction._displayable_pitch_for_record(idx)
    return note if note != "" else "?"


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
    if _note_name_cache.has(star_idx):
        return str(_note_name_cache[star_idx])
    if star_idx < 0 or star_idx >= _host._star_pitch_index.size():
        return "?"
    var p: int = _host._star_pitch_index[star_idx]
    if p < 0 or p >= _host._pitch_freqs.size():
        return "?"
    var n: String = ConstellationLogicPuzzle.note_name_for_freq(_host._pitch_freqs[p])
    _note_name_cache[star_idx] = n
    return n


# Both of these are pure functions of _pitch_freqs / _star_pitch_index,
# which change only when a puzzle is loaded — but they were being recomputed
# inside nested per-record loops. _distinct_note_names() in particular is
# called from _records_provably_identical(), i.e. once per record PAIR, and
# each call re-deduped, re-sorted, and re-ran note_name_for_freq() over the
# whole table. Together with _note_name_for_star()'s own repeated
# frequency->name conversion this was the multi-second stall on sequence
# entry. Cleared by clear_pitch_caches() from _load_constellation_data().
var _distinct_notes_cache: Array[String] = []
var _note_name_cache: Dictionary = {}


func clear_pitch_caches() -> void:
    _distinct_notes_cache = []
    _note_name_cache.clear()


## Widget-side state that belongs to ONE puzzle and must not survive a
## constellation switch. Kept separate from clear_pitch_caches() on purpose:
## that one drops memoised lookups (a correctness-of-derivation concern),
## this one drops player-facing selections. Called from
## _load_constellation_data() alongside it — see the note there for why a
## reused overlay node makes this necessary.
##
## _search_term is a term picked from the PREVIOUS puzzle's vocabulary.
## Carried over, the SEARCH tab headers itself "Clues mentioning <term>" and
## lists nothing — or, when the two constellations happen to share a name,
## lists results that look legitimate and are not.
func clear_per_puzzle_ui_state() -> void:
    _search_term = ""


func _distinct_note_names() -> Array[String]:
    if not _distinct_notes_cache.is_empty():
        return _distinct_notes_cache
    var uniq_freqs: Array = []
    for f in _host._pitch_freqs:
        if not uniq_freqs.has(f):
            uniq_freqs.append(f)
    uniq_freqs.sort()
    var names: Array[String] = []
    for f in uniq_freqs:
        names.append(ConstellationLogicPuzzle.note_name_for_freq(f))
    _distinct_notes_cache = names
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
    # EFFECTIVE identity, not the star-widget record's raw `name` field —
    # the same raw-vs-effective split the Sequence and Colour/Pitch readers
    # beside this one already make, and which Name never got.
    #
    # Reported 2026-08-14: deducing Chroneeia as a specific blue C5 star
    # showed its Sequence and Pitch on the star tag but left the Name blank,
    # because those two read through _effective_seq_bounds /
    # _displayable_pitch_for_record while this read one dictionary field.
    #
    # It only became visible when eceea49 stopped folding an inferred
    # identity into the star-widget stub: before that, the merge wrote the
    # name into the stub's own field and this reader happened to find it.
    # The reader was always wrong; the merge was hiding it.
    #
    # _records_bound_to_star is the LOCATED tier — records whose effective
    # star_idx is this star, with auto-created stubs filtered out — so a
    # bare stub contributes nothing and no un-earned name can leak here.
    for i in _deduction._records_bound_to_star(star_idx):
        var nm: String = str(_deduction.record_at(int(i)).get("name", ""))
        if nm != "":
            return nm
    return ""


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
    if _star_tags_dirty:
        return   # see the coalescing note above _build_star_widgets()
    _star_tags_dirty = true
    call_deferred("_build_star_tags_impl")


func _build_star_tags_impl() -> void:
    _star_tags_dirty = false
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

        # THREE DIRECT CHILDREN, no layout container. The tags used to be a
        # VBox (stacked) plus an HBox (inline) with one of the two shown
        # depending on which fit — a layout container positions its own
        # children, which made per-label placement impossible. The
        # triangular formation needs each label placed independently, and
        # the de-overlap pass needs to move them independently, so both
        # containers are gone and _reposition_star_tags() sets all three
        # positions itself.
        #
        # `root` stays at the origin and each label carries an absolute
        # map-space position, so a label's position IS its rect origin —
        # no parent-offset arithmetic anywhere in the collision code.
        root.position = Vector2.ZERO

        var name_str: String = _confirmed_name_for_star(i)
        if name_str == "":
            name_str = "?"
        var seq_str: String = _confirmed_sequence_str(i)
        var pitch_str: String = _confirmed_pitch_str_for_star(i)

        var name_lbl := Label.new()
        name_lbl.name = "NameLabel"
        name_lbl.text = name_str
        name_lbl.add_theme_font_size_override("font_size", 19)
        name_lbl.add_theme_color_override("font_color", star_color)
        name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

        var seq_lbl := Label.new()
        seq_lbl.name = "SeqLabel"
        seq_lbl.text = "%s" % _ordinal_str(seq_str)
        seq_lbl.add_theme_font_size_override("font_size", 19)
        seq_lbl.add_theme_color_override("font_color", Color(star_color.r, star_color.g, star_color.b, 0.75))
        seq_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

        var pitch_lbl := Label.new()
        pitch_lbl.name = "PitchLabel"
        pitch_lbl.text = pitch_str
        pitch_lbl.add_theme_font_size_override("font_size", 19)
        pitch_lbl.add_theme_color_override("font_color", Color(star_color.r, star_color.g, star_color.b, 0.75))
        pitch_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

        # Order is load-bearing: _reposition_star_tags() reads them back by
        # index (0 Name, 1 Sequence, 2 Pitch) to place the triangle.
        root.add_child(name_lbl)
        root.add_child(seq_lbl)
        root.add_child(pitch_lbl)

    _reposition_star_tags()


# ==================================================
# STAR TAG PLACEMENT — triangular formation + de-overlap
# ==================================================
# Each star's three on-map labels sit in a triangle around its dot: Name
# and Sequence stacked on the LEFT (the base), Pitch alone on the RIGHT
# (the vertex). Name and Sequence are the two HIDDEN axes — the ones the
# player is actually solving — so grouping them opposite the Listen-
# revealed Pitch matches how the information is used, not just how it fits.
#
# Replaces a VBox-stack-with-inline-fallback. That arrangement only ever
# checked the MAP edges, never other stars, so neighbouring tags could and
# did overlap each other. Spreading each star's labels wider makes that
# strictly more likely, so the separation pass below is not a nicety here —
# it is what makes the triangle usable at all.

## Desired triangle geometry, before any separation nudging.
const TAG_TRI_GAP_X: float = 13.0   # px from dot centre to a label's near edge
const TAG_TRI_GAP_Y: float = 3.0    # px from dot centre to each base label

## Separation pass tuning. Runs on rebuild and on resize only — never per
## frame — so the O(labels^2) sweep is affordable at 3 labels x star_count.
const TAG_SEPARATION_PASSES: int = 12
## How far a label may be pushed from where its triangle wanted it. Without
## a cap, a dense cluster can shove a label most of the way across the map,
## and a tag far from its own star is worse than a tag slightly overlapping
## one — it reads as belonging to the wrong star. Dense clusters therefore
## resolve as "spread as far as the cap allows", which may leave a little
## residual overlap; that is the deliberate trade, not a failure.
const TAG_MAX_NUDGE: float = 34.0


func _reposition_star_tags() -> void:
    var map_w: float = _host._star_map_control.size.x
    var map_h: float = _host._star_map_control.size.y

    # Phase 1 — lay out each star's triangle independently.
    var placed: Array = []      # {label:Label, rect:Rect2, home:Vector2}
    for i in _host._star_tags.size():
        if i >= _host._star_screen_pos.size():
            break
        var root: Control = _host._star_tags[i]
        if not is_instance_valid(root):
            continue
        # Same defensive read as before: a direct typed assignment from
        # get_child() HANGS the engine (not a catchable error) if the
        # structure ever changes, so `as` + null-check degrades to skipping
        # this tag instead. Now three Labels rather than a VBox + HBox.
        if root.get_child_count() < 3:
            continue
        var name_lbl: Label = root.get_child(0) as Label
        var seq_lbl: Label = root.get_child(1) as Label
        var pitch_lbl: Label = root.get_child(2) as Label
        if not name_lbl or not seq_lbl or not pitch_lbl:
            continue

        root.position = Vector2.ZERO
        var dot: Vector2 = _host._star_screen_pos[i]
        for lbl in [name_lbl, seq_lbl, pitch_lbl]:
            (lbl as Label).visible = true
            (lbl as Label).reset_size()

        var n_sz: Vector2 = name_lbl.get_combined_minimum_size()
        var s_sz: Vector2 = seq_lbl.get_combined_minimum_size()
        var p_sz: Vector2 = pitch_lbl.get_combined_minimum_size()

        # Base: right-aligned against a shared edge left of the dot, one
        # above and one below. Vertex: left edge right of the dot, centred.
        var base_right: float = dot.x - TAG_TRI_GAP_X
        _tag_place(placed, name_lbl,
            Vector2(base_right - n_sz.x, dot.y - TAG_TRI_GAP_Y - n_sz.y), n_sz, map_w, map_h)
        _tag_place(placed, seq_lbl,
            Vector2(base_right - s_sz.x, dot.y + TAG_TRI_GAP_Y), s_sz, map_w, map_h)
        _tag_place(placed, pitch_lbl,
            Vector2(dot.x + TAG_TRI_GAP_X, dot.y - p_sz.y * 0.5), p_sz, map_w, map_h)

    # Phase 2 — push apart anything that collides, then commit.
    _separate_tag_rects(placed, map_w, map_h)
    for e in placed:
        (e["label"] as Label).position = (e["rect"] as Rect2).position


## Clamp a label's desired rect inside the map and record it for phase 2.
func _tag_place(placed: Array, lbl: Label, pos: Vector2, size: Vector2,
        map_w: float, map_h: float) -> void:
    var r := Rect2(_tag_clamp(pos, size, map_w, map_h), size)
    placed.append({"label": lbl, "rect": r, "home": r.position})


func _tag_clamp(pos: Vector2, size: Vector2, map_w: float, map_h: float) -> Vector2:
    return Vector2(
        clampf(pos.x, 0.0, maxf(0.0, map_w - size.x)),
        clampf(pos.y, 0.0, maxf(0.0, map_h - size.y)))


## Iterative pairwise separation: push overlapping rects apart along their
## SHALLOWER axis (the minimum-translation direction), which keeps a label
## near its star rather than flinging it out along the long axis of an
## overlap. Each rect is re-clamped to the map and to TAG_MAX_NUDGE from
## where its triangle put it, so a label can never leave the map or drift
## far enough to look like it belongs to a different star.
func _separate_tag_rects(placed: Array, map_w: float, map_h: float) -> void:
    for _pass in TAG_SEPARATION_PASSES:
        var moved: bool = false
        for a in range(placed.size()):
            for b in range(a + 1, placed.size()):
                var ra: Rect2 = placed[a]["rect"]
                var rb: Rect2 = placed[b]["rect"]
                if not ra.intersects(rb):
                    continue
                var inter: Rect2 = ra.intersection(rb)
                if inter.size.x <= 0.0 or inter.size.y <= 0.0:
                    continue
                # +0.5 so a resolved pair ends genuinely apart rather than
                # exactly touching, which would re-trigger next pass.
                if inter.size.x <= inter.size.y:
                    var dx: float = inter.size.x * 0.5 + 0.5
                    if ra.get_center().x <= rb.get_center().x:
                        ra.position.x -= dx
                        rb.position.x += dx
                    else:
                        ra.position.x += dx
                        rb.position.x -= dx
                else:
                    var dy: float = inter.size.y * 0.5 + 0.5
                    if ra.get_center().y <= rb.get_center().y:
                        ra.position.y -= dy
                        rb.position.y += dy
                    else:
                        ra.position.y += dy
                        rb.position.y -= dy
                ra.position = _tag_leash(ra.position, placed[a]["home"], ra.size, map_w, map_h)
                rb.position = _tag_leash(rb.position, placed[b]["home"], rb.size, map_w, map_h)
                placed[a]["rect"] = ra
                placed[b]["rect"] = rb
                moved = true
        if not moved:
            return   # settled early; nothing left overlapping


## Clamp to the map AND to TAG_MAX_NUDGE of the label's home position.
func _tag_leash(pos: Vector2, home: Vector2, size: Vector2,
        map_w: float, map_h: float) -> Vector2:
    var off: Vector2 = pos - home
    if off.length() > TAG_MAX_NUDGE:
        pos = home + off.normalized() * TAG_MAX_NUDGE
    return _tag_clamp(pos, size, map_w, map_h)


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
            # Was this exact literal; now the shared palette entry, so the
            # popup rows and this list cannot drift apart again.
            name_lbl.add_theme_color_override("font_color", STATE_COLORS.eliminated_label)
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
            var existing_star: int = int(_deduction.record_at(name_record).get("star_idx", -1))
            if existing_star >= 0 and existing_star != star_idx:
                _apply_name_row_visual(2, name_lbl, btn_check, btn_x, star_color)
                return
        var record_idx: int = _deduction._get_or_create_match_record_for_name(star_name)
        record_idx = await _deduction._confirm_match_record_identity(record_idx, star_idx, star_name)
        if record_idx < 0:
            _apply_name_row_visual(_deduction._star_elim_state(star_idx, star_name), name_lbl, btn_check, btn_x, star_color)
            return
        var resolved_name: String = str(_deduction.record_at(record_idx)["name"])
        _deduction._propagate_name_confirmed(star_idx, resolved_name)
        _deduction._save_puzzle_notes()
        _deduction._full_propagation_refresh()
        return

    var record_idx2: int = _deduction._get_or_create_match_record_for_name(star_name)
    var elim2: Dictionary = _deduction.record_at(record_idx2).get("star_elim", {})
    elim2[star_idx] = new_state
    _deduction.record_at(record_idx2)["star_elim"] = elim2
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
    var elim: Dictionary = _deduction.record_at(record_idx).get("star_elim", {})
    elim[star_idx] = new_state
    _deduction.record_at(record_idx)["star_elim"] = elim
    _apply_name_row_visual(new_state, name_lbl, btn_check, btn_x, star_color)

    _deduction._set_star_name_user_blocked(star_idx, star_name, new_state == 2)

    _deduction._save_puzzle_notes()
    _deduction._full_propagation_refresh()


# ==================================================
# UNDO NAME-SELECTION/NAME-BLOCK CALLBACKS
# ==================================================
func _on_undo_name_selects(star_idx: int) -> void:
    var own_record: int = _deduction._find_match_record_by_star_idx(star_idx)
    if own_record >= 0:
        var r: Dictionary = _deduction.record_at(own_record)
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
    for i in _deduction.record_count():
        if i == own_record:
            continue
        var other: Dictionary = _deduction.record_at(i)
        var other_star: int = int(other.get("star_idx", -1))
        if other_star >= 0 and other_star != star_idx:
            continue
        var other_name: String = str(other.get("name", ""))
        if _deduction._is_star_name_user_blocked(star_idx, other_name):
            continue
        var elim2: Dictionary = other.get("star_elim", {})
        if int(elim2.get(star_idx, 0)) == 2:
            elim2.erase(star_idx)
            other["star_elim"] = elim2
    _deduction._clear_protected_names_for_star(star_idx)
    _deduction._save_puzzle_notes()
    _deduction._full_propagation_refresh()


func _on_undo_name_blocks(star_idx: int) -> void:
    for name_str in _deduction._user_blocked_names_for_star(star_idx):
        var rec: int = _deduction._find_match_record_by_name(name_str)
        if rec >= 0:
            var elim: Dictionary = _deduction.record_at(rec).get("star_elim", {})
            if elim.has(star_idx):
                elim.erase(star_idx)
                _deduction.record_at(rec)["star_elim"] = elim
    _deduction._clear_star_name_user_blocks(star_idx)
    _deduction._save_puzzle_notes()
    _deduction._full_propagation_refresh()


func _on_undo_name_all(star_idx: int) -> void:
    var own_record: int = _deduction._find_match_record_by_star_idx(star_idx)
    if own_record >= 0:
        var r: Dictionary = _deduction.record_at(own_record)
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
    for i in _deduction.record_count():
        if i == own_record:
            continue
        var other: Dictionary = _deduction.record_at(i)
        var other_star: int = int(other.get("star_idx", -1))
        if other_star >= 0 and other_star != star_idx:
            continue
        var elim2: Dictionary = other.get("star_elim", {})
        if elim2.has(star_idx):
            elim2.erase(star_idx)
            other["star_elim"] = elim2

    _deduction._clear_protected_names_for_star(star_idx)

    _deduction._clear_star_name_user_blocks(star_idx)

    _deduction._save_puzzle_notes()
    _deduction._full_propagation_refresh()


func _on_name_protect_toggle(star_idx: int, star_name: String) -> void:
    var base: int = _deduction._star_elim_state(star_idx, star_name)
    if base != 0:
        return   # already hard-confirmed or hard-eliminated; right-click no-ops
    _deduction._set_name_protected(
        star_idx, star_name, not _deduction._is_name_protected(star_idx, star_name))
    _deduction._save_puzzle_notes()
    _deduction._full_propagation_refresh()
