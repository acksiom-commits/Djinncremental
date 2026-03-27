extends Control
# ================= ALLOCATION WHEEL v0.9.1 =================
# v0.9.1: Fixed int(BigNum) casts — replaced with .to_int()
#         since BigNum is a custom class not known to GDScript's
#         built-in int() constructor.
# v0.9.0: Uonite pool total and assigned values now use BigNum.
#         Plus/minus handlers use BigNum arithmetic for uonites.
#         Foci and volitions remain int throughout.
#
# Radial resource selector with central +/- allocation controls.
# UI structure lives in AllocationWheelControl.tscn.
#
# Circle layout (8 resources in oval):
#         Sparks     (12 o'clock)
#  Motes            Monads      (10:30 / 1:30)
# Particles          Tetrads    (9:00  / 3:00)
#  Grains            Iotas      (7:30  / 4:30)
#         Uonites    (6 o'clock)

# === SIGNALS ===
signal multiplier_changed(amount: int)

# === DIMENSIONS ===
const ICON_SIZE : float = 36.0

const RESOURCE_ANGLES = {
    "sparks":   -90.0,
    "monad":    -45.0,
    "tetrad":     0.0,
    "iota":      45.0,
    "uonite":    90.0,
    "grain":    135.0,
    "particle": 180.0,
    "mote":     225.0,
}

const RESOURCE_OPERATIONS = {
    "sparks":   "sparks_summon",
    "monad":    "monad_compress",
    "tetrad":   "tetrad_assemble",
    "iota":     "iota_compress",
    "mote":     "mote_assemble",
    "particle": "particle_compress",
    "grain":    "grain_assemble",
    "uonite":   "",
}

const POOL_SUFFIXES = ["uonites", "foci", "volitions"]

const MULTI_GRID = [
    ["10X",  10],
    ["100X", 100],
    ["CSTM", -2],
    ["ALL",  -1],
]

const COLOR_SELECTED    = Color(1.00, 1.00, 1.00, 1.00)
const COLOR_ALLOCATED   = Color(1.00, 1.00, 1.00, 0.85)
const COLOR_UNALLOCATED = Color(1.00, 1.00, 1.00, 0.30)
const COLOR_BORDER_SEL  = Color(0.92, 0.90, 0.85, 0.90)
const COLOR_MULTI_SEL   = Color(0.92, 0.90, 0.85, 1.00)
const COLOR_MULTI_NORM  = Color(0.92, 0.90, 0.85, 0.40)

# === REFERENCES ===
var game_context: Node = null
var production_manager: Node = null
var game_data: Node = null

# === STATE ===
var selected_resource: String = "sparks"
var selected_multiplier: int = 1

# === SCENE NODE REFS ===
@onready var _selected_label: RichTextLabel = $CenterVBox/SelectedLabel
@onready var _custom_container: Control     = $CenterVBox/CustomInputContainerHBox
@onready var _custom_line_edit: LineEdit    = $CenterVBox/CustomInputContainerHBox/CustomLineEdit

@onready var _plus_uonites:    Button = $CenterVBox/UonitesRowHBox/PlusUonites
@onready var _minus_uonites:   Button = $CenterVBox/UonitesRowHBox/MinusUonites
@onready var _plus_foci:       Button = $CenterVBox/FociRowHBox/PlusFoci
@onready var _minus_foci:      Button = $CenterVBox/FociRowHBox/MinusFoci
@onready var _plus_volitions:  Button = $CenterVBox/VolitionsRowHBox/PlusVolitions
@onready var _minus_volitions: Button = $CenterVBox/VolitionsRowHBox/MinusVolitions

@onready var _label_uonites:   Node = $CenterVBox/UonitesRowHBox/UonitesLabelCounterVBox/RowUonitesInstance
@onready var _label_foci:      Node = $CenterVBox/FociRowHBox/FociLabelCounterVBox/RowFociInstance
@onready var _label_volitions: Node = $CenterVBox/VolitionsRowHBox/VolitionsLabelCounterVBox/RowVolitionsInstance

# Multi buttons — collected in _ready()
var _multi_buttons: Array = []

# Icon buttons built at runtime
var _icon_buttons: Dictionary = {}
var _icon_textures: Dictionary = {}

# Convenience dicts keyed by suffix for _update_center_values()
var _plus_buttons: Dictionary = {}
var _minus_buttons: Dictionary = {}
var _value_rows: Dictionary = {}


# ==================================================
# DYNAMIC DIMENSIONS (based on actual size)
# ==================================================
func _get_center_x() -> float:
    return size.x / 2.0

func _get_center_y() -> float:
    return size.y / 2.0

func _get_radius_x() -> float:
    return size.x / 2.0 - ICON_SIZE / 2.0 - 10.0

func _get_radius_y() -> float:
    return size.y / 2.0 - ICON_SIZE / 2.0 - 10.0


# ==================================================
# READY
# ==================================================
func _ready() -> void:
    game_context       = get_node_or_null("/root/GameContext")
    production_manager = get_node_or_null("/root/ProductionManager")
    game_data          = get_node_or_null("/root/GameData")

    _plus_buttons  = {"uonites": _plus_uonites,   "foci": _plus_foci,   "volitions": _plus_volitions}
    _minus_buttons = {"uonites": _minus_uonites,  "foci": _minus_foci,  "volitions": _minus_volitions}
    _value_rows    = {"uonites": _label_uonites,  "foci": _label_foci,  "volitions": _label_volitions}

    _plus_uonites.pressed.connect(func(): _on_plus_pressed("uonites"))
    _minus_uonites.pressed.connect(func(): _on_minus_pressed("uonites"))
    _plus_foci.pressed.connect(func(): _on_plus_pressed("foci"))
    _minus_foci.pressed.connect(func(): _on_minus_pressed("foci"))
    _plus_volitions.pressed.connect(func(): _on_plus_pressed("volitions"))
    _minus_volitions.pressed.connect(func(): _on_minus_pressed("volitions"))

    var ok_btn = get_node_or_null("CenterVBox/CustomInputContainerHBox/OKButton")
    if ok_btn:
        ok_btn.pressed.connect(func(): _on_custom_submitted(_custom_line_edit.text))
    if _custom_line_edit:
        _custom_line_edit.text_submitted.connect(_on_custom_submitted)

    var multi_grid = get_node_or_null("CenterVBox/MultiGrid")
    if multi_grid:
        for i in MULTI_GRID.size():
            var entry = MULTI_GRID[i]
            var amount: int = entry[1]
            var btn = multi_grid.get_child(i)
            if btn:
                _multi_buttons.append([btn, amount])
                var captured_amount = amount
                btn.pressed.connect(func(): _on_multi_pressed(captured_amount))

    _preload_textures()
    _build_icon_buttons()

    resized.connect(_on_resized)
    call_deferred("_post_ready")


func _on_resized() -> void:
    _reposition_center_vbox()
    _reposition_icon_buttons()
    queue_redraw()


func _post_ready() -> void:
    _reposition_center_vbox()
    _select_resource("sparks")
    _update_multi_button_states()


func _reposition_center_vbox() -> void:
    var vbox = get_node_or_null("CenterVBox")
    if not vbox or vbox.size.x <= 0 or vbox.size.y <= 0:
        return
    vbox.position = (size - vbox.size) / 2.0


func _reposition_icon_buttons() -> void:
    for key in _icon_buttons:
        var btn = _icon_buttons[key]
        var angle_rad = deg_to_rad(RESOURCE_ANGLES[key])
        var cx = _get_center_x() + _get_radius_x() * cos(angle_rad) - ICON_SIZE / 2.0
        var cy = _get_center_y() + _get_radius_y() * sin(angle_rad) - ICON_SIZE / 2.0
        btn.position = Vector2(cx, cy)


# ==================================================
# TEXTURE PRELOAD
# ==================================================
func _preload_textures() -> void:
    if not game_data:
        return
    for key in RESOURCE_ANGLES:
        var icon_path = game_data.RESOURCES.get(key, {}).get("icon", "")
        if icon_path != "" and ResourceLoader.exists(icon_path):
            _icon_textures[key] = load(icon_path)


# ==================================================
# ICON BUTTON CONSTRUCTION
# ==================================================
func _build_icon_buttons() -> void:
    for key in RESOURCE_ANGLES:
        var angle_rad = deg_to_rad(RESOURCE_ANGLES[key])
        var cx = _get_center_x() + _get_radius_x() * cos(angle_rad) - ICON_SIZE / 2.0
        var cy = _get_center_y() + _get_radius_y() * sin(angle_rad) - ICON_SIZE / 2.0

        var btn = TextureButton.new()
        btn.name = "WheelBtn_" + key
        btn.position = Vector2(cx, cy)
        btn.custom_minimum_size = Vector2(ICON_SIZE, ICON_SIZE)
        btn.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
        btn.ignore_texture_size = true
        if _icon_textures.has(key):
            btn.texture_normal = _icon_textures[key]
        btn.modulate = COLOR_UNALLOCATED
        _icon_buttons[key] = btn

        var captured_key = key
        btn.pressed.connect(func(): _select_resource(captured_key))
        add_child(btn)

    queue_redraw()


# ==================================================
# DRAW — oval guide ring + selection arc
# ==================================================
func _draw() -> void:
    var points: PackedVector2Array = []
    var steps = 64
    for i in steps + 1:
        var a = (float(i) / float(steps)) * TAU
        points.append(Vector2(
            _get_center_x() + _get_radius_x() * cos(a),
            _get_center_y() + _get_radius_y() * sin(a)
        ))
    for i in points.size() - 1:
        draw_line(points[i], points[i + 1], Color(0.92, 0.90, 0.85, 0.08), 1.5)

    if _icon_buttons.has(selected_resource):
        var btn = _icon_buttons[selected_resource]
        var btn_center = btn.position + Vector2(ICON_SIZE / 2.0, ICON_SIZE / 2.0)
        draw_arc(btn_center, ICON_SIZE / 2.0 + 4.0, 0, TAU, 32, COLOR_BORDER_SEL, 2.0)


# ==================================================
# RESOURCE SELECTION
# ==================================================
func _select_resource(key: String) -> void:
    selected_resource = key
    if _selected_label and game_data:
        var res_data = game_data.RESOURCES.get(key, {})
        var display_name: String = res_data.get("name", key.capitalize())
        var color_hex: String = res_data.get("color", "#ffffff")
        var accent = Color.from_string(color_hex, Color.WHITE)
        var name_len = display_name.length()
        var bbcode = "[center]"
        for i in name_len:
            var t = float(i) / max(float(name_len - 1), 1.0)
            var lerped = accent.lerp(Color.WHITE, t)
            var hex = "#%02x%02x%02x" % [
                int(lerped.r * 255),
                int(lerped.g * 255),
                int(lerped.b * 255)
            ]
            bbcode += "[color=" + hex + "]" + display_name[i] + "[/color]"
        bbcode += "[/center]"
        _selected_label.set("bbcode_text", bbcode)
    queue_redraw()
    _update_center_values()


# ==================================================
# MULTISELECTOR
# ==================================================
func _on_multi_pressed(amount: int) -> void:
    if amount == -2:
        if _custom_container.visible:
            _custom_container.visible = false
            selected_multiplier = 1
            _update_multi_button_states()
            return
        _custom_container.visible = true
        _custom_line_edit.grab_focus()
        return

    _custom_container.visible = false

    if selected_multiplier == amount:
        selected_multiplier = 1
        emit_signal("multiplier_changed", 1)
        _update_multi_button_states()
        return

    selected_multiplier = amount
    emit_signal("multiplier_changed", amount)
    _update_multi_button_states()


func _on_custom_submitted(text: String) -> void:
    var value = text.to_int()
    if value > 0:
        selected_multiplier = value
        emit_signal("multiplier_changed", value)
    _custom_container.visible = false
    _custom_line_edit.text = ""
    _update_multi_button_states()


func _update_multi_button_states() -> void:
    for entry in _multi_buttons:
        var btn: Button = entry[0]
        var amount: int = entry[1]
        var is_active = false
        if amount == -2:
            is_active = _custom_container.visible or (
                selected_multiplier != 1 and
                selected_multiplier != 10 and
                selected_multiplier != 100 and
                selected_multiplier != -1
            )
        elif amount != 1:
            is_active = (amount == selected_multiplier)
        btn.add_theme_color_override("font_color",
            COLOR_MULTI_SEL if is_active else COLOR_MULTI_NORM)


# ==================================================
# PLUS / MINUS HANDLERS
# ==================================================
func _on_plus_pressed(pool_suffix: String) -> void:
    if not game_context:
        return
    var op = RESOURCE_OPERATIONS.get(selected_resource, "")
    if op == "":
        return
    var assignment_key = op + "_" + pool_suffix

    if pool_suffix == "uonites":
        # BigNum path for uonites
        var current: BigNum = game_context.assignments.get(assignment_key, BigNum.zero())
        if not current is BigNum:
            current = BigNum.from_int(current.to_int())
        var headroom: BigNum = _get_pool_headroom_bignum(pool_suffix)
        if headroom.is_zero():
            return
        var amount: BigNum
        if selected_multiplier == -1:
            amount = headroom
        else:
            var mult = BigNum.from_int(selected_multiplier)
            amount = mult if mult.is_less_or_equal(headroom) else headroom
        var new_value = current.add(amount)
        game_context.assignments[assignment_key] = new_value
        if production_manager and production_manager.has_method("update_assignment"):
            production_manager.update_assignment(assignment_key, new_value)
    else:
        # Int path for foci and volitions
        var current: int = game_context.assignments.get(assignment_key, 0)
        var headroom: int = _get_pool_total_int(pool_suffix) - _get_pool_assigned_int(pool_suffix)
        if headroom <= 0:
            return
        var amount: int = headroom if selected_multiplier == -1 else min(selected_multiplier, headroom)
        var new_value: int = current + amount
        game_context.assignments[assignment_key] = new_value
        if production_manager and production_manager.has_method("update_assignment"):
            production_manager.update_assignment(assignment_key, new_value)


func _on_minus_pressed(pool_suffix: String) -> void:
    if not game_context:
        return
    var op = RESOURCE_OPERATIONS.get(selected_resource, "")
    if op == "":
        return
    var assignment_key = op + "_" + pool_suffix

    if pool_suffix == "uonites":
        # BigNum path for uonites
        var current: BigNum = game_context.assignments.get(assignment_key, BigNum.zero())
        if not current is BigNum:
            current = BigNum.from_int(current.to_int())
        if current.is_zero():
            return
        var amount: BigNum
        if selected_multiplier == -1:
            amount = current
        else:
            var mult = BigNum.from_int(selected_multiplier)
            amount = mult if mult.is_less_or_equal(current) else current
        var new_value = current.sub(amount)
        game_context.assignments[assignment_key] = new_value
        if production_manager and production_manager.has_method("update_assignment"):
            production_manager.update_assignment(assignment_key, new_value)
    else:
        # Int path for foci and volitions
        var current: int = game_context.assignments.get(assignment_key, 0)
        if current <= 0:
            return
        var amount: int = current if selected_multiplier == -1 else min(selected_multiplier, current)
        var new_value: int = current - amount
        game_context.assignments[assignment_key] = new_value
        if production_manager and production_manager.has_method("update_assignment"):
            production_manager.update_assignment(assignment_key, new_value)


# ==================================================
# POOL HELPERS
# ==================================================
func _get_pool_total_bignum(suffix: String) -> BigNum:
    if not game_context: return BigNum.zero()
    match suffix:
        "uonites": return game_context.uonite
    return BigNum.zero()

func _get_pool_assigned_bignum(suffix: String) -> BigNum:
    if not game_context: return BigNum.zero()
    match suffix:
        "uonites": return game_context.get_total_uonites_assigned()
    return BigNum.zero()

func _get_pool_headroom_bignum(suffix: String) -> BigNum:
    var total    = _get_pool_total_bignum(suffix)
    var assigned = _get_pool_assigned_bignum(suffix)
    if assigned.is_greater_than(total):
        return BigNum.zero()
    return total.sub(assigned)

func _get_pool_total_int(suffix: String) -> int:
    if not game_context: return 0
    match suffix:
        "foci":      return game_context.archon_foci
        "volitions": return game_context.volitions
    return 0

func _get_pool_assigned_int(suffix: String) -> int:
    if not game_context: return 0
    match suffix:
        "foci":      return game_context.get_total_foci_assigned()
        "volitions": return game_context.get_total_volitions_assigned()
    return 0


# ==================================================
# PROCESS
# ==================================================
func _process(_delta: float) -> void:
    if not game_context:
        return
    _update_icon_states()
    _update_center_values()


func _update_icon_states() -> void:
    for key in _icon_buttons:
        var btn = _icon_buttons[key]
        var op = RESOURCE_OPERATIONS.get(key, "")
        var has_allocation = false
        if op != "":
            var u = game_context.assignments.get(op + "_uonites", BigNum.zero())
            if u is BigNum and not u.is_zero():
                has_allocation = true
            if not has_allocation:
                for suffix in ["foci", "volitions"]:
                    if game_context.assignments.get(op + "_" + suffix, 0) > 0:
                        has_allocation = true
                        break
        if key == selected_resource:
            btn.modulate = COLOR_SELECTED
        elif has_allocation:
            btn.modulate = COLOR_ALLOCATED
        else:
            btn.modulate = COLOR_UNALLOCATED


func _update_center_values() -> void:
    if not game_context:
        return
    var op = RESOURCE_OPERATIONS.get(selected_resource, "")
    for suffix in POOL_SUFFIXES:
        var row = _value_rows.get(suffix)
        var plus_btn  = _plus_buttons.get(suffix)
        var minus_btn = _minus_buttons.get(suffix)
        if not row:
            continue
        if op == "":
            row.set_label("—")
            if plus_btn:  plus_btn.disabled  = true
            if minus_btn: minus_btn.disabled = true
            continue

        var assignment_key = op + "_" + suffix
        if suffix == "uonites":
            var assigned: BigNum = game_context.assignments.get(assignment_key, BigNum.zero())
            if not assigned is BigNum:
                assigned = BigNum.from_int(assigned.to_int())
            var headroom = _get_pool_headroom_bignum(suffix)
            row.set_label(_fmt_bignum(assigned))
            if plus_btn:  plus_btn.disabled  = headroom.is_zero()
            if minus_btn: minus_btn.disabled = assigned.is_zero()
        else:
            var assigned: int  = game_context.assignments.get(assignment_key, 0)
            var pool_total     = _get_pool_total_int(suffix)
            var pool_assigned  = _get_pool_assigned_int(suffix)
            var available      = max(0, pool_total - pool_assigned)
            row.set_label(_fmt_int(assigned))
            if plus_btn:  plus_btn.disabled  = (available <= 0)
            if minus_btn: minus_btn.disabled = (assigned <= 0)


func _fmt_bignum(value: BigNum) -> String:
    if game_data:
        return game_data.format_number(value)
    return value.to_display_string()

func _fmt_int(value: int) -> String:
    if game_data:
        return game_data.format_number(value, false)
    return str(value)
