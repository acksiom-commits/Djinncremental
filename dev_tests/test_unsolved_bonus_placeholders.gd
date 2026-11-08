extends "res://dev_tests/test_base.gd"
# Constellation Slideout info panel (author 2026-10-29): an unsolved
# constellation's "Effects by Tier:" block -- the header and its "??? (puzzle
# unsolved)" line, plus the separator above it -- stays HIDDEN until The
# Archon (constellation 0) has been solved once. After that it shows as
# before. A solved constellation's real ladder is never hidden by the gate.
#
# InfoBonusLabel also carries "??? (puzzle unsolved)" text but is hidden in
# the scene and never shown; checked here so it stays that way.
#
# Judged on constellation 1 (The Spark) unsolved, across the Archon gate, and
# on constellation 0 itself before and after its first solve.

# NOTE (v0.4.0, 2026-11-07): the gate is the FIRST constellation (id 0), which is
# now The Spark; the constellation judged against it (id 1) is now The Archon.
# The messages below still say "Archon" for the gate and "Spark" for the
# subject, as they did before the swap: read them as first and second.
const PopoutScene = preload("res://ConstellationPopout.tscn")
const FIRST_KEY := "constellation_0_solve_count"
const SECOND_KEY := "constellation_1_solve_count"

var fails: int = 0


func ok(c: bool, s: String) -> void:
	if c:
		print("  PASS  ", s)
	else:
		print("  FAIL  ", s)
		fails += 1


## [block shown, its text]; also fails the run if InfoBonusLabel ever shows.
func _block(p) -> Array:
	p._refresh_info_panel()
	if p._info_bonus_label.visible:
		ok(false, "InfoBonusLabel stays hidden (it is hidden in the scene)")
	var shown: bool = p._info_tier_effects.visible and p._info_tier_effects_sep.visible
	return [shown, str(p._info_tier_effects.text) if p._info_tier_effects.visible else ""]


func run() -> void:
	await process_frame   # autoloads are unreachable until one frame has passed
	var gc = root.get_node_or_null("/root/GameContext")
	var cd = root.get_node_or_null("/root/ConstellationData")
	if gc == null or cd == null:
		ok(false, "autoloads reachable -- otherwise every check below is vacuous")
		finish()
		return
	var p = PopoutScene.instantiate()
	root.add_child(p)
	await process_frame
	var saved_unlocked = cd.unlocked.duplicate()
	var saved_assign = gc.assignments.duplicate(true)
	cd.unlocked = [0, 1]
	p._build_slots()
	await process_frame
	ok(p._slot_grid.visible, "precondition: the slot grid is showing")

	# The Spark, unsolved, while The Archon has never been solved.
	gc.assignments[FIRST_KEY] = 0
	gc.assignments[SECOND_KEY] = 0
	p._selected_slot = 1
	var b: Array = _block(p)
	ok(p._info_vbox.visible, "precondition: the info panel is showing for The Spark")
	ok(not b[0] and not p._info_tier_effects.visible and not p._info_tier_effects_sep.visible,
		"Archon unsolved: The Spark shows no effect line or separator")
	ok(p._tier_effects_tooltip(1) == "", "Archon unsolved: The Spark's slot has no Effects by Tier tooltip")

	# The Archon itself, unsolved.
	p._selected_slot = 0
	b = _block(p)
	ok(not p._info_tier_effects.visible, "The Archon's own panel hides the block before its first solve")

	# Solve The Archon once: its real ladder shows, and The Spark's placeholder returns.
	gc.assignments[FIRST_KEY] = 1
	b = _block(p)
	# Since 2026-11-04 the panel shows only the current tier, led by the
	# effect's name ("Archon Title Slots ▶ Dark +1"); the ladder is the tooltip.
	ok(b[0] and str(b[1]).contains("Sparks Multiplier ▶ Dark ×1.0") and not str(b[1]).contains("???") \
			and not str(b[1]).contains("Effects by Tier"),
		"Archon solved: its own line shows its effect at the current tier (%s)" % str(b[1]))
	var tip0: String = p._tier_effects_tooltip(0)
	ok(tip0.contains("Effects by Tier") and tip0.count("\n") == 4 and not tip0.contains("???"),
		"Archon solved: its slot's tooltip lists all four tiers")
	p._selected_slot = 1
	b = _block(p)
	ok(b[0] and str(b[1]).contains("??? (puzzle unsolved)"),
		"Archon solved: The Spark's line shows '??? (puzzle unsolved)' again")
	ok(p._tier_effects_tooltip(1) == "Effects by Tier: ??? (puzzle unsolved)",
		"Archon solved: The Spark's slot tooltip says the same")

	# A solved constellation is never hidden by the gate, even with the
	# Archon count at 0 (a hand-edited save, or any future ordering).
	gc.assignments[FIRST_KEY] = 0
	gc.assignments[SECOND_KEY] = 1
	b = _block(p)
	ok(b[0] and not str(b[1]).contains("???"),
		"a solved Spark shows its real ladder whatever the Archon's count")

	# Art-tier crossings show as their line alone, with no "Art-Tier
	# Achievements:" heading (author, 2026-11-04).
	var saved_crossings = gc.constellation_art_tier_crossings.duplicate()
	gc.constellation_art_tier_crossings[1] = 2
	_block(p)
	var art: String = str(p._info_art_achievement.text)
	ok(p._info_art_achievement.visible and art.contains("2 full-tier crossings") \
			and not art.contains("Art-Tier Achievements"),
		"art crossings show as one line, no heading (%s)" % art)
	gc.constellation_art_tier_crossings = saved_crossings

	# The Satchel's Art line names its permanent storage bump too (author,
	# 2026-11-06): "Storage Increase ▶ Art  ×3.0, ×1.05 P"; its other tiers are unchanged.
	var satchel: Dictionary = cd.get_constellation_def(5)
	var srows: Array = p._tier_rows(satchel, String(satchel.get("bonus_key", "")))
	var by_tier: Dictionary = {}
	for r in srows:
		by_tier[r[0]] = r[1]
	ok(String(satchel.get("name", "")) == "The Satchel" and String(by_tier.get("art", "")) == "Art  ×3.0, ×1.05 P",
		"The Satchel's Art line reads 'Art  ×3.0, ×1.05 P' (got '%s')" % by_tier.get("art", ""))
	ok(p.BONUS_DESCRIPTIONS.get("storage_multiplier", "") == "Storage Increase",
		"its effect is named 'Storage Increase', so the panel line reads 'Storage Increase ▶ Art  ×3.0, ×1.05 P'")
	ok(String(by_tier.get("lines", "")) == "Lines  ×3.0" and String(by_tier.get("stars", "")) == "Stars  ×2.0",
		"and its other tiers are unchanged (%s / %s)" % [by_tier.get("stars", ""), by_tier.get("lines", "")])

	gc.assignments = saved_assign
	cd.unlocked = saved_unlocked
	p.queue_free()
	await process_frame
	print("\nALL PASS (%d failures)" % fails if fails == 0 else "\nFAILURES (%d failures)" % fails)
	finish()
