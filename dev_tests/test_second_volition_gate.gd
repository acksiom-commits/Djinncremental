extends "res://dev_tests/test_base.gd"
# The 2nd Volition must not be granted before the dialogue that explains it.
#
# _check_volition_grant() awards Volitions on archon_foci crossing
# 5 / 25 / 125. Foci come from many unrelated milestones (resource firsts,
# totals thresholds, Expansion counts, Tetrad categories), so crossing 25
# says nothing about tutorial progress — a player could be handed Volition
# #2 with no idea where it came from. The design is "all fifteen Tetrad
# varieties, THEN a Particle", which is exactly when
# enqueue_first_particle() ("Two Volitions!") fires.
#
# Tested through _second_volition_gate_open() rather than by driving the
# whole grant, because the gate IS the fix; the grant arithmetic around it
# was already correct.
#
# THE CASE THAT NEARLY SHIPPED BROKEN: game_context's reset zeroes
# `particle`, and _check_volition_grant() is called right after a prestige
# to re-grant Volitions from lifetime Foci. A purely live condition would
# re-close the gate every prestige and claw the player back to one
# Volition. The latch on first_particle_done is what prevents that, and
# the prestige case below is what proves it.

# A bare root_ui.gd instance with the two collaborators injected, NOT the
# full RootUI.tscn. Instantiating that scene headless aborts before this
# test's first line — it wires dozens of child controls and autoloads. Both
# `game_context` and `archon_dialogue_manager` are plain `var ... = null`
# assigned at runtime (root_ui.gd:42/46), so injecting real instances of
# each is enough for the gate and the grant, which touch nothing else.
var fails: int = 0


func ok(c: bool, s: String) -> void:
	if c:
		print("  PASS  ", s)
	else:
		print("  FAIL  ", s)
		fails += 1


func run() -> void:
	var ui = load("res://root_ui.gd").new()
	var gc = load("res://game_context.gd").new()
	var adm = load("res://archon_dialogue_manager.gd").new()
	ui.game_context = gc
	ui.archon_dialogue_manager = adm

	# ── closed on a fresh board ──────────────────────────────────────────
	print("=== closed before the tutorial chain completes ===")
	adm.all_tetrads_done = false
	adm.first_particle_done = false
	gc.particle = BigNum.zero()
	ok(not ui._second_volition_gate_open(), "closed with no tetrads and no particle")

	adm.all_tetrads_done = true
	ok(not ui._second_volition_gate_open(),
		"still closed with all tetrads but NO particle — the design is tetrads THEN particle")

	adm.all_tetrads_done = false
	gc.particle = BigNum.from_int(1)
	ok(not ui._second_volition_gate_open(),
		"still closed with a particle but tetrads incomplete")

	# ── opens on the real condition ──────────────────────────────────────
	print("\n=== opens on tetrads + particle ===")
	adm.all_tetrads_done = true
	gc.particle = BigNum.from_int(1)
	ok(ui._second_volition_gate_open(), "open once both hold")

	# ── the prestige case ────────────────────────────────────────────────
	print("\n=== stays open across a prestige ===")
	adm.first_particle_done = true          # dialogue has played
	gc.particle = BigNum.zero()             # what reset does
	ok(ui._second_volition_gate_open(),
		"still open after reset zeroes particle, because the dialogue already played")
	adm.all_tetrads_done = false            # belt and braces
	ok(ui._second_volition_gate_open(),
		"latch holds even if the tetrad flag is also cleared")

	# ── the grant itself respects the gate ───────────────────────────────
	# 25 Foci is the 2nd Volition's threshold; with the gate shut the grant
	# must cap at 1, and must NOT quietly accumulate a 3rd at 125 either.
	print("\n=== _check_volition_grant caps at 1 while gated ===")
	adm.first_particle_done = false
	adm.all_tetrads_done = false
	gc.particle = BigNum.zero()
	gc.volitions = 0
	gc.archon_foci = 25
	ui._check_volition_grant()
	ok(gc.volitions == 1, "25 Foci with the gate shut grants only the 1st (%d)" % gc.volitions)

	gc.archon_foci = 125
	ui._check_volition_grant()
	ok(gc.volitions == 1, "125 Foci with the gate shut still grants only the 1st (%d)" % gc.volitions)

	print("\n=== and releases them once the gate opens ===")
	adm.all_tetrads_done = true
	gc.particle = BigNum.from_int(1)
	ui._check_volition_grant()
	ok(gc.volitions == 3, "125 Foci with the gate open grants all three (%d)" % gc.volitions)

	# Nothing is ever taken BACK: a save that already got its early Volition
	# keeps it, because the grant only ever adds.
	print("\n=== never revokes ===")
	adm.first_particle_done = false
	adm.all_tetrads_done = false
	gc.particle = BigNum.zero()
	ui._check_volition_grant()
	ok(gc.volitions == 3, "re-closing the gate does not remove granted Volitions (%d)" % gc.volitions)

	ui.free()
	gc.free()
	adm.free()
	print("\nALL PASS (%d failures)" % fails if fails == 0 else "\nFAILURES (%d failures)" % fails)
	finish()
