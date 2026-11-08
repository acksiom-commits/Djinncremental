extends "res://dev_tests/test_base.gd"
# The Beginner Runes (author, 2026-11-01) are shapes made of a Sigil's real lines.
# Layouts get reshaped, so this holds each definition to the geometry it describes.
#
#  - Every Rune line is a real line of its layout, and no line is in two Runes.
#  - The Spark, The Hourglass, The Phial and The Satchel use every line they have.
#    The Archon's Rune is its outer triangle alone: the rest of its lines grow
#    inside it.
#  - Each Rune is the shape its name says.
#
# The Bellows has none.

const ARCHON: int = 1   # swapped with the Spark at v0.4.0
const SPARK: int = 0
const HOURGLASS: int = 2
const PHIAL: int = 4
const SATCHEL: int = 5
# How far a star may sit from the exact half-turn of its partner, as a share of
# the shape's width: these are hand-drawn outlines, not ruled ones.
const TURN_TOLERANCE: float = 0.12

var fails: int = 0


func ok(c: bool, s: String) -> void:
	if c:
		print("  PASS  ", s)
	else:
		print("  FAIL  ", s)
		fails += 1


func _layout(cd, cid: int) -> Dictionary:
	for c in cd.BUILT_IN:
		if int(c["id"]) == cid:
			return c["easy_layout"]
	return {}


func _vessel_layout(cd, key: String) -> Dictionary:
	for c in cd.BUILT_IN:
		if c.has("vessel_layouts"):
			return c["vessel_layouts"][key]["easy_layout"]
	return {}


## One closed loop: leaving out `spur`, every star holds exactly two lines and all
## of them can be walked from the first.
func _is_closed(flat: Array, spur: Array) -> bool:
	var links: Dictionary = {}
	for i in range(0, flat.size(), 2):
		var a: int = int(flat[i])
		var b: int = int(flat[i + 1])
		if spur.has(_key(a, b)):
			continue
		(links.get_or_add(a, []) as Array).append(b)
		(links.get_or_add(b, []) as Array).append(a)
	for s in links:
		if (links[s] as Array).size() != 2:
			return false
	var start: int = links.keys()[0]
	var seen: Dictionary = {start: true}
	var at: int = start
	var before: int = -1
	while true:
		var next: int = int(links[at][0]) if int(links[at][0]) != before else int(links[at][1])
		if next == start:
			break
		seen[next] = true
		before = at
		at = next
	return seen.size() == links.size()


## "" when the Rune's "hex" fit is sound, else what is wrong: every star of its
## lines placed on a real cell, no two in one cell, and no star lying on another
## of its lines (that hid a line under another in the first Ring fit).
func _hex_problem(rune: Dictionary) -> String:
	var hex: Dictionary = rune.get("hex", {})
	var flat: Array = rune["lines"]
	var cells: Dictionary = {}
	for s in flat:
		if not hex.has(int(s)):
			return "star %d has no cell" % int(s)
		var at: Array = hex[int(s)]
		if posmod(int(at[0]) - int(at[1]), 2) != 0:
			return "star %d is off the grid %s" % [int(s), str(at)]
		cells[str(at)] = int(s)
	if cells.size() != _used(flat).size():
		return "two stars share a cell"
	for i in range(0, flat.size(), 2):
		var a := _hex_point(hex[int(flat[i])])
		var b := _hex_point(hex[int(flat[i + 1])])
		for s2 in _used(flat):
			if int(s2) == int(flat[i]) or int(s2) == int(flat[i + 1]):
				continue
			var p := _hex_point(hex[int(s2)])
			var on: Vector2 = Geometry2D.get_closest_point_to_segment(p, a, b)
			if p.distance_to(on) < 0.05:
				return "star %d sits on line %d-%d" % [int(s2), int(flat[i]), int(flat[i + 1])]
	return ""


func _used(flat: Array) -> Array:
	var out: Array = []
	for s in flat:
		if not out.has(int(s)):
			out.append(int(s))
	return out


func _hex_point(at: Array) -> Vector2:
	return Vector2(float(at[0]) * sqrt(3.0) * 0.5, float(at[1]) * 1.5)


func _mean_y(layout: Dictionary, flat: Array) -> float:
	var total: float = 0.0
	for s in flat:
		total += _point(layout, int(s)).y
	return total / float(flat.size())


func _key(a: int, b: int) -> String:
	return "%d-%d" % [mini(a, b), maxi(a, b)]


func _line_keys(flat: Array) -> Array:
	var out: Array = []
	for i in range(0, flat.size(), 2):
		out.append(_key(int(flat[i]), int(flat[i + 1])))
	return out


func _point(layout: Dictionary, star: int) -> Vector2:
	var p: Array = layout["fixed_star_positions"][star]
	return Vector2(float(p[0]), float(p[1]))


func _rune_lines(layout: Dictionary, index: int) -> Array:
	return layout["runes"][index]["lines"]


## Every line of `cid`'s Runes is real and used once. Returns how many there are.
func _check_lines(layout: Dictionary, tag: String) -> int:
	var real: Array = _line_keys(layout["line_pairs"])
	var seen: Dictionary = {}
	var bad: Array = []
	var repeats: int = 0
	for r in layout["runes"]:
		for k in _line_keys(r["lines"]):
			if not real.has(k):
				bad.append(k)
			if seen.has(k):
				repeats += 1
			seen[k] = true
	ok(bad.is_empty(), "%s: all %d Rune lines are real lines %s" % [tag, seen.size(), str(bad)])
	ok(repeats == 0, "%s: no line is in two Runes" % tag)
	return seen.size()


func run() -> void:
	await process_frame
	var cd = load("res://constellation_data.gd").new()

	print("=== The Archon: one downward triangle ===")
	var archon: Dictionary = _layout(cd, ARCHON)
	ok((archon["runes"] as Array).size() == 1, "one Rune")
	_check_lines(archon, "Archon")
	var tri: Array = _rune_lines(archon, 0)
	ok(_line_keys(tri).size() == 3 and _point(archon, 2).y > _point(archon, 0).y and _point(archon, 2).y > _point(archon, 1).y,
		"three lines, with its apex below the other two")

	print("\n=== The Spark: two arrows facing opposite ways ===")
	var spark: Dictionary = _layout(cd, SPARK)
	ok(_check_lines(spark, "Spark") == (spark["line_pairs"] as Array).size() / 2, "every line is in a Rune")
	var hub: Vector2 = _point(spark, 0)
	var facing: Array = []
	for r in 2:
		var lines: Array = _rune_lines(spark, r)
		var shaft: Vector2 = Vector2.ZERO
		var behind: int = 0
		for i in range(1, lines.size(), 2):
			var off: Vector2 = _point(spark, int(lines[i])) - hub
			if off.length() > shaft.length():
				shaft = off
		for i2 in range(1, lines.size(), 2):
			if (_point(spark, int(lines[i2])) - hub).dot(shaft) > 0.0:
				behind += 1
		ok(behind == 3, "arrow %d: shaft and both barbs trail back from the hub (%d of 3)" % [r, behind])
		facing.append(-shaft)
	ok(facing[0].x > 0.0 and facing[1].x < 0.0, "the first faces right, the second left")

	print("\n=== The Hourglass: two sideways question marks ===")
	var glass: Dictionary = _layout(cd, HOURGLASS)
	ok(_check_lines(glass, "Hourglass") == (glass["line_pairs"] as Array).size() / 2, "every line is in a Rune")
	for r2 in 2:
		var path: Array = _rune_lines(glass, r2)
		var joined: bool = true
		for i3 in range(1, path.size() - 1, 2):
			if int(path[i3]) != int(path[i3 + 1]):
				joined = false
		ok(joined and path.size() == 8, "Rune %d is one unbroken path of four lines" % r2)
	# Stars 2-3 and 4-5 are the neck's two parallel lines. Each path starts at the
	# far end of one, away from its bulb, and stops at the near end of the other.
	var q0: Array = _rune_lines(glass, 0)
	var q1: Array = _rune_lines(glass, 1)
	ok(int(q0[0]) == 3 and int(q0[1]) == 2 and int(q0[q0.size() - 1]) == 4,
		"the first runs from the upper line's far end to the lower line's near end")
	ok(int(q1[0]) == 4 and int(q1[1]) == 5 and int(q1[q1.size() - 1]) == 3,
		"the second runs from the lower line's far end to the upper line's near end")
	var turned: bool = true
	for i4 in q0.size():
		var a: Vector2 = _point(glass, int(q0[i4]))
		var b: Vector2 = _point(glass, int(q1[i4]))
		if (a + b).length() > 0.26 * TURN_TOLERANCE:
			turned = false
	ok(turned, "each is the other turned half way round, star for star")

	print("\n=== The Satchel: a rectangle and an elongated M ===")
	var satchel: Dictionary = _layout(cd, SATCHEL)
	ok(_check_lines(satchel, "Satchel") == (satchel["line_pairs"] as Array).size() / 2, "every line is in a Rune")
	var box: Array = _rune_lines(satchel, 0)
	ok(_line_keys(box).size() == 4 and int(box[0]) == int(box[box.size() - 1]), "the Rectangle is one closed loop of four lines")
	var strap: Array = _rune_lines(satchel, 1)
	ok(_line_keys(strap).size() == 4 and int(strap[0]) == 0 and int(strap[strap.size() - 1]) == 1,
		"the M runs from one top corner of the box to the other")
	var peak_a: Vector2 = _point(satchel, 4)
	var dip: Vector2 = _point(satchel, 5)
	var peak_b: Vector2 = _point(satchel, 6)
	ok(peak_a.y < dip.y and peak_b.y < dip.y and dip.y < _point(satchel, 0).y,
		"two peaks with a dip between them, all above the box")

	print("\n=== The Vessels: an upper and a lower closed polygon ===")
	# "shared" is the one line both halves need to close, and "spur" a loose line
	# that stays on the upper Rune outside its polygon.
	for spec in [{"key": "ring", "shared": 0, "spur": []}, {"key": "jar", "shared": 1, "spur": []},
			{"key": "lamp", "shared": 1, "spur": ["0-1"]}]:
		var vessel: Dictionary = _vessel_layout(cd, str(spec["key"]))
		var tag: String = str(spec["key"]).capitalize()
		var real: Array = _line_keys(vessel["line_pairs"])
		var counts: Dictionary = {}
		var all_real: bool = true
		for rv in vessel["runes"]:
			for k in _line_keys(rv["lines"]):
				counts[k] = int(counts.get(k, 0)) + 1
				if not real.has(k):
					all_real = false
		var shared: int = 0
		for k2 in counts:
			if int(counts[k2]) > 1:
				shared += 1
		ok((vessel["runes"] as Array).size() == 2 and all_real, "%s: two Runes of real lines" % tag)
		ok(counts.size() == real.size(), "%s: every line is in a Rune (%d of %d)" % [tag, counts.size(), real.size()])
		ok(shared == int(spec["shared"]), "%s: %d line shared between them" % [tag, shared])
		ok(_is_closed(_rune_lines(vessel, 0), spec["spur"]) and _is_closed(_rune_lines(vessel, 1), []),
			"%s: both are closed polygons" % tag)
		ok(_mean_y(vessel, _rune_lines(vessel, 0)) < _mean_y(vessel, _rune_lines(vessel, 1)), "%s: the first sits above the second" % tag)
	var ring: Dictionary = _vessel_layout(cd, "ring")
	var left: float = _point(ring, 3).y
	var right: float = _point(ring, 5).y
	ok(_point(ring, 4).y > maxf(left, right) + 0.015, "the Ring's centre star sits below both its ends, so its lines angle down")
	ok(_point(ring, 4).y < _point(ring, 6).y, "and still above the lower arc")

	print("\n=== The Phial: a spiked less-than and an angular C ===")
	var phial: Dictionary = _layout(cd, PHIAL)
	ok(_check_lines(phial, "Phial") == (phial["line_pairs"] as Array).size() / 2, "every line is in a Rune")
	var point: Vector2 = _point(phial, 1)
	ok(_point(phial, 2).x > point.x and _point(phial, 3).x > point.x and _point(phial, 2).y < point.y and _point(phial, 3).y > point.y,
		"the less-than opens right from its point")
	ok(_point(phial, 0).x < point.x, "and the spike sticks out of that point")
	ok(_point(phial, 4).x > _point(phial, 2).x and _point(phial, 5).x > _point(phial, 3).x,
		"the C's back is on the right, so it opens left, toward the less-than")

	print("\n=== every Rune's hex fit is on the grid and shows every line ===")
	var runes: Array = []
	for c in cd.BUILT_IN:
		if c.has("easy_layout") and (c["easy_layout"] as Dictionary).has("runes"):
			runes.append_array(c["easy_layout"]["runes"])
		if c.has("vessel_layouts"):
			for key in c["vessel_layouts"]:
				runes.append_array(c["vessel_layouts"][key]["easy_layout"].get("runes", []))
	var judged: int = 0
	for rh in runes:
		judged += 1
		var problem: String = _hex_problem(rh)
		ok(problem == "", "%s: %s" % [str(rh["name"]), "fits" if problem == "" else problem])
	ok(judged == 15, "all 15 Runes judged (%d)" % judged)

	cd.free()
	if fails == 0:
		print("\nALL PASS (0 failures)")
	else:
		print("\nFAILURES (%d failures)" % fails)
	finish()
