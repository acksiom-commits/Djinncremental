extends HBoxContainer
# ================= RESOURCE ROW LABEL v1.0.0 =================
# Simple static label row for display names.
# Use in scene tree where a plain non-BBCode label is needed,
# e.g. "Uonites", "Foci", "Volitions" in the allocation wheel.
# Text set via Inspector on the Label node directly.
# No dynamic updates, no resource key, no locking.

@onready var label_node: Label = $LabelResource


func set_text(text: String) -> void:
    if label_node:
        label_node.text = text
