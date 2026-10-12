extends "res://dev_tests/test_base.gd"
# PUZZLE GENERATION IS SPREAD ACROSS FRAMES (2026-10-12).
#
# Reported: the game hitched badly right after the first Expansion, which is
# when the next constellation's puzzle is pre-generated. Generation has always
# run on the main thread and handed a frame back every few steps; the note
# proof added for hidden first notes was one search that could run for over a
# second without a break, and the note repair around it never yielded. The
# alpha is a web build, so there is no worker thread to move it to: the proof
# is now a loop that stops every few milliseconds and carries on next frame.
#
# With a host to yield to (as in the game):
#  1. no stretch of work between two frames comes near a visible hitch, even
#     for the slowest constellation measured;
#  2. the proof really did hand frames back (so 1 is not passing by luck);
#  3. the puzzle is EXACTLY the one the same seed gives without a host, clue
#     for clue -- slicing changes when the work happens and nothing else.
# NOT checked here: the running game, and a web build's slower script speed.

const PuzzleScript = preload("res://constellation_logic_puzzle.gd")

## The longest gap between two frames this test tolerates. A 60 fps frame is
## 16.7 ms; the per-frame budgets are 2-5 ms plus whatever one un-sliced step
## costs. Generous on purpose: the test machine is not the player's.
const MAX_FRAME_GAP_MSEC: int = 120

var fails: int = 0
var _last_frame_msec: int = 0
var _worst_gap_msec: int = 0
var _frames: int = 0
var _watching: bool = false


func ok(c: bool, s: String) -> void:
	if c:
		print("  PASS  ", s)
	else:
		print("  FAIL  ", s)
		fails += 1


func _beginner_puzzle(cid: int, seed: int, host):
	var cd = load("res://constellation_data.gd").new()
	var gc = load("res://game_context.gd").new()
	cd._game_context = gc
	gc.constellation_difficulty[cid] = "easy"
	cd.player_seed = seed
	var def: Dictionary = cd.get_constellation_def(cid)
	var eng = load("res://click_sequence_puzzle_engine.gd").new()
	eng.set_constellation(cid, cd, gc)
	var sq: Array = eng.get_correct_star_sequence(cid)
	var g = PuzzleScript.new()
	g.difficulty = "easy"
	g.setup(int(def["star_count"]), def["line_pairs"], sq, seed, cid, def.get("name_theme", {}),
		cd.get_note_assignment(cid), cd.get_note_freqs(cid), host)
	return g


func _texts(g) -> Array:
	var out: Array = []
	for cl in g.chosen_form_clues:
		out.append(str(cl["text"]))
	return out


func _on_frame() -> void:
	if not _watching:
		return
	var now: int = Time.get_ticks_msec()
	_worst_gap_msec = maxi(_worst_gap_msec, now - _last_frame_msec)
	_last_frame_msec = now
	_frames += 1


func run() -> void:
	process_frame.connect(_on_frame)
	# Constellation 1 is the one pre-generated after the first Expansion;
	# constellation 3 is the slowest measured (7 stars, 18 notes).
	for cid in [1, 3]:
		print("=== constellation %d ===" % cid)
		var plain = _beginner_puzzle(cid, 11, null)
		var t0: int = Time.get_ticks_msec()
		await plain.generate_clues_forms()
		var plain_ms: int = Time.get_ticks_msec() - t0
		ok(plain.gate_passed, "without a host: passes the ship gate (%d clues, %d ms in one go)" % [plain.chosen_form_clues.size(), plain_ms])
		ok(plain.note_proof_frame_yields == 0, "without a host the proof never waits for a frame")

		var sliced = _beginner_puzzle(cid, 11, root)
		await process_frame
		_frames = 0
		_worst_gap_msec = 0
		_last_frame_msec = Time.get_ticks_msec()
		_watching = true
		var t1: int = Time.get_ticks_msec()
		await sliced.generate_clues_forms()
		_watching = false
		var sliced_ms: int = Time.get_ticks_msec() - t1
		print("    with a host: %d ms over %d frames; longest gap between frames %d ms; the proof handed back %d frames" % [
			sliced_ms, _frames, _worst_gap_msec, sliced.note_proof_frame_yields])
		ok(sliced.gate_passed, "with a host: passes the ship gate")
		ok(_texts(sliced) == _texts(plain) and not _texts(plain).is_empty(),
			"with a host: the clues are exactly the host-less ones, in order (%d clues)" % _texts(plain).size())
		ok(sliced.note_proof_frame_yields > 0, "the proof handed frames back (%d times)" % sliced.note_proof_frame_yields)
		ok(_worst_gap_msec <= MAX_FRAME_GAP_MSEC,
			"no gap between frames exceeded %d ms (longest %d ms)" % [MAX_FRAME_GAP_MSEC, _worst_gap_msec])
	process_frame.disconnect(_on_frame)

	if fails == 0:
		print("\nALL PASS (0 failures)")
	else:
		print("\nFAILURES (%d failures)" % fails)
	finish()
