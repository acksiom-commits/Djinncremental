extends "res://dev_tests/test_base.gd"
# Create Grain button + cap bar + lattice display + counter (2026-10-01) --
# the Grain-branch substitute for Create Uonite's button/cap bar/
# icosahedron display, shown in place of it whenever the WILL/FORM switch
# is on FORM. Infrastructure only (per the user's own explicit scope call):
# this does NOT test live production flow through Iota/Mote recipes, only
# that the UI wiring itself -- node structure, visibility toggling, button
# connection, tooltip/counter registration -- is correct. The underlying
# math (get_grain_storage_cap/get_grain_progress/manual_create_grain) is
# covered separately in test_grain_storage_cap.gd.
#
# What must hold:
#  - Every new node exists in RootUI.tscn with the right structure.
#  - At the default (WILL) state, the Uonite cluster is visible and the
#    Grain cluster is hidden; toggling the switch swaps that exactly.
#  - The pre-existing Uonite counter in DirectReadouts is left untouched
#    by the toggle (it's a shared multi-resource panel, not swapped).
#  - CreateGrainButton is actually connected to a handler (not a dead
#    button) and registered for tooltips.
#  - RowGrainCounterInstance resolves to the generic "grain" resource_key
#    and produces a real, non-empty label once counters are updated.

var fails: int = 0


func ok(c: bool, s: String) -> void:
	if c:
		print("  PASS  ", s)
	else:
		print("  FAIL  ", s)
		fails += 1


func run() -> void:
	await process_frame

	var scene_root = load("res://RootUI.tscn").instantiate()
	root.add_child(scene_root)
	await process_frame
	# The scene's top-level node is a bare Node2D -- root_ui.gd's script
	# lives on the nested "RootUI" VBoxContainer (CanvasLayer/RootUI), not
	# the scene root. find_child() for plain node lookups works on either
	# (it recurses through all descendants regardless), but calling the
	# script's own functions/properties needs the actual scripted node.
	var root_ui = scene_root.find_child("RootUI", true, false)
	ok(root_ui != null, "sanity: the RootUI-scripted node itself is reachable")

	var gc = root.get_node_or_null("/root/GameContext")
	ok(gc != null, "sanity: GameContext autoload is reachable")
	if not gc or not root_ui:
		scene_root.queue_free()
		finish()
		return

	print("\n=== structure: every new node exists ===")
	var create_grain_btn: Node     = root_ui.find_child("CreateGrainButton", true, false)
	var grain_cooldown_bar: Node   = root_ui.find_child("GrainCooldownBar", true, false)
	var grain_strip_sub: Node      = root_ui.find_child("GrainStripSubViewport", true, false)
	var grain_strip_lattice: Node  = root_ui.find_child("GrainCycleProgressBar", true, false)
	var grain_creation_panel: Node = root_ui.find_child("GrainCreationPanel", true, false)
	var grain_tetra: Node          = root_ui.find_child("GrainTetrahedron", true, false)
	var grain_counter_row: Node    = root_ui.find_child("RowGrainCounterInstance", true, false)
	var uonite_btn: Node           = root_ui.find_child("CreateUoniteButton", true, false)
	var uonite_bar: Node           = root_ui.find_child("UoniteCooldownBar", true, false)
	var uonite_panel: Node         = root_ui.find_child("UoniteCreationPanel", true, false)
	var uonites_direct_row: Node   = root_ui.find_child("RowUonitesValueInstance", true, false)

	ok(create_grain_btn != null, "CreateGrainButton exists")
	ok(grain_cooldown_bar != null, "GrainCooldownBar exists")
	ok(grain_strip_sub != null, "GrainStripSubViewport exists")
	ok(grain_strip_lattice != null, "GrainCycleProgressBar instance exists inside the strip viewport")
	ok(grain_creation_panel != null, "GrainCreationPanel exists")
	ok(grain_tetra != null, "GrainTetrahedron instance exists inside the creation panel")
	ok(grain_counter_row != null, "RowGrainCounterInstance exists")
	ok(uonite_btn != null and uonite_bar != null and uonite_panel != null,
		"sanity: the pre-existing Uonite cluster is still intact (else the toggle checks below prove nothing)")
	ok(uonites_direct_row != null, "sanity: the DirectReadouts Uonite row still exists")

	ok(grain_tetra.get_script() == load("res://grain_tetrahedron.gd"),
		"GrainTetrahedron actually runs grain_tetrahedron.gd")
	ok(grain_strip_lattice.get_script() == load("res://grain_tetrahedron.gd"),
		"the strip bar's lattice source also runs grain_tetrahedron.gd (same reuse-the-script trick as Uonite's strip)")
	ok(grain_strip_lattice.current_motes == 4,
		"the strip bar's lattice source is frozen fully-revealed (current_motes=4, got %d)" % grain_strip_lattice.current_motes)

	print("\n=== default state (WILL): Uonite cluster visible, Grain cluster hidden ===")
	gc.will_form_switch_is_will = true
	root_ui._sync_will_form_display_visibility()
	ok(uonite_btn.visible and uonite_bar.visible and uonite_panel.visible,
		"Uonite button/bar/panel are all visible when WILL is active")
	ok(not create_grain_btn.visible and not grain_cooldown_bar.visible
			and not grain_creation_panel.visible and not grain_counter_row.visible,
		"Grain button/bar/panel/counter are all hidden when WILL is active")

	print("\n=== toggling to FORM swaps visibility exactly ===")
	gc.toggle_will_form_switch()
	await process_frame
	ok(not uonite_btn.visible and not uonite_bar.visible and not uonite_panel.visible,
		"Uonite button/bar/panel are all hidden once FORM is active")
	ok(create_grain_btn.visible and grain_cooldown_bar.visible
			and grain_creation_panel.visible and grain_counter_row.visible,
		"Grain button/bar/panel/counter are all visible once FORM is active")
	ok(uonites_direct_row.visible,
		"the DirectReadouts Uonite row is left alone by the toggle -- it's a shared panel, not swapped")

	gc.toggle_will_form_switch()
	await process_frame
	ok(uonite_btn.visible and not create_grain_btn.visible,
		"toggling back to WILL restores the original visibility")

	print("\n=== CreateGrainButton is wired, not a dead button ===")
	ok(create_grain_btn.pressed.get_connections().size() > 0,
		"CreateGrainButton's pressed signal has at least one connection")

	print("\n=== tooltip registration ===")
	root_ui._cache_tooltip_buttons()
	ok(root_ui._tooltip_buttons.has("CreateGrainButton"), "CreateGrainButton is registered for tooltips")
	root_ui._update_button_tooltips()
	ok(create_grain_btn.tooltip_text != "", "CreateGrainButton has real tooltip text after an update pass (got %s)" % create_grain_btn.tooltip_text)

	print("\n=== counter: RowGrainCounterInstance resolves to the generic 'grain' resource key ===")
	root_ui._setup_resource_rows()
	ok(grain_counter_row.resource_key == "grain",
		"resource_key resolved to 'grain' (got '%s')" % grain_counter_row.resource_key)
	root_ui._update_counters()
	var label_text: String = grain_counter_row.display_label
	ok(label_text.findn("Grain") != -1 and label_text != "",
		"the row shows a real, non-empty 'Grain: ...' label after an update pass (got '%s')" % label_text)

	scene_root.queue_free()

	if fails == 0:
		print("\nALL PASS (0 failures)")
	else:
		print("\nFAILURES (%d failures)" % fails)
	finish()
