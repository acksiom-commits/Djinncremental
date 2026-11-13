extends "res://dev_tests/test_base.gd"
# A command stack that fills every Constellation in turn after an Oscillation,
# starting with The Djinn (author's sequence, 2026-11-10). The whole stack
# waits for The Djinn's Tier 1, so The Djinn's own feeding has to get it there.
#
# The state at the end of a cycle (the author's premise):
#   - two parent Volitions: A on The Archon, D on The Djinn (25-124 Foci)
#   - child Volitions (the Archon's grant) on The Phial and The Satchel
#   - The Djinn on Endow with Foci on it; every Constellation full
#
# At the Oscillation the Satchel's +5% and the Phial's bank are paid (both
# read before the wipe), the children clear, A and D stay, and Kaleb goes back
# to bar 1, still running, and WAITS. The Djinn feeds itself from the reserve
# (the Phial's bank plus summoning) up to Tier 1, and then Kaleb starts.
#
# The travelling Volition is D, not A: the Archon grants its children only
# while a PARENT Volition is on the Archon itself
# (ConstellationData.get_bonus_volition_grant()), so moving A away would take
# away the children the Phial and Satchel need.
#
# The stack (fill_stack() below), 22 bars:
#    1        Assign Uonites -> Sparks 99999   (the Oscillation zeroed the wheel)
#    2-3      If Sparks < press -> self; Supply The Djinn xN    (on D)
#    4-5      the same for The Archon                           (on A)
#    6        Move Volition The Djinn -> The Spark              (D travels)
#    7-8      The Spark;      9 Move -> The Hourglass;  10-11
#    12       Move -> The Bellows;  13-14
#    15       Move Volition Free -> The Phial    (a child: the Archon is full)
#    16-17    The Phial
#    18       Move Volition Free -> The Satchel  (a child)
#    19-20    The Satchel
#    21       Move Volition The Bellows -> The Djinn   (D home for next cycle)
#    22       If Sparks >= 0 -> self             (park until the Oscillation)

const KC = preload("res://kaleb_commands.gd")
## The order they fill in.
const ORDER: Array[int] = [6, 1, 0, 2, 3, 4, 5]
const ALL_IDS: Array[int] = [0, 1, 2, 3, 4, 5, 6]
## Foci: 120 keeps it at two Volitions (5, 25, 125, ...).
const FOCI_TOTAL: int = 120
const CREW_FOCI: int = 60
const UONITES_FREE: int = 40
const INCOME_PER_SECOND: int = 200   # summoning, standing in for the wheel
const MAX_SECONDS: int = 8000

var fails: int = 0
func ok(c: bool, s: String) -> void:
	if c:
		print("  PASS  ", s)
	else:
		print("  FAIL  ", s)
		fails += 1


var gc: Node = null
var cdata: Node = null
var kaleb: Node = null
var clock: float = 10000.0
var fill_order: Array = []      # ids, in the order each reached its cap
var overlap: int = 0            # seconds one gained while an earlier one wasn't full
var tier1_sec: int = -1         # the second The Djinn reached Tier 1
var first_act_sec: int = -1     # the second Kaleb first did anything (bar 1)


func _supply_pair(bars: Array, id: int, per_press: int) -> void:
	var wait: Dictionary = KC.make_bar("if")
	wait.merge({"res": "sparks", "cmp": "<", "value": per_press, "goto": bars.size()}, true)
	bars.append(wait)
	var cap: int = ceili(cdata.get_spark_cap(id))
	var supply: Dictionary = KC.make_bar("supply_sparks", ceili(float(cap) / float(per_press)))
	supply.merge({"target": str(id), "workers": CREW_FOCI}, true)
	bars.append(supply)


func _move(bars: Array, from: String, to: String) -> void:
	var m: Dictionary = KC.make_bar("move_volition")
	m.merge({"res": from, "target": to, "value": 1}, true)
	bars.append(m)


func fill_stack(per_press: int) -> Array:
	var bars: Array = []
	var assign: Dictionary = KC.make_bar("assign")
	assign.merge({"res": "uonites", "target": "sparks", "value": 99999}, true)
	bars.append(assign)
	_supply_pair(bars, 6, per_press)
	_supply_pair(bars, 1, per_press)
	_move(bars, "6", "0")
	_supply_pair(bars, 0, per_press)
	_move(bars, "0", "2")
	_supply_pair(bars, 2, per_press)
	_move(bars, "2", "3")
	_supply_pair(bars, 3, per_press)
	_move(bars, "free", "4")
	_supply_pair(bars, 4, per_press)
	_move(bars, "free", "5")
	_supply_pair(bars, 5, per_press)
	_move(bars, "3", "6")
	var park: Dictionary = KC.make_bar("if")
	park.merge({"res": "sparks", "cmp": ">=", "value": 0, "goto": bars.size()}, true)
	bars.append(park)
	return bars


func _total(id: int) -> float:
	return float(gc.constellation_spark_totals.get(str(id), 0.0))


func _full(id: int) -> bool:
	return _total(id) >= cdata.get_spark_cap(id)


func _all_full() -> bool:
	for id in ALL_IDS:
		if not _full(id):
			return false
	return true


func _on_sparks() -> int:
	return gc.get_operation_uonites("sparks_summon").to_int()


## A second at a time: income, every Constellation's automatic feeding (the
## production manager's 1/s tick, stopped here so only this moves Sparks),
## then Kaleb. Until he parks with all full, pauses, or time runs out.
func _run_until_parked(max_s: int = MAX_SECONDS) -> int:
	fill_order = []
	overlap = 0
	tier1_sec = -1
	first_act_sec = -1
	var last: int = gc.kaleb_stack.size() - 1
	for s in max_s:
		clock += 1.0
		kaleb.clock_override = clock
		gc.sparks = gc.sparks.add(BigNum.from_int(INCOME_PER_SECOND))
		var before: Array = []
		for id in ORDER:
			before.append(_total(id))
		gc.accumulate_constellation_sparks()
		if tier1_sec < 0 and gc.kaleb_djinn_ready():
			tier1_sec = s
		kaleb.step()
		if first_act_sec < 0 and _on_sparks() > 0:
			first_act_sec = s
		for i in ORDER.size():
			var id: int = ORDER[i]
			if _total(id) > float(before[i]):
				for j in i:
					if not _full(ORDER[j]):
						overlap += 1
			if _full(id) and not fill_order.has(id):
				fill_order.append(id)
		if not gc.kaleb_running:
			return s + 1
		if gc.kaleb_index == last and _all_full():
			return s + 1
	return max_s


## The end of a cycle, as the author laid it out: all full, A on The Archon,
## D on The Djinn, a child on The Phial and one on The Satchel.
func _end_of_cycle_state() -> void:
	for id in ALL_IDS:
		gc.constellation_spark_totals[str(id)] = cdata.get_spark_cap(id)
	gc.accumulate_constellation_sparks()   # the Archon's grant re-syncs here
	gc.sync_bonus_children_count()
	gc.assign_next_child_in_category("constellation", 4)
	gc.assign_next_child_in_category("constellation", 5)


func _volitions_on(id: int) -> int:
	return gc.get_volition_count_for_constellation(id)


func run() -> void:
	await process_frame
	var sm = root.get_node_or_null("/root/SaveManager")
	if sm:
		sm.autosave_enabled = false
	gc = root.get_node("/root/GameContext")
	cdata = root.get_node("/root/ConstellationData")
	var snapshot: Dictionary = gc.get_save_data()
	var saved_unlocked: Array = cdata.unlocked.duplicate()
	var saved_active: Array = cdata.active_per_octant.duplicate()

	var scene = load("res://RootUI.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	await process_frame
	var ui = scene.find_child("RootUI", true, false)
	kaleb = ui._kaleb
	kaleb.set_process(false)   # the test steps him
	var adm = ui.archon_dialogue_manager
	for _i in 200:
		if adm.current_index < 0:
			break
		adm.advance_dialogue()
	var pm = root.get_node("/root/ProductionManager")
	pm.set_process(false)      # only Kaleb, the feeding tick and the test's income move Sparks

	print("=== the premise: two Volitions, A on The Archon, D on The Djinn ===")
	cdata.unlocked = ALL_IDS.duplicate()
	for id in ALL_IDS:
		cdata.active_per_octant[id] = id   # each in its own octant (Archon's grant, Phial's bank)
		gc.assignments["constellation_%d_solve_count" % id] = 1
		gc.assignments["constellation_%d_feed_mode" % id] = 0
	gc.assignments["constellation_6_feed_mode"] = 1   # The Djinn on Endow
	adm.first_particle_done = true                     # the second Volition's gate
	gc.expansions = 100
	for k in gc.assignments.keys():
		var kk: String = String(k)
		if kk.ends_with("_foci"):
			gc.assignments[k] = 0
		elif kk.ends_with("_uonites"):
			gc.assignments[k] = BigNum.zero()
	gc.kaleb_stack = []
	gc.kaleb_crew_uonites = 0
	gc.kaleb_crew_foci = 0
	gc.kaleb_running = false
	gc.archon_foci = FOCI_TOTAL
	gc.volitions = 2
	gc.volition_slots = [
		{"category": "constellation", "target": 1, "children": []},
		{"category": "constellation", "target": 6, "children": []}]
	gc._rebuild_volition_assignments()
	ok(_volitions_on(1) == 1 and _volitions_on(6) == 1, "A on The Archon, D on The Djinn")

	print("=== the crew and the stack ===")
	gc.uonite = gc.get_total_uonites_assigned()
	for _n in CREW_FOCI:
		gc.kaleb_change_crew(1)
	var per_press: int = 1 * CREW_FOCI   # click multiplier 1
	var added: int = 0
	for bar in fill_stack(per_press):
		if gc.kaleb_add_bar(bar):
			added += 1
	ok(added == 22 and gc.kaleb_stack.size() == 22, "22 bars went in (%d)" % added)
	var djinn_foci: int = gc.archon_foci - gc.get_total_foci_assigned()
	gc.assignments["constellation_6_foci"] = djinn_foci   # every Focus left on The Djinn
	ok(gc.kaleb_crew_foci == CREW_FOCI and djinn_foci > 0 and gc.archon_foci == gc.get_total_foci_assigned(),
		"a crew of %d Foci, %d bars, and the other %d Foci on The Djinn (%d of %d placed)" % [
			CREW_FOCI, added, djinn_foci, gc.get_total_foci_assigned(), gc.archon_foci])
	gc.uonite = gc.get_total_uonites_assigned().add(BigNum.from_int(UONITES_FREE))
	for i in gc.kaleb_stack.size():
		var b: Dictionary = gc.kaleb_stack[i]
		var nm = func(t: String) -> String:
			return "Free" if t == "free" else KC.constellation_name(t.to_int(), gc, cdata)
		match String(b["cmd"]):
			"assign": print("    %2d  Assign Uonites -> Sparks %d" % [i + 1, int(b["value"])])
			"if": print("    %2d  If Sparks %s %d -> #%d" % [i + 1, b["cmp"], int(b["value"]), int(b["goto"]) + 1])
			"supply_sparks": print("    %2d  Supply Sparks, %s  %d Foci  x%d" % [i + 1, nm.call(String(b["target"])), int(b["workers"]), int(b["repeat"])])
			"move_volition": print("    %2d  Move Volition %s -> %s" % [i + 1, nm.call(String(b["res"])), nm.call(String(b["target"]))])

	print("=== the end of a cycle, then the Oscillation ===")
	_end_of_cycle_state()
	ok(gc._assignment_int("constellation_4_bonus_volitions", 0) == 1 and gc._assignment_int("constellation_5_bonus_volitions", 0) == 1,
		"a child Volition on The Phial and one on The Satchel (%d children per parent from the Archon)" % gc.get_bonus_volitions_per_slot())
	gc.kaleb_running = true
	gc.kaleb_index = gc.kaleb_stack.size() - 1   # parked, as at the end of a cycle
	var bank_expected: BigNum = cdata.get_phial_spark_bank_amount()
	var cap_before: BigNum = gc.storage_cap.copy()
	ui._do_prestige_reset()
	ok(gc.storage_cap.is_greater_than(cap_before), "the Satchel's +5%% landed (%s -> %s)" % [
		cap_before.to_display_string(), gc.storage_cap.to_display_string()])
	ok(not bank_expected.is_zero() and gc.sparks.equals(bank_expected),
		"the Phial's bank is the reserve (%s Sparks; Tier 1 is %d)" % [gc.sparks.to_display_string(), int(cdata.SPARKS_TIER_STARS)])
	ok(gc.get_free_children_count() == 0 and _volitions_on(4) == 0 and _volitions_on(5) == 0,
		"the children cleared; nothing is on The Phial or The Satchel")
	ok(_volitions_on(1) == 1 and _volitions_on(6) == 1, "A and D stayed")
	ok(gc.kaleb_index == 0 and gc.kaleb_running and not gc.kaleb_djinn_ready(),
		"Kaleb is back at bar 1, still running, and The Djinn is dark")

	print("=== the run ===")
	kaleb._timer_ready.clear()
	var secs: int = _run_until_parked()
	ok(tier1_sec >= 0 and first_act_sec >= tier1_sec,
		"Kaleb did nothing until The Djinn's Tier 1 (Tier 1 at %d s, bar 1 at %d s)" % [tier1_sec, first_act_sec])
	ok(_on_sparks() == gc.uonite.to_int() and gc._free_uonites() == 0,
		"bar 1 then put every Uonite on Sparks (%d of %d)" % [_on_sparks(), gc.uonite.to_int()])
	ok(_all_full(), "all 7 Constellations are full (%s)" % str(fill_order))
	ok(fill_order == Array(ORDER), "they filled Djinn first, then in the stack's order (%s)" % str(fill_order))
	ok(overlap == 0, "one at a time: none gained Sparks while an earlier one wasn't full (%d such seconds)" % overlap)
	ok(_volitions_on(1) == 1 and _volitions_on(6) == 1 and _volitions_on(3) == 0,
		"D went round and came home to The Djinn; A never left The Archon")
	ok(gc._assignment_int("constellation_4_bonus_volitions", 0) == 1 and gc._assignment_int("constellation_5_bonus_volitions", 0) == 1,
		"children on The Phial and The Satchel again: the premise for the next cycle")
	ok(gc.kaleb_running and gc.kaleb_index == gc.kaleb_stack.size() - 1,
		"Kaleb is parked on the last bar, still running (bar %d)" % (gc.kaleb_index + 1))
	print("    %d s at %d Sparks/s income and %d Sparks a press" % [secs, INCOME_PER_SECOND, per_press])

	print("=== the next Oscillation runs it all again ===")
	cap_before = gc.storage_cap.copy()
	ui._do_prestige_reset()
	ok(gc.storage_cap.is_greater_than(cap_before) and gc.kaleb_index == 0 and not _all_full(),
		"the Satchel's +5% again, everything emptied, Kaleb at bar 1")
	_run_until_parked()
	ok(_all_full() and fill_order == Array(ORDER) and gc.kaleb_running and first_act_sec >= tier1_sec,
		"all 7 full again, Djinn first, in order")

	print("=== what it depends on: D on The Djinn ===")
	ui._do_prestige_reset()
	var d_slot: int = gc.get_first_parent_index_with_target("constellation", 6)
	gc.unassign_parent_volition(d_slot)
	ok(not gc.has_volition_for_constellation(6), "D is taken off The Djinn")
	_run_until_parked(600)
	ok(gc.kaleb_running and gc.kaleb_index == 0 and _on_sparks() == 0 and not gc.kaleb_djinn_ready(),
		"The Djinn can't feed itself, so it stays dark and Kaleb waits on bar 1, still running, touching nothing")

	gc.kaleb_running = false
	kaleb.clock_override = -1.0
	cdata.unlocked = saved_unlocked
	cdata.active_per_octant = saved_active
	scene.queue_free()
	await process_frame
	await process_frame
	gc.load_save_data(snapshot)
	print("\nALL PASS (%d failures)" % fails if fails == 0 else "\nFAILURES (%d failures)" % fails)
	finish()
