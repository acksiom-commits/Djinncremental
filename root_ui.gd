extends VBoxContainer

# ================= ROOT UI v2.8.0 =================
# v2.8.0: Production logic removed. All button handlers
#         now delegate to ProductionManager. Timer wiring
#         and batch functions removed — owned by ProductionManager.
# v2.7.0: Bars show efficiency (rate/assigned) with smoothed
#         interpolation and over-provisioning flash.
# COMPLETE FILE — NO PLACEHOLDERS, NO OMISSIONS

# === RESOURCE COLORS ===
const RESOURCE_COLORS = {
    "sparks":   Color("#ffffff"),
    "monad":    Color("#ee4444"),
    "tetrad":   Color("#ff9933"),
    "iota":     Color("#eecc00"),
    "mote":     Color("#55ff88"),
    "particle": Color("#55aaff"),
    "grain":    Color("#9944ee"),
    "uonite":   Color("#ffdd55")
}

# === MANAGER REFERENCES ===
var game_context:            Node = null
var production_manager:      Node = null
var save_manager:            Node = null
var game_data:               Node = null
var archon_dialogue_manager: Node = null

# === SUMMON SPARK EFFECT ===
const SPARK_EFFECT = preload("res://effects/spark_effect.tscn")

# === UONITE BUTTON ICON ===
var _uonite_icon_material: ShaderMaterial = null
var _uonite_icon_time:     float = 0.0
const UONITE_GRAIN_COST  = 20
const UONITE_FILL_SHADER = preload("res://uonite_fill.gdshader")

# === TETRAD DISPLAY LABELS ===
var _left_tetrad_label: RichTextLabel = null
var _middle_label:      RichTextLabel = null
var _medials2_label:    RichTextLabel = null

const TETRAD_NAMES = {
    "adaemant": "Adaemant", "aquae": "Aquae",  "aethyr": "Aethyr",
    "earth":    "Earth",    "water": "Water",   "air":    "Air",
    "mud":      "Mud",      "dust":  "Dust",    "cloud":  "Cloud",
    "dirt":     "Dirt",     "sand":  "Sand",    "haze":   "Haze",
    "mist":     "Mist",     "ooze":  "Ooze",    "foam":   "Foam",
}

const LEFT_LINE_MAP = [
    "cat_fundament",
    "adaemant", "adaemant",
    "aquae",    "aquae",
    "aethyr",   "aethyr",
    "cat_medial_1",
    "dirt",     "dirt",
    "sand",     "sand",
]

const MIDDLE_LINE_MAP = [
    "cat_element",
    "earth",    "earth",
    "water",    "water",
    "air",      "air",
    "cat_medial_1",
    "haze",     "haze",
    "mist",     "mist",
]

const MEDIALS2_LINE_MAP = [
    "cat_symmetric",
    "mud",   "mud",
    "dust",  "dust",
    "cloud", "cloud",
    "cat_medial_2",
    "ooze", "ooze",
    "foam", "foam",
]

# === BAR NODE REFERENCES ===
var bars: Dictionary = {}

const BAR_LABEL_COLOR     = Color(0.85, 0.85, 0.85, 0.65)
const BAR_LABEL_FONT_SIZE = 16

# === BAR DISPLAY STATE ===
# UI-only smoothed display values — migrate to ProductionManager on refactor
var _bar_smoothed_rates: Dictionary = {}  # resource -> float
var _time:               float = 0.0
const BAR_SMOOTH_RATE:     float = 3.5   # exponential decay speed
const BAR_FLASH_THRESHOLD: float = 1.05  # efficiency ratio for flash (5% over)
const BAR_FLASH_SPEED:     float = 4.0   # sine wave cycles per second
# TODO: BAR_FLASH_THRESHOLD should become a player preference setting

# === DEV ===
const DEV_UONITE_CHUNK = [1.11, 33]

# === DIALOGUE TRIGGER FLAGS ===
var _monad_upgrade_triggered:  bool = false
var _tetrad_upgrade_triggered: bool = false


# ==================================================
# READY
# ==================================================
func _ready() -> void:
    game_context            = get_node_or_null("/root/GameContext")
    production_manager      = get_node_or_null("/root/ProductionManager")
    save_manager            = get_node_or_null("/root/SaveManager")
    game_data               = get_node_or_null("/root/GameData")
    archon_dialogue_manager = get_node_or_null("/root/ArchonDialogueManager")

    _setup_resource_rows()
    _setup_bars()
    _connect_tetrad_signals()
    call_deferred("_setup_uonite_button")
    call_deferred("_setup_dialogue")
    _connect_action_buttons()


# ==================================================
# DIALOGUE
# ==================================================
func _setup_dialogue() -> void:
    if not archon_dialogue_manager:
        push_warning("RootUI: ArchonDialogueManager not found")
        return

    var dialogue_base = "TopBandHBox/RightStackVBox/DialoguePanelContainer/DialogueMargin/DialogueVBox/"
    var label = get_node_or_null(dialogue_base + "ArchonDialogueRichTextLabel")
    if not label:
        push_warning("RootUI: ArchonDialogueRichTextLabel not found")
        return

    label.mouse_filter = Control.MOUSE_FILTER_IGNORE
    archon_dialogue_manager.set_display_nodes(label, null)
    archon_dialogue_manager.start_intro()

    var panel = get_node_or_null("TopBandHBox/RightStackVBox/DialoguePanelContainer")
    if panel:
        panel.mouse_filter = Control.MOUSE_FILTER_STOP
        if panel.gui_input.is_connected(_on_dialogue_panel_clicked):
            panel.gui_input.disconnect(_on_dialogue_panel_clicked)
        panel.gui_input.connect(_on_dialogue_panel_clicked)
        # TODO: convert to editor signal connection
    else:
        push_warning("RootUI: DialoguePanelContainer not found for click wiring")


func _on_dialogue_panel_clicked(event: InputEvent) -> void:
    if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
        if archon_dialogue_manager:
            archon_dialogue_manager.advance_dialogue()


func _check_monad_upgrade_trigger() -> void:
    if _monad_upgrade_triggered or not archon_dialogue_manager: return
    if not game_context.get_monad_total().is_zero():
        _monad_upgrade_triggered = true
        archon_dialogue_manager.enqueue_monad_upgrade()


func _check_tetrad_upgrade_trigger() -> void:
    if _tetrad_upgrade_triggered or not archon_dialogue_manager: return
    if not game_context.get_tetrad_total().is_zero():
        _tetrad_upgrade_triggered = true
        archon_dialogue_manager.enqueue_tetrad_upgrade()


# ==================================================
# DEV INPUT
# ==================================================
func _input(event: InputEvent) -> void:
    if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_TAB:
        if game_context:
            var chunk = BigNum.from_me(DEV_UONITE_CHUNK[0], DEV_UONITE_CHUNK[1])
            game_context.uonite = game_context.uonite.add(chunk)


# ==================================================
# TETRAD LABEL SIGNALS
# ==================================================
func _connect_tetrad_signals() -> void:
    _left_tetrad_label = find_child("LeftTetradLabel",          true, false)
    _middle_label      = find_child("Medials1SymmetricsLabel",  true, false)
    _medials2_label    = find_child("Medials2Label",            true, false)

    for label in [_left_tetrad_label, _middle_label, _medials2_label]:
        if label and label is RichTextLabel:
            label.mouse_filter = Control.MOUSE_FILTER_STOP
            var line_map = LEFT_LINE_MAP if label == _left_tetrad_label else \
                           MIDDLE_LINE_MAP if label == _middle_label else \
                           MEDIALS2_LINE_MAP
            if not label.gui_input.is_connected(_on_tetrad_label_gui_input):
                # TODO: convert to editor signal connection
                label.gui_input.connect(func(event): _on_tetrad_label_gui_input(event, label, line_map))


func _on_tetrad_label_gui_input(event: InputEvent, label: RichTextLabel, line_map: Array) -> void:
    if not event is InputEventMouseButton or event.button_index != MOUSE_BUTTON_LEFT or not event.pressed: return
    if not game_context or not game_context.purity_locks_unlocked: return
    var line_height = label.get_line_height(0)
    if line_height <= 0: return
    var line = clamp(int(event.position.y / line_height), 0, line_map.size() - 1)
    var key  = line_map[line]
    if key == "": return
    if key.begins_with("cat_"):
        game_context.toggle_category_lock(key)
    else:
        game_context.toggle_lock(key)


# ==================================================
# BUTTON CONNECTIONS
# ==================================================
func _connect_action_buttons() -> void:
    # TODO: convert all to editor signal connections
    _try_connect_button("SummonSparkButton",      "pressed", _on_summon_spark_pressed)
    _try_connect_button("MonadCompressButton",    "pressed", _on_monad_compress_pressed)
    _try_connect_button("IotaCompressButton",     "pressed", _on_iota_compress_pressed)
    _try_connect_button("ParticleCompressButton", "pressed", _on_particle_compress_pressed)
    _try_connect_button("CreateUoniteButton",     "pressed", _on_create_uonite_pressed)
    _try_connect_button("TetradAssembleButton",   "pressed", _on_tetrad_assemble_pressed)
    _try_connect_button("MoteAssembleButton",     "pressed", _on_mote_assemble_pressed)
    _try_connect_button("GrainAssembleButton",    "pressed", _on_grain_assemble_pressed)


func _try_connect_button(button_name: String, signal_name: String, callable: Callable) -> void:
    var button = find_child(button_name, true, false)
    if button:
        if button.has_signal(signal_name) and not button.is_connected(signal_name, callable):
            button.connect(signal_name, callable)
    else:
        push_warning("RootUI: Button not found: " + button_name)


func _try_connect(node_path: String, signal_name: String, callable: Callable) -> void:
    var node = get_node_or_null(node_path)
    if node:
        node.connect(signal_name, callable)
    else:
        push_warning("RootUI: could not find node at path: " + node_path)


# ==================================================
# BUTTON HANDLERS — delegate to ProductionManager
# ==================================================
func _on_summon_spark_pressed() -> void:
    if not production_manager: return
    production_manager.manual_summon_spark()
    _spawn_spark_effect()


func _on_monad_compress_pressed() -> void:
    if not production_manager: return
    if production_manager.manual_monad_compress():
        _check_monad_upgrade_trigger()


func _on_iota_compress_pressed() -> void:
    if not production_manager: return
    production_manager.manual_iota_compress()


func _on_particle_compress_pressed() -> void:
    if not production_manager: return
    production_manager.manual_particle_compress()


func _on_tetrad_assemble_pressed() -> void:
    if not production_manager: return
    if production_manager.manual_tetrad_assemble():
        _check_tetrad_upgrade_trigger()


func _on_mote_assemble_pressed() -> void:
    if not production_manager: return
    production_manager.manual_mote_assemble()


func _on_grain_assemble_pressed() -> void:
    if not production_manager: return
    production_manager.manual_grain_assemble()


func _on_create_uonite_pressed() -> void:
    if not production_manager: return
    production_manager.manual_create_uonite()


# ==================================================
# SPARK EFFECT
# ==================================================
func _spawn_spark_effect() -> void:
    var btn = get_node_or_null("TopBandHBox/LeftStackVBox/ClickSelectPanelContainer/ClickSelectMargin/ClickSelectVBox/SummonSparkButton")
    if not btn: return
    var canvas_layer = get_parent()
    if not canvas_layer: return
    var rng = RandomNumberGenerator.new()
    rng.randomize()
    var btn_rect = btn.get_global_rect()
    var origin   = Vector2(
        rng.randf_range(btn_rect.position.x, btn_rect.position.x + btn_rect.size.x),
        rng.randf_range(btn_rect.position.y, btn_rect.position.y + btn_rect.size.y))
    var effect = SPARK_EFFECT.instantiate()
    canvas_layer.add_child(effect)
    effect.launch(origin)


# ==================================================
# RESOURCE ROWS
# ==================================================
func _on_row_clicked(resource_key: String) -> void:
    if not game_context: return
    game_context.toggle_lock(resource_key)


func _setup_resource_rows() -> void:
    var rows = get_tree().get_nodes_in_group("resource_rows")
    for row in rows:
        match row.name:
            "RowSparksLabelInstance":    row.set_resource_key("sparks_label")
            "RowUonitesLabelInstance":   row.set_resource_key("uonites_label")
            "RowFociLabelInstance":      row.set_resource_key("foci_label")
            "RowVolitionsLabelInstance": row.set_resource_key("volitions_label")
            "RowSparksValueInstance":    row.set_resource_key("sparks_value")
            "RowUonitesValueInstance":   row.set_resource_key("uonites_value")
            "RowFociValueInstance":      row.set_resource_key("foci_value")
            "RowVolitionsValueInstance": row.set_resource_key("volitions_value")
            "RowSolidMonadInstance":     row.set_resource_key("monad_solid")
            "RowLiquidMonadInstance":    row.set_resource_key("monad_liquid")
            "RowGasMonadInstance":       row.set_resource_key("monad_gas")
            "RowIotaInstance":           row.set_resource_key("iota")
            "RowParticleInstance":       row.set_resource_key("particle")
            "RowMoteInstance":           row.set_resource_key("mote")
            "RowGrainInstance":          row.set_resource_key("grain")
            "RowUonitesInstance":        row.set_resource_key("uonites_wheel")
            "RowFociInstance":           row.set_resource_key("foci_wheel")
            "RowVolitionsInstance":      row.set_resource_key("volitions_wheel")
            _:
                row.set_label(row.name)
                row.set_resource_key(row.name)

    var lockable = ["sparks", "monad_solid", "monad_liquid", "monad_gas", "iota", "mote", "particle", "grain"]
    for row in get_tree().get_nodes_in_group("resource_rows"):
        if row.resource_key in lockable and not row.row_clicked.is_connected(_on_row_clicked):
            row.row_clicked.connect(_on_row_clicked)
            # TODO: convert to editor signal connection


# ==================================================
# PROCESS
# ==================================================
func _process(delta: float) -> void:
    if not game_context: return
    _time += delta
    _update_counters()
    _update_tetrad_display()
    _update_bars(delta)


# ==================================================
# COUNTERS
# ==================================================
func _update_counters() -> void:
    var rows = get_tree().get_nodes_in_group("resource_rows")
    for row in rows:
        match row.resource_key:
            "sparks_label":    row.set_label("[b]Sparks[/b]")
            "uonites_label":   row.set_label("[b]Uonites[/b]")
            "foci_label":      row.set_label("[b]Foci[/b]")
            "volitions_label": row.set_label("[b]Volitions[/b]")
            "sparks_value":    row.set_label(_fmt(game_context.sparks))
            "uonites_value":
                var u_assigned  = game_context.get_total_uonites_assigned()
                var u_available = game_context.uonite.sub(u_assigned)
                row.set_label(_fmt(u_available) + "/" + _fmt(game_context.uonite))
            "foci_value":
                var f_assigned  = game_context.get_total_foci_assigned()
                var f_available = max(0, game_context.archon_foci - f_assigned)
                row.set_label(str(f_available) + "/" + str(game_context.archon_foci))
            "volitions_value":
                var v_assigned  = game_context.get_total_volitions_assigned()
                var v_available = max(0, game_context.volitions - v_assigned)
                row.set_label(str(v_available) + "/" + str(game_context.volitions))
            "sparks":
                var locked = game_context.is_locked("sparks")
                row.set_label("[color=%s]Sparks: %s%s[/color]" % [
                    "#ffdd77" if locked else "#ffffff",
                    _fmt(game_context.sparks),
                    " 🔒" if locked else ""])
            "monad_solid":
                var locked = game_context.is_locked("monad_solid")
                row.set_label("[color=%s]Solid: %s%s[/color]" % [
                    "#ffdd77" if locked else "#ffffff",
                    _fmt(game_context.monad["solid"]),
                    " 🔒" if locked else ""])
            "monad_liquid":
                var locked = game_context.is_locked("monad_liquid")
                row.set_label("[color=%s]Liquid: %s%s[/color]" % [
                    "#ffdd77" if locked else "#ffffff",
                    _fmt(game_context.monad["liquid"]),
                    " 🔒" if locked else ""])
            "monad_gas":
                var locked = game_context.is_locked("monad_gas")
                row.set_label("[color=%s]Gas: %s%s[/color]" % [
                    "#ffdd77" if locked else "#ffffff",
                    _fmt(game_context.monad["gas"]),
                    " 🔒" if locked else ""])
            "iota":
                var locked = game_context.is_locked("iota")
                row.set_label("[color=%s]Iota: %s%s[/color]" % [
                    "#ffdd77" if locked else "#ffffff",
                    _fmt(game_context.iota),
                    " 🔒" if locked else ""])
            "mote":
                var locked = game_context.is_locked("mote")
                row.set_label("[color=%s]Mote: %s%s[/color]" % [
                    "#ffdd77" if locked else "#ffffff",
                    _fmt(game_context.mote),
                    " 🔒" if locked else ""])
            "particle":
                var locked = game_context.is_locked("particle")
                row.set_label("[color=%s]Particle: %s%s[/color]" % [
                    "#ffdd77" if locked else "#ffffff",
                    _fmt(game_context.particle),
                    " 🔒" if locked else ""])
            "grain":
                var locked = game_context.is_locked("grain")
                row.set_label("[color=%s]Grain: %s%s[/color]" % [
                    "#ffdd77" if locked else "#ffffff",
                    _fmt(game_context.grain),
                    " 🔒" if locked else ""])
    _update_uonite_icon()


# ==================================================
# FORMATTING
# ==================================================
func _fmt(value) -> String:
    if value == null:
        return "0"

    if value is BigNum:
        return _format_scientific_one_decimal(value)

    # Fallback for regular float/int
    if typeof(value) in [TYPE_FLOAT, TYPE_INT]:
        if abs(float(value)) >= 1e6 or abs(float(value)) <= 1e-4:
            return "%.1e" % float(value)
        return str(int(float(value)))

    return str(value)


func _format_scientific_one_decimal(value) -> String:
    if not value is BigNum:
        return "%.1e" % float(value)

    var s: String = value.to_display_string().to_lower()

    if "e" not in s:
        # No scientific notation — show as plain integer
        return str(int(value.to_float()))

    var parts = s.split("e")
    if parts.size() != 2:
        return s

    var mantissa = snapped(float(parts[0]), 0.1)
    return "%.1fe%s" % [mantissa, parts[1]]


func _fmt_float(value: float) -> String:
    if value <= 0.0: return "0"
    return _fmt(BigNum.from_float(value))


# ==================================================
# TETRAD DISPLAY
# ==================================================
func _build_category_header(category_name: String, category_key: String) -> String:
    var locked = game_context.is_category_locked(category_key)
    return "[color=%s][i]%s[/i][/color]%s" % [
        "#ffdd77" if locked else "#aaaaaa",
        category_name,
        " 🔒" if locked else ""]


func _build_tetrad_line(keys: Array) -> String:
    var parts = []
    for key in keys:
        var locked = game_context.is_locked(key)
        var color  = "#ffdd77" if locked else "#ffffff"
        var icon   = " 🔒" if locked else ""
        parts.append("[color=%s]%s:%s[/color]\n[color=%s]%s[/color]" % [
            color, TETRAD_NAMES[key], icon,
            color, _fmt(game_context.tetrad.get(key, BigNum.zero()))])
    return "\n".join(parts)


func _update_tetrad_display() -> void:
    if not game_context:
        return

    if _left_tetrad_label and _left_tetrad_label is RichTextLabel:
        var txt  = _build_category_header("Fundaments", "cat_fundament") + "\n"
        txt     += _build_tetrad_line(["adaemant", "aquae", "aethyr"]) + "\n\n"
        txt     += _build_category_header("Medials", "cat_medial") + "\n"
        txt     += _build_tetrad_line(["dirt", "sand"]) + "\n"
        _left_tetrad_label.bbcode_enabled = true
        _left_tetrad_label.bbcode_text    = txt

    if _middle_label and _middle_label is RichTextLabel:
        var txt  = _build_category_header("Elements", "cat_element") + "\n"
        txt     += _build_tetrad_line(["earth", "water", "air"]) + "\n\n"
        txt     += _build_category_header("Medials", "cat_medial") + "\n"
        txt     += _build_tetrad_line(["haze", "mist"]) + "\n"
        _middle_label.bbcode_enabled = true
        _middle_label.bbcode_text    = txt

    if _medials2_label and _medials2_label is RichTextLabel:
        var txt  = _build_category_header("Symmetrics", "cat_symmetric") + "\n"
        txt     += _build_tetrad_line(["mud", "dust", "cloud"]) + "\n\n"
        txt     += _build_category_header("Medials", "cat_medial") + "\n"
        txt     += _build_tetrad_line(["ooze", "foam"]) + "\n"
        _medials2_label.visible       = true
        _medials2_label.bbcode_enabled = true
        _medials2_label.bbcode_text   = txt


# ==================================================
# UONITE BUTTON ICON
# ==================================================
func _setup_uonite_button() -> void:
    var btn = get_node_or_null("CanvasLayer/RootUI/TopBandHBox/LeftStackVBox/CompressPanelContainer/CompressMargin/CompressVBox/CreateUoniteButton")
    if not btn: return
    var btn_label = btn.get_node_or_null("ButtonLabelInstance")
    if not btn_label: return

    var icon_rect = TextureRect.new()
    icon_rect.name                  = "UoniteIconRect"
    icon_rect.custom_minimum_size   = Vector2(32, 32)
    icon_rect.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
    icon_rect.stretch_mode          = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
    icon_rect.mouse_filter          = Control.MOUSE_FILTER_IGNORE
    icon_rect.expand_mode           = TextureRect.EXPAND_IGNORE_SIZE

    if game_data:
        var icon_path = game_data.RESOURCES.get("uonite", {}).get("icon", "")
        if icon_path != "" and ResourceLoader.exists(icon_path):
            icon_rect.texture = load(icon_path)

    var mat = ShaderMaterial.new()
    mat.shader = UONITE_FILL_SHADER
    mat.set_shader_parameter("fill_amount", 0.0)
    mat.set_shader_parameter("time_offset", 0.0)
    icon_rect.material    = mat
    _uonite_icon_material = mat
    btn_label.add_child(icon_rect)


func _update_uonite_icon() -> void:
    if not _uonite_icon_material or not game_context: return
    _uonite_icon_time += get_process_delta_time()
    var grain_val = game_context.grain.to_float() if not game_context.grain.is_zero() else 0.0
    var fill      = clamp(grain_val / float(UONITE_GRAIN_COST), 0.0, 1.0)
    _uonite_icon_material.set_shader_parameter("fill_amount", fill)
    _uonite_icon_material.set_shader_parameter("time_offset", _uonite_icon_time)


# ==================================================
# BARS
# ==================================================
func _setup_bars() -> void:
    bars.clear()
    _bar_smoothed_rates.clear()
    var resources = ["sparks", "monad", "tetrad", "iota", "mote", "particle", "grain", "uonite"]

    for res in resources:
        var gen_bar = find_child(res.capitalize() + "GenBar", true, false)
        if gen_bar:
            var gen_lbl = _make_or_get_overlay_label(gen_bar, res.capitalize() + "GenLabel")
            bars[res] = {"gen_bar": gen_bar, "gen_lbl": gen_lbl}
            gen_bar.max_value = 100.0
            gen_bar.min_value = 0.0
            _bar_smoothed_rates[res] = 0.0
        else:
            push_warning("RootUI: Missing GenBar for " + res)


func _make_or_get_overlay_label(bar: ProgressBar, label_name: String) -> Label:
    var lbl = bar.get_node_or_null(label_name)
    if lbl:
        return lbl
    lbl = Label.new()
    lbl.name                = label_name
    lbl.set_anchors_preset(Control.PRESET_FULL_RECT)
    lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    lbl.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
    lbl.mouse_filter         = Control.MOUSE_FILTER_IGNORE
    lbl.add_theme_color_override("font_color", BAR_LABEL_COLOR)
    lbl.add_theme_font_size_override("font_size", BAR_LABEL_FONT_SIZE)
    lbl.clip_text = true
    bar.add_child(lbl)
    return lbl


func _update_bars(delta: float) -> void:
    if not game_context or bars.is_empty():
        return

    var assigned = {
        "sparks":   game_context.get_operation_total_bignum("sparks_summon").to_float(),
        "monad":    game_context.get_operation_total_bignum("monad_compress").to_float(),
        "tetrad":   game_context.get_operation_total_bignum("tetrad_assemble").to_float(),
        "iota":     game_context.get_operation_total_bignum("iota_compress").to_float(),
        "mote":     game_context.get_operation_total_bignum("mote_assemble").to_float(),
        "particle": game_context.get_operation_total_bignum("particle_compress").to_float(),
        "grain":    game_context.get_operation_total_bignum("grain_assemble").to_float(),
        "uonite":   0.0,
    }

    var per_tick = {
        "sparks":   game_context.rates["sparks_summon"].to_float(),
        "monad":    game_context.rates["monad_compress"].to_float(),
        "tetrad":   game_context.rates["tetrad_assemble"].to_float(),
        "iota":     game_context.rates["iota_compress"].to_float(),
        "mote":     game_context.rates["mote_assemble"].to_float(),
        "particle": game_context.rates["particle_compress"].to_float(),
        "grain":    game_context.rates["grain_assemble"].to_float(),
        "uonite":   100.0,  # DEV HACK: matches manual_create_uonite
    }

    var smooth_factor = 1.0 - exp(-BAR_SMOOTH_RATE * delta)

    for res in bars:
        var data    = bars[res]
        var gen_bar: ProgressBar = data["gen_bar"]
        var gen_lbl: Label       = data["gen_lbl"]

        var assign_f: float = assigned.get(res, 0.0)
        var rate_f:   float = per_tick.get(res, 0.0)

        # Exponential smoothing toward actual rate
        var smoothed: float = _bar_smoothed_rates.get(res, 0.0)
        smoothed = smoothed + smooth_factor * (rate_f - smoothed)
        _bar_smoothed_rates[res] = smoothed

        # Efficiency: actual production vs assigned workers
        var efficiency: float = 0.0
        if assign_f > 0.0:
            efficiency = smoothed / assign_f

        gen_bar.value = clamp(efficiency * 100.0, 0.0, 100.0)

        # Accent color from GameData
        var base_color: Color = Color.WHITE
        if game_data:
            base_color = Color.from_string(
                game_data.RESOURCES.get(res, {}).get("color", "#ffffff"),
                Color.WHITE)

        # Flash when over-provisioned
        if efficiency >= BAR_FLASH_THRESHOLD and assign_f > 0.0:
            var flash       = sin(_time * BAR_FLASH_SPEED * TAU) * 0.5 + 0.5
            var flash_color = base_color.lerp(Color.WHITE, flash * 0.6)
            gen_bar.add_theme_stylebox_override("fill", _make_bar_fill_style(flash_color))
        else:
            gen_bar.add_theme_stylebox_override("fill", _make_bar_fill_style(base_color))

        # Label: "assigned    rate"
        var assign_str: String
        if res == "uonite":
            assign_str = "—"
        else:
            assign_str = _fmt(game_context.get_operation_total_bignum(_res_to_op(res)))
        var rate_str = _fmt(BigNum.from_float(smoothed)) if smoothed > 0.0 else "0"
        gen_lbl.text = "%s    %s" % [assign_str, rate_str]


func _make_bar_fill_style(color: Color) -> StyleBoxFlat:
    # TODO: cache one StyleBoxFlat per resource to avoid per-frame allocation
    var s = StyleBoxFlat.new()
    s.bg_color                   = color
    s.corner_radius_top_left     = 2
    s.corner_radius_top_right    = 2
    s.corner_radius_bottom_left  = 2
    s.corner_radius_bottom_right = 2
    return s


func _res_to_op(res: String) -> String:
    match res:
        "sparks":   return "sparks_summon"
        "monad":    return "monad_compress"
        "tetrad":   return "tetrad_assemble"
        "iota":     return "iota_compress"
        "mote":     return "mote_assemble"
        "particle": return "particle_compress"
        "grain":    return "grain_assemble"
    return ""


# ==================================================
# SAVE / LOAD
# ==================================================
func save_game() -> void:
    if save_manager and save_manager.has_method("save_game"):
        save_manager.save_game()


func load_game() -> void:
    if save_manager and save_manager.has_method("load_game"):
        save_manager.load_game()
