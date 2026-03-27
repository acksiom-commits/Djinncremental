extends VBoxContainer
# ================= BUTTON LABEL v1.1.0 =================
# Reusable two-line button label for action buttons.
# Instance ButtonLabel.tscn inside any Button node.
#
# Set resource_key in the Inspector to the matching
# RESOURCES key (e.g. "sparks", "monad", "tetrad").
# All text and color is looked up from GameData automatically.
#
# Scene structure:
#   ButtonLabel (VBoxContainer) — this script
#       TopLabel (RichTextLabel)     — first line, plain white
#       BottomLabel (RichTextLabel)  — second line, resource color

@export var resource_key: String = "":
    set(v):
        resource_key = v
        _refresh()

@onready var top_label: RichTextLabel = $TopLabel
@onready var bottom_label: RichTextLabel = $BottomLabel


func _ready() -> void:
    mouse_filter = Control.MOUSE_FILTER_IGNORE
    set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    alignment = BoxContainer.ALIGNMENT_CENTER
    add_theme_constant_override("separation", 0)
    _setup_label(top_label, 20)
    _setup_label(bottom_label, 16)
    _refresh()


func _setup_label(lbl: RichTextLabel, font_size: int) -> void:
    lbl.bbcode_enabled = true
    lbl.fit_content = true
    lbl.scroll_active = false
    lbl.autowrap_mode = TextServer.AUTOWRAP_OFF
    lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
    lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    lbl.add_theme_font_size_override("normal_font_size", font_size)


func _refresh() -> void:
    if not is_node_ready():
        return

    var game_data = get_node_or_null("/root/GameData")
    if not game_data:
        return

    # Look up this button's text using the parent Button node's name
    var parent: Node = get_parent()
    var btn_name: String = String(parent.name) if parent != null else ""
    var lines: Array = game_data.BUTTON_LABELS.get(btn_name, ["", ""])
    var top_text: String = lines[0]
    var bottom_text: String = lines[1]

    # Look up color from RESOURCES using resource_key
    var color: String = "#ffffff"
    if resource_key != "":
        color = game_data.RESOURCES.get(resource_key, {}).get("color", "#ffffff")

    # Top line — plain white, no color override
    if top_text == "":
        top_label.hide()
    else:
        top_label.show()
        top_label.set("bbcode_text", "[center][b]%s[/b][/center]" % top_text)

    # Bottom line — resource color
    bottom_label.set("bbcode_text",
        "[center][b][color=%s]%s[/color][/b][/center]" % [color, bottom_text])
