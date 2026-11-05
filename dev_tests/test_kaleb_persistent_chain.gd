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
# added with none free; the player's presses do nothing while the stack runs;
# the Fundament-first draw always has a Fundament and respects locks; the
# stack saves and loads; the Oscillation keeps Persistent Grains only.

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
	kaleb.set_process(false)   # the test steps him
	ui._tetrad_assembly_ready = true

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
	gc.kaleb_running = false
	gc.kaleb_index = 0
	gc.kaleb_repeat_done = 0
	gc.uonite = gc.get_total_uonites_assigned().add(BigNum.from_int(20))
	gc.archon_foci = gc.get_total_foci_assigned() + 20

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
	ok(gc.get_total_uonites_assigned().to_int() - u0 == stack.size() - ifs,
		"every bar but the %d If-thens holds a Uonite (%d)" % [ifs, gc.get_total_uonites_assigned().to_int() - u0])
	gc.archon_foci = gc.get_total_foci_assigned()
	ok(not gc.kaleb_add_bar(_bar("monad_compress")), "no bar goes in with no Focus free")
	gc.archon_foci += 20

	print("\n=== while it runs, only Kaleb presses ===")
	gc.kaleb_running = true
	var s_before: BigNum = gc.sparks.copy()
	ui._on_monad_compress_pressed()
	ui._on_summon_spark_pressed()
	ok(gc.sparks.equals(s_before) and gc.get_monad_total().is_zero(), "the player's presses do nothing")

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

	print("\n=== the stack saves and loads ===")
	var data: Dictionary = gc.get_save_data()
	var json_round = JSON.parse_string(JSON.stringify(data))
	var before: Array = gc.kaleb_stack.duplicate(true)
	gc.kaleb_stack = []
	gc._load_kaleb_stack(json_round)
	var same: bool = gc.kaleb_stack.size() == before.size()
	if same:
		for i in before.size():
			for key in ["cmd", "repeat", "on", "target", "res", "cmp", "value", "goto"]:
				if gc.kaleb_stack[i][key] != before[i][key] or typeof(gc.kaleb_stack[i][key]) != typeof(before[i][key]):
					same = false
	ok(same, "after a JSON round trip the stack is the same, with ints still ints")

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
