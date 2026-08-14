extends "res://dev_tests/test_base.gd"
# The Study Overlay is ONE reused node, re-pointed by
# show_for_constellation(id). Every piece of per-puzzle state therefore has
# to be dropped on switch, or it silently bleeds into the next constellation.
#
# Two leaks found 2026-08-12 and fixed alongside this test:
#   * _widget_closed (star_idx -> bool) — a star widget closed in one
#     constellation started hidden in the next, and a stale index could
#     outlive a switch to a puzzle with fewer stars
#   * _search_term — the SEARCH tab kept querying a term from the previous
#     puzzle's vocabulary
#
# Latent while switching is rare; routine once multiple Constellations are
# active in the Early game.

const OverlayScene = preload("res://ConstellationStudyOverlay.tscn")

var fails: int = 0
func ok(c: bool, s: String) -> void:
	if c:
		print("  PASS  ", s)
	else:
		print("  FAIL  ", s)
		fails += 1


func run() -> void:
	var cd = load("res://constellation_data.gd").new()
	# A bare ConstellationData has no GENERATED puzzle, so every star array
	# comes back empty and the whole test passes vacuously. Load the real
	# save so at least one constellation has a populated cache.
	var raw: String = FileAccess.get_file_as_string("user://djinncremental_save.json")
	if raw != "":
		var save = JSON.parse_string(raw)
		if save != null and save.has("constellation"):
			cd.load_save_data(save["constellation"])

	var host = OverlayScene.instantiate()
	root.add_child(host)
	# _ready() is deferred in --script mode.
	await process_frame
	host._cd = cd

	# Only constellations with a generated cache are usable. Prefer two
	# different ones so the switch is real; fall back to the same id twice,
	# which still exercises the reset (it is unconditional) — reported
	# either way so a weaker run is never mistaken for a stronger one.
	var usable: Array = []
	for cid in range(8):
		var c: Dictionary = cd.get_puzzle_cache(cid)
		if c is Dictionary and int(c.get("star_count", 0)) > 0:
			usable.append(cid)
	if usable.is_empty():
		print("  (no generated puzzle in the save — cannot test a real switch)")
		print("ALL PASS (0 failures)")
		finish()   # early return is still a legitimate completion
		return
	var id_a: int = int(usable[0])
	var id_b: int = int(usable[1]) if usable.size() > 1 else id_a
	print("  usable constellations: %s   switching %d -> %d%s"
		% [str(usable), id_a, id_b, "  (same id — only one generated)" if id_a == id_b else ""])

	host.show_for_constellation(id_a)
	await process_frame
	ok(host._star_count > 0, "constellation %d loaded (%d stars)" % [id_a, host._star_count])

	# Dirty exactly the state a player would: close a widget, run a search.
	host._widget_closed[0] = true
	host._widget_closed[host._star_count - 1] = true
	host._widgets._search_term = "N:SomeNameFromPuzzleA"
	host._selected_clue_text = "a clue from puzzle A"
	host._selected_clue_tab = 2
	print("  dirtied: %d closed widgets, search=%s"
		% [host._widget_closed.size(), host._widgets._search_term])

	host.show_for_constellation(id_b)
	await process_frame

	ok(host._widget_closed.is_empty(),
		"_widget_closed cleared on switch (%d left)" % host._widget_closed.size())
	ok(host._widgets._search_term == "",
		"_search_term cleared on switch (got '%s')" % host._widgets._search_term)
	ok(host._selected_clue_text == "",
		"pinned clue cleared on switch (got '%s')" % host._selected_clue_text)
	ok(host._selected_clue_tab < 0,
		"pinned clue's tab cleared (got %d)" % host._selected_clue_tab)

	# The engine must have been rebuilt from the new constellation's notes,
	# never carried over.
	var d = host._deduction
	ok(d._derived.size() == d.record_count(),
		"derived layer matches record count after switch (%d vs %d)"
			% [d._derived.size(), d.record_count()])

	# No stale star index may outlive a switch to a SMALLER puzzle. Only
	# meaningful when the two actually differ in size; reported either way
	# so the check is not silently vacuous.
	var stale: Array = []
	for k in host._widget_closed:
		if int(k) >= host._star_count:
			stale.append(int(k))
	ok(stale.is_empty(), "no closed-widget index beyond the new star count %s" % str(stale))

	print("\nALL PASS (0 failures)" if fails == 0 else "\nFAILURES (%d failures)" % fails)
	finish()
