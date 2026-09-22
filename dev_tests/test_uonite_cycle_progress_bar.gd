extends "res://dev_tests/test_base.gd"
# Uonite strip bar bug (user-reported 2026-09-22): after the 1st
# Expansion but before the 2nd, the Fibonacci cycle cap is 2 Uonites (40
# Motes), and the player had over 100 Motes banked -- the bar should
# read full, but stalled around half.
#
# Root cause: the bar's cap/value were computed straight from
# get_uonite_cycle_cap() alone (game_context.get_uonite_cycle_progress(),
# formerly inlined in root_ui.gd), with no awareness that
# get_uonite_storage_cap() (added earlier the same session) ALSO caps
# actual creation via manual_create_uonite()/_add_resource()'s min() of
# the two. A player whose PERSISTENT uonite total was already close to
# the storage cap had uonites_this_cycle stuck below the Fibonacci cap
# while raw Mote production kept climbing motes_this_cycle to its own
# 0-20 ceiling with nothing to reset it -- the bar's own max_value never
# reflected that the storage cap, not the Fibonacci cap, was the real
# ceiling that cycle.

var fails: int = 0
func ok(c: bool, s: String) -> void:
	if c:
		print("  PASS  ", s)
	else:
		print("  FAIL  ", s)
		fails += 1


func run() -> void:
	var gc = load("res://game_context.gd").new()

	# --- Case 1: storage headroom generous -- matches the OLD (Fibonacci-
	# only) behavior exactly, confirming this fix doesn't change anything
	# for the common case. ---
	gc.expansions = 1  # cycle cap = 2
	gc.storage_cap = BigNum.from_int(987)  # base -> get_uonite_storage_cap() = 33, plenty
	gc.uonite = BigNum.from_int(3)
	gc.uonites_this_cycle = 1
	gc.motes_this_cycle = 5
	var p1: Vector2i = gc.get_uonite_cycle_progress()
	print("  case 1 (storage not binding): current=%d cap=%d" % [p1.x, p1.y])
	ok(p1.y == 40, "cap is the plain Fibonacci cap*20 (got %d)" % p1.y)
	ok(p1.x == 25, "current = uonites_this_cycle*20 + motes_this_cycle (got %d)" % p1.x)

	# --- Case 2: the reported bug -- persistent uonite total already at
	# the storage cap, well past the point ANY Uonite can complete this
	# cycle, yet the player has over 100 raw Motes banked (motes_this_cycle
	# pinned at its own 20 ceiling). Cap must come from storage, not the
	# Fibonacci limit, and current must not show misleading Mote progress
	# toward a Uonite that can never complete. ---
	gc.expansions = 1  # cycle cap = 2
	gc.storage_cap = BigNum.from_int(200)  # get_uonite_storage_cap() = floor(200^2/28801) = 1
	gc.uonite = BigNum.from_int(1)  # already AT the storage cap
	gc.uonites_this_cycle = 0  # none of it came from this cycle
	gc.motes_this_cycle = 20  # raw motes maxed out, over 100 in the real report
	var p2: Vector2i = gc.get_uonite_cycle_progress()
	print("  case 2 (storage fully exhausted before this cycle): current=%d cap=%d" % [p2.x, p2.y])
	ok(p2.x == 0 and p2.y == 1,
		"fully storage-blocked reads as an empty 0/1 bar, not a stuck-halfway 20/40 (got %d/%d)" % [p2.x, p2.y])

	# --- Case 3: storage allows exactly ONE more this cycle (smaller than
	# the Fibonacci cap of 2) -- cap should reflect storage's 1, and Mote
	# progress toward a 2nd Uonite should NOT show once that 1 is used. ---
	gc.expansions = 1  # cycle cap = 2
	gc.storage_cap = BigNum.from_int(200)  # storage cap = 1
	gc.uonite = BigNum.from_int(0)  # cycle starts with headroom for exactly 1
	gc.uonites_this_cycle = 1  # that 1 has been used up this cycle
	gc.motes_this_cycle = 20  # more raw motes keep piling up regardless
	var p3: Vector2i = gc.get_uonite_cycle_progress()
	print("  case 3 (storage allows exactly 1, already used): current=%d cap=%d" % [p3.x, p3.y])
	ok(p3.y == 20, "cap reflects the storage-derived limit (1 Uonite = 20), not the Fibonacci 2 (got %d)" % p3.y)
	ok(p3.x == 20, "current caps at the achieved 1 Uonite, ignoring further raw-Mote climb (got %d)" % p3.x)

	# --- Case 4: same as case 3, but the 1 achievable slot is NOT yet
	# used -- motes_this_cycle progress SHOULD show, since it's progress
	# toward a Uonite that genuinely can still complete. ---
	gc.uonites_this_cycle = 0
	gc.motes_this_cycle = 12
	var p4: Vector2i = gc.get_uonite_cycle_progress()
	print("  case 4 (storage allows exactly 1, still available): current=%d cap=%d" % [p4.x, p4.y])
	ok(p4.x == 12, "partial Mote progress shows while a slot is still genuinely available (got %d)" % p4.x)

	print("\nALL PASS (%d failures)" % fails if fails == 0 else "\nFAILURES (%d failures)" % fails)
	finish()
