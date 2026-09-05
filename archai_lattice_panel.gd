extends Button
# ============= ARCHAI LATTICE OPEN BUTTON v2.0.0 =============
# Opens the LatticePanel study overlay -- mirrors constellation_panel.gd's
# StudyButton exactly: a plain button that looks up the overlay by name at
# click time rather than holding a direct reference, so this button and the
# overlay it opens don't need to live under the same parent.
#
# Replaces the old inline 220x220 SubViewport (archai_lattice_panel.gd
# v1.0.0, a VBoxContainer wrapping a small always-embedded viewer) -- too
# small to read the cavity-fill detail once that was added. The lattice
# geometry and its Pause/Straight-lines/Cavity-fill controls now live
# entirely in LatticePanel.tscn / lattice_panel_overlay.gd.


func _ready() -> void:
	pressed.connect(_on_pressed)


func _on_pressed() -> void:
	var panel := get_tree().root.find_child("LatticePanel", true, false)
	if panel and panel.has_method("open"):
		panel.open()
