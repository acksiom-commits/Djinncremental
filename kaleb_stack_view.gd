extends PanelContainer
## Kaleb's command stack, shown in the Journal slideout's **Commands** tab on
## Primordial (journal_popout.gd set_commands_view(); SysDoc §7.3). It first
## sat in the Constellation box; the author moved it here, 2026-11-05.
##
##   header   Run/Pause (GameContext.kaleb_running), Restart (back to bar 1,
##            GameContext.kaleb_restart()), Crew and "+ Command", the palette
##            (kaleb_commands.gd)
##   slots    the shown slot's state, Stack 1 2 3, Save and Load. Each slot is
##            its own stack (author, 2026-11-06): picking one SHOWS it here to
##            edit. The live slot's stack is the one Kaleb runs and the only
##            one holding Uonites and Foci; Run on another slot makes that one
##            live and stops the old. Save / Load copy the shown slot's stack
##            to / from its base (GameContext.kaleb_saved_stacks).
## Every action below acts on the SHOWN slot (_stack_slot).
##   list     one row per bar, top to bottom: its number (drag handle), On/Off
##            (its Focus switching its workers), its name (drag handle), its
##            own settings, and × to remove it (returning its workers and
##            Focus). A press bar's − nU+mF + sets its workers, Uonites or,
##            when none is free, Foci: each press makes n+m times as much.
##   footer   the Persistent stocks, or why a bar couldn't be added
##
## Reordering is drag and drop: drag a bar by its number or name onto another
## bar's row and it takes that slot (GameContext.kaleb_move_bar).
##
## Rows are rebuilt only when the stack's shape changes (bars added, removed,
## moved, or a load); each frame only the lit row, counts and Run/Pause are
## refreshed, so typing in a row's number box isn't interrupted.

const KC = preload("res://kaleb_commands.gd")

const FONT_SIZE: int = 14
const ROW_H: float = 24.0
const BG := Color(0.06, 0.05, 0.10, 0.94)
const ROW_BG := Color(0.12, 0.10, 0.20, 0.85)
const ROW_CURRENT := Color(0.30, 0.24, 0.52, 0.95)
const ROW_OFF := Color(0.08, 0.07, 0.12, 0.85)
const TEXT := Color(0.92, 0.88, 0.78)
const TEXT_DIM := Color(0.55, 0.52, 0.62)
const GOLD := Color(1.0, 0.85, 0.2)
const UONITE := Color(1.0, 0.87, 0.33)   # game_data's Uonite colour
const LIVE := Color(0.55, 1.0, 0.6)       # the live (running/paused) slot
## The Uonite − and + repeat while held, like the wheel's Uonite buttons.
var _hold = preload("res://hold_repeat.gd").new()
## The palette's order.
const PALETTE: Array[String] = ["summon_spark", "monad_compress", "tetrad_assemble",
    "persistent_particle", "persistent_iota", "persistent_mote", "persistent_grain",
    "lock", "unlock", "if", "supply_sparks", "feed_endow", "feed_ignore"]
## What an If bar can count, in its menu's order.
const IF_KEYS: Array[String] = ["sparks", "monad", "tetrad", "monad_solid", "monad_liquid", "monad_gas",
    "adaemant", "aquae", "aethyr", "earth", "water", "air", "mud", "dust", "cloud",
    "silt", "sand", "haze", "mist", "ooze", "foam", "particle",
    "persistent_particle", "persistent_iota", "persistent_mote", "persistent_grain"]

var gc: Node = null
var gd: Node = null

var _run_btn: Button
var _restart_btn: Button
var _crew_lbl: Label
# Stack slots row (_build_slot_row())
var _slot_btns: Array = []
var _slot_status: Label
var _save_btn: Button
var _load_btn: Button
var _stack_slot: int = 0          # the chosen slot, 0-based
var _confirming: String = ""      # "save" or "load" while its button asks
var _confirm_until: float = 0.0
var _add_btn: MenuButton
var _list: VBoxContainer
var _scroll: ScrollContainer
var _footer: Label
var _rows: Array = []          # one Dictionary per bar: {panel, num, progress, bar}
var _built: Array = []         # the bars the rows were built from, in order
var _built_once: bool = false
var _built_slot: int = -1      # the slot the rows were built from
var _note: String = ""         # a message for the footer
var _note_until: float = 0.0


func setup(game_context: Node) -> void:
    gc = game_context


func _ready() -> void:
    gd = get_node_or_null("/root/GameData")
    var bg := StyleBoxFlat.new()
    bg.bg_color = BG
    bg.set_content_margin_all(4)
    add_theme_stylebox_override("panel", bg)
    mouse_filter = Control.MOUSE_FILTER_STOP
    clip_contents = true

    var col := VBoxContainer.new()
    col.add_theme_constant_override("separation", 3)
    add_child(col)

    var head := HBoxContainer.new()
    col.add_child(head)
    _run_btn = _small_button("Run")
    _run_btn.custom_minimum_size = Vector2(60, 0)
    _run_btn.pressed.connect(_on_run_pressed)
    head.add_child(_run_btn)
    _restart_btn = _small_button("Restart")
    _restart_btn.tooltip_text = "Send Kaleb back to bar 1 (running or paused stays as it is)"
    _restart_btn.pressed.connect(gc.kaleb_restart)
    head.add_child(_restart_btn)
    # No title: the Journal's tab already says Commands, and the Crew control
    # needs the room (2026-11-06).
    var gap := Control.new()
    gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
    head.add_child(gap)
    # The crew (author, 2026-11-06): one set of workers Kaleb takes from bar
    # to bar. + takes a free Uonite, else a free Focus; − gives a Focus back
    # first. Hold-repeat, like the wheel's Uonite buttons.
    head.add_child(_label("Crew", TEXT_DIM))
    var crew_minus := _small_button("−")
    crew_minus.custom_minimum_size = Vector2(20, 0)
    crew_minus.tooltip_text = "Shrink the crew (a Focus goes back first, then a Uonite)"
    _hold.connect_button(crew_minus, func() -> void: gc.kaleb_change_crew(-1, _stack_slot))
    head.add_child(crew_minus)
    _crew_lbl = _label("", UONITE)
    _crew_lbl.custom_minimum_size = Vector2(56, 0)
    _crew_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    head.add_child(_crew_lbl)
    var crew_plus := _small_button("+")
    crew_plus.custom_minimum_size = Vector2(20, 0)
    crew_plus.tooltip_text = "Grow the crew: a free Uonite, or a Focus when none is free"
    _hold.connect_button(crew_plus, func() -> void:
        if not gc.kaleb_change_crew(1, _stack_slot):
            _say("No free Uonite or Focus for the crew"))
    head.add_child(crew_plus)
    _add_btn = MenuButton.new()
    _add_btn.text = "+ Command"
    _add_btn.flat = false
    _add_btn.add_theme_font_size_override("font_size", FONT_SIZE)
    _compact(_add_btn)
    var pop: PopupMenu = _add_btn.get_popup()
    pop.add_theme_font_size_override("font_size", FONT_SIZE + 1)
    for i in PALETTE.size():
        pop.add_item(KC.COMMANDS[PALETTE[i]]["name"], i)
    pop.id_pressed.connect(_on_add_chosen)
    head.add_child(_add_btn)
    col.add_child(_build_slot_row())

    _scroll = ScrollContainer.new()
    _scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
    _scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
    col.add_child(_scroll)
    _list = VBoxContainer.new()
    _list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    _list.add_theme_constant_override("separation", 2)
    _scroll.add_child(_list)

    _footer = _label("", TEXT_DIM)
    _footer.add_theme_font_size_override("font_size", FONT_SIZE - 1)
    _footer.clip_text = true
    col.add_child(_footer)


func _process(delta: float) -> void:
    if gc == null or not is_visible_in_tree():
        return
    if not _built_once:
        _stack_slot = gc.kaleb_live_slot   # first shown: the live slot
    if _stack_changed():
        _rebuild()
    _refresh()
    _hold.tick(delta)


## The shown slot's bars.
func _bars() -> Array:
    return gc.kaleb_bars(_stack_slot)


func _shows_live() -> bool:
    return gc.kaleb_is_live(_stack_slot)


## Whether the bars, in order, are no longer the ones the rows were built
## from. Bars are Dictionaries, shared by reference, so this compares
## identity: a move, an add, a remove, a load or another slot shown all show
## up, an edit to a bar's settings doesn't.
func _stack_changed() -> bool:
    var bars: Array = _bars()
    if not _built_once or _built_slot != _stack_slot or _built.size() != bars.size():
        return true
    for i in _built.size():
        if not is_same(_built[i], bars[i]):
            return true
    return false


# ==================================================
# ROWS
# ==================================================
func _rebuild() -> void:
    var bars: Array = _bars()
    _built = bars.duplicate()   # shallow: the same bar Dictionaries
    _built_slot = _stack_slot
    _built_once = true
    for c in _list.get_children():
        c.queue_free()
    _rows.clear()
    for i in bars.size():
        _rows.append(_build_row(i))
    if bars.is_empty():
        var hint := _label("No commands yet: add one with + Command.", TEXT_DIM)
        _list.add_child(hint)


func _build_row(i: int) -> Dictionary:
    var bar: Dictionary = _bars()[i]
    var def: Dictionary = KC.COMMANDS.get(String(bar["cmd"]), {})
    var panel := PanelContainer.new()
    panel.custom_minimum_size = Vector2(0, ROW_H)
    panel.mouse_filter = Control.MOUSE_FILTER_PASS
    panel.set_drag_forwarding(Callable(), _can_drop.bind(i), _drop.bind(i))
    _list.add_child(panel)
    var row := HBoxContainer.new()
    row.add_theme_constant_override("separation", 3)
    panel.add_child(row)

    var num := _label("%d" % (i + 1), TEXT_DIM)
    num.custom_minimum_size = Vector2(18, 0)
    num.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
    _make_handle(num, i)
    row.add_child(num)

    var on_btn := _small_button("On" if bool(bar["on"]) else "Off")
    on_btn.toggle_mode = true
    on_btn.button_pressed = bool(bar["on"])
    on_btn.custom_minimum_size = Vector2(34, 0)
    on_btn.tooltip_text = "This bar's Focus switches its Uonite On and Off"
    on_btn.toggled.connect(func(pressed: bool) -> void:
        bar["on"] = pressed
        on_btn.text = "On" if pressed else "Off")
    row.add_child(on_btn)

    var name_lbl := _label(String(def.get("name", bar["cmd"])), TEXT)
    name_lbl.clip_text = true
    name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    name_lbl.tooltip_text = "Drag to move this command"
    _make_handle(name_lbl, i)
    row.add_child(name_lbl)

    var progress := _label("", GOLD)
    var u_lbl: Label = null
    match String(def.get("kind", "")):
        "press":
            name_lbl.text = String(def.get("name", bar["cmd"]))
            u_lbl = _add_worker_controls(row, bar)
            progress.text = "×"
            row.add_child(progress)
            row.add_child(_num_edit(bar, "repeat", 1, 999, 0, 48))
        "supply":
            # Supply Sparks into one Constellation; only the crew's Foci
            # work on it (author, 2026-11-06).
            row.add_child(_constellation_option(bar, 96, true))
            u_lbl = _add_worker_controls(row, bar)
            progress.text = "×"
            row.add_child(progress)
            row.add_child(_num_edit(bar, "repeat", 1, 999, 0, 48))
        "feed":
            row.add_child(_constellation_option(bar, 200))
        "lock", "unlock":
            row.add_child(_option(bar, "target", gc.locks.keys(), 170))
        "if":
            row.add_child(_option(bar, "res", IF_KEYS, 160))
            row.add_child(_option(bar, "cmp", KC.COMPARISONS, 50))
            row.add_child(_num_edit(bar, "value", 0, 99999, 0, 60))
            row.add_child(_label("→#", TEXT_DIM))
            var goto := _num_edit(bar, "goto", 1, 999, -1, 40)
            goto.tooltip_text = "If true, go to this bar"
            row.add_child(goto)

    var del := _small_button("×")
    del.custom_minimum_size = Vector2(20, 0)
    del.tooltip_text = "Remove (returns its On/Off Focus)"
    del.pressed.connect(func() -> void:
        gc.kaleb_remove_bar(_index_of(bar), _stack_slot))
    row.add_child(del)
    return {"panel": panel, "num": num, "progress": progress, "bar": bar, "name": name_lbl, "uonites": u_lbl}


## A working bar's − n +: how many of the crew it uses, each one more
## multiplying what a press makes. Free to change; the crew is already held.
## Returns the count label, refreshed each frame by _refresh().
func _add_worker_controls(row: HBoxContainer, bar: Dictionary) -> Label:
    var foci_only: bool = String(bar.get("cmd", "")) == "supply_sparks"
    var minus := _small_button("−")
    minus.custom_minimum_size = Vector2(20, 0)
    minus.tooltip_text = "Use one fewer of the crew"
    _hold.connect_button(minus, func() -> void: gc.kaleb_change_bar_workers(bar, -1, _stack_slot))
    row.add_child(minus)
    var lbl := _label("", UONITE)
    lbl.custom_minimum_size = Vector2(34, 0)
    lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    row.add_child(lbl)
    var plus := _small_button("+")
    plus.custom_minimum_size = Vector2(20, 0)
    plus.tooltip_text = ("Use one more of the crew's Foci (only Foci work in Constellations)" if foci_only
        else "Use one more of the crew (up to its size; grow the crew in the header)")
    _hold.connect_button(plus, func() -> void:
        if not gc.kaleb_change_bar_workers(bar, 1, _stack_slot):
            _say("It already uses the whole crew of %d" % gc.kaleb_slot_crew(_stack_slot)))
    row.add_child(plus)
    return lbl


## The unlocked Constellations, for an Endow / Ignore / Supply bar's
## target (its id, kept as a String like a Lock bar's key).
## `short` shows designations only ("ALZIRO"), for a row with little room;
## the tooltip always has the full name.
func _constellation_option(bar: Dictionary, width: float, short: bool = false) -> OptionButton:
    var cd: Node = get_node_or_null("/root/ConstellationData")
    var ids: Array = cd.unlocked.duplicate() if cd else []
    ids.sort()
    var keys: Array = []
    var labels: Array = []
    for id in ids:
        keys.append(str(id))
        labels.append(KC.constellation_name(int(id), gc, cd, short))
    if keys.is_empty():
        keys = ["0"]
        labels = [KC.constellation_name(0, gc, cd, short)]
    var o := _option(bar, "target", keys, width, labels)
    var name_now := func() -> String: return KC.constellation_name(String(bar["target"]).to_int(), gc, cd)
    o.tooltip_text = name_now.call()
    o.item_selected.connect(func(_j: int) -> void: o.tooltip_text = name_now.call())
    return o


var _row_styles: Dictionary = {}

## The row background for `col`, made once and reused every frame.
func _row_style(col: Color) -> StyleBoxFlat:
    if not _row_styles.has(col):
        var sb := StyleBoxFlat.new()
        sb.bg_color = col
        sb.set_corner_radius_all(3)
        sb.set_content_margin_all(2)
        _row_styles[col] = sb
    return _row_styles[col]


## Each frame: the lit row, its count so far, Off rows dimmed, Run/Pause, the footer.
func _refresh() -> void:
    var live: bool = _shows_live()
    var bars: Array = _bars()
    # Run/Pause works the live stack; on another slot, Run makes that slot
    # live and stops the old one (gc.kaleb_run_slot()).
    _run_btn.text = "Pause" if live and gc.kaleb_running else "Run"
    _run_btn.disabled = bars.is_empty()
    _run_btn.tooltip_text = "Run this stack" if live else \
        "Run Slot %d's stack instead: Slot %d stops, and this one takes its Foci and crew" % [
            _stack_slot + 1, gc.kaleb_live_slot + 1]
    _restart_btn.disabled = not live or (gc.kaleb_index == 0 and gc.kaleb_repeat_done == 0)
    _refresh_slot_row()
    if live:
        var cu: int = gc.kaleb_crew_uonites
        var cf: int = gc.kaleb_crew_foci
        _crew_lbl.text = ("%dU" % cu) if cf == 0 else (("%dF" % cf) if cu == 0 else "%dU+%dF" % [cu, cf])
        _crew_lbl.add_theme_color_override("font_color", UONITE if cu + cf > 0 else TEXT_DIM)
        _crew_lbl.tooltip_text = "Kaleb's crew: %d Uonite%s and %d Focus worker%s, taken from bar to bar" % [
            cu, "" if cu == 1 else "s", cf, "" if cf == 1 else "s"]
    else:
        var planned: int = gc.kaleb_slot_crew(_stack_slot)
        _crew_lbl.text = "%d" % planned
        _crew_lbl.add_theme_color_override("font_color", TEXT if planned > 0 else TEXT_DIM)
        _crew_lbl.tooltip_text = "The crew this stack takes when it runs: %d, Uonites first, then Foci" % planned
    for i in _rows.size():
        var r: Dictionary = _rows[i]
        var bar: Dictionary = r["bar"]
        var current: bool = live and i == gc.kaleb_index and not bars.is_empty()
        var style: StyleBoxFlat = _row_style(ROW_CURRENT if current else (ROW_BG if bool(bar["on"]) else ROW_OFF))
        (r["panel"] as PanelContainer).add_theme_stylebox_override("panel", style)
        (r["num"] as Label).text = ("▶" if current and gc.kaleb_running else "%d" % (i + 1))
        (r["name"] as Label).add_theme_color_override("font_color", TEXT if bool(bar["on"]) else TEXT_DIM)
        if r["uonites"]:
            # A plan's split of Uonites and Foci isn't known until it runs.
            var n: int = gc.kaleb_bar_workers(bar) if live \
                else mini(gc.kaleb_bar_count(bar), gc.kaleb_slot_crew(_stack_slot))
            var wl: Label = r["uonites"]
            wl.text = "%d" % n
            wl.add_theme_color_override("font_color", UONITE if n > 0 else TEXT_DIM)
            var foci_only: bool = String(bar["cmd"]) == "supply_sparks"
            if foci_only:
                wl.tooltip_text = "Uses %d of the crew's %d Foci (only Foci work in Constellations): each press sends %d times as many Sparks" % [
                    n, gc.kaleb_crew_foci, n]
            else:
                wl.tooltip_text = "Uses %d of the crew's %d: each press makes %d times as much" % [
                    n, gc.kaleb_slot_crew(_stack_slot), n]
        # A press bar's "×N" reads "k/N" while Kaleb is on it.
        var prog: Label = r["progress"]
        if KC.COMMANDS.get(String(bar["cmd"]), {}).get("kind", "") in ["press", "supply"]:
            prog.text = ("%d/" % gc.kaleb_repeat_done) if current else "×"
    if Time.get_ticks_msec() / 1000.0 < _note_until:
        _footer.text = _note
        _footer.add_theme_color_override("font_color", GOLD)
    else:
        _footer.text = "Persistent  Particle %s · Iota %s · Mote %s · Grain %s" % [
            gc.persistent_particle.to_display_string(), gc.persistent_iota.to_display_string(),
            gc.persistent_mote.to_display_string(), gc.persistent_grain.to_display_string()]
        _footer.add_theme_color_override("font_color", TEXT_DIM)


# ==================================================
# ACTIONS
# ==================================================
func _on_run_pressed() -> void:
    if _shows_live():
        gc.kaleb_running = not gc.kaleb_running
        return
    var was: int = gc.kaleb_live_slot
    var why: String = gc.kaleb_run_slot(_stack_slot)
    _say(why if why != "" else "Slot %d is running; Slot %d stopped" % [_stack_slot + 1, was + 1])


func _on_add_chosen(id: int) -> void:
    var cmd: String = PALETTE[id]
    var bar: Dictionary = KC.make_bar(cmd)
    match cmd:
        "lock", "unlock":
            bar["target"] = "monad_liquid"
        "if":
            bar["res"] = "persistent_particle"
            bar["value"] = 4
        "supply_sparks", "feed_endow", "feed_ignore":
            var cd: Node = get_node_or_null("/root/ConstellationData")
            var ids: Array = cd.unlocked.duplicate() if cd else []
            ids.sort()
            bar["target"] = str(ids[0]) if not ids.is_empty() else "0"
    if not gc.kaleb_add_bar(bar, -1, _stack_slot):
        _say("No free Focus for a new bar")


# ==================================================
# STACK SLOTS: save the stack to a slot, load it back (author, 2026-11-06;
# modelled on the Settings panel's save slots: pick a slot, then Save or Load)
# ==================================================
## Left to right: the chosen slot's bar count, "Stack 1 2 3", Save, Load
## (author, 2026-11-06: the count and the slot buttons swapped places, so
## the slot buttons sit next to the Save and Load they feed).
func _build_slot_row() -> HBoxContainer:
    var row := HBoxContainer.new()
    row.add_theme_constant_override("separation", 2)
    _slot_status = _label("", TEXT_DIM)
    _slot_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    _slot_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    _slot_status.clip_text = true
    row.add_child(_slot_status)
    row.add_child(_label("Stack", TEXT_DIM))
    for i in gc.kaleb_saved_stacks.size():
        var b := _small_button("%d" % (i + 1))
        b.toggle_mode = true
        b.custom_minimum_size = Vector2(26, 0)
        b.add_theme_color_override("font_pressed_color", GOLD)
        b.pressed.connect(_select_stack_slot.bind(i))
        row.add_child(b)
        _slot_btns.append(b)
    _save_btn = _small_button("Save")
    _save_btn.custom_minimum_size = Vector2(76, 0)
    _save_btn.pressed.connect(_on_stack_save)
    row.add_child(_save_btn)
    _load_btn = _small_button("Load")
    _load_btn.custom_minimum_size = Vector2(76, 0)
    _load_btn.pressed.connect(_on_stack_load)
    row.add_child(_load_btn)
    return row


## Shows slot `i`'s stack (author, 2026-11-06). Kaleb keeps running whichever
## slot is live; only Run here changes that.
func _select_stack_slot(i: int) -> void:
    _stack_slot = i
    _confirming = ""


## Save copies the shown slot's stack to its base; Load puts the base back
## (author: "allows a return to a base stack after experimentation"). Save
## over a base, or Load over a stack with bars, asks once on the button
## itself ("Overwrite?" / "Replace?"), and a second press does it, so the
## player stays in the tab; picking a slot or 3 s passing cancels.
func _on_stack_save() -> void:
    var bars: Array = _bars()
    if bars.is_empty():
        _say("No bars to save")
        return
    if not gc.kaleb_saved_bars(_stack_slot).is_empty() and _confirming != "save":
        _ask("save")
        return
    gc.kaleb_save_stack_to(_stack_slot)
    _confirming = ""
    _say("Saved Slot %d's %d bars as its base" % [_stack_slot + 1, bars.size()])


func _on_stack_load() -> void:
    if gc.kaleb_saved_bars(_stack_slot).is_empty():
        _say("Slot %d has no saved base" % (_stack_slot + 1))
        return
    if not _bars().is_empty() and _confirming != "load":
        _ask("load")
        return
    _confirming = ""
    var why: String = gc.kaleb_load_stack_from(_stack_slot)
    if why != "":
        _say(why)
    elif _shows_live():
        _say("Slot %d is back to its base: %d bars, paused at bar 1" % [_stack_slot + 1, _bars().size()])
    else:
        _say("Slot %d is back to its base: %d bars" % [_stack_slot + 1, _bars().size()])


func _ask(what: String) -> void:
    _confirming = what
    _confirm_until = Time.get_ticks_msec() / 1000.0 + 3.0


func _refresh_slot_row() -> void:
    if _confirming != "" and Time.get_ticks_msec() / 1000.0 > _confirm_until:
        _confirming = ""
    for i in _slot_btns.size():
        var b: Button = _slot_btns[i]
        b.set_pressed_no_signal(i == _stack_slot)
        var n: int = gc.kaleb_bars(i).size()
        var live_i: bool = gc.kaleb_is_live(i)
        # The live slot's number is green, so it shows from any slot.
        b.add_theme_color_override("font_color", LIVE if live_i else TEXT)
        b.tooltip_text = "Stack slot %d: %s%s" % [i + 1, ("%d bars" % n) if n > 0 else "empty",
            (" (running)" if gc.kaleb_running else " (live, paused)") if live_i else ""]
    var bars: int = _bars().size()
    var state: String = ("running" if gc.kaleb_running else "paused") if _shows_live() \
        else (("%d bars" % bars) if bars > 0 else "Empty")
    _slot_status.text = "Slot %d · %s" % [_stack_slot + 1, state]
    _slot_status.add_theme_color_override("font_color", LIVE if _shows_live() else TEXT_DIM)
    _save_btn.text = "Overwrite?" if _confirming == "save" else "Save"
    _load_btn.text = "Replace?" if _confirming == "load" else "Load"
    _save_btn.add_theme_color_override("font_color", GOLD if _confirming == "save" else TEXT)
    _load_btn.add_theme_color_override("font_color", GOLD if _confirming == "load" else TEXT)
    var base: int = gc.kaleb_saved_bars(_stack_slot).size()
    _save_btn.tooltip_text = "Save Slot %d's stack as its base (%s)" % [_stack_slot + 1,
        ("over its %d-bar base" % base) if base > 0 else "it has none yet"]
    _load_btn.tooltip_text = ("Put Slot %d's %d-bar base back as its stack" % [_stack_slot + 1, base]) if base > 0 \
        else "Slot %d has no saved base" % (_stack_slot + 1)
    _save_btn.disabled = bars == 0
    _load_btn.disabled = base == 0


func _say(text: String) -> void:
    _note = text
    _note_until = Time.get_ticks_msec() / 1000.0 + 3.0


func _index_of(bar: Dictionary) -> int:
    var bars: Array = _bars()
    for i in bars.size():
        if is_same(bars[i], bar):
            return i
    return -1


# ==================================================
# DRAG AND DROP: a bar dropped on a row takes that row's slot
# ==================================================
func _make_handle(c: Control, i: int) -> void:
    c.mouse_filter = Control.MOUSE_FILTER_STOP
    c.mouse_default_cursor_shape = Control.CURSOR_DRAG
    c.set_drag_forwarding(_drag.bind(i), _can_drop.bind(i), _drop.bind(i))


func _drag(_at: Vector2, i: int) -> Variant:
    var preview := _label("  " + String(KC.COMMANDS.get(String(_bars()[i]["cmd"]), {}).get("name", "")), GOLD)
    set_drag_preview(preview)
    return {"kaleb_bar": i}


func _can_drop(_at: Vector2, data: Variant, _i: int) -> bool:
    return data is Dictionary and data.has("kaleb_bar")


func _drop(_at: Vector2, data: Variant, i: int) -> void:
    gc.kaleb_move_bar(int(data["kaleb_bar"]), i, _stack_slot)


# ==================================================
# SMALL PARTS
# ==================================================
func _label(text: String, col: Color) -> Label:
    var l := Label.new()
    l.text = text
    l.add_theme_font_size_override("font_size", FONT_SIZE)
    l.add_theme_color_override("font_color", col)
    l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    l.mouse_filter = Control.MOUSE_FILTER_PASS
    return l


func _small_button(text: String) -> Button:
    var b := Button.new()
    b.text = text
    b.focus_mode = Control.FOCUS_NONE
    b.add_theme_font_size_override("font_size", FONT_SIZE)
    _compact(b)
    return b


## Thin padding and a 1 px border on the stack's controls: the game theme's
## padding made every row with a field or button ~30 px tall.
func _compact(c: Control) -> void:
    var names: Array = ["normal", "hover", "pressed", "disabled", "focus", "hover_pressed"]
    if c is LineEdit:
        names = ["normal", "focus", "read_only"]
    for state in names:
        var sb := StyleBoxFlat.new()
        sb.bg_color = Color(0.10, 0.09, 0.16, 0.95)
        if state in ["hover", "hover_pressed"]:
            sb.bg_color = Color(0.18, 0.16, 0.28, 0.95)
        elif state == "pressed":
            sb.bg_color = Color(0.22, 0.19, 0.36, 0.95)
        sb.set_border_width_all(1)
        sb.border_color = Color(0.85, 0.80, 0.95, 0.55 if state != "focus" else 0.9)
        if state == "focus" and not (c is LineEdit):
            sb.draw_center = false
        sb.set_corner_radius_all(3)
        sb.content_margin_left = 4
        sb.content_margin_right = 4
        sb.content_margin_top = 1
        sb.content_margin_bottom = 1
        c.add_theme_stylebox_override(state, sb)


## A small typed number field bound to bar[key], clamped to lo..hi. `shift`
## is added to what is stored: an If bar's go-to is shown 1-based, like the
## row numbers, and stored 0-based. (SpinBoxes' arrows made rows too tall.)
func _num_edit(bar: Dictionary, key: String, lo: int, hi: int, shift: int, width: float) -> LineEdit:
    var e := LineEdit.new()
    e.text = str(int(bar.get(key, lo - shift)) - shift)
    e.custom_minimum_size = Vector2(width, 0)
    e.alignment = HORIZONTAL_ALIGNMENT_CENTER
    e.select_all_on_focus = true
    e.add_theme_font_size_override("font_size", FONT_SIZE)
    e.add_theme_constant_override("minimum_character_width", 1)
    _compact(e)
    var commit := func() -> void:
        var v: int = clampi(int(e.text) if e.text.is_valid_int() else lo, lo, hi)
        bar[key] = v + shift
        e.text = str(v)
    e.text_submitted.connect(func(_t: String) -> void:
        commit.call()
        e.release_focus())
    e.focus_exited.connect(commit)
    return e


## A menu bound to bar[key], listing `keys` by their display names.
## `labels`, when given, are what the menu shows for `keys` (else their
## display names).
func _option(bar: Dictionary, key: String, keys: Array, width: float, labels: Array = []) -> OptionButton:
    var o := OptionButton.new()
    o.focus_mode = Control.FOCUS_NONE
    o.custom_minimum_size = Vector2(width, 0)
    o.fit_to_longest_item = false
    o.clip_text = true
    o.add_theme_font_size_override("font_size", FONT_SIZE)
    _compact(o)
    o.get_popup().add_theme_font_size_override("font_size", FONT_SIZE + 1)
    var selected := 0
    for j in keys.size():
        o.add_item(String(labels[j]) if j < labels.size() else _display_name(String(keys[j])), j)
        if String(keys[j]) == String(bar.get(key, "")):
            selected = j
    o.select(selected)
    bar[key] = String(keys[selected])
    o.item_selected.connect(func(j: int) -> void: bar[key] = String(keys[j]))
    o.tooltip_text = _display_name(String(bar[key]))
    return o


## A lock key or count key as the player reads it.
func _display_name(key: String) -> String:
    return KC.display_name(key, gd)
