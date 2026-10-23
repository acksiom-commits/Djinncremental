extends "res://dev_tests/test_base.gd"
# Stoctagon mini-icons "skipping briefly over the wedge boundaries" (user
# report 2026-10-20). A wall crossing glides each icon to a randomized point
# past the seam; unclamped, ~15% of those points sat outside the
# destination wedge, so the icon visibly overshot and then _confine_to_wedge()
# snapped it back by up to ~18px on the first frame after landing. Fresh
# flow icons also popped in at full alpha centred ON the outer rim.
#
# Checks run against the real storage_display.gd at its in-scene size
# (RootUI.tscn: custom_minimum_size 142x148).

var fails: int = 0
func ok(c: bool, s: String) -> void:
	if c:
		print("  PASS  ", s)
	else:
		print("  FAIL  ", s)
		fails += 1


# How far the icon's edge pokes past the worst edge of its wedge (<= 0 means
# fully inside). Read from the display's own _wedge_bounds.
func _overhang(sd, pos: Vector2, wedge: int, half: float) -> float:
	var worst: float = -INF
	for edge in sd._wedge_bounds[wedge]:
		worst = maxf(worst, (pos - edge[0]).dot(edge[1]) + half)
	return worst


# Second report, same day: top-wedge Uonite mini-icons reappearing right
# after an Oscillation with no Motes made yet. The reset zeroes mote_uonite,
# and root_ui's cosmetic icosahedron counter read that drop (e.g. 7 -> 0) as
# a 20-Mote wrap, spawning a fresh mini-icon the frame after
# clear_flow_icons() emptied the wedge.
func _check_oscillation_leaves_top_wedge_empty() -> void:
	print("\n=== an Oscillation leaves the top wedge empty ===")
	var scene_root = load("res://RootUI.tscn").instantiate()
	root.add_child(scene_root)
	await process_frame
	var root_ui = scene_root.find_child("RootUI", true, false)
	var gc = root.get_node_or_null("/root/GameContext")
	ok(root_ui != null and gc != null, "sanity: RootUI and GameContext reachable")
	if root_ui == null or gc == null:
		scene_root.queue_free()
		return
	# Driven by hand below. No autosave tick, and no save_manager to reach
	# even if something tried: this check must never write the real save.
	root_ui.set_process(false)
	root_ui.save_manager = null
	var display = root_ui._storage_display
	display.set_process(false)

	# RootUI's _ready() loaded the REAL save, so the cosmetic counter may
	# already be ramping toward that save's mote_uonite mod 20. A remainder
	# above 7 made the drop to 7 below read as a wrap and spawn a top-wedge
	# icon, failing the setup check whenever the player's save sat there
	# (2026-10-21: 111 Motes, remainder 11). Start from a known empty state.
	root_ui._icosa_mote_display = 0
	display.clear_flow_icons()

	gc.ui_unlocks["uonite_creation"] = true
	gc.mote_uonite = BigNum.from_int(7)
	for k in 10:
		root_ui._update_counters()
	ok(root_ui._icosa_mote_display == 7, "setup: the icosahedron shows 7 Motes (got %d)" % root_ui._icosa_mote_display)
	ok(display._count_completed_uonite_icons() == 0, "setup: no top-wedge icon before the reset")

	root_ui._do_prestige_reset()
	ok(gc.mote_uonite.is_zero(), "setup: the reset zeroed mote_uonite")
	for k in 10:
		root_ui._update_counters()
	var after: int = display._count_completed_uonite_icons()
	print("  top-wedge icons after the reset: %d" % after)
	ok(after == 0, "no top-wedge mini-icon reappears after an Oscillation with no Motes")
	ok(root_ui._icosa_mote_display == 0, "the icosahedron counter starts the new cycle at 0")
	scene_root.queue_free()


func run() -> void:
	var sd = load("res://storage_display.gd").new()
	sd.set_process(false)
	root.add_child(sd)
	await process_frame
	sd.size = Vector2(142, 148)
	sd._rebuild_octagon()
	sd._rng.seed = 20261020

	print("\n=== wall crossings land inside their new wedge, no snap ===")
	for leg_idx in 5:
		var leg: Dictionary = sd._flow_legs[leg_idx]
		var half: float = sd.ICON_SIZES[leg["next"]] * 0.5
		var n := 400
		var landed := 0
		var max_snap := 0.0
		var max_over := -INF
		for k in n:
			sd._icons.clear()
			sd._start_flow_for_leg(leg_idx, 1)
			var icon: Dictionary = sd._icons[0]
			var steps := 0
			while icon.has("flow_active") and steps < 2000:
				sd._advance_flow_icon(icon, 1.0 / 60.0)
				steps += 1
			if icon.has("flow_active"):
				continue
			landed += 1
			max_over = maxf(max_over, _overhang(sd, icon["pos"], icon["wedge"], half))
			var before: Vector2 = icon["pos"]
			sd._confine_to_wedge(icon)
			max_snap = maxf(max_snap, before.distance_to(icon["pos"]))
		print("  %-12s landed %d/%d, worst overhang %.2fpx, worst snap %.2fpx" % [leg["next"], landed, n, max_over, max_snap])
		ok(landed == n, "%s: every crossing finished" % leg["next"])
		ok(max_over <= 0.01, "%s: landing never pokes out of the wedge" % leg["next"])
		ok(max_snap <= 0.01, "%s: confinement never moves a just-landed icon" % leg["next"])

	print("\n=== fresh flow icons start inside their wedge, faded out ===")
	sd._icons.clear()
	sd._start_flow_for_leg(4, 3)  # Mote -> Grain, no Mote icons on hand
	var fresh_ok := 0
	for icon in sd._icons:
		var half: float = sd.ICON_SIZES[icon["resource"]] * 0.5
		if icon["alpha"] == 0.0 and _overhang(sd, icon["pos"], icon["wedge"], half) <= 0.01:
			fresh_ok += 1
	print("  %d/%d fresh icons inside their wedge at alpha 0" % [fresh_ok, sd._icons.size()])
	ok(sd._icons.size() == 3 and fresh_ok == 3, "fresh flow icons spawn inside the rim, invisible")
	var faded: Dictionary = sd._icons[0]
	for k in 60:
		sd._advance_flow_icon(faded, 1.0 / 60.0)
	ok(faded["alpha"] >= 1.0, "and fade in to full alpha (got %.2f)" % faded["alpha"])

	print("\n=== confinement settles in one call, even in the narrow inner corners ===")
	var judged := 0
	var escaped := 0
	for key in ["grain", "uonite", "mote_uonite"]:
		var half: float = sd.ICON_SIZES[key] * 0.5
		for w in range(1, 8):
			var b: Array = sd._wedge_bounds[w]
			for k in 300:
				# Random points across the wedge, biased toward its inner end.
				var t: float = sd._rng.randf()
				var s: float = sqrt(sd._rng.randf())
				var outer: Vector2 = sd._oct_verts[w].lerp(sd._oct_verts[(w + 1) % 8], t)
				var inner: Vector2 = sd._inner_verts[w].lerp(sd._inner_verts[(w + 1) % 8], t)
				var icon := {"resource": key, "wedge": w, "pos": outer.lerp(inner, s), "vel": Vector2.ZERO}
				sd._confine_to_wedge(icon)
				judged += 1
				if _overhang(sd, icon["pos"], w, half) > 0.01:
					escaped += 1
	print("  %d/%d confined icons still over an edge" % [escaped, judged])
	ok(judged == 3 * 7 * 300 and escaped == 0, "one _confine_to_wedge() call always leaves the icon inside")

	sd.queue_free()

	await _check_oscillation_leaves_top_wedge_empty()

	if fails == 0:
		print("ALL PASS (0 failures)")
	else:
		print("FAILURES (%d failures)" % fails)
	finish()
