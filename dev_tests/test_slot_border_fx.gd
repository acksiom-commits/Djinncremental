extends "res://dev_tests/test_base.gd"
# Constellation selector buttons: gold border while a Parent Volition targets
# the constellation, rotating arc while Foci are assigned, independent of each
# other, and never stealing clicks from the button.

const PopoutScene = preload("res://ConstellationPopout.tscn")

var fails: int = 0


func ok(c: bool, s: String) -> void:
	if c:
		print("  PASS  ", s)
	else:
		print("  FAIL  ", s)
		fails += 1


func run() -> void:
	await process_frame   # autoloads are unreachable until one frame has passed
	var gc = root.get_node_or_null("/root/GameContext")
	var cd = root.get_node_or_null("/root/ConstellationData")
	if gc == null or cd == null:
		ok(false, "autoloads reachable -- otherwise every check below is vacuous")
		finish()
		return
	var p = PopoutScene.instantiate()
	root.add_child(p)
	await process_frame
	for uid in [0, 1]:
		if not cd.unlocked.has(uid):
			cd.unlocked.append(uid)
	p._build_slots()
	await process_frame

	var s0 = p._slot_grid.get_node_or_null("Slot0")
	var s1 = p._slot_grid.get_node_or_null("Slot1")
	ok(s0 != null and s1 != null, "slot buttons exist (%s, %s)" % [str(s0 != null), str(s1 != null)])
	if s0 == null or s1 == null:
		finish()
		return
	var f0 = s0.get_node_or_null("BorderFx")
	var f1 = s1.get_node_or_null("BorderFx")
	ok(f0 != null and f1 != null, "each slot carries a BorderFx overlay")
	ok(f0.mouse_filter == Control.MOUSE_FILTER_IGNORE, "the overlay never takes the click")
	# The panel forces STOP onto its whole subtree when it opens; that is what
	# broke clicks in play, so exercise it for real, both ways.
	p._set_panel_input(true)
	ok(f0.mouse_filter == Control.MOUSE_FILTER_IGNORE and f1.mouse_filter == Control.MOUSE_FILTER_IGNORE,
		"opening the panel (STOP on its subtree) leaves the overlays on IGNORE")
	ok(s0.mouse_filter == Control.MOUSE_FILTER_STOP, "while the button itself does get STOP")
	p._set_panel_input(false)

	var saved_slots = gc.volition_slots.duplicate(true)
	var saved_assign = gc.assignments.duplicate(true)
	gc.volition_slots = []
	gc.assignments.erase("constellation_0_foci")
	gc.assignments.erase("constellation_1_foci")
	p._refresh_slots()
	ok(not f0.parent_gold and not f0.foci_arc and not f1.parent_gold and not f1.foci_arc,
		"nothing assigned: no effect on either button")

	gc.volition_slots = [{"category": "constellation", "target": 0}]
	p._refresh_slots()
	ok(f0.parent_gold and not f0.foci_arc, "a Parent Volition on 0: gold, no arc")
	ok(not f1.parent_gold, "and constellation 1 stays plain")

	gc.assignments["constellation_1_foci"] = 3
	p._refresh_slots()
	ok(f1.foci_arc and not f1.parent_gold, "Foci on 1: arc, no gold")
	ok(f1.is_processing(), "the arc animates only while it is on")
	ok(not f0.is_processing(), "an idle button does not animate")

	gc.assignments["constellation_0_foci"] = 1
	p._refresh_slots()
	ok(f0.parent_gold and f0.foci_arc, "both: gold border AND arc together")

	gc.volition_slots = []
	gc.assignments["constellation_0_foci"] = 0
	p._refresh_slots()
	ok(not f0.parent_gold and not f0.foci_arc, "removing both clears both")

	print("\n=== the buttons are kept, not torn down and remade ===")
	# _build_slots() runs on every unlock, panel show and octant change. It
	# used to clear and remake every button; queue_free() leaves the old ones
	# in the tree until frame end, so the replacements were renamed "@Button@N"
	# and _refresh_slots() (by-name lookup) skipped them all -- which is why
	# the border effects "never appeared" (2026-09-24). Buttons are now
	# created once and kept.
	var before0 = p._slot_grid.get_node_or_null("Slot0")
	var before_fx = before0.get_node_or_null("BorderFx")
	p._build_slots()
	p._build_slots()
	await process_frame
	ok(p._slot_grid.get_node_or_null("Slot0") == before0, "a rebuild keeps the very same Slot0 button")
	ok(before0.get_node_or_null("BorderFx") == before_fx, "and the same border overlay")
	ok(p._slot_grid.get_child_count() == 2, "no extra buttons are created (%d children)" % p._slot_grid.get_child_count())
	ok(p._slot_grid.get_node_or_null("Slot1") != null, "Slot1 still resolves by name")
	gc.volition_slots = [{"category": "constellation", "target": 0}]
	p._refresh_slots()
	ok(before_fx.parent_gold, "a refresh after rebuilds still reaches the button's border effect")

	# A newly unlocked constellation gets its button without disturbing the rest.
	if not cd.unlocked.has(2):
		cd.unlocked.append(2)
	p._build_slots()
	ok(p._slot_grid.get_node_or_null("Slot2") != null and p._slot_grid.get_node_or_null("Slot0") == before0,
		"unlocking constellation 2 adds its button and leaves Slot0 untouched")
	ok(p._slot_grid.get_child_count() == 3, "three buttons now (%d)" % p._slot_grid.get_child_count())

	# Geometry: the arc walks the perimeter clockwise.
	var geo = before_fx
	geo.size = Vector2(80, 56)
	var a: Vector2 = geo._perimeter_point(0.0)
	var b: Vector2 = geo._perimeter_point(0.1)
	var c: Vector2 = geo._perimeter_point(0.4)
	ok(b.x > a.x and is_equal_approx(b.y, a.y), "starting along the top edge, moving right (clockwise)")
	ok(c.x > 40 and c.y > 28, "then down the right side, past the corner")

	gc.volition_slots = saved_slots
	gc.assignments = saved_assign
	if fails == 0:
		print("ALL PASS (0 failures)")
	else:
		print("FAILURES (%d failures)" % fails)
	finish()
