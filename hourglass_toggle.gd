extends Control
# =================== HOURGLASS TOGGLE v0.4 ===================
# Small clickable indicator placed at the right of each genbar row.
# Upright = this operation is in hourglass_target_ops (active, full alpha).
# On its side = not targeted (low alpha, rotated 90°).
# Clicking toggles this operation in/out of the target set, subject to
# the cap of assigned Child Volitions on the Hourglass constellation slot.
# Invisible until the Hourglass puzzle has been solved.
# v0.4: Added _game_loaded flag to prevent drawing stale state before load.

@export var operation_key: String = ""

const COLOR_ACTIVE    := Color(UIAccentColors.CREAM, 0.90)
const COLOR_INACTIVE  := Color(UIAccentColors.CREAM, 0.28)
const COLOR_PARENT    := Color(1.0, 0.85, 0.2, 0.90)
const LINE_W_ACTIVE   := 2.0
const LINE_W_INACTIVE := 1.5

var gc: Node = null
var cd: Node = null
var _game_loaded: bool = false
var _saved_row_state: Dictionary = {}   # ProgressBar -> [mouse_filter, tooltip_text]


func _ready() -> void:
    gc = get_node_or_null("/root/GameContext")
    cd = get_node_or_null("/root/ConstellationData")
    var sm: Node = get_node_or_null("/root/SaveManager")
    mouse_filter = Control.MOUSE_FILTER_STOP
    tooltip_text = "Direct Hourglass here"
    visible = false
    # The whole genbar row is the click target, not just this mini-icon: the
    # row's HBox receives clicks that fall through its children (see
    # _set_row_clickable) and routes them here.
    var row := get_parent() as Control
    if row:
        row.gui_input.connect(_gui_input)
    if sm and sm.has_signal("game_loaded"):
        sm.game_loaded.connect(_on_game_loaded)


func _on_game_loaded(_elapsed: float) -> void:
    _game_loaded = true
    var unlocked := _hourglass_unlocked()
    visible = unlocked
    _set_row_clickable(unlocked)
    if unlocked:
        queue_redraw()


## While the Hourglass is unlocked, make the row's ProgressBars (MOUSE_FILTER_STOP
## by default, so they swallow clicks) pass clicks up to the row, and give them
## this toggle's tooltip. Original filters/tooltips are restored when locked.
func _set_row_clickable(on: bool) -> void:
    var row := get_parent() as Control
    if not row:
        return
    for sib in row.get_children():
        var bar := sib as ProgressBar
        if not bar:
            continue
        if on:
            if not _saved_row_state.has(bar):
                _saved_row_state[bar] = [bar.mouse_filter, bar.tooltip_text]
            bar.mouse_filter = Control.MOUSE_FILTER_PASS
            bar.tooltip_text = tooltip_text
        elif _saved_row_state.has(bar):
            bar.mouse_filter = _saved_row_state[bar][0]
            bar.tooltip_text = _saved_row_state[bar][1]
            _saved_row_state.erase(bar)


func _is_targeted() -> bool:
    if not gc: return false
    return gc.hourglass_target_ops.has(operation_key)


func _hourglass_unlocked() -> bool:
    # Shown only once the Hourglass puzzle (constellation 2) has been solved,
    # not merely once Sparks have been invested in it.
    if not gc or not gc.has_method("_assignment_int"): return false
    return gc._assignment_int("constellation_2_solve_count", 0) >= 1


func _get_hourglass_volition_cap() -> int:
    if not gc: return 0
    if gc.has_method("get_volition_count_for_constellation"):
        return gc.get_volition_count_for_constellation(2)
    return 0


func _process(_delta: float) -> void:
    if not _game_loaded:
        return
    var unlocked := _hourglass_unlocked()
    if visible != unlocked:
        visible = unlocked
        _set_row_clickable(unlocked)
    if unlocked:
        queue_redraw()


func _gui_input(event: InputEvent) -> void:
    if not event is InputEventMouseButton: return
    if not (event as InputEventMouseButton).pressed: return
    if (event as InputEventMouseButton).button_index != MOUSE_BUTTON_LEFT: return
    if not gc or not _hourglass_unlocked(): return
    var cap: int = _get_hourglass_volition_cap()
    var current_ops: Array[String] = gc.hourglass_target_ops
    if current_ops.has(operation_key):
        current_ops.erase(operation_key)
        gc.hourglass_target_ops = current_ops
    else:
        if current_ops.size() < cap:
            current_ops.append(operation_key)
            gc.hourglass_target_ops = current_ops
    queue_redraw()
    get_viewport().set_input_as_handled()


func _draw() -> void:
    if not _hourglass_unlocked(): return
    var is_active := _is_targeted()
    var is_parent: bool = is_active and gc != null \
                     and gc.has_method("has_parent_volition_for_constellation") \
                     and gc.has_parent_volition_for_constellation(2)
    var col := COLOR_PARENT if is_parent else (COLOR_ACTIVE if is_active else COLOR_INACTIVE)
    var lw  := LINE_W_ACTIVE if is_active else LINE_W_INACTIVE
    var w := size.x * 0.34
    var h := size.y * 0.38
    var rot := 0.0 if is_active else PI * 0.5
    draw_set_transform(size * 0.5, rot, Vector2.ONE)
    draw_line(Vector2(-w, -h), Vector2(w,  -h), col, lw)
    draw_line(Vector2(-w, -h), Vector2(0,   0), col, lw)
    draw_line(Vector2( w, -h), Vector2(0,   0), col, lw)
    draw_line(Vector2( 0,  0), Vector2(-w,  h), col, lw)
    draw_line(Vector2( 0,  0), Vector2( w,  h), col, lw)
    draw_line(Vector2(-w,  h), Vector2(w,   h), col, lw)
    draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
