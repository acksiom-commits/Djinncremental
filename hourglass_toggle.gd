extends Control
# =================== HOURGLASS TOGGLE v0.4 ===================
# Small clickable indicator placed at the right of each genbar row.
# Upright = this operation is in hourglass_target_ops (active, full alpha).
# On its side = not targeted (low alpha, rotated 90°).
# Clicking toggles this operation in/out of the target set, subject to
# the cap of assigned Child Volitions on the Hourglass constellation slot.
# Invisible until Hourglass is unlocked.
# v0.4: Added _game_loaded flag to prevent drawing stale state before load.

@export var operation_key: String = ""

const COLOR_ACTIVE    := Color(0.92, 0.90, 0.85, 0.90)
const COLOR_INACTIVE  := Color(0.92, 0.90, 0.85, 0.28)
const COLOR_PARENT    := Color(1.0, 0.85, 0.2, 0.90)
const LINE_W_ACTIVE   := 2.0
const LINE_W_INACTIVE := 1.5

var gc: Node = null
var cd: Node = null
var _game_loaded: bool = false


func _ready() -> void:
    gc = get_node_or_null("/root/GameContext")
    cd = get_node_or_null("/root/ConstellationData")
    var sm: Node = get_node_or_null("/root/SaveManager")
    mouse_filter = Control.MOUSE_FILTER_STOP
    tooltip_text = "Direct Hourglass here"
    if sm and sm.has_signal("game_loaded"):
        sm.game_loaded.connect(_on_game_loaded)


func _on_game_loaded(_elapsed: float) -> void:
    _game_loaded = true
    var unlocked := _hourglass_unlocked()
    visible = unlocked
    if unlocked:
        queue_redraw()


func _is_targeted() -> bool:
    if not gc: return false
    return gc.hourglass_target_ops.has(operation_key)


func _hourglass_unlocked() -> bool:
    if not cd: return false
    var frac: float = cd.get_spark_fraction(2) if cd.has_method("get_spark_fraction") else 0.0
    return frac > 0.0


func _get_hourglass_volition_cap() -> int:
    if not gc: return 0
    var slots = gc.get("volition_slots")
    if not slots is Array: return 0
    var count := 0
    for slot in (slots as Array):
        if slot.get("category", "") != "constellation":
            continue
        if int(slot.get("target", -1)) == 2:
            count += 1
        for child in slot.get("children", []):
            if child.get("category", "") == "constellation" \
            and int(child.get("target", -1)) == 2:
                count += 1
    return count


func _process(_delta: float) -> void:
    if not _game_loaded:
        return
    var unlocked := _hourglass_unlocked()
    if visible != unlocked:
        visible = unlocked
    if unlocked:
        queue_redraw()


func _gui_input(event: InputEvent) -> void:
    if not event is InputEventMouseButton: return
    if not (event as InputEventMouseButton).pressed: return
    if (event as InputEventMouseButton).button_index != MOUSE_BUTTON_LEFT: return
    if not gc: return
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
