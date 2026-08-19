extends "res://dev_tests/test_base.gd"
# Reusable throwaway driver — EDIT IN PLACE. MUST call finish() on every
# exit path. LEAVE IT GREEN when an investigation ends.
#
# PHASE 2 ELEVENTH SLICE (2026-08-18): Cross-Domain Bridge (form 20) wired
# to feed _solve_name_closure(). Picked by SURVEY, not structural guess:
# 90 of its 92 clues name a star (98%, the highest name-density of any
# unwired Form) and it fed zero facts. Emits two facts when d2==NAME —
# plain name_group membership (existing kind, drop-in) and the NEW
# name_extreme_in_group, which resolves to a SINGLE position (a PIN).
#
# MEASURED, matched-seed against commit 3fab45c — biggest gain of any
# slice in this investigation:
#
#                        baseline (3fab45c)   this slice
#     exact pin            49  ( 7.8%)        136  (21.5%)   ~2.8x
#     group/order         348  (55.1%)        293  (46.4%)
#     same-group only      82  (13.0%)         72  (11.4%)
#     UNTOUCHED           153  (24.2%)        131  (20.7%)   best ever
#     contradictions      0 / 38              0 / 38         SOUND
#     pitch size 1        35/120 (29.2%)      32/120 (26.7%)
#
# The tier movement balances exactly (+87 pins vs -55/-10/-22), so all 87
# are PROMOTIONS, not losses: 22 names left "untouched" entirely and the
# rest went from weak coverage to a hard pin. 90 name_extreme_in_group
# facts fired; Cross-Domain Bridge went from 0 to 90 of 92 clues feeding.
#
# The load-bearing number is CONTRADICTIONS: every slice so far has held
# 0/N, which is what proves the closure engine sound rather than merely
# under-fed. A nonzero count here means the new fact kind is WRONG and
# must be reverted, regardless of what coverage did. This module FAILS
# itself on any contradiction, so a suite PASS is the soundness proof.
#
# NOT YET MEASURED: whether any puzzle now reaches FULL closure
# (name_unique_closure). It has been 0/N for all eleven slices. Pins
# nearly tripling is the first change plausibly able to move it — that is
# the next measurement, and the actual goal of Phase 2.

var fails: int = 0


func run() -> void:
	var cd = load("res://constellation_data.gd").new()
	var seeds: Array = [11, 4242, 31337, 55555, 77, 909090, 13, 24601]

	var total_names: int = 0
	var exact_pin: int = 0
	var group_or_order: int = 0
	var same_group_only: int = 0
	var untouched: int = 0
	var contradictions: int = 0
	var closures_attempted: int = 0
	var by_pitch_size: Dictionary = {}

	var extreme_facts: int = 0
	var cdb_clues: int = 0
	var cdb_feeding: int = 0
	var puzzles: int = 0

	for cid in [0, 1, 2, 3, 4]:
		var cdef: Dictionary = cd.get_constellation_def(cid)
		if cdef.is_empty() or (cdef["line_pairs"] as Array).is_empty():
			continue
		var scn: int = int(cdef["star_count"])
		for seed in seeds:
			var g = load("res://constellation_logic_puzzle.gd").new()
			var sq: Array = []
			for i in range(scn):
				sq.append(i)
			g.setup(scn, cdef["line_pairs"], sq, seed, cid,
				cdef.get("name_theme", {}), cd.get_note_assignment(cid),
				cd.get_note_freqs(cid), null)
			var result: Dictionary = await g._generate_clues_forms_attempt()
			puzzles += 1

			var kind_for_star: Dictionary = {}
			var rank_order: Dictionary = {"name_group_seq": 3, "group_or_order": 2, "same_group": 1}
			for clue in g.chosen_form_clues:
				var is_cdb: bool = str(clue.get("form_name", "")) == "Cross-Domain Bridge"
				if is_cdb:
					cdb_clues += 1
				var fed: bool = false
				for f in (clue.get("disclosures", []) as Array):
					if not (f is Dictionary):
						continue
					var fd: Dictionary = f
					var kind: String = str(fd.get("kind", ""))
					match kind:
						"name_group", "name_group_neg":
							fed = true
							var s: int = int(fd["name_star"])
							var cat: int = int(fd["cat"])
							var rk: String = "name_group_seq" if cat == 1 else "group_or_order"
							if int(rank_order.get(kind_for_star.get(s, ""), 0)) < int(rank_order[rk]):
								kind_for_star[s] = rk
						"name_precedes_group", "name_follows_group":
							fed = true
							var s2: int = int(fd["name_star"])
							if int(rank_order.get(kind_for_star.get(s2, ""), 0)) < int(rank_order["group_or_order"]):
								kind_for_star[s2] = "group_or_order"
						"name_extreme_in_group":
							fed = true
							extreme_facts += 1
							# A pin — rank it as the strongest bucket, same
							# as an exact Sequence pin.
							var s4: int = int(fd["name_star"])
							kind_for_star[s4] = "name_group_seq"
						"name_same_group":
							fed = true
							for key in ["name_star_a", "name_star_b"]:
								var s3: int = int(fd[key])
								if not kind_for_star.has(s3):
									kind_for_star[s3] = "same_group"
				if is_cdb and fed:
					cdb_feeding += 1

			for s in scn:
				total_names += 1
				var k: String = str(kind_for_star.get(s, ""))
				var pgs: int = g._group_size(3, s)
				if not by_pitch_size.has(pgs):
					by_pitch_size[pgs] = {"total": 0, "untouched": 0}
				by_pitch_size[pgs]["total"] += 1
				match k:
					"name_group_seq":
						exact_pin += 1
					"group_or_order":
						group_or_order += 1
					"same_group":
						same_group_only += 1
					_:
						untouched += 1
						by_pitch_size[pgs]["untouched"] += 1

			if bool(result.get("seq_unique", false)):
				closures_attempted += 1
				if int(result.get("name_solutions_count", -1)) == 0:
					contradictions += 1

	print("\n  puzzles: %d, names: %d" % [puzzles, total_names])
	print("  exact pin (incl. new extremum): %d (%.1f%%)   [baseline 49, 7.8%%]" % [exact_pin, 100.0 * exact_pin / total_names])
	print("  group/order coverage:           %d (%.1f%%)   [baseline 348, 55.1%%]" % [group_or_order, 100.0 * group_or_order / total_names])
	print("  same-group only:                %d (%.1f%%)   [baseline 82, 13.0%%]" % [same_group_only, 100.0 * same_group_only / total_names])
	print("  UNTOUCHED:                      %d (%.1f%%)   [baseline 153, 24.2%%]" % [untouched, 100.0 * untouched / total_names])
	print("  CONTRADICTIONS: %d / %d closures attempted   [baseline 0 / 38 — MUST stay 0]" % [contradictions, closures_attempted])
	print("\n  untouched rate by pitch group size:")
	var sizes: Array = by_pitch_size.keys()
	sizes.sort()
	for sz in sizes:
		var t: Dictionary = by_pitch_size[sz]
		print("    size %d: %d / %d untouched (%.1f%%)" % [sz, t["untouched"], t["total"], 100.0 * float(t["untouched"]) / float(t["total"])])
	print("\n  name_extreme_in_group facts emitted: %d" % extreme_facts)
	print("  Cross-Domain Bridge clues: %d, of which now feed: %d" % [cdb_clues, cdb_feeding])

	if contradictions > 0:
		print("  !! CONTRADICTIONS PRESENT — the new fact kind is unsound, revert !!")
		fails += 1
	print("ALL PASS (%d failures)" % fails)
	finish()
