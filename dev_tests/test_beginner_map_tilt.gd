extends "res://dev_tests/test_base.gd"
# Beginner constellations sit the way up they were drawn, tilted a little
# (author, 2026-11-01). They used to take any angle the sky's seeded roll gave:
# the stars named to level them were Hard's, and mostly not on these layouts.
#
#  - Every Beginner layout is within 5-15 degrees of its authored pose, either
#    way, never level and never upside-down.
#  - The tilt belongs to the save: it differs between saves and survives one.
#  - Hard keeps its own leveling.
#  - The Spark's four short spokes lie near its long line, and each pair above
#    and below it opens wide.

const IDS := [0, 1, 2, 3, 4, 5, 6]
const SEEDS := [1, 7, 11, 42, 1234, 99999]

var fails: int = 0


func ok(c: bool, s: String) -> void:
	if c:
		print("  PASS  ", s)
	else:
		print("  FAIL  ", s)
		fails += 1


## How far the map's view sits from the drawing, in degrees: the angle of the
## star pair farthest apart, on the map, less the same pair as authored.
func _tilt_seen(cd, cid: int) -> float:
	var basis: Basis = cd.get_canonical_display_basis(cid)
	var pos: Array = cd.get_star_positions(cid)
	var drawn: Array = cd.get_constellation_def(cid)["fixed_star_positions"]
	var a: int = 0
	var b: int = 1
	var best: float = -1.0
	for i in pos.size():
		for j in range(i + 1, pos.size()):
			var d: float = (pos[i] as Vector3).distance_to(pos[j] as Vector3)
			if d > best:
				best = d
				a = i
				b = j
	var va: Vector3 = basis.inverse() * (pos[a] as Vector3)
	var vb: Vector3 = basis.inverse() * (pos[b] as Vector3)
	var seen: float = atan2(vb.y - va.y, vb.x - va.x)
	var authored: float = atan2(float(drawn[b][1]) - float(drawn[a][1]), float(drawn[b][0]) - float(drawn[a][0]))
	return rad_to_deg(wrapf(authored - seen, -PI, PI))


func run() -> void:
	await process_frame
	var cd = load("res://constellation_data.gd").new()
	var gc = load("res://game_context.gd").new()
	cd._game_context = gc
	gc.chosen_vessel = "lamp"
	for cid in IDS:
		gc.constellation_difficulty[cid] = "easy"

	print("=== each layout is near its authored pose, on any sky ===")
	var judged: int = 0
	var in_range: int = 0
	var negative: int = 0
	var low: float = INF
	var high: float = 0.0
	for s in SEEDS:
		for player in [0, 5]:
			cd.player_seed = player
			cd.sky_tilt_seed = s
			cd._star_positions_cache.clear()
			for cid in IDS:
				var t: float = _tilt_seen(cd, cid)
				judged += 1
				low = minf(low, absf(t))
				high = maxf(high, absf(t))
				if t < 0.0:
					negative += 1
				if absf(t) >= 4.9 and absf(t) <= 15.1:
					in_range += 1
	ok(judged == IDS.size() * SEEDS.size() * 2, "%d placements judged" % judged)
	ok(in_range == judged, "%d of %d within 5-15 degrees (seen %.1f to %.1f)" % [in_range, judged, low, high])
	ok(negative > 0 and negative < judged, "it tilts both ways (%d of %d one way)" % [negative, judged])

	print("\n=== the tilt belongs to the save ===")
	cd.sky_tilt_seed = 11
	var first: float = _tilt_seen(cd, 1)
	cd.sky_tilt_seed = 42
	ok(not is_equal_approx(_tilt_seen(cd, 1), first), "another save tilts differently")
	cd.sky_tilt_seed = 11
	ok(is_equal_approx(_tilt_seen(cd, 1), first), "the same save tilts the same")
	var saved: Dictionary = cd.get_save_data()
	cd.sky_tilt_seed = 42
	cd.load_save_data(saved)
	ok(cd.sky_tilt_seed == 11, "and it comes back from a save")

	print("\n=== The Spark's shape ===")
	var spark: Array = cd.get_constellation_def(cd.FIRST_ID)["fixed_star_positions"]   # the Spark is id 0 since v0.4.0
	var hub := Vector2(spark[0][0], spark[0][1])
	var angles: Dictionary = {}
	for tip in [3, 4, 5, 6]:
		var off: Vector2 = Vector2(spark[tip][0], spark[tip][1]) - hub
		angles[tip] = rad_to_deg(atan2(absf(off.y), absf(off.x)))
		ok(angles[tip] >= 22.0 and angles[tip] <= 32.0, "spoke %d is %.1f degrees off the long line" % [tip, angles[tip]])
	ok(180.0 - angles[3] - angles[4] > 110.0, "the pair above opens to %.0f degrees" % (180.0 - angles[3] - angles[4]))
	ok(180.0 - angles[5] - angles[6] > 110.0, "the pair below opens to %.0f degrees" % (180.0 - angles[5] - angles[6]))

	print("\n=== The Hourglass has a neck ===")
	var glass: Array = cd.get_constellation_def(2)["fixed_star_positions"]
	var neck: float = float(glass[4][1]) - float(glass[2][1])
	var bulb: float = float(glass[1][1]) - float(glass[0][1])
	ok(bulb >= neck * 4.0, "its ends stand at least 4x its neck (%.3f vs %.3f)" % [bulb, neck])

	print("\n=== Hard keeps its own leveling ===")
	gc.constellation_difficulty[cd.FIRST_ID] = "hard"
	cd._star_positions_cache.clear()
	var hard: Dictionary = cd.get_constellation_def(cd.FIRST_ID)
	ok(not hard.has("authored_upright"), "Hard is not marked for the Beginner pose")
	var basis: Basis = cd.get_canonical_display_basis(cd.FIRST_ID)
	var pos: Array = cd.get_star_positions(cd.FIRST_ID)
	var a0: Vector3 = basis.inverse() * (pos[0] as Vector3)
	var a8: Vector3 = basis.inverse() * (pos[8] as Vector3)
	ok(absf(a0.y - a8.y) < 0.0005, "The Spark's Hard spine still lies level (drop %.5f)" % absf(a0.y - a8.y))

	gc.free()
	cd.free()
	if fails == 0:
		print("\nALL PASS (0 failures)")
	else:
		print("\nFAILURES (%d failures)" % fails)
	finish()
