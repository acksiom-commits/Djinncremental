extends Node
## The Allocation Wheel and Kaleb's command stack share one slot of the
## Primordial page, one shown at a time (author, 2026-11-07: the stack moves
## out of the Journal to "a cycling display alternating with the Allocation
## Wheel"). Each shows a button that switches to the other, so the player never
## has to leave the surface they are working on (CLAUDE.md, "reduce menu
## switching"); both call the one handler, show_stack().
##
## Made by root_ui.gd _setup_kaleb(). The stack takes the wheel's place in its
## container, at the wheel's size, so what sits under the slot (the
## Constellation panel) doesn't move. Which one is showing isn't saved: the
## page opens on the wheel.

const SLOT_SIZE := Vector2(375, 450)

var gc: Node = null
var wheel: Control = null
var view: Control = null
var _wheel_btn: Button = null   # on the wheel: switch to the stack
var _showing_stack: bool = false


func setup(game_context: Node, wheel_node: Control, stack_view: Control) -> void:
    gc = game_context
    wheel = wheel_node
    view = stack_view
    var holder: Node = wheel.get_parent()
    holder.add_child(view)
    holder.move_child(view, wheel.get_index() + 1)
    view.custom_minimum_size = SLOT_SIZE
    view.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
    view.size_flags_horizontal = Control.SIZE_FILL

    _wheel_btn = Button.new()
    _wheel_btn.text = "Stack"
    _wheel_btn.focus_mode = Control.FOCUS_NONE
    _wheel_btn.tooltip_text = "Show Kaleb's command stack in place of the wheel"
    _wheel_btn.add_theme_font_size_override("font_size", 14)
    wheel.add_child(_wheel_btn)
    _wheel_btn.set_anchors_preset(Control.PRESET_TOP_RIGHT)
    _wheel_btn.offset_left = -78.0
    _wheel_btn.offset_right = -4.0
    _wheel_btn.offset_top = 4.0
    _wheel_btn.offset_bottom = 28.0
    _wheel_btn.grow_horizontal = Control.GROW_DIRECTION_BEGIN
    _wheel_btn.pressed.connect(show_stack.bind(true))

    if view.has_signal("wheel_requested"):
        view.connect("wheel_requested", show_stack.bind(false))
    show_stack(false)


## Shows the stack (true) or the wheel (false). The one handler behind both
## switch buttons.
func show_stack(on: bool) -> void:
    _showing_stack = on
    wheel.visible = not on
    view.visible = on


func is_showing_stack() -> bool:
    return _showing_stack


## The wheel's button says whether Kaleb is running, since the stack is out of
## sight while the wheel shows.
func _process(_delta: float) -> void:
    if gc == null or _wheel_btn == null or not wheel.visible:
        return
    var running: bool = bool(gc.kaleb_running)
    # Running but waiting for The Djinn's Tier 1 (author, 2026-11-10): no ▶,
    # since nothing is being done yet.
    _wheel_btn.text = "Stack ▶" if running and gc.kaleb_djinn_ready() else "Stack"
