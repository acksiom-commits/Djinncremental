extends "res://dev_tests/test_base.gd"
# Kaleb's command stack makes Persistent material (SysDoc §7.3, Phase 1).
#
# A player-style stack, run from Sparks alone: Lock Liquid and Gas Monads,
# compress until 4 Solid Monads exist, assemble a Tetrad (so it can only be
# Adaemant), unlock, make a few random Tetrads, Assemble Persistent Particle,
# and loop back until there are 4; then make cavity Tetrads and Assemble
# Persistent Iota. Kaleb presses the real handlers; the test lets each
# cooldown finish at once (white-box) so the run takes frames, not minutes.
#
# Also: every bar holds a Focus and every working bar a Uonite; a bar can't be
# added with none free; the player's clicks go through while the stack runs;
# the Fundament-first draw always has a Fundament and respects locks; the
# stack saves and loads; Kaleb pauses with a notice on a Lock bar with no
# Volition free or a press that makes nothing at full storage; the
# Oscillation keeps Persistent Grains only.

const KC = preload("res://kaleb_commands.gd")
const COOLDOWN_BARS := ["SparksCooldownBar", "MonadCooldownBar", "TetradCooldownBar",
	"ParticleCooldownBar", "IotaCooldownBar", "MoteCooldownBar"]
const MAX_FRAMES := 20000

var fails: int = 0
func ok(c: bool, s: String) -> void:
	if c:
		print("  PASS  ", s)
	else:
		print("  FAIL  ", s)
		fails += 1


func _bar(cmd: String, repeat: int = 1, extra: Dictionary = {}) -> Dictionary:
	var b: Dictionary = KC.make_bar(cmd, repeat)
	b.merge(extra, true)
	return b


func run() -> void:
	await process_frame
	var sm = root.get_node_or_null("/root/SaveManager")
	if sm:
		sm.autosave_enabled = false
	var gc = root.get_node("/root/GameContext")
	var pm = root.get_node("/root/ProductionManager")
	var snapshot: Dictionary = gc.get_save_data()

	var scene = load("res://RootUI.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	await process_frame
	var ui = scene.find_child("RootUI", true, false)
	var kaleb: Node = ui._kaleb
	# The whole stack waits for The Djinn's Tier 1 (author, 2026-11-10).
	var _cdj = root.get_node("/root/ConstellationData")
	if not _cdj.unlocked.has(_cdj.DJINN_ID):
		_cdj.unlocked.append(_cdj.DJINN_ID)
	gc.constellation_spark_totals[str(_cdj.DJINN_ID)] = _cdj.SPARKS_TIER_STARS
	kaleb.set_process(false)   # the test steps him
	ui._tetrad_assembly_ready = true
	# A tutorial dialogue blocks every press, Kaleb's too, and the loaded save
	# can set one off as the page starts (First Grain, say, which any Grain
	# made sets off since 2026-11-05): click through it, as the player would.
	var adm = ui.archon_dialogue_manager
	for _i in 200:
		if adm.current_index < 0:
			break
		adm.advance_dialogue()
	ok(not ui._is_tutorial_blocking(), "no dialogue is blocking the buttons")

	# A clean slate: plenty of Sparks and room, no material, free Volitions
	# for Kaleb's locks, and Uonites and Foci for his bars.
	gc.sparks = BigNum.from_int(1000000)
	gc.storage_cap = BigNum.from_int(1000000)
	for k in gc.monad: gc.monad[k] = BigNum.zero()
	for k in gc.tetrad: gc.tetrad[k] = BigNum.zero()
	for k in gc.PERSISTENT_KEYS: gc.set_resource(k, BigNum.zero())
	for k in gc.locks: gc.locks[k] = false
	gc.purity_locks_unlocked = true
	gc.volition_slots = []
	for i in 4:
		gc.volition_slots.append({"category": "", "target": "",
			"children": [{"category": "", "target": ""}, {"category": "", "target": ""}]})
	gc.kaleb_stack = []
	gc.kaleb_crew_uonites = 0
	gc.kaleb_crew_foci = 0
	gc.kaleb_running = false
	gc.kaleb_index = 0
	gc.kaleb_repeat_done = 0
	gc.uonite = gc.get_total_uonites_assigned().add(BigNum.from_int(20))
	gc.archon_foci = gc.get_total_foci_assigned() + 20

	print("=== an If bar can count all unlocked Monads or Tetrads ===")
	gc.monad["solid"] = BigNum.from_int(3)
	gc.monad["liquid"] = BigNum.from_int(2)
	gc.monad["gas"] = BigNum.from_int(5)
	gc.tetrad["adaemant"] = BigNum.from_int(4)
	gc.tetrad["earth"] = BigNum.from_int(1)
	gc.tetrad["mud"] = BigNum.from_int(6)
	ok(KC.read_count(gc, "monad") == 10 and KC.read_count(gc, "tetrad") == 11,
		"with nothing locked: every Monad (10) and every Tetrad (11)")
	gc.locks["monad_gas"] = true
	gc.locks["earth"] = true
	gc.locks["cat_symmetric"] = true
	ok(KC.read_count(gc, "monad") == 5 and KC.read_count(gc, "tetrad") == 4,
		"locked kinds left out, a category lock too (5 Monads, 4 Tetrads; got %d, %d)" % [
			KC.read_count(gc, "monad"), KC.read_count(gc, "tetrad")])
	for k in gc.monad: gc.monad[k] = BigNum.zero()
	for k in gc.tetrad: gc.tetrad[k] = BigNum.zero()
	for k in gc.locks: gc.locks[k] = false

	print("=== the stack holds Uonites and Foci ===")
	var u0: int = gc.get_total_uonites_assigned().to_int()
	var f0: int = gc.get_total_foci_assigned()
	var stack: Array = [
		_bar("lock", 1, {"target": "monad_liquid"}),           # 0
		_bar("lock", 1, {"target": "monad_gas"}),              # 1
		_bar("monad_compress", 4),                             # 2
		_bar("if", 1, {"res": "monad_solid", "cmp": "<", "value": 4, "goto": 2}),  # 3
		_bar("tetrad_assemble", 1),                            # 4: only Adaemant can come out
		_bar("unlock", 1, {"target": "monad_liquid"}),         # 5
		_bar("unlock", 1, {"target": "monad_gas"}),            # 6
		_bar("monad_compress", 12),                            # 7
		_bar("tetrad_assemble", 3),                            # 8
		_bar("persistent_particle", 1),                        # 9
		_bar("if", 1, {"res": "persistent_particle", "cmp": "<", "value": 4, "goto": 0}),  # 10
		_bar("monad_compress", 32),                            # 11
		_bar("tetrad_assemble", 8),                            # 12
		_bar("persistent_iota", 1),                            # 13
		_bar("if", 1, {"res": "persistent_iota", "cmp": "<", "value": 1, "goto": 11}),  # 14
	]
	var added: int = 0
	for b in stack:
		if gc.kaleb_add_bar(b):
			added += 1
	var ifs: int = 3
	ok(added == stack.size(), "all %d bars went in (%d added)" % [stack.size(), added])
	ok(gc.get_total_foci_assigned() - f0 == stack.size(), "every bar holds a Focus (%d)" % (gc.get_total_foci_assigned() - f0))
	ok(gc.get_total_uonites_assigned().to_int() == u0,
		"the bars hold no workers of their own: the %d working bars share the crew" % (stack.size() - ifs))
	ok(gc.kaleb_change_crew(1) and gc.get_total_uonites_assigned().to_int() == u0 + 1 and gc.kaleb_crew_size() == 1,
		"a crew of 1 holds one Uonite, whatever the number of bars")
	gc.archon_foci = gc.get_total_foci_assigned()
	ok(not gc.kaleb_add_bar(_bar("monad_compress")), "no bar goes in with no Focus free")
	gc.archon_foci += 20

	print("\n=== while it runs, the player's clicks go through too ===")
	# Author, 2026-11-05: at first only Kaleb could press while his stack
	# ran; reversed when clicking Particles couldn't make room at full storage.
	gc.kaleb_running = true
	var s_before: BigNum = gc.sparks.copy()
	ui._get_cooldown_bar("MonadCooldownBar")._is_ready = true
	ui._on_monad_compress_pressed()
	ok(not gc.get_monad_total().is_zero(), "the player's Compress click makes a Monad while Kaleb runs")
	for k in gc.monad: gc.monad[k] = BigNum.zero()
	gc.sparks = s_before

	print("\n=== Kaleb runs the stack ===")
	var frames: int = 0
	var adaemants_made: int = 0
	var last_adaemant: BigNum = gc.totals_created.get("adaemant", BigNum.zero()).copy()
	while frames < MAX_FRAMES and gc.persistent_iota.is_zero():
		kaleb.step()
		for n in COOLDOWN_BARS:
			var cd = ui._get_cooldown_bar(n)
			if cd:
				cd._is_ready = true
		frames += 1
	adaemants_made = gc.totals_created.get("adaemant", BigNum.zero()).sub(last_adaemant).to_int()
	var pp_made: int = gc.totals_created.get("persistent_particle", BigNum.zero()).to_int()
	print("  %d frames; %d Adaemants, %d Persistent Particles made; now %s Persistent Particles, %s Persistent Iotas"
		% [frames, adaemants_made, pp_made, gc.persistent_particle.to_display_string(), gc.persistent_iota.to_display_string()])
	ok(gc.persistent_iota.to_int() >= 1, "Kaleb made a Persistent Iota from Sparks alone")
	ok(pp_made >= 4 and adaemants_made >= 4, "via at least 4 Persistent Particles and 4 Adaemants")
	ok(not gc.locks.get("monad_liquid", false) and not gc.locks.get("monad_gas", false) or gc.kaleb_index <= 4,
		"his lock bars switch the Monad locks back off")

	print("\n=== the Fundament-first draw ===")
	gc.kaleb_running = false
	var with_f: int = 0
	var judged: int = 0
	var used_locked: int = 0
	for trial in 200:
		for k in gc.tetrad: gc.tetrad[k] = BigNum.from_int(gc.rng.randi_range(0, 3))
		gc.locks["aquae"] = trial % 2 == 0
		var d: Dictionary = pm._draw_fundament_first_tetrads()
		if d.is_empty():
			continue
		judged += 1
		var n: int = 0
		for k in d: n += int(d[k])
		if n == 4 and (d.has("adaemant") or d.has("aquae") or d.has("aethyr")):
			with_f += 1
		if gc.locks["aquae"] and d.has("aquae"):
			used_locked += 1
	gc.locks["aquae"] = false
	ok(judged > 100 and with_f == judged, "%d of %d draws were 4 Tetrads with a Fundament" % [with_f, judged])
	ok(used_locked == 0, "none used a locked Fundament (%d did)" % used_locked)

	print("\n=== the crew: one set of workers Kaleb takes from bar to bar (author, 2026-11-06) ===")
	# Uonites first, Foci standing in; each bar uses its own count of the crew,
	# capped at the crew's size; a press makes that many times a click.
	var saved_stack: Array = gc.kaleb_stack
	gc.kaleb_stack = []
	gc.kaleb_crew_uonites = 0
	gc.kaleb_crew_foci = 0
	gc.kaleb_index = 0
	gc.kaleb_repeat_done = 0
	gc.uonite = gc.get_total_uonites_assigned().add(BigNum.from_int(4))
	gc.archon_foci = gc.get_total_foci_assigned() + 3
	var cb: Dictionary = _bar("monad_compress", 1)
	ok(gc.kaleb_add_bar(cb) and gc.kaleb_bar_count(cb) == 1 and gc.kaleb_bar_workers(cb) == 0,
		"a Compress bar goes in on its On/Off Focus alone, asking for 1 of a crew of 0")
	var u_held0: int = gc.kaleb_uonites_held()
	var f_held0: int = gc.kaleb_foci_held()
	for n in 4:
		gc.kaleb_change_crew(1)
	ok(gc.kaleb_crew_uonites == 4 and gc.kaleb_crew_foci == 0 and gc.kaleb_uonites_held() == u_held0 + 4,
		"crew + takes free Uonites first (4U)")
	ok(gc.kaleb_change_crew(1) and gc.kaleb_crew_foci == 1 and gc.kaleb_foci_held() == f_held0 + 1,
		"with no Uonite free, crew + takes a spare Focus instead (4U+1F)")
	gc.archon_foci = gc.get_total_foci_assigned()
	ok(not gc.kaleb_change_crew(1), "with neither free, crew + is refused")
	for n in 6:
		gc.kaleb_change_bar_workers(cb, 1)
	ok(gc.kaleb_bar_count(cb) == 5 and not gc.kaleb_change_bar_workers(cb, 1),
		"a bar's + uses more of the crew, up to its 5, at no cost")
	var click_m: int = gc.get_click_multiplier()
	var m0: int = gc.get_monad_total().to_int()
	gc.kaleb_running = true
	ui._get_cooldown_bar("MonadCooldownBar")._is_ready = true
	kaleb.step()
	gc.kaleb_running = false
	var made: int = gc.get_monad_total().to_int() - m0
	ok(made == 5 * click_m, "one press with 5 of the crew made %d Monads (5 x click multiplier %d)" % [made, click_m])
	ok(ui._get_click_multiplier() == click_m, "and the player's own clicks are not multiplied (%d)" % ui._get_click_multiplier())
	gc.archon_foci = gc.get_total_foci_assigned() + 2
	var fb: Dictionary = _bar("tetrad_assemble")
	ok(gc.kaleb_add_bar(fb) and gc.kaleb_uonites_held() == u_held0 + 4 and gc.kaleb_foci_held() == f_held0 + 2,
		"a second working bar shares the crew: only its On/Off Focus is added")
	gc.kaleb_change_crew(-1)
	ok(gc.kaleb_crew_foci == 0 and gc.kaleb_crew_uonites == 4 and gc.kaleb_bar_count(cb) == 4,
		"crew − gives the Focus back first, and a bar asking for more is lowered to the crew (4)")
	for n in 6:
		gc.kaleb_change_crew(-1)
	ok(gc.kaleb_crew_size() == 0 and gc.kaleb_uonites_held() == u_held0 and gc.kaleb_bar_count(cb) == 1,
		"then the Uonites, down to no crew; bars still ask for 1")
	gc.kaleb_index = 0
	gc.kaleb_running = true
	ui._get_cooldown_bar("MonadCooldownBar")._is_ready = true
	var m1: int = gc.get_monad_total().to_int()
	kaleb.step()
	ok(not gc.kaleb_running and gc.get_monad_total().to_int() == m1,
		"with no crew, a press bar pauses Kaleb instead of pressing")
	gc.archon_foci = gc.get_total_foci_assigned() + 1
	var ib: Dictionary = _bar("if")
	ok(gc.kaleb_add_bar(ib) and gc.kaleb_bar_workers(ib) == 0, "an If bar needs just its one Focus")
	# A Summon Spark bar's workers multiply its summons the same way, as the
	# wheel's Spark automation is multiplied by its Uonites and Foci.
	gc.kaleb_stack = []
	gc.kaleb_index = 0
	gc.kaleb_repeat_done = 0
	gc.uonite = gc.get_total_uonites_assigned().add(BigNum.from_int(3))
	gc.archon_foci = gc.get_total_foci_assigned() + 1
	for n in 3:
		gc.kaleb_change_crew(1)
	var sb: Dictionary = _bar("summon_spark", 1)
	gc.kaleb_add_bar(sb)
	gc.kaleb_change_bar_workers(sb, 1)
	gc.kaleb_change_bar_workers(sb, 1)
	# Measured on the summoned-Sparks total: the balance is ~1e6 here, where a
	# BigNum difference of 3 can come back as 2.999… and floor to 2.
	var s0: float = gc.totals_created["sparks_summoned"].to_float()
	kaleb.clock_override = 1000.0
	kaleb._timer_ready.clear()
	sb["repeat"] = 99
	gc.kaleb_running = true
	kaleb.step()
	var per_summon: int = int(1.0 * pm.get_sparks_multiplier()) if pm.get_sparks_multiplier() > 1.0 else 1
	var summoned: int = roundi(gc.totals_created["sparks_summoned"].to_float() - s0)
	ok(gc.kaleb_bar_workers(sb) == 3 and summoned == 3 * click_m * per_summon,
		"a Summon Spark bar using 3 of the crew summoned %d Sparks in one press (3 x click %d x %d a summon)" % [summoned, click_m, per_summon])
	# Summon Spark has no cooldown bar, but Kaleb's presses wait the wheel's
	# 1-second Spark timer (author, 2026-11-05).
	var spark_timer: float = float(pm.get_timer_intervals()["sparks_summon"])
	var steps_waited := 0
	for n in 30:
		kaleb.step()
		steps_waited += 1
	var after_wait: int = roundi(gc.totals_created["sparks_summoned"].to_float() - s0)
	kaleb.clock_override = 1000.0 + spark_timer
	kaleb.step()
	var after_timer: int = roundi(gc.totals_created["sparks_summoned"].to_float() - s0)
	gc.kaleb_running = false
	kaleb.clock_override = -1.0
	ok(after_wait == summoned and after_timer == 2 * summoned,
		"his next Summon waits the %.1f s Spark timer (%d more steps: no summon; then one: +%d)" % [
			spark_timer, steps_waited, after_timer - after_wait])
	gc.kaleb_stack = saved_stack
	gc.kaleb_stack.append(cb)
	gc.kaleb_stack.append(fb)

	print("\n=== the stack saves and loads ===")
	var data: Dictionary = gc.get_save_data()
	var json_round = JSON.parse_string(JSON.stringify(data))
	var before: Array = gc.kaleb_stack.duplicate(true)
	var crew_before: Vector2i = Vector2i(gc.kaleb_crew_uonites, gc.kaleb_crew_foci)
	gc.kaleb_stack = []
	gc.kaleb_crew_uonites = 0
	gc.kaleb_crew_foci = 0
	gc._load_kaleb_stack(json_round)
	var same: bool = gc.kaleb_stack.size() == before.size()
	if same:
		for i in before.size():
			for key in ["cmd", "repeat", "on", "target", "res", "cmp", "value", "goto"]:
				if gc.kaleb_stack[i][key] != before[i][key] or typeof(gc.kaleb_stack[i][key]) != typeof(before[i][key]):
					same = false
			if gc.kaleb_bar_count(gc.kaleb_stack[i]) != gc.kaleb_bar_count(before[i]):
				same = false
	ok(same, "after a JSON round trip the stack is the same, with ints still ints")
	ok(Vector2i(gc.kaleb_crew_uonites, gc.kaleb_crew_foci) == crew_before,
		"and so is the crew (%dU+%dF)" % [crew_before.x, crew_before.y])

	print("\n=== a save from before the crew: bars held their own workers ===")
	var old_save: Dictionary = {"kaleb_stack": [
		{"cmd": "monad_compress", "repeat": 3, "uonites": 6, "foci_workers": 0},
		{"cmd": "if", "res": "monad_solid", "value": 4, "goto": 0},
		{"cmd": "tetrad_assemble", "repeat": 2, "uonites": 2, "foci_workers": 5},
		{"cmd": "persistent_iota", "uonites": 0, "foci_workers": 6}]}
	gc._load_kaleb_stack(old_save)
	ok(gc.kaleb_bar_count(gc.kaleb_stack[0]) == 6 and gc.kaleb_bar_count(gc.kaleb_stack[2]) == 7
			and gc.kaleb_bar_count(gc.kaleb_stack[3]) == 6,
		"each bar's own workers become its count (6, 7, 6)")
	ok(gc.kaleb_crew_uonites == 7 and gc.kaleb_crew_foci == 0,
		"the crew is the largest count, 7, from the 8 Uonites they held: it runs as before (%dU+%dF)" % [
			gc.kaleb_crew_uonites, gc.kaleb_crew_foci])
	gc._load_kaleb_stack(json_round)

	print("\n=== Kaleb pauses with a notice when he can't carry out a bar ===")
	# Author, 2026-11-05: a Lock bar with no Volition free failed silently,
	# his stack filled storage with mixed Monads and random Tetrads, and he
	# then looped Compress / If forever at full storage.
	var said := func(text: String) -> bool:
		for n in adm.notification_queue:
			if String(n).contains(text):
				return true
		return adm._label != null and String(adm._label.text).contains(text)
	for k in gc.locks: gc.locks[k] = false
	gc.volition_slots = [{"category": "volumitions", "target": "", "children": []}]
	gc.kaleb_stack = []
	gc.uonite = gc.get_total_uonites_assigned().add(BigNum.from_int(10))
	gc.archon_foci = gc.get_total_foci_assigned() + 10
	ok(gc.kaleb_add_bar(_bar("lock", 1, {"target": "monad_liquid"})) and gc.kaleb_add_bar(_bar("monad_compress", 3)),
		"a two-bar stack goes in: Lock Liquid Monads, Compress Monad x3")
	gc.kaleb_index = 0
	gc.kaleb_repeat_done = 0
	gc.kaleb_running = true
	kaleb.step()
	ok(not gc.kaleb_running and gc.kaleb_index == 0, "a Lock bar with no Volition free pauses him at that bar")
	ok(said.call("Kaleb paused at bar 1 (Lock Liquid Monads): no Volition is free for the Liquid Monads lock"),
		"and the notice says which bar and why")
	gc.volition_slots = [{"category": "", "target": "", "children": []}]
	gc.kaleb_running = true
	kaleb.step()
	ok(gc.locks.get("monad_liquid", false) and gc.kaleb_index == 1 and gc.kaleb_running,
		"with a Volition free, Run carries on from the same bar and the lock takes")

	gc.storage_cap = BigNum.from_int(1)
	gc.monad["solid"] = BigNum.from_int(5000)
	var solid_before: int = gc.monad["solid"].to_int()
	ui._get_cooldown_bar("MonadCooldownBar")._is_ready = true
	kaleb.step()
	ok(not gc.kaleb_running and gc.kaleb_index == 1 and gc.monad["solid"].to_int() == solid_before,
		"a Compress press at full storage that makes nothing pauses him")
	ok(said.call("Kaleb paused at bar 2 (Compress Monad): storage is full"), "and says storage is full")

	gc.kaleb_stack = []
	gc.kaleb_add_bar(_bar("summon_spark"))
	gc.kaleb_index = 0
	gc.kaleb_repeat_done = 0
	kaleb._timer_ready = {}
	var sp_before: BigNum = gc.sparks.copy()
	gc.kaleb_running = true
	kaleb.step()
	ok(gc.kaleb_running and gc.sparks.is_greater_than(sp_before), "Summon at full storage still works and doesn't pause him")

	gc.kaleb_stack = []
	gc.kaleb_add_bar(_bar("persistent_particle"))
	gc.kaleb_index = 0
	gc.kaleb_repeat_done = 0
	for k in gc.tetrad: gc.tetrad[k] = BigNum.zero()
	gc.tetrad["adaemant"] = BigNum.from_int(8)
	var pp_before: int = gc.persistent_particle.to_int()
	ui._get_cooldown_bar("ParticleCooldownBar")._is_ready = true
	kaleb.step()
	ok(gc.kaleb_running and gc.persistent_particle.to_int() > pp_before,
		"a press that frees room at full storage (Persistent Particle) goes on without a pause")
	gc.kaleb_running = false

	print("\n=== Constellation bars: Supply Sparks, Endow, Ignore (author, 2026-11-06) ===")
	var cdata = root.get_node("/root/ConstellationData")
	var saved_unlocked: Array = cdata.unlocked.duplicate()
	if not cdata.unlocked.has(0):
		cdata.unlocked.append(0)
	var cap0: float = cdata.get_spark_cap(0)
	gc.constellation_spark_totals["0"] = 0.0
	gc.assignments["constellation_0_volitions"] = 0
	gc.assignments["constellation_0_bonus_volitions"] = 0
	gc.sparks = BigNum.from_int(1000000)
	gc.storage_cap = BigNum.from_int(1000000)
	gc.kaleb_stack = []
	gc.kaleb_crew_uonites = 0
	gc.kaleb_crew_foci = 0
	gc.uonite = gc.get_total_uonites_assigned().add(BigNum.from_int(3))
	gc.archon_foci = gc.get_total_foci_assigned() + 10
	for n in 3:
		gc.kaleb_change_crew(1)
	var eb: Dictionary = _bar("supply_sparks", 5, {"target": "0"})
	gc.kaleb_add_bar(eb)
	eb["workers"] = 4
	gc.kaleb_index = 0
	gc.kaleb_repeat_done = 0
	kaleb.clock_override = 5000.0
	kaleb._timer_ready.clear()
	gc.kaleb_running = true
	kaleb.step()
	ok(not gc.kaleb_running and is_zero_approx(float(gc.constellation_spark_totals["0"])),
		"with no Volition on the Constellation, Kaleb pauses instead of endowing (as its automatic feeding needs one)")
	ok(said.call("no Volition is on"), "and says so")
	gc.assignments["constellation_0_volitions"] = 1
	gc.kaleb_running = true
	kaleb.step()
	ok(not gc.kaleb_running and is_zero_approx(float(gc.constellation_spark_totals["0"])) and gc.kaleb_bar_workers(eb) == 0,
		"with a crew of 3 Uonites and no Foci, it pauses too: only Foci work in Constellations")
	gc.kaleb_change_crew(1)
	gc.kaleb_change_crew(1)
	ok(gc.kaleb_crew_uonites == 3 and gc.kaleb_crew_foci == 2 and gc.kaleb_bar_workers(eb) == 2,
		"with 3U+2F the bar asking for 4 works with the 2 Foci only")
	var click_m2: int = gc.get_click_multiplier()
	var sp0: BigNum = gc.sparks.copy()
	gc.kaleb_running = true
	kaleb.step()
	var moved: float = float(gc.constellation_spark_totals["0"])
	ok(roundi(moved) == 2 * click_m2 and roundi(sp0.sub(gc.sparks).to_float()) == 2 * click_m2,
		"one press moves click multiplier x 2 Foci = %d Sparks into it, from the pool (%d)" % [2 * click_m2, roundi(moved)])
	kaleb.step()
	ok(is_equal_approx(float(gc.constellation_spark_totals["0"]), moved), "the next press waits the 1 s timer")
	kaleb.clock_override = 5000.0 + KC.SUPPLY_INTERVAL
	kaleb.step()
	ok(roundi(float(gc.constellation_spark_totals["0"])) == 4 * click_m2, "then presses again")
	gc.constellation_spark_totals["0"] = cap0 - 1.0
	kaleb.clock_override = 5000.0 + 2.0 * KC.SUPPLY_INTERVAL
	kaleb.step()
	ok(is_equal_approx(float(gc.constellation_spark_totals["0"]), cap0), "no further than its cap (%.0f)" % cap0)
	gc.kaleb_running = false
	kaleb.clock_override = -1.0

	gc.kaleb_stack = []
	gc.kaleb_add_bar(_bar("feed_endow", 1, {"target": "0"}))
	gc.kaleb_add_bar(_bar("if", 1, {"res": "sparks", "cmp": "<", "value": 0, "goto": 0}))
	gc.assignments["constellation_0_feed_mode"] = 0
	gc.kaleb_index = 0
	gc.kaleb_running = true
	kaleb.step()
	ok(gc._assignment_int("constellation_0_feed_mode", -1) == 1, "an Endow bar switches its Constellation's automatic feeding to Endow")
	gc.kaleb_stack[0]["cmd"] = "feed_ignore"
	gc.kaleb_index = 0
	kaleb.step()
	ok(gc._assignment_int("constellation_0_feed_mode", -1) == 0, "an Ignore bar switches it back to Ignore")
	gc.kaleb_running = false
	cdata.unlocked = saved_unlocked

	scene.queue_free()
	await process_frame
	await process_frame

	print("\n=== the Oscillation keeps Persistent Grains ===")
	gc.persistent_particle = BigNum.from_int(5)
	gc.persistent_iota = BigNum.from_int(3)
	gc.persistent_mote = BigNum.from_int(2)
	gc.persistent_grain = BigNum.from_int(7)
	gc.kaleb_index = 4
	var bars_before: int = gc.kaleb_stack.size()
	gc.do_prestige_reset()
	ok(gc.persistent_grain.to_int() == 7, "Persistent Grains survive (%d)" % gc.persistent_grain.to_int())
	ok(gc.persistent_particle.is_zero() and gc.persistent_iota.is_zero() and gc.persistent_mote.is_zero(),
		"Persistent Particles, Iotas and Motes reset")
	ok(gc.kaleb_stack.size() == bars_before and gc.kaleb_index == 0, "the stack stays; Kaleb starts from the top")

	gc.load_save_data(snapshot)
	print("\nALL PASS (%d failures)" % fails if fails == 0 else "\nFAILURES (%d failures)" % fails)
	finish()
