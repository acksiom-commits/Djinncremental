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

## Tiers (2026-11-01, author): time on a test the change could not have touched
## is what makes a run slow, whatever its total. Which tier a change needs is a
## judgement, stated when it runs:
##   -- tier:quick   display, layout data, wording, UI (~2.5 min)
##   -- tier:board   board entry, deduction, saves (~5.5 min)
##   (no argument)   generator or clues, and before a release (~27 min)
## SLOW_MODULES is every module over QUICK_LIMIT_SEC, measured; the quick tier
## is everything else, so a new module joins it until the summary says otherwise.
const QUICK_LIMIT_SEC := 10.0
const SLOW_MODULES := [
	"test_alldiff_position_release.gd",
	"test_beginner_mode_layouts_2026_10_01.gd",
	"test_cache_invariants.gd",
	"test_chain_hints.gd",
	"test_clue_has_hidden_content.gd",
	"test_clue_redundancy.gd",
	"test_clue_walk.gd",
	"test_correct_play_no_contradiction.gd",
	"test_early_stop_equivalence.gd",
	"test_easy_anchor_guarantees.gd",
	"test_firing_clue_not_decided_by_labels.gd",
	"test_firing_position.gd",
	"test_firing_relation.gd",
	"test_form_exhaustion.gd",
	"test_generation_frame_slicing.gd",
	"test_implied_hints.gd",
	"test_joint_hints.gd",
	"test_joint_name_note_proof.gd",
	"test_mus_explainer_speed.gd",
	"test_mutex_name_closure.gd",
	"test_mus_explanation_soundness.gd",
	"test_mutex_pitch_distinctness_degeneracy.gd",
	"test_name_hints.gd",
	"test_note_owner_proof.gd",
	"test_observable_identity.gd",
	"test_owner_hints.gd",
	"test_position_group_hints.gd",
	"test_prune_first_forms.gd",
	"test_prune_protects_anchors.gd",
	"test_pruning_is_gate_neutral.gd",
	"test_puzzle_rebuild_single_flight.gd",
	"test_repeat_clues_direct.gd",
	"test_repeat_count_matrix_encoding.gd",
	"test_repeat_note_gate.gd",
	"test_repeat_note_hints.gd",
	"test_solution_entry_covers_every_clue.gd",
	"test_sort_bottom_slot_scroll.gd",
	"test_value_column_identity.gd",
	"test_widget_path_independence.gd",
]
## The slow modules that exercise the board itself, added back for tier:board.
const BOARD_MODULES := [
	"test_correct_play_no_contradiction.gd",
	"test_solution_entry_covers_every_clue.gd",
	"test_widget_path_independence.gd",
]


func _init() -> void:
	var only: String = ""
	for a in OS.get_cmdline_user_args():
		only = str(a)   # optional filter: -- <substring>, or -- tier:<name>

	var modules: Array[String] = _discover()
	if only.begins_with("tier:"):
		modules = _in_tier(modules, only.trim_prefix("tier:"))
		if modules.is_empty():
			print("no such tier: %s (tier:quick, tier:board)" % only)
			quit(1)
			return
	elif only != "":
		var filtered: Array[String] = []
		for m in modules:
			if m.contains(only):
				filtered.append(m)
		modules = filtered

	print("running %d module(s) in ONE process\n" % modules.size())

	# root.get_children() is [] until one frame has passed — the autoloads
	# aren't attached yet. _run_one() snapshots root's children to know what
	# NOT to clean up, so without this the first module's snapshot was empty.
	# If that module awaited a frame (autoloads attach during it), its
	# cleanup then queue_free()d every autoload, leaving every later module
	# with no SaveManager/GameContext/etc. The unfiltered suite never hit it
	# only because probe_live_clues.gd, first alphabetically, never awaits;
	# `-- save` (intro-screen save gate first) did.
	await process_frame

	var results: Array[Dictionary] = []
	for path in modules:
		var started: int = Time.get_ticks_msec()
		var result: Dictionary = await _run_one(path)
		result["seconds"] = float(Time.get_ticks_msec() - started) / 1000.0
		results.append(result)

	print("\n" + "=".repeat(64))
	print("SUMMARY")
	print("=".repeat(64))
	var total_fails: int = 0
	var unknown: int = 0
	var total_seconds: float = 0.0
	var outgrown: Array[String] = []
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
		var seconds: float = float(r["seconds"])
		total_seconds += seconds
		if seconds > QUICK_LIMIT_SEC and not SLOW_MODULES.has(name):
			outgrown.append(name)
		print("  %-36s %-8s %7.1f s" % [name, status, seconds])
	print("=".repeat(64))
	print("TOTAL TIME: %.1f s (%.1f min)" % [total_seconds, total_seconds / 60.0])
	for name2 in outgrown:
		print("OUTGROWN THE QUICK TIER, add to SLOW_MODULES: %s" % name2)
	if total_fails == 0 and unknown == 0:
		print("ALL MODULES PASS")
	else:
		print("TOTAL FAILURES: %d%s" % [
			total_fails, ("   (%d module(s) unscored)" % unknown) if unknown > 0 else ""])
	quit(1 if total_fails > 0 else 0)


## `tier` is "quick" or "board"; anything else gives an empty list.
func _in_tier(modules: Array[String], tier: String) -> Array[String]:
	var out: Array[String] = []
	if tier != "quick" and tier != "board":
		return out
	for m in modules:
		var fname: String = m.get_file()
		if not SLOW_MODULES.has(fname) or (tier == "board" and BOARD_MODULES.has(fname)):
			out.append(m)
	return out


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
