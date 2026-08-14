extends "res://dev_tests/test_base.gd"
# PHASE 0: nothing outside the deduction engine indexes _match_records.
#
# GDScript has no access control — a leading underscore is a convention a
# compiler never checks. So the boundary is only real if something fails
# when it is crossed, and this is that something.
#
# It matters because Phase 3 needs derived identity, which needs records to
# ALIAS one another rather than be destructively merged. An alias can only
# work if every "which record is at index i" question goes through one
# function that can redirect it. One direct `_deduction._match_records[i]`
# anywhere outside silently bypasses that and reintroduces the bug class.

var fails: int = 0
func ok(c: bool, s: String) -> void:
	if c: print("  PASS  ", s)
	else: print("  FAIL  ", s); fails += 1


const OWNER := "constellation_puzzle_deduction.gd"

## Harnesses are allowed to reach in — poking internals is their job, and
## they are copied into the project root only while running. Only shipped
## game code is held to the boundary.
const HARNESS_PREFIXES := ["test_", "probe_", "bench_", "audit_", "diag", "check_", "verify_"]


func run() -> void:
	print("=== no external file reaches into _match_records ===")
	var offenders: Array[String] = []
	var scanned: int = 0
	for path in _all_scripts("res://"):
		var fname: String = path.get_file()
		if fname == OWNER or _is_harness(fname):
			continue
		var src: String = FileAccess.get_file_as_string(path)
		if src == "":
			continue
		scanned += 1
		var lines: PackedStringArray = src.split("\n")
		for i in lines.size():
			var line: String = lines[i]
			if line.strip_edges().begins_with("#"):
				continue   # prose about the boundary is not a crossing
			# The FIELD, not methods that merely contain its name:
			# "._match_records" matches the array, while
			# "._merge_match_records" / "._load_match_records" do not,
			# since their "." is followed by merge_/load_. Those are the
			# engine's own public API and are meant to be called.
			if line.contains("._match_records"):
				offenders.append("%s:%d  %s" % [fname, i + 1, line.strip_edges()])
	print("   scanned %d shipped scripts" % scanned)
	for o in offenders:
		print("   -> " + o)
	ok(offenders.is_empty(), "%d external reference(s)" % offenders.size())

	print("\n=== the accessors exist and agree with the array ===")
	var d = load("res://" + OWNER).new()
	ok(d.has_method("record_count"), "record_count() exists")
	ok(d.has_method("record_at"), "record_at() exists")
	ok(d.record_count() == 0, "record_count() reads 0 on a fresh engine")

	print("\n%s (%d failures)" % ["ALL PASS" if fails == 0 else "FAILURES", fails])
	finish()
	quit()


func _is_harness(fname: String) -> bool:
	for p in HARNESS_PREFIXES:
		if fname.begins_with(p):
			return true
	return false


func _all_scripts(dir_path: String) -> Array[String]:
	var out: Array[String] = []
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return out
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if entry.begins_with("."):
			entry = dir.get_next()
			continue
		var full := dir_path.path_join(entry)
		if dir.current_is_dir():
			out.append_array(_all_scripts(full))
		elif entry.ends_with(".gd"):
			out.append(full)
		entry = dir.get_next()
	dir.list_dir_end()
	return out
