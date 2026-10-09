extends "res://dev_tests/test_base.gd"
# The Volumitions panel (the "xN" label and its +/- buttons) must follow the
# numbers it shows, whoever changes them.
#
# It used to be redrawn only from its own click handlers, game load and
# Expansion. The Archon crossing a tier resizes every Volition's bonus
# children, and the Archon or a click-bonus constellation going active or
# inactive moves the multiplier -- neither touched the label, which stayed
# wrong until the player unassigned and reassigned a Volition there.
#
# _check_click_vol_display() compares the READ values each frame, so this
# drives the values directly (as those events do) and watches the label.
#
# A bare root_ui.gd instance with game_context and a stand-in label injected,
# as test_second_volition_gate does: RootUI.tscn will not instantiate headless.
var fails: int = 0


func ok(c: bool, s: String) -> void:
	if c:
		print("  PASS  ", s)
	else:
		print("  FAIL  ", s)
		fails += 1


func run() -> void:
	var ui = load("res://root_ui.gd").new()
	var gc = load("res://game_context.gd").new()
	var label := Label.new()
	ui.game_context = gc
	ui._click_vol_label = label
	gc.volitions = 3
	gc._ensure_slot_count(3)

	print("=== first check draws the panel ===")
	ui._check_click_vol_display()
	ok(label.text == "x1", "a fresh board reads x1 (got %s)" % label.text)

	print("\n=== bonus children appearing (an Archon tier crossing) ===")
	# What sync_bonus_children_count() leaves behind when the grant rises.
	gc.assignments["click_volitions"] = 1
	gc.assignments["click_bonus_volitions"] = 2
	ui._check_click_vol_display()
	ok(label.text == "x4", "1 parent + 2 bonus reads x4 with no click on the panel (got %s)" % label.text)

	print("\n=== bonus children going away (the Archon deactivated) ===")
	gc.assignments["click_bonus_volitions"] = 0
	ui._check_click_vol_display()
	ok(label.text == "x2", "bonus gone reads x2 (got %s)" % label.text)

	print("\n=== a Volition spent elsewhere is picked up (the +/- state) ===")
	var free_before: int = int(ui._click_vol_sig[3])
	gc.volition_slots[1]["category"] = "constellation"
	gc.volition_slots[1]["target"] = 0
	ui._check_click_vol_display()
	ok(int(ui._click_vol_sig[3]) == gc.get_volitions_free() and gc.get_volitions_free() < free_before,
		"free count follows an assignment made elsewhere (%d -> %d)" % [free_before, gc.get_volitions_free()])

	print("\n=== an unchanged board is not redrawn ===")
	label.text = "marker"
	ui._check_click_vol_display()
	ok(label.text == "marker", "nothing changed, nothing redrawn")
	gc.assignments["click_volitions"] = 2
	ui._check_click_vol_display()
	ok(label.text != "marker", "a change redraws it again")

	label.free()
	ui.free()
	gc.free()
	print("\nALL PASS (%d failures)" % fails if fails == 0 else "\nFAILURES (%d failures)" % fails)
	finish()
