extends HBoxContainer
# ================= RESOURCE ROW v0.9.0 =================
# v0.9.0: Replaced [url] meta_clicked lock interaction with
#         gui_input signal on the row itself. This avoids
#         RichTextLabel wiping theme URL style overrides on
#         every BBCode re-parse. Lock toggle is now driven by
#         row_clicked signal, connected in root_ui.gd.
#         Mouse filter set to STOP on label so clicks register.
# v0.8.0: Clean counter row. SpinBox removed.

signal row_clicked(resource_key: String)

@onready var label_node: RichTextLabel = $ResourceLabel

var display_label: String = ""
var resource_key: String = ""


func _ready() -> void:
    if not is_in_group("resource_rows"):
        add_to_group("resource_rows")
    if label_node:
        label_node.bbcode_enabled = true
        label_node.set("bbcode_text", display_label)
        label_node.autowrap_mode = TextServer.AUTOWRAP_OFF
        label_node.fit_content = true
        label_node.scroll_active = false
        # Allow this node to receive mouse input for click detection
        label_node.mouse_filter = Control.MOUSE_FILTER_STOP
        label_node.gui_input.connect(_on_label_gui_input)
    else:
        push_warning("ResourceLabel node not found in ResourceRow: " + str(self.name))


func _on_label_gui_input(event: InputEvent) -> void:
    if event is InputEventMouseButton:
        if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
            if resource_key != "":
                emit_signal("row_clicked", resource_key)


func set_label(text: String) -> void:
    display_label = text
    if label_node:
        label_node.set("bbcode_text", display_label)


func set_resource_key(key: String) -> void:
    resource_key = key
