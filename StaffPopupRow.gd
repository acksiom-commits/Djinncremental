class_name StaffPopupRow
extends HBoxContainer

# Shared puzzle-state color palette — see puzzle_state_colors.gd. Used as
# the default value for label_color/count_color below, and directly in
# set_visual_state() for the confirmed/eliminated/soft-eliminated/protected
# states — the same colors constellation_puzzle_widgets.gd etc. use.
const STATE_COLORS: PuzzleStateColors = preload("res://puzzle_state_colors.tres")

## Emitted when the checkmark button is pressed.
signal check_pressed
## Emitted when the X button is pressed.
signal x_pressed
## Emitted on right-click anywhere on the row (for protect toggle).
signal row_right_clicked

@export var label_text: String = "":
    set(value):
        label_text = value
        if _label:
            _label.text = value

@export var show_count: bool = false:
    set(value):
        show_count = value
        if _count_label:
            _count_label.visible = value

@export var count_value: int = 0:
    set(value):
        count_value = value
        if _count_label:
            _count_label.text = "(%d)" % value

@export var label_color: Color = STATE_COLORS.neutral:
    set(value):
        label_color = value
        if _label:
            _label.add_theme_color_override("font_color", value)

@export var label_font_size: int = 13:
    set(value):
        label_font_size = value
        if _label:
            _label.add_theme_font_size_override("font_size", value)

@export var count_font_size: int = 11:
    set(value):
        count_font_size = value
        if _count_label:
            _count_label.add_theme_font_size_override("font_size", value)

@export var count_color: Color = STATE_COLORS.muted:
    set(value):
        count_color = value
        if _count_label:
            _count_label.add_theme_color_override("font_color", value)

@export var button_font_size: int = 14:
    set(value):
        button_font_size = value
        if _btn_check:
            _btn_check.add_theme_font_size_override("font_size", value)
        if _btn_x:
            _btn_x.add_theme_font_size_override("font_size", value)

@onready var _label: Label = %Label
@onready var _count_label: Label = %CountLabel
@onready var _btn_check: Button = %BtnCheck
@onready var _btn_x: Button = %BtnX

## Stores visual state set before _ready() completes.
var _pending_state: int = -1


func _ready() -> void:
    # .pressed for left-click (Button's own signal for it), gui_input
    # scoped to the checkmark only for right-click (protect toggle) —
    # matches the original pre-componentization code. Note for anyone
    # debugging input here again: Control._call_gui_input() runs the
    # virtual _gui_input() override before emitting the public `gui_input`
    # signal, and skips the signal entirely if the override already marked
    # the event handled — BaseButton's own override does that for
    # left-click as part of implementing .pressed, so the `gui_input`
    # SIGNAL will never fire for left-click on a Button. Relying on it for
    # left-click is a dead end; this was investigated at length before the
    # actual bug (a separate signal/handler argument-count mismatch) was
    # found in constellation_study_overlay.gd.
    _btn_check.pressed.connect(func(): check_pressed.emit())
    _btn_x.pressed.connect(func(): x_pressed.emit())
    _btn_check.gui_input.connect(_on_check_gui_input)
    # Apply exported values — only override .tscn defaults when explicitly set.
    if label_text != "Label":
        _label.text = label_text
    _label.add_theme_color_override("font_color", label_color)
    if label_font_size != 13:
        _label.add_theme_font_size_override("font_size", label_font_size)
    _count_label.visible = show_count
    if count_value != 0:
        _count_label.text = "(%d)" % count_value
    if count_font_size != 11:
        _count_label.add_theme_font_size_override("font_size", count_font_size)
    _count_label.add_theme_color_override("font_color", count_color)
    if button_font_size != 14:
        _btn_check.add_theme_font_size_override("font_size", button_font_size)
        _btn_x.add_theme_font_size_override("font_size", button_font_size)
    # Apply any visual state that was set before nodes were ready.
    if _pending_state >= 0:
        set_visual_state(_pending_state)
        _pending_state = -1


func set_visual_state(state: int) -> void:
    # Defer if nodes aren't ready yet.
    if not _label:
        _pending_state = state
        return
    # States: 0=unchecked, 1=selected(check), 2=eliminated(X), 4=protected(magenta)
    match state:
        0:  # Unchecked / neutral
            _label.add_theme_color_override("font_color", label_color)
            _btn_check.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5, 1))
            _btn_x.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5, 1))
            _btn_check.disabled = false
            _btn_x.disabled = false
        1:  # Selected (check)
            _label.add_theme_color_override("font_color", STATE_COLORS.confirmed)
            _btn_check.add_theme_color_override("font_color", STATE_COLORS.confirmed)
            _btn_x.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5, 1))
            _btn_check.disabled = false
            _btn_x.disabled = false
        2:  # Eliminated (X)
            _label.add_theme_color_override("font_color", STATE_COLORS.eliminated)
            _btn_check.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5, 1))
            _btn_x.add_theme_color_override("font_color", STATE_COLORS.eliminated)
            _btn_check.disabled = false
            _btn_x.disabled = false
        3:  # Soft-eliminated (a sibling value on this row is protected) —
            # dimmer than a hard X, distinguishing "leaning eliminated" from
            # a confirmed one.
            _label.add_theme_color_override("font_color", STATE_COLORS.soft_eliminated)
            _btn_check.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5, 1))
            _btn_x.add_theme_color_override("font_color", Color(1.0, 0.6, 0.5, 1.0))
            _btn_check.disabled = false
            _btn_x.disabled = false
        4:  # Protected (magenta)
            _label.add_theme_color_override("font_color", STATE_COLORS.protected)
            _btn_check.add_theme_color_override("font_color", STATE_COLORS.protected)
            _btn_x.add_theme_color_override("font_color", STATE_COLORS.protected)
            _btn_check.disabled = false
            _btn_x.disabled = false
        _:  # Fallback to neutral
            set_visual_state(0)


func _on_check_gui_input(event: InputEvent) -> void:
    # Checkmark only — protect/"still possible" toggle never applied to the
    # X button, matching the original pre-componentization behavior.
    if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
        row_right_clicked.emit()
        get_viewport().set_input_as_handled()
