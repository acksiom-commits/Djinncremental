extends "res://dev_tests/test_base.gd"
# Uonite strip bar bug (user-reported 2026-09-22, TWICE): after the 2nd
# Expansion, cycle cap is 3 Uonites (60 Motes), player had exactly 60
# Motes banked -- bar should read FULL, but read less than half.
#
# Root cause, corrected mid-session: there is no partial Expansion.
# _on_create_uonite_pressed() (root_ui.gd) calls
# production_manager.manual_create_uonite(), and on success calls
# _play_expansion_animation(), which itself unconditionally tails into
# _do_prestige_reset() -> game_context.do_prestige_reset() -- i.e.
# clicking Create Uonite batch-converts banked motes AND immediately
# triggers Expansion in one atomic action. There is no such thing as
# "some Uonites created this cycle, more Motes still banked toward the
# next" -- uonites_this_cycle is only ever transiently nonzero during the
# animation's own in-flight window, and motes_this_cycle is capped to
# [0,20] and reset on each Uonite completion, so it can NEVER reflect a
# raw stockpile bigger than one Uonite's worth (e.g. 60 Motes). The bar
# must read the raw mote_uonite stockpile directly, same source
# uonite_icosahedron.gd's own cosmetic display already uses.

var fails: int = 0
func ok(c: bool, s: String) -> void:
	if c:
		print("  PASS  ", s)
	else:
		print("  FAIL  ", s)
		fails += 1


func run() -> void:
	var gc = load("res://game_context.gd").new()

	# --- Case 1: storage headroom generous -- cap is the plain Fibonacci
	# cap*20, current is the raw Mote stockpile (clamped to the cap). ---
	gc.expansions = 1  # cycle cap = 2
	gc.storage_cap = BigNum.from_int(987)  # base -> get_uonite_storage_cap() = 33, plenty
	gc.uonite = BigNum.from_int(3)
	gc.mote_uonite = BigNum.from_int(25)
	var p1: Vector2i = gc.get_uonite_cycle_progress()
	print("  case 1 (storage not binding): current=%d cap=%d" % [p1.x, p1.y])
	ok(p1.y == 40, "cap is the plain Fibonacci cap*20 (got %d)" % p1.y)
	ok(p1.x == 25, "current reads the raw mote_uonite stockpile directly (got %d)" % p1.x)

	# --- Case 2: the ORIGINAL reported bug shape -- persistent uonite
	# total already at the storage cap, so no further Uonite can complete
	# this cycle at all, even though raw Motes are banked. ---
	gc.expansions = 1  # cycle cap = 2
	gc.storage_cap = BigNum.from_int(200)  # get_uonite_storage_cap() = floor(200^2/28801) = 1
	gc.uonite = BigNum.from_int(1)  # already AT the storage cap
	gc.mote_uonite = BigNum.from_int(100)  # over 100 raw motes banked, per the real report
	var p2: Vector2i = gc.get_uonite_cycle_progress()
	print("  case 2 (storage fully exhausted): current=%d cap=%d" % [p2.x, p2.y])
	ok(p2.x == 0 and p2.y == 1,
		"fully storage-blocked reads as an empty 0/1 bar, not a stuck-halfway bar (got %d/%d)" % [p2.x, p2.y])

	# --- Case 3: storage allows exactly ONE Uonite's worth (smaller than
	# the Fibonacci cap of 2) -- cap should reflect storage's 1, and
	# current should clamp there even with more raw Motes banked. ---
	gc.expansions = 1  # cycle cap = 2
	gc.storage_cap = BigNum.from_int(200)  # storage cap = 1
	gc.uonite = BigNum.from_int(0)  # headroom for exactly 1 more
	gc.mote_uonite = BigNum.from_int(35)  # more than one Uonite's worth banked
	var p3: Vector2i = gc.get_uonite_cycle_progress()
	print("  case 3 (storage allows exactly 1, excess motes banked): current=%d cap=%d" % [p3.x, p3.y])
	ok(p3.y == 20, "cap reflects the storage-derived limit (1 Uonite = 20), not the Fibonacci 2 (got %d)" % p3.y)
	ok(p3.x == 20, "current clamps to the achievable cap, ignoring excess raw-Mote banking (got %d)" % p3.x)

	# --- Case 4: THE LATEST reported bug -- 2nd Expansion, cap is 3
	# Uonites (60 Motes), player has exactly 60 raw Motes banked. Bar must
	# read completely full. ---
	gc.expansions = 2  # cycle cap = 3
	gc.storage_cap = BigNum.from_int(987)  # plenty of storage headroom
	gc.uonite = BigNum.from_int(0)
	gc.mote_uonite = BigNum.from_int(60)
	var p4: Vector2i = gc.get_uonite_cycle_progress()
	print("  case 4 (2nd Expansion, 60 motes banked, cap 3): current=%d cap=%d" % [p4.x, p4.y])
	ok(p4.y == 60, "cap is 3 Uonites worth of Motes (got %d)" % p4.y)
	ok(p4.x == 60, "60 banked motes reads as completely full, not stuck partway (got %d)" % p4.x)

	print("\nALL PASS (%d failures)" % fails if fails == 0 else "\nFAILURES (%d failures)" % fails)
	finish()
