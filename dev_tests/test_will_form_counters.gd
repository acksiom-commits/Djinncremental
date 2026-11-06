extends "res://dev_tests/test_base.gd"
# Will/Form switch and the Particle/Iota/Mote/Grain counters (author,
# 2026-11-05: "Both, side by side"). On Form, the Iota and Mote rows count
# the Grain branch (iota_grains/mote_grains), Particle counts the shared
# Particle stock, and each, Grain too, shows its Persistent stock beside it
# as "· P n". On Will the rows are as before. A row's lock follows the stock
# it counts.

var fails: int = 0
func ok(c: bool, s: String) -> void:
	if c:
		print("  PASS  ", s)
	else:
		print("  FAIL  ", s)
		fails += 1


func _row(ui: Node, key: String) -> Node:
	for r in ui.get_tree().get_nodes_in_group("resource_rows"):
		if String(r.resource_key) == key:
			return r
	return null


func _text(row: Node) -> String:
	return String(row.label_node.text) if row.label_node else ""


func run() -> void:
	await process_frame
	var sm = root.get_node_or_null("/root/SaveManager")
	if sm:
		sm.autosave_enabled = false
	var gc = root.get_node("/root/GameContext")
	var scene = load("res://RootUI.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	await process_frame
	var ui = scene.find_child("RootUI", true, false)
	if ui == null:
		ui = scene

	var saved_locks = gc.locks.duplicate(true)
	var saved_slots = gc.volition_slots.duplicate(true)
	var saved_unlocked: bool = gc.purity_locks_unlocked
	var saved_will: bool = gc.will_form_switch_is_will
	for k in gc.locks:
		gc.locks[k] = false
	gc.particle = BigNum.from_int(11)
	gc.iota_uonite = BigNum.from_int(22)
	gc.mote_uonite = BigNum.from_int(33)
	gc.iota_grains = BigNum.from_int(44)
	gc.mote_grains = BigNum.from_int(55)
	gc.grain = BigNum.from_int(66)
	gc.persistent_particle = BigNum.from_int(7)
	gc.persistent_iota = BigNum.from_int(8)
	gc.persistent_mote = BigNum.from_int(9)
	gc.persistent_grain = BigNum.from_int(3)

	var rp: Node = _row(ui, "particle")
	var ri: Node = _row(ui, "iota_uonite")
	var rm: Node = _row(ui, "mote_uonite")
	var rg: Node = _row(ui, "grain")
	ok(rp != null and ri != null and rm != null and rg != null, "the Particle, Iota, Mote and Grain rows exist")

	print("=== Will: the Uonite branch, no Persistent counts ===")
	gc.will_form_switch_is_will = true
	ui._update_counters()
	ok(_text(rp).contains("Particle: 11") and not _text(rp).contains("· P"), "Particle: 11, nothing beside it (got %s)" % _text(rp))
	ok(_text(ri).contains("Iota: 22") and not _text(ri).contains("· P"), "Iota counts iota_uonite (got %s)" % _text(ri))
	ok(_text(rm).contains("Mote: 33") and not _text(rm).contains("· P"), "Mote counts mote_uonite (got %s)" % _text(rm))

	print("\n=== Form: the Grain branch, with Persistent beside it ===")
	gc.toggle_will_form_switch()
	ui._update_counters()
	ok(_text(rp).contains("Particle: 11 · P 7"), "Particle: 11 · P 7 (got %s)" % _text(rp))
	ok(_text(ri).contains("Iota: 44 · P 8"), "Iota counts iota_grains, P = Persistent Iotas (got %s)" % _text(ri))
	ok(_text(rm).contains("Mote: 55 · P 9"), "Mote counts mote_grains, P = Persistent Motes (got %s)" % _text(rm))
	ok(_text(rg).contains("Grain: 66 · P 3"), "Grain: 66 · P 3 (got %s)" % _text(rg))

	print("\n=== a row's lock follows the stock it counts ===")
	gc.purity_locks_unlocked = true
	gc.volition_slots = [{"category": "purity_lock", "target": "iota_grains", "children": []}]
	gc.locks["iota_grains"] = true
	ui._update_counters()
	ok(_text(ri).contains("🔒") and _text(ri).contains("[sweep"), "on Form the Iota row shows iota_grains' Parent lock (got %s)" % _text(ri))
	gc.toggle_will_form_switch()
	ui._update_counters()
	ok(not _text(ri).contains("🔒"), "on Will the same row shows iota_uonite, unlocked")
	gc.toggle_will_form_switch()
	gc.locks["iota_grains"] = false
	gc.volition_slots = [{"category": "", "target": "", "children": []}]
	ui._on_row_clicked("mote_uonite")
	ok(gc.locks.get("mote_grains", false) and not gc.locks.get("mote_uonite", false),
		"clicking the Mote row on Form locks mote_grains, not mote_uonite")

	gc.locks = saved_locks
	gc.volition_slots = saved_slots
	gc.purity_locks_unlocked = saved_unlocked
	gc.will_form_switch_is_will = saved_will
	print("\nALL PASS (%d failures)" % fails if fails == 0 else "\nFAILURES (%d failures)" % fails)
	finish()
