extends "res://dev_tests/test_base.gd"
# A new game gets its own seed (2026-11-01). set_player_seed had no callers, so
# player_seed stayed 0 and every game had the same sky, the same star-to-note
# assignments and the same first puzzles until RESET.
#
#  1. Beginning a game sets a seed, and the Vessel, as the start screen always has.
#  2. Two games differ where the seed reaches: note assignments and star placement.
#  3. The seed survives a save, so a player's puzzles stay theirs.
#  4. A save from before this keeps its 0, or its puzzles would all change.
#
# Headless can't play the start screen (it leaves for RootUI when a save exists),
# so this calls what _confirm_vessel calls.

const IntroScreen = preload("res://intro_screen.gd")
const GAMES: int = 6
const CID: int = 1

var fails: int = 0


func ok(c: bool, s: String) -> void:
	if c:
		print("  PASS  ", s)
	else:
		print("  FAIL  ", s)
		fails += 1


func run() -> void:
	await process_frame
	var gc = load("res://game_context.gd").new()
	var cd = load("res://constellation_data.gd").new()
	cd._game_context = gc

	print("=== beginning a game ===")
	ok(cd.player_seed == 0, "before a game begins, the seed is the 0 tests rely on")
	var old_notes: Array = cd.get_note_assignment(CID).duplicate()
	var old_sky: Vector3 = cd.get_star_positions(CID)[0]
	IntroScreen._begin_new_game(gc, cd, "ring")
	ok(cd.player_seed != 0, "beginning a game sets a seed (%d)" % cd.player_seed)
	ok(gc.chosen_vessel == "ring", "and still records the Vessel")
	ok(cd.get_puzzle_seed(CID) == cd.player_seed, "puzzles are built from it")

	print("\n=== games differ ===")
	var seeds: Dictionary = {}
	var notes: Dictionary = {}
	var sky_moved: int = 0
	for _i in GAMES:
		IntroScreen._begin_new_game(gc, cd, "ring")
		seeds[cd.player_seed] = true
		notes[str(cd.get_note_assignment(CID))] = true
		if not (cd.get_star_positions(CID)[0] as Vector3).is_equal_approx(old_sky):
			sky_moved += 1
	ok(seeds.size() == GAMES, "%d games, %d different seeds" % [GAMES, seeds.size()])
	ok(notes.size() >= 3, "star-to-note assignments differ (%d different over %d games)" % [notes.size(), GAMES])
	ok(sky_moved == GAMES, "the sky moved in %d of %d games, not stuck on a stale cache" % [sky_moved, GAMES])

	print("\n=== the seed lasts ===")
	IntroScreen._begin_new_game(gc, cd, "jar")
	var seed_now: int = cd.player_seed
	var notes_now: String = str(cd.get_note_assignment(CID))
	var saved = JSON.parse_string(JSON.stringify(cd.get_save_data()))
	var reloaded = load("res://constellation_data.gd").new()
	reloaded._game_context = gc
	reloaded.load_save_data(saved)
	ok(reloaded.player_seed == seed_now, "a save brings it back (%d)" % reloaded.player_seed)
	ok(str(reloaded.get_note_assignment(CID)) == notes_now, "with the same assignments")

	print("\n=== older saves keep their puzzles ===")
	var older = load("res://constellation_data.gd").new()
	older._game_context = gc
	var old_save: Dictionary = JSON.parse_string(JSON.stringify(cd.get_save_data()))
	old_save["player_seed"] = 0
	older.load_save_data(old_save)
	ok(older.player_seed == 0, "a save holding 0 stays 0")
	ok(str(older.get_note_assignment(CID)) == str(old_notes), "so its assignments do not change")

	older.free()
	reloaded.free()
	cd.free()
	gc.free()
	if fails == 0:
		print("\nALL PASS (0 failures)")
	else:
		print("\nFAILURES (%d failures)" % fails)
	finish()
