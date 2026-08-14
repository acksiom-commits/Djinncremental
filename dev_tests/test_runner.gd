extends SceneTree
# THE stable entry point for every local verification run.
#
#     godot --headless --script dev_tests/test_runner.gd
#
# That exact string, every time, with no cd / cp / rm / pipe / loop around
# it — which is the whole point. Reconstructing a different shell pipeline
# per run made each invocation a novel command needing its own approval,
# and booting Godot once per test file cost 1-4 minutes each. This runs the
# whole suite in ONE process off ONE unchanging command.
#
# Named test_* so it satisfies test_record_boundary.gd's harness allowlist,
# which matches on filename PREFIX (test_/probe_/bench_/audit_/diag/check_/
# verify_) — a runner called run.gd would be scanned as shipped game code.

const DEV_DIR := "res://dev_tests/"

## Files here that are infrastructure, not test modules.
const NOT_A_TEST := ["test_runner.gd", "test_base.gd"]


func _init() -> void:
	var only: String = ""
	for a in OS.get_cmdline_user_args():
		only = str(a)   # optional filter: -- <substring>

	var modules: Array[String] = _discover()
	if only != "":
		var filtered: Array[String] = []
		for m in modules:
			if m.contains(only):
				filtered.append(m)
		modules = filtered

	print("running %d module(s) in ONE process\n" % modules.size())

	var results: Array[Dictionary] = []
	for path in modules:
		results.append(await _run_one(path))

	print("\n" + "=".repeat(64))
	print("SUMMARY")
	print("=".repeat(64))
	var total_fails: int = 0
	var unknown: int = 0
	for r in results:
		var name: String = str(r["name"])
		var status: String
		if r["fails"] == null:
			status = "?  (no counter found - read its output above)"
			unknown += 1
		elif int(r["fails"]) == 0:
			status = "PASS"
		else:
			status = "FAIL  (%d)" % int(r["fails"])
			total_fails += int(r["fails"])
		print("  %-36s %s" % [name, status])
	print("=".repeat(64))
	if total_fails == 0 and unknown == 0:
		print("ALL MODULES PASS")
	else:
		print("TOTAL FAILURES: %d%s" % [
			total_fails, ("   (%d module(s) unscored)" % unknown) if unknown > 0 else ""])
	quit(1 if total_fails > 0 else 0)


func _discover() -> Array[String]:
	var out: Array[String] = []
	var dir := DirAccess.open(DEV_DIR)
	if dir == null:
		push_error("cannot open " + DEV_DIR)
		return out
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if entry.ends_with(".gd") and not NOT_A_TEST.has(entry) \
				and (entry.begins_with("test_") or entry.begins_with("probe_")):
			out.append(DEV_DIR + entry)
		entry = dir.get_next()
	dir.list_dir_end()
	out.sort()
	return out


func _run_one(path: String) -> Dictionary:
	var fname: String = path.get_file()
	print("\n" + "-".repeat(64))
	print("### " + fname)
	print("-".repeat(64))

	var script = load(path)
	# A .gd that fails to COMPILE still load()s fine and reports nothing at
	# all downstream — can_instantiate() is the only signal. Checked here so
	# a broken module is named instead of silently scoring as a pass.
	if script == null or not script.can_instantiate():
		print("  !! does not compile (can_instantiate() == false)")
		return {"name": fname, "fails": 1}

	# Snapshot first so ONLY what this module adds gets cleaned up — root's
	# existing children include the project's real autoloads, which the next
	# module still needs.
	var before: Array = root.get_children().duplicate()

	var mod = script.new()
	if not mod.has_method("run"):
		print("  !! not converted: still a standalone script (no run() method).")
		print("     Convert with: `extends SceneTree` -> `extends \"res://dev_tests/test_base.gd\"`")
		print("     and `func _init()` -> `func run()`. See test_base.gd.")
		return {"name": fname, "fails": null}
	if mod.has_method("setup"):
		mod.setup(self)

	await mod.run()

	# Deferred, never immediate .free(): freeing a Node from inside a call
	# stack its own signals may still be unwinding hangs the whole harness
	# silently, and several of these modules drive signal-heavy UI scenes.
	for child in root.get_children():
		if not before.has(child):
			child.queue_free()
	await process_frame
	await process_frame

	# An ABORTED module is not a passing module. Before this check, a
	# run() that died partway (null deref, bad index — GDScript halts the
	# function and hands control back here) left its own counter at 0 and
	# scored PASS. That hid a real abort through two full runs on
	# 2026-08-12. Reported ahead of the counter, because if run() never
	# finished the counter is meaningless whatever it says.
	if not bool(mod.get("completed")):
		print("  !! ABORTED partway — run() never reached its end.")
		print("     Its own pass/fail counter is meaningless; treating as FAILED.")
		print("     Common causes: touching a scene's composed members before")
		print("     `await process_frame`, or an out-of-range index.")
		return {"name": fname, "fails": 1}

	# Each module keeps its own counter under its own name — the base class
	# deliberately declares none, since a subclass redeclaring a base member
	# is a parse error and these were written independently.
	var fails = mod.get("fails")
	if fails == null:
		fails = mod.get("fail_count")
	return {"name": fname, "fails": fails}
