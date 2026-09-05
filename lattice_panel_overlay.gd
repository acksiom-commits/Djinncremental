extends Control
# ============= LATTICE PANEL OVERLAY v1.0.0 =============
# Full-screen study panel for archai_lattice.gd, structurally mirroring
# ConstellationStudyOverlay.tscn / constellation_study_overlay.gd (backdrop
# + centred fixed-size PanelContainer, opened via find_child lookup from a
# plain button, closed via CloseButton / ESCAPE / click-outside). Replaces
# the old small inline viewer that used to squat in the Archon dialogue box
# at 220x220 -- too small to read the cavity-fill detail added alongside
# this panel.
#
# "Closed" means OFF, not merely hidden, same principle the old inline
# wrapper (archai_lattice_panel.gd) already established: a hidden
# SubViewportContainer still renders its SubViewport, and the lattice's own
# _process still re-deforms every curve point regardless of visibility. So
# closing disables the viewport's update mode and the lattice's processing,
# not just this Control's own `visible`.

const PANEL_PATH := "CenterContainer/PanelContainer"
const CONTROLS_PATH := PANEL_PATH + "/OuterMargin/OuterVBox/ControlsRow"
const VIEWPORT_PATH := PANEL_PATH + "/OuterMargin/OuterVBox/ViewportContainer"

@onready var _close_btn: Button = get_node(PANEL_PATH + "/OuterMargin/OuterVBox/HeaderHBox/CloseButton")
@onready var _pause_btn: CheckButton = get_node(CONTROLS_PATH + "/PauseToggle")
@onready var _straight_btn: CheckButton = get_node(CONTROLS_PATH + "/StraightToggle")
@onready var _cavity_btn: CheckButton = get_node(CONTROLS_PATH + "/CavityFillToggle")
@onready var _extra_btn: CheckButton = get_node(CONTROLS_PATH + "/ExtraCentroidToggle")
@onready var _viewport: SubViewport = get_node(VIEWPORT_PATH + "/LatticeViewport")
@onready var _lattice: MeshInstance3D = get_node(VIEWPORT_PATH + "/LatticeViewport/ArchaiLattice")


func _ready() -> void:
    visible = false
    _close_btn.pressed.connect(_on_close)

    _pause_btn.button_pressed = not bool(_lattice.get("rotating"))
    _straight_btn.button_pressed = bool(_lattice.get("straight_lines"))
    _cavity_btn.button_pressed = bool(_lattice.get("show_cavity_fill"))
    _extra_btn.button_pressed = bool(_lattice.get("show_extra_centroid_edges"))
    _pause_btn.toggled.connect(func(paused: bool) -> void: _lattice.set("rotating", not paused))
    _straight_btn.toggled.connect(func(pressed: bool) -> void: _lattice.set("straight_lines", pressed))
    _cavity_btn.toggled.connect(func(pressed: bool) -> void: _lattice.set("show_cavity_fill", pressed))
    _extra_btn.toggled.connect(func(pressed: bool) -> void: _lattice.set("show_extra_centroid_edges", pressed))

    _apply_processing(false)


func open() -> void:
    visible = true
    _apply_processing(true)


func _on_close() -> void:
    visible = false
    _apply_processing(false)


func _apply_processing(on: bool) -> void:
    _viewport.render_target_update_mode = \
        SubViewport.UPDATE_ALWAYS if on else SubViewport.UPDATE_DISABLED
    _lattice.set_process(on)


func _input(event: InputEvent) -> void:
    if not visible:
        return

    if event is InputEventKey and (event as InputEventKey).pressed \
            and (event as InputEventKey).keycode == KEY_ESCAPE:
        _on_close()
        get_viewport().set_input_as_handled()
        return

    if event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
        var mbe := event as InputEventMouseButton
        var panel_rect: Rect2 = get_node(PANEL_PATH).get_global_rect()
        if not panel_rect.has_point(mbe.global_position):
            _on_close()
            get_viewport().set_input_as_handled()
