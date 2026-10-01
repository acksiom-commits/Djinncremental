extends "res://dev_tests/test_base.gd"
# Will/Form production switch (2026-09-30) -- the button that replaces
# GrainAssembleButton. Scope is a VISUAL/STATE toggle only for now: it
# reads/writes GameContext.will_form_switch_is_will and lights the matching
# box. Nothing downstream reacts to the flag yet (recipe routing, the
# Compress/Assemble mini-icons, and the Create Uonite/Assemble Grains
# swap are separate, not-yet-built to-do items).
#
# What must hold:
#  - Default state is Will (matches the Uonite branch already having a
#    working button), and the WILL box starts lit, FORM dimmed.
#  - Pressing the PARENT BUTTON (not a specific child) toggles the state --
#    this is the actual mechanism behind "clicking anywhere on the button,
#    including the CREATE bar, should toggle it": every child here has
#    mouse_filter = IGNORE, so Godot delivers the click to the Button
#    itself regardless of which child visually sits under the cursor.
#  - Toggling flips both boxes' lit/dim state correctly, and toggling again
#    returns to the original state.
#  - GrainAssembleButton no longer exists under its old name/role.

var fails: int = 0


func ok(c: bool, s: String) -> void:
	if c:
		print("  PASS  ", s)
	else:
		print("  FAIL  ", s)
		fails += 1


func run() -> void:
	await process_frame

	var gc = root.get_node_or_null("/root/GameContext")
	ok(gc != null, "sanity: GameContext autoload is reachable")
	if not gc:
		finish()
		return
	gc.will_form_switch_is_will = true

	var btn := Button.new()
	root.add_child(btn)
	var switch_instance = load("res://WillFormSwitch.tscn").instantiate()
	btn.add_child(switch_instance)
	await process_frame

	# Reported 2026-09-30: CreateBar sizing itself purely from font content
	# left WILL/FORM taking most of the button's height, reading as too
	# tall/awkward -- CreateBar needs an explicit share of the height, not
	# whatever its own text happens to need.
	ok(switch_instance.create_bar.custom_minimum_size.y > 0,
		"CreateBar has an explicit minimum height rather than sizing purely from its own font content (got %s)" % switch_instance.create_bar.custom_minimum_size.y)

	print("\n=== CREATE/WILL/FORM text is vertically centered in its area ===")
	# Reported 2026-09-30: text sat at the top of its box. RichTextLabel has
	# no vertical-alignment property at all, so the fix was switching these
	# three to plain Label, which does -- check the property directly on
	# all three rather than just trusting the node type.
	for case in [
		{"lbl": switch_instance.create_bar, "desc": "CreateBar"},
		{"lbl": switch_instance.will_label, "desc": "WillLabel"},
		{"lbl": switch_instance.form_label, "desc": "FormLabel"},
	]:
		var lbl: Label = case["lbl"]
		ok(lbl.vertical_alignment == VERTICAL_ALIGNMENT_CENTER,
			"%s text is vertically centered (VERTICAL_ALIGNMENT_CENTER)" % case["desc"])
		ok(lbl.horizontal_alignment == HORIZONTAL_ALIGNMENT_CENTER,
			"%s text is horizontally centered (HORIZONTAL_ALIGNMENT_CENTER)" % case["desc"])

	ok(is_equal_approx(switch_instance.will_box.get_theme_stylebox("panel").bg_color.r,
			switch_instance._will_style_lit.bg_color.r),
		"WILL box starts lit when will_form_switch_is_will=true")
	ok(is_equal_approx(switch_instance.form_box.get_theme_stylebox("panel").bg_color.r,
			switch_instance._form_style_dim.bg_color.r),
		"FORM box starts dimmed")

	print("\n=== text color always reads against its OWN current background ===")
	# Reported 2026-09-30: white text on the lit (bright gold) Will box was
	# nearly unreadable. Checked by luminance, not by hardcoding "lit=dark
	# text" -- Form's lit color (purple) is dark enough that WHITE is
	# actually the right choice there, so the fix has to read the ACTUAL
	# background color each box is currently showing, not just its state.
	for case in [
		{"bg": switch_instance._will_style_lit.bg_color, "desc": "Will lit (bright gold)"},
		{"bg": switch_instance._will_style_dim.bg_color, "desc": "Will dimmed"},
		{"bg": switch_instance._form_style_lit.bg_color, "desc": "Form lit (purple)"},
		{"bg": switch_instance._form_style_dim.bg_color, "desc": "Form dimmed"},
	]:
		var bg: Color = case["bg"]
		var text_color: Color = switch_instance._readable_text_color(bg)
		var brightness: float = bg.r * 0.299 + bg.g * 0.587 + bg.b * 0.114
		var expected: Color = Color.BLACK if brightness > 0.5 else Color.WHITE
		ok(text_color.is_equal_approx(expected),
			"%s (brightness %.2f) gets %s text" % [case["desc"], brightness, "black" if expected == Color.BLACK else "white"])

	# The actual "click anywhere" mechanism: a real click lands on the
	# BUTTON (every child ignores mouse input), so simulating the button's
	# own pressed signal is the faithful equivalent of clicking any pixel
	# inside it, CREATE bar included.
	btn.emit_signal("pressed")
	await process_frame
	ok(not gc.will_form_switch_is_will, "pressing the button toggled GameContext to Form")
	ok(is_equal_approx(switch_instance.form_box.get_theme_stylebox("panel").bg_color.r,
			switch_instance._form_style_lit.bg_color.r),
		"FORM box is now lit")
	ok(is_equal_approx(switch_instance.will_box.get_theme_stylebox("panel").bg_color.r,
			switch_instance._will_style_dim.bg_color.r),
		"WILL box is now dimmed")

	btn.emit_signal("pressed")
	await process_frame
	ok(gc.will_form_switch_is_will, "pressing again toggles back to Will")
	ok(is_equal_approx(switch_instance.will_box.get_theme_stylebox("panel").bg_color.r,
			switch_instance._will_style_lit.bg_color.r),
		"WILL box is lit again")

	btn.queue_free()

	print("\n=== GrainAssembleButton no longer exists under its old role ===")
	var root_ui = load("res://RootUI.tscn").instantiate()
	root.add_child(root_ui)
	await process_frame
	ok(root_ui.find_child("GrainAssembleButton", true, false) == null,
		"no node named GrainAssembleButton remains in RootUI.tscn")
	var new_btn = root_ui.find_child("WillFormSwitchButton", true, false)
	ok(new_btn != null, "WillFormSwitchButton exists in RootUI.tscn")
	ok(new_btn != null and new_btn.find_child("WillFormSwitchInstance", false, false) != null,
		"WillFormSwitchButton contains the WillFormSwitchInstance overlay")
	root_ui.queue_free()

	if fails == 0:
		print("\nALL PASS (0 failures)")
	else:
		print("\nFAILURES (%d failures)" % fails)
	finish()
