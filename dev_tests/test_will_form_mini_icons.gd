extends "res://dev_tests/test_base.gd"
# WILL/FORM mini-icons on the Particle/Iota/Mote Assemble buttons
# (2026-10-01) -- purely cosmetic, same scope as the switch button itself.
#
# Each button carries TWO fixed icons, not one icon that swaps shape:
#   - side="left"  is PERMANENTLY the Uonite icon, visible while WILL is lit
#   - side="right" is PERMANENTLY the Grain icon, visible while FORM is lit
# Toggling the switch fades the current side out (scale.x -> 0, "rotating
# edge-on") and the other side in (scale.x -> 1) -- corrected 2026-10-01
# after an earlier version wrongly had a single icon per slot swap which
# shape it drew; the two icons never change shape or position, only
# visibility.
#
# What must hold:
#  - A fresh WILL/left icon boots visible (scale.x=1) and the FORM/right
#    icon boots invisible (scale.x=0) when GameContext is WILL -- and the
#    mirror image when GameContext is FORM.
#  - Toggling GameContext fades each icon to the opposite state, left and
#    right alike, once the flip animation has had time to land.
#  - A "change" that doesn't alter THIS icon's own visibility is a no-op
#    (no needless tween).
#  - side="left" sits near the parent's left edge, side="right" near its
#    right edge, both inside the parent's bounds, with real non-zero size.
#  - All three Assemble buttons in RootUI.tscn actually carry both icons.

const WillFormMiniIconScript = preload("res://will_form_mini_icon.gd")

var fails: int = 0


func ok(c: bool, s: String) -> void:
	if c:
		print("  PASS  ", s)
	else:
		print("  FAIL  ", s)
		fails += 1


func _make_icon(side: String) -> Control:
	var btn := Button.new()
	btn.custom_minimum_size = Vector2(140, 55)
	btn.size = Vector2(140, 55)
	root.add_child(btn)
	var icon = load("res://WillFormMiniIcon.tscn").instantiate()
	icon.side = side
	btn.add_child(icon)
	return icon


## Waits, frame by frame, up to a generous bound for an icon's own flip
## tween to finish (or to never have started, for the no-op case). 180
## frames is a large margin over FLIP_DURATION (0.35s) even at a modest
## headless frame rate -- this bounds the wait without depending on
## exactly how fast frames tick in this harness. process_frame (not
## tree.create_timer(...).timeout) is used because it's the mechanism
## every other test in this suite already relies on successfully.
func _await_flip(icon: Control, max_frames: int = 180) -> void:
	var n := 0
	while icon._flip_tween and icon._flip_tween.is_valid() and n < max_frames:
		await process_frame
		n += 1


func run() -> void:
	await process_frame

	var gc = root.get_node_or_null("/root/GameContext")
	ok(gc != null, "sanity: GameContext autoload is reachable")
	if not gc:
		finish()
		return
	gc.will_form_switch_is_will = true

	var left_icon := _make_icon("left")
	var right_icon := _make_icon("right")
	await process_frame

	print("\n=== each side boots showing only its OWN icon ===")
	ok(is_equal_approx(left_icon.scale.x, 1.0), "left/Uonite icon boots VISIBLE when GameContext is WILL")
	ok(is_equal_approx(right_icon.scale.x, 0.0), "right/Grain icon boots INVISIBLE when GameContext is WILL")

	print("\n=== positioning: left hugs the left edge, right hugs the right edge ===")
	# Explicitly checks SIZE, not just position -- a prior version of this
	# icon collapsed to 0x0 (set_anchors_and_offsets_preset() silently
	# resizing it to an unset minimum size) and rendered nothing, but every
	# position-only assertion here still happened to pass, since "0 added
	# to a position" never breaks a `<=` bound. Reported live as "mini
	# icons are not appearing at all" -- this test should have caught it.
	ok(is_equal_approx(left_icon.size.x, WillFormMiniIconScript.ICON_SIZE) and is_equal_approx(left_icon.size.y, WillFormMiniIconScript.ICON_SIZE),
		"left icon has its real, non-zero size (got %s)" % left_icon.size)
	ok(is_equal_approx(right_icon.size.x, WillFormMiniIconScript.ICON_SIZE) and is_equal_approx(right_icon.size.y, WillFormMiniIconScript.ICON_SIZE),
		"right icon has its real, non-zero size (got %s)" % right_icon.size)

	var parent_width: float = (left_icon.get_parent() as Control).size.x
	ok(left_icon.position.x >= 0 and left_icon.position.x < parent_width * 0.5,
		"left-side icon sits in the left half of its button (x=%s of %s)" % [left_icon.position.x, parent_width])
	ok(right_icon.position.x > parent_width * 0.5 and right_icon.position.x + right_icon.size.x <= parent_width + 0.01,
		"right-side icon sits in the right half of its button, fully inside it (x=%s, size=%s, parent=%s)" % [right_icon.position.x, right_icon.size.x, parent_width])

	print("\n=== a change that doesn't affect THIS icon's visibility is a no-op ===")
	gc.emit_signal("will_form_switch_changed", true)
	await process_frame
	ok(is_equal_approx(left_icon.scale.x, 1.0) and not (left_icon._flip_tween and left_icon._flip_tween.is_valid()),
		"re-announcing the SAME state (WILL) starts no tween on the already-visible left icon")

	print("\n=== toggling GameContext fades each icon to the opposite side ===")
	# Goes through the real mechanism (toggle_will_form_switch(), the same
	# call the switch button itself makes) rather than hand-setting the
	# flag and emitting separately -- the two used to be able to drift
	# apart before toggle_will_form_switch() unified them.
	gc.toggle_will_form_switch()
	await _await_flip(left_icon)
	await _await_flip(right_icon)

	ok(is_equal_approx(left_icon.scale.x, 0.0), "left/Uonite icon faded out when FORM was selected")
	ok(is_equal_approx(right_icon.scale.x, 1.0), "right/Grain icon faded in when FORM was selected")

	gc.toggle_will_form_switch()
	await _await_flip(left_icon)
	await _await_flip(right_icon)

	ok(is_equal_approx(left_icon.scale.x, 1.0), "left/Uonite icon faded back in when WILL was reselected")
	ok(is_equal_approx(right_icon.scale.x, 0.0), "right/Grain icon faded back out when WILL was reselected")

	print("\n=== RootUI: all three Assemble buttons carry both mini-icons ===")
	var root_ui = load("res://RootUI.tscn").instantiate()
	root.add_child(root_ui)
	await process_frame
	for btn_name in ["ParticleCompressButton", "IotaAssembleButton", "MoteCompressButton"]:
		var btn: Node = root_ui.find_child(btn_name, true, false)
		ok(btn != null, "%s exists in RootUI.tscn" % btn_name)
		if btn:
			var left_node: Node = btn.find_child("WillFormIconLeft", false, false)
			var right_node: Node = btn.find_child("WillFormIconRight", false, false)
			ok(left_node != null, "%s has a WillFormIconLeft child" % btn_name)
			ok(right_node != null, "%s has a WillFormIconRight child" % btn_name)
			if left_node:
				ok(left_node.side == "left", "%s's WillFormIconLeft is actually configured side=left" % btn_name)
			if right_node:
				ok(right_node.side == "right", "%s's WillFormIconRight is actually configured side=right" % btn_name)
	root_ui.queue_free()

	if fails == 0:
		print("\nALL PASS (0 failures)")
	else:
		print("\nFAILURES (%d failures)" % fails)
	finish()
