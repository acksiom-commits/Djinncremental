extends "res://dev_tests/test_base.gd"
# The Study panel opens showing what the board has worked out, without a click
# (reported 2026-10-19: after loading a save, the panel showed out-of-date
# tags and popups until something was clicked).
#
# Loading a board clears the derived layer (_reset_derived), and only a refresh
# rebuilds it. show_for_constellation now refreshes. Fixture: a saved board
# whose one entry is a name with every other star crossed out. The board ties
# the name to the remaining star only by working it out; the star's tag must
# show the name the moment the panel opens.

const OverlayScene = preload("res://ConstellationStudyOverlay.tscn")
const PuzzleScript = preload("res://constellation_logic_puzzle.gd")
const CID := 4

var fails: int = 0


func ok(c: bool, s: String) -> void:
	if c:
		print("  PASS  ", s)
	else:
		print("  FAIL  ", s)
		fails += 1


func run() -> void:
	await process_frame
	var gc = root.get_node("GameContext")
	var cd = root.get_node("ConstellationData")
	gc.constellation_difficulty[CID] = "easy"
	gc.constellation_identity_revealed[CID] = true
	cd.player_seed = 11
	var def: Dictionary = cd.get_constellation_def(CID)
	var eng = load("res://click_sequence_puzzle_engine.gd").new()
	eng.set_constellation(CID, cd, gc)
	var g = PuzzleScript.new()
	g.difficulty = "easy"
	g.setup(int(def["star_count"]), def["line_pairs"], eng.get_correct_star_sequence(CID), 11, CID, def.get("name_theme", {}),
		cd.get_note_assignment(CID), cd.get_note_freqs(CID), null)
	await g.generate_clues_forms()
	var cache: Dictionary = g.to_cache_dict()
	var nm: String = str(g.star_names[0])
	var elim: Dictionary = {}
	for s in range(1, g.star_count):
		elim[s] = 2
	cache["player_puzzle_notes"] = {"match_records": [{"name": nm, "star_elim": elim}]}
	cd.set_puzzle_cache(CID, cache)

	var host = OverlayScene.instantiate()
	root.add_child(host)
	await process_frame
	host._gc = gc
	host._cd = cd
	host._star_map_control.size = Vector2(700, 500)
	host.show_for_constellation(CID)
	await process_frame
	await process_frame
	ok(host._star_count == g.star_count, "precondition: the panel loaded the saved puzzle (%d stars)" % host._star_count)
	var shown: String = str(host._widgets._confirmed_name_for_star(0))
	ok(shown == nm, "on opening, star 0's tag already names it %s (got '%s')" % [nm, shown])
	host._deduction._full_propagation_refresh()
	ok(str(host._widgets._confirmed_name_for_star(0)) == nm, "and a refresh agrees, so the fixture really derives it")

	host.queue_free()
	cd.clear_puzzle_cache(CID)
	await process_frame
	print("\nALL PASS (%d failures)" % fails if fails == 0 else "\nFAILURES (%d failures)" % fails)
	finish()
