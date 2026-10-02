extends "res://dev_tests/test_base.gd"
# intro_screen.gd's lamp/ring/jar selectors draw the SAME Beginner-mode
# star/line data constellation_data.gd's vessel_layouts[key]["easy_layout"]
# carries (2026-10-01), instead of hand-authored placeholder silhouettes.
#
# What must hold:
#  - intro_screen.gd still compiles.
#  - _vessel_easy_shape() returns real star/edge data for every vessel,
#    matching constellation_data.gd's own authored counts.
#  - After _populate_shapes(), every vessel lives in the star-graph dicts.
#  - Clicking where a star or edge actually renders on screen resolves to
#    that vessel's key, for every vessel (the thing a player's click
#    depends on), and clicking empty space resolves to nothing.
#
# Deliberately does NOT exercise _confirm_vessel()/_play_transition_and_
# continue() — that path calls change_scene_to_file(), which would swap the
# shared test runner's own main scene out from under every module that
# runs after this one. GameContext.chosen_vessel being read correctly by
# constellation_data.gd is already covered by
# test_beginner_mode_layouts_2026_10_01.gd.
#
# _populate_shapes() is called directly rather than via _ready(): _ready()
# returns early for a returning player's save, which a dev machine's real
# save file triggers in a headless run, leaving every shape dict empty and
# every check below vacuous.

var fails: int = 0


func ok(c: bool, s: String) -> void:
	if c:
		print("  PASS  ", s)
	else:
		print("  FAIL  ", s)
		fails += 1


func run() -> void:
	var IntroScreen = load("res://intro_screen.gd")
	ok(IntroScreen != null and IntroScreen.can_instantiate(), "intro_screen.gd compiles")

	print("\n=== _vessel_easy_shape() sources real Beginner-mode data ===")
	var expected: Dictionary = {
		"lamp": {"stars": 8, "edges": 9},
		"ring": {"stars": 8, "edges": 10},
		"jar":  {"stars": 8, "edges": 9},
	}
	var half_extent: float = IntroScreen.VESSEL_EASY_LAYOUT_HALF_EXTENT
	ok(is_equal_approx(half_extent, 0.13), "VESSEL_EASY_LAYOUT_HALF_EXTENT is 0.13 (got %s)" % half_extent)
	for key in expected:
		var shape: Dictionary = IntroScreen._vessel_easy_shape(key)
		ok(not shape.is_empty(), "%s: has easy_layout data" % key)
		var stars: Array = shape.get("stars", [])
		var edges: Array = shape.get("edges", [])
		ok(stars.size() == int(expected[key]["stars"]), "%s: %d stars (got %d)" % [key, int(expected[key]["stars"]), stars.size()])
		ok(edges.size() == int(expected[key]["edges"]), "%s: %d edges (got %d)" % [key, int(expected[key]["edges"]), edges.size()])
		# Inside the [-1,1] unit box: a sign the /0.13 conversion wasn't
		# skipped or double-applied.
		var out_of_box: int = 0
		for v in stars:
			var p: Vector2 = v
			if absf(p.x) > 1.01 or absf(p.y) > 1.01:
				out_of_box += 1
		ok(out_of_box == 0, "%s: every star lands inside the [-1,1] unit box (%d outside)" % [key, out_of_box])
	ok(IntroScreen._vessel_easy_shape("not_a_vessel").is_empty(), "an unknown vessel key yields {}")

	print("\n=== _populate_shapes() fills every vessel ===")
	var node = IntroScreen.new()
	node.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(node)
	await process_frame
	node._populate_shapes()
	for key in expected:
		ok(node._shape_stars.has(key) and node._shape_edges.has(key), "%s: star-graph populated" % key)

	print("\n=== clicking a rendered star/edge resolves to the right vessel ===")
	node.size = Vector2(1200, 800)
	node._update_shape_layout()
	for key in expected:
		var screen_stars: Array[Vector2] = node._screen_stars(key)
		ok(screen_stars.size() == int(expected[key]["stars"]), "%s: %d screen-space stars computed" % [key, int(expected[key]["stars"])])
		if screen_stars.is_empty():
			continue
		ok(node._vessel_at_point(screen_stars[0]) == key, "clicking directly on %s's star 0 resolves to '%s'" % [key, key])
		var pair: Vector2i = node._shape_edges[key][0]
		var mid: Vector2 = (screen_stars[pair.x] + screen_stars[pair.y]) * 0.5
		ok(node._vessel_at_point(mid) == key, "clicking the midpoint of %s's first edge resolves to '%s'" % [key, key])
	ok(node._vessel_at_point(Vector2(5, 5)) == "", "clicking empty space (top-left corner) resolves to no vessel")

	node.queue_free()
	await process_frame

	if fails == 0:
		print("\nALL PASS (0 failures)")
	else:
		print("\nFAILURES (%d failures)" % fails)
	finish()
