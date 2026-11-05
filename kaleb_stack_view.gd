extends PanelContainer
## Kaleb's command stack, shown in the Journal slideout's **Commands** tab on
## Primordial (journal_popout.gd set_commands_view(); SysDoc §7.3). It first
## sat in the Constellation box; the author moved it here, 2026-11-05.
##
##   header   Run/Pause (GameContext.kaleb_running) and "+ Command", the
##            palette (kaleb_commands.gd)
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
## The Uonite − and + repeat while held, like the wheel's Uonite buttons.
var _hold = preload("res://hold_repeat.gd").new()
## The palette's order.
const PALETTE: Array[String] = ["summon_spark", "monad_compress", "tetrad_assemble",
    "persistent_particle", "persistent_iota", "persistent_mote", "persistent_grain",
    "lock", "unlock", "if"]
## What an If bar can count, in its menu's order.
const IF_KEYS: Array[String] = ["sparks", "monad", "tetrad", "monad_solid", "monad_liquid", "monad_gas",
    "adaemant", "aquae", "aethyr", "earth", "water", "air", "mud", "dust", "cloud",
    "silt", "sand", "haze", "mist", "ooze", "foam", "particle",
    "persistent_particle", "persistent_iota", "persistent_mote", "persistent_grain"]

var gc: Node = null
var gd: Node = null

var _run_btn: Button
var _add_btn: MenuButton
var _list: VBoxContainer
var _scroll: ScrollContainer
var _footer: Label
var _rows: Array = []          # one Dictionary per bar: {panel, num, progress, bar}
var _built: Array = []         # the bars the rows were built from, in order
var _built_once: bool = false
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
    var title := _label("Kaleb's Commands", TEXT_DIM)
    title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    head.add_child(title)
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
    if _stack_changed():
        _rebuild()
    _refresh()
    _hold.tick(delta)


## Whether the bars, in order, are no longer the ones the rows were built
## from. Bars are Dictionaries, shared by reference, so this compares
## identity: a move, an add, a remove or a load all show up, an edit to a
## bar's settings doesn't.
func _stack_changed() -> bool:
    if not _built_once or _built.size() != gc.kaleb_stack.size():
        return true
    for i in _built.size():
        if not is_same(_built[i], gc.kaleb_stack[i]):
            return true
    return false


# ==================================================
# ROWS
# ==================================================
func _rebuild() -> void:
    _built = gc.kaleb_stack.duplicate()   # shallow: the same bar Dictionaries
    _built_once = true
    for c in _list.get_children():
        c.queue_free()
    _rows.clear()
    for i in gc.kaleb_stack.size():
        _rows.append(_build_row(i))
    if gc.kaleb_stack.is_empty():
        var hint := _label("No commands yet: add one with + Command.", TEXT_DIM)
        _list.add_child(hint)


func _build_row(i: int) -> Dictionary:
    var bar: Dictionary = gc.kaleb_stack[i]
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
            # Its Uonites: each one more multiplies what a press makes.
            var minus := _small_button("−")
            minus.custom_minimum_size = Vector2(20, 0)
            minus.tooltip_text = "Take a worker back (a Focus first, then a Uonite)"
            _hold.connect_button(minus, func() -> void: gc.kaleb_change_bar_workers(bar, -1))
            row.add_child(minus)
            u_lbl = _label("", UONITE)
            u_lbl.custom_minimum_size = Vector2(52, 0)
            u_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
            row.add_child(u_lbl)
            var plus := _small_button("+")
            plus.custom_minimum_size = Vector2(20, 0)
            plus.tooltip_text = "Give it another worker: a Uonite, or a Focus when none is free"
            _hold.connect_button(plus, func() -> void:
                if not gc.kaleb_change_bar_workers(bar, 1):
                    _say("No free Uonite or Focus"))
            row.add_child(plus)
            progress.text = "×"
            row.add_child(progress)
            row.add_child(_num_edit(bar, "repeat", 1, 999, 0, 48))
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
    del.tooltip_text = "Remove (returns its Uonite and Focus)"
    del.pressed.connect(func() -> void:
        gc.kaleb_remove_bar(_index_of(bar)))
    row.add_child(del)
    return {"panel": panel, "num": num, "progress": progress, "bar": bar, "name": name_lbl, "uonites": u_lbl}


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
    _run_btn.text = "Pause" if gc.kaleb_running else "Run"
    _run_btn.disabled = gc.kaleb_stack.is_empty()
    for i in _rows.size():
        var r: Dictionary = _rows[i]
        var bar: Dictionary = r["bar"]
        var current: bool = i == gc.kaleb_index and not gc.kaleb_stack.is_empty()
        var style: StyleBoxFlat = _row_style(ROW_CURRENT if current else (ROW_BG if bool(bar["on"]) else ROW_OFF))
        (r["panel"] as PanelContainer).add_theme_stylebox_override("panel", style)
        (r["num"] as Label).text = ("▶" if current and gc.kaleb_running else "%d" % (i + 1))
        (r["name"] as Label).add_theme_color_override("font_color", TEXT if bool(bar["on"]) else TEXT_DIM)
        if r["uonites"]:
            var u: int = gc.kaleb_bar_uonites(bar)
            var f: int = gc.kaleb_bar_focus_workers(bar)
            var wl: Label = r["uonites"]
            wl.text = ("%dU" % u) if f == 0 else (("%dF" % f) if u == 0 else "%dU+%dF" % [u, f])
            wl.tooltip_text = "%d Uonite%s and %d Focus worker%s: each press makes %d times as much" % [
                u, "" if u == 1 else "s", f, "" if f == 1 else "s", u + f]
        # A press bar's "×N" reads "k/N" while Kaleb is on it.
        var prog: Label = r["progress"]
        if KC.COMMANDS.get(String(bar["cmd"]), {}).get("kind", "") == "press":
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
    gc.kaleb_running = not gc.kaleb_running


func _on_add_chosen(id: int) -> void:
    var cmd: String = PALETTE[id]
    var bar: Dictionary = KC.make_bar(cmd)
    match cmd:
        "lock", "unlock":
            bar["target"] = "monad_liquid"
        "if":
            bar["res"] = "persistent_particle"
            bar["value"] = 4
    if not gc.kaleb_add_bar(bar):
        _say("No free %s for a new bar" % ("Focus" if cmd == "if" else "Uonite or Focus"))


func _say(text: String) -> void:
    _note = text
    _note_until = Time.get_ticks_msec() / 1000.0 + 3.0


func _index_of(bar: Dictionary) -> int:
    for i in gc.kaleb_stack.size():
        if is_same(gc.kaleb_stack[i], bar):
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
    var preview := _label("  " + String(KC.COMMANDS.get(String(gc.kaleb_stack[i]["cmd"]), {}).get("name", "")), GOLD)
    set_drag_preview(preview)
    return {"kaleb_bar": i}


func _can_drop(_at: Vector2, data: Variant, _i: int) -> bool:
    return data is Dictionary and data.has("kaleb_bar")


func _drop(_at: Vector2, data: Variant, i: int) -> void:
    gc.kaleb_move_bar(int(data["kaleb_bar"]), i)


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
func _option(bar: Dictionary, key: String, keys: Array, width: float) -> OptionButton:
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
        o.add_item(_display_name(String(keys[j])), j)
        if String(keys[j]) == String(bar.get(key, "")):
            selected = j
    o.select(selected)
    bar[key] = String(keys[selected])
    o.item_selected.connect(func(j: int) -> void: bar[key] = String(keys[j]))
    o.tooltip_text = _display_name(String(bar[key]))
    return o


## A lock key or count key as the player reads it.
func _display_name(key: String) -> String:
    match key:
        "<", ">=": return key
        "sparks": return "Sparks"
        "monad": return "Monads (unlocked)"
        "tetrad": return "Tetrads (unlocked)"
        "monad_solid": return "Solid Monads"
        "monad_liquid": return "Liquid Monads"
        "monad_gas": return "Gas Monads"
        "cat_fundament": return "Fundaments"
        "cat_element": return "Elements"
        "cat_symmetric": return "Symmetrics"
        "cat_medial": return "Medials"
        "iota_uonite", "iota_grains": return "Iota"
        "mote_uonite", "mote_grains": return "Mote"
    if gd and gd.RESOURCES.has(key):
        return String(gd.RESOURCES[key]["name"])
    if gd and gd.TETRADS.has(key):
        var shown: String = String(gd.TETRADS[key].get("display", ""))
        return shown if shown != "" else key.capitalize()
    return key.capitalize()
