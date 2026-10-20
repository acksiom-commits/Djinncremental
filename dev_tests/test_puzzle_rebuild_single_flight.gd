extends "res://dev_tests/test_base.gd"
# A constellation's puzzle is rebuilt by ONE build at a time, and the Study
# panel cannot be played while its RESET is rebuilding it (2026-10-20, reported
# on The Bellows as "the puzzle keeps resetting without my clicking RESET a
# second time").
#
#  1. Two builds started for one constellation (a RESET, then the cache-miss
#     build that selecting it during the reset used to start): the older one is
#     aborted and only the newer one's result is delivered. Before, both were,
#     and the later of the two replaced the puzzle.
#  2. The cache-miss / pre-generation entry point starts nothing while a build
#     is running or a puzzle is already cached.
#  3. The seed a RESET builds from is kept, through a save round trip, so the
#     Archon boot check and a rebuild after a lost cache agree with it.
#  4. While its rebuild runs, the Study panel's board is covered (clicks stop at
#     the cover) and RESET / Easy-Hard are disabled, for that constellation only;
#     regeneration_finished lifts it. Before, the board stayed live and marks
#     made on it were silently dropped.

const OverlayScene = preload("res://ConstellationStudyOverlay.tscn")
const FRAME_CAP: int = 60000

var fails: int = 0


## root_ui.gd without its scene: RootUI.tscn will not instantiate headless, and
## its _ready/_process/input handlers expect that scene's nodes.
class TestRoot extends "res://root_ui.gd":
	func _ready() -> void:
		pass

	func _process(_delta: float) -> void:
		pass

	func _input(_event: InputEvent) -> void:
		pass

	func _unhandled_input(_event: InputEvent) -> void:
		pass


## Stands in for ConstellationOverlay, which _generate_puzzle asks for the melody.
class FakeOverlay extends Node:
	var seq: Array = []

	func get_correct_star_sequence(_cid: int) -> Array:
		return seq


func ok(c: bool, s: String) -> void:
	if c:
		print("  PASS  ", s)
	else:
		print("  FAIL  ", s)
		fails += 1


func run() -> void:
	await process_frame

	print("=== 1. two builds for one constellation: only the newer one is delivered ===")
	var cid: int = 0
	var cd = load("res://constellation_data.gd").new()
	var gc = load("res://game_context.gd").new()
	cd._game_context = gc
	gc.constellation_difficulty[cid] = "easy"
	cd.player_seed = 11
	var eng = load("res://click_sequence_puzzle_engine.gd").new()
	eng.set_constellation(cid, cd, gc)
	var holder := Node.new()
	root.add_child(holder)
	var ui = TestRoot.new()
	ui.name = "RootUI"
	ui.game_context = gc
	holder.add_child(ui)
	var ov := FakeOverlay.new()
	ov.name = "ConstellationOverlay"
	ov.seq = eng.get_correct_star_sequence(cid)
	holder.add_child(ov)
	var def: Dictionary = cd.get_constellation_def(cid)
	var delivered: Array = []
	var cb := func(_c: int, p): delivered.append(p)
	ui._generate_puzzle(cid, cd, def, 11, "first build", cb)
	var builds = ui.get("_puzzle_builds")
	var p1 = builds.get(cid) if builds != null else null
	ui._generate_puzzle(cid, cd, def, 23, "second build", cb)
	var p2 = builds.get(cid) if builds != null else null
	ok(p1 != null and p2 != null and p1 != p2, "each start registers its own build")
	ok(p1 != null and bool(p1.abort_requested), "the older build is told to stop")
	var frames: int = 0
	var settle: int = 0
	while frames < FRAME_CAP and delivered.size() < 2:
		await process_frame
		frames += 1
		if not delivered.is_empty():
			settle += 1
			if builds != null and builds.is_empty() and settle > 120:
				break
	print("    %d frame(s); %d result(s) delivered" % [frames, delivered.size()])
	ok(frames < FRAME_CAP, "the builds finished within the frame cap")
	ok(delivered.size() == 1, "exactly one result is delivered (%d)" % delivered.size())
	ok(delivered.size() >= 1 and delivered[0] == p2, "and it is the newer build's")
	ok(p2 != null and bool(p2.gate_passed), "the newer build passed the gate")
	ok(builds != null and not builds.has(cid), "nothing is left registered")

	print("\n=== 2. the cache-miss entry point never starts a second build ===")
	var real_cd = root.get_node_or_null("/root/ConstellationData")
	ok(real_cd != null, "ConstellationData autoload reachable")
	if real_cd != null and builds != null:
		var sentinel = load("res://constellation_logic_puzzle.gd").new()
		builds[5] = sentinel
		ui._start_puzzle_generation(5)
		ok(builds.get(5) == sentinel, "with a build running, no new build replaces it")
		builds.erase(5)
		# A puzzle already cached: left alone (pre-generation used to rebuild it).
		var key: String = "5"
		var had: bool = real_cd._puzzle_cache.has(key)
		var saved = real_cd._puzzle_cache.get(key)
		real_cd._puzzle_cache[key] = {"marker": true}
		ui._start_puzzle_generation(5)
		ok(not builds.has(5), "with a puzzle cached, no build starts")
		if had:
			real_cd._puzzle_cache[key] = saved
		else:
			real_cd._puzzle_cache.erase(key)

	print("\n=== 3. a RESET's seed is kept, through a save round trip ===")
	var cd2 = load("res://constellation_data.gd").new()
	cd2.player_seed = 5
	ok(cd2.get_puzzle_seed(3) == 5, "never reset: the player seed")
	cd2.puzzle_seed_overrides["3"] = 777
	ok(cd2.get_puzzle_seed(3) == 777 and cd2.get_puzzle_seed(1) == 5, "reset: that constellation's own seed, the others unchanged")
	var round_trip = JSON.parse_string(JSON.stringify(cd2.get_save_data()))
	var cd3 = load("res://constellation_data.gd").new()
	cd3.load_save_data(round_trip)
	ok(cd3.get_puzzle_seed(3) == 777 and cd3.get_puzzle_seed(1) == cd3.player_seed, "the same after save and load (%d)" % cd3.get_puzzle_seed(3))

	print("\n=== 4. the Study panel is covered while its rebuild runs ===")
	var h = OverlayScene.instantiate()
	root.add_child(h)
	await process_frame
	h._constellation_id = 3
	h._reset_confirm.confirmed.emit()
	await process_frame
	var cover = h.get("_regen_cover")
	var clip: Control = h.get_node(h.PANEL_ROOT_PATH + "/OuterMargin/OuterVBox/CarouselClip")
	ok(cover != null and cover.visible, "after 'Yes, Reset' the board is covered")
	ok(cover != null and cover.mouse_filter == Control.MOUSE_FILTER_STOP and clip.get_child(clip.get_child_count() - 1) == cover,
		"the cover is on top and stops clicks")
	# Anchors, not rects: headless, the carousel lays out at zero width, so a
	# rect comparison would pass for any cover at all.
	ok(cover != null and cover.anchor_left == 0.0 and cover.anchor_top == 0.0 and cover.anchor_right == 1.0 and cover.anchor_bottom == 1.0 \
		and cover.offset_left == 0.0 and cover.offset_top == 0.0 and cover.offset_right == 0.0 and cover.offset_bottom == 0.0,
		"it is anchored to the whole board")
	ok(h._reset_btn.disabled, "RESET is disabled meanwhile")
	h._constellation_id = 1
	h._refresh_difficulty_button()
	ok(cover != null and not cover.visible and not h._reset_btn.disabled, "another constellation's board is not covered")
	h._constellation_id = 3
	h._refresh_difficulty_button()
	ok(cover != null and cover.visible and h._reset_btn.disabled, "back on the rebuilding one, it is again")
	if h.has_method("regeneration_finished"):
		h.regeneration_finished(3)
	ok(cover != null and not cover.visible and not h._reset_btn.disabled, "regeneration_finished lifts it")

	h.queue_free()
	holder.queue_free()
	gc.free()
	print("\nALL PASS (%d failures)" % fails if fails == 0 else "\nFAILURES (%d failures)" % fails)
	finish()
