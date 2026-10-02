extends "res://dev_tests/test_base.gd"
# New Beginner-mode (easy_layout) star layouts added 2026-10-01, user-drawn:
# The Hourglass (2), The Bellows (3), The Phial (4), The Satchel (5)
# directly, plus The Djinn's (6) "lamp", "ring" and "jar" vessel variants
# nested inside vessel_layouts.
#
# Digitized from hand-drawn outlines by reading pixel coordinates directly
# and running them through a small, reusable conversion (centre on the
# shape's own bounding box, scale so the larger axis spans +/-0.13, no
# rotation, z completed via sqrt(1-x^2-y^2)) -- the arithmetic itself isn't
# hand-derived, only the pixel coordinates and edge list are, which is what
# this test actually has to verify: that the resulting data is structurally
# sound and that a real puzzle can be generated from it.
#
# What must hold:
#  - Each resolves to the right star_count under "easy" difficulty.
#  - Every authored position is a real point on the unit sphere.
#  - Every star is reachable from every other star (fully connected, no
#    isolated stars) -- unlike some hard-mode layouts (e.g. Bellows' own
#    "air particle" stars), none of these new shapes are meant to have a
#    disconnected component.
#  - line_pairs is flat, even-length, every index in bounds, no self-loops,
#    no duplicate edges.
#  - A real end-to-end generate_clues_forms() ships a puzzle (gate_passed).
#  - Hard difficulty still resolves each Djinn vessel to its own 17-star
#    hard-mode geometry (the nested easy_layout must not leak into it).

var fails: int = 0


func ok(c: bool, s: String) -> void:
	if c:
		print("  PASS  ", s)
	else:
		print("  FAIL  ", s)
		fails += 1


func _check_layout(cd, gc, cid: int, label: String, expected_star_count: int) -> void:
	gc.constellation_difficulty[cid] = "easy"
	var def: Dictionary = cd.get_constellation_def(cid)
	var star_count: int = int(def.get("star_count", -1))
	ok(star_count == expected_star_count, "%s: star_count is %d (got %d)" % [label, expected_star_count, star_count])

	var positions: Array = def.get("fixed_star_positions", [])
	ok(positions.size() == expected_star_count, "%s: %d authored positions (got %d)" % [label, expected_star_count, positions.size()])
	var off_sphere: int = 0
	for p in positions:
		var v := Vector3(float(p[0]), float(p[1]), float(p[2]))
		if not is_equal_approx(v.length(), 1.0):
			off_sphere += 1
	ok(off_sphere == 0, "%s: every position sits on the unit sphere (%d off)" % [label, off_sphere])

	var line_pairs: Array = def.get("line_pairs", [])
	ok(line_pairs.size() % 2 == 0, "%s: line_pairs is flat and even-length (%d entries)" % [label, line_pairs.size()])
	var seen_edges: Dictionary = {}
	var bad_bounds: int = 0
	var self_loops: int = 0
	var duplicates: int = 0
	var adjacency: Dictionary = {}
	for s in star_count:
		adjacency[s] = []
	for i in range(0, line_pairs.size(), 2):
		var a: int = int(line_pairs[i])
		var b: int = int(line_pairs[i + 1])
		if a < 0 or a >= star_count or b < 0 or b >= star_count:
			bad_bounds += 1
			continue
		if a == b:
			self_loops += 1
			continue
		var key: String = "%d-%d" % [mini(a, b), maxi(a, b)]
		if seen_edges.has(key):
			duplicates += 1
		seen_edges[key] = true
		(adjacency[a] as Array).append(b)
		(adjacency[b] as Array).append(a)
	ok(bad_bounds == 0, "%s: every line_pairs index is in bounds (%d bad)" % [label, bad_bounds])
	ok(self_loops == 0, "%s: no self-loops (%d found)" % [label, self_loops])
	ok(duplicates == 0, "%s: no duplicated edges (%d found)" % [label, duplicates])

	# Connectivity: BFS from star 0, every star must be reached.
	var visited: Dictionary = {0: true}
	var queue: Array = [0]
	while not queue.is_empty():
		var cur: int = queue.pop_front()
		for nb in (adjacency.get(cur, []) as Array):
			if not visited.has(nb):
				visited[nb] = true
				queue.append(nb)
	ok(visited.size() == star_count, "%s: every star is reachable, fully connected (%d of %d)" % [label, visited.size(), star_count])


func run() -> void:
	var cd = load("res://constellation_data.gd").new()
	var gc = load("res://game_context.gd").new()
	cd._game_context = gc

	print("=== structural checks ===")
	_check_layout(cd, gc, 2, "c2 Hourglass", 8)
	_check_layout(cd, gc, 3, "c3 Bellows", 7)
	_check_layout(cd, gc, 4, "c4 Phial", 6)
	_check_layout(cd, gc, 5, "c5 Satchel", 7)

	gc.chosen_vessel = "lamp"
	_check_layout(cd, gc, 6, "c6 Djinn (lamp)", 8)
	gc.chosen_vessel = "ring"
	_check_layout(cd, gc, 6, "c6 Djinn (ring)", 8)

	gc.chosen_vessel = "jar"
	_check_layout(cd, gc, 6, "c6 Djinn (jar)", 8)

	print("\n=== hard difficulty still resolves each Djinn vessel to its own hard-mode geometry ===")
	var hard_counts: Dictionary = {"lamp": 17, "ring": 17, "jar": 17}
	for vessel in hard_counts:
		gc.chosen_vessel = vessel
		gc.constellation_difficulty[6] = "hard"
		var hard_def: Dictionary = cd.get_constellation_def(6)
		ok(int(hard_def.get("star_count", -1)) == int(hard_counts[vessel]),
			"%s under hard difficulty keeps its %d-star geometry (got %d)" % [vessel, int(hard_counts[vessel]), int(hard_def.get("star_count", -1))])
	gc.constellation_difficulty[6] = "easy"

	print("\n=== a real end-to-end generated puzzle ships for each new layout ===")
	var PuzzleScript = load("res://constellation_logic_puzzle.gd")
	var overlay_engine = load("res://click_sequence_puzzle_engine.gd").new()
	var cases: Array = [
		{"cid": 2, "vessel": "", "label": "Hourglass"},
		{"cid": 3, "vessel": "", "label": "Bellows"},
		{"cid": 4, "vessel": "", "label": "Phial"},
		{"cid": 5, "vessel": "", "label": "Satchel"},
		{"cid": 6, "vessel": "lamp", "label": "Djinn (lamp)"},
		{"cid": 6, "vessel": "ring", "label": "Djinn (ring)"},
		{"cid": 6, "vessel": "jar", "label": "Djinn (jar)"},
	]
	for c in cases:
		var cid: int = int(c["cid"])
		if str(c["vessel"]) != "":
			gc.chosen_vessel = str(c["vessel"])
		gc.constellation_difficulty[cid] = "easy"
		cd.player_seed = 11
		var def: Dictionary = cd.get_constellation_def(cid)
		var scn: int = int(def["star_count"])
		overlay_engine.set_constellation(cid, cd, gc)
		var sq: Array = overlay_engine.get_correct_star_sequence(cid)
		var g = PuzzleScript.new()
		g.difficulty = "easy"
		g.setup(scn, def["line_pairs"], sq, 11, cid, def.get("name_theme", {}),
			cd.get_note_assignment(cid), cd.get_note_freqs(cid), null)
		await g.generate_clues_forms()
		ok(g.gate_passed, "%s: a real easy-mode puzzle ships (gate_passed=%s, %d clues)" % [
			str(c["label"]), g.gate_passed, g.chosen_form_clues.size()])

	if fails == 0:
		print("\nALL PASS (0 failures)")
	else:
		print("\nFAILURES (%d failures)" % fails)
	finish()
