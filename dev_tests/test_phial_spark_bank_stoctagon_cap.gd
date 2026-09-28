extends "res://dev_tests/test_base.gd"
# The Phial's spark_bank_capacity mechanic (get_phial_spark_bank_amount() in
# constellation_data.gd): CHANGED 2026-09-27, per user direction, from a
# flat placeholder cap (bonus_levels: 250/500/1000) to a fraction of the
# Stoctagon's OWN cap (GameContext.get_effective_storage_cap()) by Phial's
# tier -- stars x0.25, lines x0.5, art x1.0 -- so a currently-active
# Satchel's temporary storage_multiplier boost to the Stoctagon carries
# straight through into how much the Phial can bank.
#
# Also exercises the id fix this same change needed: get_phial_spark_bank_
# amount() still had a local `const PHIAL_ID: int = 5` left over from
# before the Phial/Satchel id swap (constellation_data.gd v0.3.8, The Phial
# is id 4 now) -- caught while touching this function for the cap change,
# not a pre-existing regression this test predates.
#
# Mutates the LIVE GameContext/ConstellationData autoloads (established
# pattern -- see test_hourglass_volition_cap.gd) rather than bare .new()
# instances: get_effective_storage_cap() looks up ConstellationData via
# get_node_or_null("/root/ConstellationData") internally, which only
# resolves against the real autoload tree, not an injected reference --
# confirmed the hard way, a first bare-instance draft of this test always
# saw the Satchel's boost as a no-op. Restores every touched field before
# finishing so later modules in the same run are unaffected.

const PHIAL_ID: int = 4
const PHIAL_OCTANT: int = 4
const SATCHEL_ID: int = 5
const SATCHEL_OCTANT: int = 5

var fails: int = 0
func ok(c: bool, s: String) -> void:
	if c:
		print("  PASS  ", s)
	else:
		print("  FAIL  ", s)
		fails += 1


func _activate_phial(cd, gc, invested: float) -> void:
	if not cd.unlocked.has(PHIAL_ID):
		cd.unlocked.append(PHIAL_ID)
	cd.active_per_octant[PHIAL_OCTANT] = PHIAL_ID
	gc.assignments["constellation_%d_solve_count" % PHIAL_ID] = 1
	gc.assignments["constellation_%d_volitions" % PHIAL_ID] = 1
	gc.constellation_spark_totals[str(PHIAL_ID)] = invested


func _activate_satchel(cd, gc, invested: float) -> void:
	if not cd.unlocked.has(SATCHEL_ID):
		cd.unlocked.append(SATCHEL_ID)
	cd.active_per_octant[SATCHEL_OCTANT] = SATCHEL_ID
	gc.assignments["constellation_%d_solve_count" % SATCHEL_ID] = 1
	gc.assignments["constellation_%d_volitions" % SATCHEL_ID] = 1
	gc.constellation_spark_totals[str(SATCHEL_ID)] = invested


func run() -> void:
	await process_frame  # autoloads unreachable from root before one frame
	var gc = root.get_node_or_null("/root/GameContext")
	var cd = root.get_node_or_null("/root/ConstellationData")
	if not gc or not cd:
		print("  (autoloads not reachable -- cannot test)")
		print("ALL PASS (0 failures)")
		finish()
		return

	# Save live state to restore afterward.
	var saved_storage_cap: BigNum = gc.storage_cap.copy()
	var saved_uonite: BigNum = gc.uonite.copy()
	var saved_assignments: Dictionary = gc.assignments.duplicate(true)
	var saved_spark_totals: Dictionary = gc.constellation_spark_totals.duplicate(true)
	var saved_unlocked: Array = cd.unlocked.duplicate(true)
	var saved_active_per_octant: Array = cd.active_per_octant.duplicate(true)

	gc.storage_cap = BigNum.from_int(987)
	gc.uonite = BigNum.from_int(100000)  # comfortably enough to hit the cap at any rate

	print("=== tier fraction: stars x0.25, lines x0.5, art x1.0 of the Stoctagon's cap ===")
	for pair in [["stars", 4181.0, 0.25], ["lines", 10946.0, 0.5], ["art", 28657.0, 1.0]]:
		var tier: String = pair[0]
		var invested: float = pair[1]
		var frac: float = pair[2]
		_activate_phial(cd, gc, invested)
		ok(cd.get_visual_state(PHIAL_ID) == tier,
			"test setup: invested sparks land on tier '%s'" % tier)
		var expected: BigNum = gc.get_effective_storage_cap().mul_float(frac)
		var got: BigNum = cd.get_phial_spark_bank_amount()
		ok(got.equals(expected),
			"tier %s: banked %s == Stoctagon cap x%.2f (%s)"
				% [tier, got.to_display_string(), frac, expected.to_display_string()])

	print("\n=== dark tier (no investment): banks nothing ===")
	_activate_phial(cd, gc, 0.0)
	ok(cd.get_visual_state(PHIAL_ID) == "dark", "test setup: tier is 'dark'")
	ok(cd.get_phial_spark_bank_amount().is_zero(), "dark tier banks 0")

	print("\n=== Phial unlocked but NOT the active constellation in its octant: banks nothing ===")
	_activate_phial(cd, gc, 28657.0)
	cd.active_per_octant[PHIAL_OCTANT] = -1  # nothing active in the Phial's octant
	ok(cd.get_phial_spark_bank_amount().is_zero(), "inactive Phial banks 0 even at full tier/investment")

	print("\n=== an active Satchel's temporary storage_multiplier carries through ===")
	cd.active_per_octant[SATCHEL_OCTANT] = -1  # Satchel not active yet
	_activate_phial(cd, gc, 28657.0)  # Phial at art tier (x1.0 fraction)
	var base_cap: BigNum = gc.get_effective_storage_cap()
	var base_banked: BigNum = cd.get_phial_spark_bank_amount()
	ok(base_banked.equals(base_cap),
		"before Satchel: Phial's cap equals the Stoctagon's own (unboosted) cap (%s)" % base_cap.to_display_string())
	_activate_satchel(cd, gc, 28657.0)  # Satchel at art tier too -- storage_multiplier x3.0
	var boosted_cap: BigNum = gc.get_effective_storage_cap()
	var boosted_banked: BigNum = cd.get_phial_spark_bank_amount()
	ok(boosted_cap.is_greater_than(base_cap),
		"test setup: an active Satchel actually raised the Stoctagon's effective cap (%s -> %s)"
			% [base_cap.to_display_string(), boosted_cap.to_display_string()])
	ok(boosted_banked.equals(boosted_cap),
		"after Satchel: Phial's cap tracks the BOOSTED Stoctagon cap, not the static one (%s)"
			% boosted_cap.to_display_string())
	ok(boosted_banked.is_greater_than(base_banked),
		"Phial actually banks more while the Satchel's boost is active (%s -> %s)"
			% [base_banked.to_display_string(), boosted_banked.to_display_string()])

	# Restore live state.
	gc.storage_cap = saved_storage_cap
	gc.uonite = saved_uonite
	gc.assignments = saved_assignments
	gc.constellation_spark_totals = saved_spark_totals
	cd.unlocked = saved_unlocked
	cd.active_per_octant = saved_active_per_octant

	print("\nALL PASS (%d failures)" % fails if fails == 0 else "\nFAILURES (%d failures)" % fails)
	finish()
