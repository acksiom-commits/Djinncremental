extends VBoxContainer
# ================= WILL / FORM PRODUCTION SWITCH =================
# Reusable overlay for the button that toggles which Iota/Mote branch is
# active -- Will (Uonite branch) or Form (Grain branch). Instance
# WillFormSwitch.tscn inside a Button node, same pattern ButtonLabel.tscn
# already uses: every child here has mouse_filter = IGNORE, so a click
# ANYWHERE on the parent Button -- including over the CREATE bar at the
# top, not just the WILL/FORM boxes -- reaches the Button and toggles it.
#
# Scope (2026-09-30): this is a VISUAL/STATE toggle only. It reads and
# writes GameContext.will_form_switch_is_will and lights the matching box,
# but nothing downstream reacts to that flag yet -- wiring it to actually
# swap which recipe IotaAssembleButton/MoteCompressButton run, the
# Compress/Assemble mini-icons, and the Create Uonite/Assemble Grains
# button+display swap are separate, not-yet-built to-do items.
#
# Scene structure:
#   WillFormSwitchInstance (VBoxContainer) — this script
#       CreateBar (Label)                  — "CREATE", plain white
#       ChoiceRow (HBoxContainer)
#           WillBox (Panel) > WillLabel (Label)  — "WILL"
#           FormBox (Panel) > FormLabel (Label)  — "FORM"
#
# Plain Label, not RichTextLabel (2026-09-30): RichTextLabel has no
# vertical-alignment property at all, so its text always sat at the top
# of whatever box height CreateBar/WillBox/FormBox were given. Label has
# native vertical_alignment/horizontal_alignment (same pattern already
# used elsewhere in this project, e.g. NamePickerCurrentLabel), which
# centers correctly regardless of box size with no extra wrapper nodes.
# Trade-off: Label has no bbcode, so the [b] bold tag is gone -- this
# project has no custom bold-font theme to fall back on, so these rely on
# ALL-CAPS + size + color for visual weight instead of true bold weight.

# Matches button_label.gd's TOP_FONT_SIZE/BOTTOM_FONT_SIZE (2026-10-01) --
# CREATE parallels its action-line (e.g. "Compress"/"Assemble"), WILL/FORM
# parallel its resource-name line (e.g. "Monad"/"Tetrad"), so this button's
# text now reads at the same size as every other Compress/Assemble button
# instead of its own separately-tuned size.
const CREATE_FONT_SIZE: int = 20
const CHOICE_FONT_SIZE: int = 16

# CreateBar's own custom_minimum_size (set in WillFormSwitch.tscn, 41px) is
# a SEPARATE number from these font sizes, deliberately -- the first pass
# left CreateBar sized purely from its own RichTextLabel content (no
# explicit minimum), which left WILL/FORM taking the lion's share of the
# button and reading as too tall/awkward. The .tscn's 41px keeps CreateBar
# at roughly its original ~45% share of the button's height (24 of 55,
# scaled to the new 93px total), with ChoiceRow (size_flags_vertical=
# EXPAND_FILL) absorbing the rest -- so resizing the button again later
# means updating that number too, not just these font sizes.

# Darkened state is the SAME resource color, just dimmed -- not a generic
# grey -- so the inactive side still reads as "this one, turned down"
# rather than "disabled".
const DIM_BRIGHTNESS: float = 0.22

@onready var create_bar: Label = $CreateBar
@onready var choice_row: HBoxContainer = $ChoiceRow
@onready var will_box: Panel = $ChoiceRow/WillBox
@onready var will_label: Label = $ChoiceRow/WillBox/WillLabel
@onready var form_box: Panel = $ChoiceRow/FormBox
@onready var form_label: Label = $ChoiceRow/FormBox/FormLabel

var _will_style_lit: StyleBoxFlat
var _will_style_dim: StyleBoxFlat
var _form_style_lit: StyleBoxFlat
var _form_style_dim: StyleBoxFlat
var _will_text: String = "WILL"
var _form_text: String = "FORM"


func _ready() -> void:
    mouse_filter = Control.MOUSE_FILTER_IGNORE
    set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    add_theme_constant_override("separation", 2)

    _setup_label(create_bar, CREATE_FONT_SIZE)
    create_bar.text = "CREATE"

    choice_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
    choice_row.add_theme_constant_override("separation", 2)

    _setup_box(will_box, will_label, "WILL", "uonite")
    _setup_box(form_box, form_label, "FORM", "grain")

    var parent: Node = get_parent()
    if parent is BaseButton:
        parent.pressed.connect(_on_parent_pressed)

    _refresh()


func _setup_label(lbl: Label, font_size: int) -> void:
    lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    lbl.autowrap_mode = TextServer.AUTOWRAP_OFF
    lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
    lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    lbl.add_theme_font_size_override("font_size", font_size)


func _setup_box(box: Panel, lbl: Label, text: String, resource_key: String) -> void:
    box.mouse_filter = Control.MOUSE_FILTER_IGNORE
    box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    _setup_label(lbl, CHOICE_FONT_SIZE)
    lbl.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    # Text itself (not its color) is set once here -- "WILL"/"FORM" never
    # change. Color DOES change, in _refresh(), since it has to track
    # whichever background (lit or dim) is currently showing.
    if resource_key == "uonite":
        _will_text = text
    else:
        _form_text = text

    var game_data = get_node_or_null("/root/GameData")
    var color_str: String = "#ffffff"
    if game_data:
        color_str = game_data.RESOURCES.get(resource_key, {}).get("color", "#ffffff")
    var base_color := Color(color_str)

    var lit := StyleBoxFlat.new()
    lit.bg_color = base_color
    lit.corner_radius_top_left = 3
    lit.corner_radius_top_right = 3
    lit.corner_radius_bottom_left = 3
    lit.corner_radius_bottom_right = 3

    var dim := StyleBoxFlat.new()
    dim.bg_color = Color(base_color.r * DIM_BRIGHTNESS, base_color.g * DIM_BRIGHTNESS, base_color.b * DIM_BRIGHTNESS, base_color.a)
    dim.corner_radius_top_left = 3
    dim.corner_radius_top_right = 3
    dim.corner_radius_bottom_left = 3
    dim.corner_radius_bottom_right = 3

    if resource_key == "uonite":
        _will_style_lit = lit
        _will_style_dim = dim
    else:
        _form_style_lit = lit
        _form_style_dim = dim


func _on_parent_pressed() -> void:
    var gc = get_node_or_null("/root/GameContext")
    if not gc:
        return
    gc.toggle_will_form_switch()
    if gc.has_method("save_game"):
        gc.save_game()
    _refresh()


## Picks black or white text by the ACTUAL brightness of the background
## it's sitting on, not by which side (Will/Form) or state (lit/dim) it is
## -- reported 2026-09-30: white-on-white-ish gold (Will, lit) was nearly
## unreadable, and hardcoding "dark text when lit" instead would have been
## just as wrong for Form (its lit purple is dark enough that WHITE text is
## the readable choice there). Standard perceived-brightness weighting
## (human eyes are far more sensitive to green than red or blue), matching
## the usual YIQ-style threshold.
func _readable_text_color(bg: Color) -> Color:
    var brightness: float = bg.r * 0.299 + bg.g * 0.587 + bg.b * 0.114
    return Color.BLACK if brightness > 0.5 else Color.WHITE


func _apply_box_text(lbl: Label, text: String, bg: Color) -> void:
    lbl.text = text
    lbl.add_theme_color_override("font_color", _readable_text_color(bg))


func _refresh() -> void:
    if not is_node_ready():
        return
    var gc = get_node_or_null("/root/GameContext")
    var is_will: bool = true if not gc else gc.will_form_switch_is_will
    var will_style: StyleBoxFlat = _will_style_lit if is_will else _will_style_dim
    var form_style: StyleBoxFlat = _form_style_dim if is_will else _form_style_lit
    will_box.add_theme_stylebox_override("panel", will_style)
    form_box.add_theme_stylebox_override("panel", form_style)
    _apply_box_text(will_label, _will_text, will_style.bg_color)
    _apply_box_text(form_label, _form_text, form_style.bg_color)
