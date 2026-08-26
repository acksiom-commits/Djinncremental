extends "res://dev_tests/test_base.gd"
# The contradiction detector.
#
# Built after a real save sat in a provably impossible state for a whole
# session with nothing flagging it: a pitch elimination on a record whose
# star genuinely carries that pitch emptied its candidate set outright.
#
# Two things matter equally here — that it FIRES on impossible states, and
# that it stays SILENT on merely-unsolved ones. A detector that cries wolf
# on a half-filled board is worse than none.

const OverlayScene = preload("res://ConstellationStudyOverlay.tscn")

var fails: int = 0
func ok(c: bool, s: String) -> void:
	if c: print("  PASS  ", s)
	else: print("  FAIL  ", s); fails += 1


func run() -> void:
	var host = OverlayScene.instantiate()
	root.add_child(host)
	await process_frame
	host._constellation_id = 0
	host._star_count = 5
	host._star_names = ["Keriion", "Selion", "Pyrios", "Helios", "Nyxeai"]
	host._star_colors = [0, 0, 1, 2, 3]
	host._star_degrees = [2, 2, 3, 1, 2]
	host._pitch_freqs = [440.0, 493.88, 523.25, 554.37, 587.33]
	host._star_pitch_index = [0, 1, 2, 3, 4]
	host._sequence_rank_solution = [0, 1, 2, 3, 4]
	var d = host._deduction
	host._widgets.clear_pitch_caches()

	print("\n=== silent on an untouched board ===")
	d._load_match_records([])
	for nm in host._star_names:
		d._get_or_create_match_record_for_name(nm)
	d._full_propagation_refresh()
	ok(d._contradictions.is_empty(),
		"no warning on a blank board (%d raised)" % d._contradictions.size())

	print("\n=== silent on a partially-solved board ===")
	var k: int = d._find_match_record_by_name("Keriion")
	d._match_records[k]["color_states"] = {2: 2, 3: 2}
	d._match_records[k]["seq_lo"] = 1
	d._match_records[k]["seq_hi"] = 1
	d._full_propagation_refresh()
	ok(d._contradictions.is_empty(),
		"no warning on real partial progress (%d raised)" % d._contradictions.size())

	print("\n=== fires when every star is ruled out ===")
	d._load_match_records([])
	var p: int = d._get_or_create_match_record_for_name("Pyrios")
	# Every colour eliminated => no star can carry it.
	d._match_records[p]["color_states"] = {0: 2, 1: 2, 2: 2, 3: 2}
	d._full_propagation_refresh()
	ok(d._contradictions.size() >= 1, "raised (%d)" % d._contradictions.size())
	var texts: String = ""
	for c in d._contradictions:
		texts += str((c as Dictionary).get("text", "")) + " | "
	print("      %s" % texts)
	ok(texts.contains("Pyrios"), "names the offending record")
	ok(not texts.contains("star 2") and not texts.contains("White"),
		"leaks no ground truth about the right answer")

	print("\n=== clears when the bad mark is withdrawn ===")
	p = d._find_match_record_by_name("Pyrios")
	d._match_records[p]["color_states"] = {}
	d._full_propagation_refresh()
	ok(d._contradictions.is_empty(),
		"warning gone once the cause is removed (%d left)" % d._contradictions.size())

	print("\n=== the real-save shape: pitch X on the record's own note ===")
	# The shape that actually shipped: colour confirmed (others eliminated)
	# AND the record's true note ruled out, leaving no star at all.
	#
	# The confirmed colour must cover MORE THAN ONE star. With a unique
	# colour the record identifies a star outright, merges into that star's
	# record, and ground truth then overrides the bad pitch mark — the
	# contradiction is absorbed rather than reported. See the note at the
	# end of this file; the real save avoided that because its confirmed
	# colour had several stars.
	host._star_count = 6
	host._star_names = ["Keriion", "Selion", "Pyrios", "Helios", "Eos", "Zeta"]
	host._star_colors = [0, 0, 1, 1, 2, 2]
	host._star_degrees = [2, 2, 3, 1, 2, 3]
	host._pitch_freqs = [440.0, 493.88, 523.25, 554.37, 587.33, 622.25]
	host._star_pitch_index = [0, 1, 2, 3, 4, 5]
	host._sequence_rank_solution = [0, 1, 2, 3, 4, 5]
	host._widgets.clear_pitch_caches()
	d._load_match_records([])
	for s in host._star_count:
		d._get_or_create_match_record_for_star_idx(s)
	var h: int = d._get_or_create_match_record_for_name("Helios")
	# The pitch filter only applies to stars the player has LISTENED to, so
	# the star records must be marked revealed — the state the real save
	# was in.
	for i in d._match_records.size():
		if int(d._match_records[i].get("star_idx", -1)) >= 0:
			d._match_records[i]["pitch_revealed"] = true
	# Colour 2 confirmed, others eliminated — confirming alone narrows
	# nothing, since candidates are rejected on elimination.
	d._match_records[h]["color_states"] = {0: 2, 1: 2, 2: 1, 3: 2}
	# Both colour-2 stars' notes ruled out => no star can be this record.
	d._match_records[h]["pitch_states"] = {
		host._widgets._note_name_for_star(4): 2,
		host._widgets._note_name_for_star(5): 2,
	}
	d._full_propagation_refresh()
	ok(d._contradictions.size() >= 1,
		"impossible pitch+colour combination caught (%d)" % d._contradictions.size())
	for c in d._contradictions:
		print("      %s" % str((c as Dictionary).get("text", "")))

	print("\n=== two records on one star ===")
	d._load_match_records([])
	var a: int = d._get_or_create_match_record_for_name("Selion")
	var b: int = d._get_or_create_match_record_for_name("Nyxeai")
	d._match_records[a]["star_idx"] = 1
	d._match_records[b]["star_idx"] = 1
	d._full_propagation_refresh()
	var dup := false
	for c in d._contradictions:
		if str((c as Dictionary).get("axis", "")) == "identity":
			dup = true
			print("      %s" % str((c as Dictionary).get("text", "")))
	ok(dup, "duplicate star binding reported")

	print("\n=== nothing is persisted ===")
	var saved: Array = d._save_match_records()
	var leaked := false
	for e in saved:
		if (e as Dictionary).has("contradictions"):
			leaked = true
	ok(not leaked, "contradictions never reach the save file")

	print("\n%s (%d failures)" % ["ALL PASS" if fails == 0 else "FAILURES", fails])
	finish()
	quit()
